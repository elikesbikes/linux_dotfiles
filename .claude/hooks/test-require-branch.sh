#!/usr/bin/env bash
# Tests for require-branch.sh against a scratch repo (never the real ones): the hook's REPOS list is
# rewritten to point at the scratch repo. Run: bash ~/.claude/hooks/test-require-branch.sh
set -uo pipefail
SRC="$(dirname "${BASH_SOURCE[0]}")/require-branch.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/app"
git init -q -b main "$REPO" && git -C "$REPO" commit -q --allow-empty -m base
sed "s#\"\$HOME/devops/projects/ios/sshtars\"#\"$REPO\"#" "$SRC" > "$TMP/hook.sh"
fail=0

check() {  # want  label  file_path  [env]
    local want="$1" label="$2" path="$3" got
    printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' "$path" \
        | env ${4:-} bash "$TMP/hook.sh" >/dev/null 2>&1
    got=$?
    if [ "$got" = "$want" ]; then echo "ok   ($got) $label"; else echo "FAIL (want $want, got $got) $label"; fail=1; fi
}

check 2 "edit on main is refused"            "$REPO/App.swift"
check 0 "file outside the listed repos"      "$TMP/other/App.swift"
check 0 "prefix-only match is not the repo"  "${REPO}2/App.swift"
check 0 "owner override GACP_ALLOW_MAIN=1"   "$REPO/App.swift" "GACP_ALLOW_MAIN=1"
git -C "$REPO" switch -q -c br/x
check 0 "edit on a br/ branch is allowed"    "$REPO/App.swift"
exit $fail
