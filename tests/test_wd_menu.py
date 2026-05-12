"""Tests for bin/wd-menu (pure logic — no curses required)."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import sys
import types
from pathlib import Path
import curses
import tempfile
import os

# ---------------------------------------------------------------------------
# Import bin/wd-menu without executing main()
# ---------------------------------------------------------------------------

def _load_wd_menu():
    path = Path(__file__).resolve().parent.parent / "bin" / "wd-menu"
    loader = importlib.machinery.SourceFileLoader("wd_menu", str(path))
    spec = importlib.util.spec_from_loader("wd_menu", loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules["wd_menu"] = module
    loader.exec_module(module)
    return module


menu = _load_wd_menu()


# ---------------------------------------------------------------------------
# handle_key — navigation
# ---------------------------------------------------------------------------

def _items():
    return menu.MAIN_MENU


def test_arrow_down_increments_selection():
    sel, action = menu.handle_key(curses.KEY_DOWN, _items(), 0)
    assert sel == 1
    assert action is None


def test_arrow_up_decrements_selection():
    sel, action = menu.handle_key(curses.KEY_UP, _items(), 2)
    assert sel == 1
    assert action is None


def test_arrow_up_wraps_to_bottom():
    sel, action = menu.handle_key(curses.KEY_UP, _items(), 0)
    assert sel == len(_items()) - 1
    assert action is None


def test_arrow_down_wraps_to_top():
    sel, action = menu.handle_key(curses.KEY_DOWN, _items(), len(_items()) - 1)
    assert sel == 0
    assert action is None


def test_enter_activates_current_item():
    sel, action = menu.handle_key(ord("\n"), _items(), 0)
    assert sel == 0
    assert action == "write"


def test_right_arrow_activates_current_item():
    sel, action = menu.handle_key(curses.KEY_RIGHT, _items(), 1)
    assert sel == 1
    assert action == "export"


def test_escape_returns_back():
    _, action = menu.handle_key(27, _items(), 2)
    assert action == "back"


def test_q_returns_back():
    _, action = menu.handle_key(ord("q"), _items(), 2)
    assert action == "back"


def test_left_arrow_returns_back():
    _, action = menu.handle_key(curses.KEY_LEFT, _items(), 1)
    assert action == "back"


# ---------------------------------------------------------------------------
# handle_key — letter shortcuts
# ---------------------------------------------------------------------------

def test_letter_w_activates_write():
    sel, action = menu.handle_key(ord("w"), _items(), 3)
    assert action == "write"
    assert sel == 0  # jumps to the Write item


def test_letter_uppercase_W_activates_write():
    _, action = menu.handle_key(ord("W"), _items(), 3)
    assert action == "write"


def test_letter_s_activates_shell():
    _, action = menu.handle_key(ord("s"), _items(), 0)
    assert action == "shell"


def test_letter_r_activates_reboot():
    _, action = menu.handle_key(ord("r"), _items(), 0)
    assert action == "reboot"


def test_letter_p_activates_poweroff():
    _, action = menu.handle_key(ord("p"), _items(), 0)
    assert action == "poweroff"


def test_unknown_key_returns_none_action():
    sel, action = menu.handle_key(ord("z"), _items(), 2)
    assert action is None
    assert sel == 2


# ---------------------------------------------------------------------------
# handle_key — export and settings submenus
# ---------------------------------------------------------------------------

def test_export_submenu_items():
    items = menu.EXPORT_MENU
    actions = [i.action for i in items]
    assert "export_latest" in actions
    assert "export_all" in actions
    assert "export_pick" in actions


def test_export_letter_l_activates_latest():
    _, action = menu.handle_key(ord("l"), menu.EXPORT_MENU, 0)
    assert action == "export_latest"


def test_export_letter_a_activates_all():
    _, action = menu.handle_key(ord("a"), menu.EXPORT_MENU, 0)
    assert action == "export_all"


def test_settings_submenu_items():
    items = menu.SETTINGS_MENU
    actions = [i.action for i in items]
    assert "settings_blank" in actions
    assert "settings_kbd" in actions


# ---------------------------------------------------------------------------
# write_config_value — TOML config file editing
# ---------------------------------------------------------------------------

def _write_config(content: str, section: str, key: str, value: str) -> str:
    with tempfile.NamedTemporaryFile(mode="w", suffix=".toml", delete=False, encoding="utf-8") as f:
        f.write(content)
        tmp = Path(f.name)
    original_config = menu.CONFIG_PATH
    menu.CONFIG_PATH = tmp
    try:
        menu.write_config_value(section, key, value)
        result = tmp.read_text(encoding="utf-8")
    finally:
        menu.CONFIG_PATH = original_config
        tmp.unlink(missing_ok=True)
    return result


def test_write_config_updates_existing_key():
    toml = "[display]\nblank_timeout = 600\n"
    result = _write_config(toml, "display", "blank_timeout", "300")
    assert "blank_timeout = 300" in result
    assert "blank_timeout = 600" not in result


def test_write_config_adds_missing_key_to_existing_section():
    toml = "[display]\nsome_other = 1\n"
    result = _write_config(toml, "display", "blank_timeout", "300")
    assert "blank_timeout = 300" in result


def test_write_config_adds_missing_section():
    toml = "[paths]\nroot = ~/Writing\n"
    result = _write_config(toml, "display", "blank_timeout", "300")
    assert "[display]" in result
    assert "blank_timeout = 300" in result


def test_write_config_creates_file_if_absent():
    with tempfile.NamedTemporaryFile(suffix=".toml", delete=False) as f:
        tmp = Path(f.name)
    tmp.unlink()  # remove so write_config_value sees FileNotFoundError
    original_config = menu.CONFIG_PATH
    menu.CONFIG_PATH = tmp
    try:
        menu.write_config_value("display", "blank_timeout", "600")
        result = tmp.read_text(encoding="utf-8")
    finally:
        menu.CONFIG_PATH = original_config
        tmp.unlink(missing_ok=True)
    assert "[display]" in result
    assert "blank_timeout = 600" in result


def test_write_config_does_not_duplicate_key():
    toml = "[display]\nblank_timeout = 600\n"
    result = _write_config(toml, "display", "blank_timeout", "300")
    assert result.count("blank_timeout") == 1


# ---------------------------------------------------------------------------
# list_wg_files
# ---------------------------------------------------------------------------

def test_list_wg_files_returns_newest_first():
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        a = root / "a.wg"
        b = root / "b.wg"
        a.write_text("x")
        b.write_text("x")
        os.utime(a, (1000, 1000))  # older
        os.utime(b, (2000, 2000))  # newer
        files = menu.list_wg_files(root)
        assert files[0] == b
        assert files[1] == a


def test_list_wg_files_ignores_non_wg():
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "doc.txt").write_text("x")
        (root / "doc.wg").write_text("x")
        files = menu.list_wg_files(root)
        assert len(files) == 1
        assert files[0].name == "doc.wg"


def test_list_wg_files_empty_dir():
    with tempfile.TemporaryDirectory() as d:
        files = menu.list_wg_files(Path(d))
        assert files == []


def test_list_wg_files_missing_dir():
    files = menu.list_wg_files(Path("/nonexistent/path"))
    assert files == []
