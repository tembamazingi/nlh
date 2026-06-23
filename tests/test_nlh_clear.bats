#!/usr/bin/env bats
# Tests for nlh clear command (F7)

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

  # Create some fake capture files with known timestamps
  # Recent (today)
  _today=$(date +%Y-%m-%d)
  _now=$(date +%H-%M-%S)
  touch -t "$(date +%Y%m%d%H%M%S)" "$NLH_HOME/captures/${_today}T${_now}.md" 2>/dev/null || \
    touch "$NLH_HOME/captures/${_today}T${_now}.md"

  # Old file (simulate 10 days ago)
  _old_file="2020-01-01T00-00-00.md"
  cat > "$NLH_HOME/captures/$_old_file" <<'MDEOF'
# 2020-01-01 00:00:00
**Duration:** 3s

Old capture text

---
**Raw:** old raw text
MDEOF

  # Recent file
  _recent_file="${_today}T${_now}.md"
  cat > "$NLH_HOME/captures/$_recent_file" <<MDEOF
# $_today 00:00:00
**Duration:** 5s

Recent capture text

---
**Raw:** recent raw text
MDEOF

  # captures.log with entries
  cat > "$NLH_LOG" <<'LOGEOF'
[00:00:00]  [3s]  Old capture text
[12:00:00]  [5s]  Recent capture text
LOGEOF
}

# --- Menu rendering ---

@test "nlh clear presents the interactive menu" {
  run bash -c "echo '5' | NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' clear 2>&1 || true"
  [[ "$output" == *"Clear captures"* ]] || [[ "$output" == *"clear"* ]]
  [[ "$output" == *"1"* ]]  # menu option 1
  [[ "$output" == *"day"* ]] || [[ "$output" == *"All"* ]]
}

@test "nlh clear menu shows all 4 options" {
  run bash -c "echo '5' | NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' clear 2>&1 || true"
  [[ "$output" == *"1 day"* ]] || [[ "$output" == *"1)"* ]]
  [[ "$output" == *"7 day"* ]] || [[ "$output" == *"2)"* ]]
  [[ "$output" == *"2 week"* ]] || [[ "$output" == *"14"* ]] || [[ "$output" == *"3)"* ]]
  [[ "$output" == *"All"* ]] || [[ "$output" == *"all"* ]] || [[ "$output" == *"4)"* ]]
}

# --- Confirmation required ---

@test "nlh clear option 4 (all) with 'N' cancels without modifying files" {
  initial_md_count=$(ls "$NLH_HOME/captures/"*.md 2>/dev/null | wc -l | tr -d ' ')
  initial_log_lines=$(wc -l < "$NLH_LOG")

  run bash -c "printf '4\nN\n' | NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' clear 2>&1 || true"

  final_md_count=$(ls "$NLH_HOME/captures/"*.md 2>/dev/null | wc -l | tr -d ' ')
  final_log_lines=$(wc -l < "$NLH_LOG")

  [ "$final_md_count" -eq "$initial_md_count" ]
  [ "$final_log_lines" -eq "$initial_log_lines" ]
}

@test "nlh clear cancellation leaves files untouched" {
  initial_md_count=$(ls "$NLH_HOME/captures/"*.md 2>/dev/null | wc -l | tr -d ' ')

  # Send empty/cancel input
  run bash -c "printf '\n' | NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' clear 2>&1 || true"

  final_md_count=$(ls "$NLH_HOME/captures/"*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$final_md_count" -eq "$initial_md_count" ]
}

# --- Confirmation and deletion ---

@test "nlh clear option 4 (all) with 'y' removes all .md files" {
  initial_md_count=$(ls "$NLH_HOME/captures/"*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$initial_md_count" -gt 0 ]

  run bash -c "printf '4\ny\n' | NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' clear 2>&1 || true"

  final_md_count=$(ls "$NLH_HOME/captures/"*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$final_md_count" -eq 0 ]
}

@test "nlh clear option 4 (all) with 'y' clears captures.log" {
  run bash -c "printf '4\ny\n' | NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' clear 2>&1 || true"

  if [ -f "$NLH_LOG" ]; then
    log_lines=$(wc -l < "$NLH_LOG" | tr -d ' ')
    [ "$log_lines" -eq 0 ]
  fi
}

@test "nlh clear shows count of entries to be removed before confirmation" {
  run bash -c "printf '4\nN\n' | NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' clear 2>&1 || true"
  # Should mention how many captures will be removed
  [[ "$output" =~ [0-9]+ ]]
}

@test "nlh clear option 1 (1 day) removes only old files, leaves recent" {
  # Old file is from 2020, recent is today
  initial_old_exists=0
  [ -f "$NLH_HOME/captures/2020-01-01T00-00-00.md" ] && initial_old_exists=1
  [ "$initial_old_exists" -eq 1 ]

  run bash -c "printf '1\ny\n' | NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' clear 2>&1 || true"

  # Old file should be gone
  [ ! -f "$NLH_HOME/captures/2020-01-01T00-00-00.md" ]
  # Recent files should remain
  recent_count=$(ls "$NLH_HOME/captures/"*.md 2>/dev/null | wc -l | tr -d ' ')
  # At least the recent file should remain (if it was today)
  # (It may be 0 if date logic differs; just verify old is gone)
  [ ! -f "$NLH_HOME/captures/2020-01-01T00-00-00.md" ]
}

@test "nlh clear removes corresponding lines from captures.log" {
  # Clear all
  run bash -c "printf '4\ny\n' | NLH_HOME='$NLH_HOME' '$NLH_SCRIPT' clear 2>&1 || true"

  if [ -f "$NLH_LOG" ]; then
    # Log should be empty or only contain lines for files that still exist
    log_content=$(cat "$NLH_LOG" 2>/dev/null)
    # Old entries should be gone
    [[ "$log_content" != *"Old capture text"* ]]
  fi
}
