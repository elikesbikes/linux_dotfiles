#!/usr/bin/env python3
"""SSHTars host catalog: read the Obsidian note, validate it, print JSON.

Run by the broker's `catalog` command on hailmary. The note lives in the Obsidian
vault (CouchDB on hailmary) and holds one ```yaml block:

    groups: [{name, parent?, username?, port?, key?, via_hailmary?}]
    hosts:  [{label, hostname, group?, port?, username?, key?, tags?, via_hailmary?}]

`key` is a Proton Pass SSH key *name*: the item title as the device's agent lists it. Since 2026-11-12 every SSH key
lives in the HOMELAB vault (folder "SSH"), so the agent hailmary hands a device lists every key, and the device keys
need distinct titles: "SSHTars <device> identity". The note keeps the one shared name "SSHTars device identity";
with --device <name> (the broker passes it) that name is printed as "SSHTars <name> identity" for that device.

    catalog.py              -> JSON for the app ({"version": 1, "groups": [...], "hosts": [...]})
    catalog.py --device X   -> same, with the shared device key name turned into X's own key title
    catalog.py --permitopen -> permitopen="host:port",... for devices' authorized_keys lines; when no host is
                               reached through hailmary, one placeholder that allows no destination (NO_HOSTS)

`hostname` and `port` end up inside permitopen="host:port" in hailmary's authorized_keys (refresh-permitopen), so
they are checked strictly (sshtars-ios #1): a hostname is DNS labels or an IPv4 address (letters, digits, dots and
hyphens) or an IPv6 address in brackets, a port a whole number 1-65535. Anything else fails the whole catalog.
Field types are checked too (sshtars-ios #105): `via_hailmary` is true or false, never a quoted "false" (a non-empty
string is truthy and would grant the host); names, usernames and key names are text (YAML reads `name: on` as a
bool and `username: 1000` as a number, and the app cannot decode either).

Source: sshtars-ios repo tools/broker/catalog.py. Tests: tools/broker/test_catalog.py.
"""
import ipaddress
import json
import os
import re
import subprocess
import sys

NOTE = "IT/github/adastra/Homelab/projects/SSHTars hosts.md"
MCC = os.path.expanduser("~/devops/projects/mcc")

GROUP_KEYS = {"name", "parent", "username", "port", "key", "via_hailmary"}
HOST_KEYS = {"label", "hostname", "group", "port", "username", "key", "tags", "via_hailmary"}
TEXT_FIELDS = ("name", "label", "parent", "group", "username", "key")
DEVICE_KEY = "SSHTars device identity"
# --permitopen with no via_hailmary host (#105): an empty list would leave a device line with port-forwarding and
# no permitopen, which is every destination. `.invalid` never resolves, so this one allows none.
NO_HOSTS = 'permitopen="no-hosts.invalid:1"'
LABEL_RE = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?")
IPV6_RE = re.compile(r"\[([0-9A-Fa-f:.]{2,45})\]")      # no zone ids: "%" could carry anything


def fail(message):
    # The app reads the error from stdout, so exit 0 unless a script asked for permitopen.
    print(json.dumps({"version": 1, "error": message}))
    sys.exit(2 if "--permitopen" in sys.argv else 0)


def load_note():
    if os.environ.get("SSHTARS_CATALOG_FILE"):  # tests / fixtures
        with open(os.environ["SSHTARS_CATALOG_FILE"]) as f:
            return f.read()
    out = subprocess.run(
        ["python3", "tools/vault_fetch.py", "--get", NOTE],
        cwd=MCC, capture_output=True, text=True, timeout=60,
    )
    if out.returncode != 0:
        fail(f"could not read {NOTE} from the vault: {out.stderr.strip()[:200]}")
    return out.stdout


def valid_hostname(value) -> bool:
    """DNS name or IPv4 (labels of letters, digits and inner hyphens, joined by dots), or [IPv6]."""
    if not isinstance(value, str) or not value or len(value) > 253:
        return False
    v6 = IPV6_RE.fullmatch(value)
    if v6:
        try:
            ipaddress.IPv6Address(v6.group(1))
            return True
        except ValueError:
            return False
    return all(LABEL_RE.fullmatch(label) for label in value.split("."))


def valid_port(value) -> bool:
    # bool is an int in Python (YAML `port: yes`); a string "22" is refused too: the note writes numbers.
    return isinstance(value, int) and not isinstance(value, bool) and 1 <= value <= 65535


def check_port(entry, what):
    if entry.get("port") is not None and not valid_port(entry["port"]):
        fail(f"{what}: port must be a whole number from 1 to 65535, not {entry['port']!r}")


def check_types(entry, what):
    """#105: the app decodes these as String / Bool, and `via_hailmary` decides what a device key may reach."""
    for field in TEXT_FIELDS:
        if entry.get(field) is not None and not isinstance(entry[field], str):
            fail(f"{what}: {field} must be text, not {entry[field]!r} (put it in quotes)")
    if entry.get("via_hailmary") is not None and not isinstance(entry["via_hailmary"], bool):
        fail(f"{what}: via_hailmary must be true or false without quotes, not {entry['via_hailmary']!r}")


def parse(text):
    import yaml  # PyYAML (present on hailmary)

    match = re.search(r"```ya?ml\s*\n(.*?)```", text, re.S)
    if not match:
        fail("the note has no ```yaml block")
    try:
        doc = yaml.safe_load(match.group(1)) or {}
    except yaml.YAMLError as e:
        fail(f"YAML error: {e}")
    if not isinstance(doc, dict):
        fail("the yaml block must be a mapping with groups: and hosts:")

    groups, hosts = doc.get("groups") or [], doc.get("hosts") or []
    if not isinstance(groups, list) or not isinstance(hosts, list):
        fail("groups: and hosts: must be lists")
    names = set()
    for i, g in enumerate(groups):
        if not isinstance(g, dict) or not g.get("name"):
            fail(f"groups[{i}] needs a name")
        check_types(g, f"groups[{i}]" if not isinstance(g["name"], str) else f"group {g['name']}")
        unknown = set(g) - GROUP_KEYS
        if unknown:
            fail(f"group {g['name']}: unknown field(s) {sorted(unknown)}")
        if g["name"] in names:
            fail(f"group {g['name']} is listed twice")
        check_port(g, f"group {g['name']}")
        names.add(g["name"])
    for g in groups:
        if g.get("parent") and g["parent"] not in names:
            fail(f"group {g['name']}: parent {g['parent']} isn't a group")
    labels = set()
    for i, h in enumerate(hosts):
        if not isinstance(h, dict) or not h.get("label") or not h.get("hostname"):
            fail(f"hosts[{i}] needs label and hostname")
        check_types(h, f"hosts[{i}]" if not isinstance(h["label"], str) else f"host {h['label']}")
        if h.get("tags") is not None and not isinstance(h["tags"], list):
            fail(f"host {h['label']}: tags must be a list like [a, b], not {h['tags']!r}")
        unknown = set(h) - HOST_KEYS
        if unknown:
            fail(f"host {h['label']}: unknown field(s) {sorted(unknown)}")
        if h["label"] in labels:
            fail(f"host {h['label']} is listed twice")
        labels.add(h["label"])
        if h.get("group") and h["group"] not in names:
            fail(f"host {h['label']}: group {h['group']} isn't a group")
        h["tags"] = [str(t) for t in (h.get("tags") or [])]
        h["hostname"] = str(h["hostname"])
        if not valid_hostname(h["hostname"]):
            fail(f"host {h['label']}: hostname {h['hostname'][:80]!r} is not a DNS name, an IPv4 address or an [IPv6] address")
        check_port(h, f"host {h['label']}")
    return {"version": 1, "groups": groups, "hosts": hosts}


def effective(host, groups_by_name, field, default=None):
    """Host value, else nearest group's (same inheritance as the app)."""
    if host.get(field) is not None:
        return host[field]
    seen, name = set(), host.get("group")
    while name and name not in seen:
        seen.add(name)
        g = groups_by_name[name]
        if g.get(field) is not None:
            return g[field]
        name = g.get("parent")
    return default


def permitopen(doc):
    groups = {g["name"]: g for g in doc["groups"]}
    targets = []
    for h in doc["hosts"]:
        if effective(h, groups, "via_hailmary", False):
            target = f'{h["hostname"]}:{effective(h, groups, "port", 22)}'
            if not re.fullmatch(r"[A-Za-z0-9.\-\[\]:]+:[0-9]{1,5}", target):      # parse() checked; belt and braces
                fail(f"host {h['label']}: refusing permitopen target {target[:80]!r}")
            if target not in targets:
                targets.append(target)
    if not targets:
        print("no host is reached through hailmary: printing a permitopen that allows no destination", file=sys.stderr)
        return NO_HOSTS
    return ",".join(f'permitopen="{t}"' for t in targets)


def device_arg():
    if "--device" not in sys.argv:
        return None
    i = sys.argv.index("--device")
    name = sys.argv[i + 1] if i + 1 < len(sys.argv) else ""
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,40}", name):
        fail("bad --device name")
    return name


def per_device(doc, device):
    """Turn the shared device key name into this device's own key title."""
    for entry in doc["groups"] + doc["hosts"]:
        if entry.get("key") == DEVICE_KEY:
            entry["key"] = f"SSHTars {device} identity"
    return doc


def main():
    device = device_arg()
    doc = parse(load_note())
    if device:
        doc = per_device(doc, device)
    if "--permitopen" in sys.argv:
        print(permitopen(doc))
    else:
        print(json.dumps(doc))


if __name__ == "__main__":
    main()
