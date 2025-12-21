# Core

Core performs foundational system setup and must be run first.

## Responsibilities
- Run `apt update`
- Install Flatpak and configure Flathub
- Ensure OpenSSH client is present

## Notes
- Core is the only category allowed to refresh apt repositories
- Third-party repositories are added explicitly and intentionally
