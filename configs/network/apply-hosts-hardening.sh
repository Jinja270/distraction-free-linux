#!/bin/bash
# ==============================================================================
# Distraction-Free Linux: Host & Tamper-Resistance Enforcer
# File: /usr/local/sbin/apply-hosts-hardening.sh
# Invoked at boot via study-hosts-hardening.service
# ==============================================================================
set -euo pipefail

echo "[DFL Hardening] Asserting distraction blocking and tamper resistance..."

# 1. Self-healing content verification and restoration
BLOCKLIST_SOURCE=""
if [ -f /etc/hosts.blocklist ]; then
    BLOCKLIST_SOURCE="/etc/hosts.blocklist"
elif [ -f /etc/network/hosts.blocklist ]; then
    BLOCKLIST_SOURCE="/etc/network/hosts.blocklist"
elif [ -f "$(dirname "$0")/hosts.blocklist" ]; then
    BLOCKLIST_SOURCE="$(dirname "$0")/hosts.blocklist"
elif [ -f "configs/network/hosts.blocklist" ]; then
    BLOCKLIST_SOURCE="configs/network/hosts.blocklist"
fi

if [ ! -f /etc/hosts ] || ! grep -q "reddit.com" /etc/hosts 2>/dev/null; then
    echo "[DFL Hardening] WARNING: /etc/hosts missing mandatory blocks! Self-healing triggered..."
    # Unlock if immutable
    chattr -i /etc/hosts 2>/dev/null || true
    chmod 0644 /etc/hosts 2>/dev/null || true

    # Restore baseline hosts
    if [ -f /etc/hosts.original ]; then
        cat /etc/hosts.original > /etc/hosts
    else
        cat << 'EOF' > /etc/hosts
127.0.0.1   localhost distraction-free-study
127.0.1.1   distraction-free-study
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF
    fi

    echo "" >> /etc/hosts
    if [ -n "$BLOCKLIST_SOURCE" ] && [ -f "$BLOCKLIST_SOURCE" ]; then
        cat "$BLOCKLIST_SOURCE" >> /etc/hosts
        echo "[DFL Hardening] /etc/hosts restored from ${BLOCKLIST_SOURCE}."
    fi
fi

# 2. Enforce strict permissions and root ownership on /etc/hosts
if [ -f /etc/hosts ]; then
    chown root:root /etc/hosts 2>/dev/null || true
    chmod 0444 /etc/hosts
    # Assert immutable flag (+i)
    chattr +i /etc/hosts 2>/dev/null || true
    echo "[DFL Hardening] /etc/hosts locked (+i, 0444, root:root)."
fi

# 2. Enforce strict permissions and root ownership on Firefox Enterprise policies
for policy_file in /etc/firefox/policies/policies.json /usr/lib/firefox/distribution/policies.json; do
    if [ -f "$policy_file" ]; then
        chown root:root "$policy_file"
        chmod 0444 "$policy_file"
        chattr +i "$policy_file" 2>/dev/null || true
        echo "[DFL Hardening] $policy_file locked (+i, 0444, root:root)."
    fi
done

# 3. Restrict chattr and lsattr binary execution to root UID only
for bin in /usr/bin/chattr /usr/bin/lsattr /bin/chattr /bin/lsattr; do
    if [ -f "$bin" ]; then
        chown root:root "$bin"
        chmod 0700 "$bin"
    fi
done

# 4. Verify sudoers lockdown permissions
if [ -f /etc/sudoers.d/99-lockdown ]; then
    chown root:root /etc/sudoers.d/99-lockdown
    chmod 0440 /etc/sudoers.d/99-lockdown
fi

echo "[DFL Hardening] Tamper-resistance enforcement complete."
exit 0
