# Core Category

## Purpose
System foundations required by other categories. These scripts are safe to run first and are idempotent.

## What gets installed
- Flatpak runtime and Flathub remote (idempotent)
- OpenSSH client

## What does NOT happen
- No user applications
- No configuration changes
- No services enabled or restarted

## When to run
- Fresh installs
- Before Desktop or Security categories

## Scripts
- install_flatpak.sh
- install_ssh.sh

## Notes
Designed for Ubuntu 24.04 LTS.
