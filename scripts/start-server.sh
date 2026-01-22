#!/bin/bash

source /home/steam/scripts/common.sh

ARK_EXE="${ARK_SERVER_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe"

# Suppress Wine debug output
export WINEDEBUG=-all

print_banner "Starting ARK: Survival Ascended Server"

log_info "Configuration:"
log_info "  Map: ${MAP}"
log_info "  Server Name: ${SERVER_NAME}"
log_info "  Game Port: ${GAME_PORT}"
log_info "  RCON Port: ${RCON_PORT}"
log_info "  RCON Enabled: ${RCON_ENABLED}"
log_info "  Max Players: ${MAX_PLAYERS}"
log_info "  Mods: ${MODS:-none}"

# Verify server executable exists
if [ ! -f "${ARK_EXE}" ]; then
    log_error "Server executable not found: ${ARK_EXE}"
    set_status "$STATUS_ERROR" "Server executable not found"
    exit 1
fi

# Build command line arguments
# Note: Port and RCON settings are configured via GameUserSettings.ini (more reliable)
SERVER_ARGS="${MAP}?listen"
SERVER_ARGS="${SERVER_ARGS}?SessionName=${SERVER_NAME}"
SERVER_ARGS="${SERVER_ARGS}?MaxPlayers=${MAX_PLAYERS}"
SERVER_ARGS="${SERVER_ARGS}?RCONEnabled=${RCON_ENABLED}"

if [ -n "$SERVER_PASSWORD" ]; then
    SERVER_ARGS="${SERVER_ARGS}?ServerPassword=${SERVER_PASSWORD}"
    log_info "  Server Password: [set]"
fi

if [ -n "$ADMIN_PASSWORD" ]; then
    SERVER_ARGS="${SERVER_ARGS}?ServerAdminPassword=${ADMIN_PASSWORD}"
    log_info "  Admin Password: [set]"
fi

# Add mod list if specified
if [ -n "$MODS" ]; then
    SERVER_ARGS="${SERVER_ARGS}?-mods=${MODS}"
fi

# Build command line flags
CMD_FLAGS="-NoBattlEye -crossplay -servergamelog -servergamelogincludetribelogs"

# Add cluster settings if configured
if [ -d "${CLUSTER_DIR}" ] && [ -n "$CLUSTER_ID" ]; then
    log_info "  Cluster Mode: Enabled"
    log_info "  Cluster ID: ${CLUSTER_ID}"

    # Use custom cluster dir override if specified, otherwise use Wine path
    if [ -n "$CLUSTER_DIR_OVERRIDE" ]; then
        CMD_FLAGS="${CMD_FLAGS} -ClusterDirOverride=${CLUSTER_DIR_OVERRIDE}"
    else
        CMD_FLAGS="${CMD_FLAGS} -ClusterDirOverride=/home/steam/ark-cluster"
    fi

    CMD_FLAGS="${CMD_FLAGS} -clusterid=${CLUSTER_ID}"
    # Prevent transfers from other clusters/singleplayer for security
    CMD_FLAGS="${CMD_FLAGS} -NoTransferFromFiltering"
fi

# Add any custom server arguments
if [ -n "$CUSTOM_SERVER_ARGS" ]; then
    CMD_FLAGS="${CMD_FLAGS} ${CUSTOM_SERVER_ARGS}"
    log_info "  Custom Args: ${CUSTOM_SERVER_ARGS}"
fi

log_debug "Full server arguments: ${SERVER_ARGS}"
log_debug "Full command flags: ${CMD_FLAGS}"

# Load build ID from manifest for status tracking
MANIFEST_FILE="${ARK_BASE_DIR}/steamapps/appmanifest_${ARK_APP_ID}.acf"
if [ -f "$MANIFEST_FILE" ]; then
    BUILD_ID=$(grep -oP '"buildid"\s+"\K[^"]+' "$MANIFEST_FILE" 2>/dev/null || echo "unknown")
    set_status_meta "build_id" "$BUILD_ID"
    log_info "  Build ID: ${BUILD_ID}"
fi

# Clear download progress from update phase
set_status_meta "progress" ""
set_status_meta "download_current" ""
set_status_meta "download_size" ""

# Set status to starting
set_status "$STATUS_STARTING" "Launching server process"

# Handle shutdown gracefully
shutdown_handler() {
    log_info "Received shutdown signal, stopping server..."
    set_status "$STATUS_STOPPING" "Graceful shutdown initiated"

    # Try to send RCON save command if possible
    if [ "$RCON_ENABLED" = "True" ] && command -v rcon-cli &> /dev/null; then
        log_info "Sending save command via RCON"
        rcon-cli -H localhost -p "${RCON_PORT}" -P "${ADMIN_PASSWORD}" "SaveWorld" 2>/dev/null || true
        sleep 5
    fi

    # Kill the Wine process
    WINE_PID=$(get_pid)
    if [ -n "$WINE_PID" ] && is_process_running "$WINE_PID"; then
        log_info "Sending SIGTERM to server process (PID: ${WINE_PID})"
        kill -TERM "$WINE_PID" 2>/dev/null || true

        # Wait for graceful shutdown
        local timeout=30
        local elapsed=0
        while [ $elapsed -lt $timeout ] && is_process_running "$WINE_PID"; do
            sleep 1
            elapsed=$((elapsed + 1))
        done

        if is_process_running "$WINE_PID"; then
            log_warn "Server did not stop gracefully, forcing termination"
            kill -KILL "$WINE_PID" 2>/dev/null || true
        fi
    fi

    clear_pid
    set_status "$STATUS_STOPPED" "Server stopped"
    log_info "Server stopped"
    exit 0
}

trap shutdown_handler SIGTERM SIGINT

# Start the server using xvfb-run and wine
cd "${ARK_SERVER_DIR}/ShooterGame/Binaries/Win64"

log_info "Launching server with Wine and xvfb"

# ARK log file location (created after server starts)
ARK_LOG_FILE="${ARK_SERVER_DIR}/ShooterGame/Saved/Logs/ShooterGame.log"

# Start server in background and capture PID
# Redirect Wine stdout/stderr - we'll get meaningful logs from the ARK log file instead
xvfb-run --auto-servernum wine "${ARK_EXE}" "${SERVER_ARGS}" ${CMD_FLAGS} 2>&1 | \
    while IFS= read -r line; do
        # Filter out noise - most useful output comes from the ARK log file
        case "$line" in
            # Suppress Wine fixme messages (harmless compatibility notices)
            *"fixme:"*)
                ;;
            # Suppress specific Wine boot errors (expected in container)
            *"err:wineboot"*)
                ;;
            # Suppress Wine preloader messages
            *"wine:"*"preloader"*)
                ;;
            # Suppress ALL GameAnalytics output (noisy SDK with null bytes)
            *"GameAnalytics"*|*"gameanalytics"*)
                ;;
            # Suppress ALSA audio errors (expected in headless container)
            *"ALSA lib"*)
                ;;
            # Suppress lines with null bytes (corrupted GameAnalytics data)
            *$'\x00'*|*"\\u0000"*)
                ;;
            # Log Wine errors (important for debugging crashes)
            *"err:"*)
                log_error "[Wine] $line"
                ;;
            # Log crash/fault messages
            *"fault"*|*"crash"*|*"exception"*|*"segfault"*|*"Segmentation"*)
                log_error "[Wine] $line"
                ;;
            # Log the initial breakpad message
            *"breakpad"*)
                log_info "[ARK] $line"
                ;;
            # Skip empty lines
            "")
                ;;
            # Everything else - log if meaningful
            *)
                # Only log lines that don't look like binary garbage
                if [[ "$line" =~ ^[[:print:][:space:]]+$ ]]; then
                    log_info "[ARK] $line"
                fi
                ;;
        esac
    done &

WINE_PID=$!

# File to signal when server is ready (advertising)
READY_SIGNAL_FILE="${STATUS_DIR}/server.ready"
rm -f "${READY_SIGNAL_FILE}"

# Background task to tail the ARK game log for server messages
(
    # Wait for log file to be created
    timeout=120
    elapsed=0
    while [ ! -f "${ARK_LOG_FILE}" ] && [ $elapsed -lt $timeout ]; do
        sleep 2
        elapsed=$((elapsed + 2))
    done

    if [ -f "${ARK_LOG_FILE}" ]; then
        log_info "Monitoring ARK game log: ${ARK_LOG_FILE}"

        # Check if already advertising (handles race condition)
        if grep -qE "advertising for join" "${ARK_LOG_FILE}" 2>/dev/null; then
            log_info "[ARK] Server already advertising (found in existing log)"
            touch "${READY_SIGNAL_FILE}"
        fi

        tail -n 0 -F "${ARK_LOG_FILE}" 2>/dev/null | while IFS= read -r line; do
            # Skip empty lines
            [ -z "$line" ] && continue

            # Check for server ready (advertising) message
            if [[ "$line" == *"advertising for join"* ]]; then
                log_info "[ARK] $line"
                touch "${READY_SIGNAL_FILE}"
                continue
            fi

            # Determine log level based on content
            case "$line" in
                *"Error:"*|*"Error]"*|*": Error:"*)
                    log_error "[ARK] $line"
                    ;;
                *"Warning:"*|*"Warning]"*|*": Warning:"*)
                    log_warn "[ARK] $line"
                    ;;
                *)
                    # Log all other game log entries
                    log_info "[ARK] $line"
                    ;;
            esac
        done
    else
        log_warn "ARK log file not found after ${timeout}s: ${ARK_LOG_FILE}"
    fi
) &
set_pid "$WINE_PID"

log_info "Server process started with PID: ${WINE_PID}"

# Background task to monitor server readiness
(
    sleep 10  # Give the server time to start

    log_info "Waiting for server to be ready (advertising for join)..."

    timeout=600  # 10 minutes max wait for server to be ready
    elapsed=0

    while [ $elapsed -lt $timeout ]; do
        # Check if Wine/server process is still running
        if ! pgrep -f "ArkAscendedServer" > /dev/null 2>&1; then
            log_error "Server process has died unexpectedly"
            set_status "$STATUS_ERROR" "Server process crashed"
            exit 1
        fi

        # Check if server is advertising (ready signal file exists)
        if [ -f "${READY_SIGNAL_FILE}" ]; then
            log_info "Server is now advertising for join"
            set_status "$STATUS_RUNNING" "Server fully operational"
            exit 0
        fi

        # Log progress every 60 seconds
        if [ $((elapsed % 60)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            log_info "Still waiting for server... (${elapsed}s elapsed)"
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_warn "Server readiness check timed out after ${timeout}s"
    set_status "$STATUS_RUNNING" "Server running (readiness check timed out)"
) &

# Wait for the server process
wait "$WINE_PID"
EXIT_CODE=$?

log_info "Server process exited with code: ${EXIT_CODE}"
clear_pid

if [ $EXIT_CODE -eq 0 ]; then
    set_status "$STATUS_STOPPED" "Server exited normally"
else
    set_status "$STATUS_ERROR" "Server crashed with exit code ${EXIT_CODE}"
fi

exit $EXIT_CODE
