#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install_starship.log"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
STATE_FILE="$STATE_DIR/starship"
mkdir -p "$STATE_DIR"

echo "==================================================" | tee -a "$LOG_FILE"
echo "[install_starship.sh] Starting at: $(date)" | tee -a "$LOG_FILE"
echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"

if [[ -f "$STATE_FILE" ]]; then
  echo "STATE: starship already marked as installed ($STATE_FILE)" | tee -a "$LOG_FILE"
  echo "Nothing to do. Exiting." | tee -a "$LOG_FILE"
  exit 0
fi

if command -v starship >/dev/null 2>&1; then
  echo "Starship already installed: $(command -v starship)" | tee -a "$LOG_FILE"
  starship --version | tee -a "$LOG_FILE"
  echo "Skipping install." | tee -a "$LOG_FILE"
else
  echo "Installing Starship via official installer..." | tee -a "$LOG_FILE"
  curl -fsSL https://starship.rs/install.sh | sh -s -- -y | tee -a "$LOG_FILE"
fi

if command -v starship >/dev/null 2>&1; then
  touch "$STATE_FILE"
else
  echo "FAIL: starship not found after install" | tee -a "$LOG_FILE"
  exit 1
fi

echo "==================================================" | tee -a "$LOG_FILE"
echo "[install_starship.sh] Completed at: $(date)" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"
