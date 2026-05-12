# Todo / Watchlist

Ideas and follow-up work discovered while testing the WriterDeck as a real
writing appliance. These are not commitments for the next change; they are the
parking lot for things worth revisiting after more use.

## Architecture

- Make `wd` sync-agnostic. Currently the CLI is tightly coupled to Syncthing's API (`sync status/now/doctor/resolve`). Writing commands should not need to know about the sync layer. Likely direction: remove sync subcommands from `wd` entirely and let Syncthing run as a standalone daemon. Could also mean a separate `wd-sync` CLI or a pluggable backend, but full separation is cleanest.
- As part of sync-agnostic work: add a "pick your writing folder" prompt to the installer, defaulting to `~/Writing`. The writing root should be a user choice at install time, not a hardcoded assumption. Some sync tools (e.g. Dropbox) enforce their own folder location, so the installer needs to accommodate paths outside the home directory or in fixed sync roots.
- Conflict reconciliation. Syncthing preserves both versions of a file when there's a conflict — design a workflow for detecting and merging them. Depends on sync-agnostic direction above.

## Writing workflow

- Export to RTF as the primary interchange format. WordGrinder exports RTF natively; from there users can get to Word, Google Docs, Scrivener, or anything else without WriterDeck needing to know about specific apps. Plain TXT alongside as a recovery/read-anywhere copy.
- Work out whether exports should live beside `.wg` files or under an `exports/` subdirectory.
- WordGrinder templates for common draft types (note, chapter, scene, short story, blog post). Templates may also solve the "what are you writing today?" session start problem — instead of a project picker, a short template menu. Boot goes to last document by default; "new" drops into a template picker that sets folder and filename pattern automatically.
- Decide whether templates should be copied from known-good `.wg` files created by WordGrinder itself.
- Scrivener ingest via RTF — design the import workflow once export behaviour is settled.
- Scrivener continuous sync — investigate exporting one `.txt` file per WordGrinder document into a folder that Scrivener's "Sync with External Folder" feature watches. Would enable automatic pickup on project open without needing Import and Split. Likely an opt-in flow alongside the current manual export: `wd export` stays as-is; a future mode could export flat files on session exit and keep Scrivener always up to date. Depends on users setting up the sync folder once in Scrivener.

## Writing aids

- Word count and progress tracking. WordGrinder shows a word count for the current document but has no session tracking. Since `.wg` files are plain text, a simple external word count tool is feasible. Targets and streaks are probably better handled inside the editor than in the launcher — worth investigating what WordGrinder exposes before designing anything.

## Audio

- Keyboard feedback sounds (typewriter click) and ambient/white noise as optional session aids. Both would need to run alongside the editor without interfering with it. Opt-in only — off by default.

## Launcher and menu UI

- The current `wd-session` menu is intentionally minimal (plain text, single keypress) but doesn't match the feel of WordGrinder's own ncurses interface. A future launcher could use ncurses to present a full-screen menu that feels native alongside WordGrinder — better use of the screen, more holistic UX. Would also make a template picker, theme selection, and settings more feasible without feeling like a shell script.

## Session ergonomics

- Resume vs menu as a user-selectable setting. Default is resume (boot straight to last document). Option to show a session menu instead. Should be configurable via a setup interface, not by hand-editing TOML.
- Consider a "new draft" option in the session menu, leading to a template picker once templates are in place.
- Switchable editor. The editor command is already configurable in `config.toml`, but document clearly how to swap WordGrinder for another editor (Vim, Nano, etc.) — this will be a common question from the target audience.
- Decide whether the shell escape should return to the menu or optionally exit the WriterDeck session completely.
- Document the Alt/function-key limitation inside WordGrinder and the tty2 emergency path.

## Themes and appearance

- Theme support. Currently the colour palette and font are hardcoded in `foot.ini`. The installer and/or setup menu should offer quick-pick themes (e.g. WordPerfect/DOS, dark, light, high contrast) and a path to full customisation later.
- Revisit Foot font size after longer sessions.
- Keep an eye on UTF-8, box drawing, smart quotes, pound sign, and any other characters that were unreliable on the raw Linux console.

## Power saving

- Screen blanking is not working correctly — investigate and fix. Blanking is configured via kernel `consoleblank` and the installer sets a default of 600 seconds, but it is not behaving as expected under `cage` + `foot`.
- Sleep mode — investigate Pi Zero 2W sleep/suspend behaviour and whether it can be triggered from the session menu or after a longer idle period.
- Decide whether lack of Wayland output power management in Cage is acceptable or whether another compositor is worth testing.
- Test display behaviour after unplug/replug or boot without HDMI attached.

## Sync and recovery

- Confirm Syncthing behaviour across Pi, desktop, NAS, and laptop.
- Verify NAS/home-node versioning behaviour with real `.wg`, `.rtf`, and `.txt` files.
- Test conflict scenarios intentionally before trusting two-way editing.

## Installer and maintenance

- Keep the installer idempotent as defaults change.
- Add a post-install verification command — runs the checklist and reports pass/fail.
- Add a dry-run or status mode to the installer.
- Decide whether to remove legacy migration paths after the next clean install cycle.
- Keep raw tty fallback working even as Cage/Foot becomes the normal path.

## Hardware

- Watch memory and swap use during longer sessions.
- Test behaviour after long idle periods.
- Test keyboard quirks, especially modifier/function key combinations.
- Bluetooth keyboards are outside the current scope — USB HID only for now. Worth noting explicitly in docs so users don't troubleshoot a pairing problem expecting it to work.
- USB drive as an alternative to network sync — not explicitly supported, but not blocked either. Leave to the user for now.
