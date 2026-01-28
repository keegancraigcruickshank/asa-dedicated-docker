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

# STEP 1: Update SteamCMD itself first (prevents exit code 8 errors)
if ! update_steamcmd; then
    log_warn "SteamCMD self-update had issues, but continuing anyway..."
fi

# STEP 2: Now install/update the game
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

# Ensure the directory exists
mkdir -p "${ARK_SERVER_DIR}"

# Remove the appmanifest and SteamCMD download cache to force a fresh update.
# When a new ARK build drops, Steam's CDN revokes old depot manifests. If the
# appmanifest still references the old manifest ID (via InstalledDepots), SteamCMD
# gets "Access Denied" and fails with exit code 8 / state 0x6. The same stale state
# occurs when a container is stopped mid-download. Deleting the manifest forces
# SteamCMD to fetch the latest from scratch — only changed files are re-downloaded.
# Game saves (ShooterGame/Saved/) are not affected.
purge_manifest() {
    local manifest_file="${ARK_SERVER_DIR}/steamapps/appmanifest_${ARK_APP_ID}.acf"
    rm -f "$manifest_file"
    rm -rf "${ARK_SERVER_DIR}/steamapps/downloading/${ARK_APP_ID}"
    rm -rf "${ARK_SERVER_DIR}/steamapps/temp/${ARK_APP_ID}"
}

# On startup, check if a previous run left the manifest in a dirty state.
# StateFlags 0 and 4 are clean (fully installed). Anything else (e.g. 6 =
# UpdateRequired+UpdateStarted) means an update was interrupted.
MANIFEST_FILE="${ARK_SERVER_DIR}/steamapps/appmanifest_${ARK_APP_ID}.acf"
if [ -f "$MANIFEST_FILE" ]; then
    STATE_FLAGS=$(grep -oP '"StateFlags"\s+"\K[^"]+' "$MANIFEST_FILE" 2>/dev/null || echo "0")
    if [ "$STATE_FLAGS" != "0" ] && [ "$STATE_FLAGS" != "4" ]; then
        log_warn "Detected stale manifest (StateFlags=$STATE_FLAGS), purging to force fresh update"
        purge_manifest
    fi
fi

# Function to run SteamCMD app_update with retry logic
run_steamcmd_update() {
    local max_retries=3
    local retry=0
    local CURRENT_PHASE="init"
    local LAST_PROGRESS=""

    while [ $retry -lt $max_retries ]; do
        log_info "Starting SteamCMD app update (attempt $((retry + 1))/$max_retries)..."

        # Run SteamCMD - install directly to ARK_SERVER_DIR (no steamapps/common structure)
        ${STEAMCMD_DIR}/steamcmd.sh \
            +force_install_dir "${ARK_SERVER_DIR}" \
            +login anonymous \
            +app_update ${ARK_APP_ID} ${VALIDATE_FLAG} \
            +quit 2>&1 | while IFS= read -r line; do

                # Parse download progress
                if [[ "$line" =~ "Update state".*"downloading".*"progress:"[[:space:]]*([0-9.]+)[[:space:]]*\(([0-9]+)[[:space:]]*/[[:space:]]*([0-9]+)\) ]]; then
                    progress="${BASH_REMATCH[1]}"
                    current="${BASH_REMATCH[2]}"
                    total="${BASH_REMATCH[3]}"

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

                        set_status_meta "progress" "$progress"
                        set_status_meta "download_current" "$current"
                        set_status_meta "download_size" "$total"

                        if [ $((progress_int % 10)) -eq 0 ] || [ "$progress_int" -ge 99 ]; then
                            total_mb=$((total / 1024 / 1024))
                            current_mb=$((current / 1024 / 1024))
                            log_info "[SteamCMD] Downloading: ${progress}% (${current_mb}MB / ${total_mb}MB)"
                        fi
                    fi

                # Parse validation progress
                elif [[ "$line" =~ "Update state".*"verifying".*"progress:"[[:space:]]*([0-9.]+) ]]; then
                    progress="${BASH_REMATCH[1]}"
                    progress_int=${progress%.*}

                    if [ "$CURRENT_PHASE" != "validating" ]; then
                        CURRENT_PHASE="validating"
                        set_status "$STATUS_VALIDATING" "Validating game files"
                        log_info "[SteamCMD] Validating game files..."
                    fi

                    set_status_meta "progress" "$progress"

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
                elif [[ "$line" == *"Downloading"* ]] && [[ "$line" != *"Downloading update"* ]]; then
                    log_info "[SteamCMD] $line"

                else
                    log_debug "[SteamCMD] $line"
                fi
            done

        local exit_code=${PIPESTATUS[0]}

        if [ $exit_code -eq 0 ]; then
            return 0
        fi

        retry=$((retry + 1))
        if [ $retry -lt $max_retries ]; then
            log_warn "SteamCMD app_update failed (exit code: $exit_code), retrying in 10 seconds... (attempt $retry/$max_retries)"

            # Exit code 8 = content issue (often "Access Denied" for a revoked depot manifest).
            # Purge the manifest so the next attempt fetches the latest from scratch.
            if [ $exit_code -eq 8 ]; then
                log_warn "Exit code 8 detected, purging manifest to fetch latest from Steam CDN"
                purge_manifest
            fi

            sleep 10
        else
            log_error "SteamCMD failed with exit code: ${exit_code} after $max_retries attempts"
            return $exit_code
        fi
    done
}

# Run the update with retries
if ! run_steamcmd_update; then
    set_status "$STATUS_ERROR" "SteamCMD update failed after multiple retries"
    exit 1
fi

# Debug: Show what was installed if binary not found
if [ ! -f "${ARK_SERVER_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe" ]; then
    log_warn "Binary not found at expected path, listing installed content:"
    log_info "Checking: ${ARK_SERVER_DIR}"
    if [ -d "${ARK_SERVER_DIR}" ]; then
        log_info "Contents of ${ARK_SERVER_DIR}:"
        ls -1 "${ARK_SERVER_DIR}" 2>/dev/null | head -20 | while read -r item; do
            log_info "  - $item"
        done
    else
        log_warn "Directory ${ARK_SERVER_DIR} does not exist"
    fi
fi

# Verify installation
if server_installed; then
    log_info "Server installation/update completed successfully"

    # Get installed version info
    MANIFEST_FILE="${ARK_SERVER_DIR}/steamapps/appmanifest_${ARK_APP_ID}.acf"
    if [ -f "$MANIFEST_FILE" ]; then
        BUILD_ID=$(grep -oP '"buildid"\s+"\K[^"]+' "$MANIFEST_FILE" 2>/dev/null || echo "unknown")
        log_info "Installed build ID: ${BUILD_ID}"
        set_status_meta "build_id" "$BUILD_ID"
        echo "{\"success\": true, \"build_id\": \"${BUILD_ID}\", \"timestamp\": \"$(date -Iseconds)\"}" > "${UPDATE_STATUS_FILE}"
    fi

    # Create default config files if they don't exist (first install)
    CONFIG_DIR="${ARK_SERVER_DIR}/ShooterGame/Saved/Config/WindowsServer"
    if [ ! -d "${CONFIG_DIR}" ]; then
        log_info "Creating default configuration files..."
        mkdir -p "${CONFIG_DIR}"

        # Create default GameUserSettings.ini
        cat > "${CONFIG_DIR}/GameUserSettings.ini" <<'EOF'
[ServerSettings]
ServerPassword=
ServerAdminPassword=adminpassword
RCONEnabled=True
RCONPort=27020
Port=7777
MaxPlayers=70
AllowThirdPersonPlayer=True
ShowMapPlayerLocation=True
ServerCrosshair=True
ServerForceNoHUD=False
EnablePvPGamma=True
DisableStructureDecayPvE=False
AllowFlyerCarryPvE=True
DifficultyOffset=0.5
HarvestAmountMultiplier=1.0
XPMultiplier=1.0
TamingSpeedMultiplier=1.0
HarvestHealthMultiplier=1.0
PlayerCharacterWaterDrainMultiplier=1.0
PlayerCharacterFoodDrainMultiplier=1.0
DinoCharacterFoodDrainMultiplier=1.0
PlayerCharacterStaminaDrainMultiplier=1.0
DinoCharacterStaminaDrainMultiplier=1.0
PlayerCharacterHealthRecoveryMultiplier=1.0
DinoCharacterHealthRecoveryMultiplier=1.0
DayCycleSpeedScale=1.0
NightTimeSpeedScale=1.0
DayTimeSpeedScale=1.0
DinoDamageMultiplier=1.0
PlayerDamageMultiplier=1.0
StructureDamageMultiplier=1.0
PlayerResistanceMultiplier=1.0
DinoResistanceMultiplier=1.0
StructureResistanceMultiplier=1.0
PvEStructureDecayPeriodMultiplier=1.0
ResourcesRespawnPeriodMultiplier=1.0
MaxTamedDinos=5000

[SessionSettings]
SessionName=ARK Server

[/Script/Engine.GameSession]
MaxPlayers=70

[MessageOfTheDay]
Message=Welcome to the server!
Duration=20
EOF

        # Create default Game.ini
        cat > "${CONFIG_DIR}/Game.ini" <<'EOF'
[/Script/ShooterGame.ShooterGameMode]
bDisableStructurePlacementCollision=False
bAllowPlatformSaddleMultiFloors=True
bAllowUnlimitedRespecs=True
MaxNumberOfPlayersInTribe=70
MaxAlliancesPerTribe=10
MaxTribesPerAlliance=10
EOF

        log_info "Default configuration files created"
    fi
else
    log_error "Server binary not found after installation"
    set_status "$STATUS_ERROR" "Server installation failed - binary not found"
    exit 1
fi

log_info "Update process completed"
