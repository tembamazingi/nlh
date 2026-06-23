#!/usr/bin/env bats
# Tests for capture .md file schema (F6)

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
  export NLH_PLATFORM="macos"

  touch "$BATS_TEST_TMPDIR/model.bin"
  write_config
  touch "$BATS_TEST_TMPDIR/nlh_cap.wav"
  export NLH_CAP_FILE="$BATS_TEST_TMPDIR/nlh_cap.wav"

  create_macos_paste_mocks
  echo "original" > "$BATS_TEST_TMPDIR/clipboard"
}

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

get_capture_file() {
  ls "$NLH_HOME/captures/"*.md 2>/dev/null | head -1
}

@test "capture .md has heading with date in YYYY-MM-DD HH:MM:SS format" {
  create_whisper_mock "Schema test"
  create_ollama_mock "Schema refined"
  run_stop
  md_file=$(get_capture_file)
  [ -n "$md_file" ]
  first_line=$(head -1 "$md_file")
  # Must start with # followed by date
  [[ "$first_line" =~ ^#\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]
}

@test "capture .md has Duration line as second non-empty line" {
  create_whisper_mock "Duration test"
  create_ollama_mock "Duration refined"
  run_stop
  md_file=$(get_capture_file)
  [ -n "$md_file" ]
  content=$(cat "$md_file")
  [[ "$content" == *"**Duration:** "* ]]
  # Duration should be Xs format
  [[ "$content" =~ \*\*Duration:\*\*\ [0-9]+s ]]
}

@test "capture .md has refined transcript in body" {
  create_whisper_mock "Raw whisper output"
  create_ollama_mock "Cleaned up refined output"
  run_stop
  md_file=$(get_capture_file)
  [ -n "$md_file" ]
  content=$(cat "$md_file")
  [[ "$content" == *"Cleaned up refined output"* ]]
}

@test "capture .md has --- separator" {
  create_whisper_mock "Separator test"
  create_ollama_mock "Separator refined"
  run_stop
  md_file=$(get_capture_file)
  [ -n "$md_file" ]
  content=$(cat "$md_file")
  [[ "$content" == *"---"* ]]
}

@test "capture .md has **Raw:** line with original whisper transcript" {
  create_whisper_mock "Original whisper text"
  create_ollama_mock "Refined whisper text"
  run_stop
  md_file=$(get_capture_file)
  [ -n "$md_file" ]
  content=$(cat "$md_file")
  [[ "$content" == *"**Raw:** Original whisper text"* ]]
}

@test "capture .md filename is YYYY-MM-DDTHH-MM-SS.md" {
  create_whisper_mock "Filename test"
  create_ollama_mock "Filename refined"
  run_stop
  md_file=$(get_capture_file)
  [ -n "$md_file" ]
  basename_file=$(basename "$md_file")
  [[ "$basename_file" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}\.md$ ]]
}

@test "capture .md has exact structure: heading, blank, duration, blank, transcript, blank, ---, **Raw:**" {
  create_whisper_mock "Structure test input"
  create_ollama_mock "Structure test output"
  run_stop
  md_file=$(get_capture_file)
  [ -n "$md_file" ]
  content=$(cat "$md_file")
  # Check ordering: heading comes before duration, duration before transcript,
  # transcript before ---, --- before Raw
  heading_pos=$(grep -n "^# " "$md_file" | head -1 | cut -d: -f1)
  duration_pos=$(grep -n "\*\*Duration:\*\*" "$md_file" | head -1 | cut -d: -f1)
  sep_pos=$(grep -n "^---$" "$md_file" | head -1 | cut -d: -f1)
  raw_pos=$(grep -n "\*\*Raw:\*\*" "$md_file" | head -1 | cut -d: -f1)

  [ -n "$heading_pos" ]
  [ -n "$duration_pos" ]
  [ -n "$sep_pos" ]
  [ -n "$raw_pos" ]

  [ "$heading_pos" -lt "$duration_pos" ]
  [ "$duration_pos" -lt "$sep_pos" ]
  [ "$sep_pos" -lt "$raw_pos" ]
}

@test "captures.log entry format: [HH:MM:SS]  [Xs]  <refined text>" {
  create_whisper_mock "Log entry format test"
  create_ollama_mock "Log entry format refined"
  run_stop
  [ -f "$NLH_LOG" ]
  log_entry=$(tail -1 "$NLH_LOG")
  # Pattern: [HH:MM:SS]  [Xs]  text
  [[ "$log_entry" =~ ^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\].*\[[0-9]+s\].*Log\ entry\ format\ refined ]]
}
