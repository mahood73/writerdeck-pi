#!/bin/sh
# Shell unit tests for status check functions
# Run with: sh tests/test_installer_status.sh

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

assert_returns() {
  label=$1
  expected_code=$2
  command=$3

  set +e
  eval "$command"
  actual_code=$?
  set -e

  if [ "$actual_code" -eq "$expected_code" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected return code: $expected_code"
    echo "    actual return code:   $actual_code"
    FAIL=$((FAIL + 1))
  fi
}

# Create a temporary directory for test files
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Source only the pure helper functions from the installer.
# We use awk to extract lines between the two sentinel comments.
# This avoids running sudo/interactive code at source time.
INSTALLER="$(cd "$(dirname "$0")/.." && pwd)/scripts/install-trixie-lite.sh"
eval "$(awk '/^# STATUS-FUNCTIONS-START$/,/^# STATUS-FUNCTIONS-END$/' "$INSTALLER")"

echo "check_file_installed tests:"

# Case 1: file exists
TEST_FILE="$WORK_DIR/test_file.txt"
touch "$TEST_FILE"
set +e
OUTPUT=$(check_file_installed "test label" "$TEST_FILE")
set -e
assert_eq "file exists - output" "  [OK]   test label: $TEST_FILE" "$OUTPUT"
assert_returns "file exists - return code" 0 "check_file_installed 'test label' '$TEST_FILE' > /dev/null"

# Case 2: file does not exist
MISSING_FILE="$WORK_DIR/missing.txt"
set +e
OUTPUT=$(check_file_installed "missing label" "$MISSING_FILE")
set -e
assert_eq "file missing - output" "  [FAIL] missing label: $MISSING_FILE not found" "$OUTPUT"
assert_returns "file missing - return code" 1 "check_file_installed 'missing label' '$MISSING_FILE' > /dev/null"

echo ""
echo "check_dir_installed tests:"

# Case 3: directory exists
TEST_DIR="$WORK_DIR/test_dir"
mkdir "$TEST_DIR"
set +e
OUTPUT=$(check_dir_installed "dir label" "$TEST_DIR")
set -e
assert_eq "dir exists - output" "  [OK]   dir label: $TEST_DIR" "$OUTPUT"
assert_returns "dir exists - return code" 0 "check_dir_installed 'dir label' '$TEST_DIR' > /dev/null"

# Case 4: directory does not exist
MISSING_DIR="$WORK_DIR/missing_dir"
set +e
OUTPUT=$(check_dir_installed "missing dir" "$MISSING_DIR")
set -e
assert_eq "dir missing - output" "  [FAIL] missing dir: $MISSING_DIR not found" "$OUTPUT"
assert_returns "dir missing - return code" 1 "check_dir_installed 'missing dir' '$MISSING_DIR' > /dev/null"

echo ""
echo "check_autologin_configured tests:"

# Case 5: file exists and contains --autologin
OVERRIDE_CONF="$WORK_DIR/override.conf"
cat > "$OVERRIDE_CONF" << 'EOF'
[Service]
ExecStart=-/sbin/agetty --autologin writerdeck %I
EOF
set +e
OUTPUT=$(check_autologin_configured "$OVERRIDE_CONF")
set -e
assert_eq "autologin configured - output" "  [OK]   tty1 autologin: $OVERRIDE_CONF" "$OUTPUT"
assert_returns "autologin configured - return code" 0 "check_autologin_configured '$OVERRIDE_CONF' > /dev/null"

# Case 6: file does not exist
MISSING_OVERRIDE="$WORK_DIR/missing_override.conf"
set +e
OUTPUT=$(check_autologin_configured "$MISSING_OVERRIDE")
set -e
assert_eq "autologin missing file - output" "  [FAIL] tty1 autologin: $MISSING_OVERRIDE not found" "$OUTPUT"
assert_returns "autologin missing file - return code" 1 "check_autologin_configured '$MISSING_OVERRIDE' > /dev/null"

# Case 7: file exists but lacks --autologin
NO_AUTOLOGIN_CONF="$WORK_DIR/no_autologin.conf"
cat > "$NO_AUTOLOGIN_CONF" << 'EOF'
[Service]
ExecStart=-/sbin/agetty %I
EOF
set +e
OUTPUT=$(check_autologin_configured "$NO_AUTOLOGIN_CONF")
set -e
assert_eq "autologin not in file - output" "  [FAIL] tty1 autologin: --autologin not found in $NO_AUTOLOGIN_CONF" "$OUTPUT"
assert_returns "autologin not in file - return code" 1 "check_autologin_configured '$NO_AUTOLOGIN_CONF' > /dev/null"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
