#!/bin/bash
# ==============================================================================
# Distraction-Free Linux (Study OS) - Hybrid Live ISO Assembler
# File: scripts/07_build_iso.sh
# Purpose: Assembles hybrid bootable ISO image with dual UEFI & BIOS bootloaders
#          using xorriso -as mkisofs. Supports dd, Rufus, and Ventoy booting.
# ==============================================================================
set -euo pipefail

ISO_STAGING_DIR="${1:-/opt/dfl/iso}"
OUTPUT_ISO="${2:-/opt/dfl/distraction-free-linux.iso}"
VOLUME_ID="${3:-DFL_STUDY_OS}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "===================================================================="
echo "Distraction-Free Linux: Assembling Hybrid Live ISO"
echo "Staging Root : ${ISO_STAGING_DIR}"
echo "Output ISO   : ${OUTPUT_ISO}"
echo "Volume ID    : ${VOLUME_ID}"
echo "===================================================================="

# ------------------------------------------------------------------------------
# 1. Validation & Prerequisites Check
# ------------------------------------------------------------------------------
if ! command -v xorriso >/dev/null 2>&1; then
    echo "ERROR: 'xorriso' utility is not installed. Please install xorriso." >&2
    exit 1
fi

if [ ! -d "${ISO_STAGING_DIR}" ]; then
    echo "ERROR: Staging directory '${ISO_STAGING_DIR}' does not exist." >&2
    exit 1
fi

mkdir -p "$(dirname "${OUTPUT_ISO}")"

# ------------------------------------------------------------------------------
# 2. Stage Bootloader Configurations and Release Metadata
# ------------------------------------------------------------------------------
echo "===> [1/4] Staging GRUB configurations and disk release metadata..."

mkdir -p "${ISO_STAGING_DIR}/boot/grub"
mkdir -p "${ISO_STAGING_DIR}/.disk"

# Copy primary grub.cfg and loopback.cfg
if [ -f "${SCRIPT_DIR}/configs/boot/grub.cfg" ]; then
    cp -v "${SCRIPT_DIR}/configs/boot/grub.cfg" "${ISO_STAGING_DIR}/boot/grub/grub.cfg"
fi

if [ -f "${SCRIPT_DIR}/configs/boot/loopback.cfg" ]; then
    cp -v "${SCRIPT_DIR}/configs/boot/loopback.cfg" "${ISO_STAGING_DIR}/boot/grub/loopback.cfg"
fi

# Copy GRUB module trees so dynamic module loading always succeeds
if [ -d /usr/lib/grub/x86_64-efi ]; then
    echo "Staging x86_64-efi GRUB modules..."
    cp -r /usr/lib/grub/x86_64-efi "${ISO_STAGING_DIR}/boot/grub/"
fi
if [ -d /usr/lib/grub/i386-pc ]; then
    echo "Staging i386-pc GRUB modules..."
    cp -r /usr/lib/grub/i386-pc "${ISO_STAGING_DIR}/boot/grub/"
fi

# Write .disk metadata
echo "Distraction-Free Linux (Study OS) 24.04 LTS amd64 - $(date +%Y%m%d)" > "${ISO_STAGING_DIR}/.disk/info"
echo "full_cd/single" > "${ISO_STAGING_DIR}/.disk/cd_type"

# ------------------------------------------------------------------------------
# 3. Provision UEFI and BIOS Boot Images
# ------------------------------------------------------------------------------
echo "===> [2/4] Verifying and generating UEFI and BIOS boot payloads..."

mkdir -p "${ISO_STAGING_DIR}/EFI/BOOT"

# Create minimal embedded grub configuration if grub-mkstandalone is used
EMBEDDED_CFG="/tmp/dfl_embedded_grub.cfg"
cat << 'EOF' > "${EMBEDDED_CFG}"
search --no-floppy --file --set=root /casper/vmlinuz
set prefix=($root)/boot/grub
configfile ($root)/boot/grub/grub.cfg
EOF

GRUB_MODULES="iso9660 fat part_msdos part_gpt search search_fs_file configfile normal linux test echo all_video gfxterm font"

# Build UEFI standalone binary (BOOTX64.EFI) if missing
if [ ! -s "${ISO_STAGING_DIR}/EFI/BOOT/BOOTX64.EFI" ] && command -v grub-mkstandalone >/dev/null 2>&1; then
    echo "Compiling standalone x86_64-efi GRUB binary..."
    grub-mkstandalone \
        --format=x86_64-efi \
        --output="${ISO_STAGING_DIR}/EFI/BOOT/BOOTX64.EFI" \
        --modules="${GRUB_MODULES}" \
        --locales="" \
        --fonts="" \
        "boot/grub/grub.cfg=${EMBEDDED_CFG}" 2>/dev/null || true
fi

# Build FAT EFI system partition image (boot/efi.img) for El Torito alternate boot
if [ ! -f "${ISO_STAGING_DIR}/boot/efi.img" ] && command -v mkfs.vfat >/dev/null 2>&1 && command -v mcopy >/dev/null 2>&1; then
    echo "Creating FAT16 EFI boot partition image (boot/efi.img)..."
    dd if=/dev/zero of="${ISO_STAGING_DIR}/boot/efi.img" bs=1M count=8 status=none
    mkfs.vfat -F 12 -n "ESP" "${ISO_STAGING_DIR}/boot/efi.img" >/dev/null 2>&1
    mmd -i "${ISO_STAGING_DIR}/boot/efi.img" ::EFI ::EFI/BOOT >/dev/null 2>&1 || true
    if [ -f "${ISO_STAGING_DIR}/EFI/BOOT/BOOTX64.EFI" ]; then
        mcopy -i "${ISO_STAGING_DIR}/boot/efi.img" "${ISO_STAGING_DIR}/EFI/BOOT/BOOTX64.EFI" ::EFI/BOOT/BOOTX64.EFI >/dev/null 2>&1 || true
    fi
fi

# Build Legacy BIOS El Torito boot image (boot/grub/i386-pc/eltorito.img) if missing
if [ ! -s "${ISO_STAGING_DIR}/boot/grub/i386-pc/eltorito.img" ] && command -v grub-mkstandalone >/dev/null 2>&1; then
    echo "Compiling standalone i386-pc El Torito GRUB image..."
    CORE_IMG="/tmp/dfl_core.img"
    grub-mkstandalone \
        --format=i386-pc \
        --output="${CORE_IMG}" \
        --locales="" \
        --fonts="" \
        "boot/grub/grub.cfg=${EMBEDDED_CFG}" 2>/dev/null || true
    if [ -f /usr/lib/grub/i386-pc/cdboot.img ] && [ -s "${CORE_IMG}" ]; then
        cat /usr/lib/grub/i386-pc/cdboot.img "${CORE_IMG}" > "${ISO_STAGING_DIR}/boot/grub/i386-pc/eltorito.img"
    elif [ -s "${CORE_IMG}" ]; then
        cp "${CORE_IMG}" "${ISO_STAGING_DIR}/boot/grub/i386-pc/eltorito.img"
    fi
    rm -f "${CORE_IMG}"
fi

# Clean up empty eltorito.img if it failed to generate
if [ -f "${ISO_STAGING_DIR}/boot/grub/i386-pc/eltorito.img" ] && [ ! -s "${ISO_STAGING_DIR}/boot/grub/i386-pc/eltorito.img" ]; then
    rm -f "${ISO_STAGING_DIR}/boot/grub/i386-pc/eltorito.img"
fi

rm -f "${EMBEDDED_CFG}"

# Locate MBR boot hybrid image
MBR_IMG=""
for candidate in \
    "/usr/lib/grub/i386-pc/boot_hybrid.img" \
    "/usr/lib/ISOLINUX/isohdpfx.bin" \
    "/usr/share/syslinux/isohdpfx.bin"; do
    if [ -s "${candidate}" ]; then
        MBR_IMG="${candidate}"
        break
    fi
done

# ------------------------------------------------------------------------------
# 4. Assemble Hybrid ISO with xorriso
# ------------------------------------------------------------------------------
echo "===> [3/4] Invoking xorriso -as mkisofs to assemble hybrid ISO..."

# Remove stale output ISO if present
rm -f "${OUTPUT_ISO}"

XORRISO_ARGS=(
    -as mkisofs
    -iso-level 3
    -full-iso9660-filenames
    -volid "${VOLUME_ID}"
    -output "${OUTPUT_ISO}"
    -r
)

# Attach MBR hybrid boot record if available and BIOS eltorito is present
if [ -n "${MBR_IMG}" ] && [ -s "${ISO_STAGING_DIR}/boot/grub/i386-pc/eltorito.img" ]; then
    XORRISO_ARGS+=(
        --grub2-mbr "${MBR_IMG}"
        -partition_offset 16
        --mbr-force-bootable
    )
fi

# Attach El Torito BIOS boot image only if non-empty
if [ -s "${ISO_STAGING_DIR}/boot/grub/i386-pc/eltorito.img" ]; then
    XORRISO_ARGS+=(
        -c "boot.catalog"
        -b "boot/grub/i386-pc/eltorito.img"
        -no-emul-boot
        -boot-load-size 4
        -boot-info-table
        --grub2-boot-info
    )
fi

# Attach El Torito UEFI boot image if present
if [ -f "${ISO_STAGING_DIR}/boot/efi.img" ]; then
    XORRISO_ARGS+=(
        -eltorito-alt-boot
        -e "boot/efi.img"
        -no-emul-boot
        -isohybrid-gpt-basdat
    )
fi

# Target staging directory
XORRISO_ARGS+=("${ISO_STAGING_DIR}")

echo "Executing: xorriso ${XORRISO_ARGS[*]}"
xorriso "${XORRISO_ARGS[@]}"

# ------------------------------------------------------------------------------
# 5. Checksum Generation and Verification
# ------------------------------------------------------------------------------
echo "===> [4/4] Generating SHA256 checksum and verifying build artifact..."

if [ ! -f "${OUTPUT_ISO}" ] || [ ! -s "${OUTPUT_ISO}" ]; then
    echo "ERROR: ISO generation failed. Output artifact is missing or zero bytes." >&2
    exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
    (cd "$(dirname "${OUTPUT_ISO}")" && sha256sum "$(basename "${OUTPUT_ISO}")" > "$(basename "${OUTPUT_ISO}").sha256")
fi

ISO_SIZE="$(du -h "${OUTPUT_ISO}" | cut -f1)"
echo "===================================================================="
echo "Hybrid Live ISO Build Successful!"
echo "ISO File   : ${OUTPUT_ISO}"
echo "Size       : ${ISO_SIZE}"
if [ -f "${OUTPUT_ISO}.sha256" ]; then
    echo "SHA256     : $(cat "${OUTPUT_ISO}.sha256")"
fi
echo "===================================================================="
exit 0
