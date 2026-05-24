# AllTalk

**Push-to-talk dictation for macOS, where your voice never leaves your machine.**

Hold **⌃⌥Space**, talk, let go. AllTalk transcribes what you said using a speech model
running on *your own GPU* and pastes the text wherever your cursor is. No cloud, no
account, no API key.

> ### 🎹 What is ⌃⌥Space?
> It's the keyboard shortcut you hold to dictate. Those symbols are how macOS writes
> modifier keys, and **⌃⌥Space means three keys pressed together:**
>
> | Glyph | Key |
> |:---:|---|
> | **⌃** | **Control** |
> | **⌥** | **Option** (labelled `alt` on some keyboards) |
> | **Space** | the **spacebar** |
>
> So **⌃⌥Space = Control + Option + Spacebar, held at the same time.**
> (For reference, the other macOS modifier glyphs are ⌘ Command and ⇧ Shift.)
> Everywhere you see **⌃⌥Space** below, it means exactly those three keys at once.

---

## Why AllTalk exists

Speech-to-text got good enough to run at home. A modern Mac has the hardware to
transcribe your voice locally, in real time, with a model like Voxtral. So here's the
question that started this project: **if your own hardware can do the work, why send
your voice to someone else's computer to do it?**

Every cloud dictation service works the same way — it streams your audio to a data
centre, runs the model there, and sends text back. In return you get a privacy policy
and a promise. You don't get proof. Once your voice leaves your machine you're trusting
that it isn't logged, retained "to improve our services," handed over on request,
leaked in a breach, or quietly used to train the next model. I'm skeptical that none of
that ever happens — and skepticism isn't paranoia when you genuinely *cannot verify it*.

AllTalk is the other answer:

```
  Cloud dictation:
    your voice ─▶ the internet ─▶ someone's data centre ─▶ text
    (their servers, their logs, their retention policy, your trust)

  AllTalk:
    your voice ─▶ your own GPU ─▶ text
    (nothing ever leaves your machine)
```

This is what **self-sovereignty** looks like in practice: you own the hardware, you own
the model, you own the data — and the data stays put. The *only* time AllTalk touches
the internet is a one-time model download on first run. After that, pull the ethernet
cable and it still works.

---

## How it works

Three small pieces, all running locally on your Mac:

```
   you speak  ──  hold ⌃⌥Space, then release
       │
       ▼
   AllTalk.app    ·  Swift menu-bar app
   └─ records your voice to a temporary .wav file
       │
       │  spawns the CLI and reads its output as it streams
       ▼
   alltalk        ·  Go CLI — ~250 lines, no dependencies
   └─ POST /v1/chat/completions   (stream = true)
       │
       │  plain HTTP — on localhost, never the internet
       ▼
   llama-server   ·  llama.cpp, port 8899
   └─ Voxtral-Mini-3B speech model, running on YOUR GPU
       │
       ▼
   text  ·  pasted at your cursor, or shown in a popover
   ─────────────────────────────────────────────────────────
   ▲ all three stages live on your machine. the audio is
     handed off as a localhost HTTP request — it never goes
     out to the internet.
```

- **`AllTalk.app`** — the menu-bar app you interact with. Owns the hotkey, records the
  mic, and shows the result.
- **`alltalk`** — a tiny Go command-line tool. It's the bridge: it takes a WAV file,
  sends it to the model, and streams the transcript back word by word. It has no
  external dependencies and works fine on its own from a terminal.
- **`llama-server`** — [llama.cpp](https://github.com/ggml-org/llama.cpp)'s built-in
  server, running the Voxtral speech model on your hardware.

Under the hood, the app uses a Carbon global hotkey (the only macOS API for a
system-wide shortcut that doesn't need extra permissions), records at **16 kHz mono**
via AVFoundation, spawns the `alltalk` binary, and reads its stdout live. It runs with
the **sandbox off and hardened runtime on** — required because it launches a child
process and synthesises a ⌘V keystroke, neither of which the App Sandbox allows.

---

## Quick start

**Hands-on time: under 5 minutes.** The only slow part is a one-time ~3.2 GB model
download — it streams in the background while you do the rest, so the actual typing is
a handful of commands.

**1 · Install the model server + download the model** (needs [Homebrew](https://brew.sh)):

```bash
brew install llama.cpp   # provides `llama-server` — AllTalk launches & stops it for you

# download the model + audio projector into a folder you control (~3.2 GB, one-time)
mkdir -p ~/dev/huggingface/models && cd ~/dev/huggingface/models
base=https://huggingface.co/ggml-org/Voxtral-Mini-3B-2507-GGUF/resolve/main
curl -L -O $base/Voxtral-Mini-3B-2507-Q4_K_M.gguf        # 2.47 GB — model
curl -L -O $base/mmproj-Voxtral-Mini-3B-2507-Q8_0.gguf   # 716 MB — audio projector
```

You don't start `llama-server` yourself — **AllTalk launches it on your first dictation
and shuts it down when you quit.** (If your paths differ from the defaults above, set
them in Settings → Model Server.)

**2 · Build the CLI bridge** (new terminal):

```bash
cd cli && go build -o alltalk . && sudo install alltalk /usr/local/bin/
```

**3 · Run the app:**

```bash
open AllTalk.xcodeproj                # then press ⌘R in Xcode
```

Grant **Microphone** when macOS asks. Then click the menu-bar waveform icon (or just
press **⌃⌥Space** — Control + Option + Spacebar together), talk, and press ⌃⌥Space again
to stop — the transcript streams in.

For *Paste at cursor* mode you'll also grant Accessibility once (see
[First-run gotchas](#first-run-gotchas)). For manual model download, prebuilt binaries,
or pointing at a model server on another machine, read on.

---

## Setup

The quick start above is the fast path; this section is the annotated version — what
each piece does and the options behind it.

You'll need a Mac (Apple Silicon strongly recommended for decent speed), Xcode, and Go.

### 1. Run the model server

**Get `llama-server`** — it ships as part of llama.cpp:

```bash
brew install llama.cpp        # macOS / Linux
llama-server --version        # verify it's installed
```

(Or grab a prebuilt binary or Docker image from the
[llama.cpp releases](https://github.com/ggml-org/llama.cpp/releases).)

**Get the model.** The GGUF repo contains *two* files you need — the model **and** its
audio projector (`mmproj`). Without the projector, `llama-server` starts up fine but
silently can't process audio (it'll look like AllTalk connects but never replies).

The recommended way is to **download both files into a folder you control** — so you
know exactly where the ~3.2 GB of weights live, and can move or delete them deliberately:

```bash
mkdir -p ~/dev/huggingface/models && cd ~/dev/huggingface/models
base=https://huggingface.co/ggml-org/Voxtral-Mini-3B-2507-GGUF/resolve/main
curl -L -O $base/Voxtral-Mini-3B-2507-Q4_K_M.gguf        # 2.47 GB — the model
curl -L -O $base/mmproj-Voxtral-Mini-3B-2507-Q8_0.gguf   # 716 MB — audio projector

llama-server \
  -m       ~/dev/huggingface/models/Voxtral-Mini-3B-2507-Q4_K_M.gguf \
  --mmproj ~/dev/huggingface/models/mmproj-Voxtral-Mini-3B-2507-Q8_0.gguf \
  --port 8899
```

**Prefer the one-liner?** `llama-server` can fetch both itself:

```bash
llama-server -hf ggml-org/Voxtral-Mini-3B-2507-GGUF --port 8899
```

…but it tucks them into a cache (`~/.cache/huggingface/hub` on current builds), not a
folder you chose. To put that cache where you want, set `LLAMA_CACHE` first:

```bash
export LLAMA_CACHE=~/dev/huggingface/models
llama-server -hf ggml-org/Voxtral-Mini-3B-2507-GGUF --port 8899
```

(Note: some builds [ignore `LLAMA_CACHE`](https://github.com/ggml-org/llama.cpp/issues/18684) —
if yours does, use the explicit download above, which always works.)

> **Why not Ollama?** Ollama can't feed audio into a model yet (open requests
> [#12440](https://github.com/ollama/ollama/issues/12440) and
> [#11432](https://github.com/ollama/ollama/issues/11432)), and its API doesn't accept
> the `input_audio` payload AllTalk sends. So it can't run Voxtral for transcription —
> use `llama-server`.

### 2. Build the command-line tool

```bash
cd cli
go build -o alltalk .
sudo install alltalk /usr/local/bin/
```

Stdlib only — no external dependencies. Quick sanity check against the running server:

```bash
alltalk -f some.wav -p "Summarise this"   # transcribe/answer for an existing file
alltalk                                   # record from the mic, then transcribe
```

### 3. Build the macOS app

```bash
open AllTalk.xcodeproj   # then hit ⌘R
```

The app appears in the menu bar — the waveform icon (no Dock icon, by design). See
[First-run gotchas](#first-run-gotchas) below for the permission prompts and an Xcode
signing tip.

---

## First-run gotchas

- **Microphone** — macOS prompts the first time you press ⌃⌥Space. Grant it.
- **Accessibility** — *Paste at Cursor* mode synthesises a ⌘V keystroke, which macOS
  blocks until you allow it under System Settings → Privacy & Security → Accessibility.
  Expect a nag the first time the app tries to paste.
- **Xcode signing** — if Xcode complains about code signing, set your **Team** in the
  target's Signing & Capabilities tab, or switch the certificate to *"Sign to Run
  Locally."*

---

## Using it

- **⌃⌥Space** (hold **Control + Option + Spacebar** together) — start recording; press
  again to stop. Stopping kicks off transcription
  and the reply streams back in real time.
- **Two output modes** — toggle from the menu or the popover:
  - **Paste at cursor** — pastes each word as it streams, so it feels like live
    dictation straight into whatever app you're in.
  - **Show in popover** — accumulates the full transcript in a scrollable SwiftUI view
    and posts a notification when it's done.
- **The model server is automatic** — AllTalk starts `llama-server` on your first
  ⌃⌥Space (the menu status goes `◐ Starting…` → `● Ready`), reuses it for the session,
  and stops it when you quit. The menu's **Stop / Start Model Server** item gives manual
  control; a server you started yourself is adopted and left running on quit.
- **Menu bar → Show Transcript…** — open the popover any time to see the latest text.
- **Menu bar → Settings…** — server URL, prompt, the `alltalk` CLI path, and the
  llama-server binary + model-folder paths.

---

## Customizing

- **Different hotkey** — edit the `kVK_Space` / `controlKey | optionKey` line in
  `AppDelegate.swift`. Carbon key codes live in `Carbon.HIToolbox`.
- **Translation or Q&A instead of plain dictation** — change the prompt in Settings.
  Voxtral understands audio natively, so e.g. `"Answer the question asked in this audio
  clip."` or `"Translate this to French."` both work.
- **Run the model on another box you own** — point the server URL at, say, a Tailscale
  host running `llama-server`. The CLI is just a thin HTTP client, so it's still your
  hardware end to end; latency becomes network + inference.

---

## Deliberately kept simple

A few things are intentionally minimal — easy to extend later if you want them:

- **The hotkey is hardcoded** to ⌃⌥Space. A rebinding UI is more work than it sounds;
  for now, change it in code (see [Customizing](#customizing)).
- **No app icon** — it's a menu-bar utility, so the waveform glyph is enough.
- **History isn't persisted** — the transcript lives for the session and isn't saved.

---

## Known limits

- llama.cpp supports the original **Voxtral 3B (July 2025)** model, not the newer 4B
  Realtime variant. Realtime streaming audio in llama.cpp is still in planning
  ([issue #20914](https://github.com/ggml-org/llama.cpp/issues/20914)). For now it's
  request/response: record first, then transcribe.
- Carbon's `RegisterEventHotKey` is officially "deprecated," but it's still the only
  public macOS API for a system-wide hotkey that doesn't require Accessibility. Apple
  hasn't shipped a replacement.
