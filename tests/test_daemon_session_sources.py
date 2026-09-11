import asyncio
import json
import sqlite3
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

from daemon.main import (
    _answer_list_request,
    _list_fallback,
    _list_pending,
)
from daemon.session_sources import (
    list_local_sessions,
    merge_session_lists,
)


@pytest.fixture(autouse=True)
def clean_pending():
    _list_pending.clear()
    yield
    _list_pending.clear()


def _make_opencode_home(tmp_path: Path) -> Path:
    db_dir = tmp_path / ".local" / "share" / "opencode"
    db_dir.mkdir(parents=True)
    conn = sqlite3.connect(db_dir / "opencode.db")
    conn.execute(
        "CREATE TABLE session (id TEXT, title TEXT, directory TEXT, time_created INTEGER)"
    )
    conn.execute(
        "INSERT INTO session VALUES (?, ?, ?, ?)",
        ("ses_disk1", "Disk Title", "/home/raza/Proj", 1788353626323),
    )
    conn.execute(
        "INSERT INTO session VALUES (?, ?, ?, ?)",
        ("ses_disk2", "", "/home/raza", 1788000000000),
    )
    conn.commit()
    conn.close()
    return tmp_path


class TestOpencodeReader:
    def test_reads_sqlite_sessions_newest_first(self, tmp_path):
        home = _make_opencode_home(tmp_path)
        sessions = list_local_sessions("opencode", home=home)
        assert [s["sessionId"] for s in sessions] == ["ses_disk1", "ses_disk2"]
        first = sessions[0]
        assert first["title"] == "Disk Title"
        assert first["cwd"] == "/home/raza/Proj"
        assert first["updatedAt"] == pytest.approx(1788353626.323)
        assert first["agentId"] == "opencode"

    def test_missing_db_yields_empty(self, tmp_path):
        assert list_local_sessions("opencode", home=tmp_path) == []

    def test_missing_table_yields_empty(self, tmp_path):
        db_dir = tmp_path / ".local" / "share" / "opencode"
        db_dir.mkdir(parents=True)
        conn = sqlite3.connect(db_dir / "opencode.db")
        conn.execute("CREATE TABLE other (id TEXT)")
        conn.commit()
        conn.close()
        assert list_local_sessions("opencode", home=tmp_path) == []


class TestCursorReader:
    def test_reads_meta_json(self, tmp_path):
        d = tmp_path / ".cursor" / "acp-sessions" / "uuid-1"
        d.mkdir(parents=True)
        (d / "meta.json").write_text(json.dumps({"schemaVersion": 1, "cwd": "/tmp/work"}))
        sessions = list_local_sessions("cursor", home=tmp_path)
        assert len(sessions) == 1
        assert sessions[0]["sessionId"] == "uuid-1"
        assert sessions[0]["cwd"] == "/tmp/work"
        assert sessions[0]["agentId"] == "cursor"

    def test_missing_dir_yields_empty(self, tmp_path):
        assert list_local_sessions("cursor", home=tmp_path) == []


class TestClaudeReader:
    def test_reads_jsonl_transcripts(self, tmp_path):
        proj = tmp_path / ".claude" / "projects" / "-home-raza"
        proj.mkdir(parents=True)
        (proj / "abc123.jsonl").write_text(
            '{"type":"x","cwd":"/home/raza"}\n'
            '{"type":"summary","summary":"Do things"}\n'
        )
        sessions = list_local_sessions("claude", home=tmp_path)
        assert len(sessions) == 1
        assert sessions[0]["sessionId"] == "abc123"
        assert sessions[0]["cwd"] == "/home/raza"
        assert sessions[0]["title"] == "Do things"

    def test_missing_dir_yields_empty(self, tmp_path):
        assert list_local_sessions("claude", home=tmp_path) == []


class TestCodexReader:
    def test_reads_rollout_first_line(self, tmp_path):
        d = tmp_path / ".codex" / "sessions" / "2026" / "01"
        d.mkdir(parents=True)
        (d / "rollout-x.jsonl").write_text(
            json.dumps(
                {
                    "timestamp": "2026-01-02T03:04:05Z",
                    "type": "session_meta",
                    "payload": {"id": "ses-codex-1", "cwd": "/home/raza/code"},
                }
            )
            + "\n"
        )
        sessions = list_local_sessions("codex", home=tmp_path)
        assert len(sessions) == 1
        assert sessions[0]["sessionId"] == "ses-codex-1"
        assert sessions[0]["cwd"] == "/home/raza/code"

    def test_missing_dir_yields_empty(self, tmp_path):
        assert list_local_sessions("codex", home=tmp_path) == []


class TestDispatch:
    def test_unknown_agent_yields_empty(self, tmp_path):
        assert list_local_sessions("copilot", home=tmp_path) == []
        assert list_local_sessions("", home=tmp_path) == []

    def test_matches_by_substring(self, tmp_path):
        _make_opencode_home(tmp_path)
        assert len(list_local_sessions("Opencode-Remote", home=tmp_path)) == 2


class TestMerge:
    def test_live_wins_and_disk_fills_gaps(self):
        live = [
            {"sessionId": "a", "title": "", "cwd": "", "updatedAt": 200.0},
            {"sessionId": "b", "title": "Live B", "cwd": "/live", "updatedAt": 100.0},
        ]
        local = [
            {"sessionId": "a", "title": "Disk A", "cwd": "/disk", "updatedAt": 50.0},
            {"sessionId": "c", "title": "Disk C", "cwd": "/c", "updatedAt": 300.0},
        ]
        merged = merge_session_lists(live, local, "opencode")
        by_id = {s["sessionId"]: s for s in merged}
        assert by_id["a"]["title"] == "Disk A"
        assert by_id["a"]["cwd"] == "/disk"
        assert by_id["b"]["title"] == "Live B"
        assert "c" in by_id
        # Newest first: c(300), a(200), b(100)
        assert [s["sessionId"] for s in merged] == ["c", "a", "b"]
        assert all(s["agentId"] == "opencode" for s in merged)

    def test_none_live_keeps_disk(self):
        local = [{"sessionId": "a", "title": "A", "cwd": "/a", "updatedAt": 1.0}]
        assert [s["sessionId"] for s in merge_session_lists(None, local, "opencode")] == ["a"]

    def test_skips_malformed_entries(self):
        merged = merge_session_lists(["nope", {"no": "id"}], [{"sessionId": "ok"}], "opencode")
        assert [s["sessionId"] for s in merged] == ["ok"]


class FakeWebSocket:
    def __init__(self):
        self.sent = []

    async def send(self, raw: str):
        self.sent.append(json.loads(raw))


class TestAnswerListRequest:
    def test_merges_live_and_disk_single_response(self):
        ws = FakeWebSocket()
        agent = SimpleNamespace(id="opencode")
        _list_pending["7"] = {
            "agent": agent,
            "local": [
                {"sessionId": "disk", "title": "D", "cwd": "/d", "updatedAt": 1.0,
                 "agentId": "opencode"}
            ],
            "answered": False,
            "task": None,
            "id": 7,
        }
        live = [{"sessionId": "live", "title": "L", "cwd": "/l", "updatedAt": 2.0}]
        assert asyncio.run(_answer_list_request(ws, "7", live)) is True
        assert "7" not in _list_pending
        assert len(ws.sent) == 1
        msg = ws.sent[0]
        assert msg["id"] == 7
        assert [s["sessionId"] for s in msg["result"]["sessions"]] == ["live", "disk"]
        assert msg["result"]["agentId"] == "opencode"

    def test_error_live_falls_back_to_disk(self):
        ws = FakeWebSocket()
        agent = SimpleNamespace(id="cursor")
        _list_pending["9"] = {
            "agent": agent,
            "local": [{"sessionId": "disk", "title": "", "cwd": "/t",
                       "updatedAt": 1.0, "agentId": "cursor"}],
            "answered": False,
            "task": None,
            "id": 9,
        }
        assert asyncio.run(_answer_list_request(ws, "9", None)) is True
        assert [s["sessionId"] for s in ws.sent[0]["result"]["sessions"]] == ["disk"]

    def test_double_answer_returns_false(self):
        ws = FakeWebSocket()
        assert asyncio.run(_answer_list_request(ws, "missing", [])) is False
        assert ws.sent == []

    def test_fallback_answers_from_disk_on_silence(self, monkeypatch):
        import daemon.main as dm

        monkeypatch.setattr(dm, "_LIST_AGENT_TIMEOUT", 0.01)
        ws = FakeWebSocket()
        agent = SimpleNamespace(id="opencode")
        _list_pending["11"] = {
            "agent": agent,
            "local": [{"sessionId": "disk", "title": "D", "cwd": "/d",
                       "updatedAt": 1.0, "agentId": "opencode"}],
            "answered": False,
            "task": None,
            "id": 11,
        }
        asyncio.run(_list_fallback(ws, "11"))
        assert len(ws.sent) == 1
        assert [s["sessionId"] for s in ws.sent[0]["result"]["sessions"]] == ["disk"]
        assert "11" not in _list_pending
