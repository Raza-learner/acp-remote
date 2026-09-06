<div align="center">
  <br />
  <img src="https://github.com/Raza-learner/Runmote/raw/main/assets/Runmote.jpeg" alt="Runmote" width="120" />

  <h3>Run any AI coding agent on your PC from your phone.<br>No SSH. No VPN. Just a 8-digit code.</h3>

  <p>
    Start an <code>opencode</code> session from the bus. Resume <code>claude code</code> from bed.<br />
    Fix a bug with <code>codex</code> while waiting for coffee.
    <br /><br />
    <b>No SSH. No VPN. No port forwarding.</b>
  </p>

  <p>
    <a href="https://github.com/Raza-learner/Runmote/actions"><img src="https://img.shields.io/github/actions/workflow/status/Raza-learner/Runmote/ci-python.yml?branch=main&label=build" alt="Build" /></a>
    <a href="https://github.com/Raza-learner/Runmote/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT" /></a>
    <a href="#"><img src="https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter" alt="Flutter" /></a>
    <a href="#"><img src="https://img.shields.io/badge/Python-3.13+-green?logo=python" alt="Python" /></a>
    <a href="#"><img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="iOS Android" /></a>
    <a href="https://play.google.com/store/apps/details?id=dev.runmote.app"><img src="https://img.shields.io/badge/Google%20Play-Get%20it%20on-414141?logo=google-play&logoColor=white" alt="Google Play" /></a>
    <a href="https://github.com/Raza-learner/Runmote/stargazers"><img src="https://img.shields.io/github/stars/Raza-learner/Runmote?style=social" alt="Stars" /></a>
  </p>

  <p>
    Listed on the official
    <a href="https://agentclientprotocol.com/get-started/clients#mobile-clients">ACP clients page</a>
    as a verified mobile ACP client.
  </p>

  <br />
  <img src="https://github.com/Raza-learner/Runmote/raw/main/assets/Runmote-demo.gif" alt="Runmote Demo" width="800" style="max-width:100%" />
  <br />
  <br />
</div>

---

## Install

### Linux / Mac

```bash
curl -fsSL https://runmote.dev/install.sh | bash
```

### Desktop app (Windows)

[Download `Runmote_0.1.0_x64-setup.exe`](https://github.com/Raza-learner/Runmote/releases/download/v0.1.0/Runmote_0.1.0_x64-setup.exe) and run it. The installer registers Runmote in Windows Apps & Features so you can uninstall from Settings. No extra dependencies needed.

> **Windows SmartScreen Warning:** Windows may show a "Windows protected your PC" blue screen when running the installer. This is because the installer is not yet signed by a trusted certificate authority. To proceed, click **More info** → **Run anyway**. This is safe — the app is open source and fully auditable.

That's it. Two minutes. After install:

```bash
runmote start          # daemon starts -> shows pairing code in terminal
runmote code           # re-display pairing code anytime
runmote status         # check if daemon is running
runmote stop           # stop the daemon
runmote --uninstall    # clean removal
```

### Android app

<a href="https://play.google.com/store/apps/details?id=dev.runmote.app"><img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" alt="Get it on Google Play" height="80"/></a>

Or download the APK from [Releases](https://github.com/Raza-learner/Runmote/releases).

---

## Why Runmote?

You *could* SSH tunnel into your PC. If you like typing firewall rules at 11pm.

| | SSH | Runmote |
|---|---|---|
| **Setup time** | 30 minutes of iptables hell | One curl command |
| **Port forwarding** | Yes, on every network | Never |
| **Works on 4G** | Only if you port-forwarded | Yes -- it's just the internet |
| **Mobile app** | Termius + tmux + prayer | Native Flutter app |
| **Session persistence** | tmux resurrection scripts | Built-in, automatic |
| **Keep your sessions** | Hope screen didn't die | Resumes from last message |

---

## Features

- **One command install** -- auto-detects your agents, no config files
- **6-digit pairing** -- open app, type code, connected
- **Persistent sessions** -- switch apps, phone dies, you're right where you left off
- **Streaming responses** -- watch the agent think, run tools, apply diffs live
- **Works on any network** -- home, office, 4G, coffee shop WiFi
- **Cross-platform** -- daemon runs on Linux, macOS, Windows
- **Self-hostable relay** -- everything is open source, run your own server

---

## How it works

```
  ┌─────────────────────────┐               ┌─────────────────────────┐               ┌──────────────────────────┐
  │    1. Install daemon    │               │  2. Open Runmote app    │               │  3. Code from anywhere   │
  │        on your PC       │      -->      │      on your phone      │      -->      │                           │
  │                         │               │                         │               │                           │
  │  curl runmote.dev/      │               │  Enter 6-digit code     │               │  Full chat + toolkit     │
  │  install.sh | bash      │               │  from terminal          │               │  any network, no config  │
  └─────────────────────────┘               └─────────────────────────┘               └──────────────────────────┘
```

---

## Supported agents

The daemon auto-detects what's installed. For each agent, the ACP adapter must be installed separately.

| Agent | Linux | Windows | macOS | ACP adapter / command |
|-------|-------|---------|-------|-----------------------|
| **OpenCode** | ✅ Auto-detect | ❌ Manual config | ✅ Auto-detect | `opencode acp` (native) |
| **Cursor** | ✅ Auto-detect | ✅ Auto-detect | ✅ Auto-detect | `cursor-agent acp` or `agent acp` (bundled with Cursor) |
| **Claude Code** | ✅ Auto-detect | ✅ Auto-detect | ✅ Auto-detect | `claude-agent-acp` or `npx @agentclientprotocol/claude-agent-acp` |
| **Codex** | ✅ Auto-detect | ✅ Auto-detect | ✅ Auto-detect | `codex-acp` or `npx @agentclientprotocol/codex-acp` |
| **GitHub Copilot** | ✅ Auto-detect | ❌ Manual config | ✅ Auto-detect | `github-copilot-acp` or `npx @agentclientprotocol/github-copilot-acp` |
| **Gemini CLI** | ✅ Manual config | ❌ Not tested | ❌ Not tested | Requires `ACP_AGENT_COMMANDS` env var |

Any agent that speaks [ACP](https://agentclientprotocol.com) works. For agents not auto-detected, set `ACP_AGENT_COMMANDS` to a JSON array of agent configs.

---

## Architecture

```
  ┌─────────────┐     WebSocket (WSS)     ┌──────────────┐     WebSocket (WSS)     ┌─────────────────┐
  │ Runmote App │ <---------------------> │ Relay Server │ <---------------------> │ Daemon (your PC)│
  │  (Flutter)  │                         │  (FastAPI)   │                         │    (Python)     │
  └─────────────┘                         └──────────────┘                         └────────┬────────┘
                                                                                             │
                                                                                   stdin / stdout
                                                                                   (JSON-RPC 2.0)
                                                                                             │
                                                                                     ┌───────▼────────┐
                                                                                     │   ACP Agent    │
                                                                                     │  opencode /    │
                                                                                     │  claude / codex│
                                                                                     └────────────────┘
```

No hacks. Phone talks to relay, relay talks to daemon, daemon pipes to agent. All WSS encrypted.

---

## FAQ

<details>
<summary><b>Does my PC need to stay on?</b></summary>

Yes -- the daemon runs as a background process on your machine. It won't use resources when idle.

</details>

<details>
<summary><b>Is this secure?</b></summary>

Every connection is encrypted with WSS (WebSocket over TLS). Session data lives on your machine, not the relay. Self-host the relay if you want full control -- it's a single Docker container.

</details>

<details>
<summary><b>How does pairing work -- can anyone connect?</b></summary>

The daemon generates a fresh 6-digit code each time it starts. Only someone who can see your terminal (or the log file) can get that code. Codes rotate on daemon restart.

</details>

<details>
<summary><b>What agents are supported?</b></summary>

| Agent | Linux | Windows | macOS |
|-------|-------|---------|-------|
| OpenCode | ✅ | ❌ | ✅ |
| Claude Code | ✅ | ✅ | ✅ |
| Codex | ✅ | ✅ | ✅ |
| Cursor | ✅ | ✅ | ✅ |
| GitHub Copilot | ✅ | ❌ | ✅ |
| Gemini CLI | ✅ | ❌ | ❌ |

The daemon auto-detects what's installed. Install the agent CLI and its ACP adapter separately. Any agent that implements [ACP](https://agentclientprotocol.com) works -- for manual setup use `ACP_AGENT_COMMANDS` environment variable.

</details>

<details>
<summary><b>Does this work on iPhone AND Android?</b></summary>

Yes. The app is built with Flutter and compiled natively for both platforms. APK available in releases.

</details>

<details>
<summary><b>Can I run my own relay instead of the public one?</b></summary>

Absolutely. The relay is 100% open source. Build it with Docker:

```bash
docker compose up -d
```

Then set `ACP_RELAY_URL` in your daemon environment to point to your server.

</details>

---

## Project structure

<details>
<summary><b>Expand tree</b></summary>

```
runmote/
├── src/
│   ├── daemon/              # Python daemon (runs on your PC)
│   │   ├── main.py          # core bridge -- relay <-> agent
│   │   └── config.py        # agent auto-detection
│   ├── relay/               # FastAPI relay server
│   │   ├── main.py          # entry point
│   │   ├── pairing.py       # 6-digit codes
│   │   ├── database.py      # SQLite
│   │   ├── session_store.py # persistence
│   │   ├── state.py         # WebSocket state
│   │   ├── discovery.py     # LAN discovery (mDNS)
│   │   └── handlers/
│   │       ├── app.py       # mobile app handler
│   │       └── daemon.py    # daemon handler
│   ├── common/              # shared utils
│   │   └── logger.py
│   └── flutter_app/         # Mobile app
│       └── lib/
│           ├── features/
│           │   ├── pair/        # pairing screen
│           │   ├── agents/      # agent list
│           │   ├── sessions/    # session list
│           │   ├── chat/        # chat + streaming + diffs
│           │   └── settings/    # MCP servers, prefs
│           ├── core/
│           │   ├── providers/   # Riverpod state
│           │   ├── models/      # Freezed models
│           │   ├── database/    # Drift (local SQLite)
│           │   ├── router/      # GoRouter
│           │   ├── services/    # prefs, env
│           │   └── theme/       # colors, spacing
│           └── shared/
│               └── widgets/     # diff viewer, terminal,
│                                # status badges, animated bg
├── scripts/
│   ├── install.sh              # Linux/macOS one-liner
│   ├── install.ps1             # Windows one-liner
│   ├── runmote                 # CLI launcher
│   ├── setup-autostart.sh      # systemd / launchd
│   ├── setup-autostart.ps1     # Windows autostart
│   ├── set-version.sh          # version bumper
│   └── lib/                    # shared helpers
├── tests/                      # Python test suite
├── Dockerfile.relay            # relay Docker image
├── docker-compose.yml
├── pyproject.toml
└── VERSION
```

</details>

---

## Contributing

Pull requests are welcome. For major changes, open an issue first to discuss.

```bash
git clone https://github.com/Raza-learner/Runmote.git
cd Runmote
uv sync                          # install Python deps
cd src/flutter_app && flutter pub get  # install Flutter deps
```

To run the daemon locally:

```bash
uv run src/daemon/main.py
```

---

## Author

<p align="left">
Built by <b>Raza</b>, an independent developer who shipped Runmote from scratch
across three platforms — Python daemon, Flutter mobile app, and a real-time relay server.
If this project saved you time or made your workflow better, consider supporting it on Ko-fi.
</p>

<p align="left">
  <a href="https://ko-fi.com/razalearner"><img src="https://img.shields.io/badge/Ko--fi-ff5e5b?logo=ko-fi&logoColor=white" alt="Ko-fi" /></a>
  <a href="https://github.com/sponsors/Raza-learner"><img src="https://img.shields.io/badge/sponsor-30363D?logo=github-sponsors&logoColor=#EA4AAA" alt="GitHub Sponsor" /></a>
</p>

---

## License

MIT © [Raza](https://github.com/Raza-learner)

<br />

<p align="center">Made with love</p>
