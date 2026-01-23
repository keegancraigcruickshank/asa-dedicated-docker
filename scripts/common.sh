#!/bin/bash
# Common functions and utilities for ARK server scripts

# Directories
export STEAMCMD_DIR="/home/steam/steamcmd"
export ARK_BASE_DIR="/home/steam/ark-server"
# Use standard Steam library structure - game installs to steamapps/common/<game name>
export ARK_SERVER_DIR="${ARK_BASE_DIR}/steamapps/common/ARK Survival Ascended Dedicated Server"
export STATUS_DIR="/home/steam/status"
export LOGS_DIR="/home/steam/logs"
export CLUSTER_DIR="/home/steam/ark-cluster"

# ARK App ID for SteamCMD
export ARK_APP_ID="2430930"

# Status file paths
export STATUS_FILE="${STATUS_DIR}/server.status"
export PID_FILE="${STATUS_DIR}/server.pid"
export UPDATE_STATUS_FILE="${STATUS_DIR}/update.status"
export STEAMCMD_UPDATED_FLAG="${STEAMCMD_DIR}/.updated"

# Log levels
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3

# Get numeric log level from string
get_log_level() {
    case "${LOG_LEVEL:-INFO}" in
        DEBUG) echo $LOG_LEVEL_DEBUG ;;
        INFO)  echo $LOG_LEVEL_INFO ;;
        WARN)  echo $LOG_LEVEL_WARN ;;
        ERROR) echo $LOG_LEVEL_ERROR ;;
        *)     echo $LOG_LEVEL_INFO ;;
    esac
}

# Logging functions with timestamps and levels
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local level_num
    local current_level

    case "$level" in
        DEBUG) level_num=$LOG_LEVEL_DEBUG ;;
        INFO)  level_num=$LOG_LEVEL_INFO ;;
        WARN)  level_num=$LOG_LEVEL_WARN ;;
        ERROR) level_num=$LOG_LEVEL_ERROR ;;
        *)     level_num=$LOG_LEVEL_INFO ;;
    esac

    current_level=$(get_log_level)

    if [ $level_num -ge $current_level ]; then
        echo "[${timestamp}] [${level}] ${message}"
    fi
}

log_debug() { log "DEBUG" "$1"; }
log_info()  { log "INFO" "$1"; }
log_warn()  { log "WARN" "$1"; }
log_error() { log "ERROR" "$1"; }

# Server status values
STATUS_INITIALIZING="initializing"
STATUS_UPDATING_STEAMCMD="updating_steamcmd"
STATUS_DOWNLOADING="downloading"
STATUS_VALIDATING="validating"
STATUS_INSTALLING_MODS="installing_mods"
STATUS_STARTING="starting"
STATUS_RUNNING="running"
STATUS_STOPPING="stopping"
STATUS_STOPPED="stopped"
STATUS_ERROR="error"

# Legacy alias for compatibility
STATUS_UPDATING="downloading"

# Status metadata file (for progress, build info, etc.)
export STATUS_META_FILE="${STATUS_DIR}/status.meta"
export START_TIME_FILE="${STATUS_DIR}/start.time"

# Initialize start time tracking
init_start_time() {
    mkdir -p "${STATUS_DIR}"
    date +%s > "${START_TIME_FILE}"
}

# Get uptime in seconds
get_uptime() {
    if [ -f "${START_TIME_FILE}" ]; then
        local start_time=$(cat "${START_TIME_FILE}")
        local now=$(date +%s)
        echo $((now - start_time))
    else
        echo "0"
    fi
}

# Format uptime as human readable
format_uptime() {
    local seconds=$1
    local days=$((seconds / 86400))
    local hours=$(( (seconds % 86400) / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$((seconds % 60))

    if [ $days -gt 0 ]; then
        printf "%dd %dh %dm %ds" $days $hours $minutes $secs
    elif [ $hours -gt 0 ]; then
        printf "%dh %dm %ds" $hours $minutes $secs
    elif [ $minutes -gt 0 ]; then
        printf "%dm %ds" $minutes $secs
    else
        printf "%ds" $secs
    fi
}

# Set status metadata (progress, etc.)
set_status_meta() {
    local key="$1"
    local value="$2"
    mkdir -p "${STATUS_DIR}"

    # Create or update meta file
    if [ ! -f "${STATUS_META_FILE}" ]; then
        echo "{}" > "${STATUS_META_FILE}"
    fi

    # Update the specific key using jq if available, otherwise simple approach
    if command -v jq &> /dev/null; then
        local tmp=$(mktemp)
        jq --arg k "$key" --arg v "$value" '.[$k] = $v' "${STATUS_META_FILE}" > "$tmp" && mv "$tmp" "${STATUS_META_FILE}"
    else
        # Fallback: just store key=value pairs
        echo "${key}=${value}" >> "${STATUS_META_FILE}.tmp"
    fi
}

# Get status metadata
get_status_meta() {
    local key="$1"
    if [ -f "${STATUS_META_FILE}" ] && command -v jq &> /dev/null; then
        jq -r --arg k "$key" '.[$k] // empty' "${STATUS_META_FILE}" 2>/dev/null
    fi
}

# Clear status metadata
clear_status_meta() {
    rm -f "${STATUS_META_FILE}"
}

# Set server status with full metadata
set_status() {
    local status="$1"
    local message="${2:-}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local uptime_secs=$(get_uptime)
    local uptime_formatted=$(format_uptime $uptime_secs)

    mkdir -p "${STATUS_DIR}"

    # Read optional metadata
    local progress=$(get_status_meta "progress")
    local build_id=$(get_status_meta "build_id")
    local download_size=$(get_status_meta "download_size")
    local download_current=$(get_status_meta "download_current")

    # Write status as JSON for easy parsing
    cat > "${STATUS_FILE}" <<EOF
{
    "status": "${status}",
    "message": "${message}",
    "timestamp": "${timestamp}",
    "pid": "$(cat "${PID_FILE}" 2>/dev/null || echo "")",
    "server_name": "${SERVER_NAME}",
    "map": "${MAP}",
    "game_port": "${GAME_PORT}",
    "rcon_port": "${RCON_PORT}",
    "uptime_seconds": ${uptime_secs},
    "uptime": "${uptime_formatted}",
    "build_id": "${build_id:-}",
    "progress": ${progress:-null},
    "download": {
        "current_bytes": ${download_current:-null},
        "total_bytes": ${download_size:-null}
    }
}
EOF
    log_info "Status changed to: ${status}${message:+ - }${message}"
}

# Get current server status
get_status() {
    if [ -f "${STATUS_FILE}" ]; then
        jq -r '.status' "${STATUS_FILE}" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# Set PID file
set_pid() {
    local pid="$1"
    mkdir -p "${STATUS_DIR}"
    echo "$pid" > "${PID_FILE}"
}

# Get PID
get_pid() {
    if [ -f "${PID_FILE}" ]; then
        cat "${PID_FILE}"
    else
        echo ""
    fi
}

# Clear PID file
clear_pid() {
    rm -f "${PID_FILE}"
}

# Check if server binary exists
server_installed() {
    [ -f "${ARK_SERVER_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe" ]
}

# Check if a process is running
is_process_running() {
    local pid="$1"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# Wait for a port to be listening (used to detect RCON ready)
wait_for_port() {
    local port="$1"
    local timeout="${2:-300}"
    local elapsed=0

    log_info "Waiting for port ${port} to be available (timeout: ${timeout}s)"

    while [ $elapsed -lt $timeout ]; do
        if nc -z localhost "$port" 2>/dev/null; then
            log_info "Port ${port} is now available"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_warn "Timeout waiting for port ${port}"
    return 1
}

# Sanitize a string for use in file names
sanitize_name() {
    echo "$1" | tr -cd '[:alnum:]-_' | tr '[:upper:]' '[:lower:]'
}

# Print a banner
print_banner() {
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

# Update SteamCMD itself (separate from game updates)
# This prevents exit code 8 errors during game installation
update_steamcmd() {
    local max_retries=3
    local retry=0

    # Skip if already updated this session
    if [ -f "${STEAMCMD_UPDATED_FLAG}" ]; then
        log_debug "SteamCMD already updated this session"
        return 0
    fi

    log_info "Updating SteamCMD client..."
    set_status "$STATUS_UPDATING_STEAMCMD" "Updating SteamCMD client"

    while [ $retry -lt $max_retries ]; do
        # Run SteamCMD with just +quit to trigger self-update
        ${STEAMCMD_DIR}/steamcmd.sh +quit 2>&1 | while IFS= read -r line; do
            if [[ "$line" == *"Downloading"* ]]; then
                log_info "[SteamCMD] $line"
            elif [[ "$line" == *"Error"* ]] || [[ "$line" == *"FAILED"* ]]; then
                log_error "[SteamCMD] $line"
            else
                log_debug "[SteamCMD] $line"
            fi
        done

        local exit_code=${PIPESTATUS[0]}
        if [ $exit_code -eq 0 ]; then
            log_info "SteamCMD updated successfully"
            touch "${STEAMCMD_UPDATED_FLAG}"
            return 0
        fi

        retry=$((retry + 1))
        if [ $retry -lt $max_retries ]; then
            log_warn "SteamCMD update failed (exit code: $exit_code), retrying in 5 seconds... (attempt $retry/$max_retries)"
            sleep 5
        fi
    done

    log_error "SteamCMD update failed after $max_retries attempts"
    return 1
}
