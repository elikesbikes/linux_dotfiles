#!/bin/bash
echo "Installing Fastfetch..."

# --- EDIT BELOW ---

# Example for Ubuntu (PPA might be needed):
sudo add-apt-repository ppa:cason/fastfetch -y
sudo apt update
sudo apt install -y fastfetch

# Example for macOS (Homebrew):
# brew install fastfetch

# Example for Arch Linux:
# sudo pacman -S fastfetch

echo "Fastfetch installation script finished."
