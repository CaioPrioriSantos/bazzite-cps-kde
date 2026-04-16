#!/usr/bin/env bash
set -euo pipefail
ASSETS_DIR="$(cd "$(dirname "$0")" && pwd)/assets"
TMP_DIR="$(mktemp -d)"
mkdir -p "${ASSETS_DIR}"
trap 'rm -rf "${TMP_DIR}"' EXIT
cd "${TMP_DIR}"
curl -fL -o warsaw_setup64.run \
  https://cloud.gastecnologia.com.br/bb/downloads/ws/warsaw_setup64.run
chmod +x warsaw_setup64.run
./warsaw_setup64.run --noexec --target ./warsaw_setup 2>/dev/null || true
DEB_PATH="$(find ./warsaw_setup -maxdepth 1 -type f -name 'warsaw_*_amd64.deb' | head -n1)"
[[ -z "${DEB_PATH}" ]] && { echo "ERROR: .deb não encontrado"; exit 1; }
cp -f "${DEB_PATH}" "${ASSETS_DIR}/warsaw_current_amd64.deb"
echo "OK: $(basename ${DEB_PATH}) → ${ASSETS_DIR}/warsaw_current_amd64.deb"
