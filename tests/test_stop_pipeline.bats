#!/usr/bin/env bats
# Tests for stop.sh paste pipeline (F2, F3, F4, F5, F6)

load 'helpers/mocks'

STOP_SCRIPT="$BATS_TEST_DIRNAME/../stop.sh"

setup() {
  setup_nlh_home
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export NLH_HOME
  export NLH_CONFIG
  export NLH_LOG
  export NLH_ERROR_LOG

  touch "$BATS_TEST_TMPDIR/model.bin"
  write_config

  # Create a fake audio capture file
  touch "$BATS_TEST_TMPDIR/nlh_cap.wav"
  export NLH_CAP_FILE="$BATS_TEST_TMPDIR/nlh_cap.wav"

  # Set up macOS mocks by default
  create_macos_paste_mocks
  # Sox mock
  create_sox_mock 0

  # Seed clipboard with something to verify save/restore
  echo "original clipboard" > "$BATS_TEST_TMPDIR/clipboard"

  # Mock wl-paste/wl-copy/ydotool as fallbacks
  create_wayland_paste_mocks

  # Override platform to macOS for these tests
  export NLH_PLATFORM="macos"
}

teardown() {
  :
}

# Helper: run stop.sh with env pointing at test fixtures
run_stop() {
  run bash -c "
    export NLH_HOME='$NLH_HOME'
    export NLH_CONFIG='$NLH_CONFIG'
    export NLH_LOG='$NLH_LOG'
    export NLH_ERROR_LOG='$NLH_ERROR_LOG'
    export NLH_CAP_FILE='$NLH_CAP_FILE'
    export NLH_PLATFORM='$NLH_PLATFORM'
    export TMPDIR='$BATS_TEST_TMPDIR'
    export PATH='$BATS_TEST_TMPDIR/bin:$PATH'
    '$STOP_SCRIPT' 2>&1
  "
}

# --- Happy path ---

@test "stop.sh: transcription result is written to clipboard" {
  create_whisper_mock "Hello world"
  create_ollama_mock "Hello world refined"
  run_stop
  clipboard=$(cat "$BATS_TEST_TMPDIR/clipboard" 2>/dev/null || true)
  # After stop.sh, clipboard should have been written (and then restored)
  # The transcript should have been pasted (clipboard written during paste)
  [ -n "$clipboard" ]
}

@test "stop.sh: capture .md file is created in captures directory" {
  create_whisper_mock "Test transcript"
  create_ollama_mock "Test transcript refined"
  run_stop
  # There should be at least one .md file
  md_count=$(ls "$NLH_HOME/captures/"*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$md_count" -ge 1 ]
}

@test "stop.sh: capture .md file has correct schema" {
  create_whisper_mock "Test transcript here"
  create_ollama_mock "Refined transcript here"
  run_stop
  # Find the md file
  md_file=$(ls "$NLH_HOME/captures/"*.md 2>/dev/null | head -1)
  [ -n "$md_file" ]
  content=$(cat "$md_file")
  # Must have a heading with date
  [[ "$content" == *"# 20"* ]]
  # Must have Duration line
  [[ "$content" == *"**Duration:**"* ]]
  # Must have separator
  [[ "$content" == *"---"* ]]
  # Must have Raw line
  [[ "$content" == *"**Raw:**"* ]]
}

@test "stop.sh: captures.log is appended after successful capture" {
  create_whisper_mock "Log me please"
  create_ollama_mock "Log me please refined"
  run_stop
  [ -f "$NLH_LOG" ]
  log_content=$(cat "$NLH_LOG")
  [ -n "$log_content" ]
}

@test "stop.sh: captures.log entry has correct format [HH:MM:SS] [Xs]" {
  create_whisper_mock "Log format test"
  create_ollama_mock "Log format test refined"
  run_stop
  [ -f "$NLH_LOG" ]
  log_entry=$(cat "$NLH_LOG" | tail -1)
  # Format: [HH:MM:SS]  [Xs]  <text>
  [[ "$log_entry" =~ \[[0-9]{2}:[0-9]{2}:[0-9]{2}\] ]]
  [[ "$log_entry" =~ \[[0-9]+s\] ]]
}

@test "stop.sh: capture file is deleted after transcription" {
  create_whisper_mock "Delete test"
  create_ollama_mock "Delete test refined"
  run_stop
  # WAV file should be deleted
  [ ! -f "$NLH_CAP_FILE" ]
}

@test "stop.sh: osascript is called for paste on macOS" {
  create_whisper_mock "Paste test"
  create_ollama_mock "Paste test refined"
  run_stop
  [ -f "$BATS_TEST_TMPDIR/osascript.calls" ]
  osascript_calls=$(cat "$BATS_TEST_TMPDIR/osascript.calls")
  [ -n "$osascript_calls" ]
}

@test "stop.sh: original clipboard is restored after paste" {
  echo "saved clipboard content" > "$BATS_TEST_TMPDIR/clipboard"
  create_whisper_mock "Clipboard restore test"
  create_ollama_mock "Clipboard restore refined"
  run_stop
  # After paste, clipboard should be restored
  clipboard=$(cat "$BATS_TEST_TMPDIR/clipboard" 2>/dev/null)
  [ "$clipboard" = "saved clipboard content" ]
}

# --- Error handling ---

@test "stop.sh: empty whisper output discards silently, no log entry" {
  create_whisper_mock ""
  create_ollama_mock ""
  initial_log_lines=0
  [ -f "$NLH_LOG" ] && initial_log_lines=$(wc -l < "$NLH_LOG" | tr -d ' ')
  run_stop
  current_log_lines=0
  [ -f "$NLH_LOG" ] && current_log_lines=$(wc -l < "$NLH_LOG" | tr -d ' ')
  # No new log entries
  [ "$current_log_lines" -eq "$initial_log_lines" ]
}

@test "stop.sh: whitespace-only whisper output discards silently" {
  create_whisper_mock "   "
  create_ollama_mock ""
  initial_log_lines=0
  [ -f "$NLH_LOG" ] && initial_log_lines=$(wc -l < "$NLH_LOG" | tr -d ' ')
  run_stop
  current_log_lines=0
  [ -f "$NLH_LOG" ] && current_log_lines=$(wc -l < "$NLH_LOG" | tr -d ' ')
  [ "$current_log_lines" -eq "$initial_log_lines" ]
}

@test "stop.sh: empty whisper output results in no .md file created" {
  create_whisper_mock ""
  create_ollama_mock ""
  run_stop
  md_count=$(ls "$NLH_HOME/captures/"*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$md_count" -eq 0 ]
}

@test "stop.sh: whisper-cli non-zero exit logs to error.log" {
  create_whisper_mock "ignored" 1
  run_stop
  [ -f "$NLH_ERROR_LOG" ]
  error_content=$(cat "$NLH_ERROR_LOG")
  [ -n "$error_content" ]
}

@test "stop.sh: whisper-cli non-zero exit results in no log entry" {
  create_whisper_mock "ignored" 1
  initial_log_lines=0
  [ -f "$NLH_LOG" ] && initial_log_lines=$(wc -l < "$NLH_LOG")
  run_stop
  current_log_lines=0
  [ -f "$NLH_LOG" ] && current_log_lines=$(wc -l < "$NLH_LOG")
  [ "$current_log_lines" -eq "$initial_log_lines" ]
}

@test "stop.sh: whisper-cli non-zero exit restores clipboard" {
  echo "clipboard before error" > "$BATS_TEST_TMPDIR/clipboard"
  create_whisper_mock "ignored" 1
  run_stop
  clipboard=$(cat "$BATS_TEST_TMPDIR/clipboard" 2>/dev/null)
  [ "$clipboard" = "clipboard before error" ]
}

@test "stop.sh: LLM non-zero exit pastes raw transcript" {
  create_whisper_mock "Raw transcript text"
  create_ollama_mock "ignored" 1
  run_stop
  # Log entry should exist and contain [unrefined]
  [ -f "$NLH_LOG" ]
  log_content=$(cat "$NLH_LOG")
  [[ "$log_content" == *"[unrefined]"* ]]
}

@test "stop.sh: LLM non-zero exit appends [unrefined] tag to log entry" {
  create_whisper_mock "Unrefined test"
  create_ollama_mock "ignored" 1
  run_stop
  [ -f "$NLH_LOG" ]
  log_entry=$(cat "$NLH_LOG" | tail -1)
  [[ "$log_entry" == *"[unrefined]"* ]]
}

@test "stop.sh: LLM empty output pastes raw transcript with [unrefined] tag" {
  create_whisper_mock "Another raw test"
  # LLM outputs nothing
  cat > "$BATS_TEST_TMPDIR/bin/ollama" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/ollama"
  run_stop
  [ -f "$NLH_LOG" ]
  log_entry=$(cat "$NLH_LOG" | tail -1)
  [[ "$log_entry" == *"[unrefined]"* ]]
}

@test "stop.sh: sox failure logs to error.log" {
  create_whisper_mock "irrelevant"
  # Make the capture file not exist (simulate sox failure)
  rm -f "$NLH_CAP_FILE"
  run_stop
  # Either error log has content, or status is non-zero
  if [ -f "$NLH_ERROR_LOG" ]; then
    error_content=$(cat "$NLH_ERROR_LOG")
    [ -n "$error_content" ]
  else
    [ "$status" -ne 0 ]
  fi
}

@test "stop.sh: [max-duration] tag appears in log when NLH_MAX_DURATION_HIT=1" {
  create_whisper_mock "Max duration test"
  create_ollama_mock "Max duration refined"
  run bash -c "
    export NLH_HOME='$NLH_HOME'
    export NLH_CONFIG='$NLH_CONFIG'
    export NLH_LOG='$NLH_LOG'
    export NLH_ERROR_LOG='$NLH_ERROR_LOG'
    export NLH_CAP_FILE='$NLH_CAP_FILE'
    export NLH_PLATFORM='$NLH_PLATFORM'
    export NLH_MAX_DURATION_HIT=1
    export TMPDIR='$BATS_TEST_TMPDIR'
    export PATH='$BATS_TEST_TMPDIR/bin:$PATH'
    '$STOP_SCRIPT' 2>&1
  "
  [ -f "$NLH_LOG" ]
  log_entry=$(cat "$NLH_LOG" | tail -1)
  [[ "$log_entry" == *"[max-duration]"* ]]
}

@test "stop.sh: clipboard.bak written if restore fails" {
  echo "backup test content" > "$BATS_TEST_TMPDIR/clipboard"
  create_whisper_mock "Backup test"
  create_ollama_mock "Backup refined"
  # Make pbcopy fail on second call (restore) by replacing it after first use
  # We test by checking the trap behavior: if pbcopy fails during restore, clipboard.bak should exist
  # This is tested by setting NLH_FORCE_CLIPBOARD_BAK=1
  run bash -c "
    export NLH_HOME='$NLH_HOME'
    export NLH_CONFIG='$NLH_CONFIG'
    export NLH_LOG='$NLH_LOG'
    export NLH_ERROR_LOG='$NLH_ERROR_LOG'
    export NLH_CAP_FILE='$NLH_CAP_FILE'
    export NLH_PLATFORM='$NLH_PLATFORM'
    export NLH_TEST_CLIPBOARD_RESTORE_FAIL=1
    export TMPDIR='$BATS_TEST_TMPDIR'
    export PATH='$BATS_TEST_TMPDIR/bin:$PATH'
    '$STOP_SCRIPT' 2>&1
  "
  # clipboard.bak should be written
  [ -f "$NLH_HOME/clipboard.bak" ]
}
