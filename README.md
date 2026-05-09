# WriterDeck Toolkit

Implementation of the WriterDeck v2 plan for Raspberry Pi Zero 2W on Debian 13.3 (Trixie) Lite.

## What is included

- `bin/wd`: CLI for writing workflow and sync operations.
- `bin/wd-session`: tty1 session supervisor (editor + exit menu + shell drop).
- `config/config.toml`: default config contract.
- `deploy/`: autologin, profile, firewall, and home sync-node templates.
- `scripts/install-trixie-lite.sh`: MVP install workflow for the deck.
- `scripts/uninstall-trixie-lite.sh`: removes WriterDeck tty1 integration and restores backed-up system files.
- `scripts/enable-phase2-two-way.sh`: phase transition helper.
- `tests/test_wd.py`: CLI behavior tests.

## CLI commands

- `wd open-latest`
- `wd new <foldername>`
- `wd projects`
- `wd sync status`
- `wd sync now`
- `wd sync doctor`
- `wd sync resolve <path>`

## Config contract

Default path: `/etc/writerdeck/config.toml`

```toml
[paths]
root = "/home/<pi-user>/Writing"
default_project = "inbox"

[editor]
command = "wordgrinder"

[sync]
folder_id = "writing"
mode = "single_writer" # or "two_way"
wait_timeout_sec = 180
```

## Quick start

1. Read [docs/setup-trixie-lite.md](docs/setup-trixie-lite.md).
2. Run `sudo ./scripts/install-trixie-lite.sh` on the Pi.
   The installer targets the invoking sudo user by default (`$SUDO_USER`).
3. Configure Tailscale and Syncthing folder pairing.
4. Reboot and verify `tty1` opens directly into WordGrinder.
5. Quit WordGrinder and verify the WriterDeck menu appears (`w/s/r/p`).

To remove the tty1 WriterDeck login/session behavior later, run `sudo ./scripts/uninstall-trixie-lite.sh`.

## Session behavior

- `tty1` autologin launches `wd-session`.
- Exiting the editor opens a session menu instead of immediate relogin loop.
- Menu actions:
  - `w` reopen editor
  - `s` open shell (type `exit` to return to menu)
  - `r` reboot (confirmation + sudo/systemd)
  - `p` poweroff (confirmation + sudo/systemd)
- `tty2+` remains a normal shell login.

## Phase model

- Phase 1 (default): single-writer (`Send Only` on deck, `Receive Only` on home).
- Phase 2: two-way sync with conflict preservation and manual merge tooling.

Phase 2 details are in [docs/phase2-two-way.md](docs/phase2-two-way.md).
