#!/usr/bin/env python3
"""Generate the sudoers rules for the hermes-diag account from the allowlists in diag.py.

diag.py is the single source of truth for which containers/units the account may read. The generated
file is committed as sudoers/sudoers.d/60-hermes-diag and deployed by the dotfiles pipeline
(sync-sudoers-ci.sh on rocky and hailmary). The rule names the HOST (hailmary) in sudoers' host field,
so it is inert on every other machine even though the file is synced everywhere.

  gen-sudoers.py              print the rules
  gen-sudoers.py --write F    write them to F
  gen-sudoers.py --check F    exit 1 if F differs from what diag.py implies (drift guard)
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag  # noqa: E402

SUDO_HOST = "hailmary"
ACCOUNT = "hermes-diag"
LOG = "/var/log/sudo-hermes-diag.log"
_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._@-]*")


def render():
    rules = []
    for c in diag.CONTAINERS:
        assert _NAME.fullmatch(c), c
        rules.append(f"{diag.DOCKER} logs --tail 200 {c}")
    for u in diag.UNITS:
        assert _NAME.fullmatch(u), u
        rules.append(f"{diag.JOURNALCTL} -u {u} -n 200 --no-pager -o short-iso")
    body = ", \\\n".join(f"    {r}" for r in rules)
    return (
        "# Managed by scripts/hermes-diag/gen-sudoers.py from the allowlists in diag.py. DO NOT EDIT BY HAND.\n"
        "# EXACT commands only (no wildcards). Deployed by the dotfiles pipeline; applies ONLY to host "
        f"'{SUDO_HOST}' and user '{ACCOUNT}'.\n"
        f"Cmnd_Alias HERMES_DIAG = \\\n{body}\n"
        f"Defaults:{ACCOUNT} !requiretty, logfile={LOG}\n"
        f"{ACCOUNT} {SUDO_HOST}=(root) NOPASSWD: HERMES_DIAG\n"
    )


def main(argv):
    text = render()
    if len(argv) == 3 and argv[1] == "--write":
        open(argv[2], "w").write(text)
    elif len(argv) == 3 and argv[1] == "--check":
        have = open(argv[2]).read() if os.path.exists(argv[2]) else None
        if have != text:
            sys.stderr.write(f"{argv[2]} is out of date with diag.py: run gen-sudoers.py --write {argv[2]}\n")
            return 1
    elif len(argv) == 1:
        sys.stdout.write(text)
    else:
        sys.stderr.write(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
