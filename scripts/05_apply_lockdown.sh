#!/bin/bash
# ==============================================================================
# Distraction-Free Linux (Study OS) - Rootfs Lockdown & Hardening Integration
# File: scripts/05_apply_lockdown.sh
# Purpose: Integrate hosts sinkhole, nftables firewall, sudoers lockdown,
#          systemd hardening service, and Firefox Enterprise policies into rootfs.
# ==============================================================================
set -euo pipefail

ROOTFS_DIR="${1:-/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "===================================================================="
echo "Distraction-Free Linux: Applying Milestone 1 Lockdown to ${ROOTFS_DIR}"
echo "===================================================================="

# ------------------------------------------------------------------------------
# 1. System Hosts Sinkhole & Inode Hardening
# ------------------------------------------------------------------------------
echo "===> [1/4] Applying /etc/hosts sinkhole and tamper resistance..."

if [ ! -f "${ROOTFS_DIR}/etc/hosts.original" ]; then
    if [ -f "${ROOTFS_DIR}/etc/hosts" ]; then
        cp "${ROOTFS_DIR}/etc/hosts" "${ROOTFS_DIR}/etc/hosts.original"
    else
        cat << 'EOF' > "${ROOTFS_DIR}/etc/hosts.original"
127.0.0.1   localhost distraction-free-study
127.0.1.1   distraction-free-study
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF
    fi
fi

# Build unified /etc/hosts
cat "${ROOTFS_DIR}/etc/hosts.original" > "${ROOTFS_DIR}/etc/hosts"
echo "" >> "${ROOTFS_DIR}/etc/hosts"
cat "${SCRIPT_DIR}/configs/network/hosts.blocklist" >> "${ROOTFS_DIR}/etc/hosts"

chown root:root "${ROOTFS_DIR}/etc/hosts" 2>/dev/null || true
chmod 0444 "${ROOTFS_DIR}/etc/hosts"

# Deploy backup of hosts.blocklist for self-healing runtime restoration
install -m 0444 "${SCRIPT_DIR}/configs/network/hosts.blocklist" \
               "${ROOTFS_DIR}/etc/hosts.blocklist"
chown root:root "${ROOTFS_DIR}/etc/hosts.blocklist" 2>/dev/null || true

# Deploy hardening helper script
install -d -m 0755 "${ROOTFS_DIR}/usr/local/sbin"
install -m 0755 "${SCRIPT_DIR}/configs/network/apply-hosts-hardening.sh" \
               "${ROOTFS_DIR}/usr/local/sbin/apply-hosts-hardening.sh"
chown root:root "${ROOTFS_DIR}/usr/local/sbin/apply-hosts-hardening.sh" 2>/dev/null || true

# Deploy and enable systemd study-hosts-hardening.service
install -d -m 0755 "${ROOTFS_DIR}/etc/systemd/system"
install -m 0644 "${SCRIPT_DIR}/configs/network/study-hosts-hardening.service" \
               "${ROOTFS_DIR}/etc/systemd/system/study-hosts-hardening.service"

install -d -m 0755 "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants"
ln -sf "/etc/systemd/system/study-hosts-hardening.service" \
       "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/study-hosts-hardening.service"

# Deploy Sudoers lockdown snippet
install -d -m 0750 "${ROOTFS_DIR}/etc/sudoers.d"
install -m 0440 "${SCRIPT_DIR}/configs/security/99-lockdown" \
               "${ROOTFS_DIR}/etc/sudoers.d/99-lockdown"
chown root:root "${ROOTFS_DIR}/etc/sudoers.d/99-lockdown" 2>/dev/null || true

# Neutralize permissive default casper sudoers if present
if [ -f "${ROOTFS_DIR}/etc/sudoers.d/casper" ]; then
    rm -f "${ROOTFS_DIR}/etc/sudoers.d/casper"
fi

# Restrict chattr/lsattr executable permissions to root
for bin_path in "${ROOTFS_DIR}/usr/bin/chattr" "${ROOTFS_DIR}/usr/bin/lsattr" \
                "${ROOTFS_DIR}/bin/chattr" "${ROOTFS_DIR}/bin/lsattr"; do
    if [ -f "${bin_path}" ]; then
        chmod 0700 "${bin_path}"
        chown root:root "${bin_path}" 2>/dev/null || true
    fi
done

# Apply chattr +i to /etc/hosts and hosts.blocklist (ignore failure in non-ext4/container environments)
chattr +i "${ROOTFS_DIR}/etc/hosts" 2>/dev/null || true
chattr +i "${ROOTFS_DIR}/etc/hosts.blocklist" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 2. Firewall & Kernel Network Hardening (nftables & wireguard)
# ------------------------------------------------------------------------------
echo "===> [2/4] Deploying nftables firewall & WireGuard blacklist..."

install -d -m 0755 "${ROOTFS_DIR}/etc"
install -m 0644 "${SCRIPT_DIR}/configs/network/nftables.conf" \
               "${ROOTFS_DIR}/etc/nftables.conf"
chown root:root "${ROOTFS_DIR}/etc/nftables.conf" 2>/dev/null || true

# Enable nftables.service
install -d -m 0755 "${ROOTFS_DIR}/etc/systemd/system/sysinit.target.wants"
ln -sf "/lib/systemd/system/nftables.service" \
       "${ROOTFS_DIR}/etc/systemd/system/sysinit.target.wants/nftables.service" 2>/dev/null || true

# Validate syntax if nft tool is present in current environment
if command -v nft >/dev/null 2>&1; then
    echo "Validating nftables.conf syntax..."
    nft -c -f "${ROOTFS_DIR}/etc/nftables.conf"
fi

# Deploy WireGuard kernel blacklist
install -d -m 0755 "${ROOTFS_DIR}/etc/modprobe.d"
install -m 0444 "${SCRIPT_DIR}/configs/security/wireguard-lockdown.conf" \
               "${ROOTFS_DIR}/etc/modprobe.d/wireguard-lockdown.conf"
chown root:root "${ROOTFS_DIR}/etc/modprobe.d/wireguard-lockdown.conf" 2>/dev/null || true

chattr +i "${ROOTFS_DIR}/etc/nftables.conf" 2>/dev/null || true
chattr +i "${ROOTFS_DIR}/etc/modprobe.d/wireguard-lockdown.conf" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 3. Hardened Firefox Enterprise Policies
# ------------------------------------------------------------------------------
echo "===> [3/4] Deploying Firefox Enterprise policies.json..."

install -d -m 0755 "${ROOTFS_DIR}/etc/firefox/policies"
install -d -m 0755 "${ROOTFS_DIR}/usr/lib/firefox/distribution"

install -m 0444 "${SCRIPT_DIR}/configs/browser/policies.json" \
               "${ROOTFS_DIR}/etc/firefox/policies/policies.json"
install -m 0444 "${SCRIPT_DIR}/configs/browser/policies.json" \
               "${ROOTFS_DIR}/usr/lib/firefox/distribution/policies.json"

chown root:root "${ROOTFS_DIR}/etc/firefox/policies/policies.json" 2>/dev/null || true
chown root:root "${ROOTFS_DIR}/usr/lib/firefox/distribution/policies.json" 2>/dev/null || true

chattr +i "${ROOTFS_DIR}/etc/firefox/policies/policies.json" 2>/dev/null || true
chattr +i "${ROOTFS_DIR}/usr/lib/firefox/distribution/policies.json" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 4. Deploy Automated Verification Tools to System Path
# ------------------------------------------------------------------------------
echo "===> [4/4] Installing verification scripts to /usr/local/bin..."

install -d -m 0755 "${ROOTFS_DIR}/usr/local/bin"
install -m 0755 "${SCRIPT_DIR}/scripts/verify_blocking.sh" \
               "${ROOTFS_DIR}/usr/local/bin/verify_blocking.sh"
install -m 0755 "${SCRIPT_DIR}/scripts/verify_blocking.py" \
               "${ROOTFS_DIR}/usr/local/bin/verify_blocking.py"

chown root:root "${ROOTFS_DIR}/usr/local/bin/verify_blocking.sh" 2>/dev/null || true
chown root:root "${ROOTFS_DIR}/usr/local/bin/verify_blocking.py" 2>/dev/null || true

echo "===================================================================="
echo "Milestone 1 Lockdown successfully integrated into ${ROOTFS_DIR}."
echo "===================================================================="
