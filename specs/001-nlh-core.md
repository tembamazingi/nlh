# 001 — nlh: Local Push-to-Talk Dictation Tool

## Context

Voice dictation on macOS/Linux is either cloud-dependent or over-engineered. `nlh` ("Now Listen Here") is a minimal, local-first push-to-talk dictation tool: hold a key, speak, release, get clean text pasted wherever the cursor is. All inference is on-device. The only user-facing surfaces are a hotkey and a TUI log.

## Scope

**In scope:**
- Global push-to-talk hotkey daemon via `skhd` (macOS) or `sxhkd`/`keyd` (Linux)
- Audio capture from default system mic via `sox` (16 kHz mono WAV)
- Local transcription via `whisper-cli` (whisper.cpp, GGML format)
- Transcript refinement via local LLM (`ollama`, `llama.cpp`, or `transformers` Python wrapper)
- Clipboard-based paste with clipboard save/restore
- Per-capture Markdown files + flat index log
- CLI subcommands: `setup`, `start`, `stop`, `status`, `log`, `open`, `clear`, `config`
- BATS test suite covering all above
- macOS and Linux (X11 and Wayland)

**Out of scope:**
- Audio file input mode (WAV/MP3 transcription)
- MCP server / agent integration
- Speaker diarization
- Windows
- GUI, tray icon, or menubar item
- Real-time streaming transcription
- Text-to-speech or voice cloning
- Homebrew formula (stretch goal, not v1)

---

## Acceptance criteria

### F1 — Global Push-to-Talk

- [ ] Holding the configured PTT chord begins recording from any foreground app.
- [ ] Releasing the PTT chord stops recording and triggers the transcription/refinement/paste pipeline.
- [ ] **Toggle mode:** tapping `Space` while holding the PTT chord mid-hold (without interrupting audio) switches to toggle mode; recording continues until the user taps the PTT chord a second time (tap = press + release without Space).
- [ ] PTT chord is configurable in `~/.nlh/config`. Default: `Right Cmd + Right Option`.
- [ ] Toggle-mode trigger chord is configurable. Default: `Right Cmd + Right Option` + `Space` mid-hold.

### F2 — Audio Capture

- [ ] Records from the default system microphone at 16 kHz mono.
- [ ] Audio written to `$TMPDIR/nlh_cap.wav`; file deleted immediately after transcription completes (or fails).
- [ ] If `sox` exits non-zero (mic unavailable), capture is aborted cleanly; error logged to `~/.nlh/error.log`; no paste.
- [ ] Recording stops automatically when `max_duration` seconds elapse (config key, default `300`); transcript is processed as normal and a `[max-duration]` tag appended to the log entry.

### F3 — Local Transcription

- [ ] Transcribes using `whisper-cli` with the GGML model at `whisper_model_path`.
- [ ] Zero network calls at runtime.
- [ ] If `whisper_model_path` is not found on disk, `nlh start` fails immediately with a message naming the missing path.
- [ ] If `whisper-cli` exits non-zero, error is logged to `~/.nlh/error.log`; clipboard restored; no paste.
- [ ] If Whisper returns empty or whitespace-only output, the capture is discarded silently — no paste, no log entry.

### F4 — Transcript Refinement

- [ ] Every non-empty transcript is piped through the configured local LLM before paste.
- [ ] Filler words (`um`, `uh`, `like`, `you know`), false starts, and self-corrections are removed. Technical terms, proper nouns, and code identifiers are preserved exactly.
- [ ] LLM backend is one of: `ollama`, `llama.cpp`, `transformers`. Configured once via `nlh setup`.
- [ ] `transformers` backend is invoked via a bundled `scripts/llm_refine.py`; the script's path is written into config by `nlh setup`. Shell scripts call `python3 <llm_script_path>` with the transcript on stdin.
- [ ] If the LLM exits non-zero, produces no output, or does not respond within 10 seconds, the raw Whisper transcript is pasted as a fallback; `[unrefined]` is appended to the log entry.
- [ ] System prompt is user-configurable (`llm_system_prompt` in config). Default: *"You are a transcript cleaner. Remove filler words (um, uh, like, you know), false starts, and self-corrections. Fix punctuation and capitalisation. Preserve all technical terms, proper nouns, and code identifiers exactly as spoken. Output only the cleaned transcript — no commentary, no explanations."*
- [ ] LLM model path/identifier is configurable (`llm_model_path` in config).

### F5 — Paste

- [ ] Transcript copied to clipboard via `pbcopy` (macOS) / `xclip` (X11) / `wl-copy` (Wayland).
- [ ] Synthetic `Cmd+V` fired into the app that held focus at chord-start (not at paste time) via `osascript` (macOS) / `xdotool` (X11) / `ydotool` (Wayland).
- [ ] Existing clipboard contents saved before and restored after paste.
- [ ] If `stop.sh` crashes between clipboard write and restore, original clipboard is written to `~/.nlh/clipboard.bak`. A `trap` in `stop.sh` handles this.
- [ ] If the paste target app is no longer available, the error is logged and the transcript remains on the clipboard for manual paste.
- [ ] macOS requires Accessibility permission granted once to the `skhd` daemon; `nlh setup` prints the path to the System Settings pane.

### F6 — TUI Log & Capture Browser

- [ ] Each capture is saved as an individual Markdown file in `~/.nlh/captures/`, named `YYYY-MM-DDTHH-MM-SS.md`.

  File structure (exact):
  ```markdown
  # YYYY-MM-DD HH:MM:SS
  **Duration:** Xs

  <refined transcript>

  ---
  **Raw:** <raw Whisper transcript>
  ```

- [ ] A flat index log at `~/.nlh/captures.log` is appended after every successful capture: `[HH:MM:SS]  [Xs]  <refined transcript text>`
- [ ] `nlh log` prints the 25 most recent entries, numbered most-recent-first (1 = newest), piped through `less`.
- [ ] `nlh log -a` / `nlh log --all` prints all entries through `less`.
- [ ] `nlh open <n>` opens entry `n` (as numbered by `nlh log`) in `$EDITOR`.
- [ ] `nlh open -b <n>` / `nlh open --browser <n>` renders entry `n` via `pandoc` and opens the resulting HTML in the default browser.
- [ ] `nlh open` with no argument and `fzf` available launches an `fzf` picker over all captures.
- [ ] `nlh open` with no argument and `fzf` absent prints an error message directing the user to provide an entry number or install `fzf`.

### F7 — Capture Hygiene

- [ ] `nlh clear` presents an interactive menu:
  ```
  Clear captures older than:
    1) 1 day
    2) 7 days
    3) 2 weeks
    4) All
  > _
  ```
- [ ] After selection, displays the count of entries to be removed and prompts for confirmation (`y/N`) before deleting.
- [ ] On confirmation, removes matching `.md` files from `~/.nlh/captures/` and removes corresponding lines from `~/.nlh/captures.log`.
- [ ] On cancellation or any non-`y` input, exits without modifying any files.

### F8 — Background Daemon Management

- [ ] `nlh start` registers `skhd` (macOS) / `sxhkd` or `keyd` (Linux) as a login service so it persists across reboots. Also registers `ollama` if it is the selected LLM backend.
- [ ] `nlh stop` tears down all registered services.
- [ ] `nlh status` prints (single terminal output, no pager): daemon state (running / stopped), model paths, and the last 5 captures.
- [ ] `nlh status` warns if the `ollama` endpoint is detected on a non-loopback interface.

### F9 — Config

- [ ] Config file at `~/.nlh/config` uses `KEY=VALUE` shell syntax (one key per line, no spaces around `=`).
- [ ] Keys: `whisper_model_path`, `hotkey`, `llm_backend`, `llm_model_path`, `llm_script_path`, `llm_system_prompt`, `log_path`, `max_duration`.
- [ ] `nlh setup` runs an interactive first-run wizard: detects platform, prompts for LLM backend choice, model paths, hotkey; writes `~/.nlh/config`; writes `~/.skhdrc` (or equivalent).
- [ ] If `~/.nlh/config` already exists, `nlh setup` warns the user and asks whether to overwrite or abort. Existing config is not silently clobbered.
- [ ] Config changes take effect on next `start.sh` / `stop.sh` invocation — no daemon restart required.
- [ ] `nlh config` opens `~/.nlh/config` in `$EDITOR`.

### CLI & Codebase

- [ ] Single `nlh` shell script dispatcher routes all subcommands.
- [ ] `start.sh` handles keydown (begins capture); `stop.sh` handles keyup (stops capture → transcribe → refine → paste → log).
- [ ] Platform-agnostic wrappers `nlh-paste` and `nlh-type` resolve to the correct tool (`pbcopy`/`xclip`/`wl-copy` and `osascript`/`xdotool`/`ydotool`) at runtime based on detected platform.
- [ ] No build step. All scripts are auditable shell (and one Python file for the `transformers` wrapper).

### Performance

- [ ] Hotkey-to-paste latency under 3 seconds for utterances up to 30 seconds on Apple Silicon (M-series).

---

## Edge cases and error handling

| Failure | Detection | Behaviour |
|---------|-----------|-----------|
| `whisper_model_path` not found | checked at `nlh start` | Immediate failure with the missing path printed; daemon not registered |
| No speech / silence | Whisper returns empty/whitespace | Discard silently; no paste; no log entry |
| `whisper-cli` non-zero exit | Exit code check in `stop.sh` | Log to `~/.nlh/error.log`; restore clipboard; no paste |
| LLM timeout or error | Non-zero exit or no output within 10s | Paste raw transcript; append `[unrefined]` to log entry |
| Paste target app closed | `osascript`/`xdotool` error | Log error; transcript left on clipboard |
| Mic unavailable | `sox` immediate non-zero exit | Log error; abort capture |
| Clipboard restore failure | `trap` in `stop.sh` | Write original clipboard to `~/.nlh/clipboard.bak` |
| Max duration reached | Timer in `start.sh` or `stop.sh` | Stop and process normally; append `[max-duration]` tag |
| `nlh open` without `fzf` and without entry number | `fzf` not in PATH | Print error: "Provide an entry number (nlh open <n>) or install fzf." |
| `nlh setup` re-run with existing config | File existence check | Warn user; prompt to overwrite or abort; do not clobber silently |
| `ollama` bound to non-loopback interface | `nlh status` detects binding | Print warning in `nlh status` output |

All errors surface via `nlh status` and `~/.nlh/error.log`. No error silently swallows a transcript.

---

## Open questions

- Toggle-mode stop gesture: specced as "tap PTT chord a second time." If skhd's keyup event fires on release of a mid-hold Space tap, there may be an edge case where releasing the original PTT chord (still held while Space was tapped) triggers a spurious stop. Implementation should verify skhd event ordering for this sequence. *(Flagged for implementation.)*
- `transformers` Python wrapper: `scripts/llm_refine.py` will need a model-loading strategy (load on first call vs. persistent process). A persistent process avoids repeated cold-start overhead. This is an implementation decision; the spec requires the wrapper exists and that `nlh setup` writes its path to `llm_script_path`.

---

## Notes

- No network calls at runtime is a hard requirement, including during setup after model files are placed.
- `$TMPDIR` (not `/tmp`) is used for the temp WAV file; on macOS this resolves to a user-private directory.
- Test suite uses BATS (`brew install bats-core`). All pipeline paths must have passing BATS tests before a feature is considered done.
- Linux Wayland support uses `keyd` (hotkey), `wl-copy`/`wl-paste` (clipboard), `ydotool` (synthetic paste).
