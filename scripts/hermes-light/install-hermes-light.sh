#!/usr/bin/env bash
# install-hermes-light.sh — Hermes Light (remote-only Hermes Desktop) on a Linux desktop.
#
# Hermes Light is the Hermes Desktop app with NO local agent and NO Python: it only
# connects to an existing Hermes gateway (ours: endurance, https://hermes.home.elikesbikes.com)
# and signs in through it (Authelia). Nous does not publish a Linux build, so this script
# builds it from source inside a throwaway container (nothing is installed on the host
# besides the app folder), at the commit endurance runs.
#
# What it writes (all under $HOME, no sudo):
#   ~/.local/share/hermes-light/app/            the unpacked Electron app
#   ~/.local/bin/hermes-light                   launcher (fixes the settings folder)
#   ~/.local/share/applications/hermes-light.desktop
#   ~/.config/hermes-light/secure-token-storage.json   {"on":true}: the sign-in token is
#       encrypted with the OS keyring (gnome-keyring) from the first save, never a plain file.
#
# Usage:
#   install-hermes-light.sh [--commit SHA] [--from DIR]
#     --commit SHA  hermes-agent commit to build (default: the one endurance runs, read via ssh)
#     --from DIR    skip the build and install an already built linux-unpacked folder
# Remove: rm -rf ~/.local/share/hermes-light ~/.config/hermes-light ~/.local/bin/hermes-light \
#             ~/.local/share/applications/hermes-light.desktop
#         (also delete the "Hermes" entry in the keyring if you want the token gone)
set -euo pipefail

COMMIT=""
FROM=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit) COMMIT="$2"; shift 2 ;;
    --from) FROM="$2"; shift 2 ;;
    -h|--help) sed -n 2,25p "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

APP_DIR="$HOME/.local/share/hermes-light/app"
DATA_DIR="$HOME/.config/hermes-light"
BIN="$HOME/.local/bin/hermes-light"
DESKTOP="$HOME/.local/share/applications/hermes-light.desktop"

if ! busctl --user list 2>/dev/null | grep -q org.freedesktop.secrets; then
  echo "No Secret Service (gnome-keyring) on this desktop: the token would be stored as a plain file. Stopping." >&2
  exit 1
fi

if [[ -z "$FROM" ]]; then
  if [[ -z "$COMMIT" ]]; then
    COMMIT=$(ssh endurance 'docker exec hermes cat /opt/hermes/install-stamp.json' | python3 -c 'import json,sys;print(json.load(sys.stdin)["commit"])')
  fi
  [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "bad commit: $COMMIT" >&2; exit 1; }
  WORK=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/hermes-light-build.XXXXXX")
  trap 'rm -rf "$WORK"' EXIT
  mkdir -p "$WORK/out"
  cat > "$WORK/build.sh" <<EOF
set -e
apt-get update -qq && apt-get install -y -qq git ca-certificates python3 build-essential >/dev/null
git clone -q --filter=blob:none https://github.com/NousResearch/hermes-agent.git /src
cd /src && git checkout -q $COMMIT
npm ci --no-audit --no-fund --loglevel=error
cd apps/desktop && HERMES_DESKTOP_VARIANT=light npm run pack
cp -a release/linux-unpacked /out/ && chown -R $(id -u):$(id -g) /out
EOF
  echo "Building Hermes Light at $COMMIT (node:26-slim container, several minutes)..."
  # node >= 26 is required by the repo; build-essential for the node-pty native module.
  docker run --rm -v "$WORK/build.sh:/build.sh:ro" -v "$WORK/out:/out" node:26-slim bash /build.sh > "$WORK/build.log" 2>&1 \
    || { tail -30 "$WORK/build.log" >&2; exit 1; }
  FROM="$WORK/out/linux-unpacked"
fi

[[ -x "$FROM/Hermes Light" ]] || { echo "no 'Hermes Light' binary in $FROM" >&2; exit 1; }

mkdir -p "$(dirname "$APP_DIR")" "$DATA_DIR" "$(dirname "$BIN")" "$(dirname "$DESKTOP")"
rm -rf "$APP_DIR.new" && cp -a "$FROM" "$APP_DIR.new" && rm -rf "$APP_DIR" && mv "$APP_DIR.new" "$APP_DIR"
[[ -n "$COMMIT" ]] && echo "$COMMIT" > "$APP_DIR/BUILD_COMMIT"

# Keyring encryption ON before the first launch (the app's default is a plain 0600 file).
if [[ ! -f "$DATA_DIR/secure-token-storage.json" ]]; then
  ( umask 077; printf '{"on":true,"migrated":true}' > "$DATA_DIR/secure-token-storage.json" )
fi
chmod 700 "$DATA_DIR"

cat > "$BIN" <<'EOF'
#!/usr/bin/env bash
# Hermes Light launcher (dotfiles scripts/hermes-light). Fixed settings folder, Wayland when available.
export HERMES_DESKTOP_USER_DATA_DIR="$HOME/.config/hermes-light"
exec "$HOME/.local/share/hermes-light/app/Hermes Light" --ozone-platform-hint=auto --password-store=gnome-libsecret "$@"
EOF
chmod 755 "$BIN"

ICON="$APP_DIR/resources/app.asar.unpacked/dist/apple-touch-icon.png"   # the only app icon PNG in the Linux build
[[ -f "$ICON" ]] || ICON=""
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Hermes Light
Comment=Hermes on endurance (remote-only desktop client)
Exec=$BIN
Icon=${ICON:-utilities-terminal}
Terminal=false
Categories=Network;
StartupWMClass=com.nousresearch.hermes-light
EOF

echo "Installed: $BIN  (menu: Hermes Light). First launch: Connect to existing Hermes -> https://hermes.home.elikesbikes.com"
