#!/bin/bash
set -e

#REPO_DIR="/home/ecloaiza/devops/github/homelab"
REPO_DIR="/home/ecloaiza/devops/github/linux_dotfiles"
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

# Navigate to repo
cd "$REPO_DIR"

# Check for uncommitted changes
echo ""
echo "🔍 Checking Git status..."
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
  echo "⚠️  You have uncommitted changes in the Git repo"
  echo ""
  git status --short
  echo ""
  echo "What do you want to do?"
  echo "  1) Commit and push changes now"
  echo "  2) Stash changes and pull (you can unstash later)"
  echo "  3) Sync locally only (skip git pull/push)"
  echo "  4) Abort"
  read -p "Choice [1/2/3/4]: " choice

  case $choice in
  1)
    echo ""
    read -p "Commit message: " commit_msg
    git add sudoers.d/
    git commit -m "$commit_msg"
    git push
    echo "✅ Changes committed and pushed"
    ;;
  2)
    git stash
    echo "✅ Changes stashed"
    ;;
  3)
    echo "⚠️  Skipping git pull/push (local sync only)"
    SKIP_GIT=true
    ;;
  4)
    echo "Aborting."
    exit 0
    ;;
  *)
    echo "Invalid choice. Aborting."
    exit 1
    ;;
  esac
fi

# Pull latest from Git (unless skipped)
if [[ "$SKIP_GIT" != "true" ]]; then
  echo ""
  echo "📥 Pulling from Git..."
  git pull
fi

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
  if ! sudo grep -q "ignore = Name ${EXCLUDE_FILES}" /root/.unison/sudoers.prf 2>/dev/null; then
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

# Remind about stashed changes
if [[ "$choice" == "2" ]]; then
  echo ""
  echo "⚠️  Don't forget: You have stashed changes"
  echo "Run 'git stash pop' in $REPO_DIR to restore them"
fi
