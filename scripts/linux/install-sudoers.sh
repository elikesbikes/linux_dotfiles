#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="/home/ecloaiza/sudoers"
DST_DIR="/etc/sudoers.d"

echo "==> Installing sudoers fragments"
echo "    Source dir : ${SRC_DIR}"
echo "    Target dir : ${DST_DIR}"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "ERROR: Source directory not found: $SRC_DIR"
  exit 1
fi

# Only install numbered fragments (ignore README.md and legacy files like ecloaiza-nopasswd)
mapfile -t FRAGMENTS < <(
  ls -1 "$SRC_DIR" 2>/dev/null \
    | grep -E '^[0-9]{2}-' \
    | sort
)

if [[ "${#FRAGMENTS[@]}" -eq 0 ]]; then
  echo "ERROR: No sudoers fragments found in $SRC_DIR (expected files like 00-defaults, 10-admin, ...)"
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/var/tmp/sudoers.d-backup-${TS}"
mkdir -p "$BACKUP_DIR"

# Track which files existed so rollback can restore/delete appropriately
declare -A EXISTED=()
declare -a INSTALLED=()

rollback() {
  echo "!! ERROR detected; rolling back sudoers.d changes"
  for f in "${INSTALLED[@]}"; do
    dst="${DST_DIR}/${f}"
    if [[ "${EXISTED[$f]:-0}" -eq 1 ]]; then
      if [[ -f "${BACKUP_DIR}/${f}" ]]; then
        sudo install -m 0440 "${BACKUP_DIR}/${f}" "$dst"
        echo "    Restored: $dst"
      fi
    else
      sudo rm -f "$dst"
      echo "    Removed : $dst"
    fi
  done

  echo "Rollback complete. Validate sudo with: sudo visudo -c"
}

trap rollback ERR

echo "==> Backing up existing destination files (if any) to: ${BACKUP_DIR}"
for f in "${FRAGMENTS[@]}"; do
  dst="${DST_DIR}/${f}"
  if sudo test -f "$dst"; then
    EXISTED["$f"]=1
    sudo cp -a "$dst" "${BACKUP_DIR}/${f}"
  else
    EXISTED["$f"]=0
  fi
done

echo "==> Installing fragments..."
for f in "${FRAGMENTS[@]}"; do
  src="${SRC_DIR}/${f}"
  dst="${DST_DIR}/${f}"

  if [[ ! -f "$src" ]]; then
    echo "ERROR: Missing fragment source file: $src"
    exit 1
  fi

  echo "    -> ${f}"
  sudo install -m 0440 "$src" "$dst"

  # Validate each fragment after install
  sudo visudo -cf "$dst" >/dev/null

  INSTALLED+=("$f")
done

echo "==> Validating full sudo configuration"
sudo visudo -c >/dev/null

trap - ERR
echo "✔ All sudoers fragments installed and validated successfully"
