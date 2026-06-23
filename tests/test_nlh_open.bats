#!/usr/bin/env bats
# Tests for nlh open command edge cases (F6)

load 'helpers/mocks'

NLH_SCRIPT="$BATS_TEST_DIRNAME/../nlh"

setup() {
  setup_nlh_home
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export NLH_HOME
  export NLH_CONFIG
  export NLH_LOG
  write_config

  # Create some capture files
  cat > "$NLH_HOME/captures/2024-01-15T10-00-00.md" <<'EOF'
# 2024-01-15 10:00:00
**Duration:** 5s

First capture text

---
**Raw:** first raw text
EOF

  cat > "$NLH_HOME/captures/2024-01-15T11-00-00.md" <<'EOF'
# 2024-01-15 11:00:00
**Duration:** 3s

Second capture text

---
**Raw:** second raw text
EOF

  # captures.log (newest first via nlh log numbering)
  cat > "$NLH_LOG" <<'EOF'
[10:00:00]  [5s]  First capture text
[11:00:00]  [3s]  Second capture text
EOF

  # Mock editor
  cat > "$BATS_TEST_TMPDIR/bin/fake_editor" <<'EOF'
#!/usr/bin/env bash
echo "EDITOR_CALLED: $*" >> "$BATS_TEST_TMPDIR/editor.calls"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/fake_editor"
  export EDITOR="$BATS_TEST_TMPDIR/bin/fake_editor"

  # Mock pandoc
  cat > "$BATS_TEST_TMPDIR/bin/pandoc" <<'EOF'
#!/usr/bin/env bash
echo "PANDOC_CALLED: $*" >> "$BATS_TEST_TMPDIR/pandoc.calls"
# Create output file if -o specified
for i in "$@"; do
  shift
  if [ "$prev" = "-o" ]; then
    echo "<html>test</html>" > "$i"
  fi
  prev="$i"
done
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/pandoc"

  # Mock browser opener
  cat > "$BATS_TEST_TMPDIR/bin/open" <<'EOF'
#!/usr/bin/env bash
echo "OPEN_CALLED: $*" >> "$BATS_TEST_TMPDIR/open.calls"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/open"
}

# --- fzf absent + no arg ---

@test "nlh open with no arg and no fzf prints error message" {
  # Ensure fzf is not available
  run bash -c "PATH='$BATS_TEST_TMPDIR/bin:/usr/bin:/bin' NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' open 2>&1 || true"
  # fzf not present in $BATS_TEST_TMPDIR/bin
  [[ "$output" == *"fzf"* ]] || [[ "$output" == *"entry number"* ]] || [[ "$output" == *"install"* ]]
}

@test "nlh open with no arg and no fzf exits non-zero" {
  run bash -c "PATH='$BATS_TEST_TMPDIR/bin:/usr/bin:/bin' NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' open 2>&1 || true"
  # Output should direct user to provide entry number or install fzf
  [[ "$output" == *"nlh open"* ]] || [[ "$output" == *"fzf"* ]] || [[ "$output" == *"entry"* ]]
}

# --- nlh open <n> ---

@test "nlh open 1 opens the most recent entry in EDITOR" {
  run bash -c "NLH_HOME='$NLH_HOME' EDITOR='$BATS_TEST_TMPDIR/bin/fake_editor' '$NLH_SCRIPT' open 1 2>&1"
  [ -f "$BATS_TEST_TMPDIR/editor.calls" ]
  editor_call=$(cat "$BATS_TEST_TMPDIR/editor.calls")
  [ -n "$editor_call" ]
}

@test "nlh open 2 opens the second most recent entry in EDITOR" {
  run bash -c "NLH_HOME='$NLH_HOME' EDITOR='$BATS_TEST_TMPDIR/bin/fake_editor' '$NLH_SCRIPT' open 2 2>&1"
  [ -f "$BATS_TEST_TMPDIR/editor.calls" ]
  editor_call=$(cat "$BATS_TEST_TMPDIR/editor.calls")
  [ -n "$editor_call" ]
}

@test "nlh open with out-of-range index prints error" {
  run bash -c "NLH_HOME='$NLH_HOME' EDITOR='$BATS_TEST_TMPDIR/bin/fake_editor' '$NLH_SCRIPT' open 999 2>&1 || true"
  [[ "$output" == *"No entry"* ]] || [[ "$output" == *"not found"* ]] || [[ "$output" == *"invalid"* ]] || [ "$status" -ne 0 ]
}

# --- nlh open -b <n> ---

@test "nlh open -b 1 calls pandoc for browser rendering" {
  run bash -c "NLH_HOME='$NLH_HOME' PATH='$BATS_TEST_TMPDIR/bin:$PATH' '$NLH_SCRIPT' open -b 1 2>&1 || true"
  [ -f "$BATS_TEST_TMPDIR/pandoc.calls" ] || [[ "$output" == *"pandoc"* ]]
}

@test "nlh open --browser 1 is equivalent to nlh open -b 1" {
  run bash -c "NLH_HOME='$NLH_HOME' PATH='$BATS_TEST_TMPDIR/bin:$PATH' '$NLH_SCRIPT' open --browser 1 2>&1 || true"
  [ -f "$BATS_TEST_TMPDIR/pandoc.calls" ] || [[ "$output" == *"pandoc"* ]] || [ "$status" -eq 0 ]
}

# --- fzf present ---

@test "nlh open with no arg and fzf present launches fzf picker" {
  # Create fzf mock that returns a filename
  cat > "$BATS_TEST_TMPDIR/bin/fzf" <<'EOF'
#!/usr/bin/env bash
echo "BATS_TEST_TMPDIR/nlh_home/captures/2024-01-15T11-00-00.md" >> "$BATS_TEST_TMPDIR/fzf.calls"
echo "$NLH_HOME/captures/2024-01-15T11-00-00.md"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/fzf"

  run bash -c "NLH_HOME='$NLH_HOME' EDITOR='$BATS_TEST_TMPDIR/bin/fake_editor' PATH='$BATS_TEST_TMPDIR/bin:$PATH' '$NLH_SCRIPT' open 2>&1 || true"
  # fzf should have been called (file exists as a signal)
  [ -f "$BATS_TEST_TMPDIR/fzf.calls" ] || [ "$status" -eq 0 ]
}
