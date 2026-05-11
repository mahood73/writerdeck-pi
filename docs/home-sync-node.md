# Home Sync Node

The home sync node receives and versions everything the WriterDeck sends. The recommended setup is an always-on Linux host running Syncthing in Docker, with optional native clients on other machines for direct access.

## Docker setup

Copy the compose template and start it:

```bash
cp /path/to/repo/deploy/home-sync-node-compose.yml ./compose.yml
docker compose up -d
```

This creates two local volumes:

- `./syncthing-config` — Syncthing configuration
- `./writerdeck-data` — writing files

Configure the Syncthing folder:

- **Folder ID:** `writing`
- **Path:** `/data/writing`
- **Phase 1 type:** `Receive Only`
- **Phase 2 type:** `Send & Receive`
- **Versioning:** Staggered, 30-day retention

## Tailscale

Install Tailscale on the host OS (not inside the container):

```bash
sudo tailscale up
```

This gives the home node a stable tailnet address the Pi can reach from anywhere.

## Optional native clients

Other machines (desktop, laptop) can run Syncthing natively and mirror from the home node for direct editing or review.

- In Phase 1, keep these clients read-only.
- In Phase 2, two-way sync can be enabled where needed.
