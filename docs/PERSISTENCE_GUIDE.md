# Persistence Guide — Distraction-Free Linux (Study OS)

This guide details the dual-mode persistent storage architecture of Distraction-Free Linux (DFL), the security rationale behind **Mode B (`home-rw`)**, step-by-step setup using `scripts/setup_persistence.sh`, and integration with Ventoy's persistence plugin.

---

## 1. Dual-Mode Persistence Architecture

Distraction-Free Linux boots live into RAM using Casper (`toram` kernel parameter). By default, live sessions are 100% amnesic: when you shut down or reboot, all file modifications and runtime memory disappear completely.

To allow users to preserve their Anki flashcard decks, research papers, Markdown notes, and reading bookmarks, DFL supports persistent secondary partitions:

```
+-------------------------------------------------------------------------------+
|                       USB Drive Partition Layout                              |
+---------------------------------------+---------------------------------------+
|  Partition 1: ISO Bootloader (FAT/ISO)|  Partition 2: Persistence (ext4)      |
|  - EFI/BOOT/BOOTX64.EFI               |  - Label: 'home-rw' (Mode B) OR       |
|  - casper/filesystem.squashfs         |    Label: 'writable' (Mode A)         |
|  - casper/vmlinuz & initrd            |  - Stores persistent notes and files  |
+---------------------------------------+---------------------------------------+
```

### Architectural Comparison: Mode B vs Mode A

| Property | Mode B: `home-rw` (Recommended) | Mode A: `writable` |
|---|---|---|
| **Partition Label** | `home-rw` | `writable` |
| **Mount Target** | `/home/study` (User Home Directory) | `/` (Full Operating System Root Overlay) |
| **Tamper Resistance** | **Absolute (Immutable across reboots)** | Vulnerable (Changes to `/etc` persist) |
| **Distraction Blocks** | Resets to pristine blocklist on every reboot | Can be permanently altered/disabled |
| **Firefox Lockdown** | Re-locks policies on every reboot | Can be modified if root is compromised |
| **Package Installs** | Cleared on reboot (prevents software bloat) | Persist across reboots |
| **Study Notes & Anki** | **Persisted permanently** | Persisted permanently |
| **Recommended For** | **Dedicated study & deep focus** | System development and testing only |

---

## 2. Security Rationale: Why Mode B (`home-rw`) is Superior

The core mission of Distraction-Free Linux is to establish an unbypassable, dedicated study environment. 

### The Problem with Full Persistence (Mode A)
In traditional full persistence systems (`writable` label), every change made to the root filesystem is written to the persistent overlay. If a user in a moment of procrastination uses `sudo` to remove `/etc/hosts`, disable `nftables`, or uninstall Firefox Enterprise policies, those compromises persist across subsequent reboots. The machine ceases to be distraction-free.

### The Solution: Mode B (`home-rw`)
Mode B implements **split persistence**:
1. **Volatile System Root (`/`)**:
   - The operating system root, `/etc/hosts` sinkhole, `nftables` firewall rules, Firefox Enterprise policies, and system services execute exclusively from volatile RAM tmpfs.
   - Even if the user temporarily edits a system configuration file during a study session, **rebooting the computer completely wipes all modifications**. The system returns to its pristine, tamper-resistant lockdown state on every boot.
2. **Persistent User Space (`/home/study`)**:
   - All study materials, Anki decks (`~/.local/share/Anki2`), Zathura bookmarks, FocusWriter documents, and notes are mounted to the persistent ext4 partition labeled `home-rw`.
   - Your intellectual work is preserved safely while the operating system remains immutably hardened.

---

## 3. Creating a Persistence Partition via `setup_persistence.sh`

Distraction-Free Linux provides an automated script `scripts/setup_persistence.sh` to partition, format, label, and provision persistent partitions.

### Step 1: Identify your USB drive partition
Insert your USB drive and list the partition tables:
```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
```
Assume `/dev/sdb` is your USB drive:
- `/dev/sdb1`: Primary ISO live boot partition (created during flashing)
- `/dev/sdb2`: Free space / unallocated partition reserved for persistence

If you need to create the secondary partition, you can use `fdisk` or `parted`:
```bash
sudo parted /dev/sdb --script mkpart primary ext4 4000MB 100%
```

### Step 2: Run `setup_persistence.sh` (Mode B: `home-rw`)
Run the script targeting the secondary partition:
```bash
sudo ./scripts/setup_persistence.sh --device /dev/sdb2 --mode home-rw
```

#### What `setup_persistence.sh` does automatically:
1. Validates that the device exists and is not a critical host disk.
2. Prompts for explicit user confirmation before touching the partition (can be bypassed with `--force`).
3. Formats the partition with an `ext4` filesystem and assigns the filesystem label `home-rw`.
4. Creates the target user directory structure:
   - `/study` (owned by UID 1000, GID 100 / `users`, permissions `0755`)
   - Pre-provisions standard subdirectories: `Documents/`, `Notes/`, `Anki/`, `Downloads/`.
5. Safely unmounts and flushes disk caches.

### Command Line Options Reference

```
Usage: setup_persistence.sh [OPTIONS] --device <PARTITION_DEVICE>

Options:
  -d, --device <dev>     Target block device partition (e.g. /dev/sdb2)
  -m, --mode <mode>      Persistence mode:
                           'home-rw'  (Mode B - Default: Amnesic root + persistent /home/study)
                           'writable' (Mode A: Full root overlay persistence)
  -u, --user <username>  Target user account for home directory setup (default: study)
  -f, --force            Bypass interactive safety confirmation prompt
  -h, --help             Display usage summary
```

---

## 4. Ventoy Persistence Plugin Integration

If you boot Distraction-Free Linux using a [Ventoy](https://www.ventoy.net/) multi-boot USB drive, you do not need to repartition the physical disk. Ventoy supports file-backed persistence loop devices using a `.dat` image.

### Step 1: Create the persistence image
On a Linux host, download and run Ventoy's `CreatePersistentImg.sh` tool:
```bash
# Create a 4 GB ext4 image labeled home-rw
bash CreatePersistentImg.sh -s 4096 -t ext4 -l home-rw -o dfl-home-rw.dat
```

### Step 2: Copy image to your Ventoy USB drive
Copy both the ISO and the `.dat` file to the root of your Ventoy USB drive:
```bash
cp distraction-free-linux.iso /media/$USER/Ventoy/
cp dfl-home-rw.dat /media/$USER/Ventoy/
```

### Step 3: Configure `ventoy/ventoy.json`
Create or edit `ventoy/ventoy.json` on the root of your Ventoy USB partition:
```json
{
  "persistence": [
    {
      "image": "/distraction-free-linux.iso",
      "backend": "/dfl-home-rw.dat"
    }
  ]
}
```

When you select `distraction-free-linux.iso` in the Ventoy boot menu, Ventoy will automatically attach `dfl-home-rw.dat` as an emulated block device with label `home-rw`, activating seamless Mode B persistence.

---

## 5. Verifying Active Persistence in Live Session

Once booted into the Distraction-Free Linux desktop:

### Check Mount Status
Open a terminal and run:
```bash
df -h
```
- In **Mode B (`home-rw`)**, you will see:
  ```
  /dev/sdb2       ...  /home/study
  ```
- In **Mode A (`writable`)**, you will see:
  ```
  /dev/sdb2       ...  /var/log/casper.log /cow
  ```

### Check Overlay Filesystem
```bash
mount | grep -E "home-rw|overlay|casper"
```

### Test Persistence Workflow
1. Create a test file in your home directory:
   ```bash
   echo "Study Session: Chapter 4 Calculus Notes" > ~/Documents/notes.txt
   ```
2. Reboot the system:
   ```bash
   sudo reboot
   ```
3. Boot back into Distraction-Free Linux.
4. Verify the file exists:
   ```bash
   cat ~/Documents/notes.txt
   ```

---

## 6. Troubleshooting & Recovery

### Permissions Issues in `/home/study`
If files saved in a previous session become read-only or owned by an unrecognized user, reset ownership to the live `study` user:
```bash
sudo chown -R study:users /home/study
sudo chmod -R u+rwX /home/study
```

### Filesystem Check (`fsck`)
If the USB drive was unplugged without shutting down cleanly:
```bash
sudo e2fsck -f -y /dev/sdX2
```
