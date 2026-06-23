#!/usr/bin/env bash
# start.sh — nlh keydown handler
# Begins audio capture via sox from the default microphone at 16 kHz mono.
# Stops automatically after max_duration seconds (default: 300).
# On max-duration timeout, writes a flag file and invokes stop.sh directly.

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
# Flag file used to signal max-duration to stop.sh (env vars don't cross process boundaries)
NLH_MAX_DURATION_FLAG="${NLH_MAX_DURATION_FLAG:-${TMPDIR:-/tmp}/nlh_max_duration}"

# Remove any stale flag from a previous session
rm -f "$NLH_MAX_DURATION_FLAG"

# Start recording; sox exits 0 when trim endpoint reached (max_duration), non-zero on error
sox_exit=0
sox -d -r 16000 -c 1 -b 16 -e signed-integer "$NLH_CAP_FILE" \
    trim 0 "$max_duration" 2>/dev/null || sox_exit=$?

if [[ $sox_exit -ne 0 ]]; then
  # sox exits non-zero on mic error or when killed by the hotkey keyup (normal stop).
  # Distinguish: if the capture file is missing or empty, it's a real mic error.
  if [[ ! -f "$NLH_CAP_FILE" ]] || [[ ! -s "$NLH_CAP_FILE" ]]; then
    mkdir -p "$(dirname "$NLH_ERROR_LOG")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] sox failed: microphone unavailable or device error" >> "$NLH_ERROR_LOG"
    exit 1
  fi
  # Non-zero with a valid file = killed by keyup; stop.sh handles the rest via skhd keyup event.
  exit 0
fi

# sox exited 0 = trim endpoint reached = max duration hit.
# Write flag file so stop.sh can detect this across the process boundary, then invoke stop.sh.
touch "$NLH_MAX_DURATION_FLAG"
NLH_HOME="$NLH_HOME" NLH_CONFIG="$NLH_CONFIG" \
  NLH_CAP_FILE="$NLH_CAP_FILE" \
  NLH_MAX_DURATION_FLAG="$NLH_MAX_DURATION_FLAG" \
  "$SCRIPT_DIR/stop.sh"
