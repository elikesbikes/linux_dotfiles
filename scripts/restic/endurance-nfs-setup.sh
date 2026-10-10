#!/usr/bin/env bash
# One-time NFS setup for restic on endurance. Run ON endurance by the owner (needs sudo):
#
#     sudo bash ~/scripts/restic/endurance-nfs-setup.sh
#
# Prerequisite (on the NAS, by hand): an NFS export  /mnt/PROD1/nfs_restic/nfs_endurance2  that allows 192.168.5.46
# (endurance), read-write, mapall/maproot so that the files are owned by the owner's uid on the share.
# homeidrive (.52) is for disaster recovery only and is never used here.
#
# What it does (idempotent, safe to re-run):
#   1. installs nfs-common if missing (apt-get)
#   2. checks the NAS answers on 2049 - stops if not (nothing is changed before this check)
#   3. creates the mount point and adds ONE line to /etc/fstab (a copy of fstab is saved first)
#   4. mounts it and checks that it is really NFS and writable by ecloaiza
#   5. links ~/devops/docker/restic/backup to the mount (as ecloaiza)
# It does NOT start restic: that is done by the pipeline (gacp_tutorials_wcopy restic "..." endurance), whose
# pre-flight refuses to deploy unless ./backup is an NFS mount.
set -euo pipefail

NAS=192.168.5.51
EXPORT=/mnt/PROD1/nfs_restic/nfs_endurance2
MP=/mnt/homenas/nfs_restic/nfs_endurance2
OWNER=ecloaiza
LINK="/home/$OWNER/devops/docker/restic/backup"
FSTAB_LINE="$NAS:$EXPORT $MP nfs rw,noatime,vers=3,_netdev,nofail 0 0"

[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }

echo "==> 2. is the NAS reachable on 2049?"
timeout 5 bash -c "exec 3<>/dev/tcp/$NAS/2049" 2>/dev/null || { echo "NAS $NAS does not answer on 2049 (is it up? it shuts down at 5 PM). Nothing changed." >&2; exit 1; }

echo "==> 1. nfs-common"
dpkg -s nfs-common >/dev/null 2>&1 || apt-get install -y nfs-common

echo "==> 3. mount point and fstab"
mkdir -p "$MP"
if ! grep -qsF " $MP " /etc/fstab; then
  cp -p /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d-%H%M%S)"
  echo "$FSTAB_LINE" >> /etc/fstab
  echo "    added: $FSTAB_LINE"
else
  echo "    fstab already has an entry for $MP"
fi
systemctl daemon-reload

echo "==> 4. mount and check"
mountpoint -q "$MP" || mount "$MP"
FS="$(findmnt -T "$MP" -n -o FSTYPE)"; case "$FS" in nfs*) ;; *) echo "not NFS ($FS) - stopping" >&2; exit 1;; esac
sudo -u "$OWNER" bash -c "t=\$(mktemp '$MP/.write-test.XXXXXX') && rm -f \"\$t\"" \
  || { echo "ecloaiza cannot write to $MP - fix the export permissions on the NAS" >&2; exit 1; }
echo "    $MP is NFS and writable by $OWNER"

echo "==> 5. link ./backup"
if [ -L "$LINK" ]; then
  [ "$(readlink "$LINK")" = "$MP/" ] || ln -sfn "$MP/" "$LINK"
elif [ -e "$LINK" ]; then
  echo "$LINK exists and is not a link - move it away first" >&2; exit 1
else
  sudo -u "$OWNER" ln -s "$MP/" "$LINK"
fi
ls -l "$LINK"
echo "DONE. Next: gacp_tutorials_wcopy restic \"first restic deploy on endurance\" endurance   (from tars, then play preflight and deploy jobs)"
