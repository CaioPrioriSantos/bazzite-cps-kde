#!/bin/bash

set -ouex pipefail

dnf5 config-manager setopt terra-mesa.enabled=0 terra.enabled=0 terra-extras.enabled=0 || true

dnf5 install -y tmux

systemctl enable podman.socket
