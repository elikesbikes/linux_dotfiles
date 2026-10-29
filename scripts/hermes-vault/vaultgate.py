#!/usr/bin/python3 -I
"""Vault capture gate for the Hermes agent (forced command of the `hermes-vault` SSH user on hailmary).

Hermes (an AI agent in a container on endurance) connects here over SSH to put the owner's school notes into the
Obsidian vault (CouchDB + LiveSync). sshd ignores whatever it asks to run and starts THIS script; the request arrives
only as data in $SSH_ORIGINAL_COMMAND and, for `create`, the note text on stdin. The script is the security boundary:

  * four verbs: help, list <prefix>, get <path>, create <path> (text on stdin);
  * read only under READ_ROOTS, write only under WRITE_ROOTS, create-only: an existing note is NEVER overwritten
    (case-insensitive, like the owner's Macs), nothing is ever deleted, new course folders are never invented;
  * paths are checked character by character BEFORE use (no "..", no hidden parts, .md only, depth-capped);
  * secrets: this account's OWN Proton Pass PAT (TPM handle 0x81010002, read through one exact sudo rule; the
    account is not in the tss group, so it cannot unseal the owner's PAT at 0x81010001). The PAT may read exactly
    three items. Values live only in this process; the pass-cli session is kept in ~/.pp-session (mode 700) so a
    note does not cost a Proton login (Proton rate-limits logins);
  * vault I/O goes through the MCC vault_fetch module (the same LiveSync format the owner's tools write), imported
    with a stub dotenv: MCC's .env is not readable by this account and is not needed;
  * every request, accepted or refused, goes to syslog (-> Graylog) with the client address; vault writes are also
    recorded by MCC's audit (event vault.write).
"""

import fcntl
import json
import os
import pwd
import re
import signal
import subprocess
import sys
import syslog
import time
import types
import unicodedata
from pathlib import Path

READ_ROOTS = ("Career/Courses/", "Templates/")
WRITE_ROOTS = ("Career/Courses/",)
MAX_PARTS = 5                 # Career/Courses/<course>/<folder>/<note>.md (owner: <= 3 folders deep under Career)
MAX_PATH = 300
MAX_NOTE = 256 * 1024
MAX_OUT = 512 * 1024
TIMEOUT_S = 120

MCC_ROOT = "/home/ecloaiza/devops/projects/mcc"
COUCHDB_URL = "https://couchdb.home.elikesbikes.com"
AUDIT_SYSLOG = "tcp://hailmary.home.elikesbikes.com:1514"
LIB = "/usr/local/lib/hermes-vault"
UNSEAL = f"{LIB}/unseal-pat"
PASS_CLI = f"{LIB}/pass-cli"
HOME = Path(pwd.getpwuid(os.getuid()).pw_dir)   # not $HOME: under `sudo -u` it can still be root's
SECRETS = {   # env var -> Proton Pass item title (field "note"); the PAT can read these three items and nothing else
    "COUCHDB_USER": "MCC - COUCHDB_USER",
    "COUCHDB_PASSWORD": "MCC - COUCHDB_PASSWORD",
    "VAULT_PASSPHRASE": "MCC - VAULT_PASSPHRASE",
}

VERB_RE = re.compile(r"[a-z]{1,10}")
# One path part: letters (any language), digits and a few punctuation marks used in course/note names.
PART_RE = re.compile(r"[\w][\w .,()&+'#-]*", re.UNICODE)

HELP = """hermes-vault: put school notes into the Obsidian vault (create-only).
  help
  list <prefix>      note paths under <prefix>        (allowed: {read})
  get <path.md>      one note's text                  (allowed: {read})
  create <path.md>   new note, text on stdin          (allowed: {write}; never overwrites, max {kb} KiB)
Paths are plain text after the verb: no quotes, no leading '/'. Example:
  create Career/Courses/2026-Fall COMP 666 - Intro to Software Development/Modules/1.1 - Version Control.md
""".format(read=", ".join(READ_ROOTS), write=", ".join(WRITE_ROOTS), kb=MAX_NOTE // 1024)


class Refused(Exception):
    """A request this gate will not run (reported to the caller, logged as refused)."""


# ---------------------------------------------------------------------------------------------- validation
def check_path(raw, roots, note):
    """Normalized vault path, or Refused. note=True: must name a .md note; False: a listing prefix."""
    if raw is None or raw == "":
        raise Refused("a path is required")
    path = unicodedata.normalize("NFC", raw)
    if len(path) > MAX_PATH:
        raise Refused(f"path longer than {MAX_PATH} characters")
    if path != path.strip() or path.startswith("/") or "//" in path or "\\" in path:
        raise Refused("path must be relative, without leading/trailing spaces, '//' or '\\'")
    if any(c in path for c in "\"`$*?<>|:;\t\r\n\0"):
        raise Refused("path contains a character that is not allowed (do not quote the path)")
    if not any(path.startswith(r) or (not note and r.startswith(path) and path.endswith("/")) for r in roots):
        raise Refused(f"path must be under {', '.join(roots)}")
    parts = path.rstrip("/").split("/") if not note else path.split("/")
    if len(parts) > MAX_PARTS:
        raise Refused(f"path is deeper than {MAX_PARTS} parts")
    for p in parts:
        if p in (".", "..") or p.startswith(".") or p != p.strip() or not PART_RE.fullmatch(p):
            raise Refused(f"path part not allowed: {p!r}")
    if note and not path.endswith(".md"):
        raise Refused("note path must end in .md")
    return path


def parse(request):
    """(verb, argument) from $SSH_ORIGINAL_COMMAND, or Refused."""
    if not request or not request.strip():
        return "help", ""
    if any(ord(c) < 32 for c in request):
        raise Refused("control characters in request")
    verb, _, arg = request.partition(" ")
    if not VERB_RE.fullmatch(verb) or verb not in ("help", "list", "get", "create"):
        raise Refused(f"unknown command {verb[:20]!r} (try: help)")
    return verb, arg


def check_note_text(data):
    if len(data) > MAX_NOTE:
        raise Refused(f"note is larger than {MAX_NOTE // 1024} KiB")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        raise Refused("note text is not UTF-8")
    if "\0" in text:
        raise Refused("note text contains NUL bytes")
    if not text.strip():
        raise Refused("note text is empty")
    return text


def course_root(path):
    """'Career/Courses/<course>/' of a write path (a note must go inside an existing course)."""
    parts = path.split("/")
    if len(parts) < 4:
        raise Refused("a note must go inside a course folder: Career/Courses/<course>/.../<note>.md")
    return "/".join(parts[:3]) + "/"


# ---------------------------------------------------------------------------------------------- secrets
def _pp(args, extra_env=None):
    env = {"PATH": "/usr/bin:/bin", "HOME": str(HOME), "LANG": "C.UTF-8",
           "PROTON_PASS_SESSION_DIR": str(HOME / ".pp-session"), "PROTON_PASS_KEY_PROVIDER": "fs",
           "PROTON_PASS_NO_UPDATE_CHECK": "1", "PROTON_PASS_DISABLE_TELEMETRY": "1", "NO_COLOR": "1"}
    env.update(extra_env or {})
    return subprocess.run([PASS_CLI, *args], env=env, capture_output=True, timeout=30)


def _view_all():
    # The PAT is granted single ITEMS, not the vault: it sees no vault by name (--vault-name fails), each item is its
    # own share. So: share id by item title from `share list`, then view by share id (verified 2026-10-28).
    r = _pp(["share", "list", "--only-items", "true", "--output", "json"])
    if r.returncode != 0:
        return None
    try:
        shares = {s["name"]: s["id"] for s in json.loads(r.stdout)["shares"]}
    except (ValueError, KeyError, TypeError):
        return None
    values = {}
    for var, title in SECRETS.items():
        if title not in shares:
            return None
        r = _pp(["item", "view", "--share-id", shares[title], "--item-title", title, "--field", "note"])
        if r.returncode != 0 or not r.stdout.strip():
            return None
        values[var] = r.stdout.decode().strip()
    return values


def load_secrets():
    """The three vault secrets, from the kept pass-cli session; one PAT login only when the session is gone."""
    values = _view_all()
    if values:
        return values, "session"
    session = HOME / ".pp-session"
    subprocess.run(["/bin/rm", "-rf", str(session)], check=False)
    session.mkdir(mode=0o700)
    pat = subprocess.run(["/usr/bin/sudo", "-n", UNSEAL], capture_output=True, timeout=15)
    if pat.returncode != 0 or not pat.stdout.strip():
        raise RuntimeError("could not read this account's PAT from the TPM")
    r = _pp(["login"], {"PROTON_PASS_PERSONAL_ACCESS_TOKEN": pat.stdout.decode().strip()})
    if r.returncode != 0:
        raise RuntimeError("Proton Pass login failed (rate limit? wait ~5 minutes and retry)")
    values = _view_all()
    if not values:
        raise RuntimeError("logged in, but the vault items could not be read")
    return values, "login"


def vault_module(secrets):
    """MCC's vault_fetch, with this process's secrets and a stub dotenv (MCC's .env is neither readable nor used)."""
    os.environ.update(secrets)
    os.environ.update({"COUCHDB_URL": COUCHDB_URL, "MCC_AUDIT_DIR": str(HOME / "audit"),
                       "MCC_AUDIT_SYSLOG": AUDIT_SYSLOG})
    stub = types.ModuleType("dotenv")
    stub.load_dotenv = lambda *a, **k: False
    sys.modules["dotenv"] = stub
    sys.path[:0] = [MCC_ROOT, f"{MCC_ROOT}/tools"]
    import vault_fetch  # noqa: E402  (path set just above)
    return vault_fetch


# ---------------------------------------------------------------------------------------------- commands
def handle(request, stdin):
    """(exit code, output text, outcome for the log, detail for the log)."""
    try:
        verb, arg = parse(request)
        if verb == "help":
            return 0, HELP, "ok", "help"
        if verb == "list":
            path = check_path(arg, READ_ROOTS, note=False)
        elif verb == "get":
            path = check_path(arg, READ_ROOTS, note=True)
        else:
            path = check_path(arg, WRITE_ROOTS, note=True)
            course = course_root(path)
            text = check_note_text(stdin.read(MAX_NOTE + 1))
    except Refused as e:
        return 2, f"REFUSED: {e}\n", "refused", str(e)

    lock = open(HOME / ".lock", "w")
    fcntl.flock(lock, fcntl.LOCK_EX)          # one request at a time: no parallel Proton logins or duplicate creates
    try:
        secrets, how = load_secrets()
        vf = vault_module(secrets)
        if verb == "list":
            notes = sorted(n for n in vf.list_notes(path) if any(n.startswith(r) for r in READ_ROOTS))
            return 0, "".join(n + "\n" for n in notes) or "(no notes)\n", "ok", f"{verb} {path} n={len(notes)} {how}"
        if verb == "get":
            text = vf.get_note(path)
            if text is None:
                return 1, f"NOT FOUND: {path}\n", "notfound", f"{verb} {path}"
            return 0, text, "ok", f"{verb} {path} {how}"
        existing = vf.list_notes(course)
        if not existing:
            return 2, f"REFUSED: no course folder {course} (create the course hub first)\n", "refused", f"no course {course}"
        if any(n.casefold() == path.casefold() for n in existing):
            return 2, f"REFUSED: {path} already exists (create-only: pick another name)\n", "refused", f"exists {path}"
        if not vf.put_note(path, text):
            return 1, f"FAILED: CouchDB did not accept {path}\n", "failed", f"create {path}"
        n = len(text.encode("utf-8"))
        return 0, f"CREATED {path} ({n} bytes)\n", "ok", f"create {path} bytes={n} {how}"
    except Exception as e:   # reported without values: the messages above never contain secrets
        return 1, f"FAILED: {type(e).__name__}: {e}\n", "failed", f"{verb} {type(e).__name__}"
    finally:
        lock.close()


def audit(client, outcome, detail, ms):
    syslog.openlog("hermes-vault", syslog.LOG_PID, syslog.LOG_AUTH)
    syslog.syslog(syslog.LOG_NOTICE if outcome == "ok" else syslog.LOG_WARNING,
                  f"client={client} outcome={outcome} ms={ms} {detail[:400]}")


def main():
    signal.alarm(TIMEOUT_S)
    os.umask(0o077)
    client = (os.environ.get("SSH_CLIENT") or "unknown").split()[0]
    t0 = time.monotonic()
    code, text, outcome, detail = handle(os.environ.get("SSH_ORIGINAL_COMMAND"), sys.stdin.buffer)
    audit(client, outcome, detail, int((time.monotonic() - t0) * 1000))
    sys.stdout.write(text[:MAX_OUT])
    return code


if __name__ == "__main__":
    sys.exit(main())
