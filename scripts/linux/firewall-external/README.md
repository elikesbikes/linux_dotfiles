# firewall-external

This directory contains scripts used to manage **external-facing firewall rules**
for Docker hosts using `iptables`, with special handling for:

- Docker (`DOCKER-USER` chain)
- Tailscale
- A dynamic *home IP* resolved via DDNS
- Safe re-application after reboot or Docker restarts

---

## Files

### apply-firewall.sh
**Entry-point script**

Responsibilities:
- Resolves the home IP using DDNS (DNS lookup only)
- Optionally detects IP changes
- Calls `firewall-apply-rules.sh` with the resolved IP
- Designed to be run manually or via cron

Typical usage:
```bash
sudo ./apply-firewall.sh
sudo ./apply-firewall.sh --force
```

---

### firewall-apply-rules.sh
**Rule implementation script**

Responsibilities:
- Applies `iptables` rules to the `DOCKER-USER` chain
- Allows traffic from:
  - Home IP (SSH, HTTPS, Docker socket proxy)
  - Docker bridge networks (`172.16.0.0/12`)
  - Tailscale interface
  - Loopback
  - Established/related connections
- Explicitly drops everything else (including ICMP)

This script assumes:
- Docker is running
- The `DOCKER-USER` chain exists

---

## Design Principles

- **Never modify Docker-managed chains directly**
- All custom filtering happens in `DOCKER-USER`
- Rules are ordered from most-specific → least-specific
- Explicit drops at the end to avoid accidental exposure

---

## Typical Rule Logic (High Level)

1. Allow traffic from trusted Docker bridge networks
2. Allow traffic from home IP to selected ports
3. Allow ICMP *only* from home IP
4. Allow Tailscale traffic
5. Allow loopback
6. Allow established / related traffic
7. Drop ICMP from everywhere else
8. Drop everything else

---

## After Reboot / Docker Restart

Docker recreates chains on startup.

If firewall rules are missing after reboot:
```bash
sudo systemctl restart docker
sudo ./apply-firewall.sh --force
```

---

## Cron (Optional)

To re-apply rules periodically (example: every 10 minutes):

```cron
*/10 * * * * /home/ecloaiza/scripts/linux/firewall-external/apply-firewall.sh --force
```

> This is optional but useful on hosts where Docker or networking
> can restart unexpectedly.

---

## Safety Notes

- Always keep an active SSH session when testing firewall changes
- Prefer inserting rules (`-I`) instead of appending when testing manually
- Verify with:
```bash
sudo iptables -L DOCKER-USER -n -v
```

---

## Requirements

- Linux with `iptables`
- Docker
- Root privileges
