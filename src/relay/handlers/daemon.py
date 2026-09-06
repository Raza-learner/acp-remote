import json
from fastapi import APIRouter, WebSocket

try:
    from .. import state
    from ..config import RELAY_TOKEN, PUBLIC_URL
    from ..pairing import generate_pairing_code, cleanup_expired_codes, is_code_expired
except ImportError:
    import state
    from config import RELAY_TOKEN, PUBLIC_URL
    from pairing import generate_pairing_code, cleanup_expired_codes, is_code_expired

router = APIRouter()


def _paired_clients(session: state.DaemonSession):
    """Yield (client_id, websocket) for clients paired with this daemon."""
    for cid, ws in list(state.app_clients.items()):
        if cid in session.paired_apps:
            yield cid, ws


def _register_session(session: dict, daemon_id: str = "") -> str:
    sid = session.get("sessionId") or session.get("id") or ""
    if not sid:
        return ""

    if state.store.is_deleted(sid):
        return ""

    name = session.get("name") or session.get("title") or ""
    cwd = session.get("cwd") or ""
    updated_at = session.get("updatedAt") or session.get("createdAt")
    if not isinstance(updated_at, (int, float)):
        updated_at = None

    state.store.register(
        sid,
        client_id=session.get("clientId", ""),
        name=name,
        cwd=cwd,
        agent_id=session.get("agentId", ""),
        updated_at=updated_at,
        daemon_id=daemon_id or session.get("daemonId", ""),
    )
    return sid


@router.websocket("/daemon")
async def daemon_endpoint(websocket: WebSocket):
    await websocket.accept()
    session: state.DaemonSession | None = None

    try:
        async for message in websocket.iter_text():
            try:
                data = json.loads(message)
                method = data.get("method", "")
                msg_id = data.get("id")

                if method == "$/ping":
                    await websocket.send_text(
                        json.dumps(
                            {
                                "jsonrpc": "2.0",
                                "method": "$/pong",
                            }
                        )
                    )
                    continue

                if method == "daemon/identify":
                    params = data.get("params") or {}
                    daemon_id = params.get("daemonId", "unknown")
                    token = params.get("token") or ""

                    if RELAY_TOKEN is not None and token != RELAY_TOKEN:
                        print(f"  → daemon {daemon_id} token rejected (got '{token[:4]}...')")
                        if msg_id:
                            await websocket.send_text(
                                json.dumps(
                                    {
                                        "jsonrpc": "2.0",
                                        "id": msg_id,
                                        "error": {"code": -32001, "message": "invalid token"},
                                    }
                                )
                            )
                        await websocket.close()
                        return

                    # Remove previous session for same daemon_id (reconnect)
                    old = state.daemons.pop(daemon_id, None)
                    if old:
                        print(f"  → daemon {daemon_id} reconnected, replacing old session")

                    ever_paired = daemon_id in state.daemon_ever_paired

                    # Generate pairing code unique across all daemons
                    all_codes = set(state.code_to_daemon.keys())
                    cleanup_expired_codes(all_codes)
                    for c in list(state.code_to_daemon.keys()):
                        if is_code_expired(c):
                            state.code_to_daemon.pop(c, None)
                    pairing_code = generate_pairing_code(all_codes)
                    state.code_to_daemon[pairing_code] = daemon_id

                    # Derive paired apps from persistent app_to_daemon mapping
                    # (survives daemon disconnects — only cleared when the app
                    # explicitly disconnects).
                    paired_apps = {cid for cid, did in state.app_to_daemon.items() if did == daemon_id}

                    session = state.DaemonSession(
                        websocket=websocket,
                        daemon_id=daemon_id,
                        token=token,
                        public_url=PUBLIC_URL or "",
                        paired_apps=paired_apps,
                    )
                    state.daemons[daemon_id] = session
                    state.store.set_daemon_id(daemon_id)
                    print(
                        f"  → daemon {daemon_id} identified (paired_apps={len(session.paired_apps)}, ever_paired={ever_paired})"
                    )
                    print(f"  → pairing code: {pairing_code[:3]}...-{pairing_code[-3:]}")

                    if msg_id:
                        result = {"pairingCode": pairing_code}
                        if PUBLIC_URL:
                            result["publicUrl"] = PUBLIC_URL
                        result["pairedAppCount"] = len(session.paired_apps)
                        result["everPaired"] = ever_paired
                        await websocket.send_text(
                            json.dumps(
                                {
                                    "jsonrpc": "2.0",
                                    "id": msg_id,
                                    "result": result,
                                }
                            )
                        )

                    forward = {
                        "jsonrpc": "2.0",
                        "method": "daemon/identified",
                        "params": {"daemonId": daemon_id},
                    }
                    for cid, client in _paired_clients(session):
                        try:
                            await client.send_text(json.dumps(forward))
                        except Exception:
                            state.app_clients.pop(cid, None)
                            session.paired_apps.discard(cid)
                    continue

                if method == "pairing/complete":
                    params = data.get("params") or {}
                    client_id = params.get("clientId", "")
                    if session and client_id:
                        session.paired_apps.add(client_id)
                        state.remember_ever_paired(session.daemon_id)
                    continue

                result = data.get("result")
                if isinstance(result, dict):
                    owner = session.daemon_id if session else ""
                    sid = _register_session(result, daemon_id=owner)

                    sessions = result.get("sessions")
                    if isinstance(sessions, list):
                        for s in sessions:
                            if isinstance(s, dict):
                                sid = s.get("sessionId") or s.get("id") or ""
                                if state.store.is_deleted(sid):
                                    continue
                                _register_session(s, daemon_id=owner)

                error = data.get("error")
                if isinstance(error, dict):
                    sid = (error.get("data") or {}).get("sessionId")
                    if sid:
                        state.store.remove(sid)
            except Exception as e:
                print(f"  → failed to process daemon message: {e}")
                continue

            if session is None:
                continue

            # Determine which agent produced this response so we can
            # filter sessions that belong to other agents.
            result_agent_id = ""
            fwd_result = data.get("result")
            if isinstance(fwd_result, dict):
                result_agent_id = fwd_result.get("agentId", "")

            for cid, client in _paired_clients(session):
                try:
                    fwd = data
                    if fwd.get("result") and isinstance(fwd["result"], dict):
                        sess_list = fwd["result"].get("sessions")
                        if isinstance(sess_list, list):
                            filtered = [
                                s
                                for s in sess_list
                                if not isinstance(s, dict)
                                or not state.store.is_deleted(s.get("sessionId") or s.get("id") or "")
                            ]
                            # Cross-agent safety: drop sessions whose
                            # agentId doesn't match the result-level agentId.
                            if result_agent_id:
                                filtered = [
                                    s
                                    for s in filtered
                                    if not isinstance(s, dict) or s.get("agentId") in (None, "", result_agent_id)
                                ]
                            agent_sids = {
                                s.get("sessionId") or s.get("id") or "" for s in filtered if isinstance(s, dict)
                            }
                            if result_agent_id:
                                for cs in state.store.list_sessions(
                                    agent_id=result_agent_id,
                                    daemon_id=session.daemon_id,
                                ):
                                    if cs["sessionId"] not in agent_sids and not state.store.is_deleted(
                                        cs["sessionId"]
                                    ):
                                        filtered.append(cs)
                            for s in filtered:
                                if isinstance(s, dict) and not s.get("cwd"):
                                    sid = s.get("sessionId") or s.get("id") or ""
                                    stored = state.store.get(sid)
                                    if stored and stored.get("cwd"):
                                        s["cwd"] = stored["cwd"]
                            fwd["result"]["sessions"] = filtered
                    await client.send_text(json.dumps(fwd))
                except Exception:
                    state.app_clients.pop(cid, None)
                    session.paired_apps.discard(cid)

    finally:
        if session and state.daemons.get(session.daemon_id) is session:
            del state.daemons[session.daemon_id]
            state.store.clear_daemon_id()
            print(f"Daemon {session.daemon_id} disconnected!")
            forward = {
                "jsonrpc": "2.0",
                "method": "daemon/disconnected",
                "params": {},
            }
            for cid, client in _paired_clients(session):
                try:
                    await client.send_text(json.dumps(forward))
                except Exception:
                    state.app_clients.pop(cid, None)
