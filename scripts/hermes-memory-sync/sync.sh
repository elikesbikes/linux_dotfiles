#!/usr/bin/env bash
# Copy the owner's Claude Code memory (tars) to endurance as a READ-ONLY Hermes skill, so Hermes
# (Discord + chattars/Open WebUI) knows the same preferences, rules and project history.
#
#   sync.sh            build + copy (what the timer runs: every 15 min, 08:00-17:00)
#   sync.sh --dry-run  build only, print what would be sent, copy nothing
#
# What is sent: every ~/.claude/projects/*/memory/*.md (MEMORY.md indexes excluded; a generated index replaces
# them) plus ~/.claude/CLAUDE.md, flattened to references/<project>__<file>.md (Hermes reads references/*.md only,
# not subfolders). Every file passes hermes-config's secret-scan.sh first; a file that matches is SKIPPED and logged.
# One way only: tars -> endurance. On endurance the folder is mounted :ro into the container, so Hermes cannot
# change it. The folder name ends in _data so deploy-endurance.sh never touches it.
set -euo pipefail

SRC="$HOME/.claude/projects"
STAGE_ROOT="$HOME/.cache/hermes-memory-sync"
DEST="endurance:devops/docker/hermes/claude_memory_data/"
SCAN="$HOME/devops/projects/hermes-config/scripts/secret-scan.sh"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

log() { echo "$*"; logger -t hermes-memory-sync "$*"; }

[ -x "$SCAN" ] || { log "FAILED: secret scanner missing ($SCAN)"; exit 1; }

STAGE="$(mktemp -d "$STAGE_ROOT.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
SKILL="$STAGE/owner-context"
REF="$SKILL/references"
mkdir -p "$REF"

# frontmatter field (first match, quotes stripped); empty when absent
field() { awk -v k="$2" 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} { sub(/^[ \t]+/,"") } index($0,k":")==1 { sub("^"k":[ \t]*",""); gsub(/^"|"$/,""); print; exit }' "$1"; }

declare -A INDEX=()
SENT=0; SKIPPED=()

add() {  # add <source file> <reference name>
  local src="$1" name="$2" type desc
  if ! "$SCAN" "$src" >/dev/null 2>&1; then SKIPPED+=("$name"); return; fi
  cp "$src" "$REF/$name"
  type="$(field "$src" type)"; desc="$(field "$src" description)"
  case "$type" in user|feedback|project|reference) ;; *) type="other" ;; esac
  INDEX[$type]+="- \`references/$name\` — ${desc:-(no description)}"$'\n'
  SENT=$((SENT + 1))
}

add "$HOME/.claude/CLAUDE.md" "global__CLAUDE.md"
INDEX[other]=""   # CLAUDE.md has no frontmatter; it is listed under the owner instead
INDEX[user]="- \`references/global__CLAUDE.md\` — the owner's global Claude Code rules (identity, hosts, secrets, git, working style, app theme)"$'\n'"${INDEX[user]:-}"

for dir in "$SRC"/*/memory; do
  proj="$(basename "$(dirname "$dir")")"
  case "$proj" in -tmp*) continue ;; esac
  slug="${proj#-home-ecloaiza}"; slug="${slug#-}"; slug="${slug:-home}"
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "MEMORY.md" ] && continue
    add "$f" "${slug}__$(basename "$f")"
  done
done

cat > "$SKILL/SKILL.md" <<EOF
---
name: owner-context
description: "Who the owner (Emmanuel) is and how they want to work: their Claude Code memory (preferences, working rules, projects, references) and global CLAUDE.md, copied read-only from tars every 15 min, 08:00-17:00. Load it to tailor any answer to the owner, or when they mention past work, a host, a project or 'what Claude Code knows'."
---

# Owner context (from Claude Code)

Read-only copy of the owner's Claude Code memory, refreshed from tars every 15 minutes between 08:00 and 17:00
(last refresh: $(date '+%Y-%m-%d %H:%M %Z')). Hermes cannot edit it; to change a fact, the owner tells Claude Code.

How to use:
- Always respect the **feedback** entries (how the owner wants you to work) and the **user** entries.
- For anything about a project, host or past decision, open the matching file with
  \`skill_view(name="owner-context", file_path="references/<file>")\`; the project and reference list is in
  \`references/_index-projects.md\`.
- Entries are dated notes, true when written. Check before acting on one; newer Honcho memory or the owner's
  own words win.
- Names in a file prefix are Claude Code project folders (e.g. \`devops-github-adastra__\` = the homelab docs repo).

## About the owner (user)
${INDEX[user]:-(none)}
## How the owner wants you to work (feedback)
${INDEX[feedback]:-(none)}
EOF

{
  echo "# Projects and references (Claude Code memory)"
  echo
  echo "## Projects"; echo "${INDEX[project]:-(none)}"
  echo "## References"; echo "${INDEX[reference]:-(none)}"
  echo "## Other"; echo "${INDEX[other]:-(none)}"
} > "$REF/_index-projects.md"

MSG="$SENT files staged, ${#SKIPPED[@]} skipped by the secret scan${SKIPPED:+: ${SKIPPED[*]}}"
if [ "$DRY" = 1 ]; then
  log "DRY RUN: $MSG (nothing copied); staging: $STAGE"
  du -sh "$SKILL"; ls "$REF" | wc -l
  trap - EXIT; echo "kept for inspection: $STAGE"
  exit 0
fi

rsync -a --delete --chmod=D755,F644 -e "ssh -o BatchMode=yes -o ConnectTimeout=10" "$STAGE/" "$DEST" \
  || { log "FAILED: rsync to endurance ($MSG)"; exit 1; }
log "synced to endurance: $MSG"
