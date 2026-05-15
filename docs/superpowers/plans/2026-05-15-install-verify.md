# Install Verify Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `install-trixie-lite.sh --status` (check what's installed) and `wd verify` (runtime system check), giving users and developers a clear pass/fail picture of the install state.

**Architecture:** Two complementary checks: `--status` on the installer reports whether the installer's artefacts are in place (files, directories, systemd drop-in); `wd verify` is a new `wd` subcommand that checks runtime correctness (config, writing root, editor in PATH, wd-session, tty1 autologin, syncthing). Both report `[OK]` / `[FAIL]` / `[SKIP]` per item and exit non-zero if any check fails. Pure shell helper functions for the installer live in a sentinel block so they can be unit-tested with the same `awk`+`eval` pattern already used for resolution tests.

**Tech Stack:** POSIX sh (installer), Python 3.11+ (wd CLI), unittest + subprocess (Python tests), sh unit tests (installer tests)

---

## File Map

| Action  | File                                   | Responsibility                          |
|---------|----------------------------------------|-----------------------------------------|
| Modify  | `scripts/install-trixie-lite.sh`       | Add `# STATUS-FUNCTIONS-START/END` sentinel block + `show_status()` + `--status` flag |
| Create  | `tests/test_installer_status.sh`       | Shell unit tests for status check functions |
| Modify  | `bin/wd`                               | Add `_verify_*` functions, `cmd_verify`, update `main()` |
| Modify  | `tests/test_wd.py`                     | Add `WriterDeckVerifyTests` class       |

---

## Task 1: Write failing shell tests for installer status functions

**Files:**
- Create: `tests/test_installer_status.sh`

- [ ] **Step 1: Create the test file**

```sh
#!/bin/sh
# Shell unit tests for installer status check functions.
# Run with: sh tests/test_installer_status.sh

set -eu

PASS=0
FAIL=0

assert_eq() {
  label=$1
  expected=$2
  actual=$3
  if [ "$actual" = "$expected" ]; then
    printf '  PASS: %s\n' "$label"
    PASS=$((PASS + 1))
  else
    printf '  FAIL: %s\n' "$label"
    printf '    expected: %s\n' "$expected"
    printf '    actual:   %s\n' "$actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_returns() {
  label=$1
  expected=$2
  eval "$3"
  actual=$?
  if [ "$actual" = "$expected" ]; then
    printf '  PASS: %s\n' "$label"
    PASS=$((PASS + 1))
  else
    printf '  FAIL: %s (returned %s, expected %s)\n' "$label" "$actual" "$expected"
    FAIL=$((FAIL + 1))
  fi
}

INSTALLER="$(cd "$(dirname "$0")/.." && pwd)/scripts/install-trixie-lite.sh"
eval "$(awk '/^# STATUS-FUNCTIONS-START$/,/^# STATUS-FUNCTIONS-END$/' "$INSTALLER")"

TMPDIR_WORK=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR_WORK"; }
trap cleanup EXIT

# check_file_installed
echo "check_file_installed tests:"

REAL_FILE="$TMPDIR_WORK/present.txt"
touch "$REAL_FILE"

assert_eq "ok output for existing file" \
  "  [OK]   mybin: $REAL_FILE" \
  "$(check_file_installed "mybin" "$REAL_FILE")"

assert_returns "returns 0 for existing file" 0 \
  "check_file_installed 'mybin' '$REAL_FILE' >/dev/null 2>&1"

assert_eq "fail output for missing file" \
  "  [FAIL] mybin: $TMPDIR_WORK/missing not found" \
  "$(check_file_installed "mybin" "$TMPDIR_WORK/missing")"

assert_returns "returns 1 for missing file" 1 \
  "check_file_installed 'mybin' '$TMPDIR_WORK/missing' >/dev/null 2>&1 || true; [ \$? -eq 1 ]"

# check_dir_installed
echo ""
echo "check_dir_installed tests:"

REAL_DIR="$TMPDIR_WORK/present_dir"
mkdir "$REAL_DIR"

assert_eq "ok output for existing dir" \
  "  [OK]   mytheme: $REAL_DIR" \
  "$(check_dir_installed "mytheme" "$REAL_DIR")"

assert_eq "fail output for missing dir" \
  "  [FAIL] mytheme: $TMPDIR_WORK/missing_dir not found" \
  "$(check_dir_installed "mytheme" "$TMPDIR_WORK/missing_dir")"

# check_autologin_configured
echo ""
echo "check_autologin_configured tests:"

OVERRIDE_OK="$TMPDIR_WORK/override_ok.conf"
printf '[Service]\nExecStart=-/sbin/agetty --autologin testuser %%I\n' > "$OVERRIDE_OK"

OVERRIDE_BAD="$TMPDIR_WORK/override_bad.conf"
printf '[Service]\nExecStart=-/sbin/agetty %%I\n' > "$OVERRIDE_BAD"

assert_eq "ok when --autologin present" \
  "  [OK]   tty1 autologin: $OVERRIDE_OK" \
  "$(check_autologin_configured "$OVERRIDE_OK")"

assert_eq "fail when override missing" \
  "  [FAIL] tty1 autologin: $TMPDIR_WORK/no_override.conf not found" \
  "$(check_autologin_configured "$TMPDIR_WORK/no_override.conf")"

assert_eq "fail when --autologin absent from file" \
  "  [FAIL] tty1 autologin: --autologin not found in $OVERRIDE_BAD" \
  "$(check_autologin_configured "$OVERRIDE_BAD")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run tests to confirm they fail (sentinel block not in installer yet)**

```sh
sh tests/test_installer_status.sh
```

Expected: error like `check_file_installed: not found` — functions don't exist yet.

---

## Task 2: Add STATUS-FUNCTIONS-START/END sentinel block to installer

**Files:**
- Modify: `scripts/install-trixie-lite.sh`

The sentinel block should go after the existing `# MAP-FUNCTIONS-END` comment and before `# LABEL-FUNCTION-START`.

- [ ] **Step 1: Add the STATUS-FUNCTIONS sentinel block**

Insert after the line `# MAP-FUNCTIONS-END` in `scripts/install-trixie-lite.sh`:

```sh
# STATUS-FUNCTIONS-START
status_ok() {
  printf '  [OK]   %s\n' "$*"
}

status_fail() {
  printf '  [FAIL] %s\n' "$*"
}

# check_file_installed label path
check_file_installed() {
  _label=$1
  _path=$2
  if [ -f "$_path" ]; then
    status_ok "$_label: $_path"
    return 0
  else
    status_fail "$_label: $_path not found"
    return 1
  fi
}

# check_dir_installed label path
check_dir_installed() {
  _label=$1
  _path=$2
  if [ -d "$_path" ]; then
    status_ok "$_label: $_path"
    return 0
  else
    status_fail "$_label: $_path not found"
    return 1
  fi
}

# check_autologin_configured override_conf_path
check_autologin_configured() {
  _path=$1
  if [ ! -f "$_path" ]; then
    status_fail "tty1 autologin: $_path not found"
    return 1
  fi
  if grep -q -- '--autologin' "$_path" 2>/dev/null; then
    status_ok "tty1 autologin: $_path"
    return 0
  fi
  status_fail "tty1 autologin: --autologin not found in $_path"
  return 1
}
# STATUS-FUNCTIONS-END
```

- [ ] **Step 2: Run shell tests to confirm they pass**

```sh
sh tests/test_installer_status.sh
```

Expected: all PASS, exit 0.

---

## Task 3: Add `show_status()` and `--status` flag to installer

**Files:**
- Modify: `scripts/install-trixie-lite.sh`

- [ ] **Step 1: Add `show_status()` function**

Add this function after the `STATUS-FUNCTIONS-END` line (before `# LABEL-FUNCTION-START`). It calls the sentinel functions with real system paths:

```sh
show_status() {
  echo ""
  echo "WriterDeck installation status:"
  _fails=0

  # Required packages
  _required_pkgs="wordgrinder-ncurses cage foot labwc wlopm python3 plymouth plymouth-label"
  for _pkg in $_required_pkgs; do
    if dpkg-query -W -f='${Status}' "$_pkg" 2>/dev/null | grep -q '^install ok installed$'; then
      status_ok "package: $_pkg"
    else
      status_fail "package: $_pkg"
      _fails=$((_fails + 1))
    fi
  done

  check_file_installed "config" "$CONFIG_PATH" || _fails=$((_fails + 1))
  check_file_installed "wd" "/usr/local/bin/wd" || _fails=$((_fails + 1))
  check_file_installed "wd-session" "/usr/local/bin/wd-session" || _fails=$((_fails + 1))
  check_file_installed "wd-menu" "/usr/local/bin/wd-menu" || _fails=$((_fails + 1))
  check_file_installed "profile script" "/etc/profile.d/wd-session.sh" || _fails=$((_fails + 1))
  check_autologin_configured \
    "/etc/systemd/system/getty@tty1.service.d/override.conf" || _fails=$((_fails + 1))
  check_dir_installed "plymouth theme" \
    "/usr/share/plymouth/themes/writerdeck" || _fails=$((_fails + 1))

  echo ""
  if [ "$_fails" -eq 0 ]; then
    echo "All checks passed."
  else
    echo "$_fails check(s) failed."
  fi
  return "$_fails"
}
```

- [ ] **Step 2: Add `--status` flag parsing at the top of the main flow**

The main flow starts after the `NEEDS_SUDO` block, just before `show_header`. Find the section that begins:

```sh
# If we need sudo and don't have it, request it for the rest of the script
if [ "$NEEDS_SUDO" = "true" ]; then
```

Add argument parsing before it (after the `INITIAL_USER`/`NEEDS_SUDO` initial setup section):

```sh
# Parse flags
STATUS_MODE=false
for _arg in "$@"; do
  case "$_arg" in
    --status) STATUS_MODE=true ;;
    *) ;;
  esac
done

if [ "$STATUS_MODE" = "true" ]; then
  show_status
  exit $?
fi
```

- [ ] **Step 3: Smoke-test `--status` locally (no Pi needed for this)**

```sh
sh scripts/install-trixie-lite.sh --status
```

Expected: prints the check table (most items will show `[FAIL]` on a dev machine — that's correct). Exits non-zero. Does **not** prompt for user input.

- [ ] **Step 4: Commit**

```bash
git add scripts/install-trixie-lite.sh tests/test_installer_status.sh
git commit -m "feat: add --status flag to installer (issues #12 #13)"
```

---

## Task 4: Write failing Python tests for `wd verify`

**Files:**
- Modify: `tests/test_wd.py`

- [ ] **Step 1: Add `WriterDeckVerifyTests` class**

Append the following class to `tests/test_wd.py` (before the `if __name__ == "__main__":` line):

```python
class WriterDeckVerifyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "projects"
        self.root.mkdir()
        self.config_path = Path(self.tmp.name) / "config.toml"

        # Fake wd-session binary
        self.fake_session = Path(self.tmp.name) / "wd-session"
        self.fake_session.write_text("#!/bin/sh\n", encoding="utf-8")
        self.fake_session.chmod(self.fake_session.stat().st_mode | stat.S_IXUSR)

        # Fake tty1 override.conf with autologin
        self.fake_override = Path(self.tmp.name) / "override.conf"
        self.fake_override.write_text(
            "[Service]\nExecStart=-/sbin/agetty --autologin testuser %I\n",
            encoding="utf-8",
        )

        self._write_config("cat")  # 'cat' is always in PATH

    def _write_config(self, editor_command):
        content = textwrap.dedent(
            f"""
            [paths]
            root = "{self.root}"
            default_project = "inbox"

            [editor]
            command = "{editor_command}"
            """
        ).strip()
        self.config_path.write_text(content, encoding="utf-8")

    def _run_verify(self):
        env = os.environ.copy()
        env["WD_CONFIG"] = str(self.config_path)
        env["WD_SESSION_PATH"] = str(self.fake_session)
        env["WD_TTY1_OVERRIDE_CONF"] = str(self.fake_override)
        return subprocess.run(
            [sys.executable, str(WD_BIN), "verify"],
            env=env,
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_verify_config_ok(self):
        result = self._run_verify()
        self.assertIn("[OK]   config:", result.stdout)

    def test_verify_config_fail_when_missing(self):
        self.config_path.unlink()
        result = self._run_verify()
        self.assertIn("[FAIL] config:", result.stdout)
        self.assertEqual(result.returncode, 1)

    def test_verify_writing_root_ok(self):
        result = self._run_verify()
        self.assertIn("[OK]   writing root:", result.stdout)

    def test_verify_writing_root_fail_when_missing(self):
        self.root.rmdir()
        result = self._run_verify()
        self.assertIn("[FAIL] writing root:", result.stdout)
        self.assertEqual(result.returncode, 1)

    def test_verify_editor_ok(self):
        result = self._run_verify()
        self.assertIn("[OK]   editor:", result.stdout)

    def test_verify_editor_fail_when_not_in_path(self):
        self._write_config("no_such_editor_xyz_abc")
        result = self._run_verify()
        self.assertIn("[FAIL] editor:", result.stdout)
        self.assertEqual(result.returncode, 1)

    def test_verify_wd_session_ok(self):
        result = self._run_verify()
        self.assertIn("[OK]   wd-session:", result.stdout)

    def test_verify_wd_session_fail_when_missing(self):
        self.fake_session.unlink()
        result = self._run_verify()
        self.assertIn("[FAIL] wd-session:", result.stdout)
        self.assertEqual(result.returncode, 1)

    def test_verify_tty1_autologin_ok(self):
        result = self._run_verify()
        self.assertIn("[OK]   tty1 autologin:", result.stdout)

    def test_verify_tty1_autologin_fail_when_file_missing(self):
        self.fake_override.unlink()
        result = self._run_verify()
        self.assertIn("[FAIL] tty1 autologin:", result.stdout)
        self.assertEqual(result.returncode, 1)

    def test_verify_tty1_autologin_fail_when_no_autologin_directive(self):
        self.fake_override.write_text("[Service]\nExecStart=-/sbin/agetty %I\n", encoding="utf-8")
        result = self._run_verify()
        self.assertIn("[FAIL] tty1 autologin:", result.stdout)
        self.assertEqual(result.returncode, 1)

    def test_verify_fail_count_in_summary(self):
        self.fake_session.unlink()
        self.fake_override.unlink()
        result = self._run_verify()
        self.assertEqual(result.returncode, 1)
        self.assertIn("2 check(s) failed", result.stdout)

    def test_verify_all_clear_shows_all_ok_lines(self):
        result = self._run_verify()
        # All checks that are controllable via env/config should pass
        fail_lines = [
            line for line in result.stdout.splitlines()
            if "[FAIL]" in line and "syncthing" not in line
        ]
        self.assertEqual(fail_lines, [], result.stdout)
```

- [ ] **Step 2: Run tests to confirm they fail**

```sh
uv run --with pytest pytest tests/test_wd.py::WriterDeckVerifyTests -v
```

Expected: `ERROR` or `FAILED` — `verify` command not implemented yet.

---

## Task 5: Implement `wd verify` in `bin/wd`

**Files:**
- Modify: `bin/wd`

- [ ] **Step 1: Add env-var-overridable path constants after `DEFAULT_CONFIG_PATH`**

After the line `DEFAULT_CONFIG_PATH = Path("/etc/writerdeck/config.toml")`, add:

```python
_WD_SESSION_PATH = Path(os.getenv("WD_SESSION_PATH", "/usr/local/bin/wd-session"))
_TTY1_AUTOLOGIN_PATH = Path(
    os.getenv(
        "WD_TTY1_OVERRIDE_CONF",
        "/etc/systemd/system/getty@tty1.service.d/override.conf",
    )
)
```

- [ ] **Step 2: Add the six verify helper functions**

Add these functions after the `_run_editor` and `_is_wordgrinder_command` functions, before `cmd_open_latest`:

```python
def _verify_config(config_path: Path) -> tuple[bool | None, str]:
    try:
        _load_config(config_path)
        return True, str(config_path)
    except WriterDeckError as exc:
        return False, str(exc)


def _verify_writing_root(cfg: Config) -> tuple[bool | None, str]:
    if not cfg.root.exists():
        return False, f"{cfg.root} does not exist"
    if not os.access(cfg.root, os.W_OK):
        return False, f"{cfg.root} not writable"
    return True, f"{cfg.root} (writable)"


def _verify_editor(cfg: Config) -> tuple[bool | None, str]:
    cmd = shlex.split(cfg.editor_command)
    if not cmd:
        return False, "editor command is empty"
    binary = cmd[0]
    found = shutil.which(binary)
    if found is None:
        return False, f"{binary} not found in PATH"
    return True, found


def _verify_wd_session() -> tuple[bool | None, str]:
    path = _WD_SESSION_PATH
    if path.exists():
        return True, str(path)
    return False, f"{path} not found"


def _verify_tty1_autologin() -> tuple[bool | None, str]:
    path = _TTY1_AUTOLOGIN_PATH
    if not path.exists():
        return False, f"{path} not found"
    if "--autologin" in path.read_text(encoding="utf-8"):
        return True, str(path)
    return False, "autologin not configured in override.conf"


def _verify_syncthing(user: str) -> tuple[bool | None, str]:
    if shutil.which("systemctl") is None:
        return None, "systemctl not available"
    for service in (f"syncthing@{user}.service", "syncthing.service"):
        r = subprocess.run(
            ["systemctl", "is-active", "--quiet", service],
            check=False,
            capture_output=True,
        )
        if r.returncode == 0:
            return True, f"{service} active"
    return False, "syncthing service not running"
```

- [ ] **Step 3: Add `cmd_verify` function**

Add after the verify helper functions:

```python
def cmd_verify(cfg: Config | None, args: argparse.Namespace) -> int:
    import getpass

    config_path = Path(args.config).expanduser()
    user = getpass.getuser()

    results: list[tuple[str, bool | None, str]] = [
        ("config", *_verify_config(config_path)),
    ]
    if cfg is not None:
        results.append(("writing root", *_verify_writing_root(cfg)))
        results.append(("editor", *_verify_editor(cfg)))
    results.append(("wd-session", *_verify_wd_session()))
    results.append(("tty1 autologin", *_verify_tty1_autologin()))
    results.append(("syncthing", *_verify_syncthing(user)))

    fail_count = 0
    for label, passed, detail in results:
        if passed is True:
            tag = "[OK]  "
        elif passed is False:
            tag = "[FAIL]"
            fail_count += 1
        else:
            tag = "[SKIP]"
        print(f"  {tag} {label}: {detail}")

    print()
    if fail_count == 0:
        print("All checks passed.")
    else:
        print(f"{fail_count} check(s) failed.")

    return 0 if fail_count == 0 else 1
```

- [ ] **Step 4: Register `verify` subcommand in `build_parser()`**

Add after the `export_cmd` block in `build_parser()`:

```python
    verify_cmd = subparsers.add_parser("verify", help="Check WriterDeck install state")
    verify_cmd.set_defaults(func=None)
```

- [ ] **Step 5: Update `main()` to handle verify before loading config**

Replace the current `main()` function with:

```python
def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    config_path = Path(args.config).expanduser()

    if args.command == "verify":
        try:
            cfg = _load_config(config_path)
        except WriterDeckError:
            cfg = None
        return cmd_verify(cfg, args)

    try:
        cfg = _load_config(config_path)
        return args.func(cfg, args)
    except WriterDeckError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
```

- [ ] **Step 6: Run tests to confirm they pass**

```sh
uv run --with pytest pytest tests/test_wd.py::WriterDeckVerifyTests -v
```

Expected: all tests pass.

- [ ] **Step 7: Run full test suite to check for regressions**

```sh
uv run --with pytest pytest tests/ -v
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add bin/wd tests/test_wd.py
git commit -m "feat: add wd verify command (issues #12 #13)"
```

---

## Task 6: Open PR

- [ ] **Step 1: Push branch and open PR**

```bash
git push -u origin <branch-name>
gh pr create --title "feat: install --status and wd verify (#12 #13)" --body "$(cat <<'EOF'
## Summary
- `install-trixie-lite.sh --status`: prints pass/fail for every installer artefact (packages, binaries, config, tty1 autologin, Plymouth theme) without making any changes
- `wd verify`: new subcommand that checks runtime state — config validity, writing root, editor in PATH, wd-session installed, tty1 autologin, Syncthing service

## Test plan
- [ ] `sh tests/test_installer_status.sh` passes locally
- [ ] `uv run --with pytest pytest tests/` passes locally
- [ ] Push branch, SSH to Pi, run `sudo sh scripts/install-trixie-lite.sh --status` — all checks pass on an installed Pi
- [ ] Run `wd verify` on Pi — all checks pass (Syncthing check reflects actual service state)
- [ ] Run `wd verify` before installing on a fresh system — relevant checks show `[FAIL]`

Closes #12, #13
EOF
)"
```
