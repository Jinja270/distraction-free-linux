#!/bin/bash
# ==============================================================================
# Distraction-Free Linux (Study OS) - Base Rootfs Bootstrap Engine
# File: scripts/01_bootstrap.sh
# Purpose: Bootstrap minimal Ubuntu 24.04 LTS (noble) minbase rootfs using
#          debootstrap, configure basic APT sources, hostname, hosts, and DNS.
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration & Environment Variables
# ------------------------------------------------------------------------------
TARGET_DIR="${1:-${CHROOT_DIR:-/opt/dfl/chroot}}"
UBUNTU_RELEASE="${UBUNTU_RELEASE:-noble}"
UBUNTU_MIRROR="${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "===================================================================="
echo "Distraction-Free Linux: Bootstrapping Base System (${UBUNTU_RELEASE})"
echo "Target Rootfs : ${TARGET_DIR}"
echo "Release       : ${UBUNTU_RELEASE}"
echo "Mirror        : ${UBUNTU_MIRROR}"
echo "===================================================================="

# ------------------------------------------------------------------------------
# 1. Prerequisites and Privilege Validation
# ------------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: 01_bootstrap.sh must be run as root (or via sudo)." >&2
    exit 1
fi

if ! command -v debootstrap >/dev/null 2>&1; then
    echo "ERROR: 'debootstrap' utility is not installed." >&2
    echo "Install via: apt-get install -y debootstrap" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 2. Directory Preparation
# ------------------------------------------------------------------------------
echo "===> [1/4] Preparing target rootfs directory..."

if [ -d "${TARGET_DIR}/bin" ] && [ -f "${TARGET_DIR}/etc/os-release" ]; then
    echo "Notice: Existing rootfs detected in ${TARGET_DIR}."
    if [ "${CLEAN_BOOTSTRAP:-0}" = "1" ]; then
        echo "CLEAN_BOOTSTRAP=1 specified: removing old rootfs..."
        rm -rf "${TARGET_DIR}"
        mkdir -p "${TARGET_DIR}"
    else
        echo "Preserving existing bootstrap. To force re-bootstrap, set CLEAN_BOOTSTRAP=1."
    fi
else
    mkdir -p "${TARGET_DIR}"
fi

# ------------------------------------------------------------------------------
# 3. Execute Debootstrap (minbase variant)
# ------------------------------------------------------------------------------
if [ ! -f "${TARGET_DIR}/bin/bash" ]; then
    echo "===> [2/4] Executing debootstrap (${UBUNTU_RELEASE} minbase)..."
    
    DEBOOTSTRAP_PKGS="ca-certificates,gnupg,curl,wget,xz-utils"
    
    debootstrap \
        --arch=amd64 \
        --variant=minbase \
        --include="${DEBOOTSTRAP_PKGS}" \
        "${UBUNTU_RELEASE}" \
        "${TARGET_DIR}" \
        "${UBUNTU_MIRROR}"
        
    echo "Debootstrap base stage complete."
else
    echo "===> [2/4] Base rootfs already present. Skipping debootstrap execution."
fi

# ------------------------------------------------------------------------------
# 4. Configure Basic APT Repositories & System Identity
# ------------------------------------------------------------------------------
echo "===> [3/4] Configuring APT sources, hostname, and resolver..."

# Setup standard Ubuntu 24.04 noble repositories
cat << EOF > "${TARGET_DIR}/etc/apt/sources.list"
deb ${UBUNTU_MIRROR} ${UBUNTU_RELEASE} main restricted universe multiverse
deb ${UBUNTU_MIRROR} ${UBUNTU_RELEASE}-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ ${UBUNTU_RELEASE}-security main restricted universe multiverse
deb ${UBUNTU_MIRROR} ${UBUNTU_RELEASE}-backports main restricted universe multiverse
EOF

# Set system hostname
echo "distraction-free" > "${TARGET_DIR}/etc/hostname"

# Set base /etc/hosts (pre-lockdown stage)
cat << 'EOF' > "${TARGET_DIR}/etc/hosts"
127.0.0.1   localhost distraction-free distraction-free-study
127.0.1.1   distraction-free distraction-free-study
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

# Backup hosts for stage 05 lockdown
cp -f "${TARGET_DIR}/etc/hosts" "${TARGET_DIR}/etc/hosts.original"

# Ensure host DNS resolver is available inside chroot during build
if [ -f /etc/resolv.conf ]; then
    cp -L /etc/resolv.conf "${TARGET_DIR}/etc/resolv.conf" 2>/dev/null || true
else
    cat << 'EOF' > "${TARGET_DIR}/etc/resolv.conf"
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
fi

# Prevent daemons from auto-starting during chroot package installations
cat << 'EOF' > "${TARGET_DIR}/usr/sbin/policy-rc.d"
#!/bin/sh
exit 101
EOF
chmod +x "${TARGET_DIR}/usr/sbin/policy-rc.d"

# ------------------------------------------------------------------------------
# 5. Validation
# ------------------------------------------------------------------------------
echo "===> [4/4] Validating bootstrapped filesystem structure..."

if [ ! -f "${TARGET_DIR}/etc/os-release" ] || [ ! -f "${TARGET_DIR}/bin/bash" ]; then
    echo "ERROR: Bootstrapped rootfs failed validation. Missing os-release or bash binary." >&2
    exit 1
fi

ROOTFS_SIZE="$(du -sh "${TARGET_DIR}" 2>/dev/null | cut -f1)"
echo "===================================================================="
echo "Stage 01: Base Rootfs Bootstrap Complete!"
echo "Target Rootfs : ${TARGET_DIR}"
echo "Estimated Size: ${ROOTFS_SIZE}"
echo "===================================================================="
exit 0
