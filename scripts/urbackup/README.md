# UrBackup Image Backups on Linux
## Master Runbook (ENTRY POINT)

> **Audience:** Linux administrators / operators  
> **Scope:** ALL Linux systems using UrBackup image backups  
> **Purpose:** This document is the **single entry point** for installing,
> configuring, and operating UrBackup image backups using `dattobd`.

This runbook **does not implement backups by itself**.  
It directs you to the **correct downstream guide** based on your system layout.

---

## 1. What This Runbook Is (and Is Not)

### This runbook **IS**:
- The **starting point** for all UrBackup image backup work
- A decision guide to choose **NON-LVM vs LVM**
- A controller for **execution order**
- The authoritative map of this repository

### This runbook **IS NOT**:
- A filesystem-specific implementation
- A replacement for NON-LVM or LVM runbooks
- A script reference

---

## 2. Repository Structure (Authoritative)

```
/home/ecloaiza/scripts/urbackup/
├── README.md                  ← THIS FILE (ENTRY POINT)
├── Pre-Req/
│   └── Install-Pre-REq.md     ← Install dattobd + UrBackup client (MANDATORY)
├── NON-LVM/
│   ├── Install-NON-LVM2.md    ← NON-LVM snapshot runbook
│   └── *.sh                   ← NON-LVM operational scripts
└── LVM/
    └── Install-LVM.md         ← LVM snapshot runbook (to be added)
```

This structure is intentional.  
Filesystem-specific logic **must never be mixed**.

---

## 3. Mandatory Execution Order (DO NOT SKIP)

All systems **must** follow this order:

### Step 1 — Install Prerequisites (ALL systems)

Before doing anything else, install and validate:

- `dattobd` (DKMS kernel snapshot driver)
- Kernel headers / DKMS tooling
- UrBackup client backend

📄 Follow **this guide first**:

```
/home/ecloaiza/scripts/urbackup/Pre-Req/Install-Pre-REq.md
```

Stop if any validation step fails.

---

### Step 2 — Identify Your System Type

Determine **how your root filesystem is implemented**.

Run:

```bash
lsblk -f /
```

Then classify the system:

| System Type | Description |
|-----------|------------|
| **NON-LVM** | Root filesystem directly on disk/partition (e.g. `/dev/sda2`) |
| **LVM** | Root filesystem on `/dev/mapper/<vg>-<lv>` |

If unsure, assume **LVM** until proven otherwise.

---

### Step 3 — Follow the Correct Runbook

#### NON-LVM Systems

Follow:

```
/home/ecloaiza/scripts/urbackup/NON-LVM/Install-NON-LVM2.md
```

#### LVM Systems

Follow:

```
/home/ecloaiza/scripts/urbackup/LVM/Install-LVM.md
```

⚠️ LVM systems use **different snapshot logic** and must not reuse NON-LVM scripts.

---

## 4. Hard Rules (ALL Systems)

❌ Do NOT:
- Skip the Pre-Req install
- Mix NON-LVM and LVM logic
- Run `dbdctl` manually during backups
- Modify UrBackup binaries

✅ Always:
- Start from this runbook
- Follow exactly one filesystem-specific guide
- Validate after every change

---

## 5. Status

- ✅ Entry-point runbook defined
- ✅ Pre-Req install documented
- ✅ NON-LVM runbook complete
- ⏳ LVM runbook pending

---

## 6. Summary

**Start here → Install Pre-Req → Choose NON-LVM or LVM → Follow exactly one runbook**
