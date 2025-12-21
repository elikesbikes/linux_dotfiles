# GNOME Keybindings Backup & Restore

This directory contains scripts to **backup and restore GNOME keybindings** on Ubuntu (GNOME Shell).

The design goals are:
- Safe and reversible
- Explicit (no silent destructive actions)
- Non-destructive by default
- Git-friendly
- Compatible with Wayland and X11

Keybindings are **not sensitive data**, so backups are stored alongside the scripts.

---

## Directory Layout

```
keybindings/
├── backup-gnome-keybindings.sh
├── restore-gnome-keybindings.sh
├── README.md
└── backups/
    └── gnome-keybindings-YYYYMMDD_HHMMSS/
        ├── wm-keybindings.txt
        ├── media-keys.txt
        ├── shell-keybindings.txt
        ├── mutter-keybindings.txt
        ├── custom-keybindings.dconf
        └── full-gnome-backup.conf
```

---

## Scripts

### `backup-gnome-keybindings.sh`

Creates a timestamped backup of GNOME keybindings.

**What is backed up:**
- Window manager keybindings
- Media keys
- GNOME Shell keybindings
- Mutter keybindings
- **Custom keybindings (correctly backed up via dconf paths)**
- Optional full GNOME configuration dump

**Backup location:**
```
<script_directory>/backups/
```

Each execution creates a new timestamped backup directory.

---

### `restore-gnome-keybindings.sh`

Restores GNOME keybindings from a selected backup directory.

The restore process is **interactive** and supports multiple modes.

#### Restore Modes

1. **Restore ONLY custom keybindings**
   - Restores user-defined shortcuts (applications, scripts, commands)
   - Does NOT touch system or GNOME defaults

2. **Restore ALL keybindings (system + custom)**
   - Restores all GNOME-managed keybindings
   - Does NOT restore full GNOME UI configuration

3. **Restore ALL keybindings + FULL GNOME config**
   - Restores keybindings
   - Restores full GNOME configuration via `dconf load`
   - This overwrites themes, extensions, and UI preferences

All restore actions require explicit confirmation.

---

## Usage

### Backup
```bash
./backup-gnome-keybindings.sh
```

### Restore
```bash
./restore-gnome-keybindings.sh ./backups/gnome-keybindings-YYYYMMDD_HHMMSS
```

Follow the interactive prompts to select the desired restore mode.

---

## Notes

- Always **log out and log back in** after restoring for all changes to apply.
- Custom keybindings are stored and restored via:
  ```
  /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/
  ```
- Full GNOME restore should be used only for:
  - New system migration
  - GNOME configuration corruption recovery

---

## Location

These scripts live in:
```
/home/ecloaiza/scripts/linux/keybindings
```

Safe to commit to Git (no secrets stored).

---

## Author

ELIKESBIKES (Tars)
