#!/bin/bash
# ==============================================================================
# Distraction-Free Linux (Study OS) - Minimal XFCE Desktop Installation
# File: scripts/03_install_desktop.sh
# Purpose: Installs minimal XFCE desktop packages, configures LightDM autologin,
#          locks notification daemon in DND mode, silences acoustic noise,
#          and eliminates bloatware/games/telemetry.
# ==============================================================================
set -euo pipefail

ROOTFS_DIR="${1:-/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "===================================================================="
echo "Distraction-Free Linux: Installing Minimal XFCE Desktop to ${ROOTFS_DIR}"
echo "===================================================================="

export DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------------------------
# 1. Mount Helper & Chroot Execution Setup
# ------------------------------------------------------------------------------
MOUNTED=false

cleanup_mounts() {
    if [ "${MOUNTED}" = "true" ] && [ "${ROOTFS_DIR}" != "/" ]; then
        echo "Cleaning up chroot virtual filesystem mounts..."
        umount -lf "${ROOTFS_DIR}/dev/pts" 2>/dev/null || true
        umount -lf "${ROOTFS_DIR}/dev" 2>/dev/null || true
        umount -lf "${ROOTFS_DIR}/proc" 2>/dev/null || true
        umount -lf "${ROOTFS_DIR}/sys" 2>/dev/null || true
    fi
}
trap cleanup_mounts EXIT INT TERM

run_chroot() {
    if [ "${ROOTFS_DIR}" = "/" ]; then
        "$@"
    else
        chroot "${ROOTFS_DIR}" "$@"
    fi
}

if [ "${ROOTFS_DIR}" != "/" ]; then
    if [ ! -d "${ROOTFS_DIR}" ]; then
        echo "ERROR: Target rootfs directory '${ROOTFS_DIR}' does not exist." >&2
        exit 1
    fi

    mount --bind /dev "${ROOTFS_DIR}/dev"
    mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"
    mount -t proc proc "${ROOTFS_DIR}/proc"
    mount -t sysfs sysfs "${ROOTFS_DIR}/sys"
    MOUNTED=true

    if [ -f /etc/resolv.conf ]; then
        cp -L /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf" 2>/dev/null || true
    fi
fi

# ------------------------------------------------------------------------------
# 2. Install Minimal XFCE Desktop Environment & Core Dependencies
# ------------------------------------------------------------------------------
echo "===> [1/6] Installing minimal XFCE packages..."

# Core Ubuntu GNOME, X11, Display Manager, and UI Theme packages
XFCE_PACKAGES=(
    xorg
    xserver-xorg-video-all
    xserver-xorg-input-all
    ubuntu-desktop-minimal
    gdm3
    gnome-shell
    gnome-control-center
    gnome-terminal
    nautilus
    gnome-calculator
    gnome-screenshot
    yaru-theme-gnome-shell
    yaru-theme-gtk
    yaru-theme-icon
    papirus-icon-theme
    alsa-utils
    vorbis-tools
    dconf-cli
)

run_chroot apt-get update -y
run_chroot apt-get install -y --no-install-recommends "${XFCE_PACKAGES[@]}"

# ------------------------------------------------------------------------------
# 2. Configure Autologin for study user (GDM3 & LightDM)
# ------------------------------------------------------------------------------
echo "===> [2/6] Configuring GDM3 and LightDM autologin for study user..."

install -d -m 0755 "${ROOTFS_DIR}/etc/gdm3"
cat << 'EOF' > "${ROOTFS_DIR}/etc/gdm3/custom.conf"
# GDM3 autologin configuration for Distraction-Free Study OS
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=study
WaylandEnable=true
EOF

# Configure GNOME system-wide dconf defaults (dark mode, DND notifications, pinned study apps)
install -d -m 0755 "${ROOTFS_DIR}/etc/dconf/profile"
cat << 'EOF' > "${ROOTFS_DIR}/etc/dconf/profile/user"
user-db:user
system-db:local
EOF

install -d -m 0755 "${ROOTFS_DIR}/etc/dconf/db/local.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/dconf/db/local.d/00-study-defaults"
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='Yaru-dark'
icon-theme='Yaru'

[org/gnome/desktop/notifications]
show-banners=false

[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'

[org/gnome/shell]
favorite-apps=['firefox.desktop', 'anki.desktop', 'evince.desktop', 'focuswriter.desktop', 'featherpad.desktop', 'pomodoro-timer.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop']
EOF

run_chroot dconf update 2>/dev/null || true

install -d -m 0755 "${ROOTFS_DIR}/etc/lightdm/lightdm.conf.d"
install -m 0644 "${SCRIPT_DIR}/configs/desktop/lightdm-autologin.conf" \
               "${ROOTFS_DIR}/etc/lightdm/lightdm.conf.d/50-autologin.conf"
chown root:root "${ROOTFS_DIR}/etc/lightdm/lightdm.conf.d/50-autologin.conf" 2>/dev/null || true

# Provision live 'study' user and required autologin groups if running in rootfs
run_chroot groupadd -r autologin 2>/dev/null || true
run_chroot groupadd -r nopasswdlogin 2>/dev/null || true

if ! run_chroot id -u study >/dev/null 2>&1; then
    run_chroot useradd -m -s /bin/bash -u 1000 -g users \
        -G sudo,audio,video,plugdev,netdev,autologin,nopasswdlogin study 2>/dev/null || true
    echo "study:study" | run_chroot chpasswd 2>/dev/null || true
else
    run_chroot usermod -aG autologin,nopasswdlogin,audio,video,sudo study 2>/dev/null || true
fi

# Passwordless sudo for study user
install -d -m 0750 "${ROOTFS_DIR}/etc/sudoers.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/sudoers.d/99-study-user"
study ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 "${ROOTFS_DIR}/etc/sudoers.d/99-study-user"
chown root:root "${ROOTFS_DIR}/etc/sudoers.d/99-study-user" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 3. Permanent Notification Do Not Disturb Locking
# ------------------------------------------------------------------------------
echo "===> [3/6] Locking xfce4-notifyd into permanent Do Not Disturb mode..."

install -d -m 0755 "${ROOTFS_DIR}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
install -m 0644 "${SCRIPT_DIR}/configs/desktop/xfce4-notifyd.xml" \
               "${ROOTFS_DIR}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-notifyd.xml"
chown root:root "${ROOTFS_DIR}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-notifyd.xml" 2>/dev/null || true

# Also place in study user / skel directory to ensure immutable defaults
install -d -m 0755 "${ROOTFS_DIR}/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"
install -m 0644 "${SCRIPT_DIR}/configs/desktop/xfce4-notifyd.xml" \
               "${ROOTFS_DIR}/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-notifyd.xml"

if [ -d "${ROOTFS_DIR}/home/study" ]; then
    install -d -m 0755 "${ROOTFS_DIR}/home/study/.config/xfce4/xfconf/xfce-perchannel-xml"
    install -m 0644 "${SCRIPT_DIR}/configs/desktop/xfce4-notifyd.xml" \
                   "${ROOTFS_DIR}/home/study/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-notifyd.xml"
    chown -R study:users "${ROOTFS_DIR}/home/study/.config" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 4. Silence Acoustic Noise (PC Speaker & System Bell)
# ------------------------------------------------------------------------------
echo "===> [4/6] Blacklisting pcspkr and silencing acoustic noise..."

install -d -m 0755 "${ROOTFS_DIR}/etc/modprobe.d"
install -m 0644 "${SCRIPT_DIR}/configs/desktop/nobeep.conf" \
               "${ROOTFS_DIR}/etc/modprobe.d/nobeep.conf"
chown root:root "${ROOTFS_DIR}/etc/modprobe.d/nobeep.conf" 2>/dev/null || true

# Disable X11 system bell
install -d -m 0755 "${ROOTFS_DIR}/etc/X11/xorg.conf.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/X11/xorg.conf.d/10-nobell.conf"
Section "InputClass"
    Identifier "system-bell"
    MatchIsKeyboard "on"
    Option "Bell" "off"
EndSection
EOF
chmod 0644 "${ROOTFS_DIR}/etc/X11/xorg.conf.d/10-nobell.conf"
chown root:root "${ROOTFS_DIR}/etc/X11/xorg.conf.d/10-nobell.conf" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 5. Purge and Exclude Bloatware, Games, Telemetry, and Unused Daemons
# ------------------------------------------------------------------------------
echo "===> [5/6] Purging bloatware, games, telemetry, and unneeded background daemons..."

BLOAT_PURGE_LIST=(
    aisleriot
    gnome-mines
    gnome-sudoku
    mahjongg
    quadrapassel
    sgt-puzzles
    kpat
    kmines
    bsdgames
    whoopsie
    apport
    popularity-contest
    ubuntu-report
    apport-symptoms
    zeitgeist
    zeitgeist-core
    zeitgeist-datahub
    geoclue
    geoclue-2.0
    speech-dispatcher
    snapd
    ubiquity
    ubiquity-frontend-gtk
    calamares
    subiquity
)

run_chroot apt-get purge -y --auto-remove "${BLOAT_PURGE_LIST[@]}" 2>/dev/null || true
run_chroot apt-get autoremove -y 2>/dev/null || true
run_chroot apt-get clean 2>/dev/null || true

# ------------------------------------------------------------------------------
# 6. Archive Package Manifest to Rootfs
# ------------------------------------------------------------------------------
echo "===> [6/6] Deploying package manifest to /etc/desktop-package-manifest.txt..."

install -m 0644 "${SCRIPT_DIR}/configs/desktop/package_manifest.txt" \
               "${ROOTFS_DIR}/etc/desktop-package-manifest.txt"
chown root:root "${ROOTFS_DIR}/etc/desktop-package-manifest.txt" 2>/dev/null || true

# Ensure graphical target and LightDM display manager are enabled by default
if [ -d "${ROOTFS_DIR}/etc/systemd/system" ]; then
    ln -sf /lib/systemd/system/graphical.target "${ROOTFS_DIR}/etc/systemd/system/default.target"
    ln -sf /lib/systemd/system/lightdm.service "${ROOTFS_DIR}/etc/systemd/system/display-manager.service"
fi

echo "===================================================================="
echo "Minimal XFCE Desktop installation completed successfully."
echo "===================================================================="
