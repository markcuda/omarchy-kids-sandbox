#!/bin/bash
# One-time bring-up on the test laptop. Usage: bash bringup.sh "<ssh public key>"
set -euo pipefail
KEY="${1:?usage: bringup.sh \"ssh-ed25519 AAAA... comment\"}"
sudo hostnamectl set-hostname kids-test
mkdir -p ~/.ssh && chmod 700 ~/.ssh
grep -qF "$KEY" ~/.ssh/authorized_keys 2>/dev/null || echo "$KEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
sudo systemctl enable --now sshd
echo "Bring-up done. Reach this box at:"
ip -4 -o addr show scope global | awk '{print "  ssh "USER"@"$4}' | cut -d/ -f1
echo "  (or: ssh $(whoami)@kids-test.local if mDNS resolves)"
