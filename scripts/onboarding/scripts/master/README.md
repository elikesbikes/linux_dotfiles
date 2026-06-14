# Master Onboarding Menu

The interactive entry point (`master.sh`). It orchestrates install / verify / uninstall across all categories using a `gum`-powered menu.

## 1. UX

- Powered by `gum` (auto-installed on first run if missing)
- Explicit confirmation flow; nothing runs hidden behind the menu
- Output is shown directly to the terminal
- Terminfo guard: falls back to `xterm-256color` if `$TERM` has no terminfo entry
  (e.g. SSH from a Kitty terminal into a host without `kitty-terminfo`)

## 2. Features

- **Install by category** — multi-select `core`, `cli`, `desktop`, `security`, `extensions`
- **Verify by category** — runs the matching audit-only verify script
- **Uninstall by category** — runs any `uninstall_*.sh` present in a category

## 3. How It Works

- Auto-discovers and runs every `install_*.sh` in the chosen category directory
- A failing installer is reported and skipped — it does not tear down the menu
- The category marker under `installed/` is written **only if all** installers succeed
- Verification routing:
  - `extensions` → `scripts/extensions/verify_extensions.sh`
  - all others → `scripts/verify/verify_<category>.sh`

## 4. State Tracking

Installed categories and tools are tracked under:

```
~/.local/state/onboarding/installed/
```

Logs are written under `~/.local/state/onboarding/logs/`.

## 5. Usage

```bash
bash master.sh
```
