#!/bin/bash
set -e

# This script must run as root (invoked via `sudo` from CI). It is whitelisted
# NOPASSWD in sudoers/sudoers.d/40-scripts so it works over non-interactive SSH.
if [[ "$EUID" -ne 0 ]]; then
    echo "❌ This script must be run as root (use: sudo $0)"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUDOERS_SOURCE="${REPO_DIR}/sudoers/sudoers.d"
SUDOERS_DEST="/etc/sudoers.d"

# Locate the invoking user's home (we run as root but need their unison profile)
INVOKING_USER="${SUDO_USER:-$USER}"
USER_HOME="$(getent passwd "$INVOKING_USER" | cut -d: -f6)"

echo "🔄 [CI] Syncing sudoers from ${SUDOERS_SOURCE}..."
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

# Validate all files (visudo -cf does not require root)
echo ""
echo "🔍 Validating sudoers files..."
for file in "${SUDOERS_SOURCE}"/*; do
    [[ -f "$file" ]] || continue
    filename=$(basename "$file")
    [[ "$filename" == "README" || "$filename" == "README.md" ]] && continue

    # Skip excluded files for sudo-rs
    if [[ -n "$EXCLUDE_FILES" ]] && [[ "$EXCLUDE_FILES" == *"$filename"* ]]; then
        echo "  ⊘ Skipping $filename (${SUDO_TYPE} incompatible)"
        continue
    fi

    if ! visudo -cf "$file"; then
        echo "❌ Syntax error in $filename - ABORTING"
        exit 1
    fi
    echo "  ✓ $filename"
done

# Ensure root has the unison profile
echo ""
echo "📋 Setting up Unison profile for root..."
if [ -f "${USER_HOME}/.unison/sudoers.prf" ]; then
    mkdir -p /root/.unison
    cp "${USER_HOME}/.unison/sudoers.prf" /root/.unison/
else
    echo "⚠️  Warning: ${USER_HOME}/.unison/sudoers.prf not found, skipping root profile setup"
fi

# Update Unison profile to exclude incompatible files
if [[ -n "$EXCLUDE_FILES" ]]; then
    echo ""
    echo "⚙️  Updating Unison profile to exclude: $EXCLUDE_FILES"

    if [ -f /root/.unison/sudoers.prf ]; then
        if ! grep -q "ignore = Name ${EXCLUDE_FILES}" /root/.unison/sudoers.prf 2>/dev/null; then
            echo "ignore = Name ${EXCLUDE_FILES}" >> /root/.unison/sudoers.prf
        fi
    fi
fi

# Run unison as root
echo ""
echo "🔄 Running Unison sync..."
unison sudoers -batch

# Clean up temporary ignore patterns
if [[ -n "$EXCLUDE_FILES" ]]; then
    if [ -f /root/.unison/sudoers.prf ]; then
        sed -i "/ignore = Name ${EXCLUDE_FILES}/d" /root/.unison/sudoers.prf
    fi
fi

# Fix permissions (Unison might not preserve them correctly)
echo ""
echo "🔧 Fixing permissions..."
for file in "${SUDOERS_DEST}"/*; do
    [[ -f "$file" ]] || continue
    filename=$(basename "$file")
    [[ "$filename" == "README" ]] && continue

    chmod 0440 "$file"
    chown root:root "$file"
    echo "  ✓ $filename"
done

echo ""
echo "✅ Sudoers sync complete on ${SUDO_TYPE}!"
