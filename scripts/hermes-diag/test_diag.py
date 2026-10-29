"""Tests for the hermes-diag gate. The point of these tests is to try to BREAK it."""
import os
import subprocess
import sys

import pytest

sys.path.insert(0, os.path.dirname(__file__))
import diag  # noqa: E402

@pytest.fixture(autouse=True)
def _as_hailmary(monkeypatch):
    """The legacy tests describe hailmary's profile; pin it so they pass on any build host."""
    monkeypatch.setattr(diag, "detect_profile", lambda: diag.PROFILES["hailmary"])
    monkeypatch.setattr(diag, "detect_os", lambda: "linux")


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


# ---------------------------------------------------------------- sudoers file must not drift from the allowlists

def _repo_sudoers():
    return os.path.join(os.path.dirname(__file__), "..", "..", "sudoers", "sudoers.d", "60-hermes-diag")


def test_committed_sudoers_file_matches_the_allowlists():
    import importlib.util
    spec = importlib.util.spec_from_file_location("gen_sudoers", os.path.join(os.path.dirname(__file__), "gen-sudoers.py"))
    gen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen)
    assert open(_repo_sudoers()).read() == gen.render()


def test_sudoers_rule_is_exact_host_restricted_and_has_no_wildcards():
    text = open(_repo_sudoers()).read()
    cmds = [l.strip().rstrip("\\").strip().rstrip(",") for l in text.splitlines() if l.startswith("    /usr/bin/")]
    assert len(cmds) == len(diag.CONTAINERS) + len(diag.UNITS)
    assert not any(c in text for c in ("*", "?", "[", "ALL=", "NOPASSWD: ALL"))
    assert "hermes-diag hailmary=(root) NOPASSWD: HERMES_DIAG" in text
    for name in diag.CONTAINERS:
        assert f"/usr/bin/docker logs --tail 200 {name}" in cmds


# ---------------------------------------------------------------- multi-host generic commands
ALL_BIN = {c for cands in diag.BIN.values() for c in cands}


def _gen(cmd, osname, profile=None, exists=lambda p: True):
    spy = Spy("L1\nL2\n")
    code, text, outcome = diag.handle(cmd, run=spy, profile=profile or diag.DEFAULT_PROFILE,
                                      osname=osname, exists=exists)
    return code, text, spy


@pytest.mark.parametrize("osname", ["linux", "darwin"])
def test_generic_commands_use_absolute_fixed_argv_no_sudo_no_shell(osname):
    for cmd, per_os in diag.GENERIC.items():
        if osname not in per_os:
            continue
        code, text, spy = _gen(cmd, osname)
        assert code == 0, (cmd, text)
        for argv in spy.calls:
            assert argv[0] in ALL_BIN and argv[0].startswith("/"), argv
            assert "sudo" not in argv


def test_failed_units_is_linux_only():
    assert _gen("failed-units", "linux")[0] == 0
    code, text, spy = _gen("failed-units", "darwin")
    assert code == 2 and spy.calls == []


def test_processes_never_requests_full_command_lines():
    for osname in ("linux", "darwin"):
        _, _, spy = _gen("processes", osname)
        flat = " ".join(spy.calls[0])
        assert "comm" in flat and "args" not in flat and "command" not in flat.replace("comm", "")


def test_processes_output_is_truncated_to_16_lines():
    spy = Spy("\n".join(str(i) for i in range(100)) + "\n")
    _, text, _ = diag.handle("processes", run=spy, profile=diag.DEFAULT_PROFILE, osname="linux",
                             exists=lambda p: True)
    assert len(text.strip().splitlines()) <= 17


def test_macos_hardware_overview_drops_identifiers():
    spy = Spy("Model Name: Mac mini\nSerial Number (system): ABC123\nHardware UUID: X\nChip: M2\n")
    _, text, _ = diag.handle("hostinfo", run=spy, profile=diag.DEFAULT_PROFILE, osname="darwin",
                             exists=lambda p: True)
    assert "Mac mini" in text and "M2" in text
    assert "ABC123" not in text and "Hardware UUID" not in text


def test_missing_program_is_reported_not_crashed():
    code, text, spy = _gen("hostinfo", "linux", exists=lambda p: False)
    assert code == 0 and "not installed" in text and spy.calls == []


def test_listening_is_linux_only():
    # macOS netstat prints no TCP rows and lsof only shows the caller's own processes, so it is not offered there.
    assert _gen("listening", "linux")[0] == 0
    assert _gen("listening", "darwin")[0] == 2


def test_default_profile_has_no_mcc_or_logs_commands():
    for req in ("status", "component runner", "container-logs tars-n8n", "service-journal mcc-runner.service"):
        code, text, spy = _gen(req, "linux")
        assert code == 2 and spy.calls == [], req


def test_help_lists_only_what_the_host_offers():
    _, text, _ = _gen("help", "darwin")
    assert "hostinfo" in text and "failed-units" not in text and "container-logs" not in text
    _, text, _ = _gen("help", "linux", profile=diag.PROFILES["hailmary"])
    assert "container-logs <name>" in text and "status" in text


@pytest.mark.parametrize("bad", ["hostinfo extra", "disk /etc", "memory; id", "load\n", "os $(id)"])
def test_generic_commands_reject_arguments_and_metacharacters(bad):
    code, _, spy = _gen(bad, "linux")
    assert code == 2 and spy.calls == []


def test_unknown_hostname_gets_default_profile(monkeypatch):
    monkeypatch.setattr(diag.socket, "gethostname", lambda: "Kipp.local")
    monkeypatch.undo()  # fixture patch is undone; real detect_profile runs below
    monkeypatch.setattr(diag.socket, "gethostname", lambda: "kipp.local")
    assert diag.detect_profile() is diag.DEFAULT_PROFILE
    monkeypatch.setattr(diag.socket, "gethostname", lambda: "HailMary.home")
    assert diag.detect_profile() is diag.PROFILES["hailmary"]


# ---------------------------------------------------------------- fit: owner's fitness/health data (MCC /api/life)

class FitSpy:
    """Records every URL the gate asks the MCC runner for."""
    def __init__(self, data=None):
        self.urls, self.data = [], data if data is not None else {"ok": 1}

    def __call__(self, url):
        self.urls.append(url)
        return self.data


def fit(request, data=None, profile=None):
    spy = FitSpy(data)
    code, text, outcome = diag.handle(request, api_fetch=lambda: API, run=Spy(), profile=profile, fit_fetch=spy)
    return code, text, spy


@pytest.mark.parametrize("request_text,url", [
    ("fit activities", "fitness/activities?days=28&limit=2000"),
    ("fit rides 90", "fitness/activities?days=90&limit=2000"),
    ("fit pmc 365", "fitness/pmc?days=365"),
    ("fit readiness", "fitness/readiness"),
    ("fit labs", "medical/labs"),
    ("fit anxiety", "health/anxiety"),
    ("fit activity-compare 24894506646", "fitness/activity/24894506646/compare"),
])
def test_fit_fetches_exactly_one_fixed_local_url(request_text, url):
    code, _, spy = fit(request_text)
    assert code == 0 and spy.urls == ["http://127.0.0.1:5679/api/life/" + url]


@pytest.mark.parametrize("request_text", [
    "fit", "fit nope", "fit activities 0", "fit activities 121", "fit activities 99999", "fit activities -5",
    "fit activities 28 extra", "fit activities 1e3", "fit readiness 7", "fit labs 1", "fit activity-compare",
    "fit activity-compare 12", "fit activity-compare abc123456", "fit activity-compare 24894506646 1",
    "fit activities 28&limit=1", "fit activities?days=1", "fit ../status", "fit activities/../../status",
    "fit streams 24894506646", "fit sync", "fit ACTIVITIES", "fit activities 28;id",
])
def test_fit_rejects_everything_else_and_fetches_nothing(request_text):
    code, _, spy = fit(request_text)
    assert code == 2 and spy.urls == [], request_text


def test_every_fit_url_is_local_get_with_only_digits_from_the_caller():
    for name, (path, query, default, most) in diag.FIT.items():
        arg = "24894506646" if name == "activity-compare" else (str(most) if most else None)
        url = diag.fit_url(name, arg)
        assert url.startswith("http://127.0.0.1:5679/api/life/") and "streams" not in url and "sync" not in url


def test_fit_is_hailmary_only():
    code, _, spy = fit("fit activities", profile=diag.DEFAULT_PROFILE)
    assert code == 2 and spy.urls == []
    _, text, _ = fit("help", profile=diag.DEFAULT_PROFILE)
    assert "fit <name>" not in text
    _, text, _ = fit("help")
    assert "fit <name>" in text and "labs" in text


ROWS = {"days": 28, "activities": [
    {"id": "2", "date": "2026-10-29", "type": "road_biking", "name": "Ride\twith\ntabs", "avg_power": 180,
     "hr_zones": {"z1": 10.0, "z2": 20.5, "z3": 0.0}, "power_zones": {"z1": None, "z2": 3.0}, "power_curve": [1] * 999},
    {"id": "1", "date": "2026-10-28", "type": "walking", "name": "Walk"},
    {"id": "0", "date": "2026-10-27", "type": "indoor_cycling", "name": "Pettit"},
]}


def test_activities_are_a_compact_table_without_power_curves():
    _, text, _ = fit("fit activities", data=ROWS)
    lines = text.splitlines()
    assert lines[0].startswith("3 activities") and lines[1].split("\t") == list(diag.ACTIVITY_COLS)
    first = lines[2].split("\t")
    assert len(first) == len(diag.ACTIVITY_COLS) and "Ride with tabs" in first
    assert "10/20.5/0" in first and "/3" in first and "power_curve" not in text and "999" not in text


def test_rides_keep_only_cycling():
    _, text, _ = fit("fit rides", data=ROWS)
    assert text.splitlines()[0].startswith("2 rides") and "Walk" not in text and "Pettit" in text


def test_labs_drop_the_point_history():
    data = {"summary": {"analyte_count": 1}, "analytes": [{"analyte": "ALT", "latest": 19.0, "points": [{"v": 61}]}],
            "qualitative": [{"analyte": "Appearance", "latest": "Clear", "values": [{"v": "Clear"}]}]}
    _, text, _ = fit("fit labs", data=data)
    assert '"latest":19.0' in text and "points" not in text and "values" not in text


def test_fit_output_is_still_redacted_and_capped():
    _, text, _ = fit("fit coach-report", data={"markdown": "token=" + FAKE_PAT, "pad": "y " * 40000})
    assert FAKE_PAT not in text and "truncated" in text


def test_fit_fetch_failure_is_reported_without_traceback():
    def boom(url):
        raise OSError("connection refused to http://127.0.0.1:5679/secret-path")
    code, text, outcome = diag.handle("fit pmc", fit_fetch=boom)
    assert code == 3 and text == "hermes-diag: error: OSError\n"
