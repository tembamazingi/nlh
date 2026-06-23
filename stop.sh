#!/usr/bin/env bash
# stop.sh — nlh keyup handler
# Stops audio capture, transcribes, refines, pastes, and logs.
#
# Environment variables (all have defaults derived from ~/.nlh/config):
#   NLH_HOME         — base dir (default: ~/.nlh)
#   NLH_CONFIG       — config file path
#   NLH_LOG          — captures.log path
#   NLH_ERROR_LOG    — error.log path
#   NLH_CAP_FILE     — path to WAV capture file
#   NLH_PLATFORM     — macos|x11|wayland (auto-detected if unset)
#   NLH_MAX_DURATION_FLAG — path to flag file written by start.sh on timeout
#   NLH_MAX_DURATION_HIT — set to 1 if max duration was reached (legacy/test override)
#   NLH_TEST_CLIPBOARD_RESTORE_FAIL — set to 1 to test clipboard.bak path

set -uo pipefail

# ── Defaults ────────────────────────────────────────────────────────────────
NLH_HOME="${NLH_HOME:-$HOME/.nlh}"
NLH_CONFIG="${NLH_CONFIG:-$NLH_HOME/config}"
NLH_LOG="${NLH_LOG:-$NLH_HOME/captures.log}"
NLH_ERROR_LOG="${NLH_ERROR_LOG:-$NLH_HOME/error.log}"
NLH_CAP_FILE="${NLH_CAP_FILE:-${TMPDIR:-/tmp}/nlh_cap.wav}"
NLH_MAX_DURATION_FLAG="${NLH_MAX_DURATION_FLAG:-${TMPDIR:-/tmp}/nlh_max_duration}"
NLH_MAX_DURATION_HIT="${NLH_MAX_DURATION_HIT:-0}"
NLH_TEST_CLIPBOARD_RESTORE_FAIL="${NLH_TEST_CLIPBOARD_RESTORE_FAIL:-0}"

# Check flag file written by start.sh (env vars don't cross skhd process boundaries)
if [[ -f "$NLH_MAX_DURATION_FLAG" ]]; then
  NLH_MAX_DURATION_HIT=1
  rm -f "$NLH_MAX_DURATION_FLAG"
fi

# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Load config ──────────────────────────────────────────────────────────────
if [[ -f "$NLH_CONFIG" ]]; then
  # shellcheck source=/dev/null
  source "$NLH_CONFIG"
fi

whisper_model_path="${whisper_model_path:-}"
llm_backend="${llm_backend:-ollama}"
llm_model_path="${llm_model_path:-llama3}"
llm_script_path="${llm_script_path:-}"
llm_system_prompt="${llm_system_prompt:-You are a transcript cleaner. Remove filler words (um, uh, like, you know), false starts, and self-corrections. Fix punctuation and capitalisation. Preserve all technical terms, proper nouns, and code identifiers exactly as spoken. Output only the cleaned transcript — no commentary, no explanations.}"
log_path="${log_path:-$NLH_LOG}"
max_duration="${max_duration:-300}"

# Use log_path from config if set
NLH_LOG="$log_path"

# ── Helpers ──────────────────────────────────────────────────────────────────
log_error() {
  local msg="$1"
  mkdir -p "$(dirname "$NLH_ERROR_LOG")"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$NLH_ERROR_LOG"
}

detect_platform() {
  if [[ -n "${NLH_PLATFORM:-}" ]]; then
    echo "$NLH_PLATFORM"
    return
  fi
  if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    echo "wayland"
    return
  fi
  if [[ -n "${DISPLAY:-}" ]]; then
    echo "x11"
    return
  fi
  if command -v pbcopy &>/dev/null; then
    echo "macos"
    return
  fi
  if command -v wl-copy &>/dev/null; then
    echo "wayland"
    return
  fi
  if command -v xclip &>/dev/null; then
    echo "x11"
    return
  fi
  echo "macos"  # default fallback
}

PLATFORM=$(detect_platform)

clipboard_read() {
  case "$PLATFORM" in
    macos)   pbpaste ;;
    x11)     xclip -selection clipboard -o ;;
    wayland) wl-paste ;;
    *)
      log_error "clipboard_read: unrecognised platform '$PLATFORM'"
      return 1
      ;;
  esac
}

clipboard_write() {
  case "$PLATFORM" in
    macos)   printf '%s' "$1" | pbcopy ;;
    x11)     printf '%s' "$1" | xclip -selection clipboard ;;
    wayland) printf '%s' "$1" | wl-copy ;;
    *)
      log_error "clipboard_write: unrecognised platform '$PLATFORM'"
      return 1
      ;;
  esac
}

do_paste() {
  case "$PLATFORM" in
    macos)
      osascript -e 'tell application "System Events" to keystroke "v" using command down' || {
        log_error "Paste target unavailable (osascript failed)"
      }
      ;;
    x11)
      xdotool key --clearmodifiers ctrl+v || {
        log_error "Paste target unavailable (xdotool failed)"
      }
      ;;
    wayland)
      ydotool key 29:1 47:1 47:0 29:0 || {
        log_error "Paste target unavailable (ydotool failed)"
      }
      ;;
  esac
}

# ── Save original clipboard ──────────────────────────────────────────────────
original_clipboard=""
original_clipboard=$(clipboard_read 2>/dev/null || true)

# ── Trap for clipboard restoration ──────────────────────────────────────────
cleanup() {
  local exit_code=$?
  if [[ "$NLH_TEST_CLIPBOARD_RESTORE_FAIL" == "1" ]]; then
    # Simulate restore failure: write to clipboard.bak instead
    mkdir -p "$NLH_HOME"
    echo -n "$original_clipboard" > "$NLH_HOME/clipboard.bak"
  else
    clipboard_write "$original_clipboard" 2>/dev/null || {
      mkdir -p "$NLH_HOME"
      echo -n "$original_clipboard" > "$NLH_HOME/clipboard.bak"
    }
  fi
  # Clean up WAV file
  rm -f "$NLH_CAP_FILE"
  exit $exit_code
}
trap cleanup EXIT

# ── Validate capture file ────────────────────────────────────────────────────
if [[ ! -f "$NLH_CAP_FILE" ]]; then
  log_error "Capture file not found: $NLH_CAP_FILE (sox may have failed)"
  exit 1
fi

# ── Transcribe ───────────────────────────────────────────────────────────────
start_time=$(date +%s)

whisper_output=""
if ! whisper_output=$(whisper-cli --model "$whisper_model_path" --no-gpu -f "$NLH_CAP_FILE" 2>/dev/null); then
  log_error "whisper-cli failed (non-zero exit) for capture $NLH_CAP_FILE"
  exit 1
fi

end_time=$(date +%s)
duration=$(( end_time - start_time ))

# Strip leading/trailing whitespace from whisper output
whisper_text="${whisper_output#"${whisper_output%%[![:space:]]*}"}"
whisper_text="${whisper_text%"${whisper_text##*[![:space:]]}"}"

# Discard silently if empty
if [[ -z "$whisper_text" ]]; then
  exit 0
fi

# ── LLM Refinement ───────────────────────────────────────────────────────────
refined_text=""
unrefined=0

run_llm() {
  local input="$1"
  local output=""
  local llm_exit=0

  case "$llm_backend" in
    ollama)
      output=$(printf '%s' "$input" | timeout 10 ollama run "$llm_model_path" \
        --system "$llm_system_prompt" 2>/dev/null) || llm_exit=$?
      ;;
    llama.cpp)
      output=$(printf '%s' "$input" | timeout 10 llama-cli -m "$llm_model_path" \
        --prompt "$llm_system_prompt" --stdin 2>/dev/null) || llm_exit=$?
      ;;
    transformers)
      output=$(echo "$input" | timeout 10 \
        NLH_LLM_MODEL_PATH="$llm_model_path" \
        NLH_LLM_SYSTEM_PROMPT="$llm_system_prompt" \
        python3 "$llm_script_path" 2>/dev/null) || llm_exit=$?
      ;;
    *)
      llm_exit=1
      ;;
  esac

  if [[ $llm_exit -ne 0 ]] || [[ -z "$output" ]]; then
    echo "__UNREFINED__"
    return
  fi
  echo "$output"
}

llm_result=$(run_llm "$whisper_text")

if [[ "$llm_result" == "__UNREFINED__" ]]; then
  refined_text="$whisper_text"
  unrefined=1
else
  refined_text="$llm_result"
  unrefined=0
fi

# ── Write to clipboard and paste ─────────────────────────────────────────────
clipboard_write "$refined_text"
do_paste

# ── Write capture .md file ───────────────────────────────────────────────────
mkdir -p "$NLH_HOME/captures"
timestamp=$(date '+%Y-%m-%dT%H-%M-%S')
display_ts=$(date '+%Y-%m-%d %H:%M:%S')
capture_file="$NLH_HOME/captures/${timestamp}.md"

cat > "$capture_file" <<MDEOF
# $display_ts
**Duration:** ${duration}s

$refined_text

---
**Raw:** $whisper_text
MDEOF

# ── Append to captures.log ────────────────────────────────────────────────────
mkdir -p "$(dirname "$NLH_LOG")"
log_time=$(date '+%H:%M:%S')
log_tags=""
[[ "$unrefined" -eq 1 ]] && log_tags=" [unrefined]"
[[ "$NLH_MAX_DURATION_HIT" == "1" ]] && log_tags="$log_tags [max-duration]"
echo "[$log_time]  [${duration}s]  $refined_text$log_tags" >> "$NLH_LOG"
