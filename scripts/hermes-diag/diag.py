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
                                        fit <name> [n]                the owner's fitness/health/labs data: fixed
                                                                      GETs on the MCC runner's local /api/life API
                                                                      (owner OK 2026-10-29, incl. anxiety + labs)
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
LIFE_API = "http://127.0.0.1:5679/api/life/"

# `fit <name> [n]`: name -> (path under LIFE_API, query with {n}, default n, max n). n=None: takes no number.
# Every URL is built from these constants plus a validated integer: no caller text ever reaches the URL.
# Only GET routes that read MCC's local data files (no Garmin/TrainerRoad call, no writes). Not offered:
# activity streams (fetches from Garmin), anything that POSTs.
FIT = {
    "activities":         ("fitness/activities", "days={n}&limit=2000", 28, 120),
    "rides":              ("fitness/activities", "days={n}&limit=2000", 28, 365),
    "activity-compare":   ("fitness/activity/{n}/compare", "", None, None),   # n = Garmin activity id
    "tss-weekly":         ("fitness/tss-weekly", "weeks={n}", 12, 104),
    "zones-weekly":       ("fitness/zones-weekly", "weeks={n}", 12, 52),
    "pmc":                ("fitness/pmc", "days={n}", 90, 365),
    "readiness":          ("fitness/readiness", "", None, None),
    "training-readiness": ("fitness/training-readiness", "days={n}", 30, 365),
    "training-status":    ("fitness/training-status", "days={n}", 30, 365),
    "insights":           ("fitness/insights", "days={n}", 120, 365),
    "ef-trend":           ("fitness/ef-trend", "days={n}&category=all", 180, 365),
    "power-profile":      ("fitness/power-profile", "ranges=all,ytd,d90&category=all", None, None),
    "power-records":      ("fitness/power-records", "category=all", None, None),
    "power-prs":          ("fitness/power-prs", "limit=8&category=all", None, None),
    "prs":                ("fitness/prs", "days={n}", 42, 365),
    "coach-report":       ("fitness/coach-report", "", None, None),
    "fitness-age":        ("fitness/fitness-age", "days={n}", 365, 730),
    "vo2max":             ("fitness/vo2max", "days={n}", 365, 730),
    "endurance":          ("fitness/endurance", "days={n}", 365, 730),
    "ftp":                ("health/ftp", "months={n}", 12, 36),
    "health-flags":       ("health/flags", "", None, None),
    "hrv":                ("health/hrv", "days={n}", 14, 365),
    "rhr":                ("health/rhr", "days={n}", 30, 365),
    "respiration":        ("health/respiration", "days={n}", 56, 365),
    "body-battery":       ("health/body-battery", "days={n}", 30, 365),
    "stress":             ("health/stress", "days={n}", 30, 365),
    "sleep":              ("health/sleep", "days={n}", 7, 30),
    "sleep-trend":        ("health/sleep-trend", "days={n}", 30, 365),
    "apple-sleep":        ("health/apple-sleep", "days={n}", 14, 365),
    "apple-sleep-score":  ("health/apple-sleep-score", "days={n}", 30, 365),
    "apple-hrv":          ("health/apple-hrv", "days={n}", 14, 365),
    "apple-sleep-rhr":    ("health/apple-sleep-rhr", "days={n}", 14, 365),
    "weight":             ("health/weight", "days={n}", 90, 730),
    "blood-pressure":     ("health/blood-pressure", "days={n}", 90, 730),
    "anxiety":            ("health/anxiety", "", None, None),
    "labs":               ("medical/labs", "", None, None),
}
FIT_ID_RE = re.compile(r"[0-9]{6,15}")      # Garmin activity id (fullmatch)
FIT_N_RE = re.compile(r"[0-9]{1,4}")        # day/week/month count (fullmatch)
# Columns of the `activities`/`rides` table (the raw rows carry ~50 fields + a power curve: 76 KB for 4 weeks).
ACTIVITY_COLS = ("id", "date", "start_time", "type", "name", "duration", "distance_km", "elevation_gain_m",
                 "avg_power", "norm_power", "max_power", "max20min_power", "intensity_factor", "tss", "avg_hr",
                 "max_hr", "avg_cadence", "aerobic_te", "anaerobic_te", "training_effect_label",
                 "activity_training_load", "work_kj", "hr_zones", "power_zones")

# --------------------------------------------------------------------------------------------------------
# Per-host profiles. Exact names only. Adding a container/unit here ALSO needs the matching exact line in
# sudoers/sudoers.d/60-hermes-diag (generated from this file by gen-sudoers.py).
PROFILES = {
    "hailmary": {
        "mcc": True,
        "fitness": True,
        "containers": ("tars-mcc-bot", "case-mcc-bot", "tars-n8n"),
        "units": ("mcc-runner.service",),
    },
}
DEFAULT_PROFILE = {"mcc": False, "fitness": False, "containers": (), "units": ()}

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
    if profile.get("fitness"):
        cmds += ["fit <name> [n]   names: " + ", ".join(sorted(FIT)),
                 "                 n = days/weeks/months (activity-compare: a Garmin activity id)"]
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
    if cmd == "fit":
        if not 1 <= len(args) <= 2:
            raise Rejected("usage: fit <name> [n]")
        if args[0] not in FIT:
            raise Rejected("unknown fit name (try: help)")
        path, query, default, most = FIT[args[0]]
        if args[0] == "activity-compare":
            if len(args) != 2 or not FIT_ID_RE.fullmatch(args[1]):
                raise Rejected("usage: fit activity-compare <garmin activity id>")
            return cmd, args
        if len(args) == 2:
            if default is None:
                raise Rejected("fit %s takes no number" % args[0])
            if not FIT_N_RE.fullmatch(args[1]) or not 1 <= int(args[1]) <= most:
                raise Rejected("n must be 1..%d for fit %s" % (most, args[0]))
        return cmd, args
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


def _fit_fetch(url):
    with urllib.request.urlopen(url, timeout=TIMEOUT_S) as resp:
        return json.load(resp)


def fit_url(name, arg=None):
    """URL for a parsed `fit` request: constants + a validated integer only."""
    path, query, default, most = FIT[name]
    if name == "activity-compare":
        return LIFE_API + path.format(n=int(arg))
    n = int(arg) if arg is not None else default
    return LIFE_API + path + ("?" + query.format(n=n) if query else "")


def _cell(v):
    if isinstance(v, dict):   # zones: {"z1": 91.0, ...} -> 91/42/0/0/0 (z1..zN, seconds)
        return "/".join("" if v[k] is None else ("%g" % v[k] if isinstance(v[k], (int, float)) else str(v[k]))
                        for k in sorted(v))
    if v is None:
        return ""
    return " ".join(str(v).split())   # no tabs/newlines inside a cell


def _is_ride(row):
    t = str(row.get("type", ""))
    return "cycling" in t or "biking" in t or t == "virtual_ride"


def _fit_format(name, data):
    if name in ("activities", "rides") and isinstance(data, dict):
        rows = [r for r in data.get("activities", []) if name == "activities" or _is_ride(r)]
        out = ["%d %s in the last %s days (newest first). hr_zones/power_zones = SECONDS in z1/z2/... "
               "(HR z1-z5, power z1-z7)" % (len(rows), name, data.get("days")), "\t".join(ACTIVITY_COLS)]
        out += ["\t".join(_cell(r.get(c)) for c in ACTIVITY_COLS) for r in rows]
        return "\n".join(out) + "\n"
    if name == "labs" and isinstance(data, dict):   # latest value per analyte; full point history is 106 KB
        data = {"summary": data.get("summary"),
                "analytes": [{k: v for k, v in a.items() if k != "points"} for a in data.get("analytes", [])],
                "qualitative": [{k: v for k, v in a.items() if k != "values"} for a in data.get("qualitative", [])]}
    return json.dumps(data, separators=(",", ":"), sort_keys=True, default=str) + "\n"


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


def execute(cmd, args, api_fetch=_api_fetch, run=_run, profile=None, osname=None, exists=os.path.exists,
            fit_fetch=_fit_fetch):
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

    if cmd == "fit":
        if not profile.get("fitness"):
            raise Rejected("fit is not available on this host")
        return _fit_format(args[0], fit_fetch(fit_url(args[0], args[1] if len(args) > 1 else None)))

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


def handle(request, api_fetch=_api_fetch, run=_run, profile=None, osname=None, exists=os.path.exists,
           fit_fetch=_fit_fetch):
    """Full pipeline for one request. Returns (exit_code, text, outcome)."""
    try:
        cmd, args = parse(request)
        out = execute(cmd, args, api_fetch, run, profile, osname, exists, fit_fetch)
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
