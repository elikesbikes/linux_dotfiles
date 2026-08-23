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
