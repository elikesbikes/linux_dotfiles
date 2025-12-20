# TrueNAS SCALE Replication Monitor (ntfy)

## Overview

This project provides a **remote monitoring script** for **TrueNAS SCALE replication jobs** that sends **human-readable notifications** via **ntfy**.

The script is designed to run from any Linux host (for example, a Proxmox node), while monitoring **TrueNAS SCALE** through its API.
It intentionally avoids unreliable replication metadata and instead relies on **job logs**, which are the **same source of truth used by the TrueNAS UI**.

---

## Why This Script Exists (Important Context)

TrueNAS SCALE replication monitoring has several **non-obvious pitfalls**:

### ❌ What does *not* work reliably
- `/api/v2.0/replication/*` status fields
- Replication numeric IDs
- Task metadata fields
- Matching jobs by arguments
- Assuming task names or dataset names always exist

### ✅ What *does* work
- `/api/v2.0/core/get_jobs`
- `/api/v2.0/core/job_log?id=<JOB_ID>`
- Parsing **zettarepl job logs**

Some replication jobs **do not include task names or dataset mappings** in their logs.
When this happens, the script **does not guess** — it explicitly states that the information was **not present in the job log**.

This avoids false or misleading notifications.

---

## Key Features

- Runs **remotely** (no SSH access to TrueNAS required)
- Uses **job logs as the authoritative source of truth**
- Sends **one ntfy notification per replication job per day**
- Sends a **separate alert** if replication **did not run**
- Notifications are **human-readable**, not raw JSON
- Safe for cron (silent stdout)
- No secrets stored in the script
- Hidden env file only

---

## Directory Structure

/home/ecloaiza/scripts/
└── truenas/
└── replication-monitor/
├── truenas-repl-ntfy.sh
└── README.md



This structure groups scripts by **system responsibility** (TrueNAS), not by where they are executed from.

---

## Script Location



---

## Environment File (REQUIRED)

The script resolves its environment file **internally**.
**Nothing is hardcoded in cron.**

### Location


### Example `~/.truenas-repl-ntfy.env`

```bash
# TrueNAS API
TRUENAS_URL="https://nas.home.elikesbikes.com"
TRUENAS_API_KEY="PASTE_YOUR_TRUENAS_API_KEY_HERE"

# ntfy
NTFY_URL="https://ntfy.home.elikesbikes.com"
NTFY_TOPIC="truenas-replication"

# Optional settings
VERIFY_TLS="true"          # set to false only for self-signed certs
TIMEOUT_SEC="20"
NTFY_TAGS="truenas,replication"


### Example `~/.truenas-repl-ntfy.env`

```bash
# TrueNAS API
TRUENAS_URL="https://nas.home.elikesbikes.com"
TRUENAS_API_KEY="PASTE_YOUR_TRUENAS_API_KEY_HERE"

# ntfy
NTFY_URL="https://ntfy.home.elikesbikes.com"
NTFY_TOPIC="truenas-replication"

# Optional settings
VERIFY_TLS="true"          # set to false only for self-signed certs
TIMEOUT_SEC="20"
NTFY_TAGS="truenas,replication"

chmod 600 ~/.truenas-repl-ntfy.env
