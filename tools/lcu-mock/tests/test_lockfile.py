import os
import stat

from lcu_mock.lockfile import lockfile_text, write_lockfile


def test_lockfile_text_matches_the_client_format():
    assert lockfile_text(4321, 54321, "abc_DEF-123") == "LeagueClient:4321:54321:abc_DEF-123:https"


def test_write_lockfile_creates_parents_and_is_owner_only(tmp_path):
    path = tmp_path / "nested" / "lockfile"
    write_lockfile(path, 54321, "secret")

    parts = path.read_text(encoding="utf-8").split(":")
    assert parts == ["LeagueClient", str(os.getpid()), "54321", "secret", "https"]
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
