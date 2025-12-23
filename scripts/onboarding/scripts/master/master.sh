#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------
# Path resolution
# master.sh lives in: scripts/onboarding/scripts/master/
# --------------------------------------------------
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="$BASE_DIR"

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
  local script="$1"
  chmod +x "$script"
  "$script"
}

# --------------------------------------------------
# Ensure gum (Charm repo, Omakub-style)
# --------------------------------------------------
ensure_gum() {
  if command -v gum >/dev/null 2>&1; then
    return 0
  fi

  clear
  echo "Installing gum (required for menu)..."
  echo

  sudo apt-get update
  sudo apt-get install -y curl ca-certificates gnupg

  sudo install -d -m 0755 /etc/apt/keyrings

  if [[ ! -f /etc/apt/keyrings/charm.gpg ]]; then
    curl -fsSL https://repo.charm.sh/apt/gpg.key \
      | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
  fi

  if [[ ! -f /etc/apt/sources.list.d/charm.list ]]; then
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
      | sudo tee /etc/apt/sources.list.d/charm.list > /dev/null
  fi

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
  local dir="$SCRIPTS_DIR/$category"

  clear
  gum style --border normal --padding "1 2" "VERIFY: $category"
  echo

  for script in "$dir"/verify_*.sh; do
    [[ -f "$script" ]] || continue
    run_script "$script"
    echo
  done

  pause
}

uninstall_category() {
  local category="$1"
  local dir="$SCRIPTS_DIR/$category"

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
  local choices
  choices=$(printf "core\ncli\ndesktop\nsecurity\nextensions\nback" \
    | gum choose --no-limit)

  if [[ -z "$choices" ]]; then
    clear
    echo "⚠️  No selection made."
    pause
    return
  fi

  for choice in $choices; do
    [[ "$choice" == "back" ]] && return
    run_category "$choice"
  done
}

verify_menu() {
  local choices
  choices=$(printf "core\ncli\ndesktop\nsecurity\nextensions\nback" \
    | gum choose --no-limit)

  if [[ -z "$choices" ]]; then
    clear
    echo "⚠️  No selection made."
    pause
    return
  fi

  for choice in $choices; do
    [[ "$choice" == "back" ]] && return
    verify_category "$choice"
  done
}

uninstall_menu() {
  local choices
  choices=$(printf "core\ncli\ndesktop\nsecurity\nextensions\nback" \
    | gum choose --no-limit)

  if [[ -z "$choices" ]]; then
    clear
    echo "⚠️  No selection made."
    pause
    return
  fi

  for choice in $choices; do
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

    choice=$(printf "Install components\nVerify system\nUninstall components\nExit\n" \
      | gum choose)

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
