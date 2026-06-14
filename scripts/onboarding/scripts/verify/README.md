# Verify

Audit-only verification scripts, one per category. They check that the expected tools/apps are present and **never modify the system**. Each exits with the number of failed checks (`0` = pass), which the master menu uses to report PASS/FAIL.

## 1. Scripts

| Script | Category | Strategy |
|--------|----------|----------|
| `verify_core.sh` | core | `command -v` for sudo, ssh, flatpak, kitty |
| `verify_cli.sh` | cli | `command -v` for each tool (exa **or** eza); `dpkg` for build-essential |
| `verify_desktop.sh` | desktop | `dpkg` (native), `snap list`, `flatpak list` |
| `verify_security.sh` | security | onboarding state markers (Proton package names vary) |

> The `extensions` category has its own verifier at `../extensions/verify_extensions.sh`.

## 2. Usage

Run from the master menu (**Verify system**) or directly:

```bash
bash verify_cli.sh
echo "exit code = $?"   # 0 = all checks passed
```

## 3. Notes

- Scripts use `set -uo pipefail` (no `-e`) so a single failing check is counted, not fatal
- Output is human-readable per item (`OK` / `MISSING`) with a summary line
- Master routes `verify_<category>.sh` here for core/cli/desktop/security
