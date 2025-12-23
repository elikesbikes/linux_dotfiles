#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# GNOME Extensions Installer (Omakub-style via gext)
# - Reads desired state from extensions.conf
# - Installs missing extensions via gnome-extensions-cli (gext)
# - Enables/disables per desired state
# - Only manages extensions listed in extensions.conf
# - Logs everything
# - Works when launched from gum menus by using /dev/tty
# ==================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/extensions.conf"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding"
LOG_DIR="$STATE_DIR/logs"
LOG_FILE="$LOG_DIR/install_extensions.log"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[extensions] Auto-install + Reconcile (gext)"
echo "=================================================="
echo "Date: $(date)"
echo "Log : $LOG_FILE"
echo

# --------------------------------------------------
# Preconditions
# --------------------------------------------------
if ! command -v gnome-extensions >/dev/null 2>&1; then
  echo "GNOME not detected (gnome-extensions missing)."
  echo "Skipping extensions."
  exit 0
fi

if ! command -v gnome-shell >/dev/null 2>&1; then
  echo "gnome-shell not found. Skipping extensions."
  exit 0
fi

GNOME_VERSION="$(gnome-shell --version | awk '{print $3}')"
GNOME_MAJOR="${GNOME_VERSION%%.*}"

echo "Detected distro      : $(. /etc/os-release 2>/dev/null && echo "${ID:-unknown}" || echo unknown)"
echo "GNOME Shell (major)  : $GNOME_MAJOR ($GNOME_VERSION)"
echo

if [[ ! -f "$CONF_FILE" ]]; then
  echo "ERROR: extensions.conf not found at: $CONF_FILE"
  exit 1
fi

# We must use /dev/tty for interactive tools because gum menus can break stdin.
HAS_TTY=0
if [[ -e /dev/tty ]]; then
  HAS_TTY=1
fi

# --------------------------------------------------
# Distro helpers
# --------------------------------------------------
detect_distro() {
  local id="unknown"
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-unknown}"
  fi
  echo "$id"
}

install_pkgs_ubuntu() {
  local pkgs=("$@")
  sudo apt-get update
  sudo apt-get install -y "${pkgs[@]}"
}

install_pkgs_arch() {
  local pkgs=("$@")
  sudo pacman -Sy --noconfirm "${pkgs[@]}"
}

ensure_deps() {
  local distro
  distro="$(detect_distro)"

  echo "Preparing system dependencies..."
  case "$distro" in
    ubuntu|debian)
      echo "Ensuring deps (Ubuntu): curl jq unzip python3 python3-pip pipx"
      install_pkgs_ubuntu curl jq unzip python3 python3-pip pipx
      ;;
    arch)
      echo "Ensuring deps (Arch): curl jq unzip python python-pipx"
      install_pkgs_arch curl jq unzip python python-pipx
      ;;
    *)
      echo "WARN: Unknown distro '$distro'. Attempting best-effort deps."
      if command -v apt-get >/dev/null 2>&1; then
        echo "Best-effort via apt: curl jq unzip python3 python3-pip pipx"
        install_pkgs_ubuntu curl jq unzip python3 python3-pip pipx
      elif command -v pacman >/dev/null 2>&1; then
        echo "Best-effort via pacman: curl jq unzip python python-pipx"
        install_pkgs_arch curl jq unzip python python-pipx
      else
        echo "ERROR: No supported package manager found (apt/pacman)."
        exit 1
      fi
      ;;
  esac

  # Ensure pipx path is set for this shell
  if command -v pipx >/dev/null 2>&1; then
    # pipx ensurepath may print messages; do not fail script if it does
    pipx ensurepath || true
    # Add common pipx bin paths for current run
    export PATH="$HOME/.local/bin:$PATH"
  fi

  echo
}

# --------------------------------------------------
# gext (gnome-extensions-cli) install / checks
# --------------------------------------------------
ensure_gext() {
  if command -v gext >/dev/null 2>&1; then
    echo "gext already installed: $(command -v gext)"
    echo
    return 0
  fi

  echo "Installing gnome-extensions-cli (gext) via pipx..."

  if ! command -v pipx >/dev/null 2>&1; then
    echo "ERROR: pipx not available even after deps install."
    exit 1
  fi

  # Omakub uses: pipx install gnome-extensions-cli --system-site-packages
  # Use /dev/tty for any prompts (though pipx is usually non-interactive)
  if [[ "$HAS_TTY" -eq 1 ]]; then
    pipx install gnome-extensions-cli --system-site-packages </dev/tty
  else
    pipx install gnome-extensions-cli --system-site-packages
  fi

  export PATH="$HOME/.local/bin:$PATH"

  if ! command -v gext >/dev/null 2>&1; then
    echo "ERROR: gext still not found after installation."
    echo "PATH: $PATH"
    exit 1
  fi

  echo "gext installed: $(command -v gext)"
  echo
}

# --------------------------------------------------
# Extension state helpers
# --------------------------------------------------
is_installed() {
  gnome-extensions info "$1" >/dev/null 2>&1
}

is_enabled() {
  gnome-extensions info "$1" 2>/dev/null | grep -q "State: ENABLED"
}

is_disabled() {
  gnome-extensions info "$1" 2>/dev/null | grep -q "State: DISABLED"
}

normalize_desired() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | xargs
}

# --------------------------------------------------
# Schema compile (Omakub-like, but safe)
# Copies any *.gschema.xml found under installed extensions into
# /usr/share/glib-2.0/schemas and compiles.
# This is optional but helps gsettings configs work when you add them later.
# --------------------------------------------------
copy_and_compile_schemas() {
  local schema_dir="/usr/share/glib-2.0/schemas"
  local tmp_list
  tmp_list="$(mktemp)"

  # Collect schemas from user-installed extensions we manage
  while IFS='=' read -r UUID DESIRED; do
    [[ -z "$UUID" || "$UUID" =~ ^# ]] && continue
    if [[ -d "$HOME/.local/share/gnome-shell/extensions/$UUID/schemas" ]]; then
      find "$HOME/.local/share/gnome-shell/extensions/$UUID/schemas" \
        -maxdepth 1 -type f -name "*.gschema.xml" -print >> "$tmp_list" || true
    fi
  done < "$CONF_FILE"

  if [[ ! -s "$tmp_list" ]]; then
    rm -f "$tmp_list"
    return 0
  fi

  echo "Detected gsettings schemas in managed extensions."
  echo "Copying schemas to $schema_dir and compiling..."
  sudo mkdir -p "$schema_dir"

  while IFS= read -r schema; do
    # Copy only if the source exists
    [[ -f "$schema" ]] || continue
    sudo cp -f "$schema" "$schema_dir/"
  done < "$tmp_list"

  sudo glib-compile-schemas "$schema_dir"
  rm -f "$tmp_list"

  echo "Schemas compiled."
  echo
}

# --------------------------------------------------
# Main: deps + gext + reconcile
# --------------------------------------------------
ensure_deps
ensure_gext

echo "Processing extensions.conf..."
echo

ERRORS=0

while IFS='=' read -r UUID DESIRED; do
  [[ -z "$UUID" || "$UUID" =~ ^# ]] && continue
  DESIRED="$(normalize_desired "$DESIRED")"

  if [[ "$DESIRED" != "enabled" && "$DESIRED" != "disabled" ]]; then
    echo "→ $UUID"
    echo "  desired: $DESIRED"
    echo "  ERROR  : invalid desired state (must be enabled|disabled)"
    echo
    ERRORS=1
    continue
  fi

  echo "→ $UUID"
  echo "  desired: $DESIRED"

  if ! is_installed "$UUID"; then
    echo "  status : missing"
    echo "  action : installing via gext"

    # gext may prompt for confirmations; force it to use /dev/tty when available
    if [[ "$HAS_TTY" -eq 1 ]]; then
      if ! gext install "$UUID" </dev/tty; then
        echo "  ERROR  : gext install failed"
        echo
        ERRORS=1
        continue
      fi
    else
      # Non-interactive environment: gext may hang or fail due to confirmations.
      echo "  WARN   : no /dev/tty available; gext may require confirmations."
      echo "  WARN   : skipping install to avoid hang in non-interactive mode."
      echo
      ERRORS=1
      continue
    fi

    # Verify install actually landed
    if ! is_installed "$UUID"; then
      echo "  ERROR  : install reported success but extension still missing"
      echo "  state  : not installed"
      echo "  action : cannot reconcile"
      echo
      ERRORS=1
      continue
    fi

    echo "  status : installed (after gext)"
  else
    echo "  status : installed"
  fi

  # Reconcile enabled/disabled
  if [[ "$DESIRED" == "enabled" ]]; then
    if is_enabled "$UUID"; then
      echo "  state  : already enabled"
      echo "  action : none"
    else
      echo "  state  : disabled"
      echo "  action : enabling"
      if ! gnome-extensions enable "$UUID" 2>/dev/null; then
        echo "  WARN   : enable failed (might require logout/login)"
        ERRORS=1
      fi
    fi
  else
    if is_disabled "$UUID"; then
      echo "  state  : already disabled"
      echo "  action : none"
    else
      echo "  state  : enabled"
      echo "  action : disabling"
      if ! gnome-extensions disable "$UUID" 2>/dev/null; then
        echo "  WARN   : disable failed (might require logout/login)"
        ERRORS=1
      fi
    fi
  fi

  echo
done < "$CONF_FILE"

# Optional schema compilation (safe, useful)
copy_and_compile_schemas

if [[ "$ERRORS" -eq 0 ]]; then
  echo "=================================================="
  echo " Extensions install + reconcile COMPLETE (OK)"
  echo "=================================================="
else
  echo "=================================================="
  echo " Extensions install + reconcile COMPLETE (WITH WARNINGS/ERRORS)"
  echo " Check log: $LOG_FILE"
  echo "=================================================="
fi

echo "If extensions misbehave, log out and log back in."
