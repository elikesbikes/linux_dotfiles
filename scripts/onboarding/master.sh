#!/bin/bash
set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"

mkdir -p "$STATE_DIR"

# ------------------------------------------------------------
# Dry-run support
# ------------------------------------------------------------
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
  echo "[DRY-RUN MODE ENABLED]"
fi

# ------------------------------------------------------------
# Ensure fzf is installed
# ------------------------------------------------------------
if ! command -v fzf >/dev/null 2>&1; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY-RUN] Would install fzf via apt"
  else
    echo "fzf not found. Installing..."
    sudo apt update
    sudo apt install -y fzf
  fi
fi

# ------------------------------------------------------------
# Menu definitions
# ------------------------------------------------------------
declare -A DESCRIPTIONS=(
  [core]="Install system foundations (Flatpak, SSH)"
  [cli]="Install CLI & developer tools"
  [desktop]="Install desktop GUI applications"
  [security]="Install security & privacy tools (Proton, YubiKey)"
  [verify]="Verify installed components (installed categories only)"
  [uninstall]="Uninstall onboarding-installed components (selective)"
  [exit]="Exit installer without making changes"
)

MAIN_CATEGORIES=(core cli desktop security verify uninstall exit)
UNINSTALL_CATEGORIES=(cli desktop security)

# ------------------------------------------------------------
# Install category
# ------------------------------------------------------------
run_install_category() {
  local category="$1"
  local dir="$SCRIPTS_DIR/$category"

  echo ""
  echo "======================================"
  echo " INSTALL: $category"
  echo " ${DESCRIPTIONS[$category]}"
  echo "======================================"

  [[ ! -d "$dir" ]] && echo "Missing directory: $dir" && return

  for script in "$dir"/install_*.sh; do
    [[ -e "$script" ]] || continue
    chmod +x "$script"

    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[DRY-RUN] Would run: $script"
    else
      "$script"
    fi
  done

  # Mark category as installed (state)
  if [[ "$DRY_RUN" -eq 0 ]]; then
    touch "$STATE_DIR/$category"
  else
    echo "[DRY-RUN] Would mark category '$category' as installed"
  fi
}

# ------------------------------------------------------------
# Verification (STATE-AWARE)
# ------------------------------------------------------------
run_verify() {
  local verify_dir="$SCRIPTS_DIR/verify"

  echo ""
  echo "======================================"
  echo " VERIFY (installed categories only)"
  echo "======================================"

  [[ ! -d "$verify_dir" ]] && echo "Missing verify directory: $verify_dir" && exit 1

  for script in "$verify_dir"/verify_*.sh; do
    [[ -e "$script" ]] || continue

    category="$(basename "$script" | sed 's/^verify_//; s/\.sh$//')"
    marker="$STATE_DIR/$category"

    if [[ ! -f "$marker" ]]; then
      echo "SKIP: $category (not installed via onboarding)"
      continue
    fi

    chmod +x "$script"

    echo ""
    echo "--------------------------------------"
    echo " VERIFY: $category"
    echo "--------------------------------------"

    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[DRY-RUN] Would run: $script"
    else
      "$script"
    fi
  done
}

# ------------------------------------------------------------
# Selective Uninstall (with Back option)
# ------------------------------------------------------------
run_uninstall() {
  local dir="$SCRIPTS_DIR/cleanup"

  [[ ! -d "$dir" ]] && echo "Missing directory: $dir" && exit 1

  while true; do
    MENU_INPUT=""
    for cat in "${UNINSTALL_CATEGORIES[@]}"; do
      MENU_INPUT+="$cat | Uninstall $cat-installed components"$'\n'
    done
    MENU_INPUT+="back | Return to main menu"$'\n'

    SELECTED=$(echo "$MENU_INPUT" | fzf \
      --multi \
      --bind="space:toggle,q:abort" \
      --prompt="Select uninstall categories > " \
      --header="SPACE select | ENTER confirm | q / ESC back" \
      --height=40% \
      --border \
      --layout=reverse
    )

    [[ -z "$SELECTED" ]] && return

    while IFS= read -r line; do
      choice="$(echo "$line" | cut -d'|' -f1 | xargs)"

      if [[ "$choice" == "back" ]]; then
        return
      fi

      script="$dir/cleanup_${choice}.sh"

      if [[ ! -f "$script" ]]; then
        echo "Uninstall script not found: $script"
        continue
      fi

      chmod +x "$script"

      echo ""
      echo "--------------------------------------"
      echo " UNINSTALL: $choice"
      echo "--------------------------------------"

      if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[DRY-RUN] Would run: $script"
        echo "[DRY-RUN] Would remove state marker: $STATE_DIR/$choice"
      else
        "$script"
        rm -f "$STATE_DIR/$choice"
      fi
    done <<< "$SELECTED"
  done
}

# ------------------------------------------------------------
# Main menu loop
# ------------------------------------------------------------
while true; do
  MENU_INPUT=""
  for cat in "${MAIN_CATEGORIES[@]}"; do
    MENU_INPUT+="$cat | ${DESCRIPTIONS[$cat]}"$'\n'
  done

  SELECTED=$(echo "$MENU_INPUT" | fzf \
    --bind="q:abort" \
    --prompt="Select action > " \
    --header="ENTER select | / search | q / ESC exit" \
    --height=40% \
    --border \
    --layout=reverse
  )

  [[ -z "$SELECTED" ]] && echo "Exiting installer." && exit 0

  choice="$(echo "$SELECTED" | cut -d'|' -f1 | xargs)"

  case "$choice" in
    core|cli|desktop|security)
      run_install_category "$choice"
      ;;
    verify)
      run_verify
      ;;
    uninstall)
      run_uninstall
      ;;
    exit)
      echo "Exiting installer."
      exit 0
      ;;
    *)
      echo "Unknown selection: $choice"
      ;;
  esac
done
