#!/bin/bash
# ==============================================================================
# bazzite-cps-kde — build.sh
# KERNEL_FLAVOR: "bazzite" (default) | "cachyos"
# ==============================================================================
set -ouex pipefail

KERNEL_FLAVOR="${KERNEL_FLAVOR:-bazzite}"

# DNF5 — downloads paralelos
sed -i '/^\[main\]/a max_parallel_downloads=10' /etc/dnf/dnf.conf

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

# ------------------------------------------------------------------------------
# ASUS + Tuned sync — tuned manda, ASUS acompanha + aplica PPT/NV
# ------------------------------------------------------------------------------
mkdir -p /etc/asusd /usr/local/bin /usr/lib/systemd/system

cat > /etc/asusd/asusd.ron << 'RON'
(
    charge_control_end_threshold: 94,
    base_charge_control_end_threshold: 0,
    disable_nvidia_powerd_on_battery: true,
    ac_command: "",
    bat_command: "",
    platform_profile_linked_epp: false,
    platform_profile_on_battery: Quiet,
    change_platform_profile_on_battery: false,
    platform_profile_on_ac: Performance,
    change_platform_profile_on_ac: false,
    profile_quiet_epp: Power,
    profile_balanced_epp: BalancePower,
    profile_custom_epp: Performance,
    profile_performance_epp: Performance,
    ac_profile_tunings: {
        Performance: (
            enabled: true,
            group: {
                PptApuSppt: 100,
                PptPlatformSppt: 115,
            },
        ),
        Balanced: (
            enabled: true,
            group: {
                PptApuSppt: 45,
                PptPlatformSppt: 65,
            },
        ),
        Quiet: (
            enabled: true,
            group: {
                PptApuSppt: 25,
                PptPlatformSppt: 40,
            },
        ),
    },
    dc_profile_tunings: {
        Performance: (
            enabled: true,
            group: {
                PptApuSppt: 50,
                PptPlatformSppt: 80,
            },
        ),
        Balanced: (
            enabled: true,
            group: {
                PptApuSppt: 30,
                PptPlatformSppt: 45,
            },
        ),
        Quiet: (
            enabled: true,
            group: {
                PptApuSppt: 15,
                PptPlatformSppt: 30,
            },
        ),
    },
    armoury_settings: {},
)
RON

cat > /usr/local/bin/asus-tuned-sync.sh << 'SH'
#!/bin/bash
set -euo pipefail

get_ac() {
    cat /sys/class/power_supply/AC0/online 2>/dev/null || \
    cat /sys/class/power_supply/AC/online 2>/dev/null || \
    echo 1
}

get_tuned() {
    tuned-adm active 2>/dev/null | sed 's/^Current active profile: //'
}

LAST=""

while true; do
    AC="$(get_ac)"
    TP="$(get_tuned)"

    case "$TP" in
        throughput-performance-bazzite|throughput-performance)
            PP="performance"
            if [ "$AC" = "1" ]; then
                PL1=125; PL2=150; FPPT=150; APU=100; PLATFORM=115; NV=87
            else
                PL1=80; PL2=100; FPPT=100; APU=50; PLATFORM=80; NV=83
            fi
            ;;
        balanced-bazzite|balanced|balanced-battery|balanced-battery-bazzite)
            PP="balanced"
            if [ "$AC" = "1" ]; then
                PL1=80; PL2=100; FPPT=100; APU=45; PLATFORM=65; NV=83
            else
                PL1=45; PL2=60; FPPT=60; APU=30; PLATFORM=45; NV=80
            fi
            ;;
        powersave-bazzite|powersave|powersave-battery-bazzite)
            PP="quiet"
            if [ "$AC" = "1" ]; then
                PL1=35; PL2=45; FPPT=45; APU=25; PLATFORM=40; NV=75
            else
                PL1=20; PL2=25; FPPT=25; APU=15; PLATFORM=30; NV=75
            fi
            ;;
        *)
            sleep 1
            continue
            ;;
    esac

    CUR="$TP|$AC|$PP|$PL1|$PL2|$FPPT|$APU|$PLATFORM|$NV"

    if [ "$CUR" != "$LAST" ]; then
        LAST="$CUR"
        echo "$PP"       > /sys/firmware/acpi/platform_profile
        echo "$PL1"      > /sys/devices/platform/asus-nb-wmi/ppt_pl1_spl
        echo "$PL2"      > /sys/devices/platform/asus-nb-wmi/ppt_pl2_sppt
        echo "$FPPT"     > /sys/devices/platform/asus-nb-wmi/ppt_fppt
        echo "$APU"      > /sys/devices/platform/asus-nb-wmi/ppt_apu_sppt
        echo "$PLATFORM" > /sys/devices/platform/asus-nb-wmi/ppt_platform_sppt
        echo "$NV"       > /sys/devices/platform/asus-nb-wmi/nv_temp_target
        logger -t asus-tuned-sync "TP=$TP AC=$AC PP=$PP PL1=$PL1 PL2=$PL2 FPPT=$FPPT APU=$APU PLATFORM=$PLATFORM NV=$NV"
    fi

    sleep 1
done
SH

chmod 755 /usr/local/bin/asus-tuned-sync.sh

cat > /usr/lib/systemd/system/asus-tuned-sync.service << 'UNIT'
[Unit]
Description=Sync Tuned profile with ASUS platform profile and extra PPTs
After=asusd.service multi-user.target
Wants=asusd.service

[Service]
Type=simple
ExecStart=/usr/local/bin/asus-tuned-sync.sh
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable asus-tuned-sync.service


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

    # Desactiva scriptlets de kernel durante o install
    cd /usr/lib/kernel/install.d \
        && mv 05-rpmostree.install 05-rpmostree.install.bak \
        && mv 50-dracut.install 50-dracut.install.bak \
        && printf '%s\n' '#!/bin/sh' 'exit 0' > 05-rpmostree.install \
        && printf '%s\n' '#!/bin/sh' 'exit 0' > 50-dracut.install \
        && chmod +x 05-rpmostree.install 50-dracut.install

    dnf5 copr enable -y bieszczaders/kernel-cachyos-lto

    BAZZITE_KERNEL_PKGS=$(rpm -qa --queryformat '%{NAME}\n' \
        | grep -E '^kernel(-core|-modules|-modules-core|-modules-extra|-modules-internal|-uki-virt)?$' \
        | sort -u)

    dnf5 remove -y kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra || true
    rm -rf /lib/modules/*

    dnf5 install -y kernel-cachyos-lto kernel-cachyos-lto-devel-matched --allowerasing

    if [[ -n "${BAZZITE_KERNEL_PKGS}" ]]; then
        echo "${BAZZITE_KERNEL_PKGS}" | xargs dnf5 remove -y || true
    fi

    ## Required to install CachyOS settings
    rm -rf /usr/lib/systemd/coredump.conf

    ## Install KSMD and CachyOS-Settings
    dnf5 install -y libcap-ng libcap-ng-devel procps-ng procps-ng-devel
    dnf5 install -y cachyos-settings cachyos-ksm-settings --allowerasing

    ## Enable KSMD
    tee "/usr/lib/systemd/system/ksmd.service" > /dev/null <<KSMD
[Unit]
Description=Activates Kernel Samepage Merging
ConditionPathExists=/sys/kernel/mm/ksm

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/ksmctl -e
ExecStop=/usr/bin/ksmctl -d

[Install]
WantedBy=multi-user.target
KSMD
    ln -s /usr/lib/systemd/system/ksmd.service /etc/systemd/system/multi-user.target.wants/ksmd.service

    # Restaura scriptlets
    mv -f 05-rpmostree.install.bak 05-rpmostree.install \
        && mv -f 50-dracut.install.bak 50-dracut.install
    cd -

    # Gera initramfs correctamente para bootc/ostree
    releasever=$(/usr/bin/rpm -E %fedora)
    basearch=$(/usr/bin/arch)
    CACHY_VER=$(dnf list kernel-cachyos-lto -q | awk '/kernel-cachyos-lto/ {print $2}' | head -n 1 | cut -d'-' -f1)-cachyos1.lto.fc${releasever}.${basearch}
    depmod -a "${CACHY_VER}"
    export DRACUT_NO_XATTR=1
    /usr/bin/dracut --no-hostonly --kver "${CACHY_VER}" --reproducible -v --add ostree -f "/lib/modules/${CACHY_VER}/initramfs.img"
    chmod 0600 "/lib/modules/${CACHY_VER}/initramfs.img"
    echo "kernel-cachyos-lto instalado com sucesso"
    # Silenciar módulos Bazzite que não existem no kernel CachyOS
    for mod in gcadapter_oc kvmfr nct6687; do
        printf '# %s not built for CachyOS kernel — silenced\n' "$mod" \
            > /etc/modules-load.d/${mod}.conf
    done


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
ExecStart=/usr/bin/bash -c 'mkdir -p /var/lib/bazzite-cps && flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo && xargs flatpak install --system --noninteractive flathub < /usr/share/bazzite-cps/flatpaks.list && touch /var/lib/bazzite-cps/.flatpaks-installed'

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

# KWin better blur
dnf5 copr enable -y infinality/kwin-effects-better-blur-dx
dnf5 install -y kwin-effects-better-blur-dx

# Limpeza cache DNF — reduz tamanho da imagem
dnf5 clean all

# Corrigir bbr → cubic (bbr falha no boot em composefs)
if [ -f /usr/lib/sysctl.d/75-networking.conf ]; then
  sed -i 's/^net\.ipv4\.tcp_congestion_control=bbr$/net.ipv4.tcp_congestion_control=cubic/' /usr/lib/sysctl.d/75-networking.conf || true
fi
