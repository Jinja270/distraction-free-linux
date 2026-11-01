#!/bin/bash
# ==============================================================================
# Distraction-Free Linux (Study OS) - USB Persistence Setup Script
# File: scripts/setup_persistence.sh
# Purpose: Format, label, and initialize USB persistence partitions for DFL.
# Supports Mode B (home-rw: amnesic root + persistent study notes in /home/study)
# and Mode A (writable: full root filesystem overlay persistence).
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Default Settings
# ------------------------------------------------------------------------------
TARGET_DEV=""
PERSISTENCE_MODE="home-rw"  # Default Mode B: home-rw (preserves tamper-resistant root)
TARGET_USER="study"
USER_UID=1000
USER_GID=100
FORCE=false

# ------------------------------------------------------------------------------
# Helper & Logging Functions
# ------------------------------------------------------------------------------
log_info() {
    echo -e "\033[1;32m[INFO]\033[0m $*"
}

log_warn() {
    echo -e "\033[1;33m[WARN]\033[0m $*"
}

log_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $*" >&2
}

show_usage() {
    cat << 'EOF'
Usage: setup_persistence.sh [OPTIONS] --device <PARTITION_DEVICE>

Options:
  -d, --device <dev>     Target block device partition (e.g. /dev/sdb2, /dev/sdc3)
  -m, --mode <mode>      Persistence mode:
                           'home-rw'  (Mode B - Default: Amnesic root + persistent /home/study)
                           'writable' (Mode A: Full root overlay persistence)
  -u, --user <username>  Target user account for home directory setup (default: study)
  -f, --force            Bypass interactive safety confirmation prompt
  -h, --help             Display this usage summary

Modes:
  1. Mode B: 'home-rw' (Recommended)
     Isolates user notes, flashcards, and documents under /home/study while
     keeping the operating system root (/etc/hosts, nftables, policies) in volatile
     RAM. Distraction-blocking rules reset to pristine immutable state every reboot.

  2. Mode A: 'writable'
     Standard Ubuntu full persistence overlay. Any filesystem modifications
     (including package installations or system alterations) persist across reboots.

Examples:
  sudo ./setup_persistence.sh --device /dev/sdb2 --mode home-rw
  sudo ./setup_persistence.sh -d /dev/sdc2 -m writable -f
EOF
}

# ------------------------------------------------------------------------------
# Parse Command-Line Arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--device)
            TARGET_DEV="$2"
            shift 2
            ;;
        -m|--mode)
            PERSISTENCE_MODE="$2"
            shift 2
            ;;
        -u|--user)
            TARGET_USER="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Validation Checks
# ------------------------------------------------------------------------------
if [[ -z "${TARGET_DEV}" ]]; then
    log_error "Missing required option: --device <PARTITION_DEVICE>"
    show_usage
    exit 1
fi

# Ensure running with administrative / root privileges
if [[ "$(id -u)" -ne 0 ]]; then
    log_error "This script must be executed as root (e.g. sudo $0)."
    exit 1
fi

# Validate chosen persistence mode
if [[ "${PERSISTENCE_MODE}" != "home-rw" && "${PERSISTENCE_MODE}" != "writable" ]]; then
    log_error "Invalid persistence mode: '${PERSISTENCE_MODE}'. Must be 'home-rw' or 'writable'."
    exit 1
fi

# Validate target block device exists
if [[ ! -b "${TARGET_DEV}" ]]; then
    log_error "Target device '${TARGET_DEV}' is not a valid block device."
    exit 1
fi

# Safety Check 1: Check if partition or device is already mounted
log_info "Verifying target device mount status via findmnt and lsblk..."
if findmnt -n --source "${TARGET_DEV}" >/dev/null 2>&1 || grep -qs "^${TARGET_DEV} " /proc/mounts; then
    MOUNT_POINT="$(findmnt -n -o TARGET --source "${TARGET_DEV}" 2>/dev/null || grep "^${TARGET_DEV} " /proc/mounts | awk '{print $2}')"
    log_error "Device '${TARGET_DEV}' is currently mounted at '${MOUNT_POINT}'!"
    log_error "Please unmount the partition before proceeding (e.g. sudo umount ${TARGET_DEV})."
    exit 1
fi

# Safety Check 2: Guard against formatting active host root or boot drive
ROOT_SOURCE="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
if [[ -n "${ROOT_SOURCE}" && "${TARGET_DEV}" == "${ROOT_SOURCE}"* ]]; then
    log_error "CRITICAL SAFETY VIOLATION: Device '${TARGET_DEV}' is the active system root filesystem!"
    exit 1
fi

# Safety Check 3: Guard against formatting active swap partitions
if grep -qs "^${TARGET_DEV}[[:space:]]" /proc/swaps 2>/dev/null; then
    log_error "CRITICAL SAFETY VIOLATION: Device '${TARGET_DEV}' is currently active as system swap!"
    exit 1
fi

# Safety Check 4: Guard against formatting internal non-removable disk unintentionally
DEVICE_NAME="$(basename "${TARGET_DEV}")"
PARENT_DISK="/sys/class/block/${DEVICE_NAME}"
if [[ -e "${PARENT_DISK}/removable" ]]; then
    IS_REMOVABLE="$(cat "${PARENT_DISK}/removable" 2>/dev/null || echo "0")"
    if [[ "${IS_REMOVABLE}" == "0" && "${FORCE}" != "true" ]]; then
        log_warn "Target device '${TARGET_DEV}' appears to be an INTERNAL non-removable drive!"
        read -r -p "Are you ABSOLUTELY sure you want to format ${TARGET_DEV}? [y/N]: " CONFIRM
        if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
            log_info "Aborting operation by user request."
            exit 0
        fi
    fi
fi

# ------------------------------------------------------------------------------
# Confirmation Prompt (unless forced)
# ------------------------------------------------------------------------------
if [[ "${FORCE}" != "true" ]]; then
    echo "===================================================================="
    echo "Distraction-Free Linux: USB Persistence Partition Setup"
    echo "===================================================================="
    echo "Target Partition : ${TARGET_DEV}"
    echo "Persistence Mode : ${PERSISTENCE_MODE}"
    echo "Volume Label     : ${PERSISTENCE_MODE}"
    echo "Target User      : ${TARGET_USER}"
    echo "===================================================================="
    echo "WARNING: ALL DATA ON ${TARGET_DEV} WILL BE PERMANENTLY ERASED!"
    read -r -p "Proceed with ext4 format and configuration? [y/N]: " CONFIRM
    if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
        log_info "Setup aborted by user."
        exit 0
    fi
fi

# ------------------------------------------------------------------------------
# Formatting with ext4 and Label Assignment
# ------------------------------------------------------------------------------
log_info "Formatting ${TARGET_DEV} with ext4 filesystem (Label: ${PERSISTENCE_MODE})..."
mkfs.ext4 -F -L "${PERSISTENCE_MODE}" -m 1 "${TARGET_DEV}"

log_info "Verifying partition label via lsblk / blkid..."
ASSIGNED_LABEL="$(lsblk -no LABEL "${TARGET_DEV}" 2>/dev/null || blkid -s LABEL -o value "${TARGET_DEV}" 2>/dev/null || echo "${PERSISTENCE_MODE}")"
log_info "Successfully assigned filesystem label: [${ASSIGNED_LABEL}]"

# ------------------------------------------------------------------------------
# Temporary Mount & Initial Directory Structure Provisioning
# ------------------------------------------------------------------------------
TEMP_MNT="$(mktemp -d /tmp/dfl_persistence_mnt.XXXXXX)"
log_info "Mounting ${TARGET_DEV} to temporary mountpoint ${TEMP_MNT}..."
mount "${TARGET_DEV}" "${TEMP_MNT}"

cleanup() {
    if findmnt -n --target "${TEMP_MNT}" >/dev/null 2>&1; then
        log_info "Unmounting ${TEMP_MNT}..."
        umount "${TEMP_MNT}" || umount -l "${TEMP_MNT}"
    fi
    rm -rf "${TEMP_MNT}"
}
trap cleanup EXIT

if [[ "${PERSISTENCE_MODE}" == "home-rw" ]]; then
    log_info "Initializing Mode B structure: /home/${TARGET_USER} dedicated study persistence..."
    USER_HOME_DIR="${TEMP_MNT}/${TARGET_USER}"
    mkdir -p "${USER_HOME_DIR}/Documents"
    mkdir -p "${USER_HOME_DIR}/Notes"
    mkdir -p "${USER_HOME_DIR}/Desktop"
    mkdir -p "${USER_HOME_DIR}/.local/share/Anki2"
    mkdir -p "${USER_HOME_DIR}/.config/focuswriter"

    # Create welcoming README for the student
    cat << 'README_EOF' > "${USER_HOME_DIR}/Notes/STUDY_NOTES_README.txt"
======================================================================
Distraction-Free Linux (Study OS) - Persistent Study Storage
======================================================================
Your study materials, Anki flashcard collections, and notes saved here
are preserved across reboots in Mode B ('home-rw').

The underlying operating system remains 100% amnesic in RAM tmpfs:
- All system configurations, /etc/hosts, and firewall rules reset on boot.
- Internal host disks remain completely untouched and unmounted.
- Your study notes in this directory remain intact and secure.
======================================================================
README_EOF

    # Set proper ownership and permissions for the study user
    log_info "Configuring permissions for user '${TARGET_USER}' (UID: ${USER_UID}, GID: ${USER_GID})..."
    chown -R "${USER_UID}:${USER_GID}" "${TEMP_MNT}" 2>/dev/null || true
    chmod 0750 "${USER_HOME_DIR}" 2>/dev/null || true

elif [[ "${PERSISTENCE_MODE}" == "writable" ]]; then
    log_info "Initializing Mode A structure: standard overlay persistence upperdir..."
    mkdir -p "${TEMP_MNT}/upper"
    mkdir -p "${TEMP_MNT}/work"
    chmod 0755 "${TEMP_MNT}"
fi

# Sync disk buffers before unmounting
sync

log_info "Unmounting temporary mountpoint..."
umount "${TEMP_MNT}"
rmdir "${TEMP_MNT}"
trap - EXIT

echo "===================================================================="
log_info "USB Persistence partition successfully configured on ${TARGET_DEV}!"
echo "Label            : ${PERSISTENCE_MODE}"
echo "Mode             : ${PERSISTENCE_MODE}"
echo "Boot Instruction : When booting live USB, select:"
echo "                   'Distraction-Free Linux (Live in RAM + Study Persistence)'"
echo "===================================================================="
exit 0
