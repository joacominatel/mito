from pathlib import Path

from lcu_recorder.discovery import Credentials, discover, parse_lockfile, parse_process_list

UX = "/Applications/League of Legends.app/Contents/LoL/LeagueClient.app/Contents/LeagueClientUx"


def test_reads_port_and_token_from_the_ux_process_in_any_order():
    ps = "\n".join(
        [
            "ARGS",
            "/usr/sbin/syslogd",
            f"{UX} --app-pid=1234 --remote-auth-token=AbC-d_9 --locale=es_AR --app-port=54321",
        ]
    )
    assert parse_process_list(ps) == Credentials(port=54321, token="AbC-d_9")


def test_accepts_quoted_arguments_and_paths_with_spaces():
    ps = f'"{UX}" "--app-port=50001" "--remote-auth-token=tok123" "--install-directory=/A B/"'
    assert parse_process_list(ps) == Credentials(port=50001, token="tok123")


def test_ignores_processes_that_are_not_the_ux_or_lack_arguments():
    ps = "\n".join(
        [
            "/usr/bin/other --app-port=1 --remote-auth-token=nope",
            f"{UX}Helper --type=renderer",
            f"{UX} --app-port=60000",
        ]
    )
    assert parse_process_list(ps) is None


def test_rejects_an_out_of_range_port():
    assert parse_process_list(f"{UX} --app-port=70000 --remote-auth-token=t") is None


def test_parses_a_well_formed_lockfile():
    assert parse_lockfile("LeagueClient:1234:54321:s3cr3t:https\n") == Credentials(54321, "s3cr3t")


def test_rejects_malformed_lockfiles():
    for text in ["", "LeagueClient:1234:54321", "LeagueClient:1:port:pw:https", "a:1:2::https"]:
        assert parse_lockfile(text) is None


def test_the_token_never_shows_in_repr():
    assert "s3cr3t" not in repr(Credentials(port=1, token="s3cr3t"))


def test_falls_back_to_the_lockfile_when_no_process_matches(tmp_path: Path, monkeypatch):
    lockfile = tmp_path / "lockfile"
    lockfile.write_text("LeagueClient:9:50123:pw:https")
    monkeypatch.setattr("lcu_recorder.discovery.parse_process_list", lambda _: None, raising=True)
    assert discover(lockfile) == Credentials(50123, "pw")
    assert discover(tmp_path / "missing") is None
