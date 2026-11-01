#!/bin/bash
# ==============================================================================
# Distraction-Free Linux (Study OS) - Base System & Kernel Configuration
# File: scripts/02_configure_system.sh
# Purpose: Installs generic Linux kernel, Casper live boot components, locales,
#          timezone, NetworkManager, provisions 'study' user, and enforces
#          host disk isolation policies (udev & Polkit).
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration & Environment Variables
# ------------------------------------------------------------------------------
ROOTFS_DIR="${1:-${CHROOT_DIR:-/opt/dfl/chroot}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "===================================================================="
echo "Distraction-Free Linux: Configuring Base System & Kernel"
echo "Target Rootfs : ${ROOTFS_DIR}"
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

    # Mount required pseudo-filesystems for package configuration & kernel hooks
    mount --bind /dev "${ROOTFS_DIR}/dev"
    mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"
    mount -t proc proc "${ROOTFS_DIR}/proc"
    mount -t sysfs sysfs "${ROOTFS_DIR}/sys"
    MOUNTED=true

    # Ensure DNS works during chroot package operations
    if [ -f /etc/resolv.conf ]; then
        cp -L /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf" 2>/dev/null || true
    fi
fi

# ------------------------------------------------------------------------------
# 2. Package Lists & Essential Core Utilities
# ------------------------------------------------------------------------------
echo "===> [1/6] Updating APT repositories and installing core packages..."

run_chroot apt-get update -y

CORE_PACKAGES=(
    systemd
    systemd-sysv
    udev
    dbus
    kmod
    sudo
    locales
    tzdata
    ca-certificates
    curl
    wget
    nano
    vim-tiny
    bash-completion
    pciutils
    usbutils
    zstd
    initramfs-tools
)

run_chroot apt-get install -y --no-install-recommends "${CORE_PACKAGES[@]}"

# ------------------------------------------------------------------------------
# 3. Kernel & Casper Live Boot Environment
# ------------------------------------------------------------------------------
echo "===> [2/6] Installing Ubuntu generic kernel and Casper live-boot framework..."

KERNEL_PACKAGES=(
    linux-image-generic
    linux-headers-generic
    casper
    zram-tools
    linux-firmware
    firmware-sof-signed
    alsa-ucm-conf
    wireless-regdb
    bluez
    bluez-tools
    pipewire
    pipewire-pulse
    pipewire-audio
    wireplumber
    libspa-0.2-bluetooth
    power-profiles-daemon
    intel-media-va-driver
    mesa-va-drivers
    mesa-vulkan-drivers
    xserver-xorg-input-libinput
    libinput-tools
)

run_chroot apt-get install -y --no-install-recommends "${KERNEL_PACKAGES[@]}"

# Configure casper defaults
install -d -m 0755 "${ROOTFS_DIR}/etc/casper.conf.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/casper.conf"
# Distraction-Free Linux Casper Live Environment Configuration
export USERNAME="study"
export USERFULLNAME="Study User"
export HOST="distraction-free-study"
export BUILD_SYSTEM="Ubuntu"
EOF

# ------------------------------------------------------------------------------
# 4. Localization, Charset, and Timezone Setup
# ------------------------------------------------------------------------------
echo "===> [3/6] Setting locale (en_US.UTF-8) and timezone (UTC)..."

echo "en_US.UTF-8 UTF-8" > "${ROOTFS_DIR}/etc/locale.gen"
run_chroot locale-gen en_US.UTF-8
run_chroot update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Configure UTC timezone
echo "Etc/UTC" > "${ROOTFS_DIR}/etc/timezone"
ln -fs /usr/share/zoneinfo/UTC "${ROOTFS_DIR}/etc/localtime"
run_chroot dpkg-reconfigure -f noninteractive tzdata

# ------------------------------------------------------------------------------
# 5. Network Stack & NetworkManager Configuration
# ------------------------------------------------------------------------------
echo "===> [4/6] Installing NetworkManager, wireless tools, and packet filters..."

NETWORK_PACKAGES=(
    network-manager
    network-manager-gnome
    wpasupplicant
    wireless-tools
    net-tools
    iproute2
    iptables
    nftables
    isc-dhcp-client
)

run_chroot apt-get install -y --no-install-recommends "${NETWORK_PACKAGES[@]}"

# Enable NetworkManager management of all interfaces
install -d -m 0755 "${ROOTFS_DIR}/etc/NetworkManager/conf.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/NetworkManager/NetworkManager.conf"
[main]
plugins=ifupdown,keyfile

[ifupdown]
managed=true

[device]
wifi.scan-rand-mac-address=yes
EOF

# ------------------------------------------------------------------------------
# 6. Provision Study User & Sudo Authorization
# ------------------------------------------------------------------------------
echo "===> [5/6] Provisioning default 'study' live user and sudo privileges..."

# Ensure autologin group exists
run_chroot groupadd -r autologin 2>/dev/null || true
run_chroot groupadd -r nopasswdlogin 2>/dev/null || true

# Create study user if not present
if ! run_chroot id -u study >/dev/null 2>&1; then
    run_chroot useradd -m -s /bin/bash -u 1000 -g users \
        -G sudo,audio,video,plugdev,netdev,autologin,nopasswdlogin study
    echo "study:study" | run_chroot chpasswd
else
    run_chroot usermod -aG autologin,nopasswdlogin,audio,video,sudo study
fi

# Passwordless sudo for study user
install -d -m 0750 "${ROOTFS_DIR}/etc/sudoers.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/sudoers.d/99-study-user"
# Distraction-Free Linux study user privilege specification
study ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 "${ROOTFS_DIR}/etc/sudoers.d/99-study-user"
chown root:root "${ROOTFS_DIR}/etc/sudoers.d/99-study-user" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 7. Host Disk Isolation & Amnesic Security Configuration
# ------------------------------------------------------------------------------
echo "===> [6/6] Enforcing host disk isolation rules (udev, Polkit, swap masking)..."

# Deploy udev amnesic disks rules
install -d -m 0755 "${ROOTFS_DIR}/etc/udev/rules.d"
if [ -f "${SCRIPT_DIR}/configs/security/99-amnesic-disks.rules" ]; then
    install -m 0644 "${SCRIPT_DIR}/configs/security/99-amnesic-disks.rules" \
                   "${ROOTFS_DIR}/etc/udev/rules.d/99-amnesic-disks.rules"
    chown root:root "${ROOTFS_DIR}/etc/udev/rules.d/99-amnesic-disks.rules" 2>/dev/null || true
fi

# Deploy Polkit host mount prevention rules
install -d -m 0755 "${ROOTFS_DIR}/etc/polkit-1/rules.d"
if [ -f "${SCRIPT_DIR}/configs/security/99-prevent-host-mount.rules" ]; then
    install -m 0644 "${SCRIPT_DIR}/configs/security/99-prevent-host-mount.rules" \
                   "${ROOTFS_DIR}/etc/polkit-1/rules.d/99-prevent-host-mount.rules"
    chown root:root "${ROOTFS_DIR}/etc/polkit-1/rules.d/99-prevent-host-mount.rules" 2>/dev/null || true
fi

# Mask disk swap to guarantee zero host swap usage
run_chroot systemctl mask swap.target 2>/dev/null || \
    ln -sf /dev/null "${ROOTFS_DIR}/etc/systemd/system/swap.target"

# Re-generate initramfs to incorporate casper and block rules
echo "Updating initramfs for all installed kernels..."
run_chroot update-initramfs -u -k all 2>/dev/null || true

echo "===================================================================="
echo "Stage 02: Base System & Kernel Configuration Complete!"
echo "===================================================================="
exit 0
