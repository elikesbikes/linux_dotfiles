#!/usr/bin/env bash
# Consistent copies of the endurance databases, so restic backs up files that are complete (a live database
# file copied while it is being written can be torn).  Runs ON endurance as ecloaiza, read-only on the live data.
#
#   Honcho (Postgres)      docker exec honcho-db pg_dump -Fc          -> honcho-<date>.dump
#   Hermes (SQLite, *.db)  Python sqlite3 online backup                -> hermes-<name>-<date>.db
#   Open WebUI (SQLite)    Python sqlite3 online backup                -> open-webui-webui-<date>.db
#
# Output: ~/devops/docker/.db-dumps (mode 700). Each file is verified (pg_restore -l / PRAGMA integrity_check)
# before it counts; files older than KEEP_DAYS days are removed. One syslog line per run (tag hermes-db-dump).
# Exit 1 when anything failed, so the systemd unit shows as failed.
set -uo pipefail

OUT="${DUMP_DIR:-$HOME/devops/docker/.db-dumps}"
KEEP_DAYS="${KEEP_DAYS:-3}"
HERMES_DATA="${HERMES_DATA:-$HOME/devops/docker/hermes/data}"
WEBUI_DATA="${WEBUI_DATA:-$HOME/devops/docker/open-webui/data}"
STAMP="$(date +%Y%m%d)"
umask 077
mkdir -p "$OUT"; chmod 700 "$OUT"

ok=0; bad=0; msgs=()
note_ok()  { ok=$((ok+1)); echo "ok   $1 ($(du -h "$2" | cut -f1))"; }
note_bad() { bad=$((bad+1)); msgs+=("$1"); echo "FAIL $1" >&2; }

# --- Honcho: Postgres custom-format dump, verified by listing its contents
f="$OUT/honcho-$STAMP.dump"
if docker exec honcho-db pg_dump -U postgres -Fc postgres > "$f.part" 2>"$f.err" \
   && [ -s "$f.part" ] && docker exec -i honcho-db pg_restore -l < "$f.part" >/dev/null 2>&1; then
  mv -f "$f.part" "$f"; note_ok honcho "$f"
else
  rm -f "$f.part"; note_bad "honcho pg_dump failed: $(head -c 200 "$f.err" 2>/dev/null)"
fi
rm -f "$f.err"

# --- SQLite: online backup API (safe on a live WAL database), then integrity_check on the copy
sqlite_copy() {   # sqlite_copy <source db> <destination db>
  python3 - "$1" "$2" <<'PY'
import sqlite3, sys
src, dst = sys.argv[1], sys.argv[2]
s = sqlite3.connect(f"file:{src}?mode=ro", uri=True, timeout=30)
d = sqlite3.connect(dst)
s.backup(d)
r = d.execute("PRAGMA integrity_check").fetchone()[0]
d.close(); s.close()
sys.exit(0 if r == "ok" else 3)
PY
}
for src in "$HERMES_DATA"/*.db; do
  [ -f "$src" ] || continue
  name="hermes-$(basename "$src" .db)"; f="$OUT/$name-$STAMP.db"
  if sqlite_copy "$src" "$f.part" 2>"$f.err"; then mv -f "$f.part" "$f"; note_ok "$name" "$f"
  else rm -f "$f.part"; note_bad "$name sqlite backup failed: $(tail -n1 "$f.err" | head -c 200)"; fi
  rm -f "$f.err"
done
src="$WEBUI_DATA/webui.db"; f="$OUT/open-webui-webui-$STAMP.db"
if [ -f "$src" ]; then
  if sqlite_copy "$src" "$f.part" 2>"$f.err"; then mv -f "$f.part" "$f"; note_ok open-webui "$f"
  else rm -f "$f.part"; note_bad "open-webui sqlite backup failed: $(tail -n1 "$f.err" | head -c 200)"; fi
  rm -f "$f.err"
else
  note_bad "open-webui database not found: $src"
fi

# --- prune old copies (only files this script writes)
find "$OUT" -maxdepth 1 -type f \( -name 'honcho-*.dump' -o -name 'hermes-*.db' -o -name 'open-webui-*.db' \) -mtime +"$KEEP_DAYS" -delete

logger -t hermes-db-dump "ok=$ok failed=$bad ${msgs[*]:-}" 2>/dev/null || true
echo "done: $ok ok, $bad failed (in $OUT)"
[ "$bad" -eq 0 ]
