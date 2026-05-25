#!/bin/sh
# Shell unit tests for platform detection functions.
# Run with: sh tests/test_installer_platform.sh

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

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

INSTALLER="$(cd "$(dirname "$0")/.." && pwd)/scripts/install.sh"
eval "$(awk '/^# STATUS-FUNCTIONS-START$/,/^# STATUS-FUNCTIONS-END$/' "$INSTALLER")"
eval "$(awk '/^# PLATFORM-FUNCTIONS-START$/,/^# PLATFORM-FUNCTIONS-END$/' "$INSTALLER")"

echo "is_pi tests:"

PLATFORM_MODEL_FILE="$WORK_DIR/model_empty"
touch "$PLATFORM_MODEL_FILE"
assert_returns "empty model file returns false" 1 "is_pi"

PLATFORM_MODEL_FILE="$WORK_DIR/model_laptop"
printf 'System76 Galago Pro\0' > "$WORK_DIR/model_laptop"
assert_returns "non-Pi model returns false" 1 "is_pi"

PLATFORM_MODEL_FILE="$WORK_DIR/model_pi"
printf 'Raspberry Pi Zero 2 W Rev 1.0\0' > "$WORK_DIR/model_pi"
assert_returns "Pi Zero 2W model returns true" 0 "is_pi"

PLATFORM_MODEL_FILE="$WORK_DIR/model_pi4"
printf 'Raspberry Pi 4 Model B Rev 1.5\0' > "$WORK_DIR/model_pi4"
assert_returns "Pi 4 model returns true" 0 "is_pi"

PLATFORM_MODEL_FILE="$WORK_DIR/model_pi_upper"
printf 'RASPBERRY PI 4 MODEL B\0' > "$WORK_DIR/model_pi_upper"
assert_returns "Pi model case-insensitive" 0 "is_pi"

PLATFORM_MODEL_FILE="$WORK_DIR/missing_model"
assert_returns "missing model file returns false" 1 "is_pi"

echo ""
echo "check_platform tests:"

PLATFORM_MODEL_FILE="$WORK_DIR/model_pi"
assert_eq "Pi shows Raspberry Pi" \
  "  [OK]   platform: Raspberry Pi" \
  "$(check_platform)"

PLATFORM_MODEL_FILE="$WORK_DIR/model_laptop"
assert_eq "non-Pi shows generic Debian" \
  "  [OK]   platform: generic Debian" \
  "$(check_platform)"

echo ""
echo "configure_grub_splash tests:"

sudo_if_needed() { :; }
log() { :; }

GRUB_CONF_FILE="$WORK_DIR/missing_grub"
assert_returns "missing grub conf is a no-op" 0 "configure_grub_splash"

GRUB_CONF_FILE="$WORK_DIR/grub_with_splash"
printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n' > "$GRUB_CONF_FILE"
assert_returns "grub conf with splash is idempotent" 0 "configure_grub_splash"

GRUB_CONF_FILE="$WORK_DIR/grub_no_splash"
printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' > "$GRUB_CONF_FILE"
assert_returns "grub conf without splash returns 0" 0 "configure_grub_splash"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
