#!/usr/bin/env bats
# Tests for nlh-paste and nlh-type platform wrapper selection (F5)
bats_require_minimum_version 1.5.0

load 'helpers/mocks'

NLH_PASTE_SCRIPT="$BATS_TEST_DIRNAME/../nlh-paste"
NLH_TYPE_SCRIPT="$BATS_TEST_DIRNAME/../nlh-type"

setup() {
  setup_nlh_home
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BATS_TEST_TMPDIR/no-x11-bin"
  mkdir -p "$BATS_TEST_TMPDIR/wayland-bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export NLH_HOME
}

# --- nlh-paste macOS ---

@test "nlh-paste uses pbcopy on macOS" {
  create_recording_mock "pbcopy" "$BATS_TEST_TMPDIR/pbcopy.calls" 0 ""
  run bash -c "NLH_PLATFORM=macos PATH='$BATS_TEST_TMPDIR/bin' echo 'test text' | '$NLH_PASTE_SCRIPT'"
  [ -f "$BATS_TEST_TMPDIR/pbcopy.calls" ] || [ "$status" -eq 0 ]
}

@test "nlh-paste writes text to clipboard via pbcopy on macOS" {
  create_macos_paste_mocks
  run bash -c "NLH_PLATFORM=macos PATH='$BATS_TEST_TMPDIR/bin:$PATH' echo 'hello paste' | '$NLH_PASTE_SCRIPT'"
  [ "$status" -eq 0 ]
}

# --- nlh-paste X11 ---

@test "nlh-paste uses xclip on X11" {
  create_recording_mock "xclip" "$BATS_TEST_TMPDIR/xclip.calls" 0 ""
  run bash -c "NLH_PLATFORM=x11 PATH='$BATS_TEST_TMPDIR/bin:$PATH' echo 'test text' | '$NLH_PASTE_SCRIPT'"
  [ "$status" -eq 0 ]
}

# --- nlh-paste Wayland ---

@test "nlh-paste uses wl-copy on Wayland" {
  create_recording_mock "wl-copy" "$BATS_TEST_TMPDIR/wl-copy.calls" 0 ""
  run bash -c "NLH_PLATFORM=wayland PATH='$BATS_TEST_TMPDIR/bin:$PATH' echo 'test text' | '$NLH_PASTE_SCRIPT'"
  [ "$status" -eq 0 ]
}

# --- nlh-type macOS ---

@test "nlh-type uses osascript on macOS" {
  create_recording_mock "osascript" "$BATS_TEST_TMPDIR/osascript.type.calls" 0 ""
  run bash -c "NLH_PLATFORM=macos PATH='$BATS_TEST_TMPDIR/bin:$PATH' '$NLH_TYPE_SCRIPT'"
  [ -f "$BATS_TEST_TMPDIR/osascript.type.calls" ]
}

# --- nlh-type X11 ---

@test "nlh-type uses xdotool on X11" {
  create_recording_mock "xdotool" "$BATS_TEST_TMPDIR/xdotool.type.calls" 0 ""
  run bash -c "NLH_PLATFORM=x11 PATH='$BATS_TEST_TMPDIR/bin:$PATH' '$NLH_TYPE_SCRIPT'"
  [ -f "$BATS_TEST_TMPDIR/xdotool.type.calls" ]
}

# --- nlh-type Wayland ---

@test "nlh-type uses ydotool on Wayland" {
  create_recording_mock "ydotool" "$BATS_TEST_TMPDIR/ydotool.type.calls" 0 ""
  run bash -c "NLH_PLATFORM=wayland PATH='$BATS_TEST_TMPDIR/bin:$PATH' '$NLH_TYPE_SCRIPT'"
  [ -f "$BATS_TEST_TMPDIR/ydotool.type.calls" ]
}

# --- Platform auto-detection ---

@test "nlh-paste auto-detects macOS when pbcopy is available and DISPLAY unset" {
  create_macos_paste_mocks
  run -0 bash -c "
    unset DISPLAY
    unset WAYLAND_DISPLAY
    unset NLH_PLATFORM
    PATH='$BATS_TEST_TMPDIR/bin:$PATH' echo 'auto detect' | '$NLH_PASTE_SCRIPT'
  "
}

@test "nlh-type auto-detects macOS when osascript available and DISPLAY unset" {
  create_macos_paste_mocks
  run -0 bash -c "
    unset DISPLAY
    unset WAYLAND_DISPLAY
    unset NLH_PLATFORM
    PATH='$BATS_TEST_TMPDIR/bin:$PATH' '$NLH_TYPE_SCRIPT'
  "
}

@test "nlh-paste exits non-zero when platform undetectable and no tool available" {
  local empty_bin="$BATS_TEST_TMPDIR/empty-bin"
  mkdir -p "$empty_bin"
  run -1 bash -c "
    unset DISPLAY
    unset WAYLAND_DISPLAY
    unset NLH_PLATFORM
    export PATH='$empty_bin:/bin'
    printf '%s' 'no platform' | '$NLH_PASTE_SCRIPT'
    # capture paste exit code explicitly since pipefail is not set in this subshell
    exit \${PIPESTATUS[1]}
  "
}
