#!/bin/bash

source /home/steam/scripts/common.sh

print_banner "ARK Server Update/Install"

# Check for --install flag (used for fresh installations)
INSTALL_MODE=false
if [ "$1" = "--install" ]; then
    INSTALL_MODE=true
    log_info "Running in install mode"
fi

# Clear any previous metadata and set initial state
clear_status_meta

if [ "$INSTALL_MODE" = "true" ]; then
    set_status "$STATUS_DOWNLOADING" "Installing server via SteamCMD"
else
    set_status "$STATUS_DOWNLOADING" "Checking for updates via SteamCMD"
fi

# Build SteamCMD command
VALIDATE_FLAG=""
if [ "$SKIP_VALIDATION" != "true" ]; then
    VALIDATE_FLAG="validate"
    log_info "File validation enabled"
else
    log_info "File validation disabled"
fi

log_info "App ID: ${ARK_APP_ID}"
log_info "Install directory: ${ARK_SERVER_DIR}"

# Track current phase
CURRENT_PHASE="init"
LAST_PROGRESS=""

# Run SteamCMD to install/update
log_info "Starting SteamCMD..."

${STEAMCMD_DIR}/steamcmd.sh \
    +force_install_dir "${ARK_SERVER_DIR}" \
    +login anonymous \
    +app_update ${ARK_APP_ID} ${VALIDATE_FLAG} \
    +quit 2>&1 | while IFS= read -r line; do
        # Detect SteamCMD self-update
        if [[ "$line" == *"Downloading update"* ]] && [[ "$CURRENT_PHASE" != "steamcmd_update" ]]; then
            CURRENT_PHASE="steamcmd_update"
            set_status "$STATUS_UPDATING_STEAMCMD" "Updating SteamCMD"
            log_info "[SteamCMD] Updating SteamCMD client..."
        fi

        # Parse download progress: "Update state (0x61) downloading, progress: 45.31 (5488804173 / 12114105852)"
        if [[ "$line" =~ "Update state".*"downloading".*"progress:"[[:space:]]*([0-9.]+)[[:space:]]*\(([0-9]+)[[:space:]]*/[[:space:]]*([0-9]+)\) ]]; then
            progress="${BASH_REMATCH[1]}"
            current="${BASH_REMATCH[2]}"
            total="${BASH_REMATCH[3]}"

            # Only update if progress changed significantly (reduce log spam)
            progress_int=${progress%.*}
            if [ "$progress_int" != "$LAST_PROGRESS" ]; then
                LAST_PROGRESS="$progress_int"

                if [ "$CURRENT_PHASE" != "downloading" ]; then
                    CURRENT_PHASE="downloading"
                    if [ "$INSTALL_MODE" = "true" ]; then
                        set_status "$STATUS_DOWNLOADING" "Downloading server files"
                    else
                        set_status "$STATUS_DOWNLOADING" "Downloading update"
                    fi
                fi

                # Update progress metadata
                set_status_meta "progress" "$progress"
                set_status_meta "download_current" "$current"
                set_status_meta "download_size" "$total"

                # Log progress at intervals
                if [ $((progress_int % 10)) -eq 0 ] || [ "$progress_int" -ge 99 ]; then
                    total_mb=$((total / 1024 / 1024))
                    current_mb=$((current / 1024 / 1024))
                    log_info "[SteamCMD] Downloading: ${progress}% (${current_mb}MB / ${total_mb}MB)"
                fi
            fi

        # Parse validation progress: "Update state (0x81) verifying update, progress: 5.38 (651424696 / 12114105852)"
        elif [[ "$line" =~ "Update state".*"verifying".*"progress:"[[:space:]]*([0-9.]+) ]]; then
            progress="${BASH_REMATCH[1]}"
            progress_int=${progress%.*}

            if [ "$CURRENT_PHASE" != "validating" ]; then
                CURRENT_PHASE="validating"
                set_status "$STATUS_VALIDATING" "Validating game files"
                log_info "[SteamCMD] Validating game files..."
            fi

            set_status_meta "progress" "$progress"

            # Log validation progress at intervals
            if [ $((progress_int % 25)) -eq 0 ]; then
                log_info "[SteamCMD] Validating: ${progress}%"
            fi

        # Success message
        elif [[ "$line" == *"Success"* ]] || [[ "$line" == *"fully installed"* ]]; then
            set_status_meta "progress" "100"
            log_info "[SteamCMD] $line"

        # Error handling
        elif [[ "$line" == *"Error"* ]] || [[ "$line" == *"FAILED"* ]]; then
            log_error "[SteamCMD] $line"

        # Other important messages
        elif [[ "$line" == *"Downloading"* ]]; then
            log_info "[SteamCMD] $line"

        # Debug everything else
        else
            log_debug "[SteamCMD] $line"
        fi
    done

STEAMCMD_EXIT=${PIPESTATUS[0]}

# Check result
if [ $STEAMCMD_EXIT -ne 0 ]; then
    log_error "SteamCMD failed with exit code: ${STEAMCMD_EXIT}"
    set_status "$STATUS_ERROR" "SteamCMD update failed"
    exit 1
fi

# Verify installation
if server_installed; then
    log_info "Server installation/update completed successfully"

    # Get installed version info (if available)
    MANIFEST_FILE="${ARK_SERVER_DIR}/steamapps/appmanifest_${ARK_APP_ID}.acf"
    if [ -f "$MANIFEST_FILE" ]; then
        BUILD_ID=$(grep -oP '"buildid"\s+"\K[^"]+' "$MANIFEST_FILE" 2>/dev/null || echo "unknown")
        log_info "Installed build ID: ${BUILD_ID}"

        # Store build ID in status metadata for later use
        set_status_meta "build_id" "$BUILD_ID"

        # Write update status
        echo "{\"success\": true, \"build_id\": \"${BUILD_ID}\", \"timestamp\": \"$(date -Iseconds)\"}" > "${UPDATE_STATUS_FILE}"
    fi
else
    log_error "Server binary not found after installation"
    set_status "$STATUS_ERROR" "Server installation failed - binary not found"
    exit 1
fi

log_info "Update process completed"
