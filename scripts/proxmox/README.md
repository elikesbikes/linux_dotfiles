# Proxmox Backup & Monitoring Scripts

This directory contains Proxmox-related automation scripts used for backup
validation, monitoring, and notifications.

The scripts are designed to be:
- cron-safe
- host-agnostic
- runnable locally or remotely
- notification-enabled via **ntfy**

---

## 📁 Directory Layout

```
/home/ecloaiza/scripts/proxmox
├── proxmox-backup-ntfy.sh
├── proxmox-backup-ntfy-remote.sh
├── README.md
```

> Environment files are **never stored in this directory**.
> All `.env` files live in `/home/ecloaiza/` and are excluded from Git.

---

## 🔔 Notifications

All scripts send notifications via **ntfy**.

- **Server:** https://ntfy.home.elikesbikes.com
- **Topic:** backups
- Messages are **plain text only**
- No attachments are sent

Notifications include:
- Backup success or failure
- Backup start time
- Backup finish time
- Duration
- Hostname

---

## 🕒 Scheduling (Cron)

Example: run the Proxmox backup check every Sunday at 4 PM.

```
0 16 * * 0 /home/ecloaiza/scripts/proxmox/proxmox-backup-ntfy.sh
```

Scripts are written to be safe to run from cron and do not depend on the
current working directory.

---

## 🌍 Remote Execution

Some scripts support running from a **remote Ubuntu host** via SSH.

Requirements:
- SSH key-based access to the Proxmox host
- Root access on the Proxmox node
- `pvesh` available on the target system

Test SSH access with:

```
ssh -o BatchMode=yes root@proxmox-host
```

If this command succeeds, the remote backup script will work.

---

## 📦 Dependencies

On Proxmox hosts:
- pvesh
- jq
- curl

On remote hosts (if used):
- ssh
- curl

---

## 🔐 Configuration

Configuration is provided via environment files located in `/home/ecloaiza/`.

Guidelines:
- Env files are **not** stored in this repository
- Env files must be readable by root
- Sensitive values (API keys, tokens) must never be hardcoded

---

## 🛠 Design Principles

- Fail loudly and notify
- No silent failures
- No assumptions about working directory
- Minimal logic in cron, logic lives in scripts
- Iterative changes only, no destructive rewrites

---

## 📜 Logging

Scripts log execution details to the system journal or to log files where
appropriate. Check logs when troubleshooting unexpected behavior.

---

## ✅ Status

These scripts are actively used in production and have been validated for:
- job success detection
- job failure detection
- job-not-run detection
- clean notification delivery
