# AllTalk

A small macOS menu bar app for push-to-talk dictation and audio Q&A, powered by
a local **Voxtral-Mini-3B** model running in `llama-server`.

```
┌─────────────────────────────────────┐
│  AllTalk.app  (Swift, menu bar)     │
│  ├─ ⌃⌥Space hotkey (Carbon)         │
│  ├─ AVAudioRecorder → /tmp/*.wav    │
│  └─ exec: alltalk -f clip.wav …     │
└──────────────┬──────────────────────┘
               │ stdout, streamed
               ▼
┌─────────────────────────────────────┐
│  alltalk  (Go, ~250 LOC, stdlib)    │
│  └─ POST /v1/chat/completions       │
│       stream=true                   │
└──────────────┬──────────────────────┘
               │ SSE
               ▼
        llama-server :8080
        (Voxtral-Mini-3B GGUF)
```

## Setup

### 1. Run the model server

**Get `llama-server`** (it ships as part of llama.cpp):

```bash
brew install llama.cpp        # macOS / Linux
llama-server --version        # verify
```

Or grab a prebuilt binary (arch/backend-specific) or a Docker image from the
[llama.cpp releases](https://github.com/ggml-org/llama.cpp/releases).

**Get the model.** The GGUF repo has *two* files you need — the model **and** its
audio projector (`mmproj`). Without the projector, `llama-server` loads fine but
silently can't process audio (it'll look like AllTalk connects but returns nothing).

Easiest — let `llama-server` fetch both (~3.2 GB on first run):

```bash
llama-server -hf ggml-org/Voxtral-Mini-3B-2507-GGUF --port 8080
```

Or download the two files manually and point at them explicitly:

```bash
mkdir -p ~/models/voxtral && cd ~/models/voxtral
base=https://huggingface.co/ggml-org/Voxtral-Mini-3B-2507-GGUF/resolve/main
curl -L -O $base/Voxtral-Mini-3B-2507-Q4_K_M.gguf        # 2.47 GB — model
curl -L -O $base/mmproj-Voxtral-Mini-3B-2507-Q8_0.gguf   # 716 MB — audio projector

llama-server \
  -m       ~/models/voxtral/Voxtral-Mini-3B-2507-Q4_K_M.gguf \
  --mmproj ~/models/voxtral/mmproj-Voxtral-Mini-3B-2507-Q8_0.gguf \
  --port 8080
```

> **Not Ollama.** Ollama can't feed audio into a model yet (open requests
> [#12440](https://github.com/ollama/ollama/issues/12440),
> [#11432](https://github.com/ollama/ollama/issues/11432)) and its API doesn't
> accept the `input_audio` payload this app sends — so it can't run Voxtral for
> transcription. Use `llama-server`.

### 2. Build the Go CLI

```bash
cd cli
go build -o alltalk .
sudo install alltalk /usr/local/bin/
```

Stdlib only — no external deps.

Sanity check:
```bash
alltalk                              # record from mic, stream reply to stdout
alltalk -f some.wav -p "Summarise"   # use existing audio
```

### 3. Build the Swift app

```bash
open AllTalk.xcodeproj
```

Hit ⌘R. The app appears in the menu bar (look for the waveform icon — no Dock
icon by design).

First launch will prompt for **Microphone** permission. If you use *Paste at
Cursor* mode, also grant **Accessibility** in System Settings → Privacy &
Security so the app can synthesise ⌘V into the focused window.

## Usage

- **⌃⌥Space**: start/stop recording. Stop triggers transcription; the reply
  streams in.
- **Menu bar → Show Transcript…**: live popover with the streamed text.
- **Menu bar → Paste at Cursor / Show in Popover**: toggle output destination.
- **Menu bar → Settings…**: server URL, prompt, CLI path.

## Tweaks

- **Different hotkey**: edit `AppDelegate.swift` line referencing `kVK_Space` and
  `controlKey | optionKey`. Carbon key codes are in `Carbon.HIToolbox`.
- **Translation / Q&A**: change the prompt in Settings. Voxtral handles audio
  Q&A natively — e.g. `"Answer the question asked in this audio clip."`
- **Remote server**: point `serverURL` at a Tailscale host running
  `llama-server`. The Go CLI is a thin HTTP client, so latency = network +
  inference.

## Known limits

- `llama.cpp` Voxtral support is the original **3B (July 2025)** model, not the
  newer 4B Realtime variant. Realtime streaming audio in `llama.cpp` is still
  in planning (issue #20914). For now it's request/response: record, then
  transcribe.
- Carbon `RegisterEventHotKey` is "deprecated" but still the only public macOS
  API for system-wide hotkeys without Accessibility prompts. Apple has not
  shipped a replacement.
