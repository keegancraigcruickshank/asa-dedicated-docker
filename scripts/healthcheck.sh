#!/bin/bash
# Health check script for ARK server container
# Returns exit code 0 if healthy, 1 if unhealthy

source /home/steam/scripts/common.sh

# If health checks are disabled, always return healthy
if [ "$HEALTHCHECK_ENABLED" = "false" ]; then
    exit 0
fi

# Read current status
STATUS=$(get_status)

case "$STATUS" in
    "$STATUS_RUNNING")
        # Server claims to be running - verify the process is alive
        PID=$(get_pid)
        if [ -n "$PID" ] && is_process_running "$PID"; then
            # Process is running - check if RCON port is listening (optional deeper check)
            if [ "$RCON_ENABLED" = "True" ]; then
                if nc -z localhost "${RCON_PORT}" 2>/dev/null; then
                    exit 0
                else
                    # RCON not responding but process is running
                    # This might be temporary, so don't fail immediately
                    exit 0
                fi
            fi
            exit 0
        else
            # Process not running but status says running - unhealthy
            exit 1
        fi
        ;;

    "$STATUS_STARTING" | "$STATUS_INITIALIZING" | "$STATUS_UPDATING" | "$STATUS_INSTALLING_MODS")
        # Server is in a transitional state - consider healthy
        # The HEALTHCHECK start-period should cover the initial startup
        exit 0
        ;;

    "$STATUS_STOPPING")
        # Server is stopping - consider healthy (graceful shutdown)
        exit 0
        ;;

    "$STATUS_STOPPED")
        # Server is stopped - this is unhealthy for a running container
        exit 1
        ;;

    "$STATUS_ERROR")
        # Server encountered an error - unhealthy
        exit 1
        ;;

    *)
        # Unknown status - check if status file exists
        if [ ! -f "${STATUS_FILE}" ]; then
            # No status file yet - container just started
            exit 0
        fi
        exit 1
        ;;
esac
