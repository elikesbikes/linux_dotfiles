# Ubuntu Keybindings & Dock Backup/Restore Scripts

These scripts help you backup and restore your Ubuntu keybindings and dock configuration across machines.

## 📁 Files

- `backup_keybindings.sh` - Backs up keybindings and dock configuration
- `restore_keybindings.sh` - Restores keybindings and dock configuration
- `backups/` - Directory containing all backups (auto-created)

## 🚀 Quick Start

### Backup on your current machine:
```bash
./backup_keybindings.sh
```

### Restore on a new machine:
```bash
./restore_keybindings.sh
```

## 📋 What Gets Backed Up

### Keybindings
- ✅ All GNOME desktop keybindings
- ✅ Window manager keybindings
- ✅ Mutter keybindings (including Wayland)
- ✅ Media keys
- ✅ **Custom keybindings** (your personalized shortcuts)
- ✅ Shell keybindings

### Dock Configuration
- ✅ All favorite applications (dock icons)
- ✅ Dash-to-Dock settings (if installed)
- ✅ Dash-to-Panel settings (if installed)
- ✅ GNOME Shell dock configuration

### Additional Files
- ✅ Human-readable exports of all settings
- ✅ Metadata (hostname, Ubuntu version, date, etc.)

## 📖 Detailed Usage

### Backup Script

Simply run:
```bash
./backup_keybindings.sh
```

**What it does:**
1. Creates timestamped backup in `backups/backup_YYYYMMDD_HHMMSS/`
2. Exports all keybindings to `.dconf` files
3. Saves dock configuration
4. Creates readable `.txt` files for easy viewing
5. Creates a `latest` symlink for quick access

**Output files:**
```
backups/backup_20260131_143022/
├── org.gnome.desktop.wm.keybindings.dconf
├── org.gnome.mutter.keybindings.dconf
├── org.gnome.settings-daemon.plugins.media-keys.dconf
├── org.gnome.shell.keybindings.dconf
├── custom-keybindings.dconf
├── favorite-apps.txt
├── org.gnome.shell.dconf
├── dash-to-dock.dconf (if installed)
├── keybindings_readable.txt
├── dock_readable.txt
└── metadata.txt
```

### Restore Script

Run interactively:
```bash
./restore_keybindings.sh
```

**Interactive prompts:**

1. **Select backup** - Choose which backup to restore from
2. **Select scope** - Choose what to restore:
   - Option 1: Custom keybindings only
   - Option 2: All keybindings (system + custom)
   - Option 3: Dock configuration only
   - Option 4: Everything (all keybindings + dock)
3. **Restart GNOME Shell** - Optional, to apply changes immediately

## 🔧 Transfer Between Machines

### Method 1: Git Repository (Recommended)
```bash
# On old machine
./backup_keybindings.sh
git add backups/
git commit -m "Backup keybindings and dock config"
git push

# On new machine
git pull
./restore_keybindings.sh
```

### Method 2: Direct Copy
```bash
# Copy backups directory to new machine
scp -r backups/ user@newmachine:/home/ecloaiza/devops/github/linux_dotfiles/scripts/linux/keybindings/

# On new machine
./restore_keybindings.sh
```

### Method 3: Cloud Sync
Place the entire `keybindings/` directory in Dropbox, Google Drive, or similar.

## ⚠️ Important Notes

### Custom Keybindings
- The scripts focus on preserving your **custom keybindings**
- Custom keybindings are often the most problematic to import manually
- The restore script gives you the option to restore only custom ones

### GNOME Shell Restart
- On **X11**: GNOME Shell can restart automatically
- On **Wayland**: You need to log out and back in for changes to take full effect
- The script will detect your session type and advise accordingly

### Compatibility
- Tested on Ubuntu 20.04, 22.04, and 24.04
- Works with GNOME desktop environment
- Compatible with Dash-to-Dock and Dash-to-Panel extensions

## 🐛 Troubleshooting

### Keybindings don't work after restore
1. Log out and log back in
2. Check if the application for custom keybindings is installed
3. Verify the backup contains the keybindings:
   ```bash
   cat backups/latest/keybindings_readable.txt
   ```

### Dock icons missing
1. Check if the applications are installed on the new machine
2. Install missing applications
3. Run restore script again

### Permission denied
```bash
chmod +x backup_keybindings.sh restore_keybindings.sh
```

### No backups found
Make sure you run the backup script first:
```bash
./backup_keybindings.sh
```

## 📊 Viewing Backups

### Human-readable format:
```bash
# View all keybindings
cat backups/latest/keybindings_readable.txt

# View dock configuration
cat backups/latest/dock_readable.txt

# View backup metadata
cat backups/latest/metadata.txt
```

### Raw dconf format:
```bash
# Custom keybindings
cat backups/latest/custom-keybindings.dconf

# Favorite apps
cat backups/latest/favorite-apps.txt
```

## 🔍 Manual Inspection

Before restoring, you can inspect what will be restored:

```bash
# List all backups
ls -lh backups/

# Check a specific backup
cat backups/backup_20260131_143022/metadata.txt
cat backups/backup_20260131_143022/keybindings_readable.txt
```

## 💡 Tips

1. **Regular backups**: Run backup script before major system changes
2. **Version control**: Commit backups to git for history tracking
3. **Test restore**: Test on a VM before applying to production machine
4. **Custom keybindings**: Document your custom keybindings in comments
5. **App dependencies**: Keep a list of applications your custom keybindings depend on

## 📝 Example Workflow

```bash
# Old Machine Setup
cd /home/ecloaiza/devops/github/linux_dotfiles/scripts/linux/keybindings
./backup_keybindings.sh
git add backups/
git commit -m "Backup from old-laptop"
git push

# New Machine Setup
cd /home/ecloaiza/devops/github/linux_dotfiles/scripts/linux/keybindings
git pull
./restore_keybindings.sh
# Select: [1] latest
# Select: [4] Everything
# Select: [y] Restart GNOME Shell
# Log out and back in for full effect
```

## 🆘 Support

If you encounter issues:
1. Check the troubleshooting section above
2. Verify Ubuntu version compatibility
3. Check backup files exist and are not corrupted
4. Ensure you have necessary permissions

## 📜 License

MIT License - Feel free to modify and share!

---

**Author:** ecloaiza  
**Created:** 2026-01-31  
**Last Updated:** 2026-01-31
