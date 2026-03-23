# Home Sync Node (Hybrid)

Primary recommendation: always-on Linux host running Syncthing in Docker, with optional native Linux/macOS mirror clients.

## Docker node setup

From a host directory:

```bash
cp /path/to/repo/deploy/home-sync-node-compose.yml ./compose.yml
docker compose up -d
```

Local volumes:

- `./syncthing-config`
- `./writerdeck-data`

Set Syncthing folder:

- Folder id: `writing`
- Path: `/data/writing`
- Phase 1 type: `Receive Only`
- Phase 2 type: `Send & Receive`

Enable staggered versioning and 30-day retention.

## Tailscale

Install and run Tailscale on the host OS (not in container for MVP simplicity):

```bash
sudo tailscale up
```

## Optional native clients

Linux/macOS native Syncthing clients can mirror from the home node for direct editing/review.

- In Phase 1: keep them read-only.
- In Phase 2: allow two-way where desired.
