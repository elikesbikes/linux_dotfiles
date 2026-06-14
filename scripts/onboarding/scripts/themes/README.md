# Onboarding Themes

User-level theme scripts for the Brave browser, intended for onboarding and dotfiles workflows.

Design goals: HOME directory only, no `/etc`, no managed policies, no automatic installs — deterministic, reversible, and logged.

## 1. Available Themes

| Script | Palette |
|--------|---------|
| `apply_brave_catppuccin_macchiato.sh` | Catppuccin Macchiato |
| `apply_brave_catppuccin_mocha.sh` | Catppuccin Mocha |

Each script:
- Targets the Brave **Default** profile
- Backs up the `Preferences` file (timestamped)
- Patches `theme.color_palette` with `jq`
- Verifies the change was written
- Logs execution

## 2. Usage

1. Close Brave completely (the script refuses to run while Brave is open)
2. Run the desired script:
   ```bash
   bash apply_brave_catppuccin_macchiato.sh
   ```
3. Restart Brave

## 3. Requirements

- `jq`, `pgrep`, `cp`, `mv`, `date` available on `PATH` (no auto-installs)
- An initialized Brave Default profile (launch Brave once first)

## 4. Notes

- These scripts do **not** install theme extensions
- Brave must not be set to "Use system theme" for colors to appear
- Backups are stored under `~/.local/state/onboarding/backups/brave/`
