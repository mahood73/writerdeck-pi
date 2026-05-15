# Writing Workflow Design

Date: 2026-05-11

## Summary

WriterDeck is an appliance. The session model should get the user writing as fast as possible and stay out of the way. Structure and organisation belong on the desktop, not on the device.

## Session model

Boot on `tty1` launches `wd-session`, which immediately calls `wd open-latest`. No prompt, no menu, no choice. The user is in their last document within seconds.

On exit from WordGrinder, the WriterDeck menu appears with writing, export, settings, shell, reboot, and poweroff actions.

Export is a deliberate manual action run from the shell (`wd export`, not yet implemented). It is not triggered automatically on exit — the user may have worked on several files in one session, and auto-export would be noisy and unpredictable.

## File model

- `~/Writing` is the writing root (user-configurable at install time).
- Structure inside `~/Writing` is freeform. The tool does not enforce folders or taxonomy. Users organise on the desktop.
- `.wg` files are the working source of truth.
- Exported files (RTF, TXT) will land in an `exports/` subfolder alongside their source — exact behaviour to be defined when export is implemented.

## Target user

Technical enough to run an installer and SSH in, but not a developer. Comfortable following instructions; not comfortable editing TOML files to change preferences. The device itself should feel like an appliance.

## Roadmap (out of scope for this design)

- **Resume vs menu setting:** Allow users to choose between "always open latest" (current behaviour) and "show a choice menu on boot". Selectable via a setup/config interface, not by hand-editing config files.
- **Export workflow:** When to export, where files land, which formats. RTF for Scrivener ingest, TXT as a plain recovery copy.
- **Setup/config interface:** An in-session menu for tweaking device behaviour (session mode, writing folder, editor command) without requiring shell access or config file editing.
- **External storage independence:** WriterDeck should not know about storage, backup, or transfer tools outside the writing folder.
