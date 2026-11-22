#!/usr/bin/env bash
# Tests for block-owner-merge.sh: feeds hook JSON the way Claude Code does and checks the exit code
# (2 = blocked, 0 = allowed). Run: bash ~/.claude/hooks/test-block-owner-merge.sh
set -uo pipefail
HOOK="$(dirname "${BASH_SOURCE[0]}")/block-owner-merge.sh"
M=merge   # keeps this file's own command text from tripping the hook when it is run
fail=0

check() {  # expected-exit  command
    local want="$1" cmd="$2" json got
    json="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")"
    printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1
    got=$?
    if [ "$got" = "$want" ]; then echo "ok   ($got) $cmd"; else echo "FAIL (want $want, got $got) $cmd"; fail=1; fi
}

# blocked
check 2 "gacp_worktree_$M"
check 2 "cd ~/devops/projects/mcc-worktrees/x && gacp_worktree_$M"
check 2 "bash -c 'source ~/.bash/functions.sh; gacp_worktree_$M'"
check 2 "mr $M wt/x"
check 2 "~/scripts/gitlab/mr $M wt/x"
check 2 "\"\$HOME/scripts/gitlab/mr\" $M wt/x"
check 2 "glab mr $M 1"
check 2 "echo y | mr $M wt/x"
check 2 "curl -X PUT -H 'PRIVATE-TOKEN: t' https://gitlab.home.elikesbikes.com/api/v4/projects/4/merge_requests/1/$M"
check 2 "python3 -c \"call('PUT', '/projects/4/merge_requests/12/$M')\""
check 2 "ls; mr $M wt/x"
check 2 "mr $M br/x; mr $M wt/y"
check 2 "mr $M --wait wt/x"
check 2 "mr $M"

# allowed
check 0 "mr open wt/x 'title'"
check 0 "mr status wt/x"
check 0 "gacp_worktree_done 'message'"
check 0 "gacp_worktree_done"
check 0 "gacp_branch fix-x"
check 0 "gacp_branch_done 'message'"
check 0 "git $M --no-edit origin/main"
check 0 "git $M-base main HEAD"
check 0 "curl https://gitlab.home.elikesbikes.com/api/v4/projects/4/merge_requests/1"
check 0 "curl https://gitlab.home.elikesbikes.com/api/v4/projects/4/merge_requests/1/approvals"
check 0 "grep -n detailed_${M}_status file"
check 0 "ls -la"

exit $fail
