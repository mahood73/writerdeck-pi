# Sync-Agnostic wd and Configurable Writing Folder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all Syncthing-specific code from `bin/wd` and the config schema; add a writing folder prompt to the installer so the writing root is user-configurable.

**Architecture:** `bin/wd` loses the `sync` subcommand family and its supporting code entirely. `config/config.toml` drops the `[sync]` section. The installer gains a `prompt_writing_folder` step that resolves and validates the path before writing it into config.

**Tech Stack:** Python 3.11 (bin/wd), POSIX sh (installer), unittest (tests)

---

### Task 1: Remove sync test methods

**Files:**
- Modify: `tests/test_wd.py`

- [ ] **Step 1: Delete the two sync test methods**

Remove `test_sync_doctor_reports_conflicts` and `test_sync_resolve_requires_conflict_copy` entirely (lines ~139–158 in the current file). Do NOT change `_write_config` yet — `Config.__init__` still reads the `[sync]` section, so removing it from the fixture would break all tests.

- [ ] **Step 2: Run the tests and confirm they still pass**

```bash
python3 -m unittest discover tests/ -v
```

Expected: all remaining tests PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/test_wd.py
git commit -m "test: remove sync test cases"
```

---

### Task 2: Strip sync code from bin/wd

**Files:**
- Modify: `bin/wd`

- [ ] **Step 1: Remove unused imports**

Replace the import block at the top of `bin/wd`:

```python
import argparse
import datetime as dt
import json
import os
import re
import shlex
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
```

With:

```python
import argparse
import datetime as dt
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path
```

- [ ] **Step 2: Remove VALID_SYNC_MODES constant**

Delete this line:

```python
VALID_SYNC_MODES = {"single_writer", "two_way"}
```

- [ ] **Step 3: Strip sync fields from Config.__init__**

Replace the `Config.__init__` body:

```python
class Config:
    def __init__(self, raw: dict):
        self.root = Path(_read_required(raw, "paths", "root")).expanduser()
        self.default_project = _sanitize_name(
            _read_required(raw, "paths", "default_project"), "project"
        )
        self.editor_command = _read_required(raw, "editor", "command")
        self.folder_id = _read_required(raw, "sync", "folder_id")
        self.sync_mode = _read_required(raw, "sync", "mode")
        self.wait_timeout_sec = _read_required(raw, "sync", "wait_timeout_sec")

        if self.sync_mode not in VALID_SYNC_MODES:
            raise WriterDeckError(
                f"invalid sync.mode '{self.sync_mode}'. "
                f"Expected one of: {', '.join(sorted(VALID_SYNC_MODES))}"
            )

        if not isinstance(self.wait_timeout_sec, int) or self.wait_timeout_sec <= 0:
            raise WriterDeckError("sync.wait_timeout_sec must be a positive integer")
```

With:

```python
class Config:
    def __init__(self, raw: dict):
        self.root = Path(_read_required(raw, "paths", "root")).expanduser()
        self.default_project = _sanitize_name(
            _read_required(raw, "paths", "default_project"), "project"
        )
        self.editor_command = _read_required(raw, "editor", "command")
```

- [ ] **Step 4: Delete the SyncthingClient class**

Delete the entire `SyncthingClient` class (from `class SyncthingClient:` through the closing `return json.loads(body)` block — roughly lines 56–96 in the original file).

- [ ] **Step 5: Delete sync helper functions**

Delete these four functions entirely:
- `_find_syncthing_api_key()`
- `_print_status()`
- `_find_conflicts()`
- `_resolve_target_and_conflicts()`

- [ ] **Step 6: Delete sync command functions**

Delete these four functions entirely:
- `cmd_sync_status()`
- `cmd_sync_now()`
- `cmd_sync_doctor()`
- `cmd_sync_resolve()`

- [ ] **Step 7: Remove the sync subparser from build_parser**

Delete the entire sync subparser block from `build_parser()`:

```python
    sync = subparsers.add_parser("sync", help="Syncthing operations")
    sync_sub = sync.add_subparsers(dest="sync_command", required=True)

    sync_status = sync_sub.add_parser("status", help="Show current sync state")
    sync_status.set_defaults(func=cmd_sync_status)

    sync_now = sync_sub.add_parser("now", help="Trigger scan and wait for sync idle")
    sync_now.set_defaults(func=cmd_sync_now)

    sync_doctor = sync_sub.add_parser(
        "doctor", help="Report Syncthing conflict artifacts in the writing tree"
    )
    sync_doctor.set_defaults(func=cmd_sync_doctor)

    sync_resolve = sync_sub.add_parser(
        "resolve", help="Open conflicted files side by side for manual merge"
    )
    sync_resolve.add_argument("path", help="Base file path or conflict file path")
    sync_resolve.set_defaults(func=cmd_sync_resolve)
```

- [ ] **Step 8: Update the test config fixture**

Now that `Config.__init__` no longer reads `[sync]`, remove it from `_write_config` in `tests/test_wd.py`:

```python
def _write_config(self, editor_command):
    content = textwrap.dedent(
        f"""
        [paths]
        root = \"{self.root}\"
        default_project = \"inbox\"

        [editor]
        command = \"{editor_command}\"
        """
    ).strip()
    self.config_path.write_text(content, encoding="utf-8")
```

- [ ] **Step 9: Run tests to confirm nothing broke**

```bash
python3 -m unittest discover tests/ -v
```

Expected: all tests PASS.

- [ ] **Step 10: Commit**

```bash
git add bin/wd tests/test_wd.py
git commit -m "feat: remove wd sync subcommands and Syncthing coupling"
```

---

### Task 3: Update config/config.toml

**Files:**
- Modify: `config/config.toml`

- [ ] **Step 1: Replace config content**

Replace the entire file with:

```toml
[paths]
root = "~/Writing"
default_project = "inbox"

[editor]
command = "wordgrinder"
```

- [ ] **Step 2: Run tests to confirm Config still loads cleanly**

```bash
python3 -m unittest discover tests/ -v
```

Expected: all tests PASS. (Tests use their own temp config, so this verifies there's no implicit dependency on the template file.)

- [ ] **Step 3: Commit**

```bash
git add config/config.toml
git commit -m "feat: drop [sync] from config schema, use ~/Writing as default root"
```

---

### Task 4: Delete enable-phase2-two-way.sh

**Files:**
- Delete: `scripts/enable-phase2-two-way.sh`

- [ ] **Step 1: Delete the file**

```bash
git rm scripts/enable-phase2-two-way.sh
```

- [ ] **Step 2: Commit**

```bash
git commit -m "chore: remove enable-phase2-two-way.sh (sync.mode no longer exists)"
```

---

### Task 5: Add writing folder prompt and directory setup to installer

**Files:**
- Modify: `scripts/install-trixie-lite.sh`

- [ ] **Step 1: Add prompt_writing_folder function**

Insert this function after `prompt_console_settings` (before the `# Main flow` comment):

```sh
prompt_writing_folder() {
  echo ""
  echo "Writing folder:"

  while true; do
    printf "Writing folder [~/Writing]: "
    read -r folder_input

    if [ -z "$folder_input" ]; then
      WRITING_ROOT="$TARGET_HOME/Writing"
      break
    fi

    # Expand a leading ~/ or bare ~ against the target user's home
    case "$folder_input" in
      "~/"*) folder_input="$TARGET_HOME/${folder_input#~/}" ;;
      "~")   folder_input="$TARGET_HOME" ;;
    esac

    WRITING_ROOT="$folder_input"

    # Warn if path falls outside target user's home
    case "$WRITING_ROOT" in
      "$TARGET_HOME/"*|"$TARGET_HOME")
        break
        ;;
      *)
        printf "Warning: this path is outside your home directory. Are you sure? [y/N]: "
        read -r confirm
        case "$confirm" in
          y|Y|yes|YES) break ;;
          *) echo "Cancelled. Please enter a different path." ;;
        esac
        ;;
    esac
  done
}
```

- [ ] **Step 2: Add setup_writing_folder function**

Replace the existing inline writing-root setup (the three lines starting with `WRITING_ROOT=` and the two `sudo_if_needed install` calls plus `log "Created writing directory..."`) with a new `setup_writing_folder` function. Add the function definition alongside the other privileged helpers:

```sh
setup_writing_folder() {
  if [ -d "$WRITING_ROOT" ]; then
    log "Writing folder already exists at $WRITING_ROOT"
  else
    sudo_if_needed install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$WRITING_ROOT"
    sudo_if_needed install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$WRITING_ROOT/inbox"
    log "Created writing folder at $WRITING_ROOT"
  fi

  if ! sudo -u "$TARGET_USER" test -w "$WRITING_ROOT" 2>/dev/null; then
    echo "error: $TARGET_USER cannot write to $WRITING_ROOT" >&2
    echo "Check ownership and permissions: ls -ld $WRITING_ROOT" >&2
    exit 1
  fi
}
```

- [ ] **Step 3: Wire up the new prompt and function**

In the `# Run interactive prompts as current user` section, add `prompt_writing_folder` after `prompt_console_settings`:

```sh
show_header
prompt_target_user
# ... (target user resolution) ...
prompt_console_settings
prompt_writing_folder
```

In the `# Run privileged installation steps` section, replace the old three-line writing root setup with a call to the new function:

```sh
install_required_packages

sudo_if_needed install -d -m 0755 /etc/writerdeck
sudo_if_needed install -d -m 0755 "$STATE_DIR"
backup_file_if_missing "$CONFIG_PATH" etc/writerdeck/config.toml
setup_writing_folder
install_config
```

- [ ] **Step 4: Update render_default_config to substitute the new template placeholder**

The config template now uses `~/Writing`. Update `render_default_config` to substitute that placeholder:

```sh
render_default_config() {
  destination=$1
  sed "s|^root = \"~/Writing\"$|root = \"$WRITING_ROOT\"|" \
    "$DEFAULT_CONFIG_PATH" > "$destination"
}
```

- [ ] **Step 5: Manual smoke test (on the Pi or in a temp environment)**

Run the installer interactively and verify:
- Default `~/Writing` prompt accepts Enter and creates the correct directory
- Entering a path outside home shows the warning and re-prompts on `N`
- Entering a path outside home and confirming `y` proceeds without error
- Re-running the installer when the folder already exists logs "already exists" rather than "created"
- Re-running when the folder exists but is not writable by the target user exits with a clear error

- [ ] **Step 6: Commit**

```bash
git add scripts/install-trixie-lite.sh
git commit -m "feat: add writing folder prompt to installer with outside-home warning"
```

---

### Task 6: Update installer migration guards

**Files:**
- Modify: `scripts/install-trixie-lite.sh`

The installer's `install_config` function checks whether an existing config was written by a previous installer run before deciding to upgrade it. The existing guards (`is_managed_sync_writerdeck_config`, `is_managed_legacy_config`) match old path/editor patterns. We need a guard that recognises the previous managed config (which had `root = "$TARGET_HOME/Writing"` with a `[sync]` section) so re-running the new installer over an existing install upgrades cleanly.

- [ ] **Step 1: Add is_managed_writing_sync_config**

Add this function alongside the existing migration guards:

```sh
is_managed_writing_sync_config() {
  config_path=$1

  [ -f "$config_path" ] || return 1
  grep -q "^root = \"$TARGET_HOME/Writing\"$" "$config_path" || return 1
  grep -q '^default_project = "inbox"$' "$config_path" || return 1
  grep -q '^command = "wordgrinder"$' "$config_path" || return 1
  grep -q '^folder_id = "writing"$' "$config_path" || return 1
  grep -q '^mode = "single_writer"$' "$config_path" || return 1
  return 0
}
```

- [ ] **Step 2: Add the new guard to install_config**

In `install_config`, update the upgrade condition to include the new guard:

```sh
  if cmp -s "$DEFAULT_CONFIG_PATH" "$CONFIG_PATH" \
    || is_managed_sync_writerdeck_config "$CONFIG_PATH" \
    || is_managed_legacy_config "$CONFIG_PATH" \
    || is_managed_writing_sync_config "$CONFIG_PATH"; then
    sudo_if_needed install -m 0644 "$CONFIG_PATH" "${CONFIG_PATH}.bak"
    sudo_if_needed install -m 0644 "$rendered_default" "$CONFIG_PATH"
    rm -f "$rendered_default"
    log "Migrated default config path for user $TARGET_USER"
    log "Backup written to: ${CONFIG_PATH}.bak"
    return
  fi
```

- [ ] **Step 3: Manual verification**

Create a test config at `/etc/writerdeck/config.toml` matching the old managed pattern:

```toml
[paths]
root = "/home/<TARGET_USER>/Writing"
default_project = "inbox"

[editor]
command = "wordgrinder"

[sync]
folder_id = "writing"
mode = "single_writer"
wait_timeout_sec = 180
```

Re-run the installer and confirm it upgrades (backs up the old config and writes the new one) rather than leaving the old one in place.

- [ ] **Step 4: Commit**

```bash
git add scripts/install-trixie-lite.sh
git commit -m "feat: add migration guard for previous managed writing config"
```

---

### Task 7: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the CLI section**

Remove `wd sync status`, `wd sync now`, `wd sync doctor`, and `wd sync resolve` from the CLI code block. The updated block should be:

```
wd open-latest           # Open the most recently modified draft
wd new [folder]          # Start a new draft
wd projects              # List project folders
```

- [ ] **Step 2: Update the Config section**

Replace the config example with:

```toml
[paths]
root = "~/Writing"
default_project = "inbox"

[editor]
command = "wordgrinder"
```

Remove the `[sync]` block and its description entirely.

- [ ] **Step 3: Update the Sync section**

Replace the "## Sync" section body with:

```
WriterDeck writes locally. Point any sync tool (Syncthing, Dropbox, Nextcloud, etc.) at your writing folder and it will carry files to other devices. WriterDeck has no opinion about which tool you use.
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: remove sync CLI docs, update config example and sync section"
```

---

### Task 8: Final verification

- [ ] **Step 1: Run the full test suite**

```bash
python3 -m unittest discover tests/ -v
```

Expected output: all tests pass, no references to sync in output.

- [ ] **Step 2: Verify no sync references remain in bin/wd**

```bash
grep -n "sync\|Syncthing\|syncthing\|folder_id\|VALID_SYNC" bin/wd
```

Expected: no matches.

- [ ] **Step 3: Verify config.toml has no [sync] section**

```bash
grep -n "sync\|folder_id\|mode\|wait_timeout" config/config.toml
```

Expected: no matches.

- [ ] **Step 4: Verify enable-phase2-two-way.sh is gone**

```bash
ls scripts/
```

Expected: only `install-trixie-lite.sh` and `uninstall-trixie-lite.sh`.
