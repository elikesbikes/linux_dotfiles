#!/usr/bin/env python3
"""SSHTars host catalog: read the Obsidian note, validate it, print JSON.

Run by the broker's `catalog` command on hailmary. The note lives in the Obsidian
vault (CouchDB on hailmary) and holds one ```yaml block:

    groups: [{name, parent?, username?, port?, key?, via_hailmary?}]
    hosts:  [{label, hostname, group?, port?, username?, key?, tags?, via_hailmary?}]

`key` is a Proton Pass SSH key *name* (its comment in the HOMELAB agent).

    catalog.py              -> JSON for the app ({"version": 1, "groups": [...], "hosts": [...]})
    catalog.py --permitopen -> permitopen="host:port",... for devices' authorized_keys lines

Source: sshtars-ios repo tools/broker/catalog.py.
"""
import json
import os
import re
import subprocess
import sys

NOTE = "IT/github/adastra/Homelab/sshtars/hosts.md"
MCC = os.path.expanduser("~/devops/projects/mcc")

GROUP_KEYS = {"name", "parent", "username", "port", "key", "via_hailmary"}
HOST_KEYS = {"label", "hostname", "group", "port", "username", "key", "tags", "via_hailmary"}


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
    names = set()
    for i, g in enumerate(groups):
        if not isinstance(g, dict) or not g.get("name"):
            fail(f"groups[{i}] needs a name")
        unknown = set(g) - GROUP_KEYS
        if unknown:
            fail(f"group {g['name']}: unknown field(s) {sorted(unknown)}")
        if g["name"] in names:
            fail(f"group {g['name']} is listed twice")
        names.add(g["name"])
    for g in groups:
        if g.get("parent") and g["parent"] not in names:
            fail(f"group {g['name']}: parent {g['parent']} isn't a group")
    labels = set()
    for i, h in enumerate(hosts):
        if not isinstance(h, dict) or not h.get("label") or not h.get("hostname"):
            fail(f"hosts[{i}] needs label and hostname")
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
            if target not in targets:
                targets.append(target)
    return ",".join(f'permitopen="{t}"' for t in targets)


def main():
    doc = parse(load_note())
    if "--permitopen" in sys.argv:
        print(permitopen(doc))
    else:
        print(json.dumps(doc))


if __name__ == "__main__":
    main()
