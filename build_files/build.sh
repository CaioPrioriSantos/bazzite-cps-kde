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
# scx-scheds já vem no Bazzite; cachyos-settings conflitua com zram-generator-defaults

systemctl enable scx.service 2>/dev/null || true
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

    dnf5 install -y --setopt=tsflags=noscripts \
        kernel-cachyos-lto \
        kernel-cachyos-lto-devel-matched

    if [[ -n "${BAZZITE_KERNEL_PKGS}" ]]; then
        echo "${BAZZITE_KERNEL_PKGS}" | xargs dnf5 remove -y
    fi

    CACHY_VER="$(rpm -q kernel-cachyos-lto --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
    depmod "${CACHY_VER}"
    dracut -vf "/usr/lib/modules/${CACHY_VER}/initramfs.img" "${CACHY_VER}"
    echo "kernel-cachyos-lto instalado com sucesso"

else
    echo "kernel Bazzite mantido — melhorias CachyOS runtime aplicadas"
fi

# CPU DMA latency — acesso sem root para PipeWire/JACK
cat > /usr/lib/udev/rules.d/99-bazzite-cps-dma-latency.rules << 'UDEV'
KERNEL=="cpu_dma_latency", GROUP="audio", MODE="0660"
UDEV

# journald — limita logs a 50MB
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-bazzite-cps.conf << 'JOURNALD'
[Journal]
SystemMaxUse=50M
JOURNALD

# Service timeouts — boot/shutdown mais rápido
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/99-bazzite-cps-timeouts.conf << 'SYSTEMD'
[Manager]
DefaultTimeoutStartSec=15s
DefaultTimeoutStopSec=10s
SYSTEMD

# ------------------------------------------------------------------------------
# DX — Developer Experience
# ------------------------------------------------------------------------------

# VS Code — repositório Microsoft
rpm --import https://packages.microsoft.com/keys/microsoft.asc
cat > /etc/yum.repos.d/vscode.repo << 'REPO'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
REPO
dnf5 install -y code

# Docker CE — repositório oficial Docker
dnf5 config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
dnf5 install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
systemctl enable docker.socket

# Shells
dnf5 install -y fish zsh

# distrobox + flatpak-builder
dnf5 install -y distrobox flatpak-builder

# Ferramentas de performance (toolkit Brendan Gregg / Bluefin DX)
dnf5 install -y \
    perf \
    bpftrace \
    sysprof \
    strace \
    ltrace \
    lsof \
    sysstat \
    pcp \
    flamegraph

# Limpeza repos temporários
rm -f /etc/yum.repos.d/vscode.repo
dnf5 config-manager setopt docker-ce-stable.enabled=0

# ------------------------------------------------------------------------------
# DX — Pacotes adicionais (bazzite-dx oficial)
# ------------------------------------------------------------------------------

# Performance adicional
dnf5 install -y \
    bcc \
    bpftop \
    tiptop \
    nicstat \
    numactl

# Mobile dev
dnf5 install -y \
    android-tools \
    usbmuxd

# Containers
dnf5 install -y \
    podman-machine \
    podman-tui

# Cache de compilação
dnf5 install -y \
    ccache \
    sccache

# Backup e sync cloud
dnf5 install -y \
    rclone \
    restic

# LLMs locais
dnf5 install -y python3-ramalama

# Docker — módulo iptable_nat para docker-in-docker
echo 'iptable_nat' > /usr/lib/modules-load.d/iptable_nat.conf

# Performance — ferramentas adicionais
dnf5 install -y \
    turbostat \
    valgrind \
    nethogs \
    hyperfine


# GitHub CLI
dnf5 install -y gh

# GParted — acesso direto a /dev, melhor fora de sandbox
dnf5 install -y gparted

# ------------------------------------------------------------------------------
# Firefox Mozilla — instalação de sistema em /opt/firefox
# ------------------------------------------------------------------------------
tmpdir="$(mktemp -d)"

FIREFOX_URL="$(curl -fsSLI -o /dev/null -w '%{url_effective}' 'https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64&lang=en-US')"
FIREFOX_ARCHIVE="$tmpdir/$(basename "${FIREFOX_URL%%\?*}")"
curl -fsSL "$FIREFOX_URL" -o "$FIREFOX_ARCHIVE"

mkdir -p /var/opt /var/usrlocal/bin /usr/share/applications
rm -rf /opt/firefox

case "$FIREFOX_ARCHIVE" in
  *.tar.xz)  tar -xJf "$FIREFOX_ARCHIVE" -C /opt ;;
  *.tar.bz2) tar -xjf "$FIREFOX_ARCHIVE" -C /opt ;;
  *.tar.gz)  tar -xzf "$FIREFOX_ARCHIVE" -C /opt ;;
  *) echo "Formato inesperado do Firefox: $FIREFOX_ARCHIVE"; exit 1 ;;
esac

ln -sf /opt/firefox/firefox /usr/local/bin/firefox

cat > /usr/share/applications/firefox-mozilla.desktop << 'DESKTOP'
[Desktop Entry]
Name=Firefox
Comment=Browse the Web
Exec=/opt/firefox/firefox %u
Icon=/opt/firefox/browser/chrome/icons/default/default128.png
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
DESKTOP

rm -rf "$tmpdir"

# ------------------------------------------------------------------------------
# Flatpaks — instalacao no primeiro boot via systemd oneshot
# ------------------------------------------------------------------------------
mkdir -p /usr/share/bazzite-cps

cat > /usr/share/bazzite-cps/flatpaks.list << 'FLATPAKEOF'
org.libreoffice.LibreOffice
org.gimp.GIMP
org.inkscape.Inkscape
org.kde.kdenlive
org.shotcut.Shotcut
fr.handbrake.ghb
com.obsproject.Studio
org.audacityteam.Audacity
org.musescore.MuseScore
org.videolan.VLC
com.stremio.Stremio
com.transmissionbt.Transmission
com.vysp3r.ProtonPlus
org.mozilla.Thunderbird
org.zotero.Zotero
org.telegram.desktop
com.spotify.Client
ar.com.tuxguitar.TuxGuitar
org.fedoraproject.MediaWriter
io.missioncenter.MissionCenter
FLATPAKEOF

cat > /usr/lib/systemd/system/bazzite-cps-flatpaks.service << 'SVCEOF'
[Unit]
Description=bazzite-cps — instalar Flatpaks no primeiro boot
After=network-online.target flatpak-system-helper.service
Wants=network-online.target
ConditionPathExists=!/var/lib/bazzite-cps/.flatpaks-installed

[Service]
Type=oneshot
Restart=on-failure
RestartSec=30
RemainAfterExit=yes
ExecStart=/usr/bin/bash -c 'mkdir -p /var/lib/bazzite-cps && flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo && xargs flatpak install --system --noninteractive flathub < /usr/share/bazzite-cps/flatpaks.list && touch /var/lib/bazzite-cps/.flatpaks-installed && flatpak override --system org.ardour.Ardour --filesystem=host'

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl enable bazzite-cps-flatpaks.service


# RPM Fusion Free — necessário para Ardour e plugins LV2
dnf5 install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm 2>/dev/null || true

# Ardour nativo + plugins de áudio
dnf5 install -y \
    ardour9 \
    lsp-plugins \
    calf \
    zam-plugins \
    zynaddsubfx \
    yoshimi \
    ladspa-tap-plugins \
    ladspa-fil-plugins

# Corrigir bbr → cubic (bbr falha no boot em composefs)
if [ -f /usr/lib/sysctl.d/75-networking.conf ]; then
  sed -i 's/^net\.ipv4\.tcp_congestion_control=bbr$/net.ipv4.tcp_congestion_control=cubic/' /usr/lib/sysctl.d/75-networking.conf || true
fi
