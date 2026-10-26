#!/bin/bash
# trivy-scan.sh - scan every running container image with Trivy and write
# Wazuh-friendly JSON lines (one per finding) for the agent to read.
#
#   findings.ndjson : one line per NEW Critical/High finding that has a fix,
#                     plus one summary line per image per run.
#   seen.txt        : keys already reported (host|image-id|pkg|cve), so a daily
#                     run alerts once per finding, not once per day.
#
# Trivy runs as a pinned container (no install on the host) and reads images
# through the Docker socket (read-only mount). Both vulnerability DBs (main + Java, ~3 GB in the
# trivy-cache volume) refresh themselves; Java images (jars) cannot be scanned without the Java DB.
set -u

TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:0.76.1}"
BASE="${TRIVY_BASE:-$HOME/trivy}"
OUT="$BASE/findings.ndjson"
SEEN="$BASE/seen.txt"
TMP="$(mktemp -d)"
HOST="$(hostname -s)"
SEVERITIES="${TRIVY_SEVERITIES:-CRITICAL,HIGH}"
# Paths Trivy must not scan (comma-separated globs). GitLab's Web IDE bundles VS Code language
# extensions named handlebars/npm/ini/json/diff at version 1.0.0; Trivy matches them to the npm
# libraries of the same name and reports false Critical/High findings (2026-10-24).
SKIP_DIRS="${TRIVY_SKIP_DIRS:-**/gitlab-web-ide-vscode-workbench-*/vscode/extensions}"

mkdir -p "$BASE"
touch "$OUT" "$SEEN"
trap 'rm -rf "$TMP"' EXIT

# image -> container names (several containers can share an image)
docker ps --format '{{.Image}}|{{.Names}}' | sort > "$TMP/map.txt"

# TRIVY_IMAGES="img1 img2" limits a run (used for tests); default = every running image.
if [ -n "${TRIVY_IMAGES:-}" ]; then
  printf '%s\n' $TRIVY_IMAGES
else
  cut -d'|' -f1 "$TMP/map.txt" | sort -u
fi | while read -r img; do
  n="$(echo "$img" | tr '/:' '__')"
  # Trivy unpacks big images into temp space (2026-10-23: a full run took rocky's / down to 1.7 GB free).
  # Skip, and say so, rather than risk filling the disk.
  free_mb="$(df -Pm / 2>/dev/null | awk 'NR==2{print $4}')"   # Docker's data root is on / on every host
  if [ "${free_mb:-0}" -lt "${TRIVY_MIN_FREE_MB:-8192}" ]; then
    printf '{"trivy":{"type":"error","host":"%s","image":"%s","error":"scan skipped: low disk (%s MB free)"}}\n' "$HOST" "$img" "${free_mb:-?}" >> "$OUT"
    continue
  fi
  # The tag can be gone while the image is still there under its digest (compose pins by digest, e.g. immich).
  # Fall back to the image ID of a container that runs it; only if that is gone too, report it.
  target="$img"
  if ! docker image inspect "$img" >/dev/null 2>&1; then
    cname="$(grep -F -m1 "$img|" "$TMP/map.txt" | cut -d'|' -f2)"
    cid="$(docker inspect "$cname" --format '{{.Image}}' 2>/dev/null)"
    if [ -n "$cid" ] && docker image inspect "$cid" >/dev/null 2>&1; then
      target="$cid"
    else
      printf '{"trivy":{"type":"error","host":"%s","image":"%s","error":"image not in local store (container runs from a deleted image)"}}\n' "$HOST" "$img" >> "$OUT"
      continue
    fi
  fi
  if docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        -v trivy-cache:/root/.cache/ \
        "$TRIVY_IMAGE" image --quiet --format json --scanners vuln --skip-dirs "$SKIP_DIRS" \
        "$target" > "$TMP/$n.json" 2> "$TMP/$n.err"; then
    python3 - "$TMP/$n.json" "$img" "$TMP/map.txt" "$HOST" "$SEEN" "$SEVERITIES" >> "$OUT" <<'PY'
import json, sys, time
path, img, mapf, host, seenf, sevs = sys.argv[1:7]
sevs = set(sevs.split(","))
names = sorted({l.split("|", 1)[1].strip() for l in open(mapf) if l.split("|", 1)[0] == img})
d = json.load(open(path))
image_id = (d.get("Metadata") or {}).get("ImageID", img)
seen = set(l.strip() for l in open(seenf))
counts = {}
new_keys = []
for r in d.get("Results") or []:
    for v in r.get("Vulnerabilities") or []:
        s = v["Severity"]
        counts[s] = counts.get(s, 0) + 1
        if s not in sevs or not v.get("FixedVersion"):
            continue
        key = "|".join([host, image_id, v["PkgName"], v["VulnerabilityID"]])
        if key in seen:
            continue
        new_keys.append(key)
        seen.add(key)   # same pkg+CVE in several jars/files of one image: report once
        print(json.dumps({"trivy": {
            "type": "finding", "host": host, "image": img,
            "containers": ",".join(names), "target": r.get("Target"),
            "pkg": v["PkgName"], "installed": v.get("InstalledVersion"),
            "fixed": v.get("FixedVersion"), "cve": v["VulnerabilityID"],
            "severity": s, "title": (v.get("Title") or "")[:200]}}))
print(json.dumps({"trivy": {
    "type": "summary", "host": host, "image": img, "containers": ",".join(names),
    "critical": counts.get("CRITICAL", 0), "high": counts.get("HIGH", 0),
    "medium": counts.get("MEDIUM", 0), "low": counts.get("LOW", 0),
    "new_reported": len(new_keys), "scanned": int(time.time())}}))
with open(seenf, "a") as f:
    f.write("".join(k + "\n" for k in new_keys))
PY
  else
    printf '{"trivy":{"type":"error","host":"%s","image":"%s","error":"scan failed"}}\n' "$HOST" "$img" >> "$OUT"
  fi
done
