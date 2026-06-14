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
| docker-prod-1 | 192.168.5.24   |
| endurance     | 192.168.5.30   |
| gargantua     | 192.168.5.110  |
| ranger0       | 192.168.5.16   |
| ranger1       | 192.168.5.35   |
| tars          | 192.168.5.127  |
| trainerroad2  | 192.168.5.176  |

## What happens if you push FROM one of those machines

The pipeline SSHes back into the same machine and runs `git reset --hard origin/main`.
Since the files already match what was just pushed, nothing changes. Harmless.


## Adding a New Host

When adding a new host to the deployment pipeline:

1. **SSH key setup (CRITICAL)**
   - The host MUST have the `gitlab-ci-dotfiles` deploy key in `~/.ssh/authorized_keys`
   - Simply having any SSH key is not enough — must be the specific GitLab CI/CD key
   - Copy from an existing host: `ssh existing-host "cat ~/.ssh/authorized_keys" | ssh new-host "cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"`

2. **Clone the repo**
   - `git clone https://github.com/elikesbikes/linux_dotfiles.git ~/devops/github/linux_dotfiles`

3. **Update PIPELINE.md & .gitlab-ci.yml**
   - Add host to machines table (alphabetical)
   - Add SSH deployment step to pipeline

4. **Test**
   - Push a test commit to verify the host receives updates

### Troubleshooting Pipeline Failures

**"Permission denied (publickey)" for a new host?**
- Check `~/.ssh/authorized_keys` contains the `gitlab-ci-dotfiles` key specifically
- Other keys (endurance, case, github-actions) alone will NOT work for the pipeline
- Copy the full `authorized_keys` from a working host to fix

## Files

| File | Purpose |
|------|---------|
| `.gitlab-ci.yml` | Pipeline definition |
| `SSH_PRIVATE_KEY` | CI/CD variable in GitLab — private key used to SSH into each machine |
