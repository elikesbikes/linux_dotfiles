#!/bin/bash
# Auto-commit hook for Claude Code sessions.
# Called by settings.json hooks to avoid /bin/sh vs /bin/bash portability issues.
# Usage: bash ~/.claude/hooks/auto-commit.sh <repo_dir> <gacp_func> [--sync] [--stop] [--stdin]

REPO_DIR="$1"
GACP_FUNC="$2"
shift 2

DO_SYNC=false
IS_STOP=false
READ_STDIN=false
for arg in "$@"; do
    case "$arg" in
        --sync) DO_SYNC=true ;;
        --stop) IS_STOP=true ;;
        --stdin) READ_STDIN=true ;;
    esac
done

if $READ_STDIN; then
    INPUT=$(cat)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
    if ! echo "$FILE" | grep -q "$REPO_DIR"; then
        exit 0
    fi
fi

cd "$REPO_DIR" || exit 0

# Detached HEAD or a half-finished rebase/merge: do NOT commit (that is how adastra silently stopped
# pushing for a week after 2026-10-06). Report it so someone fixes the repo.
GIT_DIR_PATH=$(git rev-parse --git-dir 2>/dev/null)
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
if [ -z "$CURRENT_BRANCH" ] || [ -d "$GIT_DIR_PATH/rebase-merge" ] || [ -d "$GIT_DIR_PATH/rebase-apply" ] || [ -f "$GIT_DIR_PATH/MERGE_HEAD" ]; then
    MSG_STUCK="GIT_STUCK: repo=$(basename "$REPO_DIR") host=$(hostname -s) is detached or mid-rebase/merge; auto-commit skipped. Fix the repo (finish or abort the rebase, check out main)."
    echo "$MSG_STUCK" >&2
    logger -n 192.168.5.25 -P 514 --udp -t claude-hook -p local0.warning "$MSG_STUCK" 2>/dev/null || true
    exit 0
fi
if [ "$CURRENT_BRANCH" != "main" ]; then
    exit 0
fi

if [ -z "$(git status --porcelain)" ]; then
    exit 0
fi

source ~/.bash/functions.sh

REPO_NAME=$(basename "$REPO_DIR")
FILES=$(git diff --name-only HEAD 2>/dev/null; git diff --name-only --cached 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)
MSG="claude: update $(echo "$FILES" | sort -u | head -5 | tr '\n' ', ' | sed 's/,$//' | sed 's/,/, /g')"

STOP_SUFFIX=""
if $IS_STOP; then
    STOP_SUFFIX=" (stop)"
fi

logger -n 192.168.5.25 -P 514 --udp -t claude-hook -p local0.info \
    "GIT_COMMIT: repo=$REPO_NAME msg=$MSG from claude session${STOP_SUFFIX}" 2>/dev/null || true

$GACP_FUNC "$MSG"

if $DO_SYNC; then
    syncn
fi
