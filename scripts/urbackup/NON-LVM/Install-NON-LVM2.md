# UrBackup Image Backups – NON-LVM Systems
## dattobd Snapshot Runbook

> **Audience:** Linux administrators / operators
> **Scope:** NON-LVM systems only (raw ext4/XFS filesystems)
> **Out of scope:** LVM-based systems (covered in a separate runbook)

---

## 1. Objective

This runbook provides **step-by-step operational procedures** to:
- Deploy UrBackup image backups on NON-LVM Linux systems
- Use `dattobd` safely as the snapshot mechanism
- Recover cleanly from common and catastrophic snapshot failures

This is an **operator runbook**, not a design document.

---

## 2. Preconditions (Verify Before Anything Else)

### 2.1 System Requirements
- Linux host with **NON-LVM root filesystem**
- Supported filesystem (ext4 or XFS)
- UrBackup client installed
- `dattobd-dkms` installed and kernel module loadable
- Secure Boot either:
  - Disabled, **or**
  - MOK enrolled for dattobd

### 2.2 Required Commands
Verify these exist:

```bash
which urbackupclientbackend
which dbdctl
lsmod | grep dattobd
```

If `dattobd` is not loaded, **stop here**.

---

## 3. Canonical Repository Layout (Source of Truth)

All UrBackup-related scripts are organized under:

```
/home/ecloaiza/scripts/urbackup/
```

With filesystem-specific separation:

```
urbackup/
├── README.md
└── NON-LVM/
    ├── dattobd_create_snapshot_xfs
    ├── dattobd_remove_snapshot_xfs
    ├── cleanup_snapshots.sh
    ├── new_cleanup_snapshots.sh
    ├── snapshot.cfg
    └── Install-NON-LVM.md
```

This layout exists **by design** to avoid mixing LVM and NON-LVM logic.

The `NON-LVM/` directory is the **authoritative source** for this runbook.

---

## 4. UrBackup Snapshot Hook Directory

UrBackup executes snapshot hooks from:

```
/usr/local/share/urbackup/
```

These files **must exist**, but are implemented strictly as symlinks
to the scripts in `NON-LVM/`.

---

## 5. Configure Snapshot Mechanism (UPDATED – NON-LVM)

### 5.1 snapshot.cfg (NON-LVM only)

For NON-LVM systems, the snapshot configuration file is maintained at:

```
/home/ecloaiza/scripts/urbackup/NON-LVM/snapshot.cfg
```

Its contents **must** be:

```
# NON-LVM snapshot configuration
# Force UrBackup to use dattobd snapshot hooks

create_filesystem_snapshot=/usr/local/share/urbackup/dattobd_create_snapshot
remove_filesystem_snapshot=/usr/local/share/urbackup/dattobd_remove_snapshot

# Volume snapshots are intentionally mapped to filesystem snapshots
# on NON-LVM systems to avoid dm/lvm logic
create_volume_snapshot=/usr/local/share/urbackup/dattobd_create_snapshot
remove_volume_snapshot=/usr/local/share/urbackup/dattobd_remove_snapshot
```

Deploy it to UrBackup’s expected location:

```bash
sudo cp /home/ecloaiza/scripts/urbackup/NON-LVM/snapshot.cfg   /usr/local/etc/urbackup/snapshot.cfg
```

**Critical rules:**
- Do NOT reference LVM, dm, or btrfs helpers
- Do NOT mix NON-LVM and LVM snapshot scripts
- This file is filesystem-specific by design

---

## 6. Deploy Snapshot Script Symlinks (NON-LVM)

Create or update symlinks so UrBackup executes the NON-LVM scripts:

```bash
sudo ln -sf /home/ecloaiza/scripts/urbackup/NON-LVM/dattobd_create_snapshot_xfs   /usr/local/share/urbackup/dattobd_create_snapshot

sudo ln -sf /home/ecloaiza/scripts/urbackup/NON-LVM/dattobd_remove_snapshot_xfs   /usr/local/share/urbackup/dattobd_remove_snapshot
```

Ensure executability:

```bash
sudo chmod +x /home/ecloaiza/scripts/urbackup/NON-LVM/dattobd_*_snapshot_xfs
```

---

## 7. First Backup Execution (Validation)

### 7.1 Start Backup from Server
From the UrBackup server UI:
- Select client
- Start **Full Image Backup**

### 7.2 Monitor Client Log (Mandatory)

On the client:

```bash
sudo tail -f /var/log/urbackupclient.log
```

Expected behavior:
- Snapshot created
- `/dev/dattoX` appears
- Snapshot mounted under `/mnt/urbackup_snaps/`
- Snapshot destroyed after backup

---

## 8. Normal Operation Checklist

After each image backup, verify:

```bash
ls /dev/datto*
mount | grep urbackup_snaps
```

**Expected result:** no output.

If datto devices remain → proceed to recovery section.

---

## 9. Emergency Cleanup Procedure (NON-LVM)

### 9.1 Preconditions
- No active backups running
- Client idle

Verify:

```bash
pgrep -f urbackup || echo "Client idle"
```

### 9.2 Run Cleanup Script

Preferred (hardened):

```bash
sudo /home/ecloaiza/scripts/urbackup/NON-LVM/new_cleanup_snapshots.sh
```

Fallback:

```bash
sudo /home/ecloaiza/scripts/urbackup/NON-LVM/cleanup_snapshots.sh
```

---

## 10. Post-Recovery Validation

After cleanup:

```bash
ls /dev/datto*
mount | grep urbackup_snaps
```

Both must return **no output**.

Restart client if needed:

```bash
sudo systemctl restart urbackupclientbackend
```

Re-run a **Full Image Backup** from the server UI.

---

## 11. Hard Rules (Do Not Violate)

❌ Do NOT:
- Run `dbdctl` manually during UrBackup backups
- Mix LVM logic into NON-LVM scripts
- Assume fixed datto minor numbers
- Modify UrBackup binaries

✅ Always:
- Treat `/home/ecloaiza/scripts/urbackup/NON-LVM/` as source of truth
- Keep snapshot.cfg and scripts paired
- Use symlinks only under `/usr/local/share/urbackup`
- Treat leftover datto devices as a failure state

---

## 12. Escalation Criteria

Escalate if:
- Cleanup script cannot destroy datto devices
- Kernel reports repeated `EBUSY` or `EINVAL`
- Snapshot creation fails consistently

At this point:
- Reboot clears kernel state
- Re-evaluate filesystem support
- Consider abandoning image backups on this host

---

## 13. Status

This runbook reflects the **current folder structure and deployment model**
for NON-LVM systems.

---

## Next Runbook

**UrBackup Image Backups – LVM Systems**
(To be written separately; different scripts, different rules)

