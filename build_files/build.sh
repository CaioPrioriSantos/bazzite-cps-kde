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

# COPR asus-linux
dnf5 copr enable -y lukenukem/asus-linux

# Pacotes base (tmux já vem na imagem base — não instalar)
dnf5 install -y \
    asusctl \
    supergfxctl \
    rog-control-center

systemctl enable podman.socket
systemctl enable asusd.service
systemctl enable supergfxd.service

# CachyOS addons runtime
dnf5 copr enable -y bieszczaders/kernel-cachyos-addons
dnf5 install -y cachyos-settings scx-scheds

systemctl enable scx.service
echo 'SCX_SCHEDULER=scx_lavd' > /etc/default/scx

# ------------------------------------------------------------------------------
# Tweaks de performance (sysctl) — sem conflito com tuned do Bazzite
# Não tocamos em vm.swappiness nem I/O schedulers (geridos pelo tuned)
# ------------------------------------------------------------------------------
cat > /usr/lib/sysctl.d/99-bazzite-cps-perf.conf << 'SYSCTL'
# Cache VFS — retém mais cache de directórios/inodes (padrão=100)
vm.vfs_cache_pressure = 50
# Flush de escrita — 256MB antes de começar, 64MB em background
vm.dirty_bytes = 268435456
vm.dirty_background_bytes = 67108864
# Frequência de flush — menos wakeups do kernel (padrão=500)
vm.dirty_writeback_centisecs = 1500
# Readahead de swap desativado — melhora latência com ZRAM
vm.page-cluster = 0
# Watchdog desativado — poupa ciclos de CPU
kernel.nmi_watchdog = 0
# Fila de rede maior — menos drops em carga alta
net.core.netdev_max_backlog = 16384
# Limite de ficheiros abertos
fs.file-max = 2097152
SYSCTL

# ------------------------------------------------------------------------------
# Tweaks udev — áudio, timers, watchdog
# ------------------------------------------------------------------------------
# Audio: desativa power saving em AC (evita crackling)
cat > /usr/lib/modprobe.d/99-bazzite-cps-audio.conf << 'MODPROBE'
options snd_hda_intel power_save=0
MODPROBE

# Blacklist watchdogs desnecessários (liberta CPU)
cat > /usr/lib/modprobe.d/99-bazzite-cps-watchdog.conf << 'MODPROBE'
blacklist iTCO_wdt
blacklist sp5100_tco
MODPROBE

# Permissões HPET/RTC para grupo audio (timers de alta precisão)
cat > /usr/lib/udev/rules.d/99-bazzite-cps-audio-timers.rules << 'UDEV'
KERNEL=="rtc0", GROUP="audio"
KERNEL=="hpet", GROUP="audio"
UDEV

# Audio PM: desativa power saving em AC, reativa em bateria
cat > /usr/lib/udev/rules.d/99-bazzite-cps-audio-pm.rules << 'UDEV'
ACTION=="add", SUBSYSTEM=="sound", KERNEL=="card*", DRIVERS=="snd_hda_intel", \
  TEST!="/run/udev/snd-hda-intel-powersave", \
  RUN+="/usr/bin/bash -c 'touch /run/udev/snd-hda-intel-powersave; \
    [[ $$(cat /sys/class/power_supply/BAT0/status 2>/dev/null) != \"Discharging\" ]] && \
    echo 0 > /sys/module/snd_hda_intel/parameters/power_save'"
UDEV

# ------------------------------------------------------------------------------
# VARIANTE CACHYOS
# ------------------------------------------------------------------------------
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
