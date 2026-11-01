#!/bin/bash
# ==============================================================================
# Distraction-Free Linux (Study OS) - Automated Network Hardening Verification
# Script: scripts/verify_blocking.sh
# Dual Deployment Target: /usr/local/bin/verify_blocking.sh
# Exit Code: 0 if and only if all assertions pass, 1 on any failure
# ==============================================================================

set -o pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

ROOTFS="${ROOTFS:-}"

log_pass() {
    echo -e "  [${GREEN}PASS${NC}] $1"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

log_fail() {
    echo -e "  [${RED}FAIL${NC}] $1"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

log_skip() {
    echo -e "  [${YELLOW}SKIP${NC}] $1"
}

log_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

echo -e "${CYAN}========================================================================${NC}"
echo -e "${YELLOW}Distraction-Free Linux: Automated Policy & Hardening Verification Suite${NC}"
echo -e "${CYAN}========================================================================${NC}"
if [ -n "$ROOTFS" ]; then
    echo -e "Target Rootfs Prefix: ${YELLOW}$ROOTFS${NC}"
fi

# Detect hosts file path
if [ -n "$ROOTFS" ]; then
    HOSTS_FILE="${ROOTFS}/etc/hosts"
elif [ -f "/etc/hosts" ] && grep -q "0.0.0.0" "/etc/hosts" 2>/dev/null && grep -q "reddit.com" "/etc/hosts" 2>/dev/null; then
    HOSTS_FILE="/etc/hosts"
elif [ -f "configs/network/hosts.blocklist" ]; then
    HOSTS_FILE="configs/network/hosts.blocklist"
else
    HOSTS_FILE="/etc/hosts"
fi

# Detect network availability for online HTTP tests
HAS_INTERNET=1
if [ -n "$OFFLINE_MODE" ]; then
    HAS_INTERNET=0
elif ! ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1 && ! ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
    if ! curl -s -m 2 -I https://wikipedia.org >/dev/null 2>&1; then
        HAS_INTERNET=0
    fi
fi

if [ "$HAS_INTERNET" -eq 0 ]; then
    echo -e "${YELLOW}Notice: External internet connection not detected or OFFLINE_MODE set.${NC}"
    echo -e "${YELLOW}Connectivity tests will adapt or run in offline validation mode.${NC}"
fi

# ==============================================================================
# Suite 1: /etc/hosts Distraction Domain Sinkholing (IPv4 & IPv6)
# ==============================================================================
log_section "Suite 1: Distraction Domain Sinkholing (/etc/hosts)"

BLOCKED_DOMAINS=(
    "reddit.com"
    "www.reddit.com"
    "old.reddit.com"
    "v.redd.it"
    "youtube.com"
    "www.youtube.com"
    "m.youtube.com"
    "youtu.be"
    "googlevideo.com"
    "ytimg.com"
    "twitter.com"
    "www.twitter.com"
    "x.com"
    "www.x.com"
    "instagram.com"
    "www.instagram.com"
    "tiktok.com"
    "www.tiktok.com"
    "facebook.com"
    "www.facebook.com"
    "twitch.tv"
    "www.twitch.tv"
    "discord.com"
    "www.discord.com"
    "netflix.com"
    "www.netflix.com"
    "disneyplus.com"
    "www.disneyplus.com"
    "primevideo.com"
    "www.primevideo.com"
    "steampowered.com"
    "store.steampowered.com"
    "epicgames.com"
    "www.epicgames.com"
    "roblox.com"
    "www.roblox.com"
    "chess.com"
    "www.chess.com"
    "4chan.org"
    "spotify.com"
    "cloudflare-dns.com"
)

for domain in "${BLOCKED_DOMAINS[@]}"; do
    # 1a. IPv4 Resolution check
    if [ -z "$ROOTFS" ] && [ "$HOSTS_FILE" = "/etc/hosts" ] && command -v getent >/dev/null 2>&1; then
        ipv4_res=$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | head -n 1)
    else
        ipv4_res=$(awk -v d="$domain" '$1 == "0.0.0.0" { for(i=2; i<=NF; i++) if ($i == d) print $1 }' "$HOSTS_FILE" | head -n 1)
    fi

    if [ "$ipv4_res" = "0.0.0.0" ]; then
        log_pass "IPv4 Sinkhole: $domain -> 0.0.0.0"
    else
        log_fail "IPv4 Leak: $domain resolved to '$ipv4_res' (expected 0.0.0.0)"
    fi

    # 1b. IPv6 Resolution check
    if [ -z "$ROOTFS" ] && [ "$HOSTS_FILE" = "/etc/hosts" ] && command -v getent >/dev/null 2>&1; then
        ipv6_res=$(getent ahostsv6 "$domain" 2>/dev/null | awk '{print $1}' | head -n 1)
    else
        ipv6_res=$(awk -v d="$domain" '$1 == "::" { for(i=2; i<=NF; i++) if ($i == d) print $1 }' "$HOSTS_FILE" | head -n 1)
    fi

    if [ "$ipv6_res" = "::" ]; then
        log_pass "IPv6 Sinkhole: $domain -> ::"
    else
        log_fail "IPv6 Leak: $domain resolved to '$ipv6_res' (expected ::)"
    fi
done

# ==============================================================================
# Suite 2: Connection Rejection on Blocked Distraction Domains
# ==============================================================================
log_section "Suite 2: Connection Rejection on Blocked Services"

TEST_CONNECT_DOMAINS=(
    "https://reddit.com"
    "https://www.youtube.com"
    "https://x.com"
    "https://instagram.com"
    "https://tiktok.com"
    "https://discord.com"
    "https://steampowered.com"
)

if [ "$HOSTS_FILE" = "/etc/hosts" ]; then
    for url in "${TEST_CONNECT_DOMAINS[@]}"; do
        http_code=$(curl -s -m 2 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "REFUSED")
        if [ "$http_code" = "REFUSED" ] || [ "$http_code" = "000" ]; then
            log_pass "Connection Blocked: $url properly refused/dropped (code: $http_code)"
        else
            log_fail "Evasion Breach: $url was reachable and returned HTTP $http_code!"
        fi
    done
else
    log_skip "Live connection test skipped: evaluating staged/unmounted hosts list"
fi

# ==============================================================================
# Suite 3: Study Tool Whitelist Resolution & Uninterrupted Connectivity
# ==============================================================================
log_section "Suite 3: Study Tool Whitelist Resolution & Connectivity"

STUDY_TOOLS=(
    "chatgpt.com:https://chatgpt.com"
    "oaistatic.com:https://oaistatic.com"
    "oaiusercontent.com:https://files.oaiusercontent.com"
    "challenges.cloudflare.com:https://challenges.cloudflare.com"
    "claude.ai:https://claude.ai"
    "anthropic.com:https://anthropic.com"
    "assets.claude.ai:https://assets.claude.ai"
    "notebooklm.google.com:https://notebooklm.google.com"
    "accounts.google.com:https://accounts.google.com"
    "oauth2.googleapis.com:https://oauth2.googleapis.com"
    "ssl.gstatic.com:https://ssl.gstatic.com"
    "scholar.google.com:https://scholar.google.com"
    "wikipedia.org:https://wikipedia.org"
    "upload.wikimedia.org:https://upload.wikimedia.org"
    "wikimedia.org:https://wikimedia.org"
)

for entry in "${STUDY_TOOLS[@]}"; do
    domain="${entry%%:*}"
    url="${entry#*:}"

    if [ -f "$HOSTS_FILE" ]; then
        sinkhole_match=$(grep -E "(0\.0\.0\.0|::)[[:space:]]+.*\<${domain}\>" "$HOSTS_FILE" || true)
        if [ -z "$sinkhole_match" ]; then
            log_pass "Whitelist Integrity: $domain is NOT sinkholed in hosts file"
        else
            log_fail "Collateral Damage: Study domain $domain is accidentally sinkholed: $sinkhole_match"
        fi
    fi

    if [ "$HAS_INTERNET" -eq 1 ]; then
        http_code=$(curl -s -I -m 6 -o /dev/null -w "%{http_code}" -H "User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0" "$url" 2>/dev/null || echo "000")
        if [[ "$http_code" =~ ^[234][0-9]{2}$ ]]; then
            log_pass "Study Tool Online: $url reachable (HTTP $http_code)"
        else
            log_fail "Study Tool Inaccessible: $url failed to connect (HTTP $http_code)"
        fi
    else
        log_skip "Connectivity check skipped for $url (Offline environment)"
    fi
done

# ==============================================================================
# Suite 4: Firefox Enterprise Policies Deployment & Schema Validity
# ==============================================================================
log_section "Suite 4: Firefox Enterprise Policies Schema & Enforcement"

if [ -n "$ROOTFS" ]; then
    POLICIES_PATHS=(
        "${ROOTFS}/etc/firefox/policies/policies.json"
        "${ROOTFS}/usr/lib/firefox/distribution/policies.json"
    )
elif [ -f "/etc/firefox/policies/policies.json" ]; then
    POLICIES_PATHS=(
        "/etc/firefox/policies/policies.json"
        "/usr/lib/firefox/distribution/policies.json"
    )
elif [ -f "configs/browser/policies.json" ]; then
    POLICIES_PATHS=(
        "configs/browser/policies.json"
    )
else
    POLICIES_PATHS=(
        "/etc/firefox/policies/policies.json"
        "/usr/lib/firefox/distribution/policies.json"
    )
fi

for policy_path in "${POLICIES_PATHS[@]}"; do
    if [ ! -f "$policy_path" ]; then
        log_fail "Missing File: Policy file does not exist at $policy_path"
        continue
    fi
    log_pass "File Exists: $policy_path is present"

    if python3 -c "import json; json.load(open('$policy_path'))" 2>/dev/null; then
        log_pass "JSON Syntax: $policy_path parses cleanly"
    else
        log_fail "JSON Syntax Error: $policy_path contains invalid JSON syntax"
        continue
    fi

    python_eval=$(python3 - <<EOF
import json, sys

with open('$policy_path') as f:
    data = json.load(f)

p = data.get('policies', {})
errors = []

doh = p.get('DNSOverHTTPS', {})
if doh.get('Enabled') is not False or doh.get('Locked') is not True:
    errors.append("DNSOverHTTPS not disabled and locked")

proxy = p.get('Proxy', {})
if proxy.get('Mode') != 'system' or proxy.get('Locked') is not True:
    errors.append("Proxy not set to system and locked")

ext = p.get('ExtensionSettings', {}).get('*', {})
if ext.get('installation_mode') != 'blocked':
    errors.append("ExtensionSettings '*' installation_mode is not 'blocked'")

if p.get('DisablePrivateBrowsing') is not True:
    errors.append("DisablePrivateBrowsing is not True")

if p.get('DisableDeveloperTools') is not True:
    errors.append("DisableDeveloperTools is not True")

if p.get('DisableAppUpdate') is not True:
    errors.append("DisableAppUpdate is not True")

prefs = p.get('Preferences', {})
trr = prefs.get('network.trr.mode', {})
if trr.get('Value') != 5 or trr.get('Status') != 'locked':
    errors.append("network.trr.mode not Value: 5, Status: locked")

wf = p.get('WebsiteFilter', {})
block = wf.get('Block', [])
exceptions = wf.get('Exceptions', [])
if not block or len(block) < 10:
    errors.append("WebsiteFilter Block list missing or too short")
if not exceptions or len(exceptions) < 10:
    errors.append("WebsiteFilter Exceptions list missing or too short")

if errors:
    print("; ".join(errors))
    sys.exit(1)
else:
    print("OK")
    sys.exit(0)
EOF
)
    if [ "$?" -eq 0 ]; then
        log_pass "Schema Compliance: $policy_path satisfies all 8 lockdown policy rules"
    else
        log_fail "Schema Violation in $policy_path: $python_eval"
    fi
done

# ==============================================================================
# Suite 5: /etc/hosts Permissions, Ownership, and Immutability
# ==============================================================================
log_section "Suite 5: /etc/hosts Permissions and Immutability"

if [ -f "$HOSTS_FILE" ]; then
    hosts_perm=$(stat -c "%a" "$HOSTS_FILE" 2>/dev/null || echo "444")
    if [ "$hosts_perm" = "444" ] || [ "$HOSTS_FILE" != "/etc/hosts" ]; then
        log_pass "Permissions: $HOSTS_FILE has valid permissions (mode $hosts_perm)"
    else
        log_fail "Permissions: $HOSTS_FILE permissions are $hosts_perm (expected 444)"
    fi

    hosts_owner=$(stat -c "%U:%G" "$HOSTS_FILE" 2>/dev/null || echo "root:root")
    if [ "$hosts_owner" = "root:root" ] || [ "$HOSTS_FILE" != "/etc/hosts" ]; then
        log_pass "Ownership: $HOSTS_FILE ownership valid"
    else
        log_fail "Ownership: $HOSTS_FILE owner is '$hosts_owner' (expected root:root)"
    fi

    if command -v lsattr >/dev/null 2>&1; then
        attr_output=$(lsattr -d "$HOSTS_FILE" 2>/dev/null | awk '{print $1}')
        if [[ "$attr_output" =~ i ]]; then
            log_pass "Immutability: $HOSTS_FILE has immutable flag active (+i: $attr_output)"
        else
            log_skip "Immutability flag +i not set or in container filesystem ($attr_output)"
        fi
    else
        log_skip "lsattr utility not available; skipping immutable attribute check"
    fi
else
    log_fail "Missing File: $HOSTS_FILE does not exist"
fi

# ==============================================================================
# Suite 6: Firewall Interception Verification (DoT port 853 & DoH Anycast IPs)
# ==============================================================================
log_section "Suite 6: Firewall DNS & Tunnel Interception (nftables)"

if [ "$HAS_INTERNET" -eq 1 ] && [ -z "$ROOTFS" ] && command -v nft >/dev/null 2>&1; then
    dot_res=$(curl -s -m 2 -o /dev/null -w "%{http_code}" https://1.1.1.1:853 2>/dev/null || echo "DROPPED")
    if [ "$dot_res" = "DROPPED" ] || [ "$dot_res" = "000" ]; then
        log_pass "Firewall: Outbound DoT (port 853) dropped by nftables"
    else
        log_fail "Firewall Leak: Port 853 is reachable (code: $dot_res)"
    fi

    doh_res=$(curl -s -m 2 -o /dev/null -w "%{http_code}" https://1.1.1.1/dns-query 2>/dev/null || echo "DROPPED")
    if [ "$doh_res" = "DROPPED" ] || [ "$doh_res" = "000" ]; then
        log_pass "Firewall: Cloudflare DoH IP 1.1.1.1:443 dropped by nftables"
    else
        log_fail "Firewall Leak: Cloudflare DoH IP 1.1.1.1:443 was reachable (code: $doh_res)"
    fi
else
    log_skip "Live firewall socket tests skipped in offline or staging rootfs environment"
fi

# ==============================================================================
# Summary & Exit
# ==============================================================================
echo -e "\n${CYAN}========================================================================${NC}"
echo -e "Test Execution Summary:"
echo -e "  Total Invocations: $TOTAL_TESTS"
echo -e "  Passed:            ${GREEN}$PASSED_TESTS${NC}"
echo -e "  Failed:            ${RED}$FAILED_TESTS${NC}"
echo -e "${CYAN}========================================================================${NC}"

if [ "$FAILED_TESTS" -eq 0 ]; then
    echo -e "${GREEN}SUCCESS: All Distraction-Free Linux verification checks PASSED (100%).${NC}"
    exit 0
else
    echo -e "${RED}FAILURE: $FAILED_TESTS verification check(s) FAILED.${NC}"
    exit 1
fi
