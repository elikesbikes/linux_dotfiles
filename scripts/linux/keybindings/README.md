# GNOME Keybindings Backup & Restore

This directory contains scripts to **backup and restore GNOME keybindings** on Ubuntu (GNOME Shell).

The design goals are:
- Safe and reversible
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
        ├── custom-shortcuts.txt
        └── full-gnome-backup.conf
```

---

## Scripts

### `backup-gnome-keybindings.sh`

Creates a timestamped backup of all GNOME keybindings.

**What is backed up:**
- Window manager keybindings
- Media keys
- GNOME Shell keybindings
- Mutter keybindings
- Custom shortcuts
- Full GNOME `dconf` dump (optional but included)

**Backup location:**
```
<script_directory>/backups/
```

Each run creates a new timestamped folder.

---

### `restore-gnome-keybindings.sh`

Restores GNOME keybindings from a backup directory.

**Behavior:**
- Always restores keybindings
- Prompts whether to restore the full GNOME configuration
- If you answer **NO**, only keybindings are restored
- Full GNOME restore (`dconf load`) is optional and explicit

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

You will be prompted before any destructive operation.

---

## Notes

- Log out and log back in after restoring for all changes to apply.
- Restoring the full GNOME config will overwrite:
  - Themes
  - Extensions
  - UI preferences
- Use full restore only when migrating systems or recovering from corruption.

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
