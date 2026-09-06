import json
from unittest import mock

import pytest
from fastapi import WebSocket


@pytest.fixture(autouse=True)
def _reset_state():
    import relay.state

    relay.state.store = mock.MagicMock()
    relay.state.store.is_deleted.return_value = False
    relay.state.store.register.return_value = None
    relay.state.app_clients = {}
    relay.state.daemons = {}
    relay.state.app_to_daemon = {}
    relay.state.code_to_daemon = {}
    relay.state.known_tokens = {}
    yield


def _make_session(daemon_id="test-daemon"):
    from relay.state import DaemonSession

    ws = mock.AsyncMock(spec=WebSocket)
    return DaemonSession(websocket=ws, daemon_id=daemon_id, token="test-token")


class TestDaemonPairedClients:
    def _import(self):
        import relay.handlers.daemon as m

        return m

    def test_yields_paired_clients(self):
        mod = self._import()
        session = _make_session()
        session.paired_apps = {"c1", "c2"}
        mod.state.app_clients = {"c1": mock.MagicMock(), "c2": mock.MagicMock(), "c3": mock.MagicMock()}
        clients = list(mod._paired_clients(session))
        assert len(clients) == 2

    def test_skips_removed_clients(self):
        mod = self._import()
        session = _make_session()
        session.paired_apps = {"c1"}
        ws = mock.MagicMock()
        mod.state.app_clients = {"c1": ws}
        clients = list(mod._paired_clients(session))
        assert len(clients) == 1


class TestRegisterSession:
    def _import(self):
        import relay.handlers.daemon as m

        return m

    def test_register_with_sessionId(self):
        mod = self._import()
        session = {"sessionId": "s1", "name": "Test", "cwd": "/home", "agentId": "a1"}
        mod._register_session(session)
        mod.state.store.register.assert_called_once_with(
            "s1", client_id="", name="Test", cwd="/home", agent_id="a1", updated_at=None, daemon_id=""
        )

    def test_register_with_id_fallback(self):
        mod = self._import()
        session = {"id": "s1", "title": "Test"}
        mod._register_session(session)
        mod.state.store.register.assert_called_once_with(
            "s1", client_id="", name="Test", cwd="", agent_id="", updated_at=None, daemon_id=""
        )

    def test_register_empty_sid_returns_empty(self):
        mod = self._import()
        result = mod._register_session({})
        assert result == ""

    def test_skips_deleted_session(self):
        mod = self._import()
        mod.state.store.is_deleted.return_value = True
        result = mod._register_session({"sessionId": "deleted-s1"})
        assert result == ""
        mod.state.store.register.assert_not_called()

    def test_register_with_updated_at(self):
        mod = self._import()
        session = {"sessionId": "s1", "name": "Test", "updatedAt": 1234567890}
        mod._register_session(session)
        mod.state.store.register.assert_called_once_with(
            "s1", client_id="", name="Test", cwd="", agent_id="", updated_at=1234567890, daemon_id=""
        )

    def test_register_with_created_at_fallback(self):
        mod = self._import()
        session = {"sessionId": "s1", "name": "Test", "createdAt": 1000000000}
        mod._register_session(session)
        mod.state.store.register.assert_called_once_with(
            "s1", client_id="", name="Test", cwd="", agent_id="", updated_at=1000000000, daemon_id=""
        )

    def test_register_non_numeric_updated_at(self):
        mod = self._import()
        session = {"sessionId": "s1", "name": "Test", "updatedAt": "not-a-number"}
        mod._register_session(session)
        mod.state.store.register.assert_called_once_with(
            "s1", client_id="", name="Test", cwd="", agent_id="", updated_at=None, daemon_id=""
        )

    def test_register_passes_daemon_id(self):
        mod = self._import()
        session = {"sessionId": "s1", "name": "Test"}
        mod._register_session(session, daemon_id="pc-a")
        mod.state.store.register.assert_called_once_with(
            "s1", client_id="", name="Test", cwd="", agent_id="", updated_at=None, daemon_id="pc-a"
        )


class TestSendError:
    def _import(self):
        import relay.handlers.app as m

        return m

    @pytest.mark.asyncio
    async def test_sends_valid_error(self):
        mod = self._import()
        ws = mock.AsyncMock(spec=WebSocket)
        await mod._send_error(ws, 1, -32000, "test error")
        ws.send_text.assert_awaited_once()
        sent = json.loads(ws.send_text.call_args[0][0])
        assert sent["jsonrpc"] == "2.0"
        assert sent["id"] == 1
        assert sent["error"]["code"] == -32000
        assert sent["error"]["message"] == "test error"

    @pytest.mark.asyncio
    async def test_send_with_none_id(self):
        mod = self._import()
        ws = mock.AsyncMock(spec=WebSocket)
        await mod._send_error(ws, None, -1, "msg")
        ws.send_text.assert_awaited_once()


class TestGetDaemonWs:
    def _import(self):
        import relay.handlers.app as m

        return m

    def test_returns_none_when_no_session(self):
        mod = self._import()
        assert mod._get_daemon_ws("unknown") is None

    def test_returns_ws_when_paired(self):
        mod = self._import()
        session = _make_session()
        mod.state.daemons[session.daemon_id] = session
        mod.state.app_to_daemon["client-1"] = session.daemon_id
        ws = mod._get_daemon_ws("client-1")
        assert ws is session.websocket
