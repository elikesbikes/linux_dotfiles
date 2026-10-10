#!/usr/bin/env bash
# NFS setup for restic on endurance, the way the restic project is designed: NO fstab. A root cron job runs
# host/nfs-auto-mount.sh every 5 minutes (mounts when the NAS answers, detaches a stale mount, never hangs).
# Run ON endurance by the owner (needs sudo):
#
#     sudo bash ~/scripts/restic/endurance-nfs-setup.sh
#
# Prerequisite (on the NAS, by hand): the NFS export /mnt/PROD1/nfs_restic/nfs_endurance2 for 192.168.5.46
# (read-write, files owned by uid 1000). homeidrive (.52) is DR only and never used here.
#
# Idempotent. It:
#   1. installs nfs-common if missing
#   2. removes an endurance2 line from /etc/fstab if an earlier version of this script added one (fstab saved first)
#   3. writes ~owner/.nfs-mount.env (the entry nfs-auto-mount.sh reads), owned by ecloaiza
#   4. adds the root cron line:  */5 * * * * .../host/nfs-auto-mount.sh >> /var/log/nfs-auto-mount.log 2>&1
#   5. runs the mount script once, checks the mount is NFS and writable by ecloaiza
#   6. links ~/devops/docker/restic/backup to the mount
# It never starts or stops restic: the pipeline does that, and its pre-flight refuses unless ./backup is NFS.
set -euo pipefail

NAS=192.168.5.51
EXPORT=/mnt/PROD1/nfs_restic/nfs_endurance2
MP=/mnt/homenas/nfs_restic/nfs_endurance2
OWNER=ecloaiza
HOME_DIR="/home/$OWNER"
SCRIPT="$HOME_DIR/devops/docker/restic/host/nfs-auto-mount.sh"
ENVF="$HOME_DIR/.nfs-mount.env"
LINK="$HOME_DIR/devops/docker/restic/backup"
CRON_LINE="*/5 * * * * $SCRIPT >> /var/log/nfs-auto-mount.log 2>&1"

[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
[ -x "$SCRIPT" ] || { echo "$SCRIPT not found - deploy restic first" >&2; exit 1; }

echo "==> 1. nfs-common"
dpkg -s nfs-common >/dev/null 2>&1 || apt-get install -y nfs-common

echo "==> 2. fstab (must not hold this mount)"
if grep -qsF " $MP " /etc/fstab; then
  cp -p /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d-%H%M%S)"
  grep -vF " $MP " /etc/fstab > /etc/fstab.new && cat /etc/fstab.new > /etc/fstab && rm -f /etc/fstab.new
  systemctl daemon-reload
  echo "    removed the $MP line from /etc/fstab (copy saved)"
else
  echo "    not in fstab: good"
fi

echo "==> 3. $ENVF"
cat > "$ENVF" <<ENV
NFS_MOUNTS="
$NAS|$EXPORT|$MP|rw,hard,timeo=600,retrans=5,noatime
"
NFS_PORT=2049
NFS_CONNECT_TIMEOUT_SECONDS=2
UMOUNT_TIMEOUT_SECONDS=30
ENV
chown "$OWNER:$OWNER" "$ENVF"; chmod 600 "$ENVF"

echo "==> 4. root cron"
if crontab -l 2>/dev/null | grep -qF "$SCRIPT"; then
  echo "    cron line already present"
else
  { crontab -l 2>/dev/null || true; echo "$CRON_LINE"; } | crontab -
  echo "    added: $CRON_LINE"
fi

echo "==> 5. run the mount script once and check"
mkdir -p "$MP"
"$SCRIPT" || true
FS="$(findmnt -T "$MP" -n -o FSTYPE 2>/dev/null || true)"
case "$FS" in nfs*) ;; *) echo "$MP is not an NFS mount ($FS) - see /var/log/nfs-auto-mount.log" >&2; exit 1;; esac
sudo -u "$OWNER" bash -c "t=\$(mktemp '$MP/.write-test.XXXXXX') && rm -f \"\$t\"" \
  || { echo "ecloaiza cannot write to $MP - fix the export permissions on the NAS" >&2; exit 1; }
echo "    $MP is NFS and writable by $OWNER"

echo "==> 6. link ./backup"
if [ -L "$LINK" ]; then
  [ "$(readlink "$LINK")" = "$MP/" ] || ln -sfn "$MP/" "$LINK"
elif [ -e "$LINK" ]; then
  echo "$LINK exists and is not a link - move it away first" >&2; exit 1
else
  sudo -u "$OWNER" ln -s "$MP/" "$LINK"
fi
ls -l "$LINK"
echo "DONE."
