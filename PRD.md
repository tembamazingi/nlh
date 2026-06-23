# nlh — Now Listen Here
### Product Requirements Document · v0.1 · June 2026

---

## Problem

Voice dictation on macOS and Linux is either cloud-dependent, UI-heavy, or fragile to install. Tools that do run locally bundle far more than necessary — voice cloning, model management UIs, stories editors — and their download pipelines break on corporate networks. The actual need is narrow: hold a key, speak, release, get clean text pasted wherever the cursor is. nlh is that tool and nothing else.

---

## Goals

- **Local-first.** All inference runs on-device. No network calls during use.
- **System-wide.** Works in any app: Claude Desktop, Claude Code, Chrome, Slack, Terminal.
- **Minimal.** No GUI. No model management. No TTS. A TUI log and two shell scripts.
- **Accurate.** Whisper Large v3 Turbo transcription, always refined by a local LLM before paste. LLM backend is chosen at setup time.
- **Fast.** Hotkey-to-paste under 3 seconds for typical utterances on Apple Silicon.

## Non-Goals

- Text-to-speech or voice cloning
- GUI / app window, tray icon, or menubar item
- Cloud inference or sync of any kind
- Model downloading via UI
- Multi-voice, stories, or timeline editing
- Real-time streaming transcription
- Windows

---

## Core User Flow

```
Hold hotkey  →  mic records
Release      →  Whisper transcribes  →  LLM refines  →  pastes into focused field
```

Every capture is appended to a TUI log: `[timestamp]  [duration]  transcript`. That is the complete user-facing surface of the product.

---

## Functional Requirements

### F1 — Global Push-to-Talk

- A configurable key chord triggers recording from any app, regardless of which app has focus.
- Hold = record, release = stop and process. Toggle mode (tap to start, tap to stop) available for longer dictation: activated by tapping `Space` while holding the PTT chord mid-hold, without a gap in the audio.
- Hotkey is user-configurable in a plaintext config file. Default: `Right Cmd + Right Option` (PTT) / `Right Cmd + Right Option + Space` (toggle).

### F2 — Audio Capture

- Captures from the default system microphone at 16 kHz mono.
- Audio written to a temp WAV file for the duration of the capture.
- Temp file deleted after paste. No audio persisted.

### F3 — Local Transcription

- Whisper Large v3 Turbo in GGML format via `whisper-cli` (whisper.cpp).
- Model path is user-configurable — no bundled model, no download UI.
- Zero network calls at runtime. Fails loudly if model file is missing.

### F4 — Transcript Refinement

- Every transcript is piped through a local LLM before paste.
- Removes filler words (`um`, `uh`, `like`, `you know`) and self-corrections. Preserves all technical terms and intent exactly.
- LLM backend is selected once at setup: `ollama`, `llama.cpp`, or `transformers` (HuggingFace). All run fully locally.
- Model path and system prompt are user-configurable. Default system prompt:
  > "You are a transcript cleaner. Remove filler words (um, uh, like, you know), false starts, and self-corrections. Fix punctuation and capitalisation. Preserve all technical terms, proper nouns, and code identifiers exactly as spoken. Output only the cleaned transcript — no commentary, no explanations."

### F5 — Paste

- Transcript copied to clipboard via `pbcopy`.
- Synthetic `Cmd+V` fired into the app that held focus at chord-start, not at paste time.
- Original clipboard contents saved before and restored after.
- Requires macOS Accessibility permission granted once to the hotkey daemon (`skhd`).

### F6 — TUI Log & Capture Browser

- Each capture saved as an individual Markdown file in `~/.nlh/captures/`, named by timestamp (e.g. `2026-06-22T09-42-11.md`). Every file follows this structure:

  ```markdown
  # 2026-06-22 09:42:11
  **Duration:** 6s

  If the context window fills up, does it drop the oldest messages or does some kind of automatic summarisation happen?

  ---
  **Raw:** yeah so um if the context window fills up does it uh drop the oldest messages or is there some kind of like summarisation that happens automatically
  ```

- A flat index log at `~/.nlh/captures.log` is appended on every capture: `[HH:MM:SS]  [Xs]  transcript text`
- `nlh log` displays the 25 most recent entries, numbered most-recent-first, piped through `less` for scrolling. `nlh log -a` / `nlh log --all` shows all entries paginated through `less`.
- `nlh open <n>` opens entry n (as numbered in `nlh log`) in `$EDITOR`. `nlh open -b <n>` / `nlh open --browser <n>` renders via pandoc and opens in the default browser. `nlh open` with no argument falls back to an `fzf` picker for interactive search when the entry number isn't known — making `fzf` an optional convenience rather than a hard dependency.

### F7 — Capture Hygiene

- `nlh clear` presents an interactive prompt:
  ```
  Clear captures older than:
    1) 1 day
    2) 7 days
    3) 2 weeks
    4) All
  > _
  ```
- On selection, shows a count of entries to be removed and asks for confirmation before deleting.
- Removes both the individual `.md` files from `~/.nlh/captures/` and the corresponding lines from `~/.nlh/captures.log`.

### F8 — Background Daemon Management

- `nlh start` registers the hotkey daemon (and LLM backend daemon if applicable) as login services so they survive reboots.
- `nlh stop` tears down all registered services.
- `nlh status` reports daemon state (running / stopped), model paths, and the last 5 captures in a single terminal print.

### F9 — Config

- Single plaintext config file at `~/.nlh/config`, generated by `nlh setup`.
- Keys: `whisper_model_path`, `hotkey`, `llm_backend` (ollama | llama.cpp | transformers), `llm_model_path`, `log_path`.
- Changes take effect on next invocation — no daemon restart required.

---

## Technical Architecture

| Component      | Tool                                        | Role                                                             |
|----------------|---------------------------------------------|------------------------------------------------------------------|
| Global hotkey  | `skhd` (macOS) / `sxhkd` or `keyd` (Linux) | Fires start/stop scripts on keydown / keyup                      |
| Audio capture  | `sox`                                       | Records mic to `$TMPDIR/nlh_cap.wav`, deleted post-transcription |
| Transcription  | `whisper-cli` (whisper.cpp)                 | Local GGML inference, no network                                 |
| Refinement     | ollama / llama.cpp / transformers (pick one)| Cleans raw transcript before every paste                         |
| Paste          | `pbcopy` + `osascript` (macOS) / `xclip` + `xdotool` or `wl-copy` + `ydotool` (Linux) | Clipboard write + synthetic Cmd+V |
| Capture log    | Markdown files + `fzf`                      | Per-capture `.md` files; `nlh open` for interactive browsing     |
| Capture browse | `fzf`                                       | Fuzzy picker for `nlh open`                                      |
| Browser render | `pandoc`                                    | Markdown → HTML for `nlh open --browser`                         |
| Background     | `launchd` / `brew services` (macOS) / `systemd` (Linux) | Keeps hotkey daemon alive across reboots          |

### Platform support

Three components have platform-specific implementations; everything else is identical across macOS and Linux.

| Concern        | macOS                        | Linux (X11)           | Linux (Wayland)       |
|----------------|------------------------------|-----------------------|-----------------------|
| Global hotkey  | `skhd`                       | `sxhkd`               | `keyd`                |
| Clipboard      | `pbcopy` / `pbpaste`         | `xclip`               | `wl-copy` / `wl-paste` |
| Synthetic paste| `osascript`                  | `xdotool`             | `ydotool`             |
| Background     | `launchd` via `brew services`| `systemd` user unit   | `systemd` user unit   |

`nlh setup` detects the platform and writes the appropriate config. The `start.sh` / `stop.sh` scripts reference platform-agnostic wrappers (`nlh-paste`, `nlh-type`) that resolve to the correct tool at runtime.

### CLI

The user-facing interface is a single command: `nlh`.

```
nlh setup    # interactive first-run: choose LLM backend, set model paths, write config
nlh start    # register hotkey daemon + any backend daemons as login services, begin listening
nlh stop     # unregister services, stop listening
nlh status   # one-shot print: daemon state, model paths, last 5 captures
nlh log      # last 25 captures numbered, scrollable via less (-a/--all for full paginated history)
nlh open <n> # open entry n in $EDITOR (-b/--browser for rendered HTML; no arg for fzf picker)
nlh clear    # interactive prompt to clear captures older than: 1 day | 7 days | 2 weeks | all
nlh config   # open ~/.nlh/config in $EDITOR
```

### Codebase

v1 comprises:

- `nlh` — the CLI entry point; shell script dispatcher for the subcommands above
- `start.sh` — invoked by skhd on keydown; begins audio capture
- `stop.sh` — invoked by skhd on keyup; stops capture, runs transcription, runs refinement, pastes
- `~/.skhdrc` — hotkey bindings pointing at start/stop, written by `nlh setup`
- `~/.nlh/config` — plaintext config written by `nlh setup`

No build step. Every line is auditable without a toolchain. For contributors running from source, `nlh setup` serves the same role as an install script.

### Background operation

`nlh start` registers `skhd` as a launchd login agent via `brew services start skhd`. It starts automatically on login and listens for the hotkey chord system-wide without any visible window. If the chosen LLM backend requires a persistent daemon (ollama), `nlh start` registers that too. `nlh stop` tears both down.

---

## Error Handling

| Failure | Detection | Behaviour |
|---------|-----------|-----------|
| Model file missing at startup | `whisper_model_path` not found on disk | `nlh start` fails immediately with a clear message and the path that was checked |
| Silence / no speech captured | Whisper returns empty or whitespace-only output | Discard silently; no paste, no log entry |
| Whisper inference error | Non-zero exit from `whisper-cli` | Log error to `~/.nlh/error.log`; restore clipboard; no paste |
| LLM refinement timeout or error | Non-zero exit or no output within 10s | Fall back to pasting the raw Whisper transcript; append `[unrefined]` tag to log entry |
| Paste target app closed between chord-start and paste | `osascript` / `xdotool` returns error | Log error; transcript remains on clipboard for manual paste |
| Mic not available | `sox` exits immediately with error | Log error; abort capture cleanly |
| Clipboard restore failure | `stop.sh` trap catches any mid-paste crash | Original clipboard written to `~/.nlh/clipboard.bak` for manual recovery |

All errors surface via `nlh status` and `~/.nlh/error.log`. No error silently swallows a transcript.

---

## Testing

Tests are written with **BATS** (Bash Automated Testing System), installable via `brew install bats-core`. The test suite lives in `tests/`.

Coverage targets:

- `nlh` CLI dispatcher routes all subcommands correctly
- `stop.sh` paste pipeline: transcription → refinement → clipboard write → synthetic paste sequence
- Capture file written with correct schema on each invocation
- Error handling: each failure mode in the table above produces the expected log entry and fallback behaviour
- Platform wrapper (`nlh-paste`, `nlh-type`) selects the correct tool for the detected platform

The `/tdd` workflow is the implementation path for all the above. No feature is considered done without a passing BATS test.

---

## Security

**macOS permission model.** The app requires exactly two elevated permissions — microphone and Accessibility — both granted explicitly by the user via System Settings. No silent acquisition of either is possible on modern macOS.

**Temp audio file.** The capture is written to `$TMPDIR` (resolves to a user-private directory on macOS, e.g. `/var/folders/.../`) rather than world-readable `/tmp`. The file is deleted immediately after transcription completes.

**No network egress.** All processing — transcription, LLM refinement — happens on-device at runtime. No audio, transcript, or keystroke data is transmitted anywhere.

**skhd key listener scope.** skhd listens globally for key events but only fires on exact chord matches. It does not log or buffer arbitrary keystrokes. This is auditable directly in the skhd source.

**Clipboard safety.** The existing clipboard is saved before paste and restored after. `stop.sh` registers a trap to perform the restore on failure, ensuring a crash between write and restore does not silently destroy clipboard contents.

**ollama loopback binding.** If the user selects ollama as the LLM backend, it binds to `localhost:11434`. macOS's application firewall blocks external access by default. The endpoint is unauthenticated and must never be exposed beyond loopback; `nlh status` warns if this binding is detected on a non-loopback interface.

---

## Success Criteria

- Hotkey-to-paste latency < 3s for utterances up to 30 seconds (Apple Silicon, M-series).
- Zero network calls after initial model setup, including on restricted corporate networks.
- Paste works correctly in: Terminal, Chrome, Slack, Claude Desktop, Claude Code, and any standard macOS text field.
- Setup time under 15 minutes from zero, following the README.
- No app window, tray icon, menubar item, or background GUI process.

---

## Out of Scope — v1

- Audio file input mode (transcribe a WAV/MP3 rather than live mic)
- MCP server / agent integration
- Speaker diarization
- Windows (no Homebrew, no compatible hotkey daemon, entirely different clipboard and paste model)

---

## Stretch Goals

### Homebrew Formula

Package nlh as a Homebrew formula for one-command install:

```bash
brew tap temba/nlh
brew install nlh
```

The formula declares `skhd`, `sox`, and `whisper-cpp` as dependencies and installs the `nlh` CLI to the Homebrew prefix. After install, the user runs `nlh setup` then `nlh start` — that's the complete getting-started path.
