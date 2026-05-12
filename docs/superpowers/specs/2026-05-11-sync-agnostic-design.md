# Sync-Agnostic wd and Configurable Writing Folder

Date: 2026-05-11
Issue: #2

## Summary

Remove all Syncthing-specific code from `bin/wd` and the config schema. Add a writing folder prompt to the installer so users can point WriterDeck at any sync tool's folder. The writing root becomes a folder the user manages independently; `wd` has no opinion about what syncs it.

## bin/wd removals

The following are deleted entirely:

- `SyncthingClient` class
- `_find_syncthing_api_key()`
- `_find_conflicts()`
- `_resolve_target_and_conflicts()`
- `_print_status()`
- `cmd_sync_status`, `cmd_sync_now`, `cmd_sync_doctor`, `cmd_sync_resolve`
- `VALID_SYNC_MODES` constant
- The `sync` subparser block in `build_parser()`
- `folder_id`, `sync_mode`, `wait_timeout_sec` from `Config.__init__`
- Unused imports: `json`, `time`, `urllib`, `xml.etree.ElementTree`

The public CLI surface becomes: `open-latest`, `new`, `projects`, plus the `--config` flag.

## Config schema

`config/config.toml` template becomes:

```toml
[paths]
root = "~/Writing"
default_project = "inbox"

[editor]
command = "wordgrinder"
```

`~/Writing` works as-is because `Config` already calls `.expanduser()`. The `[sync]` section is removed entirely. No migration or deprecation notice — this is a personal appliance with no downstream API consumers.

`scripts/enable-phase2-two-way.sh` is deleted (its only purpose was flipping `sync.mode`).

## Installer: writing folder prompt

A new `prompt_writing_folder` step runs after the display settings prompt.

```
Writing folder [~/Writing]:
```

- Default is `~/Writing` (shown literally; the installer resolves it to the target user's home when writing config)
- If the entered path falls outside the target user's home directory, warn and re-confirm:
  ```
  Warning: this path is outside your home directory. Are you sure? [y/N]:
  ```
- The confirmed path is written verbatim into `/etc/writerdeck/config.toml` as `root`

**Directory handling:**
- If the directory does not exist: create it (and `inbox/` inside) with correct user/group ownership, log `Created writing folder at <path>`
- If it already exists: skip creation, log `Writing folder already exists at <path>`
- Either way: verify the target user can write into the folder. If not, exit with a clear error rather than installing a broken config.

`deploy/home-sync-node-compose.yml` and `deploy/ufw-writerdeck.sh` are left in place — they are useful deploy-time references for users running Syncthing, and are not coupled to `wd`.

## Tests

- Remove `test_sync_doctor_reports_conflicts` and `test_sync_resolve_requires_conflict_copy`
- Remove the `[sync]` section from `_write_config()` in the test fixture
- No new tests required

## Installer: migration guards

The installer's `is_managed_sync_writerdeck_config()` and `is_managed_legacy_config()` functions detect whether an existing `/etc/writerdeck/config.toml` was created by a previous installer run, so they can safely upgrade it. Both currently match on sync-containing patterns. Update them to also recognise the old sync config shape, so a re-run over an existing install migrates the config to the new schema rather than leaving the old one in place and writing a `.dist` file.

## README

- Remove `wd sync` commands from the CLI table
- Remove the `[sync]` block from the Config section
- Trim the Sync section to one sentence: sync is handled by whichever tool the user points at the writing folder
