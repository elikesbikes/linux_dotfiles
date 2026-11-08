---
revision: 1
updated: 2026-11-07 21:30
---

# herdr-app-status (Hermes plugin)

Author: TARS (Emmanuel Loaiza)

## 1. What it does

Makes a Hermes terminal show in **herdr-app's Agents list** with its status: `working` (with your message as the note), `idle` when the turn ends, `blocked` while Hermes waits for your approval. herdr-app lists only programs that report a status with the OSC 7501 escape code; Claude Code does that itself, Hermes does not.

`herdr integration install hermes` does NOT cover this: it is for the other herdr (the terminal manager, `HERDR_ENV=1`) and only reports a session id.

## 2. Install (per host)

1. `scripts/onboarding/scripts/dotfiles/create-managed-symlinks.sh` links `__init__.py` and `plugin.yaml` into `~/.hermes/plugins/herdr-app-status/` (only when `~/.hermes` exists).
2. `hermes plugins enable herdr-app-status` (answer No to the tool-override question: it adds no tools).
3. Restart any running Hermes; the status appears at the first message.

## 3. How

Hooks: `pre_llm_call` (turn start) → working, `on_session_end` (turn end) → idle, `pre_approval_request` → blocked/permission, `post_approval_response` → working, exit → clear. Writes `ESC ] 7501 ; state=…:app=hermes[:kind=…][:msg=<base64>] ESC \` to `/dev/tty`, only when `HC_TERMINAL_ID` is set (a herdr-app terminal), only for the cli/tui platforms and not for sub-agents. Format copied from Claude Code's own writer.

## 4. Tested

2026-11-07 on tars, Hermes v0.21.1, herdr-app 0.1.13 / herdr-core 0.1.18: a throwaway `hc run` Hermes reported `working` with the message, then `idle`; on exit herdr removed it. Not tested: `blocked` (no approval prompt was triggered), case.

## Revision History

| Rev | Date | Commit | Change |
|---|---|---|---|
| 1 | 2026-11-07 21:30 | (this revision) | First version. |
