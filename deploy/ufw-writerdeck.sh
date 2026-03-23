#!/bin/sh
set -eu

# Baseline firewall for WriterDeck. Replace RFC1918 ranges if your LAN differs.
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# SSH from local networks and Tailscale tailnet subnet.
ufw allow from 192.168.0.0/16 to any port 22 proto tcp
ufw allow from 10.0.0.0/8 to any port 22 proto tcp
ufw allow from 100.64.0.0/10 to any port 22 proto tcp

# Syncthing GUI/API (local admin only) and sync transport.
ufw allow from 127.0.0.1 to any port 8384 proto tcp
ufw allow from 192.168.0.0/16 to any port 22000 proto tcp
ufw allow from 10.0.0.0/8 to any port 22000 proto tcp
ufw allow from 100.64.0.0/10 to any port 22000 proto tcp
ufw allow from 192.168.0.0/16 to any port 21027 proto udp
ufw allow from 10.0.0.0/8 to any port 21027 proto udp
ufw allow from 100.64.0.0/10 to any port 21027 proto udp

ufw --force enable
ufw status verbose
