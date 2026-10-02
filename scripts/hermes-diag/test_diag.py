"""Tests for the hermes-diag gate. The point of these tests is to try to BREAK it."""
import os
import subprocess
import sys

import pytest

sys.path.insert(0, os.path.dirname(__file__))
import diag  # noqa: E402

API = {"components": [
    {"name": "runner", "status": "ok", "severity": "critical", "host": "hailmary", "detail": "fine"},
    {"name": "int-garmin", "status": "fail", "severity": "warn", "host": "hailmary", "since": 1,
     "detail": "garth refresh token expired 170.6d ago"},
    {"name": "service-inventory", "status": "fail", "severity": "warn", "host": "hailmary", "detail": "Traceback ..."},
    {"name": "inbox-x", "status": "skipped", "severity": "warn", "host": "tars", "detail": ""},
]}


# Synthetic values, assembled at runtime so no token-shaped literal exists in the source
# (secret scanners flag those, and a real credential must never be used as a test fixture).
FAKE_PAT = "pst_" + "0123456789abcdef" * 4 + "::" + "FAKEFAKE" * 5
FAKE_DISCORD = "MDAwMDAwMDAwMDAwMDAwMDAw" + "." + "Fake12" + "." + "x" * 27 + "AB"


class Spy:
    """Records every external program the gate tries to run."""
    def __init__(self, out="LOGLINE\n"):
        self.calls, self.out = [], out

    def __call__(self, argv):
        self.calls.append(argv)
        return self.out


def go(request, spy=None, api=API):
    spy = spy or Spy()
    code, text, outcome = diag.handle(request, api_fetch=lambda: api, run=spy)
    return code, text, outcome, spy


# ---------------------------------------------------------------- injection / bypass attempts

@pytest.mark.parametrize("request_text", [
    "status; id", "status && id", "status | cat", "status `id`", "status $(id)", "status > /tmp/x",
    "container-logs tars-mcc-bot; rm -rf /", "container-logs tars-mcc-bot\nid", "container-logs 'tars-mcc-bot'",
    'container-logs "tars-mcc-bot"', "container-logs tars-mcc-bot\\", "container-logs ../../etc/passwd",
    "container-logs /etc/passwd", "service-journal mcc-runner.service;id", "component a b",
    "container-logs tars-mcc-bot --follow", "container-logs -f", "container-logs --tail 1 tars-mcc-bot",
    "cat /etc/shadow", "bash", "sh -c id", "sudo -n true", "ls", "docker ps", "exec id",
    "status\x00id", "status\tid", "status\rid", "STATUS", "Status", "x" * 500, "container-logs " + "a" * 200,
])
def test_hostile_requests_are_rejected_and_run_nothing(request_text):
    code, text, outcome, spy = go(request_text)
    assert code == 2 and outcome == "rejected", (request_text, text)
    assert spy.calls == [], "a rejected request must never reach an external program"


def test_unknown_container_and_unit_are_rejected_even_if_well_formed():
    for r in ("container-logs traefik", "container-logs hermes", "container-logs tars-mcc-bot2",
              "container-logs TARS-MCC-BOT", "service-journal sshd.service", "service-journal ssh",
              "service-journal mcc-runner", "service-journal mcc-runner.service.d"):
        code, _, outcome, spy = go(r)
        assert (code, outcome) == (2, "rejected"), r
        assert spy.calls == []


def test_unknown_component_is_rejected():
    assert go("component ../x")[0] == 2
    assert go("component nope")[0] == 2


def test_subcommands_with_wrong_argument_counts_are_rejected():
    for r in ("status now", "help me", "component", "container-logs", "service-journal", "component a b"):
        assert go(r)[0] == 2, r


# ---------------------------------------------------------------- allowed requests

def test_status_lists_only_non_ok_and_fail_first():
    code, text, outcome, spy = go("status")
    assert (code, outcome) == (0, "ok") and spy.calls == []
    lines = text.splitlines()
    assert lines[0] == "4 components; 1 ok; 3 not ok"
    assert lines[1].startswith("- int-garmin [fail]") and lines[2].startswith("- service-inventory [fail]")
    assert lines[3].startswith("- inbox-x [skipped]")
    assert "runner" not in text


def test_component_returns_one_component_json():
    code, text, _, spy = go("component int-garmin")
    assert code == 0 and '"name": "int-garmin"' in text and spy.calls == []


def test_container_logs_runs_exactly_the_fixed_argv_without_a_shell():
    code, text, outcome, spy = go("container-logs tars-mcc-bot")
    assert (code, outcome) == (0, "ok") and "LOGLINE" in text
    assert spy.calls == [["sudo", "-n", "/usr/bin/docker", "logs", "--tail", "200", "tars-mcc-bot"]]


def test_service_journal_runs_exactly_the_fixed_argv():
    code, _, _, spy = go("service-journal mcc-runner.service")
    assert code == 0
    assert spy.calls == [["sudo", "-n", "/usr/bin/journalctl", "-u", "mcc-runner.service", "-n", "200",
                          "--no-pager", "-o", "short-iso"]]


def test_every_allowlisted_container_is_accepted():
    for name in diag.CONTAINERS:
        assert go(f"container-logs {name}")[0] == 0, name


def test_empty_request_shows_help_and_runs_nothing():
    for r in (None, "", "   "):
        code, text, _, spy = go(r)
        assert code == 0 and "container-logs" in text and spy.calls == []


# ---------------------------------------------------------------- redaction and caps

def test_secrets_are_redacted_in_command_output():
    secret_lines = "\n".join([
        "token=abc123SECRETvalue", "Authorization: Bearer abcdefghijklmnop1234",
        "PAT " + FAKE_PAT,
        "discord " + FAKE_DISCORD,
        "jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop",
        '{"password": "hunter2hunter2"}', "api_key: sk-ant-api03-ABCDEFGHIJKLMNOP",
        "-----BEGIN OPENSSH PRIVATE KEY-----\nAAAAB3NzaC1\n-----END OPENSSH PRIVATE KEY-----",
        "blob " + "A1b2C3d4" * 8,
    ])
    code, text, _, _ = go("container-logs tars-mcc-bot", Spy(secret_lines))
    assert code == 0
    for leak in ("abc123SECRETvalue", "abcdefghijklmnop1234", "0123456789abcdef0123456789abcdef", "FAKEFAKEFAKEFAKE", "xxxxxxxxxxxxxxxxxxxxxxxxxxxAB",
                 "hunter2hunter2", "sk-ant-api03-ABCDEF", "AAAAB3NzaC1", "A1b2C3d4A1b2C3d4A1b2C3d4"):
        assert leak not in text, leak
    assert "<redacted" in text


def test_normal_log_text_is_not_mangled():
    line = "2026-10-02T13:55:01+0000 runner INFO sweep done in 12.3s: 156 components, 2 failed\n"
    assert go("container-logs tars-mcc-bot", Spy(line))[1] == line


def test_redaction_applies_to_api_data_too():
    api = {"components": [{"name": "x", "status": "fail", "detail": "password=SuperSecret99 expired"}]}
    assert "SuperSecret99" not in go("status", api=api)[1]
    assert "SuperSecret99" not in go("component x", api=api)[1]


def test_output_is_capped():
    code, text, _, _ = go("container-logs tars-mcc-bot", Spy("line of log text\n" * 20000))
    assert code == 0 and len(text.encode()) <= diag.MAX_BYTES + 100 and "truncated" in text


# ---------------------------------------------------------------- failures never leak internals

def test_timeout_and_unexpected_errors_are_reported_without_tracebacks():
    def boom(argv):
        raise subprocess.TimeoutExpired(argv, 15)
    code, text, outcome = diag.handle("container-logs tars-mcc-bot", api_fetch=lambda: API, run=boom)
    assert (code, outcome) == (3, "timeout") and "Traceback" not in text

    def bad_api():
        raise ConnectionError("secret-host:5679 refused")
    code, text, outcome = diag.handle("status", api_fetch=bad_api, run=Spy())
    assert (code, outcome) == (3, "error") and "secret-host" not in text and "ConnectionError" in text


def test_main_uses_ssh_original_command_and_logs_every_request(monkeypatch, capsys):
    logged = []
    monkeypatch.setattr(diag.syslog, "openlog", lambda *a, **k: None)
    monkeypatch.setattr(diag.syslog, "syslog", lambda prio, msg: logged.append(msg))
    monkeypatch.setattr(diag, "_api_fetch", lambda: API)
    for req, want_code in (("status", 0), ("cat /etc/passwd", 2)):
        monkeypatch.setenv("SSH_ORIGINAL_COMMAND", req)
        monkeypatch.setenv("SSH_CLIENT", "192.168.5.46 54321 22")
        assert diag.main() == want_code
    out = capsys.readouterr().out
    assert "rejected" in out and "int-garmin" in out
    assert len(logged) == 2
    assert "client=192.168.5.46" in logged[0] and "outcome=ok" in logged[0]
    assert "outcome=rejected" in logged[1] and "cat /etc/passwd" in logged[1]


def test_log_line_cannot_be_forged_with_newlines(monkeypatch):
    logged = []
    monkeypatch.setattr(diag.syslog, "openlog", lambda *a, **k: None)
    monkeypatch.setattr(diag.syslog, "syslog", lambda prio, msg: logged.append(msg))
    diag.audit("status\nFAKE LOG LINE outcome=ok", "1.2.3.4", "rejected", 0, 1)
    assert "\n" not in logged[0]


def test_source_has_no_shell_and_no_eval():
    src = open(os.path.join(os.path.dirname(__file__), "diag.py")).read()
    assert "shell=True" not in src and "os.system" not in src and "eval(" not in src and "exec(" not in src.replace("def execute(", "")


# ---------------------------------------------------------------- each layer must hold on its own
# (the allowlists would catch most of these anyway; the parser must not rely on that)

@pytest.mark.parametrize("request_text", [
    "status;id", "status$(id)", "status|id", "status`id`", "status&id", "status>x", "status<x", "status\\x",
    "component a;b", "container-logs a$b", "service-journal a|b", "status'", 'status"', "status/", "status\n", "status*",
])
def test_parser_rejects_hostile_characters_by_itself(request_text):
    with pytest.raises(diag.Rejected):
        diag.parse(request_text)


@pytest.mark.parametrize("name", ["..", "../x", "a/b", "-rf", ".hidden", "a" * 65, "a b", "", "a;b"])
def test_name_check_rejects_bad_names_by_itself(name):
    # `a b` / `` are split or length-checked earlier; the point is that none of these ever parse.
    with pytest.raises(diag.Rejected):
        diag.parse(f"component {name}")


def test_parser_accepts_only_the_known_shapes():
    assert diag.parse("status") == ("status", [])
    assert diag.parse("component int-garmin") == ("component", ["int-garmin"])
    assert diag.parse("container-logs tars-mcc-bot") == ("container-logs", ["tars-mcc-bot"])
    assert diag.parse("service-journal mcc-runner.service") == ("service-journal", ["mcc-runner.service"])
