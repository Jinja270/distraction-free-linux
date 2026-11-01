# Flashing Guide — Distraction-Free Linux (Study OS)

This guide provides step-by-step instructions for flashing the `distraction-free-linux.iso` hybrid image onto a USB flash drive using **Rufus**, **dd**, **Ventoy**, or **BalenaEtcher**.

---

## 1. Prerequisites & Preparation

- **USB Flash Drive**:
  - Capacity: Minimum 8 GB (16 GB or 32 GB recommended if configuring persistence).
  - Speed: USB 3.0 or 3.1 recommended for rapid RAM loading (`toram` takes ~15–30 seconds over USB 3.0 vs ~2–3 minutes over USB 2.0).
- **Target Computer**:
  - 64-bit x86_64 CPU (Intel or AMD).
  - RAM: Minimum 4 GB RAM (8 GB+ recommended since the entire compressed rootfs is cached in volatile RAM tmpfs).
  - Firmware: Supports both modern UEFI and legacy BIOS/CSM.
- **Data Warning**:
  - Writing the ISO will completely erase all pre-existing partitions and files on the target USB drive. **Back up all valuable data before proceeding.**

---

## 2. Flashing Methods

### Method 1: Rufus (Windows)

Rufus is the recommended flashing utility on Windows systems.

1. Download the latest version of Rufus from [rufus.ie](https://rufus.ie/).
2. Insert your USB flash drive.
3. Launch Rufus:
   - **Device**: Select your target USB drive (verify drive letter and size).
   - **Boot selection**: Click **SELECT** and browse to `distraction-free-linux.iso`.
   - **Partition scheme**:
     - Select **GPT** for modern UEFI systems (recommended).
     - Select **MBR** if you need compatibility with older legacy BIOS systems.
   - **Target system**: UEFI (non-CSM) for GPT, or BIOS/UEFI for MBR.
   - **Volume label**: Defaults to `DFL_STUDY_OS`.
   - **File system**: Leave as default (`FAT32` or `Large FAT32`).
4. Click **START**.
5. When prompted with the **ISOHybrid Image detected** dialog:
   - Select **Write in DD Image mode** (Recommended).
   - *Note*: Writing in DD mode ensures bit-for-bit exact reproduction of the hybrid partition table (MBR + ESP partition), preventing any bootloader file translation issues.
   - Alternatively, selecting **Write in ISO Image mode** will also work as the ISO includes dual El Torito and UEFI GRUB payloads.
6. Confirm the warning dialog that all data on the target USB will be destroyed.
7. Wait for the status bar to show **READY**. Close Rufus and safely remove your USB drive.

---

### Method 2: `dd` Command Line (Linux & macOS)

The standard Unix `dd` utility provides a direct, bit-exact disk copy without any third-party dependencies.

#### Step 1: Identify your USB drive
Open a terminal and list connected block devices:
```bash
# On Linux:
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL

# On macOS:
diskutil list
```
> **CRITICAL WARNING**: Carefully verify the target drive identifier (e.g. `/dev/sdb`, `/dev/sdc` on Linux, or `/dev/disk2` on macOS). Writing to the wrong drive identifier (e.g. `/dev/sda` or `/dev/nvme0n1`) will permanently destroy your host operating system!

#### Step 2: Unmount any auto-mounted partitions
```bash
# On Linux:
sudo umount /dev/sdX* 2>/dev/null || true

# On macOS:
diskutil unmountDisk /dev/diskN
```

#### Step 3: Write the ISO image
Execute `dd` with direct I/O and synchronous flush flags:
```bash
# On Linux:
sudo dd if=distraction-free-linux.iso of=/dev/sdX bs=4M status=progress conv=fsync oflag=direct

# On macOS (use the raw disk device 'rdiskN' for high throughput):
sudo dd if=distraction-free-linux.iso of=/dev/rdiskN bs=4m status=progress
```

#### Step 4: Sync disk caches
```bash
sync
```
Once the command exits, your bootable USB is ready.

---

### Method 3: Ventoy (Multi-Boot USB with Persistence)

Ventoy allows you to install multiple ISOs on a single USB drive simply by copying the `.iso` file into the Ventoy partition. Distraction-Free Linux provides native Ventoy support via embedded `configs/boot/loopback.cfg`.

1. Download and install Ventoy onto your USB drive from [ventoy.net](https://www.ventoy.net/).
2. Once Ventoy is installed, open the main exFAT data partition on your USB drive.
3. Copy `distraction-free-linux.iso` directly into the root or an `ISO/` directory on the drive.
4. *(Optional)* To enable persistence in Ventoy:
   - Create a persistence dat file using Ventoy's `CreatePersistentImg.sh`:
     ```bash
     bash CreatePersistentImg.sh -s 4096 -t ext4 -l home-rw -o dfl-persistence.dat
     ```
   - Copy `dfl-persistence.dat` to the USB drive.
   - Create or edit `ventoy/ventoy.json` on the USB drive:
     ```json
     {
       "persistence": [
         {
           "image": "/distraction-free-linux.iso",
           "backend": "/dfl-persistence.dat"
         }
       ]
     }
     ```
5. Reboot your system and select your USB drive to boot Ventoy. Select `distraction-free-linux.iso` from the interactive menu.

---

### Method 4: BalenaEtcher (Windows, macOS, Linux)

BalenaEtcher is a cross-platform graphical image flasher with automatic drive selection validation:

1. Download and install BalenaEtcher from [etcher.balena.io](https://etcher.balena.io/).
2. Insert your USB flash drive.
3. Click **Flash from file** and select `distraction-free-linux.iso`.
4. Click **Select target** and choose your USB drive (Etcher automatically hides system internal drives).
5. Click **Flash!** and authenticate with administrator/sudo credentials.
6. Once verification finishes, safely unplug the USB.

---

## 3. Booting Distraction-Free Linux

### Boot Device Selection Key

Insert your flashed USB drive into the target computer while powered off. Power on the system and immediately tap the **Boot Menu Key** repeatedly until the boot selection menu appears:

| Manufacturer | Boot Menu Key |
|---|---|
| **Dell** | `F12` |
| **HP** | `F9` or `Esc` |
| **Lenovo** | `F12` or Novo button |
| **ASUS** | `F8` or `Esc` |
| **Acer** | `F12` |
| **MSI** | `F11` |
| **Apple Mac** | Hold `Option` / `Alt` during startup |
| **Microsoft Surface** | Hold `Volume Down`, press and release `Power` |

### BIOS/UEFI Settings

If the drive is not recognized or fails to load:
1. **Secure Boot**: Distraction-Free Linux uses standard Ubuntu unsigned live kernels by default. If your UEFI firmware requires Microsoft Third-Party UEFI CA or rejects the bootloader, enter UEFI Setup (`F2` or `Del`) and set **Secure Boot** to **Disabled**.
2. **Boot Mode**: Ensure **UEFI Boot** is enabled.

---

## 4. Boot Options & RAM Loading

When the GRUB menu appears, you will see two primary options:

1. **Distraction-Free Linux (Study OS) — Live RAM Amnesic Session**:
   - Boots with parameters `boot=casper toram layerfs=overlayfs systemd.gpt_auto=0 noswap quiet splash`.
   - Copies the entire compressed rootfs into RAM (`toram`).
   - Host internal drives are completely isolated and unmounted.
   - **Freedom of boot media**: Once the desktop appears, you can unplug the physical USB stick! The operating system runs entirely from volatile system memory.
2. **Distraction-Free Linux (Study OS) — Persistent Storage Session**:
   - Automatically detects an attached partition labeled `home-rw` or `writable`.
   - In Mode B (`home-rw`), your notes, flashcards, and study materials in `/home/study` are preserved across reboots, while all system files, firewall rules, and distraction blocking remain strictly amnesic in RAM.
3. **Safe Graphics Mode**:
   - Fallback mode using basic VESA framebuffer (`nomodeset`) for compatibility with unsupported GPU chipsets.

---

## 5. Post-Boot Verification

Once autologged into the `study` user XFCE desktop:
1. Open the terminal.
2. Verify host disks are completely unmounted:
   ```bash
   lsblk
   ```
3. Verify distraction blocking is active:
   ```bash
   python3 /usr/local/bin/verify_blocking.py
   ```
