#!/bin/bash
# ==============================================================================
# bazzite-cps-kde — build.sh
# KERNEL_FLAVOR: "bazzite" (default) | "cachyos"
# ==============================================================================
set -ouex pipefail

KERNEL_FLAVOR="${KERNEL_FLAVOR:-bazzite}"

# Limpeza repos Terra
rm -f /etc/yum.repos.d/*terra*.repo || true
dnf5 config-manager setopt terra.enabled=0 terra-extras.enabled=0 terra-mesa.enabled=0 2>/dev/null || true

# COPR asus-linux (asusctl, supergfxctl, rog-control-center)
dnf5 copr enable -y lukenukem/asus-linux

# Pacotes base
dnf5 install -y --skip-installed \
    tmux \
    asusctl \
    supergfxctl \
    rog-control-center

systemctl enable podman.socket
systemctl enable asusd.service
systemctl enable supergfxd.service

# CachyOS addons runtime (ambas as variantes)
dnf5 copr enable -y bieszczaders/kernel-cachyos-addons

dnf5 install -y \
    cachyos-settings \
    scx-scheds

systemctl enable scx.service
echo 'SCX_SCHEDULER=scx_lavd' > /etc/default/scx

# VARIANTE CACHYOS
if [[ "${KERNEL_FLAVOR}" == "cachyos" ]]; then

    dnf5 copr enable -y bieszczaders/kernel-cachyos-lto

    BAZZITE_KERNEL_PKGS=$(rpm -qa --queryformat '%{NAME}\n' \
        | grep -E '^kernel(-core|-modules|-modules-core|-modules-extra|-modules-internal|-uki-virt)?$' \
        | sort -u)

    dnf5 install -y \
        kernel-cachyos-lto \
        kernel-cachyos-lto-devel-matched

    if [[ -n "${BAZZITE_KERNEL_PKGS}" ]]; then
        echo "${BAZZITE_KERNEL_PKGS}" | xargs dnf5 remove -y
    fi

    echo "kernel-cachyos-lto instalado com sucesso"

else
    echo "kernel Bazzite mantido — melhorias CachyOS runtime aplicadas"
fi
