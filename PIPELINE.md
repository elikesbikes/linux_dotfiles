# Dotfiles CI/CD Pipeline

## What this does

Every push to `main` makes GitLab update the dotfiles checkout on each deploy host.

## Workflow

```
YOU run: gacp_dotfiles "message"
         ↓
git push → GitHub + GitLab
         ↓
--- GitLab pipeline takes over automatically ---
         ↓
One job per host, run by that host's own GitLab Runner (shell executor, user ecloaiza).
No SSH: each job runs on its host:
  cd ~/devops/github/linux_dotfiles
  git fetch gitlab main && git reset --hard gitlab/main
  (+ scripts/sync-sudoers-ci.sh when the last commit changed sudoers/)
         ↓
Symlinks pick up the changes instantly (no restart needed)
```

## Machines that get updated

| Host     | Job             | Runner (id)          | Where the runner token lives |
|----------|-----------------|----------------------|------------------------------|
| hailmary | deploy-hailmary | hailmary-shell (9)   | `~/.gitlab-runner/config.toml` |
| murph    | deploy-murph    | murph-shell (12)     | Proton Pass only (`gitlab-runner token - murph`); config.toml in RAM, see below |
| rocky    | deploy-rocky    | rocky-shell (8)      | `~/.gitlab-runner/config.toml` |

Other hosts (tars, case, gargantua, …) are **not** updated by the pipeline; pull them by hand
(`gpull_dotfiles`). A host whose runner is offline leaves its job pending until the runner comes back.

## murph: runner without a secret on disk

murph is a sandbox whose only allowed secret is its TPM-sealed Proton PAT, so its runner token
cannot sit in a `config.toml` on disk. Instead:

- `scripts/gitlab-runner/gitlab-runner-proton.sh` unseals the PAT, reads the HOMELAB item
  `gitlab-runner token - <short hostname>`, writes `config.toml` to `$XDG_RUNTIME_DIR/gitlab-runner/`
  (RAM), logs pass-cli out and starts the runner.
- `scripts/gitlab-runner/gitlab-runner-proton.service` runs it as a systemd **user** service
  (linger is on), linked into `~/.config/systemd/user/`.
- The runner is **locked** to this project and runs **protected branches only** (`main`), set with
  `PUT /api/v4/runners/12` (`locked=true`, `access_level=ref_protected`).
- The job fetches from the `gitlab` remote with murph's own GitLab token (git credential helper,
  `protonpass.hostItems true`).
- murph's Claude Code hooks (SSHTars) live in `~/.claude/settings.json`, a separate file the reset
  does not touch.

## Adding a New Host

1. **Clone the repo** to `~/devops/github/linux_dotfiles` and add the GitLab remote:
   `git remote add gitlab https://gitlab.home.elikesbikes.com/ecloaiza/linux_dotfiles.git`
2. **Install GitLab Runner** in `~/.local/bin` (same version as rocky; check the sha256 against
   `release.sha256` on the download bucket).
3. **Create the runner** in GitLab (project runner for `ecloaiza/linux_dotfiles`, tags `shell,<host>`,
   untagged jobs off) with `POST /api/v4/user/runners`, then lock it to the project and to protected
   branches (`PUT /api/v4/runners/<id>` with `locked=true`, `access_level=ref_protected`). Store its token:
   - normal host: in `~/.gitlab-runner/config.toml`, run by a `gitlab-runner` user service;
   - no-secrets host: only in Proton (`gitlab-runner token - <host>`), started with
     `gitlab-runner-proton.service`.
4. **Add a `deploy-<host>` job** to `.gitlab-ci.yml` (copy an existing one, change the tag) and add the
   host to the table above.
5. **Test**: push and check the job log shows BEFORE/AFTER on the new host.

## Files

| File | Purpose |
|------|---------|
| `.gitlab-ci.yml` | Pipeline definition (one job per host) |
| `scripts/sync-sudoers-ci.sh` | Installs `sudoers/sudoers.d/` when it changed (NOPASSWD on each host) |
| `scripts/gitlab-runner/gitlab-runner-proton.sh` / `.service` | Runner start with the token from Proton (murph) |
