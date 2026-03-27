#!/bin/bash
set -ouex pipefail

rm -f /etc/yum.repos.d/*terra*.repo || true
dnf5 config-manager setopt terra.enabled=0 terra-extras.enabled=0 terra-mesa.enabled=0 || true

dnf5 install -y tmux

systemctl enable podman.socket
