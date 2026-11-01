# Distraction-Free Linux (DFL) — Study OS

> A custom, amnesic Ubuntu 24.04 LTS (Noble Numbat) live distribution engineered from the ground up for uninterrupted, deep focus and rigorous study.

---

## 1. Architectural Overview

Distraction-Free Linux (DFL) is designed for students, researchers, developers, and knowledge workers who require an environment free of algorithmic feeds, social media distractions, and background notification noise. 

Like Tails OS, DFL boots live into volatile system RAM (`toram` Casper parameter), decoupling physical boot media upon completion of the boot sequence and leaving zero forensic footprint or data residue on host machines. Host hard drives, NVMe arrays, and internal partitions remain unmounted and isolated behind a 5-tier defense barrier.

```
                      +---------------------------------------+
                      |       Distraction-Free Linux          |
                      |        Live RAM Environment           |
                      +---------------------------------------+
                                          |
                +-------------------------+-------------------------+
                |                                                   |
    +-----------------------+                           +-----------------------+
    |   Amnesic Live Root   |                           | Dual-Mode Persistence |
    |      (volatile RAM)   |                           |      (USB Ext4)       |
    +-----------------------+                           +-----------------------+
    | - /etc/hosts Sinkhole |                           | Mode B: 'home-rw'     |
    | - nftables Firewall   |                           |  Persistent /home     |
    | - Firefox Policies    |                           |  Amnesic rootfs       |
    | - Zero Host Mounts    |                           |                       |
    | - Muted Notifications |                           | Mode A: 'writable'    |
    | - Preinstalled Tools  |                           |  Full persistence     |
    +-----------------------+                           +-----------------------+
```

### Core Architectural Pillars

1. **Amnesic Live RAM Execution & Storage Isolation**:
   - Boots with kernel flags `boot=casper toram layerfs=overlayfs systemd.gpt_auto=0 noswap quiet splash`.
   - Copies the entire compressed rootfs into RAM tmpfs, releasing physical boot media and running with zero host disk I/O.
   - Host drive protection via 5-tier isolation: kernel flags, udev rules (`UDISKS_IGNORE="1"` / `UDISKS_AUTO="0"`), Polkit restrictions (`org.freedesktop.udisks2.filesystem-mount-system` set to `Result.NO`), Thunar automount suppression, and memory-only zram swap.

2. **System-Level Distraction Blocking & Network Hardening**:
   - Dual-stack `/etc/hosts` sinkhole mapping distraction domains (social media, video streaming, digital gaming, forums, algorithmic feeds) to IPv4 `0.0.0.0` and IPv6 `::`.
   - Immutable tamper resistance: `root:root` ownership, `chmod 444`, `chattr +i`, and systemd boot service `study-hosts-hardening.service` re-asserting immutability.
   - `nftables` firewall dropping DNS-over-TLS (port 853), dropping known public DoH Anycast resolver IPs, restricting port 53 to system resolver UID, and dropping unauthorized tunneling/VPN ports.

3. **Hardened Browser & Study Whitelist Guarantee**:
   - Mozilla Firefox native package with Enterprise Policy (`policies.json`) locking DoH off (`network.trr.mode = 5`), locking proxy to system, blocking extension installations, disabling private browsing/developer tools, and enforcing `WebsiteFilter`.
   - Explicit whitelist guarantee: Uninterrupted access to `chatgpt.com`, `claude.ai`, `notebooklm.google.com`, `wikipedia.org`, `scholar.google.com` along with essential CDNs, authentication endpoints, and Turnstile captchas.

4. **Minimal Distraction-Free XFCE Desktop & Tooling**:
   - Clean, lightweight single-panel XFCE session booting directly into the `study` user with LightDM passwordless autologin.
   - Zero notification popups (`xfce4-notifyd` permanently locked in Do Not Disturb mode in XML), muted system bell (`blacklist pcspkr` in `/etc/modprobe.d/nobeep.conf`).
   - Bloatware and telemetry eliminated: purged games, `whoopsie`, `apport`, `popularity-contest`, `cups`, and `avahi-daemon`.
   - Dedicated study suite: Anki (flashcards), Evince & Zathura (minimalist document/PDF reading), FocusWriter & Markdown tools (distraction-free prose and note-taking), and a native Pomodoro focus timer.

5. **Automated Build Pipeline & CI/CD**:
   - Multi-stage Dockerfile and modular shell scripts generating a bootable hybrid ISO (`xorriso`, `mksquashfs`, `grub-mkstandalone`) supporting both UEFI and legacy BIOS.
   - GitHub Actions CI/CD workflow (`.github/workflows/build-iso.yml`) running on `ubuntu-24.04`, optimizing runner disk space, compiling the ISO, running automated verification tests, and publishing release artifacts.

---

## 2. Feature Inventory

| Feature | Description | Implementation |
|---|---|---|
| **Live RAM Execution (`toram`)** | Casper tmpfs livefs mount copying squashfs into RAM, releasing USB boot media | `configs/boot/grub.cfg`, `configs/boot/loopback.cfg` |
| **Host Disk Isolation & Amnesia** | Kernel args `systemd.gpt_auto=0 noswap`, udev `UDISKS_IGNORE="1"`, Polkit `99-prevent-host-mount.rules`, and zram | `configs/security/` |
| **Dual-Mode Persistence** | Support for `home-rw` (amnesic root + persistent user notes) and `writable` (full persistence) | `scripts/setup_persistence.sh` |
| **Dual UEFI & BIOS Hybrid Boot** | Hybrid ISO with GRUB 2 UEFI `BOOTX64.EFI`, BIOS `eltorito.img`, MBR, and Ventoy `loopback.cfg` | `scripts/07_build_iso.sh` |
| **Distraction Sinkhole** | Dual-stack IPv4 `0.0.0.0` and IPv6 `::` mapping for social media, streaming, games | `configs/network/hosts.blocklist` |
| **Tamper Resistance** | `root:root` ownership, `chmod 444`, `chattr +i`, restricted sudo, and `study-hosts-hardening.service` | `configs/network/study-hosts-hardening.service` |
| **Firewall & DNS Lockdown** | `nftables` blocking DoT port 853, public DoH Anycast IPs on port 443, UID filtering on port 53, and VPN port drops | `configs/network/nftables.conf` |
| **Firefox Enterprise Lockdown** | `policies.json` disabling DoH, locking proxy to system, blocking add-on installs, disabling private browsing/dev tools | `configs/browser/policies.json` |
| **Study Tool Whitelisting** | Preserving full functionality and CDN/auth access for ChatGPT, Claude, NotebookLM, Google Scholar, and Wikipedia | `configs/browser/policies.json` |
| **Automated Verification** | `verify_blocking.sh` and `verify_blocking.py` asserting sinkholing, connectivity drops, and study reachability | `scripts/verify_blocking.py` |
| **Minimal XFCE Desktop** | Clean single-panel XFCE session, calming theme, LightDM passwordless autologin | `configs/desktop/lightdm-autologin.conf` |
| **Notification & Noise Silencing** | `xfce4-notifyd.xml` locked in Do Not Disturb mode, system bell muted via `blacklist pcspkr` in `nobeep.conf` | `configs/desktop/xfce4-notifyd.xml`, `configs/desktop/nobeep.conf` |
| **Bloatware Elimination** | Purging games, whoopsie, apport, popularity-contest, cups, avahi-daemon, and snapd overhead | `configs/desktop/package_manifest.txt` |
| **Study Tooling Suite** | Preinstalling Anki, Evince, Zathura, FocusWriter, Markdown editor (Ghostwriter/Featherpad), Pomodoro timer | `scripts/04_install_study_tools.sh` |
| **Pomodoro Focus Timer** | Lightweight GTK3 focus timer with customizable study/break intervals and clean visual indicators | `scripts/pomodoro_timer.py` |
| **Containerized Build Engine** | Multi-stage Dockerfile and modular shell scripts building the ISO in a clean, reproducible container | `Dockerfile`, `Makefile` |
| **GitHub Actions CI/CD Pipeline** | `.github/workflows/build-iso.yml` building ISO on Ubuntu runner, running tests, and publishing release artifact | `.github/workflows/build-iso.yml` |
| **Flashing & Persistence Guides** | Step-by-step instructions for Rufus (DD/ISO mode), `dd` CLI, and Ventoy with `ventoy.json` persistence configuration | `docs/FLASHING_GUIDE.md`, `docs/PERSISTENCE_GUIDE.md` |

---

## 3. Directory Layout

```
distraction_free_linux/
├── .github/
│   └── workflows/
│       └── build-iso.yml                  # GitHub Actions CI/CD workflow
├── Dockerfile                             # Multi-stage Ubuntu 24.04 build container
├── Makefile                               # Orchestration Makefile
├── build_iso.sh                           # Master 10-stage ISO build pipeline
├── configs/
│   ├── boot/
│   │   ├── grub.cfg                       # GRUB 2 live boot configuration (toram, isolation)
│   │   └── loopback.cfg                   # Ventoy multiboot loopback configuration
│   ├── browser/
│   │   └── policies.json                  # Firefox Enterprise lockdown & study whitelist
│   ├── desktop/
│   │   ├── lightdm-autologin.conf         # Passwordless autologin to study user
│   │   ├── nobeep.conf                    # pcspkr speaker blacklisting
│   │   ├── package_manifest.txt           # Package inclusion & exclusion audit
│   │   ├── xfce4-notifyd.xml              # Locked Do-Not-Disturb configuration
│   │   ├── zathurarc                      # Minimalist distraction-free PDF viewer theme
│   │   └── launchers/                     # FreeDesktop .desktop application launchers
│   │       ├── anki.desktop
│   │       ├── evince.desktop
│   │       ├── focuswriter.desktop
│   │       ├── markdown.desktop
│   │       ├── pomodoro.desktop
│   │       └── zathura.desktop
│   ├── network/
│   │   ├── apply-hosts-hardening.sh       # Inode immutability enforcement script
│   │   ├── hosts.blocklist                # Dual-stack IPv4/IPv6 distraction sinkhole
│   │   ├── nftables.conf                  # Port 853/DoH/VPN dropping firewall rules
│   │   └── study-hosts-hardening.service  # Systemd boot service for immutable /etc/hosts
│   └── security/
│       ├── 99-amnesic-disks.rules         # Udev rules: UDISKS_IGNORE="1", UDISKS_AUTO="0"
│       ├── 99-lockdown                    # Sudoers hardening policy
│       ├── 99-prevent-host-mount.rules    # Polkit rules denying filesystem-mount-system
│       └── wireguard-lockdown.conf        # Network tunnel restriction configuration
├── docs/
│   ├── README.md                          # Comprehensive architectural overview
│   ├── FLASHING_GUIDE.md                  # Rufus, dd, Ventoy, Etcher flashing instructions
│   └── PERSISTENCE_GUIDE.md               # Mode B vs Mode A persistence configuration
├── scripts/
│   ├── 01_bootstrap.sh                    # Stage 3: debootstrap noble minbase rootfs
│   ├── 02_configure_system.sh             # Stage 4: kernel, casper, locales, tz, network, study user
│   ├── 03_install_desktop.sh              # Stage 5: minimal XFCE desktop, LightDM, DND mute
│   ├── 04_install_study_tools.sh          # Stage 6: study tooling suite preinstallation
│   ├── 05_apply_lockdown.sh               # Stage 7: hosts sinkhole, nftables, browser policies
│   ├── 06_build_squashfs.sh               # Stage 9: high-density zstd squashfs compression
│   ├── 07_build_iso.sh                    # Stage 10: hybrid live ISO assembly with xorriso
│   ├── pomodoro_timer.py                  # Standalone GTK3 Pomodoro focus timer app
│   ├── setup_persistence.sh               # USB persistence partition initializer
│   ├── verify_blocking.py                 # Automated Python network verification runner
│   └── verify_blocking.sh                 # Shell verification test runner
└── tests/
    └── e2e/                               # 4-tier requirement-driven opaque-box test suite
        ├── run_all_tests.py               # E2E test suite runner (95 assertions)
        ├── test_boot_and_persistence.py   # Bootloader, toram, and isolation tests
        ├── test_browser_policy.py         # Firefox Enterprise policies validation
        ├── test_desktop_config.py         # XFCE, LightDM, and noise reduction tests
        ├── test_helpers.py                # Shared assertions and parsers
        ├── test_network_blocking.py       # Hosts sinkhole and nftables tests
        └── test_study_tools.py            # Study suite launcher and package tests
```

---

## 4. Quickstart: Building the ISO

### Prerequisites

Building the Distraction-Free Linux ISO requires an Ubuntu/Debian host (or Docker container) with root privileges and at least 15 GB of free disk space.

```bash
sudo apt-get update
sudo apt-get install -y debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools dosfstools python3 zstd curl make
```

### Option A: Local Build with Make

```bash
# Clone the repository
git clone https://github.com/your-org/distraction-free-linux.git
cd distraction-free-linux

# Run the automated 10-stage build pipeline
sudo make all
```

The resulting hybrid ISO is compiled at `/opt/dfl/distraction-free-linux.iso` along with its SHA256 checksum file.

### Option B: Local Build with `build_iso.sh`

```bash
sudo ./build_iso.sh --workdir /tmp/dfl --output /tmp/dfl/distraction-free-linux.iso
```

### Option C: Reproducible Docker Build

```bash
# Build the container image
docker build -t distraction-free-linux-builder .

# Run the build container with privileged flag (needed for debootstrap/chroot)
docker run --rm --privileged -v "$(pwd)/output:/opt/dfl" distraction-free-linux-builder
```

---

## 5. Automated Verification & Testing

DFL includes an extensive automated test suite validating all architectural guarantees:

```bash
# Run the 95-test E2E verification suite (Tiers 1-4)
python3 tests/e2e/run_all_tests.py

# Run network blocking and whitelist resolution verification
python3 scripts/verify_blocking.py

# Validate shell script syntax across all build scripts
make lint
```

---

## 6. Flashing & Persistence

For step-by-step instructions on writing the ISO to a USB flash drive using Rufus, `dd`, Ventoy, or Etcher, refer to:
- [Flashing Guide](FLASHING_GUIDE.md)

For detailed information on configuring an optional persistent partition (`home-rw` for preserving study notes while maintaining amnesic system root), refer to:
- [Persistence Guide](PERSISTENCE_GUIDE.md)

---

## 7. License

Distributed under the MIT License. See `LICENSE` for details.
