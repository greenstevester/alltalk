# Phase 1 — App-managed `llama-server` lifecycle

**Date:** 2026-05-24
**Status:** Approved (design); pending implementation plan
**Scope:** Phase 1 of the AllTalk "self-contained app" roadmap.

## Context

AllTalk is a macOS menu-bar push-to-talk dictation app. Today the user must
start `llama-server` by hand in a terminal and kill it by hand — there is no
off switch and it's easy to leave an orphan process holding ~4 GB of RAM and
the microphone-adjacent pipeline. This was hit live ("how the hell do I kill
that now?").

This spec covers **Phase 1** only: the app owns the model server's lifecycle so
the user never touches a terminal to start or stop it, and never strands an
orphan. It is the first of four phases:

| Phase | Delivers |
|---|---|
| **1 (this spec)** | App auto-starts/stops `llama-server`; menu shows status + Stop/Start; Quit tears down the owned server. |
| 2 | First-run model auto-download + onboarding window. |
| 3 | Bundle `llama-server` + dylibs in the `.app` (drop the brew dependency). |
| 4 | Developer ID signing, Apple notarization, `.dmg`/`.zip` distribution. |

Phase 1 relies on a brew-installed `llama-server` and a model already present
on disk; those dependencies are removed in later phases.

## Goals

- The app starts `llama-server` itself when dictation needs it, and stops it on
  quit — no terminal required.
- The menu shows live server status and a single Stop/Start control.
- The app never strands an orphan server, and never kills a server it didn't
  start.

## Non-goals (explicitly deferred)

- Model auto-download (Phase 2). The model must already exist in the configured
  folder.
- Bundling `llama-server` (Phase 3). Phase 1 uses the brew-installed binary.
- Signing / notarization / packaging (Phase 4).
- Changing the recording, transcription, or output-mode behaviour beyond what
  the lifecycle requires.

## Design

### Server lifecycle state machine

A new `LlamaServerManager` (`@MainActor`, `ObservableObject`) owns the server as
a child `Process` and publishes a single `state`:

```
stopped → starting → ready
                 ↘ error(reason)
ready/error → (stop) → stopped
```

- `stopped` — no server owned by us; nothing known to be listening.
- `starting` — we spawned the process and are polling `/health`.
- `ready` — `GET http://localhost:8899/health` returned `{"status":"ok"}`.
- `error(reason)` — discovery failed, the process exited, or health never
  became ok within the timeout. `reason` is a human-readable string.

### Start timing: lazy + sticky, fired at record-start

- The server is **not** started on app launch (no RAM cost until used).
- On **⌃⌥Space (record start)** the app does two things at once:
  1. begins recording immediately (recording does not depend on the server), and
  2. calls `serverManager.ensureRunning()`.
  Model load (~seconds) overlaps with the user speaking.
- On **release (record stop)**:
  - if `state == .ready` → transcribe immediately;
  - if `state == .starting` → show "Starting model…" and transcribe as soon as
    it becomes `ready`;
  - if `state == .error` → notify with the reason and discard the recording.
- Once started, the server **stays up for the session** (subsequent dictations
  are instant). It is torn down only by explicit Stop or by Quit.

### Adoption: don't double-start

`ensureRunning()` is **idempotent**: if `state` is already `.starting` or
`.ready` it returns immediately without probing or spawning.

Otherwise it probes the port with `GET http://localhost:8899/v1/models` (the
same OpenAI-compatible endpoint the CLI uses — it confirms both readiness *and*
that the responder is a llama.cpp/compatible server):

- **200 with a non-empty `models` list** → adopt it: `state = .ready`,
  `weStartedIt = false`. We will use it but never kill it.
- **Connection refused / nothing listening** → spawn our own (below),
  `weStartedIt = true`.
- **Port answers but the response isn't a valid models list** →
  `error("port 8899 is in use by another process")`. Do not spawn, do not send
  audio to it.

### Starting our own server

Spawn `llama-server` as a child `Process` (mirrors the existing CLI-spawn
pattern in `AllTalkController.runCLI`):

```
<llama-server> -m <modelFile> --mmproj <mmprojFile> --port 8899
```

Then poll `GET /health` via `URLSession` every ~1 s, up to a 60 s timeout:
`{"status":"ok"}` → `ready`; process exits early or timeout → `error` (capture
the stderr tail for the message).

### Discovery & configuration (Phase-1 reality)

- **`llama-server` binary:** auto-detect in order — `/opt/homebrew/bin/llama-server`,
  `/usr/local/bin/llama-server`, then `$PATH`. Overridable via a new Settings
  field `llamaServerPath`.
- **Model files:** a new Settings field `modelFolder` (default
  `~/dev/huggingface/models`). The manager looks in that folder for the two
  known filenames:
  - `Voxtral-Mini-3B-2507-Q4_K_M.gguf` (model)
  - `mmproj-Voxtral-Mini-3B-2507-Q8_0.gguf` (audio projector)
- Missing binary → `error("llama-server not found — install with `brew install
  llama.cpp` or set its path in Settings")`.
- Missing model file(s) → `error("model not found in <folder> — see Setup")`.
  This is the deliberate bridge to Phase 2.

### Ownership & clean quit

- `weStartedIt: Bool` is the crux. The app **only** terminates the server when
  `weStartedIt == true`.
- **Stop Model Server** (menu) and **Quit / `applicationWillTerminate`** both
  call `stopIfOwned()`: SIGTERM → wait ~2 s → SIGKILL if still alive → delete
  the PID file → `state = .stopped`.
- A server the user started in a terminal (`weStartedIt == false`) is adopted
  for use but never killed by AllTalk.

### Crash-orphan safety net

When we spawn a server we write its PID and port to
`~/Library/Application Support/AllTalk/server.pid`. On launch, if that file
names a live `llama-server` process on :8899, the app re-adopts it as
**owned** (`weStartedIt = true`) so the next Stop/Quit can clean it up — rather
than leaving a stranded process from a previous crash.

### Menu

```
┌──────────────────────────────────┐
│ ● Model: Ready                    │  ← live status line (disabled)
│ ──────────────────────────────── │     ○ Stopped · ◐ Starting… · ⚠ Error
│ ● Start Recording        ⌃⌥Space  │
│ ──────────────────────────────── │
│ ✓ Paste at Cursor                 │
│   Show in Popover                 │
│ ──────────────────────────────── │
│ Show Transcript…                  │
│ Stop Model Server                 │  ← toggles to "Start Model Server"
│ Settings…                         │
│ ──────────────────────────────── │
│ Quit AllTalk               ⌘Q     │  ← auto-stops the owned server
└──────────────────────────────────┘
```

- The status line is a disabled menu item reflecting `serverManager.state`.
- The toggle reads "Stop Model Server" when `ready`/`starting`, "Start Model
  Server" when `stopped`/`error`.
- The menu is rebuilt on state change via the existing `onStateChange`
  callback; `LlamaServerManager.state` changes must trigger that rebuild.

### Error states (surfaced as menu status + a `UNUserNotification`)

- `llama-server` binary not found.
- Model and/or mmproj file not found in the configured folder.
- Server spawned but `/health` never returned ok within 60 s (include stderr
  tail).
- Port 8899 answered but does not look like llama.cpp.

## Components

- **new `AllTalk/LlamaServerManager.swift`** (~150 LOC) — single responsibility:
  server lifecycle. Owns the child `Process`, binary/model discovery, health
  polling, the PID file, and publishes `state` + `weStartedIt`. Public surface:
  `ensureRunning()`, `stopIfOwned()`, `toggle()`, `var state`.
- **changed `AllTalk/AllTalkController.swift`** — at record-start call
  `serverManager.ensureRunning()`; at record-stop await `.ready` before invoking
  the CLI; expose server state for the menu.
- **changed `AllTalk/AppDelegate.swift`** — menu gains the status line + Stop/
  Start toggle; `applicationWillTerminate` calls `serverManager.stopIfOwned()`.
- **changed `AllTalk/SettingsView.swift`** + UserDefaults — new keys
  `llamaServerPath` and `modelFolder` with the defaults above, following the
  existing `serverURL` / `cliPath` pattern.

## Data

- New `ServerState` enum: `stopped`, `starting`, `ready`, `error(String)`.
- New UserDefaults keys: `llamaServerPath: String`, `modelFolder: String`.
- New state file: `~/Library/Application Support/AllTalk/server.pid`
  (PID + port).

## Testing

Introduce a minimal XCTest target (the project currently has none) covering the
**pure logic**, which is where the value is:

- binary discovery order (given a fake filesystem / injected lookup);
- `ServerState` transitions and the `weStartedIt` ownership rule;
- model-folder filename resolution and the "missing file" error paths.

Process-spawning and live `/health` polling are integration-verified manually
via the existing run flow: launch the app, confirm the server starts lazily on
first ⌃⌥Space, confirm Quit leaves no `llama-server` process, confirm an
externally-started server is adopted and *not* killed on Quit.

## Success criteria

1. With no server running, first ⌃⌥Space starts `llama-server`; the menu shows
   `Starting…` then `Ready`; dictation works.
2. After Quit, `pgrep -f llama-server` returns nothing (the app cleaned up).
3. With a user-started server already on :8899, the app adopts it, dictation
   works, and Quit leaves that server running.
4. Menu Stop Model Server stops an owned server and flips to Start Model Server;
   Start brings it back.
5. Missing binary or model surfaces a clear `error` status + notification, and
   the app does not crash.
```
