# Security

Privacy and authentication tooling — the **Proton suite**, installed from official `.deb` packages. The installer is distro-guarded (Debian/Ubuntu only) and idempotent via per-app state markers.

## 1. Applications

| Component | State marker | Source |
|-----------|--------------|--------|
| Proton VPN (GNOME desktop) | `proton-vpn` | official repo `.deb` + `proton-vpn-gnome-desktop` |
| Proton Mail Desktop | `proton-mail-desktop` | official `.deb` (beta) |
| Proton Mail Bridge | `proton-mail-bridge` | official `.deb` |
| Proton Pass | `proton-pass` | official `.deb` |
| Proton Authenticator | `proton-authenticator` | official `.deb` |

## 2. Notes

- Policy: **official sources only**, idempotent, no snap
- Repositories/keys are added using modern GPG keyring practices
- Each `.deb` is downloaded to a temp dir and installed with `dpkg -i` + `apt-get -f install`
- A per-app state marker is written on success so re-runs skip completed installs
- A `security` category marker is written for the master menu

## 3. Verification

```bash
bash ../verify/verify_security.sh
```

Verification is marker-based, since the underlying Proton package names vary.

## 4. setup-ssh-key.sh (standalone — not part of the master menu)

Bootstraps SSH key access for `ecloaiza` on a **new remote host** via the Proton Pass SSH agent. This is a manual, one-off tool run against a target hostname — not a local package installer — so it intentionally does not match the `install_*.sh` naming convention and is not auto-discovered by `master.sh`'s category runner.

```bash
bash security/setup-ssh-key.sh <hostname>
```

See the script's own `usage()` for options (`--user`, `--password`, `--windows`, `--ip`).

**Key model (since dotfiles v1.14.0, 2026-11-09):** the script installs the key of the host it runs **on**, `~/.ssh/identity.pub`
(its key `<host> SSH identity` in the Proton HOMELAB vault, folder `SSH`; since v1.17.0 the agent serves every HOMELAB
SSH key and the `Host *` pin makes ssh offer only this one). It no longer looks up a `<target> SSH Key` or writes
`~/.ssh/pubkeys/<target>.pub` / per-target `IdentityFile` pins: each host signs only as itself, and the one pin lives under
`Host *`. Run it from every host that should reach the new target. A host without an identity gets the setup steps printed
(see `scripts/proton-pass/README.md`, "Adding a host").

Tested 2026-11-09: the identity path (key found, agent holds it) and the no-identity error, against an unreachable test
address. Not tested end to end against a fresh host.
