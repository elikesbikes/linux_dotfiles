# Dotfiles CI/CD Pipeline

## What this does

Every time you push dotfile changes, GitLab automatically syncs them to all machines in the homelab.

## Workflow

```
YOU run: gacp_dotfiles "message"
         ↓
git push → GitHub + GitLab
         ↓
--- GitLab pipeline takes over automatically ---
         ↓
SSH into each machine and run:
  git fetch origin && git reset --hard origin/main
         ↓
Symlinks pick up the changes instantly (no restart needed)
```

## Machines that get updated

| Machine   | IP             |
|-----------|----------------|
| endurance | 192.168.5.30   |
| ranger0   | 192.168.5.16   |
| tars      | 192.168.5.127  |

## What happens if you push FROM one of those machines

The pipeline SSHes back into the same machine and runs `git reset --hard origin/main`.
Since the files already match what was just pushed, nothing changes. Harmless.

## Files

| File | Purpose |
|------|---------|
| `.gitlab-ci.yml` | Pipeline definition |
| `SSH_PRIVATE_KEY` | CI/CD variable in GitLab — private key used to SSH into each machine |
