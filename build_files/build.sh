#!/bin/bash
# ==============================================================================
# bazzite-cps-kde — build.sh
# KERNEL_FLAVOR: "bazzite" (default) | "cachyos"
#
# Variante bazzite : kernel Bazzite + melhorias CachyOS runtime
# Variante cachyos : kernel CachyOS LTO (Clang + ThinLTO + AutoFDO + Propeller) + melhorias runtime
# ==============================================================================
set -ouex pipefail

KERNEL_FLAVOR="${KERNEL_FLAVOR:-bazzite}"

# ------------------------------------------------------------------------------
# Limpeza repos Terra
# ------------------------------------------------------------------------------
rm -f /etc/yum.repos.d/*terra*.repo || true
dnf5 config-manager setopt terra.enabled=0 terra-extras.enabled=0 terra-mesa.enabled=0 2>/dev/null || true

# ------------------------------------------------------------------------------
# Pacotes base (ambas as variantes)
# ------------------------------------------------------------------------------
dnf5 install -y \
    tmux \
    asusctl \
    supergfxctl \
    rog-control-center

systemctl enable podman.socket
systemctl enable asusd.service
systemctl enable supergfxd.service

# ------------------------------------------------------------------------------
# CachyOS COPR addons — melhorias runtime (ambas as variantes)
# cachyos-settings : sysctl tweaks, scheduler hints, network stack tuning
# scx-scheds       : schedulers alternativos via sched-ext (scx_lavd, scx_rusty…)
# ------------------------------------------------------------------------------
dnf5 copr enable -y bieszczaders/kernel-cachyos-addons

dnf5 install -y \
    cachyos-settings \
    scx-scheds

# scx_lavd é o scheduler mais indicado para laptops gaming com APU AMD
systemctl enable scx.service
echo 'SCX_SCHEDULER=scx_lavd' > /etc/default/scx

# ------------------------------------------------------------------------------
# VARIANTE CACHYOS — substituição do kernel pelo CachyOS LTO
# ------------------------------------------------------------------------------
if [[ "${KERNEL_FLAVOR}" == "cachyos" ]]; then

    # COPR LTO é separado do COPR standard
    dnf5 copr enable -y bieszczaders/kernel-cachyos-lto

    # Identificar pacotes do kernel Bazzite instalado
    BAZZITE_KERNEL_PKGS=$(rpm -qa --queryformat '%{NAME}\n' \
        | grep -E '^kernel(-core|-modules|-modules-core|-modules-extra|-modules-internal|-uki-virt)?$' \
        | sort -u)

    # Instalar kernel CachyOS LTO primeiro
    dnf5 install -y \
        kernel-cachyos-lto \
        kernel-cachyos-lto-devel-matched

    # Só depois remover o kernel Bazzite
    if [[ -n "${BAZZITE_KERNEL_PKGS}" ]]; then
        echo "${BAZZITE_KERNEL_PKGS}" | xargs dnf5 remove -y
    fi

    echo "kernel-cachyos-lto instalado com sucesso"

# ------------------------------------------------------------------------------
# VARIANTE BAZZITE — mantém kernel Bazzite, aplica melhorias CachyOS runtime
# ------------------------------------------------------------------------------
else
    echo "kernel Bazzite mantido — melhorias CachyOS runtime aplicadas"
fi
