# DDNS Update Script (ddclient wrapper)

This directory contains a small wrapper script around **ddclient** to ensure
Dynamic DNS updates are run on a schedule and logged consistently.

## What this does

- Executes `ddclient -force -verbose`
- Writes output to a log file
- Keeps log size under control with simple rotation
- Designed to be run via `cron`
- Uses **existing ddclient configuration** (no credentials stored here)

## Files

- `update-ddns.sh`
  Main script that runs ddclient and logs the result.

## Log file

The script writes to:

```
/var/log/ddns-update.log
```

If the log exceeds ~1 MB, it is automatically rotated to:

```
/var/log/ddns-update.log.1
```

## Cron configuration (recommended)

Run twice a day: **8:00 AM** and **5:00 PM**

Edit root crontab:

```bash
sudo crontab -e
```

Add:

```cron
0 8,17 * * * /home/ecloaiza/scripts/linux/DDNS/update-ddns.sh
```

## Manual test

Run once manually to verify:

```bash
sudo /home/ecloaiza/scripts/linux/DDNS/update-ddns.sh
```

Then check the log:

```bash
sudo tail -n 50 /var/log/ddns-update.log
```

## Notes

- This script assumes `ddclient` is already installed and configured.
- All authentication and provider configuration lives in `/etc/ddclient.conf`.
- No secrets are stored in this repository or script.


## Author

ELIKESBIKES (Tars)
