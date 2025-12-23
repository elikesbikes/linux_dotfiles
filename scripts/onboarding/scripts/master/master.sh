#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------
# Path resolution
# master.sh lives in: scripts/onboarding/scripts/master/
# Categories live in: scripts/onboarding/scripts/{cli,core,desktop,security,extensions}
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
run_script() {
  local script="$1"
  chmod +x "$script"
  "$script"
}

pause_and_clear() {
  echo
  read -rp "Press ENTER to return to menu..."
  clear
}

# --------------------------------------------------
# Ensure gum (Charm repo)
# --------------------------------------------------
ensure_gum() {
  if command -v gum >/dev/null 2>&1; then
    return 0
  fi

  echo "Installing gum..."
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

  for script in "$dir"/install_*.sh; do
    [[ -f "$script" ]] || continue
    echo
    echo "→ Running $(basename "$script")"
    run_script "$script"
  done

  touch "$INSTALLED_DIR/$category"
  pause_and_clear
}

verify_category() {
  local category="$1"
  local dir="$SCRIPTS_DIR/$category"

  [[ -d "$dir" ]] || return

  clear
  gum style --border normal --padding "1 2" "VERIFY: $category"
  echo

  for script in "$dir"/verify_*.sh; do
    [[ -f "$script" ]] || continue
    run_script "$script"
  done

  echo
  gum style --foreground 241 "Verification complete."
  pause_and_clear
}

uninstall_category() {
  local category="$1"
  local dir="$SCRIPTS_DIR/$category"

  [[ -d "$dir" ]] || return

  clear
  gum style --border normal --padding "1 2" "UNINSTALL: $category"

  for script in "$dir"/uninstall_*.sh; do
    [[ -f "$script" ]] || continue
    run_script "$script"
  done

  rm -f "$INSTALLED_DIR/$category"
  pause_and_clear
}

# --------------------------------------------------
# Menus
# --------------------------------------------------
install_menu() {
  local choices
  choices=$(printf "core\ncli\ndesktop\nsecurity\nextensions\nback" \
    | gum choose --no-limit)

  if [[ -z "$choices" ]]; then
    gum style --foreground 196 "No selection made."
    sleep 1
    clear
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
    gum style --foreground 196 "No selection made."
    sleep 1
    clear
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
    gum style --foreground 196 "No selection made."
    sleep 1
    clear
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
      "Exit") exit 0 ;;
    esac
  done
}

# --------------------------------------------------
# Entry
# --------------------------------------------------
ensure_gum
main_menu
