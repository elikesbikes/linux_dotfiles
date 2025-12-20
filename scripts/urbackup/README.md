# UrBackup Image Backups on Linux (NON‑LVM Systems)
## dattobd Snapshot Integration Guide

> Scope: **NON‑LVM systems only**
> (Raw disk / partition filesystems such as ext4 or XFS)
>
> LVM systems are intentionally excluded and will be documented separately.

---

## 1. Purpose of This Guide

This document explains **how UrBackup image backups were made to work reliably on NON‑LVM Linux systems** using the `dattobd` snapshot driver.

It documents:
- What UrBackup actually does under the hood
- Where snapshot scripts live
- Why the defaults fail
- How snapshot creation & removal was overridden
- How cleanup is handled when things go wrong

This guide is based on **real failure modes**, not theory.

---

## 2. High‑Level Architecture

UrBackup on Linux does **not** call `dbdctl` directly.

Instead, it executes **snapshot helper scripts** configured in:

```
/usr/local/etc/urbackup/snapshot.cfg
```

Those scripts are responsible for:
1. Creating a snapshot
2. Mounting it read‑only
3. Cleaning it up after the backup

UrBackup assumes those scripts:
- Always succeed
- Always clean up
- Never leave state behind

Those assumptions are **false** with dattobd unless corrected.

---

## 3. Where UrBackup Snapshot Scripts Live

On the client system, snapshot scripts are deployed under:

```
/usr/local/share/urbackup/
```

Example contents:

```
btrfs_create_filesystem_snapshot
btrfs_remove_filesystem_snapshot
lvm_create_filesystem_snapshot
lvm_remove_filesystem_snapshot
dm_create_snapshot
dm_remove_snapshot
filesystem_snapshot_common
dattobd_create_snapshot        -> symlink
dattobd_remove_snapshot        -> symlink
```

### Important
UrBackup **chooses which scripts to run** purely based on `snapshot.cfg`.

---

## 4. Snapshot Configuration (snapshot.cfg)

For NON‑LVM systems, the configuration was set to:

```
create_filesystem_snapshot=/usr/local/share/urbackup/dattobd_create_snapshot
remove_filesystem_snapshot=/usr/local/share/urbackup/dattobd_remove_snapshot
create_volume_snapshot=/usr/local/share/urbackup/dattobd_create_snapshot
remove_volume_snapshot=/usr/local/share/urbackup/dattobd_remove_snapshot
```

This forces UrBackup to use `dattobd` for both filesystem and volume snapshots.

---

## 5. Why the Default dattobd Scripts Failed

Out‑of‑the‑box behavior failed due to:

- Incorrect device vs mountpoint assumptions
- EFI/GPT confusion (SYSVOL / MBR errors)
- Cow file exhaustion
- Snapshots not being destroyed
- UrBackup calling remove scripts multiple times with different arguments
- datto devices remaining mounted (`/dev/datto0`, `/dev/datto1`, etc.)

Once a datto device is left behind, **all future backups fail**.

---

## 6. Script Override Strategy (NON‑LVM)

Instead of editing UrBackup code, we override behavior by:

1. Leaving UrBackup intact
2. Replacing only the snapshot scripts it calls
3. Making the scripts defensive and idempotent

### Deployment Method

The following symlinks are used:

```
/usr/local/share/urbackup/dattobd_create_snapshot
    -> dattobd_create_snapshot_xfs

/usr/local/share/urbackup/dattobd_remove_snapshot
    -> dattobd_remove_snapshot_xfs
```

The actual scripts live outside UrBackup (e.g. in Git‑tracked locations).

---

## 7. dattobd_create_snapshot_xfs (Conceptual Behavior)

This script is responsible for:

1. Determining the correct block device for the given mountpoint
2. Creating a dattobd snapshot using `dbdctl setup-snapshot`
3. Tracking the assigned datto minor number
4. Mounting the snapshot read‑only under:
   ```
   /mnt/urbackup_snaps/<id>
   ```
5. Writing a `-num` file so cleanup knows which snapshot to destroy

Key design goals:
- Never assume fixed datto numbers
- Never hardcode devices
- Fail fast if arguments are invalid

---

## 8. dattobd_remove_snapshot_xfs (Conceptual Behavior)

This script must survive **bad input**.

UrBackup may call it with:
- A full mount path
- A short snapshot ID
- A device path
- Garbage

Correct behavior:
- Ignore invalid calls
- Only act when a valid snapshot directory exists
- Lazily unmount
- Destroy the snapshot using `dbdctl destroy <num>`
- Never fail the backup due to cleanup issues

Cleanup must be **best‑effort**, not strict.

---

## 9. Why a Separate Cleanup Script Exists

Despite best efforts, kernel‑level snapshot systems can still fail.

A **standalone cleanup script** exists to recover the system when:

- datto devices are left behind
- Cow files are stuck or immutable
- Mount points remain after crashes
- UrBackup cannot recover on its own

Scripts provided:
- `cleanup_snapshots.sh`
- `new_cleanup_snapshots.sh` (hardened version)

These are **manual recovery tools**, not part of normal operation.

---

## 10. Operational Rules (NON‑LVM)

✔ Do:
- Let UrBackup control snapshot timing
- Use script overrides only
- Monitor `/var/log/urbackupclient.log`
- Keep cleanup scripts available

✘ Do NOT:
- Run `dbdctl` manually during backups
- Mix LVM logic into non‑LVM scripts
- Assume datto minor numbers
- Assume scripts are called only once

---

## 11. Known Failure Modes

- Cow file fills before transition
- Snapshot not destroyed → device busy
- Wrong filesystem detected
- Mount succeeds but unmount fails
- Multiple snapshots created concurrently

All are handled by **defensive scripting**, not configuration.

---

## 12. Status

NON‑LVM snapshot handling using `dattobd` is:
- Complex
- Fragile
- Achievable with strict discipline

This guide documents a **working, battle‑tested approach**.

---

## Next Document

**LVM systems** require a fundamentally different approach and are intentionally excluded here.
They will be covered in a separate guide.

