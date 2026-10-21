#!/usr/bin/env bash
# Refresh the GitLab DEV replica on rocky from PROD on hailmary.
#
# What it does (run from tars, which can SSH to both hosts):
#   1. Checks prod's GitLab version equals the version pinned on rocky. A GitLab backup
#      only restores into the exact same version, so a mismatch stops here.
#   2. Runs an online `gitlab-backup create` on hailmary (prod keeps running).
#   3. Streams the backup tar + gitlab-secrets.json to rocky and checks sha256 on both sides.
#   4. On rocky: stops puma/sidekiq, restores (force), puts prod's gitlab-secrets.json in
#      place (without it, CI variables and 2FA secrets cannot be decrypted), restarts.
#   5. Deletes the backup tar on both hosts and runs gitlab:doctor:secrets.
#
# Expected noise during step 4: "ERROR: must be owner of extension pg_trgm/btree_gist/amcheck".
# The restore runs as the non-superuser gitlab DB user; GitLab documents these as safe to ignore
# (support.gitlab.com article 20512506736412).
#
# EVERYTHING on the rocky replica is overwritten. Dev-only changes are lost.
# Usage: refresh-gitlab-rocky.sh --yes
set -euo pipefail

PROD=hailmary
DEV=rocky
DEV_DIR=devops/docker/gitlab        # relative to ecloaiza's home on rocky
NAME="replica_rocky_$(date +%Y%m%d_%H%M%S)"
TAR="${NAME}_gitlab_backup.tar"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { log "ERROR: $*"; exit 1; }

[ "${1:-}" = "--yes" ] || die "this overwrites the GitLab replica on $DEV. Re-run with --yes."

cleanup() {
  ssh "$PROD" "docker exec gitlab rm -f /var/opt/gitlab/backups/$TAR" || true
  ssh "$DEV" "rm -f ~/$DEV_DIR/restore-staging/$TAR; docker exec gitlab rm -f /var/opt/gitlab/backups/$TAR" || true
}
trap cleanup EXIT

# 1. Version gate: the rocky image tag is pinned in its docker-compose.yml.
prod_ver=$(ssh "$PROD" "docker exec gitlab cat /opt/gitlab/embedded/service/gitlab-rails/VERSION")
dev_ver=$(ssh "$DEV" "docker exec gitlab cat /opt/gitlab/embedded/service/gitlab-rails/VERSION")
log "prod=$prod_ver dev=$dev_ver"
[ "$prod_ver" = "$dev_ver" ] || die "version mismatch. Bump the image pin in ~/$DEV_DIR/docker-compose.yml on $DEV to ${prod_ver}-ce.0, run ./start.sh there, then re-run this."

# 2. Online backup on prod.
log "creating backup $NAME on $PROD (online)"
ssh "$PROD" "docker exec gitlab gitlab-backup create STRATEGY=copy BACKUP=$NAME" | tail -1

# 3. Stream to rocky through tars (hosts do not share SSH keys) and verify.
log "copying backup + gitlab-secrets.json to $DEV"
ssh "$DEV" "mkdir -p -m 700 ~/$DEV_DIR/restore-staging"
ssh "$PROD" "docker exec gitlab cat /var/opt/gitlab/backups/$TAR" | ssh "$DEV" "cat > ~/$DEV_DIR/restore-staging/$TAR"
ssh "$PROD" "docker exec gitlab cat /etc/gitlab/gitlab-secrets.json" | ssh "$DEV" "umask 077; cat > ~/$DEV_DIR/restore-staging/gitlab-secrets.json"
src=$(ssh "$PROD" "docker exec gitlab sha256sum /var/opt/gitlab/backups/$TAR /etc/gitlab/gitlab-secrets.json" | awk '{print $1}')
dst=$(ssh "$DEV" "sha256sum ~/$DEV_DIR/restore-staging/$TAR ~/$DEV_DIR/restore-staging/gitlab-secrets.json" | awk '{print $1}')
[ "$src" = "$dst" ] || die "checksum mismatch after copy"

# 4. Restore on rocky.
log "restoring on $DEV"
ssh "$DEV" "set -e; cd ~/$DEV_DIR
  docker cp restore-staging/$TAR gitlab:/var/opt/gitlab/backups/$TAR
  docker exec gitlab chown git:git /var/opt/gitlab/backups/$TAR
  docker exec gitlab gitlab-ctl stop puma
  docker exec gitlab gitlab-ctl stop sidekiq
  docker exec gitlab gitlab-backup restore BACKUP=$NAME force=yes | tail -1
  docker cp restore-staging/gitlab-secrets.json gitlab:/etc/gitlab/gitlab-secrets.json
  docker exec gitlab chown root:root /etc/gitlab/gitlab-secrets.json
  docker exec gitlab chmod 600 /etc/gitlab/gitlab-secrets.json
  rm -f restore-staging/gitlab-secrets.json
  docker restart gitlab >/dev/null"

log "waiting for $DEV GitLab to become healthy"
ssh "$DEV" 'for i in $(seq 1 60); do [ "$(docker inspect gitlab --format "{{.State.Health.Status}}")" = healthy ] && exit 0; sleep 10; done; exit 1' \
  || die "GitLab on $DEV not healthy after 10 min: docker logs gitlab"

# 5. Every encrypted column must decrypt with the copied secrets.
fails=$(ssh "$DEV" "docker exec gitlab gitlab-rake gitlab:doctor:secrets 2>&1" | grep -cE 'failures: [1-9]' || true)
[ "$fails" = 0 ] || die "gitlab:doctor:secrets reported failures on $DEV"
log "done: https://gitlab-rocky.home.elikesbikes.com is a copy of prod as of $NAME"
