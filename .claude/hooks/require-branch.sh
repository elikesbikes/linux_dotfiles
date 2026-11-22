#!/usr/bin/env bash
# PreToolUse guard (Edit|Write|NotebookEdit): in a repo that lands through merge requests with a
# plain branch (linux_dotfiles v1.21.0, issue #29), Claude may not edit while the checkout is on main.
# An edit on main would go out with no MR (and, for an iOS app, to TestFlight on the next push).
# Start the work with `gacp_branch <name>` (switches to br/<name>), then gacp_branch_done opens the MR.
#
# Repos are added here one by one as they move over (pilot: sshtars-ios, reviere). mcc is covered by
# its own require-worktree.sh. Owner override for deliberate work on main: launch Claude with
# GACP_ALLOW_MAIN=1 (a session cannot set it for itself).
# Matches the raw hook JSON (no jq to fail open on). Writes made through Bash are not seen.
# Test: bash ~/.claude/hooks/test-require-branch.sh
set -uo pipefail

REPOS=(
    "$HOME/devops/projects/ios/sshtars"
    "$HOME/devops/projects/reviere"
)

[ "${GACP_ALLOW_MAIN:-}" = "1" ] && exit 0
INPUT="$(cat)"

for repo in "${REPOS[@]}"; do
    case "$INPUT" in
        *"\"$repo/"*) ;;
        *) continue ;;
    esac
    branch="$(git -C "$repo" symbolic-ref -q --short HEAD 2>/dev/null)"
    if [ "$branch" = "main" ]; then
        logger -n 192.168.5.25 -P 514 --udp -t claude-hook -p local0.info "REQUIRE_BRANCH: edit refused in $(basename "$repo") on main" 2>/dev/null
        echo "BLOCKED: $(basename "$repo") lands through merge requests and is on main." >&2
        echo "  Run: cd $repo && gacp_branch <short-name>   (a session may run it), then edit;" >&2
        echo "  gacp_branch_done \"message\" opens the MR. Only the owner merges." >&2
        exit 2
    fi
done
exit 0
