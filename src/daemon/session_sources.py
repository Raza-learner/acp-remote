"""Enumerate agent sessions from on-disk session stores.

Why this exists: some agents advertise ``session/list`` but never answer
it (opencode's ACP silently drops the request), so the phone only ever
shows the sessions it created itself (via relay/app caches). The daemon
runs on the same machine as the agents, so it can read their session
stores directly and merge them with whatever the live agent reports.

Every reader is best-effort and never raises — a missing/corrupt store
simply yields no sessions.

Session dict shape (matches what the relay/app expect)::
    {"sessionId": str, "title": str, "cwd": str,
     "updatedAt": float_seconds, "agentId": str}
"""

import json
import os
import sqlite3
from pathlib import Path

_MAX_SESSIONS_PER_AGENT = 500


def _home() -> Path:
    try:
        return Path.home()
    except Exception:
        return Path(os.path.expanduser("~"))


def _as_seconds(value) -> float:
    """Normalize ms-or-seconds epoch numbers to float seconds."""
    try:
        ts = float(value)
    except (TypeError, ValueError):
        return 0.0
    if ts <= 0:
        return 0.0
    return ts / 1000.0 if ts > 9999999999 else ts


def _opencode_db_path(home: Path) -> Path | None:
    xdg = os.environ.get("XDG_DATA_HOME")
    candidates = []
    if xdg:
        candidates.append(Path(xdg) / "opencode" / "opencode.db")
    candidates.append(home / ".local" / "share" / "opencode" / "opencode.db")
    if os.name == "nt":
        local = os.environ.get("LOCALAPPDATA", "")
        if local:
            candidates.append(Path(local) / "opencode" / "opencode.db")
    for path in candidates:
        try:
            if path.is_file():
                return path
        except Exception:
            continue
    return None


def _opencode_sessions(agent_id: str, home: Path) -> list[dict]:
    db_path = _opencode_db_path(home)
    if db_path is None:
        return []
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=5)
    except Exception:
        return []
    try:
        try:
            rows = conn.execute(
                "SELECT id, title, directory, time_created FROM session"
            ).fetchall()
        except Exception:
            return []
        sessions = []
        for sid, title, directory, created in rows:
            if not sid:
                continue
            sessions.append(
                {
                    "sessionId": str(sid),
                    "title": title or "",
                    "cwd": directory or "",
                    "updatedAt": _as_seconds(created),
                    "agentId": agent_id,
                }
            )
        return sessions
    finally:
        try:
            conn.close()
        except Exception:
            pass


def _cursor_sessions(agent_id: str, home: Path) -> list[dict]:
    base = home / ".cursor" / "acp-sessions"
    try:
        entries = list(base.iterdir())
    except Exception:
        return []
    sessions = []
    for entry in entries:
        try:
            if not entry.is_dir():
                continue
            meta_file = entry / "meta.json"
            cwd = ""
            updated = entry.stat().st_mtime
            if meta_file.is_file():
                try:
                    meta = json.loads(meta_file.read_text()[:4096])
                    if isinstance(meta, dict):
                        cwd = meta.get("cwd") or ""
                    updated = meta_file.stat().st_mtime
                except Exception:
                    pass
            sessions.append(
                {
                    "sessionId": entry.name,
                    "title": "",
                    "cwd": cwd,
                    "updatedAt": float(updated),
                    "agentId": agent_id,
                }
            )
        except Exception:
            continue
    return sessions


def _claude_sessions(agent_id: str, home: Path) -> list[dict]:
    base = home / ".claude" / "projects"
    try:
        project_dirs = [d for d in base.iterdir() if d.is_dir()]
    except Exception:
        return []
    sessions = []
    for project_dir in project_dirs:
        try:
            files = [f for f in project_dir.iterdir() if f.is_file() and f.suffix == ".jsonl"]
        except Exception:
            continue
        for path in files:
            try:
                stem = path.stem
                if not stem:
                    continue
                title = ""
                cwd = ""
                try:
                    with open(path, "r", errors="replace") as f:
                        for i, line in enumerate(f):
                            if i >= 150:
                                break
                            line = line.strip()
                            if not line.startswith("{"):
                                continue
                            try:
                                obj = json.loads(line)
                            except Exception:
                                continue
                            if not isinstance(obj, dict):
                                continue
                            if not cwd and isinstance(obj.get("cwd"), str):
                                cwd = obj["cwd"]
                            if not title and isinstance(obj.get("summary"), str):
                                title = obj["summary"]
                            if title and cwd:
                                break
                except Exception:
                    pass
                sessions.append(
                    {
                        "sessionId": stem,
                        "title": title,
                        "cwd": cwd,
                        "updatedAt": float(path.stat().st_mtime),
                        "agentId": agent_id,
                    }
                )
            except Exception:
                continue
    return sessions


def _codex_sessions(agent_id: str, home: Path) -> list[dict]:
    base = home / ".codex" / "sessions"
    try:
        files = [p for p in base.rglob("*.jsonl") if p.is_file()]
    except Exception:
        return []
    sessions = []
    for path in files:
        try:
            first = ""
            try:
                with open(path, "r", errors="replace") as f:
                    first = f.readline().strip()[:4096]
            except Exception:
                pass
            sid = ""
            cwd = ""
            updated = 0.0
            if first.startswith("{"):
                try:
                    obj = json.loads(first)
                    payload = obj.get("payload") if isinstance(obj, dict) else None
                    if isinstance(payload, dict):
                        sid = str(payload.get("id") or "")
                        cwd = payload.get("cwd") or payload.get("workdir") or ""
                    ts = (obj if isinstance(obj, dict) else {}).get("timestamp")
                    updated = _as_seconds(ts)
                except Exception:
                    pass
            if not updated:
                try:
                    updated = float(path.stat().st_mtime)
                except Exception:
                    pass
            if not sid:
                continue
            sessions.append(
                {
                    "sessionId": sid,
                    "title": "",
                    "cwd": cwd if isinstance(cwd, str) else "",
                    "updatedAt": updated,
                    "agentId": agent_id,
                }
            )
        except Exception:
            continue
    return sessions


_READERS = {
    "opencode": _opencode_sessions,
    "cursor": _cursor_sessions,
    "claude": _claude_sessions,
    "codex": _codex_sessions,
}


def list_local_sessions(agent_id: str, home: Path | None = None) -> list[dict]:
    """Return sessions found on disk for *agent_id*, newest first.

    Unknown agents yield []. Never raises.
    """
    lowered = (agent_id or "").lower()
    reader = None
    for key, fn in _READERS.items():
        if key in lowered:
            reader = fn
            break
    if reader is None:
        return []
    try:
        sessions = reader(agent_id, home or _home())
    except Exception:
        return []
    sessions.sort(key=lambda s: s.get("updatedAt") or 0.0, reverse=True)
    return sessions[:_MAX_SESSIONS_PER_AGENT]


def merge_session_lists(
    live: list[dict] | None, local: list[dict], agent_id: str
) -> list[dict]:
    """Merge live agent sessions with on-disk ones.

    Live entries win on id conflict; empty live title/cwd are backfilled
    from disk. Result sorted newest-first. Never raises.
    """
    merged: dict[str, dict] = {}
    try:
        for s in local or []:
            if isinstance(s, dict):
                sid = s.get("sessionId") or s.get("id") or ""
                if sid:
                    merged[str(sid)] = dict(s)
        for s in live or []:
            if not isinstance(s, dict):
                continue
            sid = s.get("sessionId") or s.get("id") or ""
            if not sid:
                continue
            entry = dict(s)
            entry["sessionId"] = str(sid)
            existing = merged.get(str(sid))
            if existing:
                if not entry.get("title") and existing.get("title"):
                    entry["title"] = existing["title"]
                if not entry.get("cwd") and existing.get("cwd"):
                    entry["cwd"] = existing["cwd"]
            if not entry.get("agentId"):
                entry["agentId"] = agent_id
            merged[str(sid)] = entry
        for entry in merged.values():
            if not entry.get("agentId"):
                entry["agentId"] = agent_id
    except Exception:
        pass
    return sorted(
        merged.values(), key=lambda s: s.get("updatedAt") or 0.0, reverse=True
    )
