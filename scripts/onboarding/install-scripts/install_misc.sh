#!/bin/bash
echo "=== Starting Miscellaneous Apps Installation ==="

# Ensure Flatpak is set up
sudo apt update
sudo apt install -y flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# -----------------------------------------------------------
# 1. Pure Flatpak Installs
# -----------------------------------------------------------
echo "--- Installing Flatpak Applications ---"

# Caffeine (Prevents screen lock)
flatpak install -y flathub io.github.mightycreak.Caffeine

# Cryptomator (Cloud encryption)
flatpak install -y flathub org.cryptomator.Cryptomator

# Flameshot (Screenshots)
flatpak install -y flathub org.flameshot.Flameshot

# Fluent Reader (RSS)
flatpak install -y flathub me.hyliu.fluentreader

# Resources (System Monitor)
flatpak install -y flathub net.nokyan.Resources

# Syncthingy (Syncthing Tray Wrapper)
flatpak install -y flathub com.github.zocker_160.SyncThingy

# Todoist
flatpak install -y flathub com.todoist.Todoist

# Yubico Authenticator (TOTP Codes)
flatpak install -y flathub com.yubico.yubioath

# -----------------------------------------------------------
# 2. Native System Installs (APT)
# -----------------------------------------------------------
echo "--- Installing System/Hardware Tools (Native) ---"

# Timeshift
# NOTE: Timeshift must be installed natively to access the file system
# for backups. It does not work as a Flatpak.
sudo apt install -y timeshift

# Yubikey Manager
# NOTE: The 'Manager' (configuration tool) is different from the 'Authenticator'.
# It usually requires native USB access rules that Flatpaks struggle with.
sudo apt install -y yubikey-manager-qt

# -----------------------------------------------------------
# 3. Uncertain / Missing Items
# -----------------------------------------------------------

# "Clapgrep"
# ERROR: No package found by this name.
# Did you mean "Clipgrab" (video downloader) or "Czkawka" (cleaner)?
# Uncomment below if you meant Clipgrab:
# flatpak install -y flathub org.clipgrab.Clipgrab

# "Gemini Desktop"
# NOTE: There is no official Google Gemini app on Flathub yet.
# Most "Gemini" apps are for the Gemini *Protocol* (like Lagrange),
# or they are unofficial Electron wrappers not hosted on Flathub.
# I recommend using Gemini in a browser (PWA) for now.

echo "=== Miscellaneous Apps Installation Complete ==="
