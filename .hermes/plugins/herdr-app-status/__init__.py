"""Report Hermes turn status to herdr-app, so Hermes shows in its Agents list.

herdr-app lists a terminal as an agent only when its program reports a status
with OSC 7501 (herdr-core asks with `ESC ] 7501 ; ?`). Claude Code does this
natively; Hermes does not, and herdr's own `herdr integration install hermes`
targets the other herdr (the terminal manager, HERDR_ENV=1) and only reports a
session id. This plugin fills the gap for herdr-app terminals (HC_TERMINAL_ID).

Wire format, the same fields Claude Code writes (checked in its binary and with
a test terminal on 2026-11-07):
    ESC ] 7501 ; state=<working|idle|blocked>:app=hermes[:kind=permission][:msg=<base64>] ESC \\
and `state=clear` when Hermes exits.

Lives in linux_dotfiles (.hermes/plugins/herdr-app-status), linked into
~/.hermes/plugins by create-managed-symlinks.sh, enabled with
`hermes plugins enable herdr-app-status`.
"""

from __future__ import annotations

import atexit
import base64
import os
import re

_APP = "hermes"
_INTERACTIVE = {"cli", "tui"}
_MSG_MAX = 160
_CONTROL = re.compile(r"[\x00-\x1f\x7f]+")
_state = {"last": None, "registered_exit": False}


def _in_herdr_app() -> bool:
    return bool(os.environ.get("HC_TERMINAL_ID"))


def _emit(state: str, kind: str | None = None, msg: str | None = None) -> None:
    if not _in_herdr_app():
        return
    fields = [f"state={state}", f"app={_APP}"]
    if state == "blocked" and kind:
        fields.append(f"kind={kind}")
    if msg:
        text = _CONTROL.sub(" ", msg).strip()[:_MSG_MAX]
        if text:
            fields.append("msg=" + base64.b64encode(text.encode("utf-8")).decode("ascii"))
    seq = "\x1b]7501;" + ":".join(fields) + "\x1b\\"
    try:
        fd = os.open("/dev/tty", os.O_WRONLY | os.O_NOCTTY)
        try:
            os.write(fd, seq.encode("utf-8"))
        finally:
            os.close(fd)
        _state["last"] = state
    except OSError:
        pass  # no controlling terminal (gateway, cron, piped): stay silent


def _clear_on_exit() -> None:
    if _state["last"] not in (None, "clear"):
        _emit("clear")


def _interactive(kwargs) -> bool:
    return kwargs.get("platform") in _INTERACTIVE and not kwargs.get("parent_session_id")


def _session_started(**kwargs) -> None:
    if not _interactive(kwargs):
        return
    if not _state["registered_exit"]:
        atexit.register(_clear_on_exit)
        _state["registered_exit"] = True
    _emit("idle")


def _turn_started(**kwargs) -> None:
    if _interactive(kwargs):
        _emit("working", msg=kwargs.get("user_message") if isinstance(kwargs.get("user_message"), str) else None)
    return None  # pre_llm_call: never inject context


def _turn_ended(**kwargs) -> None:
    # Canonical shape has platform; CLI/TUI exit shapes may omit it, so only
    # skip shapes that name a non-interactive platform.
    platform = kwargs.get("platform")
    if platform is not None and platform not in _INTERACTIVE:
        return
    if kwargs.get("parent_session_id"):
        return
    if _state["last"] is not None:
        _emit("idle")


def _approval_asked(**kwargs) -> None:
    if _state["last"] is not None:
        _emit("blocked", kind="permission", msg=kwargs.get("description") or "approval needed")


def _approval_answered(**kwargs) -> None:
    if _state["last"] == "blocked":
        _emit("working")


def register(ctx):
    ctx.register_hook("on_session_start", _session_started)
    ctx.register_hook("pre_llm_call", _turn_started)
    ctx.register_hook("on_session_end", _turn_ended)
    ctx.register_hook("pre_approval_request", _approval_asked)
    ctx.register_hook("post_approval_response", _approval_answered)
