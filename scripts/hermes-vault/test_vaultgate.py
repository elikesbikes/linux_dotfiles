"""Tests for the hermes-vault gate's boundary (parsing, path and text rules). No network, no Proton, no CouchDB.
Run: python3 -m pytest -q scripts/hermes-vault/test_vaultgate.py
"""

import importlib.util
import io
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location("vaultgate", Path(__file__).with_name("vaultgate.py"))
vg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vg)

COURSE = "Career/Courses/2026-Fall COMP 666 - Intro to Software Development"


@pytest.mark.parametrize("path", [
    f"{COURSE}/Modules/1.1 - Version Control.md",
    f"{COURSE}/Readings/2.3 - Clean Code (ch. 1).md",
    f"{COURSE}/Assignments/1.0.1 - Setup Development Environment.md",
    "Career/Courses/2026-Fall BIO 101 - Biología/Modules/1.1 - Célula & ADN.md",
])
def test_valid_write_paths(path):
    assert vg.check_path(path, vg.WRITE_ROOTS, note=True) == path


@pytest.mark.parametrize("path,why", [
    ("", "required"),
    ("/Career/Courses/x/y.md", "relative"),
    ("Career/Courses/../Finances/x.md", "not allowed"),
    ("Career/Courses/x/.hidden.md", "not allowed"),
    ("Career/Courses/x/y.txt", ".md"),
    ("Finances/x.md", "under"),
    ("Templates/11-Course Hub.md", "under"),            # readable, never writable
    ('"Career/Courses/x/y.md"', "quote"),
    ("Career/Courses/x/y.md; rm -rf /", "not allowed"),
    ("Career/Courses/x/$(id).md", "not allowed"),
    ("Career/Courses//y.md", "//"),
    ("Career/Courses/a/b/c/d.md", "deeper"),
    ("Career/Courses/x/ y.md", "not allowed"),
    ("Career/Courses/x/y.md ", "trailing"),
    ("Career/Courses/x\\y.md", "\\"),
    ("Career/Courses/x/" + "a" * 300 + ".md", "longer"),
])
def test_refused_write_paths(path, why):
    with pytest.raises(vg.Refused, match=None) as e:
        vg.check_path(path, vg.WRITE_ROOTS, note=True)
    assert why.lower() in str(e.value).lower()


def test_read_roots_allow_templates_and_listing_prefixes():
    assert vg.check_path("Templates/12-Module Note.md", vg.READ_ROOTS, note=True)
    assert vg.check_path("Career/Courses/", vg.READ_ROOTS, note=False)
    assert vg.check_path(f"{COURSE}/", vg.READ_ROOTS, note=False)
    assert vg.check_path("Career/", vg.READ_ROOTS, note=False)     # parent of a root; results are filtered
    with pytest.raises(vg.Refused):
        vg.check_path("Career", vg.READ_ROOTS, note=False)
    with pytest.raises(vg.Refused):
        vg.check_path("Daily Notes/", vg.READ_ROOTS, note=False)


@pytest.mark.parametrize("request_,verb,arg", [
    (None, "help", ""), ("", "help", ""), ("help", "help", ""),
    ("list Career/Courses/", "list", "Career/Courses/"),
    (f"create {COURSE}/Modules/1.1 - A b.md", "create", f"{COURSE}/Modules/1.1 - A b.md"),
])
def test_parse(request_, verb, arg):
    assert vg.parse(request_) == (verb, arg)


@pytest.mark.parametrize("request_", ["delete x.md", "put x.md", "rm x", "CREATE x", "get x\nrm -rf /", "sh -c id"])
def test_parse_refuses(request_):
    with pytest.raises(vg.Refused):
        vg.parse(request_)


def test_note_text_rules():
    assert vg.check_note_text("# Hi\n".encode()) == "# Hi\n"
    for bad in (b"", b"   \n", b"\xff\xfe", b"a\0b", b"x" * (vg.MAX_NOTE + 1)):
        with pytest.raises(vg.Refused):
            vg.check_note_text(bad)


def test_course_root():
    assert vg.course_root(f"{COURSE}/Modules/x.md") == f"{COURSE}/"
    with pytest.raises(vg.Refused):
        vg.course_root("Career/Courses/x.md")


def test_refusals_never_touch_secrets(monkeypatch):
    def boom(*a, **k):
        raise AssertionError("secrets must not be loaded for a refused request")
    monkeypatch.setattr(vg, "load_secrets", boom)
    for req in ("delete x", "create Finances/x.md", "create Career/Courses/x.md", "get ../etc/passwd"):
        code, out, outcome, _ = vg.handle(req, io.BytesIO(b"# note\n"))
        assert code == 2 and outcome == "refused" and out.startswith("REFUSED")


def test_help_needs_no_secrets(monkeypatch):
    monkeypatch.setattr(vg, "load_secrets", lambda: (_ for _ in ()).throw(AssertionError()))
    code, out, outcome, _ = vg.handle("help", io.BytesIO())
    assert code == 0 and "create-only" in out
