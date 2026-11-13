# scripts/proton-pass

Proton Pass helpers for every homelab host. Secrets come from Proton Pass at run time; the only thing a host keeps is its own
Personal Access Token (PAT), sealed to its TPM (handle `0x81010001`) or, where there is no TPM, `~/.secrets/proton-pass-pat`.

| File | What it does |
|------|--------------|
| `ssh-agent-start.sh` | Starts the Proton Pass SSH agent (`~/.ssh/proton-pass-agent.sock`) with the HOMELAB SSH keys (folder `SSH`) |
| `ssh-agent-watchdog.sh` + `install-ssh-agent-watchdog.sh` | Restarts the agent when it has lost its Proton session (user timer, every 5 min, at most once per 30 min) |
| `systemd/` | User units for the agent and the watchdog (Linux). kipp (macOS) runs the same script from the LaunchAgent `com.protonpass.ssh-agent` |
| `git-credential-protonpass` | Git credential helper for github.com and gitlab.home.elikesbikes.com |
| `pass-secrets.sh`, `pass_cache.py`, `pass_trace.py` | Secret lookup helpers used by service `start.sh` scripts |

## SSH identity: each host signs only as itself (since v1.14.0; keys in HOMELAB since v1.17.0)

Every host has one key, `<host> SSH identity` (ed25519, comment `ecloaiza@<host>`), in the Proton **HOMELAB** vault,
folder `SSH`. Targets list each allowed host's public key in `authorized_keys`; nothing pins another host's key.

**What enforces it (v1.17.0, 2026-11-12):** the owner chose one vault over the nine `SSH <host>`/`SSH <device>` vaults
of v1.14.0-v1.16.x. pass-cli 2.7.0's agent can only filter by vault (`ssh-agent start|load|daemon` take `--vault-name`
or `--share-id`; there is no item filter), and every host's PAT reads all of HOMELAB, so **every agent now holds every
HOMELAB SSH key** (about 14). A host signs as itself only because its `~/.ssh/config` pins its own public key under
`Host *` (below). Anything that uses an agent socket without that config must pin the key too: on hailmary the
Semaphore container (`ansible-prod-1`) mounts the socket and has its own pin in the mounted home's `.ssh/config`.

Before v1.14.0 the keys were named after the host you log in **to** (`<X> SSH Key` = key for X), and several hosts
signed with another host's key. That model is gone; v1.17.0 keeps the one-key-per-host naming.

### How the agent picks its vault

1. `~/.config/proton-pass/ssh-agent-vault` (one line): a per-host override (none in use).
2. Otherwise `HOMELAB`.

### SSHTars devices (iPhone, iPad)

The SSHTars app reaches hosts through hailmary's broker (`scripts/sshtars/broker`, a forced command on each device's
login line). Each device has its own key in HOMELAB/`SSH`, titled `SSHTars <device> identity`, and its own agent socket,
`~/.ssh/sshtars-<device>.sock` (`ssh-agent-start.sh --device <device>`, unit `proton-pass-ssh-agent-device@<device>`).
Since v1.17.0 that socket serves **every** HOMELAB SSH key, so a device could sign as any host; the owner accepted this.
The broker runs `catalog.py --device <device>`, which turns the catalog's shared key name `SSHTars device identity` into
the device's own title, so the app picks its own key. Keep the device titles distinct (the app maps title to
fingerprint, first match wins). The broker's syslog line (`device=`) traces each use to a device.

Adding a device: create the key in HOMELAB/`SSH` titled `SSHTars <device> identity`, put the public key on every catalog
host, then on hailmary `systemctl --user enable --now proton-pass-ssh-agent-device@<device>` and add the device's
login line.

### Client side

Each host's `~/.ssh/config` has, under `Host *`:

```
IdentityAgent ~/.ssh/proton-pass-agent.sock
IdentityFile ~/.ssh/identity.pub     # this host's own public key
IdentitiesOnly yes
```

No per-target `IdentityFile` lines. `~/.ssh/identity.pub` is public; the private key never leaves Proton.

### Adding a host

1. `pass-cli folder list --vault-name HOMELAB` gives the id of the folder `SSH`, then
   `pass-cli item create ssh-key generate --vault-name HOMELAB --folder-id <SSH folder id> --title "<host> SSH identity" --comment "ecloaiza@<host>" --key-type ed25519`.
2. The host's own PAT (one per host) needs viewer on HOMELAB, which every host already has.
3. Put the public key (`pass-cli item view ... --output json`, `.item.content.content.SshKey.public_key`) in
   `authorized_keys` on every host it should reach, and in the new host's `~/.ssh/identity.pub`.
4. Restart the agent: `systemctl --user restart proton-pass-ssh-agent` (macOS: `launchctl kickstart -k gui/$(id -u)/com.protonpass.ssh-agent`)
   and check `ssh-add -l` lists `<host> SSH identity`.

### Tested (2026-11-09)

- Temporary agent per host on its own vault, logins pinned to the new key only: full mesh tars, hailmary, rocky, endurance,
  murph, kipp, trainerroad (42/42), tars to router, proxmox-prod-1s/4s/6s, proxmox-dm, Home Assistant, nvr-prod-2, mann,
  router-prodmx-5 (15/15), hailmary to router (certbot).
- After the switch, through the real agent and config: tars 15/15; rocky, murph, endurance, kipp, trainerroad 6/6 each.

Not tested: case and gargantua (offline, still on HOMELAB fallback); hailmary (on override until the SSHTars change).
