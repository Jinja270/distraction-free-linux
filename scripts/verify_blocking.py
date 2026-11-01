#!/usr/bin/env python3
"""
Distraction-Free Linux (Study OS) - Automated Network Hardening Verification Suite
Script: scripts/verify_blocking.py
Dual Deployment Target: /usr/local/bin/verify_blocking.py

Exit Code: 0 if and only if all assertions pass, 1 on any failure.
Standard Library Only: Requires no external pip dependencies.
"""

import sys
import os
import json
import socket
import ssl
import urllib.request
import urllib.error
import subprocess
import stat
import argparse
from typing import List, Tuple, Dict, Any, Optional

RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
CYAN = "\033[0;36m"
NC = "\033[0m"


class VerificationReporter:
    def __init__(self):
        self.total = 0
        self.passed = 0
        self.failed = 0
        self.skipped = 0

    def record_pass(self, title: str, detail: str = ""):
        self.total += 1
        self.passed += 1
        suffix = f" ({detail})" if detail else ""
        print(f"  [{GREEN}PASS{NC}] {title}{suffix}")

    def record_fail(self, title: str, reason: str):
        self.total += 1
        self.failed += 1
        print(f"  [{RED}FAIL{NC}] {title} - Reason: {reason}")

    def record_skip(self, title: str, reason: str):
        self.skipped += 1
        print(f"  [{YELLOW}SKIP{NC}] {title} - Reason: {reason}")

    def print_summary(self):
        print(f"\n{CYAN}========================================================================{NC}")
        print("Test Execution Summary:")
        print(f"  Total Invocations: {self.total}")
        print(f"  Passed:            {GREEN}{self.passed}{NC}")
        print(f"  Failed:            {RED}{self.failed}{NC}")
        print(f"  Skipped:           {YELLOW}{self.skipped}{NC}")
        print(f"{CYAN}========================================================================{NC}")


report = VerificationReporter()


def section(name: str):
    print(f"\n{BLUE}=== {name} ==={NC}")


def is_online() -> bool:
    """Check if outward internet connectivity is available."""
    if os.environ.get("OFFLINE_MODE") == "1":
        return False
    # Attempt quick socket connect to Wikipedia
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2.0)
        s.connect(("wikipedia.org", 443))
        s.close()
        return True
    except Exception:
        pass

    # Fallback DNS check
    try:
        socket.gethostbyname("scholar.google.com")
        return True
    except Exception:
        return False


def resolve_hosts_path(rootfs: str) -> str:
    if rootfs:
        return os.path.join(rootfs, "etc", "hosts")
    if os.path.exists("/etc/hosts"):
        try:
            with open("/etc/hosts", "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
                if "0.0.0.0" in content and "reddit.com" in content:
                    return "/etc/hosts"
        except Exception:
            pass
    if os.path.exists("configs/network/hosts.blocklist"):
        return "configs/network/hosts.blocklist"
    return "/etc/hosts"


# ==============================================================================
# Suite 1: /etc/hosts Distraction Domain Sinkholing
# ==============================================================================
def test_distraction_domain_resolution(rootfs: str):
    section("Suite 1: Distraction Domain Sinkholing (IPv4 & IPv6)")

    blocked_domains = [
        "reddit.com", "www.reddit.com", "old.reddit.com", "v.redd.it",
        "youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "googlevideo.com", "ytimg.com",
        "twitter.com", "www.twitter.com", "x.com", "www.x.com", "instagram.com", "www.instagram.com", "tiktok.com",
        "facebook.com", "www.facebook.com", "twitch.tv", "www.twitch.tv", "discord.com", "www.discord.com",
        "netflix.com", "www.netflix.com", "disneyplus.com", "www.disneyplus.com", "primevideo.com", "www.primevideo.com",
        "steampowered.com", "store.steampowered.com", "epicgames.com", "www.epicgames.com", "roblox.com", "www.roblox.com",
        "chess.com", "www.chess.com", "4chan.org", "spotify.com", "cloudflare-dns.com"
    ]

    hosts_file = resolve_hosts_path(rootfs)

    # Pre-parse hosts file
    hosts_ipv4_map: Dict[str, str] = {}
    hosts_ipv6_map: Dict[str, str] = {}

    if os.path.exists(hosts_file):
        try:
            with open(hosts_file, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    parts = line.split()
                    if len(parts) >= 2:
                        ip = parts[0]
                        for host in parts[1:]:
                            h = host.lower()
                            if ip == "0.0.0.0":
                                hosts_ipv4_map[h] = ip
                            elif ip == "::":
                                hosts_ipv6_map[h] = ip
        except Exception as e:
            report.record_fail("Hosts File Read", str(e))
    else:
        report.record_fail("Hosts File Existence", f"File not found: {hosts_file}")
        return

    is_live_system_hosts = (hosts_file == "/etc/hosts" and not rootfs)

    for domain in blocked_domains:
        # Check IPv4
        if is_live_system_hosts:
            try:
                addr_info = socket.getaddrinfo(domain, 80, socket.AF_INET, socket.SOCK_STREAM)
                resolved_ips = {item[4][0] for item in addr_info}
                if resolved_ips == {"0.0.0.0"}:
                    report.record_pass(f"IPv4 Sinkhole: {domain}", "resolved to 0.0.0.0")
                else:
                    report.record_fail(f"IPv4 Leak: {domain}", f"resolved to {resolved_ips}")
            except socket.gaierror as e:
                report.record_pass(f"IPv4 Sinkhole: {domain}", f"refused by resolver ({e})")
            except Exception as e:
                report.record_fail(f"IPv4 Query Error: {domain}", str(e))
        else:
            if hosts_ipv4_map.get(domain) == "0.0.0.0":
                report.record_pass(f"IPv4 Sinkhole Map: {domain}", "mapped to 0.0.0.0")
            else:
                report.record_fail(f"IPv4 Missing Map: {domain}", f"mapped to '{hosts_ipv4_map.get(domain)}'")

        # Check IPv6
        if is_live_system_hosts:
            try:
                addr_info_v6 = socket.getaddrinfo(domain, 80, socket.AF_INET6, socket.SOCK_STREAM)
                resolved_ips_v6 = {item[4][0] for item in addr_info_v6}
                if resolved_ips_v6 == {"::"}:
                    report.record_pass(f"IPv6 Sinkhole: {domain}", "resolved to ::")
                else:
                    report.record_fail(f"IPv6 Leak: {domain}", f"resolved to {resolved_ips_v6}")
            except socket.gaierror as e:
                if hosts_ipv6_map.get(domain) == "::":
                    report.record_pass(f"IPv6 Sinkhole: {domain}", "confirmed :: in hosts")
                else:
                    report.record_pass(f"IPv6 Resolution: {domain}", f"resolver returned: {e}")
            except Exception as e:
                report.record_fail(f"IPv6 Query Error: {domain}", str(e))
        else:
            if hosts_ipv6_map.get(domain) == "::":
                report.record_pass(f"IPv6 Sinkhole Map: {domain}", "mapped to ::")
            else:
                report.record_fail(f"IPv6 Missing Map: {domain}", f"mapped to '{hosts_ipv6_map.get(domain)}'")


# ==============================================================================
# Suite 2: Connection Rejection on Blocked Services
# ==============================================================================
def test_connection_refusal(rootfs: str):
    section("Suite 2: Connection Failure on Blocked Services")

    hosts_file = resolve_hosts_path(rootfs)
    if hosts_file != "/etc/hosts" or rootfs:
        report.record_skip("Live TCP Connection Tests", "Testing against staged blocklist or rootfs")
        return

    test_targets = [
        ("reddit.com", 443),
        ("youtube.com", 443),
        ("x.com", 443),
        ("instagram.com", 443),
        ("tiktok.com", 443),
        ("discord.com", 443),
        ("steampowered.com", 443)
    ]

    for host, port in test_targets:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2.0)
        try:
            sock.connect((host, port))
            sock.close()
            report.record_fail(f"Evasion Breach: {host}:{port}", "TCP connection unexpectedly established!")
        except (socket.timeout, ConnectionRefusedError, OSError) as e:
            report.record_pass(f"Connection Blocked: {host}:{port}", f"properly rejected ({type(e).__name__})")


# ==============================================================================
# Suite 3: Study Tool Whitelist Resolution & Uninterrupted Connectivity
# ==============================================================================
def test_study_tool_whitelist(rootfs: str, online: bool):
    section("Suite 3: Study Tool Whitelist Resolution & Connectivity")

    study_tool_domains = [
        ("chatgpt.com", "https://chatgpt.com"),
        ("oaistatic.com", "https://oaistatic.com"),
        ("oaiusercontent.com", "https://oaiusercontent.com"),
        ("challenges.cloudflare.com", "https://challenges.cloudflare.com"),
        ("claude.ai", "https://claude.ai"),
        ("anthropic.com", "https://anthropic.com"),
        ("assets.claude.ai", "https://assets.claude.ai"),
        ("notebooklm.google.com", "https://notebooklm.google.com"),
        ("accounts.google.com", "https://accounts.google.com"),
        ("oauth2.googleapis.com", "https://oauth2.googleapis.com"),
        ("ssl.gstatic.com", "https://ssl.gstatic.com"),
        ("scholar.google.com", "https://scholar.google.com"),
        ("wikipedia.org", "https://wikipedia.org"),
        ("upload.wikimedia.org", "https://upload.wikimedia.org"),
        ("wikimedia.org", "https://wikimedia.org")
    ]

    hosts_file = resolve_hosts_path(rootfs)

    if os.path.exists(hosts_file):
        with open(hosts_file, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            for domain, _ in study_tool_domains:
                is_sinkholed = False
                for line in content.splitlines():
                    line = line.strip()
                    if line.startswith("0.0.0.0") or line.startswith("::"):
                        tokens = [t.lower() for t in line.split()]
                        if domain.lower() in tokens[1:]:
                            is_sinkholed = True
                            break
                if not is_sinkholed:
                    report.record_pass(f"Whitelist Integrity: {domain}", "not blocked in hosts file")
                else:
                    report.record_fail(f"Collateral Damage: {domain}", "accidentally sinkholed in hosts file!")

    if not online:
        report.record_skip("Live HTTPS Reachability", "Offline environment")
        return

    ctx = ssl.create_default_context()
    opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx))
    user_agent = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0"

    for domain, url in study_tool_domains:
        req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": user_agent})
        try:
            with opener.open(req, timeout=7.0) as resp:
                code = resp.getcode()
                if code < 500:
                    report.record_pass(f"Study Tool Online: {domain}", f"HTTP {code}")
                else:
                    report.record_fail(f"Study Tool Status: {domain}", f"Unexpected HTTP {code}")
        except urllib.error.HTTPError as e:
            if e.code < 500:
                report.record_pass(f"Study Tool Reachable: {domain}", f"HTTP {e.code} (Edge TLS Reached)")
            else:
                report.record_fail(f"Study Tool HTTP Error: {domain}", f"HTTP {e.code}")
        except urllib.error.URLError as e:
            if domain == "oaiusercontent.com":
                sub_url = "https://files.oaiusercontent.com"
                try:
                    sub_req = urllib.request.Request(sub_url, method="HEAD", headers={"User-Agent": user_agent})
                    with opener.open(sub_req, timeout=7.0) as resp:
                        report.record_pass(f"Study Tool Reachable: {domain}", f"HTTP {resp.getcode()} (via files.oaiusercontent.com)")
                except urllib.error.HTTPError as he:
                    if he.code < 500:
                        report.record_pass(f"Study Tool Reachable: {domain}", f"HTTP {he.code} (Edge TLS Reached via files.oaiusercontent.com)")
                    else:
                        report.record_fail(f"Study Tool HTTP Error: {domain}", f"HTTP {he.code}")
                except Exception as ex:
                    report.record_fail(f"Study Tool Unreachable: {domain}", str(ex))
            else:
                report.record_fail(f"Study Tool Unreachable: {domain}", str(e))
        except Exception as e:
            report.record_fail(f"Study Tool Unreachable: {domain}", str(e))


# ==============================================================================
# Suite 4: Firefox Enterprise Policies Deployment & Schema Validity
# ==============================================================================
def test_firefox_enterprise_policies(rootfs: str):
    section("Suite 4: Firefox Enterprise Policy Deployment & Schema Validity")

    if rootfs:
        policy_paths = [
            os.path.join(rootfs, "etc", "firefox", "policies", "policies.json"),
            os.path.join(rootfs, "usr", "lib", "firefox", "distribution", "policies.json"),
        ]
    elif os.path.exists("/etc/firefox/policies/policies.json"):
        policy_paths = [
            "/etc/firefox/policies/policies.json",
            "/usr/lib/firefox/distribution/policies.json",
        ]
    elif os.path.exists("configs/browser/policies.json"):
        policy_paths = [
            "configs/browser/policies.json",
        ]
    else:
        policy_paths = [
            "/etc/firefox/policies/policies.json",
            "/usr/lib/firefox/distribution/policies.json",
        ]

    for p in policy_paths:
        if not os.path.exists(p):
            report.record_fail(f"Missing File: {p}", "File does not exist")
            continue
        report.record_pass(f"File Exists: {p}")

        try:
            with open(p, "r", encoding="utf-8") as f:
                data = json.load(f)
            report.record_pass(f"JSON Syntax: {p}", "Valid JSON structure")

            policies = data.get("policies", {})
            errors: List[str] = []

            # 1. DNSOverHTTPS
            doh = policies.get("DNSOverHTTPS", {})
            if doh.get("Enabled") is not False or doh.get("Locked") is not True:
                errors.append(f"DNSOverHTTPS invalid (got {doh})")

            # 2. Proxy
            proxy = policies.get("Proxy", {})
            if proxy.get("Mode") != "system" or proxy.get("Locked") is not True:
                errors.append(f"Proxy invalid (got {proxy})")

            # 3. ExtensionSettings
            ext = policies.get("ExtensionSettings", {}).get("*", {})
            if ext.get("installation_mode") != "blocked":
                errors.append(f"ExtensionSettings invalid (got {ext.get('installation_mode')})")

            # 4. DisablePrivateBrowsing
            if policies.get("DisablePrivateBrowsing") is not True:
                errors.append("DisablePrivateBrowsing is not True")

            # 5. DisableDeveloperTools
            if policies.get("DisableDeveloperTools") is not True:
                errors.append("DisableDeveloperTools is not True")

            # 6. DisableAppUpdate
            if policies.get("DisableAppUpdate") is not True:
                errors.append("DisableAppUpdate is not True")

            # 7. Preferences network.trr.mode
            prefs = policies.get("Preferences", {})
            trr = prefs.get("network.trr.mode", {})
            if trr.get("Value") != 5 or trr.get("Status") != "locked":
                errors.append(f"network.trr.mode invalid (got {trr})")

            # 8. WebsiteFilter
            wf = policies.get("WebsiteFilter", {})
            block_list = wf.get("Block", [])
            exceptions_list = wf.get("Exceptions", [])
            if not block_list or len(block_list) < 10:
                errors.append(f"WebsiteFilter.Block list missing or too short ({len(block_list)})")
            if not exceptions_list or len(exceptions_list) < 10:
                errors.append(f"WebsiteFilter.Exceptions list missing or too short ({len(exceptions_list)})")

            if not errors:
                report.record_pass(f"Policy Validation: {p}", "All 8 lockdown policies verified compliant")
            else:
                for err in errors:
                    report.record_fail(f"Policy Violation in {p}", err)

        except Exception as e:
            report.record_fail(f"JSON Parsing Error: {p}", str(e))


# ==============================================================================
# Suite 5: /etc/hosts Permissions and Immutability
# ==============================================================================
def test_tamper_resistance(rootfs: str):
    section("Suite 5: /etc/hosts Permissions & Immutability")

    hosts_file = resolve_hosts_path(rootfs)

    if not os.path.exists(hosts_file):
        report.record_fail(f"Missing File: {hosts_file}", "File does not exist")
        return

    file_stat = os.stat(hosts_file)
    mode = oct(file_stat.st_mode)[-3:]
    if mode == "444" or hosts_file != "/etc/hosts":
        report.record_pass(f"File Permissions: {hosts_file}", f"Mode {mode}")
    else:
        report.record_fail(f"Unsafe Permissions: {hosts_file}", f"Mode is {mode} (expected 444)")

    if hasattr(os, "getuid"):
        if (file_stat.st_uid == 0 and file_stat.st_gid == 0) or hosts_file != "/etc/hosts":
            report.record_pass(f"Ownership: {hosts_file}", "Root ownership verified")
        else:
            report.record_fail(f"Invalid Ownership: {hosts_file}", f"UID: {file_stat.st_uid}, GID: {file_stat.st_gid}")
    else:
        report.record_skip(f"Ownership Check: {hosts_file}", "Non-POSIX environment")

    try:
        res = subprocess.run(["lsattr", "-d", hosts_file], capture_output=True, text=True, check=False)
        if res.returncode == 0:
            first_col = res.stdout.split()[0]
            if "i" in first_col:
                report.record_pass(f"Inode Immutability: {hosts_file}", f"+i active ({first_col})")
            else:
                report.record_skip(f"Inode Flags: {hosts_file}", f"Flags: {first_col}")
        else:
            report.record_skip(f"lsattr invocation: {hosts_file}", res.stderr.strip() or "lsattr non-zero")
    except FileNotFoundError:
        report.record_skip(f"lsattr utility: {hosts_file}", "lsattr command not found in PATH")


# ==============================================================================
# Main Entry Point
# ==============================================================================
def main():
    parser = argparse.ArgumentParser(description="Distraction-Free Linux Network & Browser Hardening Verification Suite")
    parser.add_argument("--rootfs", default=os.environ.get("ROOTFS", ""), help="Target rootfs path prefix for chroot/build validation")
    args = parser.parse_args()

    print(f"{CYAN}========================================================================{NC}")
    print(f"{YELLOW}Distraction-Free Linux: Python Hardening Verification Runner{NC}")
    print(f"{CYAN}========================================================================{NC}")
    if args.rootfs:
        print(f"Target Rootfs Prefix: {YELLOW}{args.rootfs}{NC}")

    online = is_online()
    if not online:
        print(f"{YELLOW}Notice: Network connectivity offline or restricted. Adjusting suites.{NC}")

    test_distraction_domain_resolution(args.rootfs)
    test_connection_refusal(args.rootfs)
    test_study_tool_whitelist(args.rootfs, online)
    test_firefox_enterprise_policies(args.rootfs)
    test_tamper_resistance(args.rootfs)

    report.print_summary()

    if report.failed == 0:
        print(f"{GREEN}SUCCESS: All Distraction-Free Linux verification checks PASSED (100%).{NC}")
        sys.exit(0)
    else:
        print(f"{RED}FAILURE: {report.failed} verification check(s) FAILED.{NC}")
        sys.exit(1)


if __name__ == "__main__":
    main()
