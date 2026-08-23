# Desktop

GUI applications, installed from official sources across three mechanisms (apt, snap, flatpak). Each installer is idempotent and writes its own state marker.

## 1. Scripts

| Script | Mechanism | Applications |
|--------|-----------|--------------|
| `install_desktop_native_apps.sh` | apt / official `.deb` | Timeshift, Kitty, Spotify (official APT repo), RustDesk (`.deb`) |
| `install_desktop_snap_apps.sh` | snap | Todoist |
| `install_desktop_flatpak_apps.sh` | flatpak (Flathub) | BlueBubbles, SyncThingy, Yubico Authenticator, Clapgrep, Warehouse, Stimulator, Resources, Cryptomator |

## 2. Notes

- Official sources only; APT is preferred for native packages
- Spotify is installed via its official APT repository with a signed-by keyring
- RustDesk is installed from a pinned official `.deb` release
- Desktop installs are isolated from CLI tooling
- State markers: `desktop_native`, `desktop_snap`, `desktop_flatpak`

## 3. Verification

```bash
bash ../verify/verify_desktop.sh
```
