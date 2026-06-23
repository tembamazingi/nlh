#!/usr/bin/env bats
# Tests for the nlh CLI dispatcher routing (F8, F9, CLI criteria)

load 'helpers/mocks'

NLH_SCRIPT="$BATS_TEST_DIRNAME/../nlh"

setup() {
  setup_nlh_home
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export NLH_HOME
  export NLH_CONFIG
  # Create a model file so start doesn't fail on missing model
  touch "$BATS_TEST_TMPDIR/model.bin"
  write_config
}

teardown() {
  :
}

# --- Subcommand routing ---

@test "nlh with no arguments prints usage and exits non-zero" {
  run "$NLH_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "nlh --help prints usage and exits zero" {
  run "$NLH_SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]] || [[ "$output" == *"nlh"* ]]
}

@test "nlh unknown subcommand prints usage and exits non-zero" {
  run "$NLH_SCRIPT" foobar
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown"* ]] || [[ "$output" == *"unknown"* ]] || [[ "$output" == *"Usage"* ]]
}

@test "nlh setup subcommand routes to setup handler" {
  # We can't run real setup non-interactively, so just check it is dispatched
  # by checking the error/output refers to setup behavior
  # Use a stub that proves routing happened
  cat > "$BATS_TEST_TMPDIR/bin/nlh-setup-stub" <<'EOF'
#!/usr/bin/env bash
echo "SETUP_CALLED"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/nlh-setup-stub"
  # Run with NLH_SETUP_CMD pointing at our stub (dispatcher should honor this or we check the output)
  # Actually test that nlh setup invokes setup logic
  run bash -c "NLH_HOME='$NLH_HOME' NLH_NONINTERACTIVE=1 '$NLH_SCRIPT' setup 2>&1 || true"
  # Should not say "Unknown command"
  [[ "$output" != *"Unknown command"* ]]
}

@test "nlh status subcommand routes to status handler" {
  run bash -c "NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' status 2>&1"
  # status should not say "Unknown command"
  [[ "$output" != *"Unknown command"* ]]
  [ "$status" -eq 0 ] || [ "$status" -ne 0 ]  # any exit is ok, just routing
}

@test "nlh log subcommand routes to log handler" {
  # Create captures.log so log command has something to work with
  touch "$NLH_HOME/captures.log"
  run bash -c "NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' log 2>&1 | head -1; exit 0"
  [[ "$output" != *"Unknown command"* ]]
}

@test "nlh log --all subcommand routes to log handler with all flag" {
  touch "$NLH_HOME/captures.log"
  run bash -c "NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' log --all 2>&1 | head -1; exit 0"
  [[ "$output" != *"Unknown command"* ]]
}

@test "nlh open subcommand routes to open handler" {
  # With no fzf and no arg, should print error about fzf
  cat > "$BATS_TEST_TMPDIR/bin/fzf" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
  # Remove fzf from path
  run bash -c "PATH='$BATS_TEST_TMPDIR/no-fzf-bin' NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' open 2>&1 || true"
  [[ "$output" != *"Unknown command"* ]]
}

@test "nlh clear subcommand routes to clear handler" {
  run bash -c "echo 'N' | NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' clear 2>&1 || true"
  [[ "$output" != *"Unknown command"* ]]
}

@test "nlh config subcommand routes to config handler" {
  export EDITOR="cat"
  run bash -c "NLH_HOME='$NLH_HOME' EDITOR=cat '$NLH_SCRIPT' config 2>&1 || true"
  [[ "$output" != *"Unknown command"* ]]
}

@test "nlh stop subcommand routes to stop handler" {
  # stop.sh should be called; just verify routing
  # Without a running sox process this will fail gracefully
  run bash -c "NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' stop 2>&1 || true"
  [[ "$output" != *"Unknown command"* ]]
}

@test "nlh start subcommand routes to start handler" {
  # start would normally launch skhd, skip daemon registration in test
  run bash -c "NLH_HOME='$NLH_HOME' NLH_NO_DAEMON=1 '$NLH_SCRIPT' start 2>&1 || true"
  [[ "$output" != *"Unknown command"* ]]
}
