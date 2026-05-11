# Todo / Watchlist

Ideas and follow-up work discovered while testing the WriterDeck as a real
writing appliance. These are not commitments for the next change; they are the
parking lot for things worth revisiting after more use.

## Writing workflow

- Export-on-exit to RTF and TXT.
- Investigate WordGrinder's "export all" behavior for combined documents and
  document groups.
- Work out whether exports should live beside `.wg` files or under an
  `exports/` subdirectory.
- Decide how Scrivener ingest should work before imposing too much directory
  structure.
- WordGrinder templates for common draft types:
  - note
  - chapter
  - scene
  - short story
  - blog post
- Decide whether templates should be copied from known-good `.wg` files created
  by WordGrinder itself.

## Sync and recovery

- Confirm Syncthing behavior across Pi, desktop, NAS, and laptop.
- Decide whether the WriterDeck should be Send Only, Send & Receive, or a
  phase-based transition between the two.
- Verify NAS/home-node versioning behavior with real `.wg`, `.rtf`, and `.txt`
  files.
- Test conflict scenarios intentionally before trusting two-way editing.
- Add a simple "sync status" indication to the menu if it can be done without
  clutter.

## Terminal and display

- Revisit Foot font size after longer sessions.
- Revisit the WordPerfect/DOS colour palette after longer sessions.
- Keep an eye on UTF-8, box drawing, smart quotes, pound sign, and any other
  characters that were unreliable on the raw Linux console.
- Investigate screen blanking under `cage` + `foot`.
- Investigate sleep mode / power save behavior for the Pi and HDMI display.
- Decide whether lack of Wayland output power management in Cage is acceptable
  or whether another compositor is worth testing.

## Session ergonomics

- Power/reboot ergonomics from the menu.
- Consider a direct "sync now" menu item.
- Consider a "new inbox draft" menu item once the template/story is clearer.
- Decide whether the shell escape should return to the menu or optionally exit
  the WriterDeck session completely.
- Document the Alt/function-key limitation inside WordGrinder and the tty2
  emergency path.

## Installer and maintenance

- Keep the installer idempotent as defaults change.
- Decide whether to remove legacy migration paths after the next clean install
  cycle.
- Consider adding a dry-run or status mode to the installer.
- Consider adding a small post-install verification command.
- Keep raw tty fallback working even as Cage/Foot becomes the normal path.

## Hardware

- Watch memory and swap use during longer sessions.
- Test behavior after long idle periods.
- Test keyboard quirks, especially modifier/function key combinations.
- Test display behavior after unplug/replug or boot without HDMI attached.
