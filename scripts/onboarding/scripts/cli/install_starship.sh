#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install_starship.log"

echo "==================================================" | tee -a "$LOG_FILE"
echo "[install_starship.sh] Starting at: $(date)" | tee -a "$LOG_FILE"
echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"

if command -v starship >/dev/null 2>&1; then
  echo "Starship already installed: $(command -v starship)" | tee -a "$LOG_FILE"
  starship --version | tee -a "$LOG_FILE"
  echo "Skipping install." | tee -a "$LOG_FILE"
else
  echo "Installing Starship via official installer..." | tee -a "$LOG_FILE"
  curl -fsSL https://starship.rs/install.sh | sh -s -- -y | tee -a "$LOG_FILE"
fi

echo "==================================================" | tee -a "$LOG_FILE"
echo "[install_starship.sh] Completed at: $(date)" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"
