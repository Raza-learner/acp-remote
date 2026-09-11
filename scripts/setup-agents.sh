#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--install|--remove|--status]

Detect coding agent CLIs (codex, claude) and install/uninstall their
Runmote adapters as global npm packages.

Options:
  --install          Install Runmote adapters for detected CLIs (default)
  --remove           Remove Runmote adapter packages and symlinks
  --status           Show installed Runmote adapter status
  --help             Show this help
EOF
    exit 0
}

MODE="${1:-install}"
case "$MODE" in
    --install) MODE="install"; shift 2>/dev/null || true ;;
    --remove)  MODE="remove";  shift 2>/dev/null || true ;;
    --status)  MODE="status";  shift 2>/dev/null || true ;;
    --help)    usage ;;
    *)         MODE="install" ;;
esac

# NOTE: there is no `runmote` package on the npm registry (npx 404s),
# so don't waste a registry round-trip here — go straight to local install.


detect_os() {
    case "$(uname -s)" in
        Linux)   echo "linux" ;;
        Darwin)  echo "darwin" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)       echo "unknown" ;;
    esac
}

OS="$(detect_os)"

_install_symlinks() {
    mkdir -p "$BIN_DIR"
    if command -v codex-acp &>/dev/null; then
        local src
        src="$(command -v codex-acp)"
        ln -sf "$src" "$BIN_DIR/codex-acp" 2>/dev/null || true
        echo "  codex-acp linked to $BIN_DIR"
    fi
    if command -v claude-agent-acp &>/dev/null; then
        local src
        src="$(command -v claude-agent-acp)"
        ln -sf "$src" "$BIN_DIR/claude-agent-acp" 2>/dev/null || true
        echo "  claude-agent-acp linked to $BIN_DIR"
    fi
    if command -v agy-acp &>/dev/null; then
        local src
        src="$(command -v agy-acp)"
        ln -sf "$src" "$BIN_DIR/agy-acp" 2>/dev/null || true
        echo "  agy-acp linked to $BIN_DIR"
    fi
}

_remove_symlinks() {
    rm -f "$BIN_DIR/codex-acp" "$BIN_DIR/claude-agent-acp" "$BIN_DIR/agy-acp"
}

_ensure_npm() {
    if ! command -v npm &>/dev/null; then
        echo "  npm not found. Install Node.js first: https://nodejs.org"
        return 1
    fi
}

# Fast install check: `npm list -g` spawns the full npm machinery per
# package (seconds each). A directory check under the global root is instant.
_npm_global_root() {
    if [[ -z "${_NPM_ROOT:-}" ]]; then
        _NPM_ROOT="$(npm root -g 2>/dev/null || true)"
    fi
    printf '%s' "$_NPM_ROOT"
}

_is_pkg_installed() {
    local pkg="$1"
    local root
    root="$(_npm_global_root)"
    [[ -n "$root" && -d "$root/$pkg" ]]
}

_install_if_cli_found() {
    local cli="$1"
    local pkg="$2"

    if ! command -v "$cli" &>/dev/null; then
        echo "  '$cli' not found — skipping $pkg"
        return
    fi

    if _is_pkg_installed "$pkg"; then
        echo "  $pkg already installed — skipping"
    else
        echo "  Installing $pkg (for $cli)..."
        npm install -g "$pkg"
    fi
}

_remove_package() {
    local pkg="$1"
    if _is_pkg_installed "$pkg"; then
        echo "  Removing $pkg..."
        npm uninstall -g "$pkg"
    else
        echo "  $pkg not installed — skipping"
    fi
}

install_agents() {
    echo "Installing Runmote agent adapters..."
    echo ""

    _ensure_npm || return 1

    _install_if_cli_found "codex"       "@agentclientprotocol/codex-acp"
    _install_if_cli_found "claude"      "@agentclientprotocol/claude-agent-acp"
    _install_if_cli_found "claude-code" "@agentclientprotocol/claude-agent-acp"
    # agy (Antigravity CLI — gemini replacement) via agy-acp bridge
    if command -v agy &>/dev/null || command -v gemini &>/dev/null; then
        _install_if_cli_found "agy" "agy-acp" 2>/dev/null || \
            echo "  agy not found — skipping agy-acp"
    fi
    # copilot — native ACP mode. The CLI ships a bundled runtime
    # (~100MB+ download), so only install it on explicit opt-in and never
    # by default: it was the single slowest step for users who never use it.
    if command -v copilot &>/dev/null; then
        echo "  copilot already installed — skipping"
    elif [[ "${ACP_ENABLE_COPILOT:-false}" == true ]]; then
        echo "  Installing GitHub Copilot CLI (ACP_ENABLE_COPILOT=true)..."
        npm install -g @github/copilot 2>/dev/null || echo "  Warning: copilot install failed"
    else
        echo "  copilot skipped (set ACP_ENABLE_COPILOT=true to install it)"
    fi

    _install_symlinks

    echo ""
    echo "Done."
}

remove_agents() {
    echo "Removing Runmote agent adapters..."
    echo ""

    _ensure_npm || return 0

    _remove_package "@agentclientprotocol/codex-acp"
    _remove_package "@agentclientprotocol/claude-agent-acp"
    _remove_package "agy-acp"
    _remove_package "@github/copilot"

    _remove_symlinks

    echo ""
    echo "Done."
}

status_agents() {
    echo "Runmote Agent Adapters Status"
    echo ""

    for cli in agy copilot codex claude claude-code; do
        if command -v "$cli" &>/dev/null; then
            echo "  $cli: found ($(command -v "$cli"))"
        else
            echo "  $cli: not found"
        fi
    done

    # Check for Cursor's ACP binary (agent or cursor-agent)
    for bin in agent cursor-agent; do
        if command -v "$bin" &>/dev/null; then
            echo "  Cursor ACP: $(command -v "$bin")"
            break
        fi
    done

    echo ""
    local root
    root="$(_npm_global_root)"
    for pkg in "agy-acp" "@github/copilot" "@agentclientprotocol/codex-acp" "@agentclientprotocol/claude-agent-acp"; do
        if [[ -n "$root" && -d "$root/$pkg" ]]; then
            local ver
            ver="$(node -p "require('$root/$pkg/package.json').version" 2>/dev/null || echo '?')"
            echo "  $pkg: installed (v$ver)"
        else
            echo "  $pkg: not installed"
        fi
    done

    echo ""
    for bin in agy-acp codex-acp claude-agent-acp copilot; do
        if [[ -f "$BIN_DIR/$bin" ]]; then
            echo "  $BIN_DIR/$bin: linked"
        elif command -v "$bin" &>/dev/null; then
            echo "  $(command -v "$bin"): in PATH"
        else
            echo "  $bin: not in PATH"
        fi
    done
}

case "$MODE" in
    install) install_agents ;;
    remove)  remove_agents  ;;
    status)  status_agents  ;;
esac
