#!/bin/bash
# ==============================================================================
# bazzite-cps-kde — build.sh
# KERNEL_FLAVOR: "bazzite" (default) | "cachyos"
# ==============================================================================
set -ouex pipefail
KERNEL_FLAVOR="${KERNEL_FLAVOR:-bazzite}"
# DNF5 — downloads paralelos
sed -i '/^\[main\]/a max_parallel_downloads=10' /etc/dnf/dnf.conf
rm -f /etc/yum.repos.d/*terra*.repo || true
dnf5 config-manager setopt terra.enabled=0 terra-extras.enabled=0 terra-mesa.enabled=0 2>/dev/null || true
# COPR asus-linux
dnf5 copr enable -y lukenukem/asus-linux
dnf5 install -y \
    asusctl \
    supergfxctl \
    rog-control-center
systemctl enable podman.socket
systemctl enable asusd.service
systemctl enable supergfxd.service
# asusd.ron — variante kernel Bazzite (limites confirmados)
if [[ "${KERNEL_FLAVOR}" == "bazzite" ]]; then
    mkdir -p /etc/asusd
    cat > /etc/asusd/asusd.ron << 'RON'
(
    charge_control_end_threshold: 94,
    base_charge_control_end_threshold: 0,
    disable_nvidia_powerd_on_battery: true,
    ac_command: "",
    bat_command: "",
    platform_profile_linked_epp: true,
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
                PptPlatformSppt: 100,
                PptPl1Spl: 150,
                PptPl2Sppt: 150,
            },
        ),
        Balanced: (
            enabled: true,
            group: {
                PptApuSppt: 60,
                PptPlatformSppt: 80,
                PptPl1Spl: 100,
                PptPl2Sppt: 120,
            },
        ),
        Quiet: (
            enabled: true,
            group: {
                PptApuSppt: 25,
                PptPlatformSppt: 40,
                PptPl1Spl: 45,
                PptPl2Sppt: 55,
            },
        ),
    },
    dc_profile_tunings: {
        Performance: (
            enabled: true,
            group: {
                PptApuSppt: 45,
                PptPlatformSppt: 60,
                PptPl1Spl: 80,
                PptPl2Sppt: 100,
            },
        ),
        Balanced: (
            enabled: true,
            group: {
                PptApuSppt: 30,
                PptPlatformSppt: 45,
                PptPl1Spl: 55,
                PptPl2Sppt: 70,
            },
        ),
        Quiet: (
            enabled: true,
            group: {
                PptApuSppt: 15,
                PptPlatformSppt: 30,
                PptPl1Spl: 25,
                PptPl2Sppt: 35,
            },
        ),
    },
    armoury_settings: {},
)
RON
fi
# asusd.ron — variante kernel CachyOS (limites confirmados kernel CachyOS-LTO)
if [[ "${KERNEL_FLAVOR}" == "cachyos" ]]; then
    mkdir -p /etc/asusd
    cat > /etc/asusd/asusd.ron << 'RON'
(
    charge_control_end_threshold: 94,
    base_charge_control_end_threshold: 0,
    disable_nvidia_powerd_on_battery: true,
    ac_command: "",
    bat_command: "",
    platform_profile_linked_epp: true,
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
                PptApuSppt: 80,
                PptPlatformSppt: 115,
            },
        ),
        Balanced: (
            enabled: true,
            group: {
                PptApuSppt: 45,
                PptPlatformSppt: 70,
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
    dc_profile_tunings: {
        Performance: (
            enabled: true,
            group: {
                PptApuSppt: 45,
                PptPlatformSppt: 60,
            },
        ),
        Balanced: (
            enabled: true,
            group: {
                PptApuSppt: 35,
                PptPlatformSppt: 50,
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
    armoury_settings: {},
)
RON
fi
# CachyOS addons runtime
dnf5 copr enable -y bieszczaders/kernel-cachyos-addons
systemctl enable scx.service 2>/dev/null || true
echo 'SCX_SCHEDULER=scx_lavd' > /etc/default/scx
cat > /usr/lib/sysctl.d/99-bazzite-cps-perf.conf << 'SYSCTL'
vm.vfs_cache_pressure = 50
vm.dirty_bytes = 268435456
vm.dirty_background_bytes = 67108864
vm.dirty_writeback_centisecs = 1500
vm.page-cluster = 0
kernel.nmi_watchdog = 0
net.core.netdev_max_backlog = 16384
fs.file-max = 2097152
SYSCTL
cat > /usr/lib/modprobe.d/99-bazzite-cps-audio.conf << 'MODPROBE'
options snd_hda_intel power_save=0
MODPROBE
cat > /usr/lib/modprobe.d/99-bazzite-cps-watchdog.conf << 'MODPROBE'
blacklist iTCO_wdt
blacklist sp5100_tco
MODPROBE
cat > /usr/lib/udev/rules.d/99-bazzite-cps-audio-timers.rules << 'UDEV'
KERNEL=="rtc0", GROUP="audio"
KERNEL=="hpet", GROUP="audio"
UDEV
cat > /usr/lib/udev/rules.d/99-bazzite-cps-audio-pm.rules << 'UDEV'
ACTION=="add", SUBSYSTEM=="sound", KERNEL=="card*", DRIVERS=="snd_hda_intel", \
  TEST!="/run/udev/snd-hda-intel-powersave", \
  RUN+="/usr/bin/bash -c 'touch /run/udev/snd-hda-intel-powersave; \
    [[ $$(cat /sys/class/power_supply/BAT0/status 2>/dev/null) != \"Discharging\" ]] && \
    echo 0 > /sys/module/snd_hda_intel/parameters/power_save'"
UDEV
if [[ "${KERNEL_FLAVOR}" == "cachyos" ]]; then
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
    rm -rf /usr/lib/systemd/coredump.conf
    dnf5 install -y libcap-ng libcap-ng-devel procps-ng procps-ng-devel
    dnf5 install -y cachyos-settings cachyos-ksm-settings --allowerasing
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
    mv -f 05-rpmostree.install.bak 05-rpmostree.install \
        && mv -f 50-dracut.install.bak 50-dracut.install
    cd -
    releasever=$(/usr/bin/rpm -E %fedora)
    basearch=$(/usr/bin/arch)
    CACHY_VER=$(dnf list kernel-cachyos-lto -q | awk '/kernel-cachyos-lto/ {print $2}' | head -n 1 | cut -d'-' -f1)-cachyos1.lto.fc${releasever}.${basearch}
    depmod -a "${CACHY_VER}"
    export DRACUT_NO_XATTR=1
    /usr/bin/dracut --no-hostonly --kver "${CACHY_VER}" --reproducible -v --add ostree -f "/lib/modules/${CACHY_VER}/initramfs.img"
    chmod 0600 "/lib/modules/${CACHY_VER}/initramfs.img"
    echo "kernel-cachyos-lto instalado com sucesso"
    for mod in gcadapter_oc kvmfr nct6687; do
        printf '# %s not built for CachyOS kernel — silenced\n' "$mod" \
            > /etc/modules-load.d/${mod}.conf
    done
else
    echo "kernel Bazzite mantido — melhorias CachyOS runtime aplicadas"
fi
cat > /usr/lib/udev/rules.d/99-bazzite-cps-dma-latency.rules << 'UDEV'
KERNEL=="cpu_dma_latency", GROUP="audio", MODE="0660"
UDEV
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-bazzite-cps.conf << 'JOURNALD'
[Journal]
SystemMaxUse=50M
JOURNALD
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/99-bazzite-cps-timeouts.conf << 'SYSTEMD'
[Manager]
DefaultTimeoutStartSec=15s
DefaultTimeoutStopSec=10s
SYSTEMD
# ------------------------------------------------------------------------------
# DX — Developer Experience
# ------------------------------------------------------------------------------
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
dnf5 config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
dnf5 install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
systemctl enable docker.socket
dnf5 install -y fish zsh
dnf5 install -y distrobox flatpak-builder
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
rm -f /etc/yum.repos.d/vscode.repo
dnf5 config-manager setopt docker-ce-stable.enabled=0
dnf5 install -y \
    bcc \
    bpftop \
    tiptop \
    nicstat \
    numactl
dnf5 install -y \
    android-tools \
    usbmuxd
dnf5 install -y \
    podman-machine \
    podman-tui
dnf5 install -y \
    ccache \
    sccache
dnf5 install -y \
    rclone \
    restic
dnf5 install -y python3-ramalama
dnf5 install -y python3.10 python3.12 python3.10-devel python3.12-devel
echo 'iptable_nat' > /usr/lib/modules-load.d/iptable_nat.conf
dnf5 install -y \
    turbostat \
    valgrind \
    nethogs \
    hyperfine
dnf5 install -y gh
dnf5 install -y gparted


# KDE visual extras
dnf5 install -y \
    kvantum \
    kvantum-qt5 \
    papirus-icon-theme \
    qt5ct \
    qt6ct \
    merkuro

# ------------------------------------------------------------------------------
# Flatpaks
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
org.kde.kcalc
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
dnf5 install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm 2>/dev/null || true
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
# ------------------------------------------------------------------------------
# GTK4 Python bindings + pyenv build dependencies
# ------------------------------------------------------------------------------
dnf5 install -y \
    python3-gobject \
    python3-gobject-devel \
    gtk4-devel \
    libadwaita \
    libadwaita-devel \
    vte291-gtk4
dnf5 install -y \
    bzip2-devel \
    libffi-devel \
    readline-devel \
    sqlite-devel \
    xz-devel \
    ncurses-devel \
    tk-devel \
    freetype-devel
# PyGObject para Python 3.10 e 3.12
python3.10 -m pip install --break-system-packages PyGObject
python3.12 -m pip install --break-system-packages PyGObject
dnf5 clean all
if [ -f /usr/lib/sysctl.d/75-networking.conf ]; then
  sed -i 's/^net\.ipv4\.tcp_congestion_control=bbr$/net.ipv4.tcp_congestion_control=cubic/' /usr/lib/sysctl.d/75-networking.conf || true
fi
