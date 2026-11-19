# scripts/gitlab

| Script | What it does |
|---|---|
| `issue` | Open, close, note and list GitLab issues the same way from every session and host |
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
