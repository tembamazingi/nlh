#!/usr/bin/env bash
# Mock/stub helpers for nlh tests.
# Source this file in setup() to create stub commands in $BATS_TEST_TMPDIR/bin.

create_mock_bin() {
  local name="$1"
  local exit_code="${2:-0}"
  local output="${3:-}"
  local bin_dir="${4:-$BATS_TEST_TMPDIR/bin}"

  mkdir -p "$bin_dir"
  cat > "$bin_dir/$name" <<EOF
#!/usr/bin/env bash
${output:+echo "$output"}
exit $exit_code
EOF
  chmod +x "$bin_dir/$name"
}

# Create a mock that records its arguments
create_recording_mock() {
  local name="$1"
  local record_file="$2"
  local exit_code="${3:-0}"
  local output="${4:-}"
  local bin_dir="${5:-$BATS_TEST_TMPDIR/bin}"

  mkdir -p "$bin_dir"
  cat > "$bin_dir/$name" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$record_file"
${output:+echo "$output"}
exit $exit_code
EOF
  chmod +x "$bin_dir/$name"
}

# Create mock whisper-cli that outputs a transcript
# Note: pass the transcript as the first arg. Use "" explicitly for empty output.
# If no arg given, defaults to "Hello world".
create_whisper_mock() {
  # Use explicit sentinel to differentiate "not passed" from "empty string"
  local transcript="Hello world"
  if [[ $# -ge 1 ]]; then
    transcript="$1"
  fi
  local exit_code="${2:-0}"
  local bin_dir="${3:-$BATS_TEST_TMPDIR/bin}"

  mkdir -p "$bin_dir"
  # Write the transcript literally into the script
  cat > "$bin_dir/whisper-cli" <<MOCKEOF
#!/usr/bin/env bash
printf '%s\n' "$transcript"
exit $exit_code
MOCKEOF
  chmod +x "$bin_dir/whisper-cli"
}

# Create mock ollama
# Note: pass the refined text as the first arg. Use "" explicitly for empty output.
create_ollama_mock() {
  local refined="Refined text"
  if [[ $# -ge 1 ]]; then
    refined="$1"
  fi
  local exit_code="${2:-0}"
  local bin_dir="${3:-$BATS_TEST_TMPDIR/bin}"

  mkdir -p "$bin_dir"
  cat > "$bin_dir/ollama" <<MOCKEOF
#!/usr/bin/env bash
printf '%s\n' "$refined"
exit $exit_code
MOCKEOF
  chmod +x "$bin_dir/ollama"
}

# Create macOS paste mocks
create_macos_paste_mocks() {
  local bin_dir="${1:-$BATS_TEST_TMPDIR/bin}"
  mkdir -p "$bin_dir"

  # pbcopy: reads stdin, writes to clipboard file
  cat > "$bin_dir/pbcopy" <<'EOF'
#!/usr/bin/env bash
cat > "$BATS_TEST_TMPDIR/clipboard"
exit 0
EOF
  chmod +x "$bin_dir/pbcopy"

  # pbpaste: reads clipboard file
  cat > "$bin_dir/pbpaste" <<'EOF'
#!/usr/bin/env bash
cat "$BATS_TEST_TMPDIR/clipboard" 2>/dev/null || true
exit 0
EOF
  chmod +x "$bin_dir/pbpaste"

  # osascript: record calls
  cat > "$bin_dir/osascript" <<'EOF'
#!/usr/bin/env bash
echo "osascript $*" >> "$BATS_TEST_TMPDIR/osascript.calls"
exit 0
EOF
  chmod +x "$bin_dir/osascript"
}

# Create Linux X11 paste mocks
create_x11_paste_mocks() {
  local bin_dir="${1:-$BATS_TEST_TMPDIR/bin}"
  mkdir -p "$bin_dir"

  cat > "$bin_dir/xclip" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"-o"* ]]; then
  cat "$BATS_TEST_TMPDIR/clipboard" 2>/dev/null || true
else
  cat > "$BATS_TEST_TMPDIR/clipboard"
fi
exit 0
EOF
  chmod +x "$bin_dir/xclip"

  cat > "$bin_dir/xdotool" <<'EOF'
#!/usr/bin/env bash
echo "xdotool $*" >> "$BATS_TEST_TMPDIR/xdotool.calls"
exit 0
EOF
  chmod +x "$bin_dir/xdotool"
}

# Create Wayland paste mocks
create_wayland_paste_mocks() {
  local bin_dir="${1:-$BATS_TEST_TMPDIR/bin}"
  mkdir -p "$bin_dir"

  cat > "$bin_dir/wl-copy" <<'EOF'
#!/usr/bin/env bash
cat > "$BATS_TEST_TMPDIR/clipboard"
exit 0
EOF
  chmod +x "$bin_dir/wl-copy"

  cat > "$bin_dir/wl-paste" <<'EOF'
#!/usr/bin/env bash
cat "$BATS_TEST_TMPDIR/clipboard" 2>/dev/null || true
exit 0
EOF
  chmod +x "$bin_dir/wl-paste"

  cat > "$bin_dir/ydotool" <<'EOF'
#!/usr/bin/env bash
echo "ydotool $*" >> "$BATS_TEST_TMPDIR/ydotool.calls"
exit 0
EOF
  chmod +x "$bin_dir/ydotool"
}

# Create sox mock
create_sox_mock() {
  local exit_code="${1:-0}"
  local bin_dir="${2:-$BATS_TEST_TMPDIR/bin}"
  mkdir -p "$bin_dir"

  cat > "$bin_dir/sox" <<EOF
#!/usr/bin/env bash
# Create a dummy WAV file
touch "\${@: -1}"
exit $exit_code
EOF
  chmod +x "$bin_dir/sox"
}

setup_nlh_home() {
  export NLH_HOME="$BATS_TEST_TMPDIR/nlh_home"
  mkdir -p "$NLH_HOME/captures"
  export NLH_CONFIG="$NLH_HOME/config"
  export NLH_LOG="$NLH_HOME/captures.log"
  export NLH_ERROR_LOG="$NLH_HOME/error.log"
  export TMPDIR="$BATS_TEST_TMPDIR"
}

write_config() {
  local config_file="${1:-$BATS_TEST_TMPDIR/nlh_home/config}"
  cat > "$config_file" <<EOF
whisper_model_path=$BATS_TEST_TMPDIR/model.bin
hotkey=rcmd+ralt
llm_backend=ollama
llm_model_path=llama3
llm_script_path=$BATS_TEST_TMPDIR/llm_refine.py
llm_system_prompt="You are a transcript cleaner."
log_path=$BATS_TEST_TMPDIR/nlh_home/captures.log
max_duration=300
EOF
}
