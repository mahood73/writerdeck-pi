#!/bin/sh
# Shell unit tests for resolution_prompt_label
# Run with: sh tests/test_installer_resolution.sh

set -eu

PASS=0
FAIL=0

assert_eq() {
  label=$1
  expected=$2
  actual=$3
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

# Source only the pure helper functions from the installer.
# We use awk to extract lines between the two sentinel comments.
# This avoids running sudo/interactive code at source time.
eval "$(awk '/^# MAP-FUNCTIONS-START$/,/^# MAP-FUNCTIONS-END$/' scripts/install-trixie-lite.sh)"
eval "$(awk '/^# LABEL-FUNCTION-START$/,/^# LABEL-FUNCTION-END$/' scripts/install-trixie-lite.sh)"

echo "resolution_prompt_label tests:"

# Case 1: configured_res is set — takes priority over detected
assert_eq "configured takes priority" \
  "HDMI resolution (configured: 1920x1080, mode 86):" \
  "$(resolution_prompt_label "86" "82")"

# Case 2: no configured, detected is set
assert_eq "detected from display" \
  "HDMI resolution (detected from display: 1920x1080, mode 86):" \
  "$(resolution_prompt_label "" "86")"

# Case 3: detected maps to WriterDeck panel
assert_eq "detected writerdeck panel" \
  "HDMI resolution (detected from display: 1024x600, mode 51):" \
  "$(resolution_prompt_label "" "51")"

# Case 4: neither configured nor detected
assert_eq "no display detected" \
  "HDMI resolution (no display detected; suggested: mode 82):" \
  "$(resolution_prompt_label "" "")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
