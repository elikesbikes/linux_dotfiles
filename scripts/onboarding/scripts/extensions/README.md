# Extensions

Declarative GNOME Shell extension management. The desired state lives in `extensions.conf`; the installer reconciles the system to match it.

## 1. Files

| File | Purpose |
|------|---------|
| `extensions.conf` | Source of truth: `UUID=enabled|disabled` per extension |
| `install_extensions.sh` | Installs missing extensions and reconciles enabled/disabled state |
| `verify_extensions.sh` | Audit-only check that the system matches `extensions.conf` |
| `CHANGELOG.md` | Change history |
| `DISCLAMER.md` | Usage disclaimer |

## 2. How It Works

- Detects GNOME and the running Shell version; skips cleanly on non-GNOME systems
- Ensures dependencies (`curl`, `jq`, `unzip`, `python3`, `pipx`) per distro (Ubuntu/Debian or Arch)
- Installs `gnome-extensions-cli` (`gext`) via `pipx`
- For each entry in `extensions.conf`:
  - Installs the extension via `gext` if missing
  - Enables or disables it to match the desired state
- Optionally copies and compiles any bundled gsettings schemas

Only extensions listed in `extensions.conf` are managed. System/distro extensions are tracked for state but never installed or removed.

## 3. Usage

```bash
# Install + reconcile
bash install_extensions.sh

# Verify only
bash verify_extensions.sh
```

## 4. Notes

- Interactive `gext` prompts use `/dev/tty` so the script works when launched from the `gum` menu
- If extensions misbehave after a run, log out and back in
- Logs: `~/.local/state/onboarding/logs/install_extensions.log`
