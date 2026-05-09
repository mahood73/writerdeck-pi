# Writing Workflow Proposal

This is a working proposal for the WriterDeck writing model. It is intentionally
small and should change as the real writing workflow becomes clearer.

## Current direction

Use `~/Writing` as the top-level synced directory.

Rationale:

- `~/Writing` is a dedicated writing sync root across the Pi, NAS, desktop,
  and laptop.
- It avoids nested Syncthing folders and selective-sync ignore rules.
- Files remain easy to inspect and recover from any synced machine.
- The deck does not need to know about unrelated personal sync data.

## Editor model

WordGrinder is the current leading editor candidate.

The packaged Trixie version, WordGrinder 0.8, is likely good enough for the
first usable system. WordGrinder 0.9 exists upstream, but building it on the Pi
Zero 2W may consume all RAM and swap. Cross-compilation or source-build tuning
can wait unless 0.9 has a specific must-have fix.

Vim remains available for config and plain-text utility editing, but the
installer should not install a separate fallback editor.

## File model

Treat the WordGrinder `.wg` file as the working source of truth while writing.

On exit, a wrapper should export one or more companion files:

```text
draft.wg      working source
draft.rtf     Scrivener ingest copy
draft.txt     emergency/read-anywhere copy
```

RTF is likely a better Scrivener ingest target than Markdown because
WordGrinder has a simple rich-text model. Most writing will be plain text, but
RTF should preserve occasional italics, bold, headings, or similar formatting.

Plain text should still be exported because it is the long-term recovery format.

## Proposed directory shape

Initial top-level:

```text
~/Writing/
```

Possible future structure:

```text
~/Writing/
  longform/
    Novel Name/
      Novel Name.wg
      exports/
  shorts/
    2026-05-09_title.wg
    exports/
  notes/
    2026-05-09_reminder-note.wg
    exports/
  inbox/
    2026-05-09_untitled.wg
    exports/
```

The exact structure should wait until the Scrivener ingest workflow is designed.
The first usable system can start with a flatter structure if that keeps writing
friction low.

## Longform writing

The common case is one active novel at a time, broken down by chapter or scene.

WordGrinder's document group format appears to fit this well:

- one `.wg` per novel or major longform project
- internal documents for chapters, scenes, notes, or scraps
- export to RTF/TXT for sync and later Scrivener ingest

A future launcher can keep track of the current active longform project in a
small config file rather than asking every time.

Example:

```toml
[current]
longform = "Novel Name"
```

## Short pieces and notes

Short stories, blog posts, reminder notes, and one-off drafts probably do not
need document groups.

Use one `.wg` per piece, named predictably:

```text
YYYY-MM-DD_slug.wg
```

Examples:

```text
2026-05-09_flash-piece.wg
2026-05-09_blog-draft.wg
2026-05-09_reminder-note.wg
```

## Launcher shape

The launcher should prioritize getting to the writing surface quickly.

Possible first menu:

```text
Continue main novel
New short/blog/note
Open inbox
Shell
```

The launcher should avoid asking filing questions before the user can write.
When uncertain, create an inbox draft with a timestamped name and let later
desktop/Scrivener tooling tidy it.

## Sync and safety

Syncthing should sync `~/Writing`.

Tailscale should provide reliable connectivity while away from the home LAN.

Before real writing goes onto the deck, verify:

- WordGrinder saves the `.wg` file where expected.
- Export-on-exit creates `.rtf` and `.txt` files.
- Syncthing carries all expected files to the home node.
- Versioning or snapshots exist somewhere off-device.
- Scrivener ingest/import can consume the exported RTF without surprising loss.

Until then, use throwaway documents only.
