# Startup Mode Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Startup mode" toggle to the Settings menu so users can switch between `resume` (open last document) and `menu` (show launcher) without hand-editing TOML.

**Architecture:** All changes are in `bin/wd-menu` and `tests/test_wd_menu.py`. A new `MenuItem` is added to `SETTINGS_MENU` and `handle_settings()` is extended to read, flip, and persist `start_mode` via the existing `write_config_value()` helper. No new files.

**Tech Stack:** Python 3.11+, curses, tomllib, pytest

---

## Task 1: Create feature branch

- [ ] **Step 1: Create and switch to feature branch**

```bash
git checkout -b feat/startup-mode-setting
```

Expected: `Switched to a new branch 'feat/startup-mode-setting'`

---

## Task 2: Test and add `settings_startup` to `SETTINGS_MENU`

**Files:**
- Modify: `tests/test_wd_menu.py`
- Modify: `bin/wd-menu`

- [ ] **Step 1: Write the failing test**

In `tests/test_wd_menu.py`, update the existing `test_settings_submenu_items` test (around line 148) to also assert `settings_startup`:

```python
def test_settings_submenu_items():
    items = menu.SETTINGS_MENU
    actions = [i.action for i in items]
    assert "settings_blank" in actions
    assert "settings_kbd" in actions
    assert "settings_startup" in actions
```

- [ ] **Step 2: Run test to verify it fails**

```bash
uv run --with pytest pytest tests/test_wd_menu.py::test_settings_submenu_items -v
```

Expected: FAIL — `AssertionError: assert 'settings_startup' in [...]`

- [ ] **Step 3: Add the menu item**

In `bin/wd-menu`, find `SETTINGS_MENU` (around line 111) and add the new item:

```python
SETTINGS_MENU = [
    MenuItem("b", "Screen blank timeout", "settings_blank"),
    MenuItem("k", "Keyboard layout", "settings_kbd"),
    MenuItem("s", "Startup mode", "settings_startup"),
]
```

- [ ] **Step 4: Run test to verify it passes**

```bash
uv run --with pytest pytest tests/test_wd_menu.py::test_settings_submenu_items -v
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add bin/wd-menu tests/test_wd_menu.py
git commit -m "feat: add startup mode item to SETTINGS_MENU"
```

---

## Task 3: Test and implement the toggle handler

**Files:**
- Modify: `tests/test_wd_menu.py`
- Modify: `bin/wd-menu`

- [ ] **Step 1: Write two failing tests**

Add to `tests/test_wd_menu.py`, using the existing `_write_config` helper pattern:

```python
def _toggle_start_mode(initial_toml: str, current_mode: str) -> str:
    """Simulate what handle_settings does: flip start_mode and write it."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".toml", delete=False, encoding="utf-8") as f:
        f.write(initial_toml)
        tmp = Path(f.name)
    original_config = menu.CONFIG_PATH
    menu.CONFIG_PATH = tmp
    try:
        new_mode = "menu" if current_mode == "resume" else "resume"
        menu.write_config_value("session", "start_mode", f'"{new_mode}"')
        result = tmp.read_text(encoding="utf-8")
    finally:
        menu.CONFIG_PATH = original_config
        tmp.unlink(missing_ok=True)
    return result


def test_startup_mode_toggles_resume_to_menu():
    toml = '[session]\nstart_mode = "resume"\n'
    result = _toggle_start_mode(toml, "resume")
    assert 'start_mode = "menu"' in result
    assert 'start_mode = "resume"' not in result


def test_startup_mode_toggles_menu_to_resume():
    toml = '[session]\nstart_mode = "menu"\n'
    result = _toggle_start_mode(toml, "menu")
    assert 'start_mode = "resume"' in result
    assert 'start_mode = "menu"' not in result
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
uv run --with pytest pytest tests/test_wd_menu.py::test_startup_mode_toggles_resume_to_menu tests/test_wd_menu.py::test_startup_mode_toggles_menu_to_resume -v
```

Expected: PASS — `_write_config` is defined in the test file and calls `write_config_value` directly, so these tests pass as soon as they're added. They confirm that `write_config_value` handles quoted TOML strings correctly for `start_mode`. If they fail, check that `write_config_value` receives `'"menu"'` (a Python string containing `"menu"` with double-quotes).

- [ ] **Step 3: Implement the toggle handler and annotated menu item**

In `bin/wd-menu`, update `handle_settings()`. Replace the existing function (around line 382) with:

```python
def handle_settings(stdscr) -> None:
    selected = 0
    while True:
        rows, cols = stdscr.getmaxyx()
        cfg = load_config()
        blank = str(cfg.get("display", {}).get("blank_timeout", 600))
        kbd = os.environ.get("WD_XKB_LAYOUT", cfg.get("session", {}).get("keyboard_layout", "gb"))
        start_mode = cfg.get("session", {}).get("start_mode", "resume")

        annotated = [
            MenuItem("b", "Screen blank timeout", "settings_blank", value=f"{blank}s"),
            MenuItem("k", "Keyboard layout", "settings_kbd", value=kbd),
            MenuItem("s", "Startup mode", "settings_startup", value=start_mode),
        ]

        height, width = _box_dims("Settings", annotated)
        y = (rows - height) // 2
        x = (cols - width) // 2
        stdscr.erase()
        stdscr.noutrefresh()
        draw_menu(stdscr, y, x, "Settings", annotated, selected)
        curses.doupdate()
        key = stdscr.getch()
        selected, action = handle_key(key, annotated, selected)
        if action is None:
            continue
        if action == "back":
            return
        if action == "settings_blank":
            val = edit_value(stdscr, "Blank timeout (seconds, 0=off)", blank)
            if val is not None and val.isdigit():
                write_config_value("display", "blank_timeout", val)
                _restart_swayidle(val)
        elif action == "settings_kbd":
            val = edit_value(stdscr, "Keyboard layout (e.g. gb, us)", kbd)
            if val is not None:
                safe = val.replace("\\", "\\\\").replace('"', '\\"')
                write_config_value("session", "keyboard_layout", f'"{safe}"')
                _flash_message(stdscr, "Takes effect on next boot.")
        elif action == "settings_startup":
            new_mode = "menu" if start_mode == "resume" else "resume"
            write_config_value("session", "start_mode", f'"{new_mode}"')
```

- [ ] **Step 4: Run the full test suite**

```bash
uv run --with pytest pytest tests/test_wd_menu.py -v
```

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add bin/wd-menu tests/test_wd_menu.py
git commit -m "feat: startup mode toggle in Settings menu (issue #5)"
```

---

## Task 4: Push branch and open PR

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feat/startup-mode-setting
```

- [ ] **Step 2: Open PR**

```bash
gh pr create \
  --title "feat: startup mode toggle in Settings menu (#5)" \
  --body "$(cat <<'EOF'
## Summary

- Adds a **Startup mode** toggle to the Settings menu (`S` key)
- Cycles between `resume` (open last document on boot) and `menu` (show launcher on boot)
- Current value shown right-aligned in the Settings menu row, consistent with other settings
- Persisted to `/etc/writerdeck/config.toml` via existing `write_config_value()` helper

## Test plan

- [ ] Run `uv run --with pytest pytest tests/test_wd_menu.py -v` — all tests pass
- [ ] Pull branch on Pi, boot WriterDeck, open Settings — confirm Startup mode row appears with current value
- [ ] Press `S` — confirm value toggles between `resume` and `menu`
- [ ] Reboot — confirm new mode is respected on startup
EOF
)"
```
