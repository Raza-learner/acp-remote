import pytest

from relay.session_store import SessionStore


@pytest.fixture
def store():
    return SessionStore(db=None)


class TestRegister:
    def test_register_creates_session(self, store):
        store.register("sess-1", client_id="client-1", name="My Session", cwd="/home", agent_id="agent-1")
        session = store.get("sess-1")
        assert session is not None
        assert session["sessionId"] == "sess-1"
        assert session["clientId"] == "client-1"
        assert session["name"] == "My Session"
        assert session["title"] == "My Session"
        assert session["cwd"] == "/home"
        assert session["agentId"] == "agent-1"
        assert "createdAt" in session
        assert "updatedAt" in session

    def test_register_generates_display_name_from_timestamp(self, store):
        store.register("sess-2")
        session = store.get("sess-2")
        assert session["name"].startswith("Session ")
        assert session["title"].startswith("Session ")

    def test_register_overwrites_existing(self, store):
        store.register("sess-1", client_id="c1", name="Original")
        store.register("sess-1", client_id="c2", name="Updated")
        session = store.get("sess-1")
        assert session["clientId"] == "c2"
        assert session["name"] == "Updated"

    def test_register_preserves_updated_at(self, store):
        store.register("sess-1", updated_at=1234567890.0)
        session = store.get("sess-1")
        assert session["createdAt"] == 1234567890.0
        assert session["updatedAt"] == 1234567890.0


class TestRemove:
    def test_remove_removes_session(self, store):
        store.register("sess-1", agent_id="a1")
        store.remove("sess-1")
        assert store.get("sess-1") is None

    def test_remove_with_matching_agent_id_removes(self, store):
        store.register("sess-1", agent_id="a1")
        store.remove("sess-1", agent_id="a1")
        assert store.get("sess-1") is None

    def test_remove_with_nonmatching_agent_id_still_removes(self, store):
        store.register("sess-1", agent_id="a1")
        store.remove("sess-1", agent_id="a2")
        assert store.get("sess-1") is None

    def test_remove_nonexistent(self, store):
        store.remove("nonexistent")
        pass

    def test_remove_without_agent_id_always_removes(self, store):
        store.register("sess-1", agent_id="a1")
        store.remove("sess-1")
        assert store.get("sess-1") is None


class TestDeleted:
    def test_mark_deleted(self, store):
        store.mark_deleted("sess-1")
        assert store.is_deleted("sess-1") is True

    def test_is_deleted_returns_false_for_unknown(self, store):
        assert store.is_deleted("unknown") is False

    def test_deleted_sessions_returns_copy(self, store):
        store.mark_deleted("sess-1")
        result = store.deleted_sessions()
        assert result == {"sess-1"}
        result.add("mutated")
        assert store.deleted_sessions() == {"sess-1"}


class TestRemoveClient:
    def test_removes_all_client_sessions(self, store):
        store.register("s1", client_id="c1")
        store.register("s2", client_id="c1")
        store.register("s3", client_id="c2")
        removed = store.remove_client("c1")
        assert set(removed) == {"s1", "s2"}
        assert store.get("s1") is None
        assert store.get("s2") is None
        assert store.get("s3") is not None

    def test_remove_client_no_sessions(self, store):
        removed = store.remove_client("nonexistent")
        assert removed == []


class TestRename:
    def test_rename_existing_session(self, store):
        store.register("s1", name="Old")
        assert store.rename("s1", "New Name") is True
        assert store.get("s1")["name"] == "New Name"
        assert store.get("s1")["title"] == "New Name"

    def test_rename_nonexistent_returns_false(self, store):
        assert store.rename("unknown", "Name") is False


class TestListSessions:
    def test_list_all_sessions(self, store):
        store.register("s1", agent_id="a1")
        store.register("s2", agent_id="a2")
        sessions = store.list_sessions()
        assert len(sessions) == 2

    def test_list_filtered_by_agent_id(self, store):
        store.register("s1", agent_id="a1")
        store.register("s2", agent_id="a2")
        sessions = store.list_sessions(agent_id="a1")
        assert len(sessions) == 1
        assert sessions[0]["sessionId"] == "s1"

    def test_list_no_matches(self, store):
        store.register("s1", agent_id="a1")
        sessions = store.list_sessions(agent_id="nonexistent")
        assert sessions == []

    def test_list_empty_store(self, store):
        assert store.list_sessions() == []


class TestGet:
    def test_get_existing(self, store):
        store.register("s1")
        assert store.get("s1") is not None

    def test_get_nonexistent(self, store):
        assert store.get("unknown") is None


class TestDaemonId:
    def test_set_and_get(self, store):
        store.set_daemon_id("daemon-1")
        assert store.get_daemon_id() == "daemon-1"

    def test_clear(self, store):
        store.set_daemon_id("daemon-1")
        store.clear_daemon_id()
        assert store.get_daemon_id() == ""

    def test_default_empty(self, store):
        assert store.get_daemon_id() == ""

    def test_register_with_explicit_daemon_id(self, store):
        store.register("s1", agent_id="a1", daemon_id="pc-a")
        assert store.get("s1")["daemonId"] == "pc-a"

    def test_list_filtered_by_daemon_id(self, store):
        store.register("s1", agent_id="a1", daemon_id="pc-a")
        store.register("s2", agent_id="a1", daemon_id="pc-b")
        sessions = store.list_sessions(agent_id="a1", daemon_id="pc-a")
        assert len(sessions) == 1
        assert sessions[0]["sessionId"] == "s1"

    def test_list_daemon_id_does_not_leak_other_pc(self, store):
        store.register("s1", agent_id="a1", daemon_id="pc-a")
        store.register("s2", agent_id="a1", daemon_id="pc-b")
        sessions = store.list_sessions(agent_id="a1", daemon_id="pc-b")
        assert {s["sessionId"] for s in sessions} == {"s2"}
