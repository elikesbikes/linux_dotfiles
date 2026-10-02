#!/usr/bin/env python3
"""Read-only diagnostics gate for the Hermes agent (forced command of the `hermes-diag` SSH user).

Hermes (an AI agent on endurance) connects here over SSH. sshd ignores whatever it asks to run and
starts THIS script; the requested text arrives only as data in $SSH_ORIGINAL_COMMAND. The script is
the security boundary, so it is deliberately small and strict:

  * a fixed list of subcommands, each READ-ONLY;
  * every character of the request is checked against a tiny alphabet BEFORE it is parsed;
  * arguments must equal an entry of a hard-coded allowlist (never a pattern, never a path);
  * no shell is ever used: external programs run from fixed argv lists (shell=False);
  * output is size-capped and has secret-looking text redacted (the output is sent on to the AI
    provider, so it leaves the homelab);
  * every request, accepted or rejected, is written to syslog (-> Graylog) with the client address.

Subcommands:
  help
  status                    components that are not ok, from MCC's local API
  component <name>          full state of one MCC component (the name must exist in the API)
  container-logs <name>     last 200 log lines of one allowlisted MCC container
  service-journal <unit>    last 200 journal lines of one allowlisted systemd unit
"""

import json
import os
import re
import subprocess
import sys
import syslog
import time
import urllib.request

MAX_BYTES = 64 * 1024
TIMEOUT_S = 15
MCC_API = "http://127.0.0.1:5679/api/status"

# Exact names only. Adding one here ALSO requires the matching exact line in
# /etc/sudoers.d/60-hermes-diag (install.sh writes both from this file).
CONTAINERS = ("tars-mcc-bot", "case-mcc-bot", "tars-n8n")
UNITS = ("mcc-runner.service",)

DOCKER = "/usr/bin/docker"
JOURNALCTL = "/usr/bin/journalctl"

# The whole request may only use these characters. No quotes, ;, |, &, $, `, <, >, \, newline, /.
REQUEST_RE = re.compile(r"^[A-Za-z0-9._ -]{1,120}$")
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")

REDACTIONS = [
    (re.compile(r"pst_[0-9a-f]{16,}(::[A-Za-z0-9_-]+)?"), "<redacted:proton-pat>"),
    (re.compile(r"\b[A-Za-z0-9_-]{23,28}\.[A-Za-z0-9_-]{6,7}\.[A-Za-z0-9_-]{27,}\b"), "<redacted:discord-token>"),
    (re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"), "<redacted:jwt>"),
    (re.compile(r"\b(sk-ant-|glpat-|ghp_|gho_|xox[bap]-|AKIA)[A-Za-z0-9_-]{8,}"), "<redacted:key>"),
    (re.compile(r"(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]{8,}"), r"\1 <redacted>"),
    (re.compile(r"(?i)\b(password|passwd|secret|token|api[_-]?key|authorization|cookie|private[_-]?key)\b(\s*[=:]\s*|\"\s*:\s*\")[^\s\",;]+"),
     r"\1\2<redacted>"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", re.S), "<redacted:private-key>"),
    (re.compile(r"(?<![A-Za-z0-9+/_-])(?=[A-Za-z0-9+/_-]*[A-Za-z])(?=[A-Za-z0-9+/_-]*\d)[A-Za-z0-9+/_-]{48,}={0,2}"),
     "<redacted:long-token>"),
]


class Rejected(Exception):
    """The request is not allowed (the message is safe to show to the caller)."""


def redact(text):
    for rx, repl in REDACTIONS:
        text = rx.sub(repl, text)
    return text


def cap(text):
    raw = text.encode("utf-8", "replace")
    if len(raw) <= MAX_BYTES:
        return text
    return raw[:MAX_BYTES].decode("utf-8", "ignore") + f"\n[output truncated at {MAX_BYTES} bytes]\n"


def parse(request):
    """Return (subcommand, [args]) or raise Rejected. Nothing is executed here."""
    if request is None or request.strip() == "":
        return "help", []
    if not REQUEST_RE.match(request):
        raise Rejected("request contains characters that are not allowed")
    parts = request.split()
    cmd, args = parts[0], parts[1:]
    if cmd == "help" or cmd == "status":
        if args:
            raise Rejected(f"{cmd} takes no arguments")
        return cmd, []
    if cmd in ("component", "container-logs", "service-journal"):
        if len(args) != 1:
            raise Rejected(f"{cmd} takes exactly one argument")
        if not NAME_RE.match(args[0]):
            raise Rejected("argument is not a valid name")
        return cmd, args
    raise Rejected("unknown subcommand (try: help)")


def _api_fetch():
    with urllib.request.urlopen(MCC_API, timeout=TIMEOUT_S) as resp:
        return json.load(resp)


def _run(argv):
    """Run a FIXED argv (no shell). Returns merged stdout+stderr text."""
    p = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       timeout=TIMEOUT_S, shell=False, check=False)
    return p.stdout.decode("utf-8", "replace")


def execute(cmd, args, api_fetch=_api_fetch, run=_run):
    if cmd == "help":
        return __doc__.split("Subcommands:")[1].strip("\n") + "\n"

    if cmd == "status":
        comps = api_fetch().get("components", [])
        bad = [c for c in comps if str(c.get("status", "")).lower() not in ("ok", "expected_offline")]
        bad.sort(key=lambda c: (c.get("status") != "fail", c.get("name", "")))
        lines = [f"{len(comps)} components; {len(comps) - len(bad)} ok; {len(bad)} not ok"]
        for c in bad:
            lines.append(f"- {c.get('name')} [{c.get('status')}] severity={c.get('severity')} host={c.get('host')} "
                         f"since={c.get('since')} detail={str(c.get('detail') or c.get('message') or '')[:300]}")
        return "\n".join(lines) + "\n"

    if cmd == "component":
        comps = {c.get("name"): c for c in api_fetch().get("components", [])}
        if args[0] not in comps:
            raise Rejected("no such component")
        return json.dumps(comps[args[0]], indent=2, sort_keys=True, default=str) + "\n"

    if cmd == "container-logs":
        if args[0] not in CONTAINERS:
            raise Rejected("container is not in the allowlist: " + ", ".join(CONTAINERS))
        return run(["sudo", "-n", DOCKER, "logs", "--tail", "200", args[0]])

    if cmd == "service-journal":
        if args[0] not in UNITS:
            raise Rejected("unit is not in the allowlist: " + ", ".join(UNITS))
        return run(["sudo", "-n", JOURNALCTL, "-u", args[0], "-n", "200", "--no-pager", "-o", "short-iso"])

    raise Rejected("unknown subcommand")  # unreachable: parse() already filtered


def handle(request, api_fetch=_api_fetch, run=_run):
    """Full pipeline for one request. Returns (exit_code, text, outcome)."""
    try:
        cmd, args = parse(request)
        out = execute(cmd, args, api_fetch, run)
        return 0, cap(redact(out)), "ok"
    except Rejected as e:
        return 2, f"hermes-diag: rejected: {e}\n", "rejected"
    except subprocess.TimeoutExpired:
        return 3, "hermes-diag: command timed out\n", "timeout"
    except Exception as e:  # never leak a traceback (it can contain paths/arguments)
        return 3, f"hermes-diag: error: {type(e).__name__}\n", "error"


def audit(request, client, outcome, nbytes, ms):
    shown = (request or "")[:120].encode("ascii", "backslashreplace").decode()
    syslog.openlog("hermes-diag", syslog.LOG_PID, syslog.LOG_AUTH)
    syslog.syslog(syslog.LOG_NOTICE if outcome == "ok" else syslog.LOG_WARNING,
                  f"user={os.environ.get('USER', 'hermes-diag')} client={client} outcome={outcome} "
                  f"bytes={nbytes} ms={ms} request={shown!r}")


def main():
    request = os.environ.get("SSH_ORIGINAL_COMMAND")
    client = (os.environ.get("SSH_CLIENT") or "unknown").split()[0]
    t0 = time.monotonic()
    code, text, outcome = handle(request)
    audit(request, client, outcome, len(text), int((time.monotonic() - t0) * 1000))
    sys.stdout.write(text)
    return code


if __name__ == "__main__":
    sys.exit(main())
