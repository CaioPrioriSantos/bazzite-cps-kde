#!/bin/bash

set -ouex pipefail

dnf5 config-manager disable terra-mesa || true

dnf5 install -y tmux

systemctl enable podman.socket
