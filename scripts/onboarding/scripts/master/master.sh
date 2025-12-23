#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------
# master.sh lives in: scripts/onboarding/scripts/master/
# Categories live in: scripts/onboarding/scripts/{cli,core,desktop,security,extensions}
# --------------------------------------------------
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="$BASE_DIR"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding"
LOG_DIR="$STATE_DIR/logs"
INSTALLED_DIR="$STATE_DIR/installed"

mkdir -p "$LOG_DIR" "$INSTALLED_DIR"

clear_screen() {
  command -v clear >/dev/null 2>&1 && clear || true
}

# --------------------------------------------------
# Ensure gum (Charm repo)
# --------------------------------------------------
ensure_gum() {
  if command -v gum >/dev/null 2>&1; then
    return 0
  fi

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

run_script() {
  local script="$1"
  chmod +x "$script"
  "$script"
}

run_category() {
  local category="$1"
  local dir="$SCRIPTS_DIR/$category"

  [[ -d "$dir" ]] || return 0

  clear_screen
  gum style --border normal --padding "1 2" "Installing: $category"

  # Special UX: extensions install should always be visible in pager
  if [[ "$category" == "extensions" ]]; then
    local tmp
    tmp="$(mktemp)"
    {
      echo "=== CATEGORY: $category ==="
      echo "Started: $(date)"
      echo "Dir: $dir"
      echo
      for script in "$dir"/install_*.sh; do
        [[ -f "$script" ]] || continue
        echo "→ Running $(basename "$script")"
        echo
        run_script "$script"
        echo
      done
      echo "Completed: $(date)"
    } &> "$tmp"

    gum pager < "$tmp"
    rm -f "$tmp"
  else
    for script in "$dir"/install_*.sh; do
      [[ -f "$script" ]] || continue
      echo "→ Running $(basename "$script")"
      run_script "$script"
    done
  fi

  touch "$INSTALLED_DIR/$category"
}

verify_category() {
  local category="$1"
  local dir="$SCRIPTS_DIR/$category"

  [[ -d "$dir" ]] || return 0

  clear_screen
  gum style --border normal --padding "1 2" "VERIFY: $category"

  local tmp
  tmp="$(mktemp)"
  {
    echo "=== VERIFY CATEGORY: $category ==="
    echo "Started: $(date)"
    echo "Dir: $dir"
    echo
    for script in "$dir"/verify_*.sh; do
      [[ -f "$script" ]] || continue
      echo "→ Running $(basename "$script")"
      echo
      run_script "$script"
      echo
    done
    echo "Completed: $(date)"
  } &> "$tmp"

  gum pager < "$tmp"
  rm -f "$tmp"
}

uninstall_category() {
  local category="$1"
  local dir="$SCRIPTS_DIR/$category"

  [[ -d "$dir" ]] || return 0

  clear_screen
  gum style --border normal --padding "1 2" "UNINSTALL: $category"

  local tmp
  tmp="$(mktemp)"
  {
    echo "=== UNINSTALL CATEGORY: $category ==="
    echo "Started: $(date)"
    echo "Dir: $dir"
    echo
    for script in "$dir"/uninstall_*.sh; do
      [[ -f "$script" ]] || continue
      echo "→ Running $(basename "$script")"
      echo
      run_script "$script"
      echo
    done
    echo "Completed: $(date)"
  } &> "$tmp"

  gum pager < "$tmp"
  rm -f "$tmp"

  rm -f "$INSTALLED_DIR/$category"
}

warn_no_selection() {
  clear_screen
  gum style --border normal --padding "1 2" "No selection made" \
    "Use SPACE to select, then ENTER to confirm." \
    "" \
    "Press ENTER to return..."
  read -r
}

install_menu() {
  local choices
  choices="$(printf "core\ncli\ndesktop\nsecurity\nextensions\nback" | gum choose --no-limit || true)"

  if [[ -z "${choices:-}" ]]; then
    warn_no_selection
    return
  fi

  for choice in $choices; do
    [[ "$choice" == "back" ]] && return
    run_category "$choice"
  done
}

verify_menu() {
  local choices
  choices="$(printf "core\ncli\ndesktop\nsecurity\nextensions\nback" | gum choose --no-limit || true)"

  if [[ -z "${choices:-}" ]]; then
    warn_no_selection
    return
  fi

  for choice in $choices; do
    [[ "$choice" == "back" ]] && return
    verify_category "$choice"
  done
}

uninstall_menu() {
  local choices
  choices="$(printf "core\ncli\ndesktop\nsecurity\nextensions\nback" | gum choose --no-limit || true)"

  if [[ -z "${choices:-}" ]]; then
    warn_no_selection
    return
  fi

  for choice in $choices; do
    [[ "$choice" == "back" ]] && return
    uninstall_category "$choice"
  done
}

main_menu() {
  while true; do
    clear_screen
    gum style --border double --padding "1 4" "Linux Dotfiles Onboarding"

    local choice
    choice="$(printf "Install components\nVerify system\nUninstall components\nExit\n" | gum choose)"

    case "$choice" in
      "Install components") install_menu ;;
      "Verify system") verify_menu ;;
      "Uninstall components") uninstall_menu ;;
      "Exit") exit 0 ;;
    esac
  done
}

ensure_gum
main_menu
