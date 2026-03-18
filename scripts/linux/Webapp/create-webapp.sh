#!/bin/bash

APPS_DIR="$HOME/.local/share/applications"
ICONS_DIR="$HOME/.local/share/icons"

echo "=== Web App Installer ==="
echo ""

# App name
read -rp "App name (e.g. Notion, Gmail): " APP_NAME
if [[ -z "$APP_NAME" ]]; then
  echo "Error: App name cannot be empty." >&2
  exit 1
fi

# URL
read -rp "URL (e.g. https://notion.so): " APP_URL
if [[ -z "$APP_URL" ]]; then
  echo "Error: URL cannot be empty." >&2
  exit 1
fi

# Derive safe filename slug
SLUG=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')
DESKTOP_FILE="$APPS_DIR/${SLUG}-webapp.desktop"
ICON_FILE="$ICONS_DIR/${SLUG}.png"

# Icon — try to fetch favicon from the domain
DOMAIN=$(echo "$APP_URL" | sed -E 's|https?://([^/]+).*|\1|')
FAVICON_URL="https://www.google.com/s2/favicons?domain=${DOMAIN}&sz=256"

echo ""
echo "Fetching icon for ${DOMAIN}..."
if curl -sL "$FAVICON_URL" -o "$ICON_FILE" && file "$ICON_FILE" | grep -q "image"; then
  # Convert to proper 256x256 PNG if ImageMagick is available
  convert "$ICON_FILE" -resize 256x256 "$ICON_FILE" 2>/dev/null || true
  echo "Icon saved to $ICON_FILE"
else
  echo "Warning: Could not fetch icon. You can replace $ICON_FILE manually."
  # Create a placeholder so the .desktop file still works
  cp /usr/share/icons/hicolor/256x256/apps/brave-browser.png "$ICON_FILE" 2>/dev/null || true
fi

# Write .desktop file
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Name=${APP_NAME}
Comment=${APP_NAME} Web App
Exec=brave-browser --app=${APP_URL} --name=${APP_NAME}
Icon=${ICON_FILE}
Terminal=false
Type=Application
Categories=Network;WebApp;
StartupWMClass=${DOMAIN}
StartupNotify=true
EOF

echo "Desktop entry created: $DESKTOP_FILE"

# Refresh desktop database
update-desktop-database "$APPS_DIR"

# Pin to GNOME dock
read -rp "Pin to GNOME dock? [Y/n]: " PIN
if [[ "${PIN,,}" != "n" ]]; then
  ENTRY="${SLUG}-webapp.desktop"
  CURRENT=$(gsettings get org.gnome.shell favorite-apps)
  # Check if already pinned
  if echo "$CURRENT" | grep -q "$ENTRY"; then
    echo "Already pinned to dock."
  else
    NEW=$(echo "$CURRENT" | sed "s/]$/, '${ENTRY}'/")
    gsettings set org.gnome.shell favorite-apps "$NEW"
    echo "Pinned to dock."
  fi
fi

echo ""
echo "Done! You may need to run 'Alt+F2 → r' to restart GNOME Shell for the icon to appear."
