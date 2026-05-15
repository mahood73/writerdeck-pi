# Resolution Auto-Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the installer's resolution prompt header clearly communicate whether the default came from auto-detection, an existing config, or a hardcoded fallback.

**Architecture:** Extract a pure `resolution_prompt_label` shell function that takes `configured_res` and `detected_res` as arguments and prints the appropriate label string. Test it in isolation, then wire it into `prompt_console_settings` to replace the existing static echo.

**Tech Stack:** POSIX sh, bespoke shell test runner (no bats dependency)

---

## File Map

- Modify: `scripts/install-trixie-lite.sh` — add `resolution_prompt_label` function; replace static echo in `prompt_console_settings`
- Create: `tests/test_installer_resolution.sh` — shell unit tests for the new function

---

### Task 1: Write the failing shell test

**Files:**
- Create: `tests/test_installer_resolution.sh`

- [ ] **Step 1: Create the test file**

```sh
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
  "HDMI resolution (configured: mode 86):" \
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
```

- [ ] **Step 2: Run the test to confirm it fails**

```sh
sh tests/test_installer_resolution.sh
```

Expected: error like `resolution_prompt_label: not found` — the function doesn't exist yet.

---

### Task 2: Add sentinel comments and the new function to the installer

**Files:**
- Modify: `scripts/install-trixie-lite.sh:66-92` — wrap existing map functions in sentinel comments; add `resolution_prompt_label` after them

- [ ] **Step 1: Wrap the existing map functions in sentinel comments**

In `scripts/install-trixie-lite.sh`, find this block (around line 66):

```sh
# Map common resolutions to hdmi_mode values (DMT modes)
get_hdmi_mode() {
```

Add `# MAP-FUNCTIONS-START` on the line immediately before it, and `# MAP-FUNCTIONS-END` on the blank line after `hdmi_mode_to_resolution`'s closing `}` (after line 92).

Result — this section should look like:

```sh
# MAP-FUNCTIONS-START
# Map common resolutions to hdmi_mode values (DMT modes)
get_hdmi_mode() {
  case "$1" in
    640x480)    echo "1" ;;
    800x600)    echo "9" ;;
    1024x600)   echo "51" ;;
    1024x768)   echo "16" ;;
    1280x720)   echo "82" ;;
    1280x1024)  echo "35" ;;
    1920x1080)  echo "86" ;;
    *)          echo "" ;;
  esac
}

# Map hdmi_mode values back to resolution strings
hdmi_mode_to_resolution() {
  case "$1" in
    1)   echo "640x480" ;;
    9)   echo "800x600" ;;
    51)  echo "1024x600" ;;
    16)  echo "1024x768" ;;
    82)  echo "1280x720" ;;
    35)  echo "1280x1024" ;;
    86)  echo "1920x1080" ;;
    *)   echo "1280x720" ;;
  esac
}
# MAP-FUNCTIONS-END
```

- [ ] **Step 2: Add the `resolution_prompt_label` function after the sentinel block**

Insert the following immediately after `# MAP-FUNCTIONS-END`:

```sh
# LABEL-FUNCTION-START
# Returns the resolution prompt header line based on detection source.
# Args: $1 = configured_res (may be empty), $2 = detected_res (may be empty)
resolution_prompt_label() {
  _configured=$1
  _detected=$2
  if [ -n "$_configured" ]; then
    echo "HDMI resolution (configured: mode ${_configured}):"
  elif [ -n "$_detected" ]; then
    _label=$(hdmi_mode_to_resolution "$_detected")
    echo "HDMI resolution (detected from display: ${_label}, mode ${_detected}):"
  else
    echo "HDMI resolution (no display detected; suggested: mode 82):"
  fi
}
# LABEL-FUNCTION-END
```

- [ ] **Step 3: Run the test — it should now pass**

```sh
sh tests/test_installer_resolution.sh
```

Expected output:
```
resolution_prompt_label tests:
  PASS: configured takes priority
  PASS: detected from display
  PASS: detected writerdeck panel
  PASS: no display detected

Results: 4 passed, 0 failed
```

- [ ] **Step 4: Commit**

```sh
git add scripts/install-trixie-lite.sh tests/test_installer_resolution.sh
git commit -m "feat: add resolution_prompt_label function with shell tests"
```

---

### Task 3: Wire the function into `prompt_console_settings`

**Files:**
- Modify: `scripts/install-trixie-lite.sh:334` — replace static echo with call to `resolution_prompt_label`

- [ ] **Step 1: Replace the static echo**

Find this line in `prompt_console_settings` (around line 334):

```sh
  echo "HDMI resolution (current: ${default_res:-unknown}):"
```

Replace it with:

```sh
  echo "$(resolution_prompt_label "${configured_res:-}" "${detected_res:-}")"
```

- [ ] **Step 2: Re-run the tests to confirm nothing broke**

```sh
sh tests/test_installer_resolution.sh
```

Expected: 4 passed, 0 failed (unchanged).

- [ ] **Step 3: Also run the existing Python test suite**

```sh
uv run --with pytest pytest tests/test_wd.py tests/test_wd_menu.py -v
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```sh
git add scripts/install-trixie-lite.sh
git commit -m "feat: show detection source in resolution prompt (issue #14)"
```

---

### Task 4: Manual verification checklist (on Pi hardware)

These can't be automated — they require physical hardware. Run after pushing the branch.

- [ ] **Case 1 — HDMI display connected:** Run the installer. The resolution prompt header should read `HDMI resolution (detected from display: <res>, mode <N>):` with the display's native resolution.
- [ ] **Case 2 — Headless (no display):** Run the installer via SSH with no HDMI connected. Header should read `HDMI resolution (no display detected; suggested: mode 82):`.
- [ ] **Case 3 — Re-run on configured Pi:** Run the installer on a Pi that already has `hdmi_mode` set in `/boot/firmware/config.txt`. Header should read `HDMI resolution (configured: mode <N>):`.
