#!/usr/bin/env bash
set -euo pipefail

USER_HOME="/home/ecloaiza"

# Known DevOps/GitHub path variations across hosts
GITHUB_BASES=(
  "${USER_HOME}/DevOps/GitHub"
  "${USER_HOME}/devops/github"
)

REPO_DIR=""
for base in "${GITHUB_BASES[@]}"; do
  if [[ -d "${base}/linux_dotfiles" ]]; then
    REPO_DIR="${base}/linux_dotfiles"
    break
  fi
done

if [[ -z "$REPO_DIR" ]]; then
  echo "ERROR: linux_dotfiles repo not found."
  echo "Checked the following paths:"
  for base in "${GITHUB_BASES[@]}"; do
    echo "  - ${base}/linux_dotfiles"
  done
  exit 1
fi

SRC="${REPO_DIR}/sudoers/ecloaiza-nopasswd"
DST="/etc/sudoers.d/ecloaiza-nopasswd"

echo "==> Installing sudoers rules"
echo "    Dotfiles repo : ${REPO_DIR}"
echo "    Source file  : ${SRC}"
echo "    Target file  : ${DST}"

if [[ ! -f "$SRC" ]]; then
  echo "ERROR: sudoers source file not found: $SRC"
  exit 1
fi

# Install with correct ownership and permissions
sudo install -m 0440 "$SRC" "$DST"

# Validate syntax before sudo can break
sudo visudo -cf "$DST"

echo "✔ sudoers rules installed and validated successfully"
