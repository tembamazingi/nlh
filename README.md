# nlh — Now Listen Here

Local push-to-talk dictation for macOS and Linux. Hold a key, speak, release — cleaned text pastes wherever your cursor is. No GUI. No cloud. No network calls at runtime.

```
Hold hotkey  →  mic records
Release      →  Whisper transcribes  →  LLM refines  →  pastes into focused app
```

---

## Requirements

- macOS 13+ (Apple Silicon recommended) or Linux (X11 or Wayland)
- [Homebrew](https://brew.sh) (macOS)
- ~1 GB disk space for the Whisper model

---

## Install dependencies

```bash
brew install koekeishiya/formulae/skhd sox whisper-cpp ollama fzf pandoc
```

> **Linux:** replace `skhd` with `sxhkd` (X11) or `keyd` (Wayland), `sox` remains the same, and use `xclip`+`xdotool` (X11) or `wl-clipboard`+`ydotool` (Wayland) instead of the macOS clipboard tools.

---

## Download the Whisper model

`nlh` uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for local transcription. You need the model file on disk before setup.

```bash
mkdir -p ~/.cache/whisper
curl -L -o ~/.cache/whisper/ggml-large-v3-turbo.bin \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
```

This is an ~800 MB download. Smaller models (e.g. `ggml-base.en.bin`, ~150 MB) also work but are less accurate. Browse available models at [huggingface.co/ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp).

---

## Pull an LLM

nlh pipes every transcript through a local LLM to remove filler words and fix punctuation before pasting. The default backend is [ollama](https://ollama.com).

```bash
ollama pull llama3
```

Any instruction-following model works. `llama3` (~4 GB) is a solid default. Smaller options: `llama3:8b`, `mistral`, `phi3`.

> You do **not** need to run `ollama serve` manually. `nlh start` registers ollama as a login service so it starts automatically in the background and survives reboots.

---

## Set up nlh

Clone the repo and run setup from the project directory:

```bash
git clone git@github.com:tembamazingi/nlh.git
cd nlh
./nlh setup
```

The interactive wizard will ask for:

| Prompt | What to enter |
|--------|---------------|
| Whisper model path | `~/.cache/whisper/ggml-large-v3-turbo.bin` |
| LLM backend | `ollama` |
| LLM model | `llama3` |
| Hotkey | press Enter for default (`rcmd + ralt`) |
| Max recording duration | press Enter for default (300s) |

Setup writes `~/.nlh/config` and appends the hotkey bindings to `~/.skhdrc`.

---

## Grant permissions (macOS)

Two one-time permissions are required:

**Microphone** — grant to your terminal app:
> System Settings → Privacy & Security → Microphone → enable your terminal

**Accessibility** — required for skhd to listen for global hotkeys and for synthetic paste:
> System Settings → Privacy & Security → Accessibility → add `skhd`

skhd will prompt for Accessibility permission on first start. If the hotkey appears to do nothing, check this setting first.

---

## Start

```bash
./nlh start
```

This registers skhd as a login service (survives reboots) and starts the ollama daemon in the background. You will not see any persistent terminal window — both run as background services.

Verify everything is running:

```bash
./nlh status
```

---

## Use it

1. Click into any text field in any app (Terminal, Chrome, Slack, Claude Desktop, etc.)
2. Hold `Right Cmd + Right Option`
3. Speak
4. Release — the cleaned transcript pastes automatically within ~3 seconds

**Toggle mode** (for longer dictation): while holding the hotkey, tap `Space` to switch to toggle mode. Recording continues until you tap the hotkey again.

---

## CLI reference

```
./nlh setup              Interactive first-run wizard
./nlh start              Register hotkey daemon and start background services
./nlh stop               Stop all services
./nlh status             Daemon state, model paths, last 5 captures
./nlh log                Last 25 captures, numbered newest-first (scrollable)
./nlh log -a             Full history, paginated
./nlh open <n>           Open capture #n in $EDITOR
./nlh open -b <n>        Render capture #n as HTML and open in browser
./nlh open               Interactive fzf picker (requires fzf)
./nlh clear              Delete captures older than: 1 day | 7 days | 2 weeks | all
./nlh config             Open ~/.nlh/config in $EDITOR
```

---

## Capture log

Every capture is saved in two places:

- **`~/.nlh/captures/YYYY-MM-DDTHH-MM-SS.md`** — individual Markdown file with the refined transcript, duration, and raw Whisper output
- **`~/.nlh/captures.log`** — flat index: `[HH:MM:SS]  [Xs]  transcript text`

Errors are written to `~/.nlh/error.log`.

---

## Config reference

`~/.nlh/config` is a plain `KEY=VALUE` file. Edit it with `./nlh config` or directly in any text editor. Changes take effect on the next capture — no restart needed.

| Key | Default | Description |
|-----|---------|-------------|
| `whisper_model_path` | _(required)_ | Path to GGML model file |
| `hotkey` | `rcmd + ralt` | skhd hotkey chord |
| `llm_backend` | `ollama` | `ollama`, `llama.cpp`, or `transformers` |
| `llm_model_path` | `llama3` | Model identifier (ollama) or path (llama.cpp/transformers) |
| `llm_script_path` | `scripts/llm_refine.py` | Path to Python wrapper (transformers backend only) |
| `llm_system_prompt` | _(see below)_ | System prompt sent to the LLM on every capture |
| `log_path` | `~/.nlh/captures.log` | Path to the flat index log |
| `max_duration` | `300` | Maximum recording length in seconds |

**Default system prompt:**
> You are a transcript cleaner. Remove filler words (um, uh, like, you know), false starts, and self-corrections. Fix punctuation and capitalisation. Preserve all technical terms, proper nouns, and code identifiers exactly as spoken. Output only the cleaned transcript — no commentary, no explanations.

---

## LLM backends

### ollama (default)
Easiest to set up. Runs as a background service.
```
llm_backend=ollama
llm_model_path=llama3
```

### llama.cpp
No separate daemon. Requires a GGUF model file.
```bash
brew install llama.cpp
# download a GGUF model, e.g. from huggingface.co
llm_backend=llama.cpp
llm_model_path=/path/to/model.gguf
```

### transformers (HuggingFace)
Requires a Python environment.
```bash
pip install transformers torch
# download a model via huggingface-cli
llm_backend=transformers
llm_model_path=/path/to/model/directory
```

---

## Stop and uninstall

```bash
./nlh stop        # stops skhd and ollama services
```

To remove all nlh data:
```bash
rm -rf ~/.nlh
```

To remove the skhd hotkey bindings, open `~/.skhdrc` and delete the lines added by `nlh setup` (marked with `# nlh push-to-talk`).

---

## Troubleshooting

**Hotkey does nothing**
- Check Accessibility permission: System Settings → Privacy & Security → Accessibility → skhd must be listed and enabled
- Check skhd is running: `./nlh status`
- Check `~/.skhdrc` contains the nlh bindings: `cat ~/.skhdrc`

**Paste happens but clipboard is wrong / garbled**
- Check `~/.nlh/error.log` for LLM or whisper errors
- Confirm `whisper_model_path` points to a valid `.bin` file: `./nlh status`

**No paste, no error**
- Whisper may have returned empty output (silence or very short recording) — this is discarded silently by design
- Try holding the hotkey for at least 1 second before speaking

**ollama not responding**
- Run `./nlh start` again — it will re-register the service
- Check directly: `ollama list`

**`nlh start` says skhd not found**
```bash
brew install koekeishiya/formulae/skhd
```

---

## Security

- **Microphone and Accessibility** are the only elevated permissions required, both granted explicitly via System Settings.
- **No network calls at runtime.** All transcription and LLM inference happens on-device.
- **Audio is never persisted.** The temp WAV file is deleted immediately after transcription.
- **Clipboard safety.** Your clipboard contents are saved before paste and restored after. If a crash occurs mid-paste, the original is written to `~/.nlh/clipboard.bak`.
- **skhd** listens only for the configured hotkey chord — it does not log or buffer arbitrary keystrokes.
