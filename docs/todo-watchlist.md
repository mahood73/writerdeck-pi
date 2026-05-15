# Untracked Possible Feature Checks

Small follow-up checks discovered while using WriterDeck. Anything with a GitHub
issue should live there instead; this file is only for loose, untracked ideas
that may or may not deserve an issue later.

## Session Ergonomics

- Consider a "new draft" option in the session menu, leading to a template picker once templates are in place.
- Decide whether the shell escape should return to the menu or optionally exit the WriterDeck session completely.

## Display And Input

- Revisit Foot font size after longer sessions.
- Keep an eye on UTF-8, box drawing, smart quotes, pound sign, and any other characters that were unreliable on the raw Linux console.
- Test display behaviour after unplug/replug or boot without HDMI attached.
- Test keyboard quirks, especially modifier/function key combinations.
- Bluetooth keyboards are outside the current scope. Note this explicitly if users start expecting pairing support.

## Installer and maintenance

- Keep the installer idempotent as defaults change.
- Decide whether to remove legacy migration paths after the next clean install cycle.
- Keep raw tty fallback working even as Cage/Foot becomes the normal path.

## Hardware

- Watch memory and swap use during longer sessions.
- Test behaviour after long idle periods.
