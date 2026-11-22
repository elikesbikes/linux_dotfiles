#!/usr/bin/env bash
# PreToolUse guard (Bash), every repo: a Claude session may not merge a GitLab merge request.
#
# Owner rule 2026-11-20: a session may open an MR (gacp_worktree_done, `mr open`), which deploys
# nothing; only the owner merges, because a merge into main deploys (mcc: straight to rocky).
# The owner merges by clicking Merge in GitLab or, in their own shell, with gacp_worktree_merge /
# gacp_branch_merge (v1.21.0) / `mr merge` (scripts/gitlab/mr, which also needs a terminal and a y/N). This hook refuses those
# commands, glab's merge and a direct API merge call when Claude sends them.
#
# Matches the raw hook JSON, not a parsed command: no jq dependency to fail open on, and
# over-matching only blocks more (a commit message or heredoc that names the command is refused
# too; write such text with Edit/Write). Limits: it reads the command text, so a command hidden
# behind a variable or an encoded string is not seen. This stops a mistake, not a steered session
# on the same account.
# Test: bash ~/.claude/hooks/test-block-owner-merge.sh
set -uo pipefail

INPUT="$(cat)"

case "$INPUT" in *merge*) ;; *) exit 0 ;; esac

# JSON escapes (\n, \t, \") would glue onto neighbouring words.
TEXT="${INPUT//\\u????/ }"
TEXT="${TEXT//\\n/ }"
TEXT="${TEXT//\\r/ }"
TEXT="${TEXT//\\t/ }"
TEXT="${TEXT//\\\"/ }"

# Owner 2026-11-22: a session MAY merge in the branch repos (iOS apps, reviere, groceries), whose
# branches are br/<name>: `gacp_branch_merge` and `mr merge [--wait] br/<name>` pass. scripts/gitlab/mr
# is the second layer: without a terminal it merges only its SESSION_MERGE allowlist (never mcc).
MR_ANY="(^|[^[:alnum:]_.-])mr[\"']?[[:space:]]+merge([^[:alnum:]_-]|$)"
MR_BR="(^|[^[:alnum:]_.-])mr[\"']?[[:space:]]+merge[[:space:]]+(--wait[[:space:]]+)?br/"
n_any="$(printf '%s' "$TEXT" | grep -oE "$MR_ANY" | wc -l)"
n_br="$(printf '%s' "$TEXT" | grep -oE "$MR_BR" | wc -l)"

reason=""
if printf '%s' "$TEXT" | grep -qE 'gacp_worktree_merge'; then
    reason="gacp_worktree_merge (mcc is owner-only)"
elif [ "$n_any" -gt "$n_br" ]; then
    reason="mr merge of a non-br/ branch (mcc worktree branches are owner-only)"
elif printf '%s' "$TEXT" | grep -qE 'merge_requests/[^/[:space:]]+/merge([^[:alnum:]_]|$)'; then
    reason="merge API call"
fi

if [ -n "$reason" ]; then
    logger -n 192.168.5.25 -P 514 --udp -t claude-hook -p local0.info "BLOCK_OWNER_MERGE: $reason from claude session" 2>/dev/null
    echo "BLOCKED ($reason): merging deploys, and in mcc only the owner merges." >&2
    echo "  Open the MR (gacp_worktree_done) and give the owner the link; they click Merge or run" >&2
    echo "  gacp_worktree_merge in their own shell. (In the iOS/reviere/groceries repos a session may" >&2
    echo "  merge its own br/<name> MR with gacp_branch_merge.)" >&2
    exit 2
fi
exit 0
