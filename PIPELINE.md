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
| hailmary | deploy-hailmary | hailmary-shell (9)   | Proton Pass only (`gitlab-runner token - hailmary`), config in RAM |
| murph    | deploy-murph    | murph-shell (12)     | Proton Pass only (`gitlab-runner token - murph`), config in RAM |
| rocky    | deploy-rocky    | rocky-shell (8)      | Proton Pass only (`gitlab-runner token - rocky`), config in RAM |

Other hosts (tars, case, gargantua, …) are **not** updated by the pipeline; pull them by hand
(`gpull_dotfiles`). A host whose runner is offline leaves its job pending until the runner comes back.

## Runner tokens: never on disk (all three hosts)

No runner token is stored on disk (murph since 2026-11-08 10:36; rocky and hailmary since 11:40, when
their tokens were reset and the old `~/.gitlab-runner/config.toml` shredded). Each host runs:

- `scripts/gitlab-runner/gitlab-runner-proton.sh` unseals the PAT, reads the HOMELAB item
  `gitlab-runner token - <short hostname>`, writes `config.toml` to `$XDG_RUNTIME_DIR/gitlab-runner/`
  (RAM), logs pass-cli out and starts the runner. It sets `umask 077` only while writing the config and
  goes back to `umask 022` before starting the runner: jobs inherit the runner's umask, and 077 made every
  deployed file owner-only (fixed in v1.15.2).
- `scripts/gitlab-runner/gitlab-runner-proton.service` runs it as a systemd **user** service
  (linger is on), linked into `~/.config/systemd/user/`.
- murph's runner serves **linux_dotfiles and adastra** (adastra's `deploy-murph` since 2026-11-08), is
  **locked** (no other projects) and runs **protected branches only** (`main`), set with
  `PUT /api/v4/runners/12` (`locked=true`, `access_level=ref_protected`).
- murph's dotfiles job fetches from the `gitlab` remote with murph's own GitLab token (git credential helper,
  `protonpass.hostItems true`).
- murph's Claude Code hooks (SSHTars) live in `~/.claude/settings.json`, a separate file the reset
  does not touch.

## The other homelab runners (2026-11-08)

The same rule now covers every runner, not only the three deploy hosts. Each token was reset through the
GitLab API straight into its Proton item (never printed) and the old on-disk config was shredded.

| Runner (id) | Host | Executor | Proton item | How it starts |
|-------------|------|----------|-------------|---------------|
| tars-shell (10) | tars | shell | `gitlab-runner token - tars` | `gitlab-runner-proton.service` (old `gitlab-runner-tars.service` disabled) |
| endurance-shell (11) | endurance | shell | `gitlab-runner token - endurance` | `gitlab-runner-proton.service` |
| kipp (3) | kipp (macOS) | shell | `gitlab-runner token - kipp` | LaunchAgent `com.elikesbikes.gitlab-runner-proton` runs `gitlab-runner-proton-macos.sh`: PAT from `~/.secrets/proton-pass-pat` (no TPM on macOS), config on an 8 MB RAM disk at `~/.gitlab-runner-ram/mnt` |
| rocky-docker (6) | rocky | docker | `gitlab-runner token - rocky-docker` | container with a tmpfs `/etc/gitlab-runner`; `gitlab-runner-docker-proton.service` pipes in `docker-rocky.toml` with the token |
| homelab-docker-runner (1) | hailmary | docker | `gitlab-runner token - hailmary-docker` | same, template `docker-hailmary.toml`; the container is the `gitlab-runner` service of the GitLab compose project |

Docker runners: the container starts with an empty tmpfs and logs "Failed to load config" until the host
service injects it, which it does again after every container start (`docker events`). Rotate a token by
resetting it through the API into its Proton item, then restart the service (shell, docker) or the
LaunchAgent (kipp).

## Adding a New Host

1. **Clone the repo** to `~/devops/github/linux_dotfiles` and add the GitLab remote:
   `git remote add gitlab https://gitlab.home.elikesbikes.com/ecloaiza/linux_dotfiles.git`
2. **Install GitLab Runner** in `~/.local/bin` (same version as rocky; check the sha256 against
   `release.sha256` on the download bucket).
3. **Create the runner** in GitLab (project runner for `ecloaiza/linux_dotfiles`, tags `shell,<host>`,
   untagged jobs off) with `POST /api/v4/user/runners`, then lock it to the project and to protected
   branches (`PUT /api/v4/runners/<id>` with `locked=true`, `access_level=ref_protected`). Store its token:
   only in Proton (`gitlab-runner token - <host>`) and start it with `gitlab-runner-proton.service`.
   Never keep it in `~/.gitlab-runner/config.toml`.
4. **Add a `deploy-<host>` job** to `.gitlab-ci.yml` (copy an existing one, change the tag) and add the
   host to the table above.
5. **Test**: push and check the job log shows BEFORE/AFTER on the new host.

## Files

| File | Purpose |
|------|---------|
| `.gitlab-ci.yml` | Pipeline definition (one job per host) |
| `scripts/sync-sudoers-ci.sh` | Installs `sudoers/sudoers.d/` when it changed (NOPASSWD on each host) |
| `scripts/gitlab-runner/gitlab-runner-proton.sh` / `.service` | Shell runner start with the token from Proton (rocky, hailmary, murph, tars, endurance) |
| `scripts/gitlab-runner/gitlab-runner-proton-macos.sh` / `com.elikesbikes.gitlab-runner-proton.plist` | Same for kipp (macOS, RAM disk) |
| `scripts/gitlab-runner/gitlab-runner-docker-proton.sh` / `.service` | Injects a Docker runner's config into its tmpfs (rocky, hailmary) |
| `scripts/gitlab-runner/docker-rocky.toml`, `docker-hailmary.toml` | Docker runner config templates (`@TOKEN@`, no secret) |
