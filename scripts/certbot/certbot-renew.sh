#!/usr/bin/env bash
# Renew the router certificate with the Cloudflare credentials from Proton Pass (HOMELAB vault),
# never from a file on disk.
#
#   certbot-renew.sh                # what cron runs (03:30 daily)
#   certbot-renew.sh --dry-run      # staging test; certbot skips deploy hooks on a dry run
#
# The renewal conf points dns_cloudflare_credentials at $CF_INI below: a file on tmpfs (RAM) that this
# script writes from Proton for the run and shreds on exit. The deploy hook (hooks/deploy_to_unifi.sh)
# reaches the router with this host's own key from the Proton SSH agent.
set -euo pipefail

CERTBOT_DIR="$HOME/.secrets/certbot"
CF_DIR="/run/user/$(id -u)/certbot"
CF_INI="$CF_DIR/cloudflare.ini"

source "$HOME/scripts/proton-pass/pass-secrets.sh"
pp_load certbot "Renewing certificates" \
    "CF_INI_CONTENT|certbot - cloudflare.ini (Global API key, router cert, $(hostname -s))|note"

umask 077
mkdir -p "$CF_DIR"
trap 'shred -u "$CF_INI" 2>/dev/null || rm -f "$CF_INI"' EXIT
printf '%s\n' "$CF_INI_CONTENT" > "$CF_INI"
unset CF_INI_CONTENT

# Daily canary (warning only): the deploy hook needs this host's key in the router's /root/.ssh/authorized_keys.
# A UniFi OS reset of that file would otherwise go unnoticed until the next renewal fails to deploy.
if ! ssh -o IdentityAgent="$HOME/.ssh/proton-pass-agent.sock" -o IdentitiesOnly=yes -i "$HOME/.ssh/id_ed25519.pub" \
        -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@192.168.5.1 true 2>/dev/null; then
    echo "WARNING: router SSH check failed (root@192.168.5.1 with $(hostname -s)'s key): the certificate deploy hook will fail. Check /root/.ssh/authorized_keys on the router." >&2
fi

/usr/bin/certbot renew \
    --config-dir "$CERTBOT_DIR/config" \
    --work-dir "$CERTBOT_DIR/work" \
    --logs-dir "$CERTBOT_DIR/logs" \
    --quiet "$@"
