# audit-exempt: pure stdin->stdout filter, no side effects; callers (secrets.sh, checks.py) audit the attempts
"""Allow-list filter for pass-cli's connection trace (PASS_LOG_LEVEL / MUON_LOG_LEVEL).

Why: pass-cli logins time out in bursts ("error during transmission: timed out") and nothing we
logged could say where the time went. pass-cli's own tracing can: DNS resolve, TCP dial, TLS
handshake, "sending request, time left", the HTTP status and "send took". But at DEBUG and above
muon also dumps whole requests, including `authorization: Bearer ...`, `x-pm-uid` and the PAT in
the login body (verified on tars 2026-10-06). So the raw stream is never written anywhere. Only
lines on the allow-list below survive, and those are then masked again.

Two kinds of line come out:
  * trace lines (start with an ISO timestamp) on the allow-list, cut and masked
  * pass-cli's own error message (no timestamp), masked: the loader's audit reason is built from these

CLI:  pass-cli ... 2>&1 >/dev/null | python3 shared/pass_trace.py > attempt.log
"""
import re
import sys

# The parts of a login that tell H1 (server silent) / H3 (network) / H4 (client retry or
# alternative routing) apart. Anything not matched here is dropped.
_KEEP = re.compile(
    r"attempting to connect|resolv|connecting to|dialing|upgrading to TLS|TLS handshake|socket connected"
    r"|using HTTP/|sending request, time left|sending with retry|received http::Response|send took"
    r"|retry|retrying|backoff|sleep|Retry-After|too many|alternative|indirect|proxy|dns-query|doh"
    r"|timed out|timeout|error|fail|refused|reset|closed|personal access token session|logged in",
    re.I)
# Request/response dumps carry headers and bodies (tokens). Never keep them, whatever else they contain.
_DROP = re.compile(r"req=Request|headers:|Bearer|x-pm-uid|authorization|body ?[=:]|AccessToken|RefreshToken"
                   r"|access_token|refresh_token|PrivateKey|BEGIN PGP|Getting from the store", re.I)
_TRACE_LINE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}")
_ANSI = re.compile(r"\x1b\[[0-9;]*m")
# "/builds/pass/.../muon-2.6.1/src/client/mod.rs" -> "muon-2.6.1/client/mod.rs"
_SRC = re.compile(r"/\S*/((?:muon|pass-[a-z]+)[-\w.]*)/src/")
# From a request dump keep only "METHOD scheme://host/path" (no query string, headers or body).
_REQ = re.compile(r"method: ([A-Z]+), uri: (https?://[^\s?,]+)")
# Token-shaped runs (no dots or slashes, so hostnames and source paths stay readable).
_TOKEN = re.compile(r"[A-Za-z0-9+_=-]{24,}")

MAX_LINES = 300
MAX_LINE = 300


def mask(line):
    return _TOKEN.sub("<redacted>", line)[:MAX_LINE]


def filter_trace(text):
    """Return only the safe, useful lines of pass-cli stderr (trace + its own error message)."""
    out = []
    for raw in (text or "").splitlines():
        line = _SRC.sub(r"\1/", _ANSI.sub("", raw).rstrip())
        req = _REQ.search(line) if _TRACE_LINE.match(line) else None
        if req:
            out.append(mask(line.split(": ", 1)[0].split(" ", 1)[0] + f" REQUEST {req.group(1)} {req.group(2)}"))
            continue
        if not line.strip() or _DROP.search(line):
            continue
        if _TRACE_LINE.match(line) and not _KEEP.search(line):
            continue
        out.append(mask(line))
        if len(out) >= MAX_LINES:
            out.append("[pass_trace] output capped")
            break
    return "\n".join(out) + ("\n" if out else "")


# Proton's login throttle, as seen in a live capture (2026-10-06):
#   received http::Response { status: 429 Too Many Requests, error_code: Some(ProtonBodyCode { code: 2028, error: "Too many recent logins" ...
#   WARN ... rate limited, retrying after 273s
# pass-cli then SLEEPS for that long, so a short per-attempt cap sees only a silent hang.
_RATE = re.compile(r"status: 429|429 Too Many Requests|rate limited|Too many recent logins", re.I)
_RETRY_AFTER = re.compile(r"retrying after (\d+)\s*s", re.I)


def rate_limit(filtered):
    """None when the filtered trace shows no throttle; otherwise Proton's retry-after in seconds (0 if unstated)."""
    text = filtered or ""
    if not _RATE.search(text):
        return None
    m = _RETRY_AFTER.search(text)
    return int(m.group(1)) if m else 0


def error_lines(filtered):
    """pass-cli's own message (the non-trace lines) from filter_trace() output."""
    return "\n".join(l for l in filtered.splitlines() if not _TRACE_LINE.match(l))


if __name__ == "__main__":
    if "--rate-limit" in sys.argv[1:]:
        # exit 0 and print the retry-after seconds if the (already filtered) trace on stdin shows a throttle
        ra = rate_limit(sys.stdin.read())
        if ra is None:
            sys.exit(1)
        print(ra)
    else:
        sys.stdout.write(filter_trace(sys.stdin.read()))
