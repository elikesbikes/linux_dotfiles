# Restic Backup Scripts

This directory contains **Restic backup–related automation scripts** and their
supporting helpers. These scripts are used in production to perform container-
based backups, ensure NFS availability, and send notifications.

Location:
```
/home/ecloaiza/scripts/restic/backups
```

---

## 📁 Directory Contents

```
restic/backups
├── restic-backup.sh
├── nfs-auto-mount.sh
└── README.md
```

---

## 🧠 Design Principles

These scripts follow strict rules:

- Scripts are **location-independent**
- Scripts are **cron-safe**
- No configuration is stored in Git
- All configuration is sourced from env files in `/home/ecloaiza/`
- Iterative changes only (no destructive rewrites)
- Docker Compose files are always referenced explicitly
- Fail fast, notify loudly

---

## 🔐 Configuration (Env Files)

All configuration is provided via **one consolidated env file**:

```
/home/ecloaiza/restic.env
```

This file is **required** and must define:

- Restic repository and password
- NFS server and export paths
- Local mount point
- Ping / reachability parameters
- Backup behavior flags

⚠️ **Env files must never live in this directory**
⚠️ **Env files must never be committed to Git**

---

## 🔗 Script Responsibilities

### `restic-backup.sh`
Main backup orchestrator:

- Loads `/home/ecloaiza/restic.env`
- Ensures NFS is reachable and mounted
- Detects docker bind volumes inside the container
- Runs Restic backups via Docker Compose
- Sends status notifications via ntfy
- Logs execution details

This script can be run:
- manually
- via cron
- from any working directory

---

### `nfs-auto-mount.sh`
NFS helper script:

- Reads NFS configuration from `/home/ecloaiza/restic.env`
- Verifies NAS reachability using configured ping settings
- Mounts or unmounts NFS exports safely
- Designed to be idempotent

This script is called by `restic-backup.sh` and can also be run independently
for troubleshooting.

---

## 🔔 Notifications

Notifications are sent via **ntfy**.

- Server: `https://ntfy.home.elikesbikes.com`
- Topic: `backups`
- Plain text messages only
- No attachments

Messages include:
- Success / failure state
- Hostname
- Backup timing information

---

## 🕒 Cron Example

Run the backup every other day at 2:00 AM:

```cron
0 2 * * * /home/ecloaiza/scripts/restic/backups/restic-backup.sh
```

(Logic inside the script determines whether the backup runs on that day.)

---

## 📦 Dependencies

Required on the host:

- docker
- docker-compose plugin
- curl
- jq
- mount / umount
- ping

---

## 🧪 Troubleshooting Tips

- Always verify the correct Docker Compose file is being used
- Check container visibility of bind mounts using:
  ```bash
  docker compose -f <compose-file> run --rm restic sh
  ```
- Review logs in:
  ```
  /var/log/restic/
  ```

---

## ✅ Status

These scripts are actively used and validated across multiple hosts
with different directory layouts.
## Author

ELIKESBIKES (Tars)
