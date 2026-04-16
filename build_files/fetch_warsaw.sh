#!/usr/bin/env bash
set -euo pipefail

ASSETS_DIR="$(cd "$(dirname "$0")" && pwd)/assets"
mkdir -p "${ASSETS_DIR}"

curl -fL -o "${ASSETS_DIR}/warsaw_current_amd64.deb" \
  https://cloud.gastecnologia.com.br/bb/downloads/ws/warsaw_setup64.deb

echo "OK: warsaw_current_amd64.deb -> ${ASSETS_DIR}/warsaw_current_amd64.deb"
ls -lh "${ASSETS_DIR}/warsaw_current_amd64.deb"
