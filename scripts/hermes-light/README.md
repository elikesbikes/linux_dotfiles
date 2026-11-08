---
revision: 1
updated: 2026-11-07 20:40
---

# Hermes Light (remote-only Hermes Desktop)

Author: TARS (Emmanuel Loaiza)

## 1. What it is

Hermes Light is the Hermes Desktop app **without a local agent**: no Python, no local Hermes, no model login. It only connects to an existing Hermes gateway, ours on endurance (`https://hermes.home.elikesbikes.com`), and everything (chats, memory, skills, terminal commands, files) runs there. It is a "thin client" in a native window. The browser version of the same workspace is `https://hermes-app.home.elikesbikes.com`.

Nous does not publish a Linux build of Light, so `install-hermes-light.sh` builds it from the hermes-agent source, at the commit endurance runs, inside a throwaway `node:26-slim` container. Nothing is installed on the host except the app folder.

## 2. Prerequisites

- Docker (for the build), `ssh endurance` (to read the commit; or pass `--commit`).
- A Secret Service keyring (gnome-keyring on Omarchy). The script stops without one, because the sign-in token would otherwise be a plain file.

## 3. Install / update

```bash
~/devops/github/linux_dotfiles/scripts/hermes-light/install-hermes-light.sh
```

Writes `~/.local/share/hermes-light/app/`, `~/.local/bin/hermes-light`, the menu entry `hermes-light.desktop`, and `~/.config/hermes-light/secure-token-storage.json` (`{"on":true}`: keyring encryption on before the first sign-in; the app's default is a plain 0600 file). Run it again after endurance's Hermes is upgraded.

## 4. First launch

1. Open **Hermes Light** from the app menu.
2. Settings → Gateways: add a remote gateway `https://hermes.home.elikesbikes.com`, sign in (browser opens Authelia), set it as **Primary**.
3. Leave "This device" alone: Light has no local runtime, and no model login belongs on tars.

## 5. Remove

```bash
rm -rf ~/.local/share/hermes-light ~/.config/hermes-light ~/.local/bin/hermes-light ~/.local/share/applications/hermes-light.desktop
```

Also delete the Hermes entry in the keyring (Seahorse) to remove the stored token.

## 6. Tested

2026-11-07 on tars (commit 2bd378ed, Hermes 0.23.0): build OK, install OK, the app starts on Hyprland with no local backend (`backend-ownership.json` empty) and `~/.hermes` untouched. The remote sign-in is done by the owner.

## Revision History

| Rev | Date | Commit | Change |
|---|---|---|---|
| 1 | 2026-11-07 20:40 | (this revision) | First version: build in a container, install, keyring encryption on before first launch. |
