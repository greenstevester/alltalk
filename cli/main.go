// alltalk - send audio to a local llama-server running Voxtral, stream reply to stdout.
//
// Designed to be called from a parent process (Swift app, shell script, etc.).
// Streams tokens as they arrive so the caller can render them live.
//
// Usage:
//
//	alltalk -f clip.wav                          # transcribe a file
//	alltalk -f clip.wav -p "Translate to French" # custom prompt
//	alltalk -f clip.wav -url http://host:8080    # remote server
//	alltalk                                       # interactive mic recording (sox/ffmpeg)
package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

type audioPart struct {
	Type       string     `json:"type"`
	InputAudio inputAudio `json:"input_audio"`
}

type inputAudio struct {
	Data   string `json:"data"`
	Format string `json:"format"`
}

type textPart struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

type message struct {
	Role    string `json:"role"`
	Content []any  `json:"content"`
}

type chatRequest struct {
	Messages    []message `json:"messages"`
	Stream      bool      `json:"stream"`
	Temperature float64   `json:"temperature,omitempty"`
}

type streamChunk struct {
	Choices []struct {
		Delta struct {
			Content string `json:"content"`
		} `json:"delta"`
		FinishReason string `json:"finish_reason"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

func main() {
	var (
		serverURL = flag.String("url", "http://localhost:8080", "llama-server base URL")
		prompt    = flag.String("p", "Transcribe this audio verbatim. Output only the transcript, no commentary.", "prompt sent alongside the audio")
		file      = flag.String("f", "", "audio file to send (skip mic recording)")
		keep      = flag.Bool("keep", false, "keep the temp recording on disk and print its path to stderr")
		timeout   = flag.Duration("timeout", 5*time.Minute, "HTTP timeout")
	)
	flag.Parse()

	if err := run(*serverURL, *prompt, *file, *keep, *timeout); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run(serverURL, prompt, file string, keep bool, timeout time.Duration) error {
	var (
		path string
		err  error
	)
	if file != "" {
		path = file
	} else {
		path, err = recordInteractive()
		if err != nil {
			return fmt.Errorf("recording: %w", err)
		}
		if !keep {
			defer os.Remove(path)
		} else {
			fmt.Fprintln(os.Stderr, "recording saved:", path)
		}
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read audio: %w", err)
	}
	if len(data) == 0 {
		return errors.New("audio file is empty")
	}

	format := strings.TrimPrefix(strings.ToLower(filepath.Ext(path)), ".")
	if format == "" {
		format = "wav"
	}

	return streamChat(serverURL, prompt, base64.StdEncoding.EncodeToString(data), format, timeout)
}

// streamChat POSTs to /v1/chat/completions with stream=true and writes each
// delta chunk to stdout as it arrives. Stdout is flushed after every chunk so
// a parent process reading line-by-line sees tokens in near-realtime.
func streamChat(serverURL, prompt, b64, format string, timeout time.Duration) error {
	body := chatRequest{
		Stream: true,
		Messages: []message{{
			Role: "user",
			Content: []any{
				audioPart{Type: "input_audio", InputAudio: inputAudio{Data: b64, Format: format}},
				textPart{Type: "text", Text: prompt},
			},
		}},
	}
	buf, err := json.Marshal(body)
	if err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, "POST",
		strings.TrimRight(serverURL, "/")+"/v1/chat/completions",
		bytes.NewReader(buf))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "text/event-stream")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("post: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode/100 != 2 {
		raw, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("server %d: %s", resp.StatusCode, strings.TrimSpace(string(raw)))
	}

	// Parse SSE: lines like `data: {...}\n` separated by blank lines.
	// Final marker: `data: [DONE]`.
	scanner := bufio.NewScanner(resp.Body)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()

	for scanner.Scan() {
		line := scanner.Bytes()
		if !bytes.HasPrefix(line, []byte("data: ")) {
			continue
		}
		payload := bytes.TrimPrefix(line, []byte("data: "))
		if bytes.Equal(payload, []byte("[DONE]")) {
			out.WriteByte('\n')
			return nil
		}
		var chunk streamChunk
		if err := json.Unmarshal(payload, &chunk); err != nil {
			continue // skip malformed chunks rather than aborting mid-stream
		}
		if chunk.Error != nil {
			return errors.New(chunk.Error.Message)
		}
		for _, c := range chunk.Choices {
			if c.Delta.Content == "" {
				continue
			}
			out.WriteString(c.Delta.Content)
			out.Flush() // critical: parent reads char-by-char
		}
	}
	if err := scanner.Err(); err != nil && !errors.Is(err, context.Canceled) {
		return fmt.Errorf("read stream: %w", err)
	}
	out.WriteByte('\n')
	return nil
}

// recordInteractive records from the default mic. Used only in standalone mode;
// the Swift app records natively via AVFoundation and passes the file via -f.
func recordInteractive() (string, error) {
	recorder, args, err := pickRecorder()
	if err != nil {
		return "", err
	}

	tmp, err := os.CreateTemp("", "alltalk-*.wav")
	if err != nil {
		return "", err
	}
	tmp.Close()
	args = append(args, tmp.Name())

	fmt.Fprint(os.Stderr, "press Enter to start recording… ")
	fmt.Scanln()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	cmd := exec.CommandContext(ctx, recorder, args...)
	cmd.Stderr = io.Discard
	if err := cmd.Start(); err != nil {
		return "", fmt.Errorf("start %s: %w", recorder, err)
	}
	fmt.Fprintln(os.Stderr, "● recording — press Enter to stop")

	done := make(chan struct{})
	go func() { fmt.Scanln(); close(done) }()
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	select {
	case <-done:
	case <-sig:
	}

	_ = cmd.Process.Signal(syscall.SIGINT)
	_ = cmd.Wait()
	fmt.Fprintln(os.Stderr, "■ stopped")
	return tmp.Name(), nil
}

func pickRecorder() (string, []string, error) {
	if p, err := exec.LookPath("sox"); err == nil {
		return p, []string{"-q", "-d", "-c", "1", "-r", "16000", "-b", "16"}, nil
	}
	if p, err := exec.LookPath("ffmpeg"); err == nil {
		return p, []string{"-hide_banner", "-loglevel", "error", "-f", "avfoundation", "-i", ":0", "-ac", "1", "-ar", "16000", "-y"}, nil
	}
	return "", nil, errors.New("need `sox` or `ffmpeg` on PATH (brew install sox)")
}
