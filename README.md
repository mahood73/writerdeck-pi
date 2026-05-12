[![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/mahood73/writerdeck-pi?utm_source=oss&utm_medium=github&utm_campaign=mahood73%2Fwriterdeck-pi&labelColor=171717&color=FF570A&label=CodeRabbit+Reviews)](https://coderabbit.ai)

# WriterDeck

A distraction-free writing appliance for Raspberry Pi Zero 2W running Debian 13 (Trixie) Lite.

Boot the Pi and you're straight into WordGrinder. Quit and a small menu offers reopen, shell, reboot, or poweroff — nothing else. Writing syncs to a home node via Syncthing.

> **Personal project disclaimer:** This works on my desk, on my hardware, for my writing. It is shared in case it is useful, not as supported software. Back up your writing independently and don't trust this with anything you can't afford to lose.

## What's included

| Path                               | Purpose                                      |
| ---------------------------------- | -------------------------------------------- |
| `bin/wd`                           | CLI for writing workflow and sync            |
| `bin/wd-session`                   | tty1 session supervisor (editor → menu loop) |
| `config/config.toml`               | Default config                               |
| `deploy/`                          | Autologin, firewall, and sync-node templates |
| `scripts/install-trixie-lite.sh`   | Installer                                    |
| `scripts/uninstall-trixie-lite.sh` | Uninstaller                                  |
| `tests/test_wd.py`                 | CLI tests                                    |

## Quick start

1. Read [docs/setup-trixie-lite.md](docs/setup-trixie-lite.md).
2. Run `sudo ./scripts/install-trixie-lite.sh` on the Pi.
3. Configure Tailscale and pair a Syncthing folder with your home node.
4. Reboot — `tty1` opens directly into WordGrinder.

## CLI

```
wd open-latest           # Open the most recently modified draft
wd new [folder]          # Start a new draft
wd projects              # List project folders
wd export                # Export latest draft to TXT (Scrivener-ready)
wd export <path>         # Export a specific draft
wd export --all          # Export all drafts
```

**Export:** Drafts are exported to `exports/<filename>.txt` alongside the `.wg` file. The output uses `# Document Name` headings, allowing Scrivener's File → Import → Import and Split (select "at Markdown headings") to split it into individual Binder documents.

Config is read from `/etc/writerdeck/config.toml` by default, or set `WD_CONFIG` to override.

## Config

```toml
[paths]
root = "~/Writing"
default_project = "inbox"

[editor]
command = "wordgrinder"
```

## Session behaviour

- `tty1` autologin runs `wd-session`, which opens the editor immediately.
- Quitting the editor shows a menu: `w` reopen · `s` shell · `r` reboot · `p` poweroff.
- `tty2+` is a normal login shell.

## Sync

WriterDeck writes locally. Point any sync tool (Syncthing, Dropbox, Nextcloud, etc.) at your writing folder and it will carry files to other devices. WriterDeck has no opinion about which tool you use.
