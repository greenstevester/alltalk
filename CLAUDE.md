# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

AllTalk is a macOS menu-bar push-to-talk dictation app. Two cooperating processes plus an external model server:

- **`AllTalk/`** — Swift/SwiftUI menu-bar app. Records mic audio, spawns the Go CLI, renders the streamed reply.
- **`cli/`** — Go CLI (`alltalk`), stdlib only, ~250 LOC. A thin HTTP client that base64-encodes a WAV, POSTs it to `llama-server`, and streams the reply to stdout.
- **`llama-server`** (external, not in this repo) — runs the `Voxtral-Mini-3B` GGUF model, exposes an OpenAI-compatible `/v1/chat/completions` endpoint on `:8080`.

> Note: `Voxtral-Mini-3B` is the name of the upstream model (from `ggml-org`), not this project. The app/CLI are named **AllTalk**; the model name stays as-is wherever it appears.

The model server is a hard dependency for any end-to-end test. Start it with:
```bash
llama-server -hf ggml-org/Voxtral-Mini-3B-2507-GGUF --port 8080
```

## Build & run

**Go CLI** (no external deps):
```bash
cd cli
go build -o alltalk .
go vet ./...                            # lint
sudo install alltalk /usr/local/bin/    # where the Swift app expects it by default
alltalk -f some.wav -p "Summarise"      # run against a file
alltalk                                 # standalone: record via sox/ffmpeg, then transcribe
```

**Swift app:**
```bash
xcodebuild -project AllTalk.xcodeproj -scheme AllTalk -configuration Debug build
open AllTalk.xcodeproj   # or build/run with ⌘R in Xcode
```
Targets macOS 13+, Swift 5. Bundle id `com.greenstevester.alltalk`.

There is **no test target** in either component. If you add Go tests, `go test ./...` from `cli/`.

## Architecture: the streaming pipeline

The whole app is one streaming path. Understanding the contract between the three stages is the key to working here:

1. **Swift records** (`AllTalkController.startRecording`) → `AVAudioRecorder` writes 16 kHz / mono / 16-bit PCM WAV to a temp file. This format is deliberate — it's what the model expects, and matches the standalone CLI recorder args.
2. **Swift spawns the CLI** (`AllTalkController.runCLI`) → `Process` with `["-f", <wav>, "-url", serverURL, "-p", prompt]`. The CLI's stdout is read incrementally via a `readabilityHandler`; stderr is captured only for error reporting on non-zero exit.
3. **Go streams tokens** (`cli/main.go: streamChat`) → POSTs `stream=true`, parses the SSE response (`data: {...}` lines, terminated by `data: [DONE]`), and **flushes stdout after every content delta**. That flush is load-bearing: it's what lets the Swift parent see tokens in near-realtime instead of one batch at the end. Don't buffer it away.
4. **Swift consumes** (`AllTalkController.handleChunk`) → appends to `transcript` (shown in the popover) and, in *paste* mode, pastes each whitespace-delimited word as it arrives so dictation feels live.

The Swift↔Go contract is just argv + stdout text. The CLI has no knowledge of the app; it's independently usable from a shell. Keep it that way.

## Two output modes

`OutputMode` (`.paste` / `.popover`), persisted to `UserDefaults`:
- **paste** — synthesises ⌘V into the frontmost app via `Clipboard.paste` (CGEvent). Requires **Accessibility** permission.
- **popover** — accumulates into the transcript view; fires a notification when done.

## State management

`AllTalkController` (`@MainActor`, `ObservableObject`) is the single source of truth. All `@Published` settings mirror to `UserDefaults` in their `didSet`. UI is driven two ways:
- SwiftUI views (`PopoverView`, `SettingsView`) observe it via `@EnvironmentObject`.
- The AppKit `NSMenu` is **rebuilt imperatively** on every change via the `onStateChange` callback (`AppDelegate.rebuildMenu`) — SwiftUI doesn't own the menu bar item, so it can't auto-update it. If you add controller state that the menu shows, you must trigger `onStateChange?()`.

## macOS-specific constraints (read before "fixing" them)

These look like smells but are intentional:

- **App Sandbox is OFF** (`AllTalk.entitlements`). Required: spawning a child process and posting synthetic CGEvents are both incompatible with the sandbox. Do not re-enable it without rearchitecting.
- **Carbon `RegisterEventHotKey`** (`GlobalHotkey.swift`) for the ⌃⌥Space global hotkey. It's "deprecated" but still the only public API for a system-wide hotkey that doesn't require Accessibility. Hotkey is hardcoded; changing it means editing `kVK_Space` / `controlKey | optionKey` in `AppDelegate.applicationDidFinishLaunching`.
- **`LSUIElement` / `.accessory` activation policy** — no Dock icon by design; the app lives only in the menu bar.

## Conventions

- The Go CLI stays **stdlib-only**. Don't add dependencies to `cli/go.mod`.
- The model is request/response, not realtime — record fully, *then* transcribe. `llama.cpp` realtime audio streaming isn't available yet (upstream issue #20914), so don't build UI that assumes mid-recording partial results.
