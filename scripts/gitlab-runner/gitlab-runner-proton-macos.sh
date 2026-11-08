#!/usr/bin/env bash
# GitLab Runner on macOS (kipp) whose token never touches disk. macOS twin of gitlab-runner-proton.sh.
#
# macOS has no TPM and no RAM-backed /run, so:
#   - the Proton PAT comes from ~/.secrets/proton-pass-pat (kipp's accepted no-TPM fallback);
#   - the runner token (HOMELAB item "gitlab-runner token - <short hostname>") and the pass-cli session
#     live on a small RAM disk mounted at ~/.gitlab-runner-ram/mnt (parent folder mode 700), gone at reboot.
# The token is not passed through the environment (`run-single`): shell jobs inherit the runner's
# environment and could print it. Started by the LaunchAgent com.elikesbikes.gitlab-runner-proton.plist.
set -euo pipefail

HOST="$(hostname -s)"
PASS_CLI="$HOME/.local/bin/pass-cli"
RUNNER="/opt/homebrew/opt/gitlab-runner/bin/gitlab-runner"
PAT_FILE="$HOME/.secrets/proton-pass-pat"
VAULT="HOMELAB"
ITEM="gitlab-runner token - $HOST"
BASE="$HOME/.gitlab-runner-ram"
MNT="$BASE/mnt"
CONF="$MNT/config.toml"

umask 077
mkdir -p "$MNT"
chmod 700 "$BASE"

# Reuse the RAM disk if launchd restarted us; otherwise create one (8 MB).
if ! mount | grep -qF " on $MNT ("; then
    dev="$(hdiutil attach -nomount ram://16384 2>/dev/null | awk '{print $1}')"
    [[ "$dev" == /dev/disk* ]] || { echo "could not create a RAM disk" >&2; exit 1; }
    diskutil erasevolume HFS+ gitlab-runner-ram "$dev" >/dev/null
    diskutil unmount "$dev" >/dev/null
    diskutil mount -mountPoint "$MNT" "$dev" >/dev/null
    mount | grep -qF " on $MNT (" || { echo "RAM disk did not mount on $MNT" >&2; exit 1; }
fi

export PROTON_PASS_KEY_PROVIDER=fs
export PROTON_PASS_SESSION_DIR="$MNT/pass-session"
export PROTON_PASS_AGENT_REASON="Starting GitLab Runner on $HOST"

PROTON_PASS_PERSONAL_ACCESS_TOKEN="$(cat "$PAT_FILE")" "$PASS_CLI" login >/dev/null
token="$("$PASS_CLI" item view --vault-name "$VAULT" --item-title "$ITEM" --field note)"
"$PASS_CLI" logout >/dev/null 2>&1 || true
rm -rf "$PROTON_PASS_SESSION_DIR"
[[ "$token" == glrt-* ]] || { echo "Proton item '$ITEM' is missing or not a runner token" >&2; exit 1; }

cat > "$CONF" <<EOF
concurrent = 1
check_interval = 0
shutdown_timeout = 0

[session_server]
  session_timeout = 1800

[[runners]]
  name = "$HOST-shell"
  url = "https://gitlab.home.elikesbikes.com"
  token = "$token"
  executor = "shell"
  # 1 (the default) makes the runner log a "long polling issues" warning at every start
  request_concurrency = 2
EOF
unset token

exec "$RUNNER" run --config "$CONF" --working-directory "$HOME" --syslog
