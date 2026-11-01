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
# 1. Install Minimal XFCE Desktop Environment & Core Dependencies
# ------------------------------------------------------------------------------
echo "===> [1/6] Installing minimal XFCE packages..."

# Core XFCE, X11, Display Manager, and UI Theme packages
XFCE_PACKAGES=(
    xorg
    xserver-xorg-video-all
    xserver-xorg-input-all
    xfce4-session
    xfwm4
    xfce4-panel
    xfdesktop4
    xfce4-settings
    thunar
    lightdm
    lightdm-gtk-greeter
    greybird-gtk-theme
    papirus-icon-theme
    xfce4-notifyd
    xfce4-pulseaudio-plugin
    pavucontrol
    pulseaudio
    alsa-utils
    vorbis-tools
)

if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y --no-install-recommends "${XFCE_PACKAGES[@]}"
fi

# ------------------------------------------------------------------------------
# 2. Configure LightDM Zero-Second Passwordless Autologin
# ------------------------------------------------------------------------------
echo "===> [2/6] Configuring LightDM autologin for study user..."

install -d -m 0755 "${ROOTFS_DIR}/etc/lightdm/lightdm.conf.d"
install -m 0644 "${SCRIPT_DIR}/configs/desktop/lightdm-autologin.conf" \
               "${ROOTFS_DIR}/etc/lightdm/lightdm.conf.d/50-autologin.conf"
chown root:root "${ROOTFS_DIR}/etc/lightdm/lightdm.conf.d/50-autologin.conf" 2>/dev/null || true

# Provision live 'study' user and required autologin groups if running in rootfs
if command -v groupadd >/dev/null 2>&1; then
    groupadd -r autologin 2>/dev/null || true
    groupadd -r nopasswdlogin 2>/dev/null || true
fi

if command -v useradd >/dev/null 2>&1; then
    if ! id -u study >/dev/null 2>&1; then
        useradd -m -s /bin/bash -u 1000 -g users \
            -G sudo,audio,video,plugdev,netdev,autologin,nopasswdlogin study 2>/dev/null || true
        echo "study:study" | chpasswd 2>/dev/null || true
    else
        usermod -aG autologin,nopasswdlogin,audio,video,sudo study 2>/dev/null || true
    fi
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
    cups
    cups-browsed
    cups-daemon
    cups-client
    avahi-daemon
    avahi-autoipd
    bluetooth
    bluez
    bluez-cups
    modemmanager
    speech-dispatcher
    snapd
)

if command -v apt-get >/dev/null 2>&1; then
    apt-get purge -y --auto-remove "${BLOAT_PURGE_LIST[@]}" 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
    apt-get clean 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 6. Archive Package Manifest to Rootfs
# ------------------------------------------------------------------------------
echo "===> [6/6] Deploying package manifest to /etc/desktop-package-manifest.txt..."

install -m 0644 "${SCRIPT_DIR}/configs/desktop/package_manifest.txt" \
               "${ROOTFS_DIR}/etc/desktop-package-manifest.txt"
chown root:root "${ROOTFS_DIR}/etc/desktop-package-manifest.txt" 2>/dev/null || true

echo "===================================================================="
echo "Minimal XFCE Desktop installation completed successfully."
echo "===================================================================="
