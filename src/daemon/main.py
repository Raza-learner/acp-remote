import asyncio
import json
import os
import signal
import stat
import sys
import time
from copy import deepcopy
from datetime import datetime, timezone
from io import StringIO
from pathlib import Path

import qrcode

_src = Path(__file__).resolve().parent
if str(_src) not in sys.path:
    sys.path.insert(0, str(_src))

from config import get_agent_configs, DAEMON_ID, DAEMON_TOKEN, RECONNECT_DELAY, RELAY_URL
from websockets.asyncio.client import connect


class DaemonUnpaired(Exception):
    """Raised when the daemon reconnects but has no paired mobile apps
    after having been paired previously — indicates the mobile app unpaired."""


def log(msg: str, *args):
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")[:23]
    if args:
        msg = msg % args
    try:
        print(f"[{ts}] {msg}", flush=True)
    except Exception:
        try:
            print(f"[{ts}] {msg}", file=sys.stderr, flush=True)
        except Exception:
            pass


def _pairing_banner(code: str, public_url: str = "") -> str:
    """Generate a pairing banner with QR code (primary) and text code (secondary).

    If *public_url* is provided, the QR encodes an acp:// URL so the
    mobile app connects via a cloud relay instead of LAN mDNS.
    """
    if len(code) == 6:
        formatted = f"{code[:3]}-{code[3:]}"
    else:
        formatted = f"{code[:4]}-{code[4:]}"

    if public_url:
        qr_data = f"{public_url}/connect?code={code}"
        title = "Scan to connect from anywhere"
    else:
        qr_data = code
        title = "Scan QR Code"

    qr = qrcode.QRCode(border=2, box_size=1)
    qr.add_data(qr_data)
    qr.make(fit=True)
    buf = StringIO()
    qr.print_ascii(out=buf, invert=False)
    qr_lines = buf.getvalue().splitlines()
    qr_width = max(len(l) for l in qr_lines)
    inner_width = max(qr_width, 32)
    lines = [f"╔{'═' * (inner_width + 2)}╗"]
    lines.append(f"║{' ' * (inner_width + 2)}║")
    pad = (inner_width - len(title)) // 2
    lines.append(f"║  {' ' * pad}{title}{' ' * (inner_width - pad - len(title))}  ║")
    lines.append(f"║{' ' * (inner_width + 2)}║")
    for ql in qr_lines:
        side = inner_width - len(ql)
        lines.append(f"║  {ql}{' ' * side}  ║")
    lines.append(f"║{' ' * (inner_width + 2)}║")
    lines.append(f"║  {'─' * inner_width}  ║")
    lines.append(f"║{' ' * (inner_width + 2)}║")
    sub = "Or enter code:"
    pad2 = (inner_width - len(sub)) // 2
    lines.append(f"║  {' ' * pad2}{sub}{' ' * (inner_width - pad2 - len(sub))}  ║")
    code_line = f"   {formatted}   "
    pad3 = (inner_width - len(code_line)) // 2
    lines.append(f"║  {' ' * pad3}{code_line}{' ' * (inner_width - pad3 - len(code_line))}  ║")
    lines.append(f"║{' ' * (inner_width + 2)}║")
    lines.append(f"╚{'═' * (inner_width + 2)}╝")
    if public_url:
        # Only show custom relay links; hide default Runmote cloud relay
        from config import is_cloud_relay
        if not is_cloud_relay(public_url):
            lines.append(f"  Relay: {public_url}")
        else:
            lines.append(f"  Relay: Runmote Relay")
    return "\n" + "\n".join(lines) + "\n"


# Tracks request info (cwd, method) keyed by message id, so
# cwd can be injected into the agent response and method-level
# error handling can be applied (e.g. session/close "Method not found").
_request_info: dict[str, dict] = {}


def _normalize_path(path: str) -> str:
    return path.replace("\\", "/")


def _resolve_path(path: str) -> str:
    """Translate a path into a native OS path. Handles Unix-style paths
    sent from a mobile client when the daemon is running on Windows."""
    if not path:
        return path
    path = os.path.expanduser(path)
    if sys.platform == "win32" and path.startswith("/"):
        home = os.path.expanduser("~")
        # /home/<user>/... -> C:\Users\<current user>\...
        if path.startswith("/home/"):
            rest = "/".join(path.split("/")[3:])
            return os.path.join(home, rest) if rest else home
        # /root -> user home
        if path == "/root" or path.startswith("/root/"):
            return home + path[5:]
        # Bare / on Windows -> user home
        if path == "/":
            return home
    return path


def _is_hidden(entry: os.DirEntry) -> bool:
    if entry.name.startswith("."):
        return True
    if sys.platform == "win32":
        attrs = entry.stat(follow_symlinks=False).st_file_attributes
        if attrs is not None:
            return bool(attrs & stat.FILE_ATTRIBUTE_HIDDEN)
    return False


class AgentProcess:
    def __init__(self, config: dict):
        self.id = config["id"]
        self.name = config.get("name", self.id)
        self.command = config["command"]
        self.proc = None
        self.online = False
        self.version = ""
        self.info = {"name": self.name, "version": ""}
        self.capabilities = {}

    async def start(self):
        if self.proc and self.proc.returncode is None:
            return

        kwargs = {}
        cmd = list(self.command)
        if sys.platform == "win32":
            kwargs["creationflags"] = 0x08000000  # CREATE_NO_WINDOW
            if cmd[0].endswith((".cmd", ".bat")):
                cmd = ["cmd.exe", "/c"] + cmd

        self.proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            **kwargs,
        )
        self.online = True
        init_id = f"daemon_init_{self.id}"
        await self.send(
            {
                "jsonrpc": "2.0",
                "method": "initialize",
                "id": init_id,
                "params": {"protocolVersion": 1},
            }
        )
        # Read the initialize response so agent info/capabilities are
        # captured early and agents that gate every session/* call behind
        # authenticate() (e.g. cursor-agent) can be authenticated now.
        # Without this, cursor rejects session/new with "Authentication
        # required" and the mobile app only sees a generic failure.
        try:
            init_resp = await self._read_response(init_id, timeout=10)
        except Exception as e:
            log("Agent %s: no initialize response (%s)", self.id, e)
            init_resp = None
        if isinstance(init_resp, dict):
            _capture_agent_info(init_resp, self)
            result = init_resp.get("result")
            methods = result.get("authMethods") if isinstance(result, dict) else None
            if isinstance(methods, list) and methods:
                first = methods[0] if isinstance(methods[0], dict) else {}
                method_id = first.get("id")
                if method_id:
                    auth_id = f"daemon_auth_{self.id}"
                    try:
                        await self.send(
                            {
                                "jsonrpc": "2.0",
                                "method": "authenticate",
                                "id": auth_id,
                                "params": {"methodId": method_id},
                            }
                        )
                        auth_resp = await self._read_response(auth_id, timeout=20)
                        if isinstance(auth_resp, dict) and auth_resp.get("error"):
                            log(
                                "Agent %s: authenticate failed: %s",
                                self.id,
                                json.dumps(auth_resp.get("error"))[:200],
                            )
                        else:
                            log("Agent %s: authenticated via %s", self.id, method_id)
                    except Exception as e:
                        log("Agent %s: authenticate failed (%s)", self.id, e)
        await self.send(
            {
                "jsonrpc": "2.0",
                "method": "session/list",
                "id": f"daemon_sessions_{self.id}",
                "params": {},
            }
        )
        log(f"Started {self.id}: {' '.join(self.command)}")

    async def _read_response(self, expect_id: str, timeout: float = 10.0):
        """Read stdout lines until the JSON-RPC response with *expect_id* arrives.

        Other lines (notifications/updates) are logged and dropped — at
        startup only our own handshake responses are expected. Raises
        TimeoutError when the response does not arrive in time.
        """
        if not self.proc or not self.proc.stdout:
            raise RuntimeError(f"agent {self.id} has no stdout")
        loop = asyncio.get_running_loop()
        deadline = loop.time() + timeout
        while True:
            remaining = deadline - loop.time()
            if remaining <= 0:
                raise TimeoutError(f"agent {self.id}: no response to {expect_id}")
            line = await asyncio.wait_for(self.proc.stdout.readline(), timeout=remaining)
            if not line:
                raise RuntimeError(f"agent {self.id} stdout closed")
            raw = line.decode(errors="replace").strip()
            if not raw:
                continue
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                log("%s startup: ignoring non-JSON output: %s", self.id, raw[:120])
                continue
            if data.get("id") == expect_id:
                return data
            log("%s startup: skipping message while waiting for %s", self.id, expect_id)

    async def send(self, message: dict):
        if not self.proc or not self.proc.stdin or self.proc.returncode is not None:
            self.online = False
            raise RuntimeError(f"agent {self.id} is not running")
        self.proc.stdin.write(json.dumps(message).encode() + b"\n")
        await self.proc.stdin.drain()

    async def stop(self):
        if self.proc is None or self.proc.returncode is not None:
            return
        self.proc.terminate()
        try:
            await asyncio.wait_for(self.proc.wait(), timeout=5)
        except asyncio.TimeoutError:
            self.proc.kill()
            await self.proc.wait()
        self.online = False

    def as_json(self) -> dict:
        return {
            "id": self.id,
            "name": self.info.get("name") or self.name,
            "version": self.info.get("version") or self.version,
            "online": self.online,
            "command": self.command,
        }


def _agent_list_message(agents: dict[str, AgentProcess], msg_id=None) -> dict:
    message = {
        "jsonrpc": "2.0",
        "result": {"agents": [agent.as_json() for agent in agents.values()]},
    }
    if msg_id is None:
        message["method"] = "agent/list"
    else:
        message["id"] = msg_id
    return message


def _default_agent_id(agents: dict[str, AgentProcess]) -> str:
    for agent in agents.values():
        if agent.online:
            return agent.id
    return next(iter(agents))


def _extract_agent_id(message: dict, agents: dict[str, AgentProcess]) -> str:
    params = message.get("params")
    agent_id = message.get("agentId")
    if isinstance(params, dict):
        agent_id = params.get("agentId") or agent_id
    if agent_id in agents:
        return agent_id
    return _default_agent_id(agents)


def _message_for_agent(message: dict) -> dict:
    forwarded = deepcopy(message)
    forwarded.pop("agentId", None)
    params = forwarded.get("params")
    if isinstance(params, dict):
        params.pop("agentId", None)
    return forwarded


def _tag_agent_response(message: dict, agent: AgentProcess, session_cwd: str = "", session_method: str = "") -> dict:
    tagged = deepcopy(message)

    # Handle "Method not found" for session/close — some agents
    # (cursor, copilot) don't implement it. Treat as success so the
    # client considers the session closed.
    if session_method == "session/close":
        error = tagged.get("error")
        if isinstance(error, dict) and error.get("code") == -32601:
            return {"jsonrpc": "2.0", "id": message.get("id"), "result": {"ok": True}}

    # Handle session/resume failures — agent either doesn't support
    # resume (-32601) or can't resume this session (-32603, e.g.
    # codex's "no rollout found"). Let the client create a new session.
    if session_method == "session/resume":
        error = tagged.get("error")
        if isinstance(error, dict) and error.get("code") in (-32601, -32603):
            return {
                "jsonrpc": "2.0",
                "id": message.get("id"),
                "result": {
                    "sessionId": "",
                    "agentId": agent.id,
                    "note": "Session resume not available, create a new session",
                },
            }

    # Regular handling
    result = tagged.get("result")
    if isinstance(result, dict):
        result.setdefault("agentId", agent.id)
        if session_cwd and not result.get("cwd"):
            result["cwd"] = session_cwd
        sessions = result.get("sessions")
        if isinstance(sessions, list):
            for session in sessions:
                if isinstance(session, dict):
                    session.setdefault("agentId", agent.id)
                    if session_cwd and not session.get("cwd"):
                        session["cwd"] = session_cwd
    params = tagged.get("params")
    if isinstance(params, dict):
        params.setdefault("agentId", agent.id)
    error = tagged.get("error")
    if isinstance(error, dict):
        data = error.setdefault("data", {})
        if isinstance(data, dict):
            data.setdefault("agentId", agent.id)
    return tagged


def _capture_agent_info(message: dict, agent: AgentProcess):
    result = message.get("result")
    if not isinstance(result, dict):
        return

    info = result.get("agentInfo")
    if isinstance(info, dict):
        # Prefer daemon-configured display name over agent self-reported name
        # so codex shows "Codex" instead of "@agentclientprotocol/codex-acp".
        display_name = agent.name or info.get("name")
        info["name"] = display_name
        agent.info = {
            "name": display_name,
            "version": info.get("version") or "",
        }
        agent.version = agent.info["version"]

    capabilities = result.get("agentCapabilities")
    if isinstance(capabilities, dict):
        agent.capabilities = capabilities


async def _send_json(websocket, message: dict):
    await websocket.send(json.dumps(message))


async def run_daemon():
    agents = {
        config["id"]: AgentProcess(config)
        for config in get_agent_configs()
        if config.get("id") and config.get("command")
    }
    if not agents:
        log("WARNING: no ACP agents detected — daemon will start with no agents")
        log("  Set ACP_AGENT_COMMANDS env var or check agent installation")
        log("  The app will see the daemon as online with no agents")

    while True:
        from config import is_cloud_relay, relay_display_name
        log("Connecting to relay: %s ...", relay_display_name(RELAY_URL) if is_cloud_relay(RELAY_URL) else RELAY_URL)
        ping_tag = id(RELAY_URL) & 0xFFFF  # don't leak address
        try:
            async with connect(
                RELAY_URL,
                additional_headers={"Origin": "https://runmote.dev"},
                ping_interval=30,
                ping_timeout=15,
                close_timeout=10,
            ) as websocket:
                log("Connected to relay!  (socket %#x)", ping_tag)

                identify_id = "daemon_ident"
                await _send_json(
                    websocket,
                    {
                        "jsonrpc": "2.0",
                        "id": identify_id,
                        "method": "daemon/identify",
                        "params": {"daemonId": DAEMON_ID, "token": DAEMON_TOKEN},
                    },
                )

                async for msg in websocket:
                    try:
                        data = json.loads(msg)
                        if data.get("id") == identify_id:
                            result = data.get("result") or {}
                            pairing_code = result.get("pairingCode", "")
                            paired_count = result.get("pairedAppCount", 0)
                            ever_paired = result.get("everPaired", False)
                            public_url = result.get("publicUrl", "")
                            log(
                                "identify response: pairedAppCount=%d everPaired=%s publicUrl=%s",
                                paired_count, ever_paired, public_url or "(none)",
                            )
                            if pairing_code:
                                # Log the raw code (no dash) — consumers grep
                                # this line and re-format it themselves. Logging
                                # a truncated "V4N-SYJ" loses chars and causes
                                # double-dash corruption downstream.
                                log("pairing code: %s", pairing_code)
                                try:
                                    print(_pairing_banner(pairing_code, public_url), flush=True)
                                except Exception:
                                    pass
                                # Write pairing code to temp file so installer can read it
                                try:
                                    temp_path = os.environ.get("TEMP", "/tmp") + "/runmote-pairing-code.txt"
                                    with open(temp_path, "w") as f:
                                        f.write(pairing_code)
                                    os.chmod(temp_path, 0o600)
                                except Exception:
                                    pass
                                # Persist public URL for runmote script
                                if public_url:
                                    config_dir = Path.home() / ".config" / "runmote"
                                    config_dir.mkdir(parents=True, exist_ok=True)
                                    (config_dir / "public_url").write_text(public_url)
                            # If daemon was previously paired (ever_paired) but has
                            # no paired apps now, the mobile app may have unpaired.
                            # Log a warning but keep running so the user can re-pair.
                            if paired_count == 0 and ever_paired:
                                log("No paired mobile apps — daemon was unpaired, waiting for re-pair")
                            break
                        else:
                            log("Ignoring non-identify message during handshake: %s", msg[:200])
                    except json.JSONDecodeError:
                        log("Invalid JSON from relay during identify: %s", msg[:200])

                log("Starting %d agent(s)...", len(agents))
                for agent in agents.values():
                    try:
                        await agent.start()
                    except Exception as e:
                        agent.online = False
                        log("Failed to start %s: %s", agent.id, e)

                await _send_json(websocket, _agent_list_message(agents))

                # NOTE: this closure references `send_queues`, `agent_tasks` and
                # `agents` defined later in this function scope. This works because
                # the closure doesn't execute until the event loop yields.
                async def relay_to_agents():
                    log("relay_to_agents: started")
                    try:
                        async for message in websocket:
                            try:
                                data = json.loads(message)
                            except json.JSONDecodeError:
                                log("Invalid JSON from relay: %s", message[:200])
                                continue

                            method = data.get("method")
                            msg_id = data.get("id")
                            # log("relay msg: method=%s id=%s", method, str(msg_id)[:20])
                            if method == "pairing/complete":
                                from pathlib import Path
                                import tempfile

                                Path(tempfile.gettempdir()).joinpath("acp-paired").write_text("paired")
                                log("pairing/complete received")
                                continue

                            if method == "agent/list":
                                log("agent/list requested by relay")
                                # Re-detect from the live system so installing or
                                # removing an agent shows up on the next request
                                # without a daemon restart. Explicit
                                # ACP_AGENT_COMMANDS is still respected.
                                detected = {
                                    a["id"]: a
                                    for a in get_agent_configs()
                                    if a.get("id") and a.get("command")
                                }
                                for aid in list(agents.keys()):
                                    if aid not in detected:
                                        log("Agent '%s' no longer configured, stopping...", aid)
                                        if aid in agent_tasks:
                                            at = agent_tasks.pop(aid)
                                            for t in [at["relay"], at["stderr"], at.get("watch"), at.get("sender")]:
                                                if t and not t.done():
                                                    t.cancel()
                                        send_queues.pop(aid, None)
                                        await agents[aid].stop()
                                        del agents[aid]
                                    elif not agents[aid].online:
                                        log("Agent '%s' was offline, restarting...", aid)
                                        if aid in agent_tasks:
                                            at = agent_tasks.pop(aid)
                                            for t in [at["relay"], at["stderr"], at.get("watch"), at.get("sender")]:
                                                if t and not t.done():
                                                    t.cancel()
                                        send_queues.pop(aid, None)
                                        await agents[aid].stop()
                                        del agents[aid]
                                for aid, cfg in detected.items():
                                    if aid not in agents:
                                        log("Agent '%s' newly configured, starting...", aid)
                                        agents[aid] = AgentProcess(cfg)
                                        try:
                                            await agents[aid].start()
                                        except Exception as e:
                                            agents[aid].online = False
                                            log("Failed to start new agent %s: %s", aid, e)
                                        if agents[aid].online:
                                            send_q = asyncio.Queue()
                                            send_queues[aid] = send_q
                                            agent_tasks[aid] = {
                                                "agent": agents[aid],
                                                "relay": asyncio.create_task(agent_to_relay(agents[aid])),
                                                "stderr": asyncio.create_task(log_stderr(agents[aid])),
                                                "watch": asyncio.create_task(watch_agent(agents[aid])),
                                                "sender": asyncio.create_task(agent_sender(agents[aid], send_q)),
                                            }
                                await _send_json(websocket, _agent_list_message(agents, msg_id))
                                continue

                            if method == "filesystem/list_drives":
                                try:
                                    drives = []
                                    if sys.platform == "win32":
                                        import string
    
                                        for letter in string.ascii_uppercase:
                                            drive = f"{letter}:\\"
                                            if os.path.exists(drive):
                                                drives.append(
                                                    {
                                                        "name": f"{letter}:",
                                                        "path": _normalize_path(os.path.abspath(drive)),
                                                        "type": "directory",
                                                        "size": 0,
                                                        "isSymlink": False,
                                                    }
                                                )
                                    else:
                                        drives.append(
                                            {
                                                "name": "/",
                                                "path": "/",
                                                "type": "directory",
                                                "size": 0,
                                                "isSymlink": False,
                                            }
                                        )
                                    await _send_json(
                                        websocket,
                                        {
                                            "jsonrpc": "2.0",
                                            "id": msg_id,
                                            "result": {"entries": drives},
                                        },
                                    )
                                except Exception as e:
                                    await _send_json(
                                        websocket,
                                        {
                                            "jsonrpc": "2.0",
                                            "id": msg_id,
                                            "error": {"code": -32000, "message": f"Failed to list drives: {e}"},
                                        },
                                    )
                                continue
    
                            if method == "filesystem/get_home":
                                await _send_json(
                                    websocket,
                                    {
                                        "jsonrpc": "2.0",
                                        "id": msg_id,
                                        "result": {"home": _normalize_path(os.path.expanduser("~"))},
                                    },
                                )
                                continue
    
                            if method == "filesystem/list_directory":
                                params = data.get("params") or {}
                                path = _resolve_path(params.get("path", ".") or ".")
                                show_hidden = params.get("showHidden", False)
                                if not os.path.isdir(path):
                                    # Directory doesn't exist (e.g., stale path from a different machine).
                                    # Fall back to the daemon's home directory so the user can navigate.
                                    path = os.path.expanduser("~")
                                try:
                                    entries = []
                                    for entry in os.scandir(path):
                                        if not show_hidden and _is_hidden(entry):
                                            continue
                                        try:
                                            is_dir = entry.is_dir()
                                            is_file = entry.is_file()
                                            is_symlink = entry.is_symlink()
                                            stat_info = entry.stat(follow_symlinks=False)
                                            entries.append(
                                                {
                                                    "name": entry.name,
                                                    "path": _normalize_path(os.path.abspath(entry.path)),
                                                    "type": "directory" if is_dir else "file" if is_file else "other",
                                                    "size": stat_info.st_size if is_file else 0,
                                                    "isSymlink": is_symlink,
                                                }
                                            )
                                        except OSError:
                                            pass
                                    entries.sort(key=lambda e: (0 if e["type"] == "directory" else 1, e["name"].lower()))
                                    await _send_json(
                                        websocket,
                                        {
                                            "jsonrpc": "2.0",
                                            "id": msg_id,
                                            "result": {
                                                "entries": entries,
                                                "path": _normalize_path(os.path.abspath(path)),
                                            },
                                        },
                                    )
                                except Exception as e:
                                    await _send_json(
                                        websocket,
                                        {
                                            "jsonrpc": "2.0",
                                            "id": msg_id,
                                            "error": {"code": -32000, "message": f"Failed to list directory: {e}"},
                                        },
                                    )
                                continue
    
                            if method == "fs/read_text_file":
                                params = data.get("params") or {}
                                path = _resolve_path(params.get("path", ""))
                                try:
                                    with open(path, "r") as f:
                                        content = f.read()
                                    result = {"content": content}
                                    await _send_json(
                                        websocket,
                                        {
                                            "jsonrpc": "2.0",
                                            "id": msg_id,
                                            "result": result,
                                        },
                                    )
                                except Exception as e:
                                    await _send_json(
                                        websocket,
                                        {
                                            "jsonrpc": "2.0",
                                            "id": msg_id,
                                            "error": {"code": -32000, "message": f"Failed to read file: {e}"},
                                        },
                                    )
                                continue
    
                            if method == "fs/write_text_file":
                                params = data.get("params") or {}
                                path = _resolve_path(params.get("path", ""))
                                content = params.get("content", "")
                                try:
                                    os.makedirs(os.path.dirname(path), exist_ok=True)
                                    with open(path, "w") as f:
                                        f.write(content)
                                    await _send_json(
                                        websocket,
                                        {
                                            "jsonrpc": "2.0",
                                            "id": msg_id,
                                            "result": None,
                                        },
                                    )
                                except Exception as e:
                                    await _send_json(
                                        websocket,
                                        {
                                            "jsonrpc": "2.0",
                                            "id": msg_id,
                                            "error": {"code": -32000, "message": f"Failed to write file: {e}"},
                                        },
                                    )
                                continue
    
                            agent = agents[_extract_agent_id(data, agents)]
                            if not agent.online:
                                await _send_json(
                                    websocket,
                                    {
                                        "jsonrpc": "2.0",
                                        "id": msg_id,
                                        "error": {
                                            "code": -32005,
                                            "message": f"agent {agent.id} is not running",
                                            "data": {"agentId": agent.id},
                                        },
                                    },
                                )
                                continue
    
                            # Save request info (cwd, method) keyed by message id.
                            # Used to inject cwd into the agent response and to
                            # handle method-level errors (e.g. session/close).
                            if msg_id is not None:
                                info: dict[str, str] = {"method": method or ""}
                                if method in ("session/new", "session/resume"):
                                    params = data.get("params") or {}
                                    cwd = _resolve_path(params.get("cwd", ""))
                                    if cwd:
                                        info["cwd"] = cwd
                                _request_info[str(msg_id)] = info
    
                            if agent.id in send_queues:
                                await send_queues[agent.id].put(_message_for_agent(data))
                            else:
                                log("No send queue for %s, dropping message", agent.id)
                                if msg_id is not None:
                                    try:
                                        await _send_json(
                                            websocket,
                                            {
                                                "jsonrpc": "2.0",
                                                "id": msg_id,
                                                "error": {
                                                    "code": -32005,
                                                    "message": f"agent {agent.id} is not running",
                                                    "data": {"agentId": agent.id},
                                                },
                                            },
                                        )
                                    except Exception:
                                        pass
                    except asyncio.CancelledError:
                        log("relay_to_agents: cancelled")
                        raise
                    except Exception as exc:
                        log("relay_to_agents: error %s", exc)
                        import traceback
                        log(traceback.format_exc().rstrip())
                    log("relay_to_agents: websocket loop ended")

                async def agent_to_relay(agent: AgentProcess):
                    if not agent.proc or not agent.proc.stdout:
                        return
                    buf = b""
                    while True:
                        try:
                            chunk = await agent.proc.stdout.read(65536)
                        except Exception:
                            break
                        if not chunk:
                            break
                        buf += chunk
                        while b"\n" in buf:
                            line, buf = buf.split(b"\n", 1)
                            raw = line.decode(errors="replace").strip()
                            if not raw:
                                continue
                            try:
                                data = json.loads(raw)
                                _capture_agent_info(data, agent)
                                req_id = str(data.get("id")) if data.get("id") is not None else ""
                                info = _request_info.pop(req_id, {}) if req_id else {}
                                cwd = info.get("cwd", "")
                                method = info.get("method", "")
                                tagged = _tag_agent_response(data, agent, session_cwd=cwd, session_method=method)
                                await _send_json(websocket, tagged)
                            except json.JSONDecodeError:
                                await websocket.send(raw)
                        if len(buf) > 1_048_576:
                            log("%s stdout: discarding oversized buffer (%d bytes without newline)", agent.id, len(buf))
                            buf = b""
                    if buf:
                        raw = buf.decode(errors="replace").strip()
                        if raw:
                            try:
                                data = json.loads(raw)
                                _capture_agent_info(data, agent)
                                req_id = str(data.get("id")) if data.get("id") is not None else ""
                                info = _request_info.pop(req_id, {}) if req_id else {}
                                cwd = info.get("cwd", "")
                                method = info.get("method", "")
                                tagged = _tag_agent_response(data, agent, session_cwd=cwd, session_method=method)
                                await _send_json(websocket, tagged)
                            except json.JSONDecodeError:
                                await websocket.send(raw)
                    log("%s agent_to_relay: stdout pipe closed", agent.id)

                async def log_stderr(agent: AgentProcess):
                    if not agent.proc or not agent.proc.stderr:
                        return
                    async for line in agent.proc.stderr:
                        if line:
                            try:
                                print(
                                    f"[{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S.%f')[:23]}] {agent.id} stderr: {line.decode().strip()}",
                                    file=sys.stderr,
                                    flush=True,
                                )
                            except Exception:
                                pass
                    log("%s stderr pipe closed", agent.id)

                async def watch_agent(agent: AgentProcess):
                    if not agent.proc:
                        return
                    await agent.proc.wait()
                    agent.online = False
                    log("Agent %s exited with code %s", agent.id, agent.proc.returncode)
                    await _send_json(websocket, _agent_list_message(agents))

                async def agent_sender(agent: AgentProcess, queue: asyncio.Queue):
                    while True:
                        message = await queue.get()
                        try:
                            await agent.send(message)
                        except Exception as exc:
                            agent.online = False
                            log("agent_sender %s: send failed (%s)", agent.id, exc)
                            # Reply to the failed message and anything still
                            # queued so the app gets an error instead of
                            # hanging until its own timeout.
                            pending = [message]
                            while not queue.empty():
                                try:
                                    pending.append(queue.get_nowait())
                                except asyncio.QueueEmpty:
                                    break
                            for msg in pending:
                                mid = msg.get("id")
                                if mid is None:
                                    continue
                                try:
                                    await _send_json(
                                        websocket,
                                        {
                                            "jsonrpc": "2.0",
                                            "id": mid,
                                            "error": {
                                                "code": -32005,
                                                "message": f"agent {agent.id} is not running",
                                                "data": {"agentId": agent.id},
                                            },
                                        },
                                    )
                                except Exception:
                                    pass
                            break

                relay_task = asyncio.create_task(relay_to_agents())
                send_queues: dict[str, asyncio.Queue] = {}
                agent_tasks: dict = {}
                for agent in agents.values():
                    if agent.online:
                        send_q = asyncio.Queue()
                        send_queues[agent.id] = send_q
                        agent_tasks[agent.id] = {
                            "agent": agent,
                            "relay": asyncio.create_task(agent_to_relay(agent)),
                            "stderr": asyncio.create_task(log_stderr(agent)),
                            "watch": asyncio.create_task(watch_agent(agent)),
                            "sender": asyncio.create_task(agent_sender(agent, send_q)),
                        }

                log("Starting %d agent task(s)", len(agent_tasks))
                if agent_tasks:
                    while agent_tasks:
                        # Wait for any agent to fail
                        all_tasks = [relay_task] + [
                            t for at in agent_tasks.values() for t in at.values() if isinstance(t, asyncio.Task)
                        ]
                        done, pending = await asyncio.wait(
                            [t for t in all_tasks if not t.done()],
                            return_when=asyncio.FIRST_COMPLETED,
                        )

                        # Check which agent's watch task completed
                        for aid, at in list(agent_tasks.items()):
                            if at["watch"].done():
                                log("Agent %s stopped, continuing others...", aid)
                                for t in [at["relay"], at["stderr"], at.get("sender")]:
                                    if t and not t.done():
                                        t.cancel()
                                send_queues.pop(aid, None)
                                del agent_tasks[aid]

                        # If relay task stopped or no agents left, stop everything
                        if relay_task.done() or not agent_tasks:
                            if relay_task.done():
                                exc = relay_task.exception()
                                if exc:
                                    log("Relay task exception: %s", exc)
                            break

                # Cancel remaining agent tasks, but keep relay_task alive
                for t in pending:
                    if t is not relay_task:
                        t.cancel()

                # Stay connected after agents exit so pairing/mobile app works
                if not relay_task.done():
                    log("Waiting for relay task to finish...")
                    await relay_task
                    log("Relay task finished")

        except asyncio.CancelledError:
            log("run_daemon: cancelled")
            raise
        except DaemonUnpaired:
            log("run_daemon: daemon was unpaired, raising")
            raise
        except Exception as e:
            log("Connection error: %s", e)
            try:
                import traceback

                log(traceback.format_exc().rstrip())
            except Exception:
                pass

        for agent in agents.values():
            try:
                await agent.stop()
            except Exception:
                pass

        log("Reconnecting in %ss...", RECONNECT_DELAY)
        await asyncio.sleep(RECONNECT_DELAY)


async def main():
    loop = asyncio.get_running_loop()
    stop = asyncio.Event()

    if sys.platform != "win32":
        for sig in (signal.SIGINT, signal.SIGTERM):
            try:
                loop.add_signal_handler(sig, stop.set)
            except NotImplementedError:
                pass

    async def _run_or_stop():
        """Run the daemon — stop on unpaired, signal, or crash."""
        nonlocal stop
        while True:
            try:
                daemon_task = asyncio.create_task(run_daemon())
                # Wait for either daemon exit or stop signal
                done, _ = await asyncio.wait(
                    [daemon_task, asyncio.create_task(stop.wait())],
                    return_when=asyncio.FIRST_COMPLETED,
                )
                if daemon_task in done:
                    exc = daemon_task.exception()
                    if isinstance(exc, DaemonUnpaired):
                        print("Daemon unpaired — shutting down", flush=True)
                        return
                    if isinstance(exc, asyncio.CancelledError):
                        return
                    if exc:
                        raise exc
                    # Daemon exited normally
                    if sys.platform == "win32":
                        log("Daemon exited, restarting in 5s...")
                        await asyncio.sleep(5)
                        continue
                    else:
                        return
                else:
                    # stop was set (SIGINT/SIGTERM)
                    daemon_task.cancel()
                    try:
                        await daemon_task
                    except (asyncio.CancelledError, DaemonUnpaired):
                        pass
                    return
            except DaemonUnpaired:
                print("Daemon unpaired — shutting down", flush=True)
                return

    await _run_or_stop()
    print("\nShutting down...")


if __name__ == "__main__":
    asyncio.run(main())
