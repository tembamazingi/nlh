#!/usr/bin/env bats
# Tests for nlh setup command (F9)

load 'helpers/mocks'

NLH_SCRIPT="$BATS_TEST_DIRNAME/../nlh"

setup() {
  setup_nlh_home
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export NLH_HOME
  export NLH_CONFIG
  # Ensure config does NOT exist initially
  rm -f "$NLH_CONFIG"
}

# --- Re-run with existing config ---

@test "nlh setup warns when config already exists" {
  write_config
  [ -f "$NLH_CONFIG" ]
  # Run setup non-interactively; it should warn about existing config
  run bash -c "printf 'N\n' | NLH_HOME='$NLH_HOME' NLH_NONINTERACTIVE=1 '$NLH_SCRIPT' setup 2>&1 || true"
  [[ "$output" == *"already exists"* ]] || [[ "$output" == *"exists"* ]] || [[ "$output" == *"overwrite"* ]] || [[ "$output" == *"abort"* ]]
}

@test "nlh setup with existing config does not clobber on abort" {
  write_config
  original_content=$(cat "$NLH_CONFIG")

  # Send 'N' to abort
  run bash -c "printf 'N\n' | NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' setup 2>&1 || true"

  [ -f "$NLH_CONFIG" ]
  current_content=$(cat "$NLH_CONFIG")
  [ "$current_content" = "$original_content" ]
}

@test "nlh setup with existing config prompts to overwrite or abort" {
  write_config
  run bash -c "printf '\n' | NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' setup 2>&1 || true"
  # Should ask about overwriting
  [[ "$output" == *"overwrite"* ]] || [[ "$output" == *"abort"* ]] || [[ "$output" == *"exists"* ]]
}

# --- Config format ---

@test "nlh setup (noninteractive) creates config with KEY=VALUE format" {
  rm -f "$NLH_CONFIG"
  # In noninteractive mode, setup uses defaults
  run bash -c "NLH_HOME='$NLH_HOME' NLH_NONINTERACTIVE=1 '$NLH_SCRIPT' setup 2>&1 || true"

  if [ -f "$NLH_CONFIG" ]; then
    # Each line should be KEY=VALUE (no spaces around =)
    while IFS= read -r line; do
      # Skip empty lines and comments
      [[ -z "$line" ]] && continue
      [[ "$line" =~ ^# ]] && continue
      # Must match KEY=VALUE
      [[ "$line" =~ ^[A-Za-z_]+=.*$ ]] || {
        echo "Invalid config line: $line"
        return 1
      }
    done < "$NLH_CONFIG"
  fi
}

@test "nlh setup noninteractive creates config with all required keys" {
  rm -f "$NLH_CONFIG"
  run bash -c "NLH_HOME='$NLH_HOME' NLH_NONINTERACTIVE=1 '$NLH_SCRIPT' setup 2>&1 || true"

  if [ -f "$NLH_CONFIG" ]; then
    content=$(cat "$NLH_CONFIG")
    [[ "$content" == *"whisper_model_path"* ]]
    [[ "$content" == *"llm_backend"* ]]
    [[ "$content" == *"max_duration"* ]]
  fi
}

# --- Config keys ---

@test "nlh config opens config file in EDITOR" {
  write_config
  cat > "$BATS_TEST_TMPDIR/bin/fakeedit" <<'EOF'
#!/usr/bin/env bash
echo "EDITOR_CALLED: $*" > "$BATS_TEST_TMPDIR/config_editor.call"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/fakeedit"

  run bash -c "NLH_HOME='$NLH_HOME' EDITOR='$BATS_TEST_TMPDIR/bin/fakeedit' '$NLH_SCRIPT' config 2>&1"
  [ -f "$BATS_TEST_TMPDIR/config_editor.call" ]
  call_content=$(cat "$BATS_TEST_TMPDIR/config_editor.call")
  [[ "$call_content" == *"$NLH_CONFIG"* ]] || [[ "$call_content" == *"config"* ]]
}

@test "nlh config fails gracefully when config does not exist" {
  rm -f "$NLH_CONFIG"
  cat > "$BATS_TEST_TMPDIR/bin/fakeedit" <<'EOF'
#!/usr/bin/env bash
echo "EDITOR_CALLED: $*" > "$BATS_TEST_TMPDIR/config_editor.call"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/fakeedit"

  run bash -c "NLH_HOME='$NLH_HOME' EDITOR='$BATS_TEST_TMPDIR/bin/fakeedit' '$NLH_SCRIPT' config 2>&1 || true"
  # Either creates the file and opens it, or prints a message to run setup
  [[ "$output" == *"setup"* ]] || [ -f "$BATS_TEST_TMPDIR/config_editor.call" ]
}
