#!/bin/bash
# Refresh Claude OAuth access token before it expires.
# Root cause fix for recurring int-claude-oauth alerts.
# Access tokens expire every ~8-12h; this runs every 6h to stay ahead.

CREDS="$HOME/.claude/.credentials.json"
LOG="$HOME/.claude/token-refresh.log"

if [ ! -f "$CREDS" ]; then
    echo "$(date -Iseconds) ERROR: $CREDS missing" >> "$LOG"
    exit 1
fi

# Check if token is expired or will expire within 2 hours
expires_at=$(python3 -c "
import json
d = json.load(open('$CREDS')).get('claudeAiOauth', {})
print(d.get('expiresAt', 0))
")
now_ms=$(date +%s)000
margin_ms=7200000  # 2 hours

if [ "$expires_at" -gt "$(( now_ms + margin_ms ))" ] 2>/dev/null; then
    echo "$(date -Iseconds) SKIP: token still valid" >> "$LOG"
    exit 0
fi

# Refresh by making a minimal claude call
output=$(timeout 30 /home/ecloaiza/.local/bin/claude --print 'ok' 2>&1)
rc=$?

if [ $rc -eq 0 ]; then
    new_exp=$(python3 -c "
import json
from datetime import datetime, timezone
d = json.load(open('$CREDS')).get('claudeAiOauth', {})
exp = datetime.fromtimestamp(int(d.get('expiresAt',0))/1000, timezone.utc)
print(exp.isoformat())
")
    echo "$(date -Iseconds) OK: refreshed, new expiry $new_exp" >> "$LOG"
else
    echo "$(date -Iseconds) FAIL (rc=$rc): $output" >> "$LOG"
    exit 1
fi
