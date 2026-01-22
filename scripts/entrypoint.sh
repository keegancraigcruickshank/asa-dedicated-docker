#!/bin/bash
set -e

source /home/steam/scripts/common.sh

print_banner "ARK: Survival Ascended Server Container"

log_info "Container starting up"
log_info "Server Name: ${SERVER_NAME}"
log_info "Map: ${MAP}"
log_info "Game Port: ${GAME_PORT}"
log_info "RCON Port: ${RCON_PORT}"
log_info "Max Players: ${MAX_PLAYERS}"

# Ensure directories exist with correct permissions
mkdir -p "${ARK_BASE_DIR}" "${STATUS_DIR}" "${LOGS_DIR}" "${STEAMCMD_DIR}"

# Ensure SteamCMD is installed (may be empty if volume is fresh)
if [ ! -f "${STEAMCMD_DIR}/steamcmd.sh" ]; then
    log_info "SteamCMD not found, downloading..."
    curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxf - -C "${STEAMCMD_DIR}"
    log_info "SteamCMD installed"
fi

# Initialize uptime tracking
init_start_time
clear_status_meta

# Initialize status
set_status "$STATUS_INITIALIZING" "Container starting"

# Handle graceful shutdown
shutdown_handler() {
    log_info "Received shutdown signal"
    set_status "$STATUS_STOPPING" "Shutdown signal received"

    PID=$(get_pid)
    if [ -n "$PID" ] && is_process_running "$PID"; then
        log_info "Stopping server process (PID: ${PID})"
        kill -TERM "$PID" 2>/dev/null || true

        # Wait for process to exit (with timeout)
        local timeout=60
        local elapsed=0
        while [ $elapsed -lt $timeout ] && is_process_running "$PID"; do
            sleep 1
            elapsed=$((elapsed + 1))
        done

        if is_process_running "$PID"; then
            log_warn "Process did not exit gracefully, forcing kill"
            kill -KILL "$PID" 2>/dev/null || true
        fi
    fi

    clear_pid
    set_status "$STATUS_STOPPED" "Server stopped"
    log_info "Server shutdown complete"
    exit 0
}

trap shutdown_handler SIGTERM SIGINT SIGHUP

# Check if server needs installation or update
if ! server_installed; then
    log_info "Server not installed, initiating installation"
    /home/steam/scripts/update.sh --install
elif [ "$AUTO_UPDATE" = "true" ]; then
    log_info "Checking for server updates"
    /home/steam/scripts/update.sh
else
    log_info "Skipping server update (AUTO_UPDATE=false)"
fi

# Install mods if specified
if [ -n "$MODS" ]; then
    /home/steam/scripts/install-mods.sh
fi

# Configure server settings
/home/steam/scripts/configure.sh

# Start the server
exec /home/steam/scripts/start-server.sh
