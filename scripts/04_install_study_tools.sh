#!/bin/bash
# ==============================================================================
# Distraction-Free Linux (Study OS) - Study Tooling Suite Installation
# File: scripts/04_install_study_tools.sh
# Purpose: Installs Anki, Evince, Zathura, FocusWriter, Markdown editor,
#          deploys Pomodoro focus timer, zathurarc dark theme,
#          and registers all FreeDesktop launchers and desktop shortcuts.
# ==============================================================================
set -euo pipefail

ROOTFS_DIR="${1:-/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "===================================================================="
echo "Distraction-Free Linux: Installing Study Tooling Suite to ${ROOTFS_DIR}"
echo "===================================================================="

export DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------------------------
# 1. Install Repository Study Tools & Document Viewers
# ------------------------------------------------------------------------------
echo "===> [1/5] Installing document viewers, writing tools, and dependencies..."

STUDY_PACKAGES=(
    evince
    zathura
    zathura-pdf-poppler
    focuswriter
    ghostwriter
    featherpad
    python3
    python3-gi
    python3-gi-cairo
    gir1.2-gtk-3.0
    curl
    tar
    zstd
)

if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y --no-install-recommends "${STUDY_PACKAGES[@]}"
fi

# ------------------------------------------------------------------------------
# 2. Install Anki (Spaced Repetition Flashcards)
# ------------------------------------------------------------------------------
echo "===> [2/5] Installing Anki flashcard engine..."

ANKI_INSTALLED=false

# Try official upstream standalone Qt6 bundle if network or cached archive is available
ANKI_VERSION="24.06.3"
ANKI_TARBALL="/tmp/anki-${ANKI_VERSION}-linux-qt6.tar.zst"
ANKI_URL="https://github.com/ankitects/anki/releases/download/${ANKI_VERSION}/anki-${ANKI_VERSION}-linux-qt6.tar.zst"

if [ -f "${ANKI_TARBALL}" ] || (command -v curl >/dev/null 2>&1 && curl -fsSL -m 15 "${ANKI_URL}" -o "${ANKI_TARBALL}" 2>/dev/null); then
    echo "Extracting and installing standalone Anki bundle..."
    mkdir -p /tmp/anki-build
    tar -xaf "${ANKI_TARBALL}" -C /tmp/anki-build/
    ANKI_DIR=$(find /tmp/anki-build -mindepth 1 -maxdepth 1 -type d | head -n 1)
    if [ -n "${ANKI_DIR}" ] && [ -f "${ANKI_DIR}/install.sh" ]; then
        (cd "${ANKI_DIR}" && PREFIX="${ROOTFS_DIR}/usr/local" bash ./install.sh) || true
        ANKI_INSTALLED=true
    fi
    rm -rf /tmp/anki-build "${ANKI_TARBALL}"
fi

# Fallback to apt anki package if standalone download was skipped/failed
if [ "${ANKI_INSTALLED}" = false ] && command -v apt-get >/dev/null 2>&1; then
    echo "Installing Anki from apt repository..."
    apt-get install -y --no-install-recommends anki 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 3. Deploy Zathura Distraction-Free Dark Configuration
# ------------------------------------------------------------------------------
echo "===> [3/5] Deploying zathurarc dark theme and geometry settings..."

# System-wide zathurarc
install -d -m 0755 "${ROOTFS_DIR}/etc"
install -m 0644 "${SCRIPT_DIR}/configs/desktop/zathurarc" \
               "${ROOTFS_DIR}/etc/zathurarc"
chown root:root "${ROOTFS_DIR}/etc/zathurarc" 2>/dev/null || true

# User default / skel zathurarc
install -d -m 0755 "${ROOTFS_DIR}/etc/skel/.config/zathura"
install -m 0644 "${SCRIPT_DIR}/configs/desktop/zathurarc" \
               "${ROOTFS_DIR}/etc/skel/.config/zathura/zathurarc"

if [ -d "${ROOTFS_DIR}/home/study" ]; then
    install -d -m 0755 "${ROOTFS_DIR}/home/study/.config/zathura"
    install -m 0644 "${SCRIPT_DIR}/configs/desktop/zathurarc" \
                   "${ROOTFS_DIR}/home/study/.config/zathura/zathurarc"
    chown -R study:users "${ROOTFS_DIR}/home/study/.config" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 4. Deploy Pomodoro Focus Timer Executable
# ------------------------------------------------------------------------------
echo "===> [4/5] Deploying Pomodoro focus timer to /usr/local/bin/pomodoro_timer.py..."

install -d -m 0755 "${ROOTFS_DIR}/usr/local/bin"
install -m 0755 "${SCRIPT_DIR}/scripts/pomodoro_timer.py" \
               "${ROOTFS_DIR}/usr/local/bin/pomodoro_timer.py"
chown root:root "${ROOTFS_DIR}/usr/local/bin/pomodoro_timer.py" 2>/dev/null || true

# Symlink helper
ln -sf "/usr/local/bin/pomodoro_timer.py" "${ROOTFS_DIR}/usr/local/bin/pomodoro" 2>/dev/null || true
ln -sf "/usr/local/bin/pomodoro_timer.py" "${ROOTFS_DIR}/usr/local/bin/study-timer" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 5. Deploy FreeDesktop Launchers & Desktop Shortcuts
# ------------------------------------------------------------------------------
echo "===> [5/5] Deploying FreeDesktop .desktop launchers to applications and desktop..."

LAUNCHERS_DIR="${SCRIPT_DIR}/configs/desktop/launchers"

# Target directories
APPS_DIR="${ROOTFS_DIR}/usr/share/applications"
SKEL_DESKTOP_DIR="${ROOTFS_DIR}/etc/skel/Desktop"

install -d -m 0755 "${APPS_DIR}"
install -d -m 0755 "${SKEL_DESKTOP_DIR}"

for desktop_file in "${LAUNCHERS_DIR}"/*.desktop; do
    if [ -f "${desktop_file}" ]; then
        fname="$(basename "${desktop_file}")"
        echo "  - Installing ${fname}..."
        install -m 0644 "${desktop_file}" "${APPS_DIR}/${fname}"
        chown root:root "${APPS_DIR}/${fname}" 2>/dev/null || true

        # Also place on study desktop for instant access
        install -m 0755 "${desktop_file}" "${SKEL_DESKTOP_DIR}/${fname}"
    fi
done

if [ -d "${ROOTFS_DIR}/home/study" ]; then
    STUDY_DESKTOP_DIR="${ROOTFS_DIR}/home/study/Desktop"
    install -d -m 0755 "${STUDY_DESKTOP_DIR}"
    for desktop_file in "${LAUNCHERS_DIR}"/*.desktop; do
        if [ -f "${desktop_file}" ]; then
            fname="$(basename "${desktop_file}")"
            install -m 0755 "${desktop_file}" "${STUDY_DESKTOP_DIR}/${fname}"
        fi
    done
    chown -R study:users "${STUDY_DESKTOP_DIR}" 2>/dev/null || true
fi

echo "===================================================================="
echo "Study Tooling Suite installation completed successfully."
echo "===================================================================="
