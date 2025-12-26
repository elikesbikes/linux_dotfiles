# Onboarding Themes

Author: Tars (ELIKESBIKES)

## Purpose

This directory contains **user-level theme scripts** for Brave, intended for
onboarding and dotfiles workflows.

Design goals:
- HOME directory only
- No `/etc`
- No managed policies
- No automatic installs
- Deterministic, reversible, logged

---

## Available Themes

### Catppuccin Macchiato
Script: `apply_brave_catppuccin_macchiato.sh`

What it does:
- Targets the Brave Default profile
- Backs up the Preferences file
- Applies Catppuccin Macchiato colors to `theme.color_palette`
- Verifies the change
- Logs execution

### Catppuccin Mocha
Script: `apply_brave_catppuccin_mocha.sh`

Same behavior, different palette.

---

## Usage

1. Close Brave completely
2. Run the desired script
3. Restart Brave

---

## Notes

- These scripts do not install theme extensions.
- Brave UI must not be set to "Use system theme" for colors to appear.
- Backups are stored under:
  `~/.local/state/onboarding/backups/brave/`
