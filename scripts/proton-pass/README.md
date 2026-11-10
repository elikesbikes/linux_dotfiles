# scripts/proton-pass

Proton Pass helpers for every homelab host. Secrets come from Proton Pass at run time; the only thing a host keeps is its own
Personal Access Token (PAT), sealed to its TPM (handle `0x81010001`) or, where there is no TPM, `~/.secrets/proton-pass-pat`.

| File | What it does |
|------|--------------|
| `ssh-agent-start.sh` | Starts the Proton Pass SSH agent (`~/.ssh/proton-pass-agent.sock`) with **only this host's own key** |
| `ssh-agent-watchdog.sh` + `install-ssh-agent-watchdog.sh` | Restarts the agent when it has lost its Proton session (user timer, every 5 min, at most once per 30 min) |
| `systemd/` | User units for the agent and the watchdog (Linux). kipp (macOS) runs the same script from the LaunchAgent `com.protonpass.ssh-agent` |
| `git-credential-protonpass` | Git credential helper for github.com and gitlab.home.elikesbikes.com |
| `pass-secrets.sh`, `pass_cache.py`, `pass_trace.py` | Secret lookup helpers used by service `start.sh` scripts |

## SSH identity: each host signs only as itself (since v1.14.0, 2026-11-09)

Every host has its own Proton vault, `SSH <short hostname>`, holding one key, `<host> SSH identity` (ed25519, comment
`ecloaiza@<host>`). The host's PAT has **viewer access to that vault only** for SSH, so a host cannot load another host's key.
Targets list each allowed host's public key in `authorized_keys`; nothing pins another host's key.

Before v1.14.0 every agent loaded all ~21 keys in the HOMELAB vault, and the keys were named after the host you log in **to**
(`<X> SSH Key` = key for X). Any host could sign as any other, sshd's `MaxAuthTries 6` forced per-target pins, and several
hosts signed with another host's key. That model is gone.

### How the agent picks its vault (first match wins)

1. `~/.config/proton-pass/ssh-agent-vault` (one line): a per-host override (unused since v1.15.0; hailmary used
   `HOMELAB` until the SSHTars devices got their own agents).
2. `SSH <short hostname>`, when the PAT can see that vault.
3. `HOMELAB`, with a syslog warning (`proton-pass-ssh-agent` tag): a host that has not been migrated yet (case, gargantua)
   keeps working until it gets its vault.

### SSHTars devices (iPhone, iPad)

The SSHTars app reaches hosts through hailmary's broker (`scripts/sshtars/broker`, a forced command on each device's
login line). Each device has its own vault, `SSH <device>`, with one key titled `SSHTars device identity`, served by
`ssh-agent-start.sh --device <device>` on `~/.ssh/sshtars-<device>.sock` (unit `proton-pass-ssh-agent-device@<device>`).
The broker hands a device only its own socket, so the iPhone cannot sign as the iPad or as hailmary. hailmary's PAT has
viewer access to the device vaults (one PAT per host); the broker's syslog line (`device=`) traces each use to a device.

Adding a device: create the vault and key as for a host (title `SSHTars device identity`), grant hailmary's PAT, put the
public key on every catalog host, then on hailmary
`systemctl --user enable --now proton-pass-ssh-agent-device@<device>` and add the device's login line.

### Client side

Each host's `~/.ssh/config` has, under `Host *`:

```
IdentityAgent ~/.ssh/proton-pass-agent.sock
IdentityFile ~/.ssh/identity.pub     # this host's own public key
IdentitiesOnly yes
```

No per-target `IdentityFile` lines. `~/.ssh/identity.pub` is public; the private key never leaves Proton.

### Adding a host

1. `pass-cli vault create --name "SSH <host>"`, then
   `pass-cli item create ssh-key generate --vault-name "SSH <host>" --title "<host> SSH identity" --comment "ecloaiza@<host>" --key-type ed25519`.
2. Grant the host's PAT viewer on that vault:
   `pass-cli personal-access-token access grant --personal-access-token-id <pat_id> --vault-name "SSH <host>" --role viewer`
   (`pass-cli personal-access-token list --output json` gives `pat_id`).
3. Put the public key (`pass-cli item view ... --output json`, `.item.content.content.SshKey.public_key`) in
   `authorized_keys` on every host it should reach, and in the new host's `~/.ssh/identity.pub`.
4. Restart the agent: `systemctl --user restart proton-pass-ssh-agent` (macOS: `launchctl kickstart -k gui/$(id -u)/com.protonpass.ssh-agent`)
   and check `ssh-add -l` shows exactly one key.

### Tested (2026-11-09)

- Temporary agent per host on its own vault, logins pinned to the new key only: full mesh tars, hailmary, rocky, endurance,
  murph, kipp, trainerroad (42/42), tars to router, proxmox-prod-1s/4s/6s, proxmox-dm, Home Assistant, nvr-prod-2, mann,
  router-prodmx-5 (15/15), hailmary to router (certbot).
- After the switch, through the real agent and config: tars 15/15; rocky, murph, endurance, kipp, trainerroad 6/6 each.

Not tested: case and gargantua (offline, still on HOMELAB fallback); hailmary (on override until the SSHTars change).
