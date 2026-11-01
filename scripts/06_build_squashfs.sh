#!/bin/bash
# ==============================================================================
# Distraction-Free Linux (Study OS) - SquashFS Rootfs Compression Engine
# File: scripts/06_build_squashfs.sh
# Purpose: Compresses the debootstrapped and hardened rootfs into a high-density,
#          zstd-compressed SquashFS container (filesystem.squashfs) for Casper live boot.
# ==============================================================================
set -euo pipefail

CHROOT_DIR="${1:-/opt/dfl/chroot}"
OUTPUT_DIR="${2:-/opt/dfl/iso/casper}"
SQUASHFS_PATH="${OUTPUT_DIR}/filesystem.squashfs"

echo "===================================================================="
echo "Distraction-Free Linux: Building SquashFS Container"
echo "Rootfs Source : ${CHROOT_DIR}"
echo "Casper Target : ${OUTPUT_DIR}"
echo "===================================================================="

# ------------------------------------------------------------------------------
# 1. Prerequisites and Environment Validation
# ------------------------------------------------------------------------------
if ! command -v mksquashfs >/dev/null 2>&1; then
    echo "ERROR: 'mksquashfs' utility not found. Please install squashfs-tools." >&2
    exit 1
fi

if [ ! -d "${CHROOT_DIR}" ]; then
    echo "ERROR: Rootfs source directory '${CHROOT_DIR}' does not exist." >&2
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"

# ------------------------------------------------------------------------------
# 2. Extract Kernel & Initramfs to Staging Casper Directory
# ------------------------------------------------------------------------------
echo "===> [1/4] Extracting kernel (vmlinuz) and initramfs (initrd)..."

VMLINUZ_FILE="$(find "${CHROOT_DIR}/boot" -maxdepth 1 -name "vmlinuz*" | sort -V | tail -n 1)"
INITRD_FILE="$(find "${CHROOT_DIR}/boot" -maxdepth 1 -name "initrd.img*" | sort -V | tail -n 1)"

if [ -n "${VMLINUZ_FILE}" ] && [ -f "${VMLINUZ_FILE}" ]; then
    cp -v "${VMLINUZ_FILE}" "${OUTPUT_DIR}/vmlinuz"
else
    echo "WARNING: No vmlinuz binary found in ${CHROOT_DIR}/boot."
fi

if [ -n "${INITRD_FILE}" ] && [ -f "${INITRD_FILE}" ]; then
    cp -v "${INITRD_FILE}" "${OUTPUT_DIR}/initrd"
else
    echo "WARNING: No initrd.img binary found in ${CHROOT_DIR}/boot."
fi

# ------------------------------------------------------------------------------
# 3. Clean Rootfs Caches and Temporary Files
# ------------------------------------------------------------------------------
echo "===> [2/4] Cleaning chroot temporary directories and package caches..."

rm -rf "${CHROOT_DIR}/tmp/"* "${CHROOT_DIR}/var/tmp/"*
rm -rf "${CHROOT_DIR}/var/cache/apt/archives/"*.deb
rm -rf "${CHROOT_DIR}/var/lib/apt/lists/"*
rm -f "${CHROOT_DIR}/etc/resolv.conf.bak"
rm -f "${CHROOT_DIR}/root/.bash_history"

# ------------------------------------------------------------------------------
# 4. Generate Filesystem Size and Package Manifest
# ------------------------------------------------------------------------------
echo "===> [3/4] Generating filesystem.size and filesystem.manifest..."

# Calculate uncompressed filesystem size in bytes
printf "%s" "$(du -sx --block-size=1 "${CHROOT_DIR}" | cut -f1)" > "${OUTPUT_DIR}/filesystem.size"

# Generate package manifest if chroot execution is available
if [ -x "${CHROOT_DIR}/usr/bin/dpkg-query" ]; then
    chroot "${CHROOT_DIR}" dpkg-query -W --showformat='${Package} ${Version}\n' > "${OUTPUT_DIR}/filesystem.manifest" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 5. Compress Rootfs into SquashFS with Zstandard (zstd) Compression
# ------------------------------------------------------------------------------
echo "===> [4/4] Compressing filesystem.squashfs using high-density zstd..."

# Remove old squashfs image if present
rm -f "${SQUASHFS_PATH}"

# Build SquashFS with zstd, 1M block size, no-recovery, and always-use-fragments
mksquashfs "${CHROOT_DIR}" "${SQUASHFS_PATH}" \
    -comp zstd \
    -b 1M \
    -no-recovery \
    -always-use-fragments \
    -noappend \
    -wildcards \
    -e "boot/*" \
    -e "root/*" \
    -e "tmp/*" \
    -e "var/tmp/*" \
    -e "var/cache/apt/archives/*" \
    -e "proc/*" \
    -e "sys/*" \
    -e "dev/*" \
    -e "run/*"

# Verify generated squashfs
if [ ! -f "${SQUASHFS_PATH}" ] || [ ! -s "${SQUASHFS_PATH}" ]; then
    echo "ERROR: Failed to generate valid filesystem.squashfs!" >&2
    exit 1
fi

SQUASHFS_SIZE="$(du -h "${SQUASHFS_PATH}" | cut -f1)"
echo "===================================================================="
echo "SquashFS build complete!"
echo "Image Path : ${SQUASHFS_PATH}"
echo "Size       : ${SQUASHFS_SIZE}"
echo "===================================================================="
exit 0
