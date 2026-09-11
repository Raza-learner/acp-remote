#!/usr/bin/env bash

# ==========================================================
# Runmote Installer
# Handles installation, updates and verification
# ==========================================================

[[ -n "${ACP_INSTALLER_LOADED:-}" ]] && return
ACP_INSTALLER_LOADED=1

# ----------------------------------------------------------
# Dependencies
# ----------------------------------------------------------

if [[ -z "${ACP_UI_LOADED:-}" ]]; then
    echo "installer.sh requires ui.sh"
    return 1
fi

# ----------------------------------------------------------
# Installer Variables
# ----------------------------------------------------------

ACP_PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ACP_INSTALL_DIR="${ACP_DIR:-$HOME/.local/share/runmote}"

ACP_BIN_DIR="$HOME/.local/bin"

ACP_SERVICE_NAME="runmoted"

ACP_REMOTE="${ACP_REMOTE:-https://github.com/Raza-learner/Runmote.git}"

ACP_BRANCH="${ACP_BRANCH:-main}"

ACP_IS_LOCAL=0

ACP_OS="$(uname -s)"

ACP_ARCH="$(uname -m)"

# Detect local repository
if [[ -f "$ACP_PROJECT_DIR/pyproject.toml" ]]; then
    ACP_IS_LOCAL=1
fi

# ----------------------------------------------------------
# Helper
# ----------------------------------------------------------

command_exists() {

    command -v "$1" >/dev/null 2>&1

}

# ----------------------------------------------------------
# Install uv
# ----------------------------------------------------------

ensure_uv() {

    section "Python Package Manager"

    if command_exists uv; then

        doctor_ok "uv already installed"

        return 0

    fi

    info "Installing uv..."

    case "$ACP_OS" in

        Linux|Darwin)

            if command_exists curl; then

                curl -LsSf https://astral.sh/uv/install.sh | sh

            elif command_exists wget; then

                wget -qO- https://astral.sh/uv/install.sh | sh

            else

                error "Neither curl nor wget found."

                return 1

            fi

            ;;

        MINGW*|MSYS*|CYGWIN*)

            powershell.exe \
                -NoProfile \
                -ExecutionPolicy Bypass \
                -Command "iex ((New-Object Net.WebClient).DownloadString('https://astral.sh/uv/install.ps1'))"

            ;;

        *)

            error "Unsupported operating system."

            return 1

            ;;

    esac

    # Reload PATH

    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

    if command_exists uv; then

        success "uv installed successfully"

    else

        error "uv installation failed"

        return 1

    fi

}
# ----------------------------------------------------------
# Create Installation Directories
# ----------------------------------------------------------

create_directories() {

    section "Preparing Installation"

    local dirs=(
        "$ACP_INSTALL_DIR"
        "$ACP_BIN_DIR"
        "$ACP_INSTALL_DIR/logs"
        "$ACP_INSTALL_DIR/config"
    )

    for dir in "${dirs[@]}"; do

        if mkdir -p "$dir"; then
            success "Created: $dir"
        else
            error "Failed to create: $dir"
            return 1
        fi

    done

    return 0

}

# ----------------------------------------------------------
# Install Project Files
# ----------------------------------------------------------

install_project_files() {

    section "Installing Runmote Files"

    #
    # Local Repository
    #
    if [[ "$ACP_IS_LOCAL" -eq 1 ]]; then

        info "Using local project"

        if [[ "$ACP_PROJECT_DIR" != "$ACP_INSTALL_DIR" ]]; then

            info "Copying project files..."

            if command -v rsync >/dev/null 2>&1; then
                rsync -a \
                    --delete \
                    --exclude ".git" \
                    --exclude ".venv" \
                    --exclude "__pycache__" \
                    --exclude ".pytest_cache" \
                    --exclude "logs" \
                    "$ACP_PROJECT_DIR/" \
                    "$ACP_INSTALL_DIR/"
            else
                rm -rf "$ACP_INSTALL_DIR"
                cp -rp "$ACP_PROJECT_DIR" "$ACP_INSTALL_DIR"
                rm -rf "$ACP_INSTALL_DIR/.git" \
                       "$ACP_INSTALL_DIR/.venv" \
                       "$ACP_INSTALL_DIR/__pycache__" \
                       "$ACP_INSTALL_DIR/.pytest_cache" \
                       "$ACP_INSTALL_DIR/logs" \
                       2>/dev/null || true
            fi

        fi

    #
    # Clone Repository
    #
    else

        info "Downloading Runmote..."

        if [[ -d "$ACP_INSTALL_DIR/.git" ]]; then

            git -C "$ACP_INSTALL_DIR" fetch origin

            git -C "$ACP_INSTALL_DIR" checkout "$ACP_BRANCH"

            git -C "$ACP_INSTALL_DIR" pull

        else

            rm -rf "$ACP_INSTALL_DIR"

            git clone \
                --depth 1 \
                --branch "$ACP_BRANCH" \
                "$ACP_REMOTE" \
                "$ACP_INSTALL_DIR"

        fi

    fi

    #
    # Verify
    #

    if [[ ! -f "$ACP_INSTALL_DIR/pyproject.toml" ]]; then

        error "Runmote project files missing."

        return 1

    fi

    success "Project files installed"

    return 0

}
# ----------------------------------------------------------
# Install Python Dependencies
# ----------------------------------------------------------

install_dependencies() {

    section "Installing Dependencies"

    cd "$ACP_INSTALL_DIR"

    if [[ ! -f "pyproject.toml" ]]; then
        error "pyproject.toml not found."
        return 1
    fi

    # Find uv — it might not be on PATH because run_task runs in a subshell
    local uv_cmd
    if command_exists uv; then
        uv_cmd="uv"
    elif [[ -x "$HOME/.local/bin/uv" ]]; then
        uv_cmd="$HOME/.local/bin/uv"
    elif [[ -x "$HOME/.cargo/bin/uv" ]]; then
        uv_cmd="$HOME/.cargo/bin/uv"
    else
        error "uv not found. Install it first: curl -LsSf https://astral.sh/uv/install.sh | sh"
        return 1
    fi

    # Don't nuke .venv: uv sync is idempotent and re-resolves staleness
    # itself. Recreating forces a full Python + dependency re-download
    # (minutes on slow links) on every reinstall. Set ACP_RECREATE_VENV=1
    # for a clean rebuild when actually needed.
    if [[ "${ACP_RECREATE_VENV:-0}" == 1 ]]; then
        info "Recreating virtualenv (ACP_RECREATE_VENV=1)..."
        rm -rf .venv
    fi
    # --frozen uses uv.lock: no resolution step, deterministic, faster.
    "$uv_cmd" sync --frozen || "$uv_cmd" sync || return 1
    success "Dependencies installed"

    return 0

}

# ----------------------------------------------------------
# Install Launcher
# ----------------------------------------------------------

install_launcher() {

    section "Installing Launcher"

    mkdir -p "$ACP_BIN_DIR"

    local launcher="$ACP_BIN_DIR/runmote"

    rm -f "$launcher"

    cat > "$launcher" <<EOF
#!/usr/bin/env bash
exec "$ACP_INSTALL_DIR/scripts/runmote" "\$@"
EOF

    chmod +x "$launcher"

    success "Launcher installed"

    if [[ ":$PATH:" != *":$ACP_BIN_DIR:"* ]]; then

        warn "$ACP_BIN_DIR is not in PATH."

        echo
        echo "Add this to your shell profile:"
        echo
        echo "export PATH=\"$ACP_BIN_DIR:\$PATH\""
        echo

    fi

    return 0

}

# ----------------------------------------------------------
# Configure Auto-start
# ----------------------------------------------------------

install_autostart() {

    section "Configuring Auto-start"

    if [[ "$ACP_ENABLE_AUTOSTART" != true ]]; then

        info "Auto-start skipped"

        return 0

    fi

    case "$ACP_OS" in

        Linux)

            bash "$ACP_INSTALL_DIR/scripts/setup-autostart.sh" \
                --install \
                --dir "$ACP_INSTALL_DIR"

            ;;

        Darwin)

            bash "$ACP_INSTALL_DIR/scripts/setup-autostart.sh" \
                --install \
                --dir "$ACP_INSTALL_DIR"

            ;;

        MINGW*|MSYS*|CYGWIN*)

            powershell.exe \
                -NoProfile \
                -ExecutionPolicy Bypass \
                -File "$ACP_INSTALL_DIR/scripts/setup-autostart.ps1" \
                -Install

            ;;

        *)

            warn "Auto-start unsupported"

            return 0

            ;;

    esac

    success "Auto-start configured"

    return 0

}
# ----------------------------------------------------------
# Install Agent Adapters
# ----------------------------------------------------------

install_agents() {

    section "Agent Adapters"

    if [[ "${ACP_ENABLE_AGENTS:-true}" == false ]]; then

        info "Agent adapters skipped"

        return 0

    fi

    case "$ACP_OS" in

        Linux|Darwin)

            bash "$ACP_INSTALL_DIR/scripts/setup-agents.sh" \
                --install

            ;;

        MINGW*|MSYS*|CYGWIN*)

            powershell.exe \
                -NoProfile \
                -ExecutionPolicy Bypass \
                -File "$ACP_INSTALL_DIR/scripts/setup-agents.ps1" \
                -Install

            ;;

        *)

            warn "Agent adapters unsupported"

            return 0

            ;;

    esac

    success "Agent adapters configured"

    return 0

}
# ----------------------------------------------------------
# Start Daemon
# ----------------------------------------------------------

start_daemon() {

    section "Starting Runmote Daemon"

    case "$ACP_OS" in

        Linux|Darwin)

            if command -v runmote >/dev/null 2>&1; then

                timeout 10 runmote start >/dev/null 2>&1 || true

            fi

            ;;

        MINGW*|MSYS*|CYGWIN*)

            powershell.exe \
                -NoProfile \
                -ExecutionPolicy Bypass \
                -Command "runmote start" \
                >/dev/null 2>&1 || true

            ;;

    esac

    sleep 2

    success "Daemon started"

    return 0

}

# ----------------------------------------------------------
# Verify Installation
# ----------------------------------------------------------

verify_installation() {

    section "Verifying Installation"

    local failed=0

    [[ -d "$ACP_INSTALL_DIR" ]] || {
        error "Installation directory missing"
        failed=1
    }

    [[ -f "$ACP_INSTALL_DIR/pyproject.toml" ]] || {
        error "pyproject.toml missing"
        failed=1
    }

    command -v uv >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/uv" ]] || [[ -x "$HOME/.cargo/bin/uv" ]] || {
        error "uv not found"
        failed=1
    }

    command -v runmote >/dev/null 2>&1 || {
        error "Launcher missing"
        failed=1
    }

    if ((failed)); then

        error "Installation verification failed"

        return 1

    fi

    success "Installation verified"

    return 0

}

# ----------------------------------------------------------
# Install Runmote
# ----------------------------------------------------------

install_acp() {

    progress_init 9

    progress_section "Installing Runmote"

    run_task "Installing uv" \
        ensure_uv || return 1

    run_task "Creating directories" \
        create_directories || return 1

    run_task "Installing project files" \
        install_project_files || return 1

    run_task "Installing dependencies" \
        install_dependencies || return 1

    run_task "Installing launcher" \
        install_launcher || return 1

    run_task "Configuring auto-start" \
        install_autostart || return 1

    run_task "Installing agent adapters" \
        install_agents || return 1

    run_task "Starting daemon" \
        start_daemon || return 1

    run_task "Verifying installation" \
        verify_installation || return 1

    progress_finish

    progress_summary

    return 0

}