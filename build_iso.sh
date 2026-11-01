#!/bin/bash
# ==============================================================================
# Distraction-Free Linux (Study OS) - Master ISO Build Pipeline
# File: build_iso.sh
# Purpose: Orchestrates the 10-stage automated build pipeline for Distraction-Free
#          Linux: bootstrapping Ubuntu 24.04 noble, kernel & casper configuration,
#          minimal XFCE desktop, study tooling suite, distraction lockdown,
#          high-density SquashFS compression, and hybrid UEFI/BIOS ISO generation.
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Default Settings & Parameters
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${WORKDIR:-/opt/dfl}"
OUTPUT_ISO="${OUTPUT_ISO:-${WORKDIR}/distraction-free-linux.iso}"
VOLUME_ID="${VOLUME_ID:-DFL_STUDY_OS}"
SKIP_BOOTSTRAP=false
CLEAN_FIRST=false
VERBOSE=false

# ANSI Color Codes
CLR_RED="\033[1;31m"
CLR_GRN="\033[1;32m"
CLR_YLW="\033[1;33m"
CLR_BLU="\033[1;34m"
CLR_CYN="\033[1;36m"
CLR_RST="\033[0m"

# ------------------------------------------------------------------------------
# Help & Usage Display
# ------------------------------------------------------------------------------
show_help() {
    cat << EOF
Distraction-Free Linux (Study OS) - Automated ISO Build Pipeline

Usage: $(basename "$0") [OPTIONS]

Options:
  -w, --workdir <DIR>      Base staging directory (default: /opt/dfl)
  -o, --output <FILE>      Output path for compiled ISO (default: /opt/dfl/distraction-free-linux.iso)
  -v, --volume-id <ID>     ISO 9660 volume label (default: DFL_STUDY_OS)
      --skip-bootstrap     Skip Stage 3 (debootstrap) if rootfs already exists
      --clean              Clean workspace and caches before starting build
      --verbose            Enable verbose command logging
  -h, --help               Display this help message

Execution Stages:
  Stage  1: Environment & Dependency Validation
  Stage  2: Workspace Directory Initialization & Cleanup
  Stage  3: Bootstrap Base Rootfs (scripts/01_bootstrap.sh)
  Stage  4: Base System & Kernel Configuration (scripts/02_configure_system.sh)
  Stage  5: Minimal XFCE Desktop Environment (scripts/03_install_desktop.sh)
  Stage  6: Study Tooling Suite Installation (scripts/04_install_study_tools.sh)
  Stage  7: Distraction Blocking & Browser Lockdown (scripts/05_apply_lockdown.sh)
  Stage  8: Pre-Squashfs Verification & Rootfs Sanitization
  Stage  9: SquashFS Container Compression (scripts/06_build_squashfs.sh)
  Stage 10: Hybrid Live ISO Assembly & Checksum (scripts/07_build_iso.sh)
EOF
}

# ------------------------------------------------------------------------------
# Parse Command Line Arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -w|--workdir)
            WORKDIR="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_ISO="$2"
            shift 2
            ;;
        -v|--volume-id)
            VOLUME_ID="$2"
            shift 2
            ;;
        --skip-bootstrap)
            SKIP_BOOTSTRAP=true
            shift
            ;;
        --clean)
            CLEAN_FIRST=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${CLR_RED}ERROR: Unknown option '$1'${CLR_RST}" >&2
            show_help
            exit 1
            ;;
    esac
done

CHROOT_DIR="${WORKDIR}/chroot"
ISO_STAGING_DIR="${WORKDIR}/iso"
CASPER_DIR="${ISO_STAGING_DIR}/casper"
LOG_DIR="${WORKDIR}/logs"
LOG_FILE="${LOG_DIR}/build_iso_$(date +%Y%m%d_%H%M%S).log"

# ------------------------------------------------------------------------------
# Logging & Helper Functions
# ------------------------------------------------------------------------------
log_info() {
    local msg="$*"
    echo -e "${CLR_GRN}[INFO]${CLR_RST} ${msg}"
    if [ -d "${LOG_DIR:-}" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
    fi
}

log_stage() {
    local num="$1"
    local title="$2"
    echo -e "\n${CLR_CYN}========================================================================${CLR_RST}"
    echo -e "${CLR_CYN}STAGE [${num}/10]: ${CLR_YLW}${title}${CLR_RST}"
    echo -e "${CLR_CYN}========================================================================${CLR_RST}"
    if [ -d "${LOG_DIR:-}" ]; then
        echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] === STAGE [${num}/10]: ${title} ===" >> "${LOG_FILE}" 2>/dev/null || true
    fi
}

log_warn() {
    local msg="$*"
    echo -e "${CLR_YLW}[WARN]${CLR_RST} ${msg}"
    if [ -d "${LOG_DIR:-}" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
    fi
}

log_error() {
    local msg="$*"
    echo -e "${CLR_RED}[ERROR]${CLR_RST} ${msg}" >&2
    if [ -d "${LOG_DIR:-}" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------------------
# Error Handling & Mount Cleanup Trap
# ------------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    if [ ${exit_code} -ne 0 ]; then
        log_error "Build pipeline terminated with exit code ${exit_code}."
        log_error "Inspect build log for detailed diagnostics: ${LOG_FILE}"
    fi

    # Unmount chroot virtual filesystems if still attached
    if [ -d "${CHROOT_DIR}" ]; then
        umount -lf "${CHROOT_DIR}/dev/pts" 2>/dev/null || true
        umount -lf "${CHROOT_DIR}/dev" 2>/dev/null || true
        umount -lf "${CHROOT_DIR}/proc" 2>/dev/null || true
        umount -lf "${CHROOT_DIR}/sys" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

handle_error() {
    local err_code="$1"
    local line_no="$2"
    log_error "Command failed at line ${line_no} with return code ${err_code}."
}
trap 'handle_error $? $LINENO' ERR

# ------------------------------------------------------------------------------
# STAGE 1: Environment & Dependency Validation
# ------------------------------------------------------------------------------
PIPELINE_START_TIME=$(date +%s)
log_stage "1" "Environment & Dependency Validation"

# Verify root privileges
if [ "$(id -u)" -ne 0 ]; then
    log_error "build_iso.sh must be executed as root (or via sudo)."
    exit 1
fi
log_info "Root privileges confirmed."

# Required build host tools
REQUIRED_TOOLS=(
    debootstrap
    mksquashfs
    xorriso
    grub-mkstandalone
    mcopy
    mkfs.vfat
    python3
    zstd
    curl
    tar
    du
    df
)

MISSING_TOOLS=()
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        MISSING_TOOLS+=("${tool}")
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    log_error "Missing required build tool(s): ${MISSING_TOOLS[*]}"
    log_error "Install with: apt-get update && apt-get install -y debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools dosfstools python3 zstd curl"
    exit 1
fi
log_info "All required build dependencies are present."

# Check available disk space (minimum 12 GB required for staging and squashfs)
AVAILABLE_KB=$(df -k "$(dirname "${WORKDIR}")" | awk 'NR==2 {print $4}')
REQUIRED_KB=$((12 * 1024 * 1024)) # 12 GB in KB
if [ "${AVAILABLE_KB}" -lt "${REQUIRED_KB}" ]; then
    log_warn "Free disk space ($((AVAILABLE_KB / 1024 / 1024)) GB) is below recommended 12 GB."
else
    log_info "Sufficient free disk space confirmed: $((AVAILABLE_KB / 1024 / 1024)) GB available."
fi

# ------------------------------------------------------------------------------
# STAGE 2: Workspace Directory Initialization & Cleanup
# ------------------------------------------------------------------------------
log_stage "2" "Workspace Directory Initialization & Cleanup"

if [ "${CLEAN_FIRST}" = "true" ]; then
    log_info "Cleaning workspace: ${WORKDIR}..."
    rm -rf "${CHROOT_DIR}" "${ISO_STAGING_DIR}" "${OUTPUT_ISO}" "${OUTPUT_ISO}.sha256"
fi

mkdir -p "${WORKDIR}"
mkdir -p "${CHROOT_DIR}"
mkdir -p "${ISO_STAGING_DIR}"
mkdir -p "${CASPER_DIR}"
mkdir -p "${LOG_DIR}"
mkdir -p "$(dirname "${OUTPUT_ISO}")"

touch "${LOG_FILE}"
log_info "Workspace initialized at: ${WORKDIR}"
log_info "Build logs directed to: ${LOG_FILE}"

# ------------------------------------------------------------------------------
# STAGE 3: Bootstrap Base Rootfs
# ------------------------------------------------------------------------------
log_stage "3" "Bootstrap Base Rootfs (scripts/01_bootstrap.sh)"

if [ "${SKIP_BOOTSTRAP}" = "true" ] && [ -f "${CHROOT_DIR}/etc/os-release" ]; then
    log_info "--skip-bootstrap flag specified and valid rootfs found. Skipping debootstrap."
else
    STAGE3_START=$(date +%s)
    bash "${SCRIPT_DIR}/scripts/01_bootstrap.sh" "${CHROOT_DIR}" 2>&1 | tee -a "${LOG_FILE}"
    STAGE3_DURATION=$(( $(date +%s) - STAGE3_START ))
    log_info "Base rootfs bootstrap complete in ${STAGE3_DURATION}s."
fi

# ------------------------------------------------------------------------------
# STAGE 4: Base System & Kernel Configuration
# ------------------------------------------------------------------------------
log_stage "4" "Base System & Kernel Configuration (scripts/02_configure_system.sh)"

STAGE4_START=$(date +%s)
bash "${SCRIPT_DIR}/scripts/02_configure_system.sh" "${CHROOT_DIR}" 2>&1 | tee -a "${LOG_FILE}"
STAGE4_DURATION=$(( $(date +%s) - STAGE4_START ))
log_info "Base system and kernel configured in ${STAGE4_DURATION}s."

# ------------------------------------------------------------------------------
# STAGE 5: Minimal XFCE Desktop Environment
# ------------------------------------------------------------------------------
log_stage "5" "Minimal XFCE Desktop Environment (scripts/03_install_desktop.sh)"

STAGE5_START=$(date +%s)
bash "${SCRIPT_DIR}/scripts/03_install_desktop.sh" "${CHROOT_DIR}" 2>&1 | tee -a "${LOG_FILE}"
STAGE5_DURATION=$(( $(date +%s) - STAGE5_START ))
log_info "Minimal XFCE desktop environment installed in ${STAGE5_DURATION}s."

# ------------------------------------------------------------------------------
# STAGE 6: Study Tooling Suite Installation
# ------------------------------------------------------------------------------
log_stage "6" "Study Tooling Suite Installation (scripts/04_install_study_tools.sh)"

STAGE6_START=$(date +%s)
bash "${SCRIPT_DIR}/scripts/04_install_study_tools.sh" "${CHROOT_DIR}" 2>&1 | tee -a "${LOG_FILE}"
STAGE6_DURATION=$(( $(date +%s) - STAGE6_START ))
log_info "Study tooling suite installed in ${STAGE6_DURATION}s."

# ------------------------------------------------------------------------------
# STAGE 7: Distraction Blocking & Browser Lockdown
# ------------------------------------------------------------------------------
log_stage "7" "Distraction Blocking & Browser Lockdown (scripts/05_apply_lockdown.sh)"

STAGE7_START=$(date +%s)
bash "${SCRIPT_DIR}/scripts/05_apply_lockdown.sh" "${CHROOT_DIR}" 2>&1 | tee -a "${LOG_FILE}"
STAGE7_DURATION=$(( $(date +%s) - STAGE7_START ))
log_info "Distraction blocking and browser lockdown applied in ${STAGE7_DURATION}s."

# ------------------------------------------------------------------------------
# STAGE 8: Pre-Squashfs Verification & Rootfs Sanitization
# ------------------------------------------------------------------------------
log_stage "8" "Pre-Squashfs Verification & Rootfs Sanitization"

log_info "Running validation check against rootfs configuration..."
# Verify essential security files are present in rootfs
test -f "${CHROOT_DIR}/etc/hosts" || { log_error "Missing /etc/hosts in chroot"; exit 1; }
test -f "${CHROOT_DIR}/etc/nftables.conf" || { log_error "Missing /etc/nftables.conf in chroot"; exit 1; }
test -f "${CHROOT_DIR}/etc/firefox/policies/policies.json" || { log_error "Missing Firefox policies in chroot"; exit 1; }
test -f "${CHROOT_DIR}/etc/lightdm/lightdm.conf.d/50-autologin.conf" || { log_error "Missing LightDM autologin in chroot"; exit 1; }
test -f "${CHROOT_DIR}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-notifyd.xml" || { log_error "Missing notifyd config in chroot"; exit 1; }

# Remove temporary build files, policy-rc.d override, and apt archives
log_info "Sanitizing rootfs for production squashfs packaging..."
rm -f "${CHROOT_DIR}/usr/sbin/policy-rc.d"
rm -f "${CHROOT_DIR}/etc/resolv.conf.tmp"
rm -rf "${CHROOT_DIR}/tmp/"* "${CHROOT_DIR}/var/tmp/"*
rm -rf "${CHROOT_DIR}/var/cache/apt/archives/"*.deb
rm -rf "${CHROOT_DIR}/var/lib/apt/lists/"*
log_info "Rootfs sanitized successfully."

# ------------------------------------------------------------------------------
# STAGE 9: SquashFS Container Compression
# ------------------------------------------------------------------------------
log_stage "9" "SquashFS Container Compression (scripts/06_build_squashfs.sh)"

STAGE9_START=$(date +%s)
bash "${SCRIPT_DIR}/scripts/06_build_squashfs.sh" "${CHROOT_DIR}" "${CASPER_DIR}" 2>&1 | tee -a "${LOG_FILE}"
STAGE9_DURATION=$(( $(date +%s) - STAGE9_START ))
log_info "SquashFS compression complete in ${STAGE9_DURATION}s."

# ------------------------------------------------------------------------------
# STAGE 10: Hybrid Live ISO Assembly & Checksum
# ------------------------------------------------------------------------------
log_stage "10" "Hybrid Live ISO Assembly & Checksum (scripts/07_build_iso.sh)"

STAGE10_START=$(date +%s)
bash "${SCRIPT_DIR}/scripts/07_build_iso.sh" "${ISO_STAGING_DIR}" "${OUTPUT_ISO}" "${VOLUME_ID}" 2>&1 | tee -a "${LOG_FILE}"
STAGE10_DURATION=$(( $(date +%s) - STAGE10_START ))

# ------------------------------------------------------------------------------
# Pipeline Completion & Final Summary
# ------------------------------------------------------------------------------
TOTAL_BUILD_TIME=$(( $(date +%s) - PIPELINE_START_TIME ))

if [ ! -f "${OUTPUT_ISO}" ] || [ ! -s "${OUTPUT_ISO}" ]; then
    log_error "Build failed: output ISO was not created or is empty!"
    exit 1
fi

ISO_FINAL_SIZE="$(du -h "${OUTPUT_ISO}" | cut -f1)"
SHA256_HASH="$(cat "${OUTPUT_ISO}.sha256" 2>/dev/null || sha256sum "${OUTPUT_ISO}" | cut -d' ' -f1)"

echo -e "\n${CLR_GRN}========================================================================${CLR_RST}"
echo -e "${CLR_GRN}DISTRACTION-FREE LINUX (STUDY OS) - BUILD SUCCESSFUL!${CLR_RST}"
echo -e "${CLR_GRN}========================================================================${CLR_RST}"
echo -e "Artifact Path : ${CLR_YLW}${OUTPUT_ISO}${CLR_RST}"
echo -e "File Size     : ${CLR_YLW}${ISO_FINAL_SIZE}${CLR_RST}"
echo -e "SHA256 Digest : ${CLR_YLW}${SHA256_HASH}${CLR_RST}"
echo -e "Total Time    : ${CLR_YLW}$((TOTAL_BUILD_TIME / 60))m $((TOTAL_BUILD_TIME % 60))s${CLR_RST}"
echo -e "Log File      : ${CLR_YLW}${LOG_FILE}${CLR_RST}"
echo -e "${CLR_GRN}========================================================================${CLR_RST}\n"
exit 0
