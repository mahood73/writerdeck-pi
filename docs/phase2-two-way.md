# Phase 2: Two-Way Sync

Phase 2 enables edits on both WriterDeck and capable machines.

## Scope

- Two-way sync for all project folders.
- Conflict policy: keep both versions; no destructive auto-resolution.

## Enablement steps

1. Update WriterDeck config mode:

```bash
sudo ./scripts/enable-phase2-two-way.sh
```

2. In Syncthing UI, change folder type to `Send & Receive` on:

- WriterDeck
- Home sync node

3. Keep staggered versioning enabled on home node.

## Conflict workflow

- Detect conflicts:

```bash
wd sync doctor
```

- Open conflicting files for manual merge:

```bash
wd sync resolve <project>/<file>.wg
```

or pass the conflict file path directly.

## Operational notes

- Do not auto-delete `*.sync-conflict-*` files.
- Resolve then remove conflict copies only after confirming merged content.
- Keep `sync.wait_timeout_sec` at 180 or higher for slow networks.
