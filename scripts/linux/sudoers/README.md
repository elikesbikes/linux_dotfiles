# sync-sudoers.sh

Syncs sudoers drop-in files from a homelab Git repo to `/etc/sudoers.d` using Unison. Handles both traditional `sudo` and `sudo-rs` (automatically detects which is installed and skips incompatible files).

## Prerequisites

- [`unison`](https://github.com/bcpierce00/unison) installed and configured with a `sudoers` profile at `~/.unison/sudoers.prf`
- Homelab repo cloned at `/home/ecloaiza/devops/github/homelab` with sudoers files under `sudoers.d/`
- `sudo` access

## Usage

```bash
./sync-sudoers.sh
```

No arguments needed. The script is interactive when there are uncommitted changes in the repo.

## What It Does

1. **Detects sudo implementation** — identifies `sudo-rs` vs traditional `sudo` and adjusts accordingly
2. **Checks Git status** — if there are uncommitted changes, prompts you to choose:
   - Commit and push them now
   - Stash them and pull latest
   - Sync locally only (skip git operations)
   - Abort
3. **Pulls latest** from the remote Git repo (unless skipped)
4. **Validates** all files with `visudo -c` before touching the system — aborts on any syntax error
5. **Copies Unison profile** to root's home (`/root/.unison/sudoers.prf`)
6. **Runs Unison** as root to sync files from the repo to `/etc/sudoers.d`
7. **Fixes permissions** — sets `0440 root:root` on all synced files

## sudo-rs Compatibility

When `sudo-rs` is detected, `00-defaults-logging` is automatically excluded from the sync since it uses directives not supported by `sudo-rs`. The exclusion is applied temporarily to the Unison profile and cleaned up after the sync.

## Source

Sudoers files live in the homelab repo:
```
/home/ecloaiza/devops/github/homelab/sudoers.d/
```
claude --resume 4642e37b-50cc-4405-8afb-95a6ce494d75