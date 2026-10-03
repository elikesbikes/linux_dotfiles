#!/usr/bin/env python3
"""Read-only diagnostics gate for the Hermes agent (forced command of the `hermes-diag` SSH user).

Hermes (an AI agent in a container on endurance) connects here over SSH. sshd ignores whatever it asks to run and
starts THIS script; the requested text arrives only as data in $SSH_ORIGINAL_COMMAND. The script is the security
boundary, so it is deliberately small and strict:

  * a fixed list of subcommands, each READ-ONLY;
  * every character of the request is checked against a tiny alphabet BEFORE it is parsed;
  * arguments must equal an entry of a hard-coded allowlist (never a pattern, never a path);
  * no shell is ever used: external programs run from fixed argv lists (shell=False), with absolute paths picked
    from a fixed candidate list (PATH is never searched);
  * output is size-capped and redacted (it is sent on to the AI provider, so it leaves the homelab);
  * every request, accepted or rejected, is written to syslog (-> Graylog) with the client address.

The same script runs on every target. What a host allows is decided by its PROFILE (keyed by short hostname) plus
its OS (Linux or macOS):

  generic (every host, no privileges):  hostinfo os disk memory load processes network listening
                                        failed-units (Linux/systemd only)
  profile-specific (hailmary today):    status, component <name>      the MCC runner's own /api/status
                                        container-logs <name>         allowlisted containers
                                        service-journal <unit>        allowlisted units
Python 3.9 compatible on purpose (macOS ships 3.9).
"""

import json
import os
import re
import socket
import subprocess
import sys
import syslog
import time
import urllib.request

MAX_BYTES = 64 * 1024
TIMEOUT_S = 15
MCC_API = "http://127.0.0.1:5679/api/status"

# --------------------------------------------------------------------------------------------------------
# Per-host profiles. Exact names only. Adding a container/unit here ALSO needs the matching exact line in
# sudoers/sudoers.d/60-hermes-diag (generated from this file by gen-sudoers.py).
PROFILES = {
    "hailmary": {
        "mcc": True,
        "containers": ("tars-mcc-bot", "case-mcc-bot", "tars-n8n"),
        "units": ("mcc-runner.service",),
    },
}
DEFAULT_PROFILE = {"mcc": False, "containers": (), "units": ()}

# Names kept for the sudoers generator and existing callers (hailmary's lists).
CONTAINERS = PROFILES["hailmary"]["containers"]
UNITS = PROFILES["hailmary"]["units"]

DOCKER = "/usr/bin/docker"
JOURNALCTL = "/usr/bin/journalctl"

# Absolute-path candidates per program; the first that exists is used. PATH is never searched.
BIN = {
    "uname": ["/usr/bin/uname", "/bin/uname"],
    "lscpu": ["/usr/bin/lscpu"],
    "free": ["/usr/bin/free"],
    "lsblk": ["/usr/bin/lsblk", "/bin/lsblk"],
    "uptime": ["/usr/bin/uptime"],
    "df": ["/usr/bin/df", "/bin/df"],
    "ps": ["/usr/bin/ps", "/bin/ps"],
    "ip": ["/usr/sbin/ip", "/usr/bin/ip", "/sbin/ip"],
    "ss": ["/usr/bin/ss", "/usr/sbin/ss"],
    "systemctl": ["/usr/bin/systemctl", "/bin/systemctl"],
    "sw_vers": ["/usr/bin/sw_vers"],
    "system_profiler": ["/usr/sbin/system_profiler"],
    "vm_stat": ["/usr/bin/vm_stat"],
    "sysctl": ["/usr/sbin/sysctl"],
    "ifconfig": ["/sbin/ifconfig"],
}

# Generic read-only commands. A step is (program, [fixed args], post-filter-or-None); ("osrelease",) reads a file.
GENERIC = {
    "hostinfo": {
        "linux": [("uname", ["-srm"], None), ("lscpu", [], None), ("free", ["-h"], None),
                  ("lsblk", ["-o", "NAME,SIZE,TYPE,MOUNTPOINT"], None), ("uptime", [], None)],
        "darwin": [("sw_vers", [], None), ("system_profiler", ["SPHardwareDataType"], "hwscrub"), ("uptime", [], None)],
    },
    "os": {
        "linux": [("osrelease",), ("uname", ["-sr"], None)],
        "darwin": [("sw_vers", [], None)],
    },
    "disk": {
        "linux": [("df", ["-h", "-x", "tmpfs", "-x", "devtmpfs", "-x", "squashfs", "-x", "overlay"], None)],
        "darwin": [("df", ["-h"], None)],
    },
    "memory": {
        "linux": [("free", ["-h"], None)],
        "darwin": [("vm_stat", [], None), ("sysctl", ["hw.memsize"], None)],
    },
    "load": {
        "linux": [("uptime", [], None)],
        "darwin": [("uptime", [], None)],
    },
    "processes": {   # names only (comm), never full command lines, which can contain secrets
        "linux": [("ps", ["-eo", "pid,user,pcpu,pmem,etime,comm", "--sort=-pcpu"], "head16")],
        "darwin": [("ps", ["-Ao", "pid,user,pcpu,pmem,etime,comm", "-r"], "head16")],
    },
    "network": {
        "linux": [("ip", ["-br", "addr"], None)],
        "darwin": [("ifconfig", ["-a"], None)],
    },
    "listening": {
        "linux": [("ss", ["-ltn"], None)],
    },
    "failed-units": {
        "linux": [("systemctl", ["--failed", "--no-legend", "--no-pager"], None)],
    },
}
OSRELEASE_KEYS = ("PRETTY_NAME", "NAME", "VERSION", "VERSION_ID", "ID")
# system_profiler's hardware overview includes identifiers that do not belong in a chat with an AI provider.
HW_DROP = re.compile(r"serial number|hardware uuid|provisioning udid|activation lock|system firmware version", re.I)

# The whole request may only use these characters. No quotes, ;, |, &, $, `, <, >, \, newline, /.
REQUEST_RE = re.compile(r"[A-Za-z0-9._ -]{1,120}")   # used with fullmatch: "$" would accept a trailing newline
NAME_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")   # used with fullmatch

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
    return raw[:MAX_BYTES].decode("utf-8", "ignore") + "\n[output truncated at %d bytes]\n" % MAX_BYTES


def detect_os():
    return "darwin" if sys.platform == "darwin" else "linux"


def detect_profile():
    short = socket.gethostname().split(".")[0].lower()
    return PROFILES.get(short, DEFAULT_PROFILE)


def available_commands(profile, osname):
    cmds = ["help"] + [c for c, per_os in GENERIC.items() if osname in per_os]
    if profile.get("mcc"):
        cmds += ["status", "component <name>"]
    if profile.get("containers"):
        cmds.append("container-logs <name>")
    if profile.get("units"):
        cmds.append("service-journal <unit>")
    return cmds


NO_ARG = set(["help", "status"]) | set(GENERIC)
ONE_ARG = set(["component", "container-logs", "service-journal"])


def parse(request):
    """Return (subcommand, [args]) or raise Rejected. Nothing is executed here."""
    if request is None or request.strip() == "":
        return "help", []
    if not REQUEST_RE.fullmatch(request):
        raise Rejected("request contains characters that are not allowed")
    parts = request.split()
    cmd, args = parts[0], parts[1:]
    if cmd in NO_ARG:
        if args:
            raise Rejected("%s takes no arguments" % cmd)
        return cmd, []
    if cmd in ONE_ARG:
        if len(args) != 1:
            raise Rejected("%s takes exactly one argument" % cmd)
        if not NAME_RE.fullmatch(args[0]):
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


def _resolve(name, exists):
    for cand in BIN[name]:
        if exists(cand):
            return cand
    return None


def _post(kind, text):
    if kind == "head16":
        return "\n".join(text.splitlines()[:16]) + "\n"
    if kind == "hwscrub":
        return "\n".join(l for l in text.splitlines() if not HW_DROP.search(l)) + "\n"
    return text


def _osrelease(read=None):
    try:
        with open("/etc/os-release") as f:
            lines = f.read().splitlines()
    except OSError:
        return "(no /etc/os-release)\n"
    keep = [l for l in lines if l.split("=", 1)[0] in OSRELEASE_KEYS]
    return "\n".join(keep) + "\n"


def _generic(cmd, run, osname, exists):
    steps = GENERIC[cmd].get(osname)
    if not steps:
        raise Rejected("%s is not available on this OS" % cmd)
    out = []
    for step in steps:
        if step[0] == "osrelease":
            out.append(_osrelease())
            continue
        name, args, post = step
        path = _resolve(name, exists)
        if path is None:
            out.append("(%s is not installed on this host)\n" % name)
            continue
        out.append("$ %s %s\n" % (name, " ".join(args)))
        text = _post(post, run([path] + args))
        if osname == "darwin":   # defence in depth: no macOS identifiers in any output
            text = _post("hwscrub", text)
        out.append(text)
    return "".join(out)


def execute(cmd, args, api_fetch=_api_fetch, run=_run, profile=None, osname=None, exists=os.path.exists):
    profile = profile if profile is not None else detect_profile()
    osname = osname or detect_os()

    if cmd == "help":
        return "Commands available on this host:\n  " + "\n  ".join(available_commands(profile, osname)) + "\n"

    if cmd in GENERIC:
        return _generic(cmd, run, osname, exists)

    if cmd in ("status", "component"):
        if not profile.get("mcc"):
            raise Rejected("%s is not available on this host" % cmd)
        comps_all = api_fetch().get("components", [])
        if cmd == "status":
            bad = [c for c in comps_all if str(c.get("status", "")).lower() not in ("ok", "expected_offline")]
            bad.sort(key=lambda c: (c.get("status") != "fail", c.get("name", "")))
            lines = ["%d components; %d ok; %d not ok" % (len(comps_all), len(comps_all) - len(bad), len(bad))]
            for c in bad:
                lines.append("- %s [%s] severity=%s host=%s since=%s detail=%s" % (
                    c.get("name"), c.get("status"), c.get("severity"), c.get("host"), c.get("since"),
                    str(c.get("detail") or c.get("message") or "")[:300]))
            return "\n".join(lines) + "\n"
        comps = {c.get("name"): c for c in comps_all}
        if args[0] not in comps:
            raise Rejected("no such component")
        return json.dumps(comps[args[0]], indent=2, sort_keys=True, default=str) + "\n"

    if cmd == "container-logs":
        allowed = profile.get("containers", ())
        if args[0] not in allowed:
            raise Rejected("container is not in the allowlist: " + (", ".join(allowed) or "(none on this host)"))
        return run(["sudo", "-n", DOCKER, "logs", "--tail", "200", args[0]])

    if cmd == "service-journal":
        allowed = profile.get("units", ())
        if args[0] not in allowed:
            raise Rejected("unit is not in the allowlist: " + (", ".join(allowed) or "(none on this host)"))
        return run(["sudo", "-n", JOURNALCTL, "-u", args[0], "-n", "200", "--no-pager", "-o", "short-iso"])

    raise Rejected("unknown subcommand")  # unreachable: parse() already filtered


def handle(request, api_fetch=_api_fetch, run=_run, profile=None, osname=None, exists=os.path.exists):
    """Full pipeline for one request. Returns (exit_code, text, outcome)."""
    try:
        cmd, args = parse(request)
        out = execute(cmd, args, api_fetch, run, profile, osname, exists)
        return 0, cap(redact(out)), "ok"
    except Rejected as e:
        return 2, "hermes-diag: rejected: %s\n" % e, "rejected"
    except subprocess.TimeoutExpired:
        return 3, "hermes-diag: command timed out\n", "timeout"
    except Exception as e:  # never leak a traceback (it can contain paths/arguments)
        return 3, "hermes-diag: error: %s\n" % type(e).__name__, "error"


def audit(request, client, outcome, nbytes, ms):
    shown = (request or "")[:120].encode("ascii", "backslashreplace").decode()
    syslog.openlog("hermes-diag", syslog.LOG_PID, syslog.LOG_AUTH)
    syslog.syslog(syslog.LOG_NOTICE if outcome == "ok" else syslog.LOG_WARNING,
                  "user=%s host=%s client=%s outcome=%s bytes=%d ms=%d request=%r" % (
                      os.environ.get("USER", "hermes-diag"), socket.gethostname().split(".")[0], client,
                      outcome, nbytes, ms, shown))


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
