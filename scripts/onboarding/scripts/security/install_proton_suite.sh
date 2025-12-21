#!/bin/bash

echo "=== Starting Proton Suite Installation ==="

# 1. Install Flatpak (Requested explicitly)
echo "--- Installing Flatpak ---"
sudo apt update
sudo apt install -y flatpak gnome-software-plugin-flatpak

# Add the Flathub repository (needed for Mail and Pass)
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# 2. Setup Proton VPN Repository (Native)
# We need the native repo for VPN and Bridge to work correctly with system networking.
echo "--- Setting up Proton VPN Repository ---"
# Download the official repo setup file
wget -q -O protonvpn-repo.deb https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.4_all.deb

# Install the repo
sudo dpkg -i protonvpn-repo.deb
sudo apt update

# 3. Install Proton VPN & Proton Bridge (Native)
echo "--- Installing Proton VPN and Proton Bridge ---"
# proton-vpn-gnome is the GUI version
sudo apt install -y proton-vpn-gnome protonvpn-cli proton-bridge

# Cleanup the repo file
rm protonvpn-repo.deb

# 4. Install Proton Mail (via Flatpak)
# Using Flatpak is often more reliable for the Desktop app than finding the beta .deb
echo "--- Installing Proton Mail (Flatpak) ---"
flatpak install -y flathub com.proton.Mail

# 5. Install Proton Pass (via Flatpak)
echo "--- Installing Proton Pass (Flatpak) ---"
flatpak install -y flathub me.proton.Pass
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/<category>"

echo "=== Proton Suite Installation Complete ==="
echo "Note: You may need to restart your computer for the VPN system tray icons to appear correctly."
