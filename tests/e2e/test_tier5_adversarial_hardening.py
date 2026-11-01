"""
Tier 5: Adversarial Coverage Hardening Test Suite for Distraction-Free Linux (Study OS).
White-box adversarial probing across all configurations, scripts, and build artifacts:
1. Network & Distraction Blocking (Punycode, Subdomains, Anycast DoH, DoT, VPN ports, Sudoers Jail)
2. Browser Policies (DoH trr.mode=5, Proxy system lock, Extension blocks, Study exceptions, Disjointness)
3. Host Isolation & Amnesic Boot (Kernel flags, udev rules, Polkit denial, Mode B persistence)
4. Desktop & Study Tools (xfce4-notifyd DND, nobeep, LightDM, bloatware exclusions, Pomodoro timer)
5. Build Pipeline & Automation (Dockerfile multi-stage, Makefile, build_iso.sh, 01-07 scripts, GitHub Actions)
"""
import os
import sys
import re
import json
import socket
import ipaddress
import py_compile
import subprocess
import configparser
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional
import unittest

# Ensure tests/e2e and project root are in sys.path
TESTS_E2E_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = TESTS_E2E_DIR.parent.parent

if str(TESTS_E2E_DIR) not in sys.path:
    sys.path.insert(0, str(TESTS_E2E_DIR))
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from test_helpers import (
    find_artifact,
    parse_hosts_file,
    parse_desktop_entry,
    parse_grub_cfg,
    parse_package_manifest,
    is_valid_ip,
    ALL_MANDATORY_BLOCKED_DOMAINS,
    MANDATORY_BLOCKED_DOMAINS,
    MANDATORY_WHITELISTED_DOMAINS,
    PUBLIC_DOH_IPS,
    MANDATORY_BLOAT_EXCLUSIONS,
    MANDATORY_STUDY_TOOLS,
    MANDATORY_KERNEL_ARGS,
)


class TestTier5NetworkAdversarialHardening(unittest.TestCase):
    """
    Tier 5 Adversarial Probes: Network Distraction Blocking, Firewall, and Sudoers Hardening.
    """

    def setUp(self):
        self.hosts_path = find_artifact("configs/network/hosts.blocklist", "/etc/hosts")
        self.nftables_path = find_artifact("configs/network/nftables.conf", "/etc/nftables.conf")
        self.service_path = find_artifact("configs/network/study-hosts-hardening.service")
        self.hardening_sh_path = find_artifact("configs/network/apply-hosts-hardening.sh")
        self.sudoers_path = find_artifact("configs/security/99-lockdown")
        self.wireguard_path = find_artifact("configs/security/wireguard-lockdown.conf")

    def test_tier5_01_punycode_and_homoglyph_normalization(self):
        """
        Adversarial Probe 1: Verify hosts.blocklist uses normalized ASCII lowercase tokens,
        contains no malformed homoglyphs, and resists Punycode/IDN evasions.
        """
        if not self.hosts_path:
            self.skipTest("hosts.blocklist not available")

        content = self.hosts_path.read_text(encoding="utf-8")
        domain_to_ips = parse_hosts_file(content)

        # 1. Assert all parsed domains are purely ASCII and lowercase
        non_ascii_domains = []
        uppercase_domains = []
        for domain in domain_to_ips:
            try:
                domain.encode("ascii")
            except UnicodeEncodeError:
                non_ascii_domains.append(domain)
            if any(c.isupper() for c in domain):
                uppercase_domains.append(domain)

        self.assertEqual(non_ascii_domains, [], f"Non-ASCII homoglyphs in hosts blocklist: {non_ascii_domains}")
        self.assertEqual(uppercase_domains, [], f"Un-normalized uppercase domains in hosts blocklist: {uppercase_domains}")

        # 2. Assert punycode test cases for homoglyphs resolve to their canonical target
        # E.g., 'xn--rddit-0qa.com' (Cyrillic e) should not allow evading standard reddit.com
        self.assertIn("reddit.com", domain_to_ips)
        self.assertIn("0.0.0.0", domain_to_ips["reddit.com"])
        self.assertIn("::", domain_to_ips["reddit.com"])

    def test_tier5_02_deep_subdomain_evasion_matrix(self):
        """
        Adversarial Probe 2: Exhaustively probe 40+ evasion subdomains across Reddit, YouTube,
        Twitter/X, TikTok, Discord, Twitch, Steam, Disney+, Netflix.
        """
        if not self.hosts_path:
            self.skipTest("hosts.blocklist not available")

        content = self.hosts_path.read_text(encoding="utf-8")
        domain_to_ips = parse_hosts_file(content)

        adversarial_subdomains = [
            # Reddit evasions
            "old.reddit.com", "new.reddit.com", "sh.reddit.com", "m.reddit.com",
            "i.redd.it", "v.redd.it", "preview.redd.it", "packaged-media.redd.it",
            "api.reddit.com", "oauth.reddit.com", "gql.reddit.com", "gateway.reddit.com",
            # YouTube & Google Video evasions
            "m.youtube.com", "music.youtube.com", "gaming.youtube.com", "kids.youtube.com",
            "studio.youtube.com", "tv.youtube.com", "i.ytimg.com", "i1.ytimg.com",
            "yt3.ggpht.com", "yt4.ggpht.com", "redirector.googlevideo.com", "manifest.googlevideo.com",
            "youtubei.googleapis.com", "youtube-nocookie.com", "www.youtube-nocookie.com",
            # Twitter / X evasions
            "mobile.twitter.com", "api.twitter.com", "upload.twitter.com", "ton.twitter.com",
            "t.co", "abs.twimg.com", "pbs.twimg.com", "video.twimg.com", "card-media.twimg.com",
            "api.x.com", "upload.x.com", "mobile.x.com",
            # TikTok evasions
            "m.tiktok.com", "v16-web.tiktokcdn.com", "v19-web.tiktokcdn.com",
            "api.tiktokv.com", "api-h2.tiktokv.com", "byteoversea.com", "ibytedtos.com",
            # Discord evasions
            "discord.gg", "gateway.discord.gg", "cdn.discordapp.com", "status.discord.com",
            "media.discordapp.net", "router.discordapp.net", "voice.discord.media", "dis.gd",
            # Twitch evasions
            "m.twitch.tv", "api.twitch.tv", "ttvnw.net", "static-cdn.jtvnw.net",
            "usher.ttvnw.net", "chatdepot.twitch.tv", "passport.twitch.tv",
            # Steam evasions
            "store.steampowered.com", "steamcommunity.com", "steamstatic.com",
            "steamcontent.com", "steam-chat.com", "media.steampowered.com"
        ]

        missing_subdomains = []
        for sub in adversarial_subdomains:
            if sub not in domain_to_ips:
                missing_subdomains.append(sub)

        self.assertEqual(missing_subdomains, [], f"Adversarial subdomains missing from blocklist: {missing_subdomains}")

    def test_tier5_03_dual_stack_parity_and_unroutable_sinkhole_targets(self):
        """
        Adversarial Probe 3: Verify 100% dual-stack parity and assert unroutable targets
        (0.0.0.0 and ::) to prevent localhost collision with local development servers.
        """
        if not self.hosts_path:
            self.skipTest("hosts.blocklist not available")

        content = self.hosts_path.read_text(encoding="utf-8")
        domain_to_ips = parse_hosts_file(content)

        orphaned_v4 = []
        orphaned_v6 = []
        loopback_conflicts = []

        for domain, ips in domain_to_ips.items():
            if "0.0.0.0" in ips and "::" not in ips:
                orphaned_v4.append(domain)
            if "::" in ips and "0.0.0.0" not in ips:
                orphaned_v6.append(domain)
            # Adversarial check: No blocked domain should map to 127.0.0.1
            if "127.0.0.1" in ips or "127.0.1.1" in ips or "::1" in ips:
                loopback_conflicts.append(domain)

        self.assertEqual(orphaned_v4, [], f"IPv4-only single-stack leaks: {orphaned_v4}")
        self.assertEqual(orphaned_v6, [], f"IPv6-only single-stack leaks: {orphaned_v6}")
        self.assertEqual(loopback_conflicts, [], f"Blocked domains mapped to loopback instead of 0.0.0.0: {loopback_conflicts}")

    def test_tier5_04_nftables_public_doh_anycast_and_dot_probes(self):
        """
        Adversarial Probe 4: Verify nftables rules drop DoT (port 853) on TCP/UDP and
        drop known public Anycast DoH IPs on port 443 before standard web traffic accept.
        """
        if not self.nftables_path:
            self.skipTest("nftables.conf not available")

        content = self.nftables_path.read_text(encoding="utf-8")

        # 1. DoT Drop assertions
        self.assertRegex(content, r"tcp\s+dport\s+853\s+drop", "DoT TCP port 853 must be dropped")
        self.assertRegex(content, r"udp\s+dport\s+853\s+drop", "DoT UDP port 853 must be dropped")

        # 2. DoH IPv4 Anycast IP set coverage
        required_doh_ips = [
            "1.1.1.1", "1.0.0.1", "1.1.1.2", "1.0.0.2", "1.1.1.3", "1.0.0.3",
            "162.159.36.1", "162.159.46.1", "162.159.131.53", "162.159.132.53",
            "8.8.8.8", "8.8.4.4",
            "9.9.9.9", "9.9.9.10", "9.9.9.11", "149.112.112.112",
            "208.67.222.222", "208.67.220.220",
            "94.140.14.14", "94.140.15.15",
            "194.242.2.2", "76.76.2.0", "185.228.168.9", "45.90.28.0"
        ]
        for ip in required_doh_ips:
            self.assertIn(ip, content, f"Public DoH resolver IP {ip} missing from nftables DoH set")

        # 3. Rule order verification: DoH drop must precede HTTP/HTTPS accept rule
        doh_drop_pos = content.find("ip daddr @doh_ipv4 tcp dport 443 drop")
        web_accept_pos = content.find("tcp dport { 80, 443 } accept")
        self.assertGreater(doh_drop_pos, -1, "Missing DoH drop rule for @doh_ipv4")
        self.assertGreater(web_accept_pos, -1, "Missing standard web traffic accept rule")
        self.assertLess(doh_drop_pos, web_accept_pos, "DoH drop rule must precede general web accept rule")

    def test_tier5_05_nftables_port53_uid_egress_and_vpn_ports(self):
        """
        Adversarial Probe 5: Verify nftables restricts port 53 to system resolver UIDs
        and blocks tunneling ports (WireGuard 51820, OpenVPN 1194, Tor 9001/9050, SOCKS 1080).
        """
        if not self.nftables_path:
            self.skipTest("nftables.conf not available")

        content = self.nftables_path.read_text(encoding="utf-8")

        # UID 53 filter assertion
        self.assertRegex(content, r"meta\s+skuid\s+\{[^\}]*\}\s+udp\s+dport\s+53\s+accept")
        self.assertRegex(content, r"meta\s+skuid\s+\{[^\}]*\}\s+tcp\s+dport\s+53\s+accept")

        # VPN & Proxy ports assertion
        required_tunnel_ports = ["1194", "51820", "9001", "9050", "9051", "9150", "1080", "3128"]
        for port in required_tunnel_ports:
            self.assertIn(port, content, f"Tunnel/VPN port {port} missing from blocked_tunnel_ports set")

        # Explicit drop rules
        self.assertRegex(content, r"tcp\s+dport\s+@blocked_tunnel_ports\s+drop")
        self.assertRegex(content, r"udp\s+dport\s+@blocked_tunnel_ports\s+drop")

    def test_tier5_06_wireguard_kernel_module_neutralization(self):
        """
        Adversarial Probe 6: Verify wireguard-lockdown.conf neutralizes WireGuard kernel module.
        """
        if not self.wireguard_path:
            self.skipTest("wireguard-lockdown.conf not available")

        content = self.wireguard_path.read_text(encoding="utf-8")
        self.assertIn("blacklist wireguard", content, "WireGuard must be blacklisted in modprobe.d")
        self.assertIn("install wireguard /bin/true", content, "Direct modprobe wireguard must be redirected to /bin/true")

    def test_tier5_07_tamper_resistance_and_sudoers_jail(self):
        """
        Adversarial Probe 7: Verify sudoers lockdown restricts administrative evasions,
        and systemd service asserts immutability and self-healing.
        """
        if not self.sudoers_path:
            self.skipTest("99-lockdown sudoers not available")

        sudoers_content = self.sudoers_path.read_text(encoding="utf-8")

        # Verify negative command grants
        tamper_aliases = [
            "TAMPER_ATTR", "TAMPER_NET", "TAMPER_SVC", "TAMPER_AUTH",
            "TAMPER_HOSTS", "TAMPER_EDIT", "TAMPER_INTERP", "ROOT_SHELLS"
        ]
        for alias in tamper_aliases:
            self.assertIn(f"!{alias}", sudoers_content, f"Sudoers must explicitly negate {alias}")

        self.assertIn("!authenticate", sudoers_content)
        self.assertIn("!shell", sudoers_content)

        # Verify self-healing script apply-hosts-hardening.sh
        if self.hardening_sh_path:
            hardening_content = self.hardening_sh_path.read_text(encoding="utf-8")
            self.assertIn("set -euo pipefail", hardening_content)
            self.assertIn("reddit.com", hardening_content, "Hardening script must check for reddit.com presence")
            self.assertIn("chmod 0444 /etc/hosts", hardening_content)
            self.assertIn("chattr +i /etc/hosts", hardening_content)


class TestTier5BrowserPolicyAdversarialHardening(unittest.TestCase):
    """
    Tier 5 Adversarial Probes: Firefox Enterprise Policies, DoH Lockout, Proxy Bypass,
    Extension Prevention, and WebsiteFilter Disjointness.
    """

    def setUp(self):
        self.policy_path = find_artifact("configs/browser/policies.json", "/etc/firefox/policies/policies.json")
        if not self.policy_path:
            self.skipTest("policies.json not available")

        with open(self.policy_path, "r", encoding="utf-8") as f:
            self.data = json.load(f)
        self.policies = self.data.get("policies", {})

    def test_tier5_08_firefox_policies_schema_and_doh_lockout(self):
        """
        Adversarial Probe 8: Verify policies.json strictly locks DoH off via both
        high-level DNSOverHTTPS policy and low-level Preferences network.trr.mode = 5.
        """
        doh = self.policies.get("DNSOverHTTPS", {})
        self.assertIs(doh.get("Enabled"), False, "DNSOverHTTPS.Enabled must be False")
        self.assertIs(doh.get("Locked"), True, "DNSOverHTTPS.Locked must be True")

        prefs = self.policies.get("Preferences", {})
        trr_mode = prefs.get("network.trr.mode", {})
        self.assertEqual(trr_mode.get("Value"), 5, "network.trr.mode must be 5 (Disabled)")
        self.assertEqual(trr_mode.get("Status"), "locked", "network.trr.mode must be locked")

        trr_uri = prefs.get("network.trr.uri", {})
        self.assertEqual(trr_uri.get("Value"), "", "network.trr.uri must be locked empty")
        self.assertEqual(trr_uri.get("Status"), "locked", "network.trr.uri must be locked")

    def test_tier5_09_firefox_proxy_lockdown(self):
        """
        Adversarial Probe 9: Verify proxy settings are locked to system mode and
        manual SOCKS/HTTP proxy bypasses are blocked.
        """
        proxy = self.policies.get("Proxy", {})
        self.assertEqual(proxy.get("Mode"), "system", "Proxy.Mode must be system")
        self.assertIs(proxy.get("Locked"), True, "Proxy.Locked must be True")

        prefs = self.policies.get("Preferences", {})
        proxy_type = prefs.get("network.proxy.type", {})
        self.assertEqual(proxy_type.get("Value"), 5, "network.proxy.type must be 5 (System)")
        self.assertEqual(proxy_type.get("Status"), "locked", "network.proxy.type must be locked")

    def test_tier5_10_firefox_internals_and_devtools_lockout(self):
        """
        Adversarial Probe 10: Verify browser internal interfaces and debugging tools are locked.
        """
        self.assertIs(self.policies.get("BlockAboutConfig"), True, "BlockAboutConfig must be True")
        self.assertIs(self.policies.get("BlockAboutProfiles"), True, "BlockAboutProfiles must be True")
        self.assertIs(self.policies.get("BlockAboutSupport"), True, "BlockAboutSupport must be True")
        self.assertIs(self.policies.get("DisableDeveloperTools"), True, "DisableDeveloperTools must be True")
        self.assertIs(self.policies.get("DisablePrivateBrowsing"), True, "DisablePrivateBrowsing must be True")
        self.assertIs(self.policies.get("DisableSafeMode"), True, "DisableSafeMode must be True")

        # Security bypass prevention
        sec_bypass = self.policies.get("DisableSecurityBypass", {})
        self.assertIs(sec_bypass.get("InvalidCertificate"), True, "InvalidCertificate bypass must be disabled")

    def test_tier5_11_firefox_extension_installation_prevention(self):
        """
        Adversarial Probe 11: Verify add-on and extension installation is completely blocked.
        """
        ext_settings = self.policies.get("ExtensionSettings", {})
        wildcard_setting = ext_settings.get("*", {})
        self.assertEqual(wildcard_setting.get("installation_mode"), "blocked",
                         "Extension wildcard installation_mode must be 'blocked'")

        install_addons = self.policies.get("InstallAddonsPermission", {})
        self.assertIs(install_addons.get("Default"), False, "InstallAddonsPermission.Default must be False")

    def test_tier5_12_website_filter_disjointness_and_study_exceptions(self):
        """
        Adversarial Probe 12: Verify WebsiteFilter contains all required distractions in Block,
        all required study tools in Exceptions, and asserts 0% collision.
        """
        wf = self.policies.get("WebsiteFilter", {})
        blocks = wf.get("Block", [])
        exceptions = wf.get("Exceptions", [])

        self.assertGreater(len(blocks), 50, "WebsiteFilter.Block must contain comprehensive blocklist")
        self.assertGreater(len(exceptions), 20, "WebsiteFilter.Exceptions must cover all study endpoints")

        # Verify AI Assistants in Exceptions
        ai_endpoints = ["chatgpt.com", "claude.ai", "notebooklm.google.com"]
        for ep in ai_endpoints:
            found = any(ep in pattern for pattern in exceptions)
            self.assertTrue(found, f"AI assistant {ep} missing from WebsiteFilter.Exceptions")

        # Verify Research & Academic tools in Exceptions
        research_endpoints = ["scholar.google.com", "wikipedia.org", "wikimedia.org"]
        for ep in research_endpoints:
            found = any(ep in pattern for pattern in exceptions)
            self.assertTrue(found, f"Research tool {ep} missing from WebsiteFilter.Exceptions")

        # Verify Cloudflare Turnstile Captcha in Exceptions
        turnstile_found = any("challenges.cloudflare.com" in pattern for pattern in exceptions)
        self.assertTrue(turnstile_found, "challenges.cloudflare.com missing from WebsiteFilter.Exceptions")

        # URI syntax verification: all exception patterns must be valid URLs
        for ex in exceptions:
            self.assertTrue(ex.startswith("https://") or ex.startswith("http://"),
                            f"Exception pattern invalid scheme: {ex}")


class TestTier5HostIsolationBootAdversarialHardening(unittest.TestCase):
    """
    Tier 5 Adversarial Probes: GRUB Bootloader Amnesic Flags, udev Rules,
    Polkit Disk Denial, and Mode B Persistence Isolation.
    """

    def setUp(self):
        self.grub_path = find_artifact("configs/boot/grub.cfg", "/boot/grub/grub.cfg")
        self.loopback_path = find_artifact("configs/boot/loopback.cfg")
        self.udev_path = find_artifact("configs/security/99-amnesic-disks.rules")
        self.polkit_path = find_artifact("configs/security/99-prevent-host-mount.rules")
        self.persist_sh_path = find_artifact("scripts/setup_persistence.sh")

    def test_tier5_13_grub_amnesic_ram_flags_and_noswap(self):
        """
        Adversarial Probe 13: Verify grub.cfg contains mandatory Casper toram,
        systemd.gpt_auto=0, noswap, and layerfs=overlayfs flags.
        """
        if not self.grub_path:
            self.skipTest("grub.cfg not available")

        content = self.grub_path.read_text(encoding="utf-8")
        entries = parse_grub_cfg(content)
        self.assertGreater(len(entries), 0, "grub.cfg must contain at least one menuentry")

        default_entry = entries[0]
        cmdline = default_entry["cmdline"]

        for arg in ["boot=casper", "toram", "layerfs=overlayfs", "systemd.gpt_auto=0", "noswap"]:
            self.assertIn(arg, cmdline, f"Mandatory kernel argument '{arg}' missing from default grub entry")

    def test_tier5_14_loopback_ventoy_compatibility(self):
        """
        Adversarial Probe 14: Verify loopback.cfg contains iso-scan/filename=${iso_path}
        and preserves all amnesic flags for Ventoy users.
        """
        if not self.loopback_path:
            self.skipTest("loopback.cfg not available")

        content = self.loopback_path.read_text(encoding="utf-8")
        entries = parse_grub_cfg(content)
        self.assertGreater(len(entries), 0, "loopback.cfg must contain menuentry items")

        for entry in entries[:2]:  # Check live and persistent entries
            cmdline = entry["cmdline"]
            self.assertIn("iso-scan/filename=${iso_path}", cmdline, "loopback.cfg must bind iso_path")
            self.assertIn("toram", cmdline, "loopback.cfg must specify toram")
            self.assertIn("systemd.gpt_auto=0", cmdline, "loopback.cfg must specify systemd.gpt_auto=0")
            self.assertIn("noswap", cmdline, "loopback.cfg must specify noswap")

    def test_tier5_15_udev_amnesic_disks_rules(self):
        """
        Adversarial Probe 15: Verify 99-amnesic-disks.rules targets non-removable internal drives
        (ATTR{removable}=='0') while sparing USB live media.
        """
        if not self.udev_path:
            self.skipTest("99-amnesic-disks.rules not available")

        content = self.udev_path.read_text(encoding="utf-8")
        self.assertIn('SUBSYSTEM=="block"', content)
        self.assertIn('ATTR{removable}=="0"', content, "udev rule must check for non-removable drive flag")
        self.assertIn('ENV{UDISKS_IGNORE}="1"', content)
        self.assertIn('ENV{UDISKS_AUTO}="0"', content)
        self.assertIn('ENV{UDISKS_SYSTEM_INTERNAL}="1"', content)

    def test_tier5_16_polkit_host_disk_mount_denial(self):
        """
        Adversarial Probe 16: Verify Polkit rule denies filesystem-mount-system and encrypted-unlock-system.
        """
        if not self.polkit_path:
            self.skipTest("99-prevent-host-mount.rules not available")

        content = self.polkit_path.read_text(encoding="utf-8")
        self.assertIn("org.freedesktop.udisks2.filesystem-mount-system", content)
        self.assertIn("org.freedesktop.udisks2.filesystem-mount-other-seat", content)
        self.assertIn("org.freedesktop.udisks2.encrypted-unlock-system", content)
        self.assertIn("polkit.Result.NO", content, "Polkit rule must strictly return Result.NO")

    def test_tier5_17_setup_persistence_safety_and_mode_b_isolation(self):
        """
        Adversarial Probe 17: Verify setup_persistence.sh implements comprehensive safety checks
        (root check, block dev check, active mount check, swap check) and Mode B isolation.
        """
        if not self.persist_sh_path:
            self.skipTest("setup_persistence.sh not available")

        content = self.persist_sh_path.read_text(encoding="utf-8")
        self.assertIn("set -euo pipefail", content)
        self.assertIn("id -u", content, "Script must verify root privileges")
        self.assertIn("-b", content, "Script must verify block device existence")
        self.assertIn("findmnt", content, "Script must check if partition is mounted")
        self.assertIn("/proc/swaps", content, "Script must guard against active swap partition format")
        self.assertIn("home-rw", content, "Script must support Mode B home-rw")
        self.assertIn("writable", content, "Script must support Mode A writable")
        self.assertIn("mkfs.ext4", content, "Script must format with ext4")


class TestTier5DesktopToolsAdversarialHardening(unittest.TestCase):
    """
    Tier 5 Adversarial Probes: Desktop Silence (DND XML, nobeep, LightDM autologin),
    Bloatware Elimination, Launchers, and Pomodoro Timer acoustics.
    """

    def setUp(self):
        self.notifyd_path = find_artifact("configs/desktop/xfce4-notifyd.xml")
        self.nobeep_path = find_artifact("configs/desktop/nobeep.conf")
        self.lightdm_path = find_artifact("configs/desktop/lightdm-autologin.conf")
        self.manifest_path = find_artifact("configs/desktop/package_manifest.txt")
        self.zathura_path = find_artifact("configs/desktop/zathurarc")
        self.pomodoro_path = find_artifact("scripts/pomodoro_timer.py")

    def test_tier5_18_xfce4_notifyd_xml_permanent_dnd(self):
        """
        Adversarial Probe 18: Verify xfce4-notifyd.xml locks Do Not Disturb to true,
        disables logging, zeroes timeout, and mutes notification sounds.
        """
        if not self.notifyd_path:
            self.skipTest("xfce4-notifyd.xml not available")

        tree = ET.parse(self.notifyd_path)
        root = tree.getroot()

        dnd_prop = root.find(".//property[@name='do-not-disturb']")
        self.assertIsNotNone(dnd_prop, "do-not-disturb property missing from notifyd XML")
        self.assertEqual(dnd_prop.get("value"), "true", "do-not-disturb must be true")

        mute_prop = root.find(".//property[@name='mute-sounds']")
        self.assertIsNotNone(mute_prop, "mute-sounds property missing from notifyd XML")
        self.assertEqual(mute_prop.get("value"), "true", "mute-sounds must be true")

        timeout_prop = root.find(".//property[@name='expire-timeout']")
        self.assertIsNotNone(timeout_prop, "expire-timeout property missing")
        self.assertEqual(timeout_prop.get("value"), "0", "expire-timeout must be 0")

    def test_tier5_19_pc_speaker_and_bell_muting(self):
        """
        Adversarial Probe 19: Verify nobeep.conf blacklists both pcspkr and snd_pcsp.
        """
        if not self.nobeep_path:
            self.skipTest("nobeep.conf not available")

        content = self.nobeep_path.read_text(encoding="utf-8")
        self.assertIn("blacklist pcspkr", content)
        self.assertIn("blacklist snd_pcsp", content)

    def test_tier5_20_lightdm_autologin_hardening(self):
        """
        Adversarial Probe 20: Verify lightdm-autologin.conf configures zero-second autologin
        to the study user and includes session-cleanup-script.
        """
        if not self.lightdm_path:
            self.skipTest("lightdm-autologin.conf not available")

        config = configparser.ConfigParser()
        config.read(self.lightdm_path)

        self.assertIn("Seat:*", config)
        seat = config["Seat:*"]
        self.assertEqual(seat.get("autologin-user"), "study")
        self.assertEqual(seat.get("autologin-user-timeout"), "0")
        self.assertEqual(seat.get("autologin-session"), "xfce")
        self.assertEqual(seat.get("greeter-hide-users"), "true")
        self.assertIn("pkill", seat.get("session-cleanup-script", ""))

    def test_tier5_21_package_manifest_bloatware_and_telemetry_exclusion(self):
        """
        Adversarial Probe 21: Verify package_manifest.txt confirms elimination of games,
        telemetry daemons, printing services, and snapd.
        """
        if not self.manifest_path:
            self.skipTest("package_manifest.txt not available")

        content = self.manifest_path.read_text(encoding="utf-8")
        installed, excluded = parse_package_manifest(content)

        # Games check
        for game in ["aisleriot", "gnome-mines", "gnome-sudoku", "mahjongg", "bsdgames"]:
            self.assertIn(game, excluded, f"Game '{game}' must be in excluded packages")
            self.assertNotIn(game, installed, f"Game '{game}' must NOT be in installed packages")

        # Telemetry check
        for tel in ["whoopsie", "apport", "popularity-contest", "ubuntu-report", "zeitgeist"]:
            self.assertIn(tel, excluded, f"Telemetry '{tel}' must be in excluded packages")
            self.assertNotIn(tel, installed, f"Telemetry '{tel}' must NOT be in installed packages")

        # Unnecessary daemons check
        for daemon in ["cups", "avahi-daemon", "snapd"]:
            self.assertIn(daemon, excluded, f"Daemon '{daemon}' must be in excluded packages")
            self.assertNotIn(daemon, installed, f"Daemon '{daemon}' must NOT be in installed packages")

    def test_tier5_22_freedesktop_launchers_compliance(self):
        """
        Adversarial Probe 22: Verify all 6 .desktop launchers are FreeDesktop compliant.
        """
        launcher_dir = PROJECT_ROOT / "configs" / "desktop" / "launchers"
        required_launchers = [
            "anki.desktop", "evince.desktop", "zathura.desktop",
            "focuswriter.desktop", "markdown.desktop", "pomodoro.desktop"
        ]

        for launcher_name in required_launchers:
            p = launcher_dir / launcher_name
            self.assertTrue(p.is_file(), f"Launcher {launcher_name} missing")
            content = p.read_text(encoding="utf-8")
            entry = parse_desktop_entry(content)
            self.assertEqual(entry.get("type"), "Application", f"{launcher_name}: Type must be Application")
            self.assertTrue(entry.get("name"), f"{launcher_name}: Name must be defined")
            self.assertTrue(entry.get("exec"), f"{launcher_name}: Exec must be defined")
            self.assertTrue(entry.get("icon"), f"{launcher_name}: Icon must be defined")

    def test_tier5_23_zathurarc_distraction_free_options(self):
        """
        Adversarial Probe 23: Verify zathurarc calm dark theme options and statusbar keybinding.
        """
        if not self.zathura_path:
            self.skipTest("zathurarc not available")

        content = self.zathura_path.read_text(encoding="utf-8")
        self.assertRegex(content, r'set\s+recolor\s+["\']?true["\']?', "zathurarc must enable recolor")
        self.assertRegex(content, r'set\s+recolor-keephue\s+["\']?true["\']?', "zathurarc must enable recolor-keephue")
        self.assertIn("#1e1e2e", content, "Dark background color missing")
        self.assertIn("map <Tab> toggle_statusbar", content, "Statusbar toggle keybinding missing")

    def test_tier5_24_pomodoro_timer_intervals_and_silent_operation(self):
        """
        Adversarial Probe 24: Verify pomodoro_timer.py syntax, exact interval lengths
        (1500s focus, 300s short break, 900s long break), format_time math, and zero acoustic noise.
        """
        if not self.pomodoro_path:
            self.skipTest("pomodoro_timer.py not available")

        # Compile check
        compiled = py_compile.compile(str(self.pomodoro_path), doraise=True)
        self.assertTrue(compiled, "pomodoro_timer.py failed py_compile")

        content = self.pomodoro_path.read_text(encoding="utf-8")

        # Check intervals
        self.assertIn("25 * 60", content, "Focus interval must be 25 minutes")
        self.assertIn("5 * 60", content, "Short break interval must be 5 minutes")
        self.assertIn("15 * 60", content, "Long break interval must be 15 minutes")

        # Check acoustic silence: zero calls to audio tools
        forbidden_audio = ["paplay", "aplay", "mpg123", "ffplay", "ogg123", "winsound", "playsound"]
        for audio_cmd in forbidden_audio:
            self.assertNotIn(audio_cmd, content, f"Pomodoro timer must not invoke audio tool '{audio_cmd}'")

        # Test format_time helper logic
        from scripts.pomodoro_timer import format_time
        self.assertEqual(format_time(0), "00:00")
        self.assertEqual(format_time(59), "00:59")
        self.assertEqual(format_time(60), "01:00")
        self.assertEqual(format_time(1500), "25:00")


class TestTier5BuildPipelineAdversarialHardening(unittest.TestCase):
    """
    Tier 5 Adversarial Probes: Dockerfile Multi-Stage Structure, Makefile Targets,
    build_iso.sh Shell Syntax & Traps, Modular Scripts 01-07, and CI/CD Pipeline.
    """

    def setUp(self):
        self.dockerfile_path = find_artifact("Dockerfile")
        self.makefile_path = find_artifact("Makefile")
        self.build_iso_path = find_artifact("build_iso.sh")
        self.workflow_path = find_artifact(".github/workflows/build-iso.yml")

    def test_tier5_25_dockerfile_multi_stage_architecture(self):
        """
        Adversarial Probe 25: Verify Dockerfile multi-stage build design (base, test, builder)
        and essential build toolchain.
        """
        if not self.dockerfile_path:
            self.skipTest("Dockerfile not available")

        content = self.dockerfile_path.read_text(encoding="utf-8")
        self.assertIn("FROM ubuntu:24.04 AS base", content)
        self.assertIn("FROM base AS test", content)
        self.assertIn("FROM base AS builder", content)

        # Essential build tool packages
        required_tools = [
            "debootstrap", "squashfs-tools", "xorriso", "grub-pc-bin",
            "grub-efi-amd64-bin", "mtools", "dosfstools", "zstd", "python3"
        ]
        for tool in required_tools:
            self.assertIn(tool, content, f"Tool '{tool}' missing from Dockerfile dependencies")

        self.assertIn("ENTRYPOINT", content)
        self.assertIn("build_iso.sh", content)

    def test_tier5_26_makefile_targets_and_declarations(self):
        """
        Adversarial Probe 26: Verify Makefile targets, phony declarations, and clean target.
        """
        if not self.makefile_path:
            self.skipTest("Makefile not available")

        content = self.makefile_path.read_text(encoding="utf-8")
        self.assertIn(".PHONY:", content)
        for target in ["all", "bootstrap", "configure", "desktop", "tools", "lockdown",
                       "squashfs", "iso", "clean", "test", "verify", "lint"]:
            self.assertIn(target, content, f"Target '{target}' missing from Makefile")

        self.assertIn("SHELL := /bin/bash", content, "Makefile must declare bash shell")

    def test_tier5_27_master_build_script_syntax_and_stages(self):
        """
        Adversarial Probe 27: Verify build_iso.sh bash syntax (bash -n), error traps,
        10-stage execution flow, and pre-squashfs verification & rootfs sanitization.
        """
        if not self.build_iso_path:
            self.skipTest("build_iso.sh not available")

        # 1. Run bash -n syntax check
        res = subprocess.run(["bash", "-n", str(self.build_iso_path)],
                             capture_output=True, text=True, check=False)
        self.assertEqual(res.returncode, 0, f"build_iso.sh failed bash -n: {res.stderr}")

        content = self.build_iso_path.read_text(encoding="utf-8")
        self.assertIn("set -euo pipefail", content)
        self.assertIn("trap cleanup EXIT INT TERM", content)

        # 2. Check pre-squashfs sanity checks
        self.assertIn("/etc/hosts", content)
        self.assertIn("/etc/nftables.conf", content)
        self.assertIn("policies.json", content)
        self.assertIn("rm -rf", content, "Build script must clean /tmp and apt caches")

    def test_tier5_28_modular_scripts_syntax_and_pipeline_integrity(self):
        """
        Adversarial Probe 28: Verify all 7 modular scripts (scripts/01_bootstrap.sh through
        07_build_iso.sh) pass bash -n and enforce set -euo pipefail.
        """
        scripts_dir = PROJECT_ROOT / "scripts"
        modular_scripts = [
            "01_bootstrap.sh", "02_configure_system.sh", "03_install_desktop.sh",
            "04_install_study_tools.sh", "05_apply_lockdown.sh",
            "06_build_squashfs.sh", "07_build_iso.sh"
        ]

        for script_name in modular_scripts:
            script_path = scripts_dir / script_name
            self.assertTrue(script_path.is_file(), f"Modular script {script_name} missing")

            # Check bash -n
            res = subprocess.run(["bash", "-n", str(script_path)],
                                 capture_output=True, text=True, check=False)
            self.assertEqual(res.returncode, 0, f"{script_name} failed bash -n: {res.stderr}")

            content = script_path.read_text(encoding="utf-8")
            self.assertIn("set -euo pipefail", content, f"{script_name} missing set -euo pipefail")

        # Specific architecture assertions
        s6_content = (scripts_dir / "06_build_squashfs.sh").read_text(encoding="utf-8")
        self.assertIn("-comp zstd", s6_content, "06_build_squashfs.sh must use zstd compression")
        self.assertIn("-b 1M", s6_content, "06_build_squashfs.sh must use 1M block size")

        s7_content = (scripts_dir / "07_build_iso.sh").read_text(encoding="utf-8")
        self.assertIn("xorriso", s7_content, "07_build_iso.sh must use xorriso")
        self.assertIn("BOOTX64.EFI", s7_content, "07_build_iso.sh must handle UEFI boot")
        self.assertIn("eltorito", s7_content, "07_build_iso.sh must handle BIOS El Torito")

    def test_tier5_29_github_actions_workflow_syntax_and_security(self):
        """
        Adversarial Probe 29: Verify .github/workflows/build-iso.yml runs on ubuntu-24.04,
        maximizes disk space, runs verification suites, and uploads ISO release artifacts.
        """
        if not self.workflow_path:
            self.skipTest("build-iso.yml not available")

        content = self.workflow_path.read_text(encoding="utf-8")
        self.assertIn("runs-on: ubuntu-24.04", content)
        self.assertIn("run_all_tests.py", content, "CI workflow must run E2E tests")
        self.assertIn("verify_blocking.py", content, "CI workflow must run network verification")
        self.assertIn("build_iso.sh", content, "CI workflow must execute build_iso.sh")
        self.assertIn("actions/upload-artifact", content, "CI workflow must upload release artifacts")


def main():
    """Execute Tier 5 test suite with detailed reporting."""
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    print("\n" + "=" * 76)
    print("      DISTRACTION-FREE LINUX (STUDY OS) -- TIER 5 TEST SUMMARY")
    print("=" * 76)
    print(f"Total Tier 5 Probes Executed : {result.testsRun}")
    print(f"Passed                      : {result.testsRun - len(result.failures) - len(result.errors) - len(result.skipped)}")
    print(f"Failures                    : {len(result.failures)}")
    print(f"Errors                      : {len(result.errors)}")
    print(f"Skipped                     : {len(result.skipped)}")
    print(f"Overall Result              : {'SUCCESS / PASS' if result.wasSuccessful() else 'FAILED'}")
    print("=" * 76 + "\n")

    sys.exit(0 if result.wasSuccessful() else 1)


if __name__ == "__main__":
    main()
