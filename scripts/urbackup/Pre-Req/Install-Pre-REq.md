# Runbook: Installing dattobd and UrBackup Client (All Linux Distros)

> **Audience:** Linux administrators  
> **Scope:** Client-side installation only  
> **Applies to:** Debian/Ubuntu, RHEL/CentOS/Rocky/Alma, generic Linux  
> **Purpose:** Provide a repeatable, distro-agnostic install procedure for
> `dattobd` (snapshot driver) and the UrBackup client.

This runbook is a **prerequisite** for both NON-LVM and LVM UrBackup image
backup runbooks.

---

## 1. High-Level Overview

UrBackup image backups on Linux require **two independent components**:

1. **UrBackup client**
   - User-space backup agent
   - Communicates with UrBackup server
2. **dattobd**
   - Kernel-level snapshot driver (DKMS)
   - Provides crash-consistent block snapshots via `/dev/datto*`

Both must be installed and functional **before** any snapshot scripting or
UrBackup configuration.

---

## 2. Universal Preconditions (All Distros)

### 2.1 Kernel & Build Requirements
- Running kernel must have matching headers installed
- DKMS must be available
- Root privileges required

### 2.2 Secure Boot
Because `dattobd` is a DKMS module, Secure Boot must be handled:

Choose **one**:
- Secure Boot **disabled**
- Secure Boot **enabled with MOK enrollment** for the dattobd module

Failure to satisfy this will prevent the module from loading.

---

## 3. Install dattobd

Source reference:
- https://github.com/datto/dattobd/blob/main/INSTALL.md

---

### 3.1 Debian / Ubuntu

```bash
sudo apt update
sudo apt install -y dkms linux-headers-$(uname -r)
```

Add Datto repository and key (per upstream instructions):

```bash
curl -fsSL https://linux.datto.com/repo_setup.sh | sudo bash
```

Install dattobd:

```bash
sudo apt install -y dattobd-dkms dattobd-utils
```

---

### 3.2 RHEL / CentOS / Rocky / Alma

```bash
sudo dnf install -y epel-release
sudo dnf install -y dkms kernel-devel kernel-headers
```

Add Datto repository:

```bash
curl -fsSL https://linux.datto.com/repo_setup.sh | sudo bash
```

Install dattobd:

```bash
sudo dnf install -y dattobd-dkms dattobd-utils
```

---

### 3.3 Generic / Unsupported Distros

If no packages are available:

```bash
git clone https://github.com/datto/dattobd.git
cd dattobd
make
sudo make install
```

> This path is **not recommended** for production unless packaging is unavailable.

---

## 4. Validate dattobd Installation

Run the following **before continuing**:

```bash
lsmod | grep dattobd
which dbdctl
```

Expected:
- `dattobd` kernel module is loaded
- `dbdctl` exists (usually `/usr/bin/dbdctl`)

If Secure Boot is enabled and the module fails to load:
- Enroll the MOK key
- Reboot
- Re-run validation

---

## 5. Install UrBackup Client

Source reference:
- https://www.urbackup.org/download.html#linux_all_binary

UrBackup provides a **portable binary installer**.

---

### 5.1 Download Installer

```bash
cd /tmp
curl -O https://hndl.urbackup.org/Client/2.5.28/UrBackup%20Client%20Linux%202.5.28.sh
```

(Version number may change; always verify on the UrBackup website.)

---

### 5.2 Run Installer

```bash
sudo sh UrBackup\ Client\ Linux\*.sh
```

Follow prompts to:
- Install client backend
- Enable service

---

## 6. Validate UrBackup Client

```bash
which urbackupclientbackend
systemctl status urbackupclientbackend
```

Expected:
- Binary present (often `/usr/local/sbin/urbackupclientbackend`)
- Service active (running)

---

## 7. Post-Install Sanity Checks

Run **all** of the following:

```bash
lsmod | grep dattobd
which dbdctl
which urbackupclientbackend
```

Example expected output:

```text
dattobd               114688  0
/usr/bin/dbdctl
/usr/local/sbin/urbackupclientbackend
```

If any check fails:
- Stop
- Resolve installation issues
- Do not proceed to snapshot configuration

---

## 8. Known Failure Points

- Missing kernel headers → DKMS build fails
- Secure Boot blocks module loading
- Kernel update without rebuilding DKMS module
- urbackupclientbackend installed but service not enabled

---

## 9. Next Steps

After completing this runbook successfully:

- Proceed to **NON-LVM Image Backup Runbook**, or
- Proceed to **LVM Image Backup Runbook**

Do **not** configure snapshot scripts or UrBackup image backups until this
runbook completes successfully.

---

## 10. Status

This runbook defines the **minimum supported installation state** for all
UrBackup image backup workflows on Linux.
