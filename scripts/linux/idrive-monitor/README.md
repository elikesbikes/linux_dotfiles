# IDrive Backup Monitor

This script monitors IDrive backups on Linux by inspecting IDrive’s own
log files and sending human-readable notifications via ntfy.

It is designed to be:
- Cron-safe
- Deterministic
- Explicit (no heuristic guessing)
- Easy to debug
- Honest about backup results

---

## Script

```
monitor-idrive-by-filename.sh
```

Location:
```
/home/ecloaiza/scripts/linux/idrive-monitor
```

---

## How It Works (High Level)

1. Reads IDrive backup logs from:
   ```
   /opt/IDriveForLinux/idriveIt/user_profile/<user>/<email>/Backup/DefaultBackupSet/LOGS
   ```

2. Uses the **log filename** as the authoritative job status:
   - `*_Running_*`
   - `*_Success_*`
   - `*_Skipped_*`
   - `*_Canceled_*`

3. Uses the **SUMMARY section** inside the log file to extract:
   - Files backed up
   - Files failed to backup

4. Sends formatted notifications to ntfy:
   ```
   https://ntfy.home.elikesbikes.com
   topic: backups
   ```

---

## Execution Modes

### Manual run (interactive)

```bash
./monitor-idrive-by-filename.sh
```

- Will notify if a backup is currently **RUNNING**
- Useful for debugging and validation

---

### Cron run (quiet on RUNNING)

```bash
./monitor-idrive-by-filename.sh --cron
```

- Suppresses notifications while a backup is running
- Still alerts on:
  - Success
  - Skipped
  - Canceled
  - No backup today
  - Stale success (older than N days)

---

## Cron Configuration

Example cron entry (runs daily at 5:00 PM):

```cron
0 17 * * * /usr/bin/env bash /home/ecloaiza/scripts/linux/idrive-monitor/monitor-idrive-by-filename.sh --cron
```

---

## Environment Configuration (Optional)

You may override defaults via an env file:

```
/home/ecloaiza/.idrive.env
```

Example:

```bash
NTFY_URL="https://ntfy.home.elikesbikes.com"
NTFY_TOPIC="backups"
MAX_DAYS_SINCE_SUCCESS=2
```

---

## Important Notes About IDrive Semantics

- IDrive may report `Success` even if some files were skipped due to
  permission errors **when the setting**:

  ```
  Ignore file/folder level permission errors: enabled
  ```

  is turned on.

- The script reports **what IDrive actually did**, not what it claimed
  in marketing terms.

- For strict backup correctness, disable permission-error ignoring
  inside IDrive settings.

---

## Design Philosophy

This script favors:
- Truth over optimism
- Explicit behavior over heuristics
- Debuggability over cleverness

Future refactors may modularize this further, but for now this directory
exists to:
- Keep related scripts grouped
- Make cron paths explicit
- Prepare for future organization without breaking behavior
