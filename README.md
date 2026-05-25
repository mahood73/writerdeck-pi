[![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/mahood73/writerdeck-pi?utm_source=oss&utm_medium=github&utm_campaign=mahood73%2Fwriterdeck-pi&labelColor=171717&color=FF570A&label=CodeRabbit+Reviews)](https://coderabbit.ai)

# WriterDeck

A distraction-free writing appliance built on Debian. Primarily targets the Raspberry Pi Zero 2W; also works on any Debian machine (x86, ARM, or otherwise) — handy for testing before buying hardware.

Boot the Pi and you're straight into WordGrinder. Quit and a small menu offers writing, export, settings, shell, reboot, and poweroff actions.

> **Personal project disclaimer:** This works on my desk, on my hardware, for my writing. It is shared in case it is useful, not as supported software. Back up your writing independently and don't trust this with anything you can't afford to lose.

## What's included

| Path                               | Purpose                                      |
| ---------------------------------- | -------------------------------------------- |
| `bin/wd`                           | CLI for the writing workflow                 |
| `bin/wd-session`                   | tty1 session supervisor (editor → menu loop) |
| `config/config.toml`               | Default config                               |
| `deploy/`                          | Autologin, terminal, and firewall templates  |
| `scripts/install.sh`   | Installer                                    |
| `scripts/uninstall.sh` | Uninstaller                                  |
| `tests/test_wd.py`                 | CLI tests                                    |

## Quick start

1. Read [docs/setup.md](docs/setup.md).
2. Run `sudo ./scripts/install.sh` on the device.
3. Reboot — `tty1` opens directly into WordGrinder.

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
- Quitting the editor shows the WriterDeck menu: `w` write · `e` export · `,` settings · `s` shell · `r` reboot · `p` poweroff.
- Settings currently includes screen blank timeout, keyboard layout, and startup mode.
- `tty2+` is a normal login shell.

## Tests

Run the full test suite with:

```bash
uv --cache-dir /private/tmp/uv-cache run --with pytest pytest -q
```

The `uv` command supplies pytest without adding a project dependency file. The
explicit cache directory avoids permission issues on systems where `~/.cache/uv`
is not writable by the current environment.

If pytest is unavailable, this partial fallback runs only the `unittest`-based
CLI tests:

```bash
python3 -m unittest tests.test_wd -v
```
