# Startup Mode Setting — Design Spec

**Issue:** #5 — Resume vs menu as a user-selectable session setting
**Date:** 2026-05-13

## Summary

Add a "Startup mode" toggle to the Settings menu so users can choose whether WriterDeck opens the last document or shows the launcher menu on boot. The setting is persisted in `/etc/writerdeck/config.toml` and takes effect on the next session start.

## Config

`config.toml` already has:

```toml
[session]
start_mode = "resume"
```

Valid values: `"resume"` (open last document) or `"menu"` (show launcher menu). No schema changes needed. The existing `write_config_value()` helper writes the value as an unquoted TOML string.

## Settings Menu

A third item is added to the Settings menu:

```text
 S  Startup mode          [resume] >
 B  Screen blank timeout    [600s]
 K  Keyboard layout           [gb]
```

The `value` field shows the current `start_mode` from config, right-aligned in `[value]` format — consistent with the existing rows.

## Toggle Behaviour

Activating "Startup mode" (via shortcut or Enter) immediately flips the value:

- `resume` → `menu`
- `menu` → `resume`

The new value is written to config via `write_config_value("session", "start_mode", ...)` and the menu redraws with the updated value. No flash message or confirmation dialog.

## Implementation Scope

All changes are in `bin/wd-menu`:

1. Add `MenuItem("s", "Startup mode", "settings_startup")` to `SETTINGS_MENU`.
2. In `handle_settings()`, include the annotated item with `value=start_mode`.
3. Add a handler for `"settings_startup"` that reads, flips, and writes `start_mode`.

## Tests

`tests/test_wd_menu.py` gets two new tests:

- Toggle from `resume` → `menu`: write a config with `start_mode = "resume"`, trigger `settings_startup`, assert the written value is `menu`.
- Toggle from `menu` → `resume`: same in reverse.

## Branch

All work on a feature branch (`feat/startup-mode-setting`); merged via PR.
