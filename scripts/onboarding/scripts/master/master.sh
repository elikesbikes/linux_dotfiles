#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------
# Paths
# --------------------------------------------------
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="$BASE_DIR"

# --------------------------------------------------
# Utilities
# --------------------------------------------------
clear_screen() {
  clear
}

run_script() {
  local script="$1"
  [[ -f "$script" ]] || return 0
  chmod +x "$script"
  "$script"
}

warn_no_selection() {
  clear_screen

  gum style \
    --border normal \
    --padding "1 2" \
    --foreground 196 \
    "No selection made.\n\nUse SPACE to select items.\nPress ENTER to confirm."

  gum confirm "Press Enter to continue" --affirmative "OK" >/dev/null

  clear_screen
}

# --------------------------------------------------
# Ensure gum (Ubuntu/Debian)
# --------------------------------------------------
ensure_gum() {
  command -v gum >/dev/null 2>&1 && return

  clear_screen
  echo "Installing gum (Charm repo)..."

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

  [[ -d "$dir" ]] || return 0

  clear_screen
  gum style --border normal --padding "1 2" "Installing: $category"

  for script in "$dir"/install_*.sh; do
    [[ -f "$script" ]] || continue
    echo "→ Running $(basename "$script")"
    run_script "$script"
  done
}

verify_category() {
  local category="$1"
  local verify_script="$SCRIPTS_DIR/verify/verify_${category}.sh"
  local fallback_dir="$SCRIPTS_DIR/$category"

  clear_screen
  set +e
  set +o pipefail

  local output
  output=$(
    {
      echo "======================================"
      echo " VERIFY: $category"
      echo "======================================"
      echo

      if [[ -f "$verify_script" ]]; then
        "$verify_script"
      else
        for script in "$fallback_dir"/verify_*.sh; do
          [[ -f "$script" ]] || continue
          "$script"
        done
      fi
    } 2>&1
  )

  local status=$?

  set -euo pipefail

  printf "%s\n\nExit code: %s\n" "$output" "$status" | gum pager

  clear_screen
}

uninstall_category() {
  local category="$1"
  local cleanup="$SCRIPTS_DIR/cleanup/cleanup_${category}.sh"

  clear_screen
  gum style --border normal --padding "1 2" "UNINSTALL: $category"

  if [[ -f "$cleanup" ]]; then
    run_script "$cleanup"
  else
    echo "No uninstall script for $category"
    gum confirm "Press Enter to continue" --affirmative "OK" >/dev/null
  fi
}

# --------------------------------------------------
# Menus
# --------------------------------------------------
install_menu() {
  while true; do
    clear_screen
    local choices
    choices=$(printf "dotfiles\ncore\ncli\ndesktop\nextensions\nsecurity\nback" \
      | gum choose --no-limit)

    [[ "$choices" == *"back"* ]] && { clear_screen; return; }
    [[ -z "$choices" ]] && { warn_no_selection; continue; }

    for choice in $choices; do
      run_category "$choice"
    done

    clear_screen
    return
  done
}

verify_menu() {
  while true; do
    clear_screen
    local choices
    choices=$(printf "core\ncli\ndesktop\nextensions\nsecurity\nback" \
      | gum choose --no-limit)

    [[ "$choices" == *"back"* ]] && { clear_screen; return; }
    [[ -z "$choices" ]] && { warn_no_selection; continue; }

    for choice in $choices; do
      verify_category "$choice"
    done

    return
  done
}

uninstall_menu() {
  while true; do
    clear_screen
    local choices
    choices=$(printf "cli\ndesktop\nsecurity\nextensions\nback" \
      | gum choose --no-limit)

    [[ "$choices" == *"back"* ]] && { clear_screen; return; }
    [[ -z "$choices" ]] && { warn_no_selection; continue; }

    for choice in $choices; do
      uninstall_category "$choice"
    done

    clear_screen
    return
  done
}

# --------------------------------------------------
# Main menu
# --------------------------------------------------
main_menu() {
  while true; do
    clear_screen
    gum style --border double --padding "1 4" "Linux Dotfiles Onboarding"

    choice=$(printf "Install components\nVerify system\nUninstall components\nExit\n" \
      | gum choose)

    case "$choice" in
      "Install components") install_menu ;;
      "Verify system") verify_menu ;;
      "Uninstall components") uninstall_menu ;;
      "Exit") clear_screen; exit 0 ;;
    esac
  done
}

# --------------------------------------------------
# Entry
# --------------------------------------------------
ensure_gum
main_menu
