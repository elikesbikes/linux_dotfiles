#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: master.sh
# Version: 1.0.5
# Date: 2025-12-23
# Author: Tars (ELIKESBIKES)
#
# Changelog:
#   1.0.5 - FIX: Hybrid verification routing.
#           - cli/core/desktop/security verified via
#             scripts/verify/verify_<category>.sh
#           - extensions verified via
#             scripts/extensions/verify_extensions.sh
#           No file moves. No UX changes.
#   1.0.3 - Attach verify scripts to /dev/tty.
#   1.0.2 - UX baseline.
# ==================================================

# --------------------------------------------------
# Path resolution
# --------------------------------------------------
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="$BASE_DIR"
VERIFY_DIR="$BASE_DIR/verify"
EXTENSIONS_DIR="$BASE_DIR/extensions"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding"
LOG_DIR="$STATE_DIR/logs"
INSTALLED_DIR="$STATE_DIR/installed"

mkdir -p "$LOG_DIR" "$INSTALLED_DIR"

# --------------------------------------------------
# Utilities
# --------------------------------------------------
pause() {
  echo
  read -r -p "Press Enter to return to menu..." </dev/tty
}

run_script() {
  chmod +x "$1"
  "$1"
}

# Run script attached to real terminal (CTT-style)
run_script_tty() {
  local script="$1"
  chmod +x "$script"
  bash "$script" </dev/tty >/dev/tty 2>/dev/tty
  return $?
}

# --------------------------------------------------
# Ensure gum (menus only)
# --------------------------------------------------
ensure_gum() {
  command -v gum >/dev/null 2>&1 && return

  clear
  echo "Installing gum (required for menu)..."
  echo

  sudo apt-get update
  sudo apt-get install -y gum
}

# --------------------------------------------------
# Category execution
# --------------------------------------------------
run_category() {
  local category="$1"
  local dir="$SCRIPTS_DIR/$category"

  [[ -d "$dir" ]] || return

  clear
  gum style --border normal --padding "1 2" "Installing: $category"
  echo

  for script in "$dir"/install_*.sh; do
    [[ -f "$script" ]] || continue
    echo "→ Running $(basename "$script")"
    echo
    run_script "$script"
    echo
  done

  touch "$INSTALLED_DIR/$category"
  pause
}

verify_category() {
  local category="$1"
  local script=""

  clear
  echo "======================================"
  echo " VERIFY: $category"
  echo "======================================"
  echo

  if [[ "$category" == "extensions" ]]; then
    script="$EXTENSIONS_DIR/verify_extensions.sh"
  else
    script="$VERIFY_DIR/verify_${category}.sh"
  fi

  if [[ ! -f "$script" ]]; then
    echo "⚠ No verify script found for category '$category'"
    pause
    return
  fi

  set +e
  run_script_tty "$script"
  rc=$?
  set -e

  echo
  if [[ "$rc" -eq 0 ]]; then
    echo "✓ Verification category '$category' PASSED"
  else
    echo "⚠ Verification category '$category' FAILED"
  fi

  pause
}

uninstall_category() {
  local category="$1"
  local dir="$SCRIPTS_DIR/$category"

  [[ -d "$dir" ]] || return

  clear
  gum style --border normal --padding "1 2" "UNINSTALL: $category"
  echo

  for script in "$dir"/uninstall_*.sh; do
    [[ -f "$script" ]] || continue
    run_script "$script"
    echo
  done

  rm -f "$INSTALLED_DIR/$category"
  pause
}

# --------------------------------------------------
# Menus
# --------------------------------------------------
install_menu() {
  local selections
  selections="$(printf "core\ncli\ndesktop\nsecurity\nextensions\nback" \
    | gum choose --no-limit)"

  [[ -z "$selections" ]] && return

  for choice in $selections; do
    [[ "$choice" == "back" ]] && return
    run_category "$choice"
  done
}

verify_menu() {
  local selections
  selections="$(printf "core\ncli\ndesktop\nsecurity\nextensions\nback" \
    | gum choose --no-limit)"

  [[ -z "$selections" ]] && return

  for choice in $selections; do
    [[ "$choice" == "back" ]] && return
    verify_category "$choice"
  done
}

uninstall_menu() {
  local selections
  selections="$(printf "core\ncli\ndesktop\nsecurity\nextensions\nback" \
    | gum choose --no-limit)"

  [[ -z "$selections" ]] && return

  for choice in $selections; do
    [[ "$choice" == "back" ]] && return
    uninstall_category "$choice"
  done
}

# --------------------------------------------------
# Main menu
# --------------------------------------------------
main_menu() {
  while true; do
    clear
    gum style --border double --padding "1 4" "Linux Dotfiles Onboarding"

    choice="$(printf "Install components\nVerify system\nUninstall components\nExit\n" \
      | gum choose)"

    case "$choice" in
      "Install components") install_menu ;;
      "Verify system") verify_menu ;;
      "Uninstall components") uninstall_menu ;;
      "Exit") clear; exit 0 ;;
    esac
  done
}

# --------------------------------------------------
# Entry
# --------------------------------------------------
ensure_gum
main_menu
