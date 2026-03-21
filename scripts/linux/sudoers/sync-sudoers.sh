#!/bin/bash
set -e

REPO_DIR="/home/ecloaiza/devops/github/homelab"
SUDOERS_SOURCE="${REPO_DIR}/sudoers.d"
SUDOERS_DEST="/etc/sudoers.d"

echo "🔄 Syncing sudoers..."
echo ""

# Detect sudo implementation
SUDO_VERSION=$(sudo --version 2>&1 | head -n1)
if [[ "$SUDO_VERSION" == *"sudo-rs"* ]]; then
  SUDO_TYPE="sudo-rs"
  echo "📍 Detected: sudo-rs (limited feature set)"
  EXCLUDE_FILES="00-defaults-logging"
else
  SUDO_TYPE="sudo"
  echo "📍 Detected: Traditional sudo (full features)"
  EXCLUDE_FILES=""
fi

# Pull latest from Git
cd "$REPO_DIR"
echo ""
echo "📥 Pulling from Git..."
git pull

# Validate all files
echo ""
echo "🔍 Validating files..."
for file in "${SUDOERS_SOURCE}"/*; do
  filename=$(basename "$file")
  [[ "$filename" == "README" ]] && continue

  # Skip excluded files for sudo-rs
  if [[ -n "$EXCLUDE_FILES" ]] && [[ "$EXCLUDE_FILES" == *"$filename"* ]]; then
    echo "  ⊘ Skipping $filename (${SUDO_TYPE} incompatible)"
    continue
  fi

  if ! sudo visudo -cf "$file"; then
    echo "❌ Syntax error in $filename - ABORTING"
    exit 1
  fi
  echo "  ✓ $filename"
done

# Ensure root has the unison profile
echo ""
echo "📋 Setting up Unison profile for root..."
sudo mkdir -p /root/.unison
sudo cp ~/.unison/sudoers.prf /root/.unison/

# Update Unison profile to exclude incompatible files
if [[ -n "$EXCLUDE_FILES" ]]; then
  echo ""
  echo "⚙️  Updating Unison profile to exclude: $EXCLUDE_FILES"

  # Add ignore pattern to root's profile if not already there
  if ! sudo grep -q "ignore = Name ${EXCLUDE_FILES}" /root/.unison/sudoers.prf; then
    echo "ignore = Name ${EXCLUDE_FILES}" | sudo tee -a /root/.unison/sudoers.prf >/dev/null
  fi
fi

# Run unison as root
echo ""
echo "🔄 Running Unison sync..."
sudo unison sudoers -batch

# Clean up temporary ignore patterns
if [[ -n "$EXCLUDE_FILES" ]]; then
  sudo sed -i "/ignore = Name ${EXCLUDE_FILES}/d" /root/.unison/sudoers.prf
fi

# Fix permissions (Unison might not preserve them correctly)
echo ""
echo "🔧 Fixing permissions..."
for file in "${SUDOERS_DEST}"/*; do
  filename=$(basename "$file")
  [[ "$filename" == "README" ]] && continue

  sudo chmod 0440 "$file"
  sudo chown root:root "$file"
  echo "  ✓ $filename"
done

echo ""
echo "✅ Sudoers sync complete on ${SUDO_TYPE}!"
