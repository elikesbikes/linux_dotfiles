#!/usr/bin/env python3
# audit-exempt: library + CLI used by pass-secrets.sh / MCC secrets.sh; every outcome is logged by the caller
"""TPM-sealed local cache of Proton Pass secrets ("offline mode" for unattended starts).

Why: Proton rate-limits PAT logins (429, code 2028 "Too many recent logins", Retry-After ~270 s).
Every service start used to log in. With this cache a start (1) skips the login when the cache is
fresh (default 10 min, so a deploy that loads 3 times logs in once), and (2) still starts when Proton
refuses or times out, from a copy at most MAX_AGE old (default 7 days), loudly ("degraded").

Crypto: one random 32-byte AES key per host and user, sealed by this host's TPM / vTPM
(tpm2_create under a transient owner-hierarchy ECC primary; only the public/private blobs are on disk,
the TPM can unseal them and no other machine can). Each component's values are AES-256-GCM encrypted
with that key; the header (component, key-set hash, created) is bound as associated data, so editing it
breaks decryption. Plaintext exists only in this process's memory and the caller's pipe, never on disk.
Same trust model as the TPM-sealed PAT: whoever can unseal the PAT on this host can unseal this.

CLI (values travel as NUL-separated KEY\\0VALUE\\0 pairs on stdin/stdout, never argv):
  put  <component> <keyset>             store stdin pairs
  get  <component> <keyset> <max_age_s> print pairs; exit 0 hit, 3 miss (absent/stale/other key set),
                                        4 cannot decrypt (TPM/key changed, tampered)
  age  <component>                      seconds since the cache was written, or -1 (no decryption)
  drop <component>                      delete it (compromise runbook)
Dir: $PP_CACHE_DIR or ~/.local/state/proton-pass-cache (mode 700).
"""
import fcntl
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

VERSION = 1
MISS, BAD = 3, 4


def cache_dir():
    d = Path(os.environ.get("PP_CACHE_DIR") or Path.home() / ".local/state/proton-pass-cache")
    d.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(d, 0o700)
    return d


def _tpm(args, **kw):
    return subprocess.run(args, check=True, capture_output=True, timeout=30, **kw)


def _primary(tmp):
    ctx = os.path.join(tmp, "primary.ctx")
    # Same template every time -> same primary (derived from the owner seed); nothing persistent.
    _tpm(["tpm2_createprimary", "-Q", "-C", "o", "-G", "ecc", "-c", ctx])
    return ctx


def _host_key(create):
    """The host's AES key (hex), unsealed into memory. create=True makes one on first use."""
    d = cache_dir()
    pub, priv = d / "key.pub", d / "key.priv"
    with os.fdopen(os.open(d / ".key.lock", os.O_WRONLY | os.O_CREAT, 0o600), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)              # two first-time writers must not make two keys
        with tempfile.TemporaryDirectory(prefix="pp-tpm-") as tmp:
            primary = _primary(tmp)
            if not (pub.exists() and priv.exists()):
                if not create:
                    return None
                tp, tv = d / ".key.pub.new", d / ".key.priv.new"
                _tpm(["tpm2_create", "-Q", "-C", primary, "-i", "-", "-u", str(tp), "-r", str(tv)],
                     input=os.urandom(32).hex().encode())
                os.chmod(tp, 0o600); os.chmod(tv, 0o600)
                os.replace(tp, pub); os.replace(tv, priv)
            obj = os.path.join(tmp, "key.ctx")
            _tpm(["tpm2_load", "-Q", "-C", primary, "-u", str(pub), "-r", str(priv), "-c", obj])
            key = _tpm(["tpm2_unseal", "-c", obj]).stdout.decode().strip()
    if len(key) != 64:
        raise ValueError("unsealed key has the wrong length")
    return bytes.fromhex(key)


def _aad(component, keyset, created):
    return f"pp{VERSION}|{component}|{keyset}|{created}".encode()


def _path(component):
    if not component or "/" in component or component.startswith("."):
        raise ValueError(f"bad component name {component!r}")
    return cache_dir() / f"{component}.cache"


def _read_pairs(data):
    parts = data.split(b"\0")
    if parts and parts[-1] == b"":
        parts.pop()
    if len(parts) % 2:
        raise ValueError("odd number of NUL-separated fields")
    return parts


def put(component, keyset, data):
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    _read_pairs(data)                                  # validate before storing
    created = int(time.time())
    nonce = os.urandom(12)
    blob = nonce + AESGCM(_host_key(create=True)).encrypt(nonce, data, _aad(component, keyset, created))
    doc = {"v": VERSION, "component": component, "keyset": keyset, "created": created,
           "host": socket.gethostname(), "blob": blob.hex()}
    p = _path(component)
    fd, tmp = tempfile.mkstemp(dir=p.parent, prefix=f".{component}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:                  # mkstemp: mode 600; holds ciphertext only
            json.dump(doc, f)
        os.replace(tmp, p)
    except BaseException:
        os.unlink(tmp)
        raise


def _load(component):
    try:
        return json.loads(_path(component).read_text())
    except FileNotFoundError:
        return None


def get(component, keyset, max_age):
    from cryptography.exceptions import InvalidTag
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    doc = _load(component)
    if not doc or doc.get("v") != VERSION or doc.get("keyset") != keyset:
        return MISS, b""
    if time.time() - doc["created"] > max_age:
        return MISS, b""
    try:
        key = _host_key(create=False)
        if key is None:
            return BAD, b""
        blob = bytes.fromhex(doc["blob"])
        data = AESGCM(key).decrypt(blob[:12], blob[12:], _aad(component, keyset, doc["created"]))
        _read_pairs(data)
        return 0, data
    except (InvalidTag, ValueError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return BAD, b""


def age(component):
    doc = _load(component)
    return int(time.time() - doc["created"]) if doc else -1


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, component = argv[0], argv[1]
    if cmd == "put" and len(argv) == 3:
        put(component, argv[2], sys.stdin.buffer.read())
        return 0
    if cmd == "get" and len(argv) == 4:
        rc, data = get(component, argv[2], int(argv[3]))
        sys.stdout.buffer.write(data)
        return rc
    if cmd == "age" and len(argv) == 2:
        print(age(component))
        return 0
    if cmd == "drop" and len(argv) == 2:
        _path(component).unlink(missing_ok=True)
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
