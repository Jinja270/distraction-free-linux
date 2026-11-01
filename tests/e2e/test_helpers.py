"""
Shared Test Helpers, Verification Oracles, and Parsers for DFL E2E Test Suite.
Used by all test modules in tests/e2e/.
"""
import os
import sys
import re
import json
import ipaddress
import configparser
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Optional, Dict, List, Set, Tuple

# Project root is two levels up from tests/e2e/
TESTS_E2E_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = TESTS_E2E_DIR.parent.parent

# Reference Domain Dictionaries derived from ORIGINAL_REQUEST.md & PROJECT.md
MANDATORY_BLOCKED_DOMAINS = {
    "social": [
        "reddit.com", "www.reddit.com", "old.reddit.com",
        "twitter.com", "www.twitter.com", "x.com", "www.x.com",
        "instagram.com", "www.instagram.com",
        "tiktok.com", "www.tiktok.com",
        "facebook.com", "www.facebook.com", "m.facebook.com",
    ],
    "video_streaming": [
        "youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be",
        "twitch.tv", "www.twitch.tv",
        "netflix.com", "www.netflix.com",
        "disneyplus.com", "www.disneyplus.com",
        "hulu.com", "www.hulu.com",
        "primevideo.com", "www.primevideo.com",
    ],
    "gaming_and_distraction": [
        "discord.com", "www.discord.com",
        "steampowered.com", "store.steampowered.com",
        "epicgames.com", "www.epicgames.com",
        "roblox.com", "www.roblox.com",
        "chess.com", "www.chess.com",
    ]
}

ALL_MANDATORY_BLOCKED_DOMAINS = [
    dom for group in MANDATORY_BLOCKED_DOMAINS.values() for dom in group
]

MANDATORY_WHITELISTED_DOMAINS = [
    "chatgpt.com",
    "oaistatic.com",
    "oaiusercontent.com",
    "claude.ai",
    "anthropic.com",
    "assets.claude.ai",
    "notebooklm.google.com",
    "wikipedia.org",
    "wikimedia.org",
    "upload.wikimedia.org",
    "scholar.google.com",
    "challenges.cloudflare.com",  # Turnstile captcha
]

# Public DoH Anycast Endpoints to be blocked by firewall
PUBLIC_DOH_IPS = [
    "1.1.1.1", "1.0.0.1",        # Cloudflare
    "8.8.8.8", "8.8.4.4",        # Google
    "9.9.9.9", "149.112.112.112", # Quad9
    "208.67.222.222", "208.67.220.220", # OpenDNS
]

# Bloatware packages that must be excluded / purged
MANDATORY_BLOAT_EXCLUSIONS = [
    # Games
    "aisleriot", "gnome-mines", "gnome-sudoku", "mahjongg",
    # Telemetry and crash reports
    "whoopsie", "apport", "popularity-contest", "ubuntu-report",
    # Background services
    "cups", "cups-browsed", "avahi-daemon",
    # Heavy container daemon
    "snapd",
]

# Mandatory Study Tool suite
MANDATORY_STUDY_TOOLS = [
    "anki",
    "evince",
    "zathura",
    "focuswriter",
    "markdown",
    "pomodoro",
]

# Mandatory kernel arguments for live amnesic RAM execution
MANDATORY_KERNEL_ARGS = [
    "boot=casper",
    "toram",
    "layerfs=overlayfs",
    "systemd.gpt_auto=0",
    "noswap",
]


def resolve_project_file(*subpath: str) -> Path:
    """Return the resolved Path to a file in the project repository."""
    return PROJECT_ROOT.joinpath(*subpath)


def find_artifact(relative_path: str, live_system_path: Optional[str] = None) -> Optional[Path]:
    """
    Find artifact either in local repo workspace or live system path.
    Returns Path if exists, else None.
    """
    local_path = PROJECT_ROOT / relative_path
    if local_path.is_file():
        return local_path
    if live_system_path and os.path.exists(live_system_path):
        return Path(live_system_path)
    return None


def parse_hosts_file(content: str) -> Dict[str, Set[str]]:
    """
    Parse /etc/hosts content.
    Returns a dict mapping lowercase domain -> set of IP strings (e.g. {'0.0.0.0', '::'}).
    """
    domain_to_ips: Dict[str, Set[str]] = {}
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 2:
            ip = parts[0].strip()
            for domain in parts[1:]:
                dom = domain.strip().lower()
                domain_to_ips.setdefault(dom, set()).add(ip)
    return domain_to_ips


def parse_desktop_entry(content: str) -> Dict[str, str]:
    """Parse a .desktop file content into a key-value dictionary under [Desktop Entry]."""
    parser = configparser.ConfigParser(interpolation=None)
    # Desktop entries are INI files
    parser.read_string(content)
    if "Desktop Entry" in parser:
        return dict(parser["Desktop Entry"])
    return {}


def parse_grub_cfg(content: str) -> List[Dict[str, str]]:
    """
    Parse grub.cfg content.
    Returns a list of menuentry dicts with 'title' and 'cmdline'.
    """
    entries = []
    current_title = None
    current_cmdline = []
    in_entry = False

    for line in content.splitlines():
        line = line.strip()
        menu_match = re.match(r'^menuentry\s+[\'"]([^\'"]+)[\'"]', line)
        if menu_match:
            current_title = menu_match.group(1)
            current_cmdline = []
            in_entry = True
            continue
        if in_entry:
            if line.startswith("linux") or line.startswith("linux16") or line.startswith("linuxefi"):
                current_cmdline.append(line)
            if line.endswith("}"):
                entries.append({
                    "title": current_title or "Unknown",
                    "cmdline": " ".join(current_cmdline),
                    "full_block": line,
                })
                in_entry = False
                current_title = None
    return entries


def parse_package_manifest(content: str) -> Tuple[Set[str], Set[str]]:
    """
    Parse package_manifest.txt.
    Returns (installed_packages, excluded_packages) sets.
    """
    installed = set()
    excluded = set()
    current_section = "installed"

    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        lower = line.lower()
        if "exclude" in lower or "purged" in lower or "removed" in lower:
            current_section = "excluded"
            continue
        if "installed" in lower or "packages" in lower and ":" in lower:
            current_section = "installed"
            continue

        pkg_name = line.split()[0].split("=")[0].split(":")[0].strip()
        if pkg_name:
            if current_section == "excluded":
                excluded.add(pkg_name)
            else:
                installed.add(pkg_name)
    return installed, excluded


def is_valid_ip(ip_str: str) -> bool:
    """Check if string is a valid IPv4 or IPv6 address."""
    try:
        ipaddress.ip_address(ip_str)
        return True
    except ValueError:
        return False
