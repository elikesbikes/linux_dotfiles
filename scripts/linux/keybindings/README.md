# GNOME Keybindings Backup & Restore

This directory contains scripts to **backup and restore GNOME keybindings** on Ubuntu (GNOME Shell).

The scripts are designed to be:
- Safe
- Reversible
- Non-destructive by default
- Compatible with Wayland and X11

---

## Files

### `backup-gnome-keybindings.sh`
Creates a timestamped backup of all GNOME keybindings and configuration.

**What it backs up:**
- Window manager keybindings
- Media keys
- Shell keybindings
- Mutter keybindings
- Custom shortcuts
- Optional full GNOME `dconf` dump

**Backup location:**
```
~/Downloads/gnome-keybindings-YYYYMMDD_HHMMSS/
```

---

### `restore-gnome-keybindings.sh`
Restores GNOME keybindings from a previously created backup.

**Behavior:**
- Always restores keybindings
- Prompts whether to restore the full GNOME configuration
- If you answer **NO**, only keybindings are restored
- Full GNOME restore is optional and explicit

---

## Usage

### Backup
```bash
./backup-gnome-keybindings.sh
```

### Restore
```bash
./restore-gnome-keybindings.sh ~/Downloads/gnome-keybindings-YYYYMMDD_HHMMSS
```

You will be prompted before any destructive operation.

---

## Notes

- After restoring, **log out and log back in** for all changes to apply.
- Full GNOME restore (`dconf load`) will overwrite themes, extensions, and UI settings.
- Use full restore only when migrating systems or recovering from corruption.

---

## Location

These scripts live in:
```
/home/ecloaiza/scripts/linux/keybindings
```

They are safe to commit to Git (no secrets stored).

---

## Author

Maintained by ecloaiza
