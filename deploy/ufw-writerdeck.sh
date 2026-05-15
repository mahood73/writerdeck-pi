#!/bin/sh
set -eu

# Baseline firewall for WriterDeck. Replace RFC1918 ranges if your LAN differs.
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# SSH from local networks.
ufw allow from 192.168.0.0/16 to any port 22 proto tcp
ufw allow from 10.0.0.0/8 to any port 22 proto tcp

ufw --force enable
ufw status verbose
