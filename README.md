<p align="center">
  <img src="https://raw.githubusercontent.com/greenstevester/alltalk/main/design/icon.png" alt="AllTalk app icon" width="128" height="128">
</p>

# AllTalk

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: macOS 13+](https://img.shields.io/badge/Platform-macOS%2013%2B-lightgrey.svg)
![Swift 5](https://img.shields.io/badge/Swift-5-F05138.svg?logo=swift&logoColor=white)
![Go 1.22](https://img.shields.io/badge/Go-1.22-00ADD8.svg?logo=go&logoColor=white)

Push-to-talk dictation for macOS that runs entirely on your own machine. Hold a hotkey,
speak, release. The transcript is typed at your cursor. No cloud, no account, no API key.

## Why

Speech-to-text is now good enough to run locally. A modern Mac has the hardware to
transcribe your voice in real time with a model like Voxtral. So the premise is simple:
if your own machine can do the work, your voice shouldn't have to leave it.

Cloud dictation streams your audio to a data centre, transcribes it there, and sends text
back. In exchange you get a privacy policy and a promise — not proof. Once your voice
leaves your machine you are trusting that it isn't logged, retained, handed over, or used
to train the next model, and you cannot verify any of it.

AllTalk keeps the whole loop local:

```
cloud dictation   your voice ──▶ the internet ──▶ someone's servers ──▶ text
AllTalk           your voice ──▶ your own GPU ──▶ text
```

The only time AllTalk touches the network is a one-time model download on first setup.
After that it works offline.

## How it works

Three local components:

```
   you speak  ──  hold ⌃⌥Space, then release
       │
       ▼
   AllTalk.app    Swift menu-bar app
   └─ records your voice to a temporary .wav
       │  spawns the CLI, reads its output as it streams
       ▼
   alltalk        Go CLI, ~250 lines, no dependencies
   └─ POST /v1/chat/completions  (stream = true)
       │  plain HTTP on localhost
       ▼
   llama-server   llama.cpp, port 8899
   └─ Voxtral-Mini-3B, running on your GPU
       │
       ▼
   text  ──  pasted at your cursor, or shown in a popover
```

- **`AllTalk.app`** owns the hotkey, records the mic, manages the model server, and shows
  the result. Records at 16 kHz mono via AVFoundation; uses a Carbon global hotkey (the
  only macOS API for a system-wide shortcut that needs no extra permissions). Runs with the
  App Sandbox off and hardened runtime on, because it launches a child process and
  synthesises a ⌘V keystroke.
- **`alltalk`** is the bridge: a small, dependency-free Go tool that sends a WAV to the
  model and streams the transcript back word by word. It also works on its own from a shell.
- **`llama-server`** is [llama.cpp](https://github.com/ggml-org/llama.cpp)'s server, running
  the Voxtral speech model. AllTalk starts and stops it for you (see [Using it](#using-it)).

## Install

**Get the app** — with Homebrew:

```sh
brew install --cask greenstevester/tap/alltalk
```

or download `AllTalk.app` from the [latest release](https://github.com/greenstevester/alltalk/releases/latest),
unzip it, and move it to `/Applications`.

> **Not notarized yet.** This build isn't signed with an Apple Developer ID, so macOS
> blocks it on first launch. Allow it once with:
>
> ```sh
> xattr -dr com.apple.quarantine "/Applications/AllTalk.app"
> ```
>
> or via System Settings → Privacy & Security → "Open Anyway". This applies to the Homebrew
> install too — the app ends up at `/Applications/AllTalk.app` either way. A notarized build
> is planned, which removes this step entirely.

**Set up the model** — AllTalk drives a local `llama.cpp` server, which it starts and stops
for you. Install the server and download the model once:

```bash
brew install llama.cpp

mkdir -p ~/dev/huggingface/models && cd ~/dev/huggingface/models
base=https://huggingface.co/ggml-org/Voxtral-Mini-3B-2507-GGUF/resolve/main
curl -L -O $base/Voxtral-Mini-3B-2507-Q4_K_M.gguf        # 2.47 GB, model
curl -L -O $base/mmproj-Voxtral-Mini-3B-2507-Q8_0.gguf   # 716 MB, audio projector
```

Both files are required — the model and its audio projector (`mmproj`); without the
projector the server starts but can't process audio. If you store them somewhere other than
`~/dev/huggingface/models`, set the path in the app's Settings.

<details>
<summary>Other ways to get the model</summary>

`llama-server` can fetch the model itself with `-hf ggml-org/Voxtral-Mini-3B-2507-GGUF`,
but it caches the files in `~/.cache/huggingface/hub` rather than a folder you chose. Set
`LLAMA_CACHE=/your/path` to redirect that cache (note: some builds
[ignore it](https://github.com/ggml-org/llama.cpp/issues/18684), in which case use the
explicit download above).

Ollama is not an option: it cannot feed audio into a model
([open requests](https://github.com/ollama/ollama/issues/12440)), so it cannot run Voxtral
for transcription.
</details>

## Build from source

For hacking on AllTalk. You need Xcode and Go, plus the model from [Install](#install) above.

```bash
cd cli && go build -o alltalk . && sudo install alltalk /usr/local/bin/   # the CLI
open AllTalk.xcodeproj                                                    # the app — then ⌘R
```

If Xcode complains about signing, set your Team under Signing & Capabilities, or switch the
certificate to "Sign to Run Locally."

## Using it

**The hotkey is ⌃⌥Space** — a three-key chord. Hold Control, Option, and the spacebar at
the same time, not in sequence. The symbols are how macOS writes modifier keys:

| Symbol | Key | Where it is |
|:------:|-----|-------------|
| ⌃ | Control | bottom row, far left |
| ⌥ | Option (`alt` on some keyboards) | left of Command |
| Space | spacebar | the long bar at the bottom |

(The other macOS modifiers, for reference: ⌘ Command and ⇧ Shift.) It is a *global* hotkey
— it fires whatever app is focused. If it ever seems unresponsive, check whether an
input-source or Spotlight shortcut has claimed ⌃Space or ⌥Space in System Settings →
Keyboard → Keyboard Shortcuts.

- **Record.** Press ⌃⌥Space to start, press again to stop. Transcription begins on stop and
  streams back in real time.
- **Two output modes**, switchable from the menu or popover:
  - *Paste at cursor* types each word as it arrives, for live dictation into any app.
  - *Show in popover* collects the full transcript in a scrollable view and notifies when done.
- **The model server is automatic.** AllTalk starts `llama-server` on your first ⌃⌥Space
  (the menu shows `Starting…` then `Ready`), keeps it for the session, and stops it on quit.
  The menu's *Stop / Start Model Server* item gives manual control; a server you started
  yourself is reused and left running.
- **Settings** holds the server URL, prompt, CLI path, and the llama-server and model paths.

On first launch macOS asks for **Microphone** access. *Paste at cursor* mode also needs
**Accessibility** (System Settings → Privacy & Security → Accessibility) to synthesise ⌘V.

## Customizing

- **Hotkey.** Hardcoded to ⌃⌥Space; change `kVK_Space` / `controlKey | optionKey` in
  `AppDelegate.swift` (Carbon key codes live in `Carbon.HIToolbox`).
- **Translation or Q&A.** Change the prompt in Settings — Voxtral handles audio directly,
  so `"Answer the question in this audio."` or `"Translate this to French."` both work.
- **Remote model.** Point the server URL at another machine you own (for example a Tailscale
  host running `llama-server`). The CLI is a thin HTTP client, so it stays your hardware
  end to end.

## Limitations

- llama.cpp supports the original Voxtral 3B (July 2025) model, not the newer 4B Realtime
  variant. Streaming audio is still
  [in planning](https://github.com/ggml-org/llama.cpp/issues/20914) upstream, so for now it
  is record-then-transcribe rather than live.
- The transcript is not persisted; it lives for the session.
- `RegisterEventHotKey` is a deprecated Carbon API, but it remains the only public way to
  register a system-wide hotkey without Accessibility. Apple has not shipped a replacement.

## License

[MIT](LICENSE) © 2026 Steve Greensill. The Voxtral model and llama.cpp are the property of
their respective authors, under their own licenses.
