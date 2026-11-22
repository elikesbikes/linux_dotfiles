# scripts/gitlab

| Script | What it does |
|---|---|
| `issue` | Open, close, note and list GitLab issues the same way from every session and host |
| `mr` | Open or check the merge request for a branch (used by `gacp_worktree_done`) |
| `refresh-gitlab-rocky.sh` | Refresh the GitLab dev replica on rocky from prod on hailmary (see the script header) |

## issue

Issues are kept in GitLab, in the repo that owns the work (owner rule 2026-11-18, in
`.claude/CLAUDE.md` "Issues and Backlog"). Two kinds: `finding` (a bug or broken thing) and `feature`
(the backlog). A bug fixed on the spot still gets an issue, opened and closed by the fix.

```bash
issue repos                                         # where things go
issue open mcc "title" --host hailmary --body "..." # a finding (add --feature for the backlog)
issue open adastra "title" --body - < notes.md      # body from stdin
issue fixed mcc "title" --commit de47fbd            # fixed at once: opened and closed together
issue close mcc 12 --note "fixed by abc1234"
issue note mcc 12 "more evidence"
issue list                                          # open issues in every repo
issue list cooper-ios --label feature --all
```

In a commit message, `Closes #12` closes the issue when the commit reaches `main` (proved with
mcc#2 and de47fbd, 2026-11-18).

- **Token:** the GitLab credential helper (`git credential fill`), the same one git uses; nothing is
  stored by the script.
- **Labels** (in every live project): `finding`, `feature`, `security`, `owner-action`, `migrated`,
  `host:tars|rocky|hailmary|kipp|endurance|gargantua`. `--host` refuses a name outside that list.
- **Audit:** every write logs one syslog line, tag `gitlab-issue`
  (`action=open repo=mcc iid=4 outcome=ok`), which the host ships to Graylog.
- **Privacy:** `linux_dotfiles` is public, so its issues are set to members only (checked
  2026-11-18: anonymous list returns `[]` while one issue exists). Never put a secret in a title or
  body.

**Tested on tars 2026-11-18:** `repos`, `list` (one repo, all repos, `--closed`), `open`, the unknown
`--host` refusal, the syslog line. **Not tested:** `fixed`, `close`, `note` (first real use will),
and running it on rocky, hailmary, kipp or endurance.

## mr

Used by `gacp_worktree_done` (v1.19.0), which pushes the worktree branch and then calls it. Run it
inside the checkout; the project comes from `origin`, which must be on this GitLab.

```bash
mr open wt/my-task "Short title"   # opens the MR into main, or refreshes the open one; prints the URL
mr status wt/my-task               # "merged <url>" (exit 0), or opened / closed / none (exit 1)
mr merge wt/my-task                # OWNER ONLY: merge the open MR (deploys); y/N on your terminal
```

The description lists the branch's commits and repeats every `Closes #N` / `Fixes #N` from their
messages, so the issues close when the MR is merged. Same token and audit as `issue` (syslog tag
`gitlab-mr`). The title is cut to its first line and 255 characters.

### Merging from the terminal (v1.20.0)

Only the owner merges, because a merge into main deploys (mcc: straight to rocky). Two ways, same
result: click **Merge** in GitLab, or, inside the worktree in your own shell:

```bash
gacp_worktree_merge     # mr merge for this worktree's branch, then gacp_worktree_done cleans up
```

`mr merge` refuses unless GitLab calls the MR mergeable (tests green, no conflicts, not a draft),
prints the title, link, pipeline and commits, and asks y/N. It needs a terminal, has no flag to skip
the question, and pins the merge to the commit it showed (a push in between makes GitLab refuse).
`gacp_worktree_merge` also refuses when the worktree has uncommitted edits or commits GitLab does not
have yet. Each merge is logged (`MR_MERGED`, tag `gitlab-mr`; `WORKTREE_MERGED`, tag `gacp`).

Claude sessions cannot run either: `~/.claude/hooks/block-owner-merge.sh` (registered in
`.claude/settings.json`) refuses any Bash command naming `gacp_worktree_merge`, `mr merge`,
`glab mr merge` or an API `merge_requests/<n>/merge` call. Tests:
`bash ~/.claude/hooks/test-block-owner-merge.sh`.

**Tested 2026-11-20:** `open` and `status` on mcc (pilot MR !1); a GitHub origin is refused with a
clear message. **Tested 2026-11-21:** the hook (21 cases: 11 blocked, 10 allowed); `mr merge`
refuses with no terminal. **Not tested yet:** a real merge with `gacp_worktree_merge` (the owner runs
the first one).
