#!/usr/bin/env bash
# start.sh — nlh keydown handler
# Begins audio capture via sox from the default microphone at 16 kHz mono.
# Stops automatically after max_duration seconds (default: 300).
# Sets NLH_MAX_DURATION_HIT=1 if max duration is reached, then calls stop.sh.

set -uo pipefail

NLH_HOME="${NLH_HOME:-$HOME/.nlh}"
NLH_CONFIG="${NLH_CONFIG:-$NLH_HOME/config}"

# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load config
if [[ -f "$NLH_CONFIG" ]]; then
  # shellcheck source=/dev/null
  source "$NLH_CONFIG"
fi

whisper_model_path="${whisper_model_path:-}"
max_duration="${max_duration:-300}"

# Validate model path
if [[ -n "$whisper_model_path" ]] && [[ ! -f "$whisper_model_path" ]]; then
  echo "nlh: whisper model not found: $whisper_model_path" >&2
  echo "nlh: run 'nlh setup' to configure the model path." >&2
  exit 1
fi

NLH_CAP_FILE="${NLH_CAP_FILE:-${TMPDIR:-/tmp}/nlh_cap.wav}"
NLH_ERROR_LOG="${NLH_ERROR_LOG:-$NLH_HOME/error.log}"

# Start recording
if ! sox -d -r 16000 -c 1 -b 16 -e signed-integer "$NLH_CAP_FILE" \
     trim 0 "$max_duration" 2>/dev/null; then
  sox_exit=$?
  if [[ "$sox_exit" -eq 1 ]]; then
    # sox exits 1 on normal termination (killed by stop.sh) or timeout
    # Check if the file was actually created
    if [[ ! -f "$NLH_CAP_FILE" ]] || [[ ! -s "$NLH_CAP_FILE" ]]; then
      mkdir -p "$(dirname "$NLH_ERROR_LOG")"
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] sox failed: microphone unavailable or device error" >> "$NLH_ERROR_LOG"
      exit 1
    fi
  fi
fi

# Check if max duration was reached
if [[ -f "$NLH_CAP_FILE" ]]; then
  actual_duration=$(sox "$NLH_CAP_FILE" --info -D 2>/dev/null || echo "0")
  # If duration is >= max_duration - 1, consider it a max-duration hit
  if (( $(echo "$actual_duration >= $max_duration - 1" | bc -l 2>/dev/null || echo 0) )); then
    export NLH_MAX_DURATION_HIT=1
  fi
fi
