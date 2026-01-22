#!/bin/bash

source /home/steam/scripts/common.sh

if [ -z "$MODS" ]; then
    log_info "No mods specified, skipping mod installation"
    exit 0
fi

print_banner "Installing Mods"

set_status "$STATUS_INSTALLING_MODS" "Installing Steam Workshop mods"

log_info "Mods to install: ${MODS}"

# Parse comma-separated mod list
IFS=',' read -ra MOD_ARRAY <<< "$MODS"

FAILED_MODS=()
INSTALLED_MODS=()

for MOD_ID in "${MOD_ARRAY[@]}"; do
    # Trim whitespace
    MOD_ID=$(echo "$MOD_ID" | tr -d ' ')

    if [ -z "$MOD_ID" ]; then
        continue
    fi

    log_info "Installing mod: ${MOD_ID}"

    # Run SteamCMD to download the mod
    if ${STEAMCMD_DIR}/steamcmd.sh \
        +force_install_dir "${ARK_SERVER_DIR}" \
        +login anonymous \
        +workshop_download_item ${ARK_APP_ID} ${MOD_ID} \
        +quit 2>&1 | while IFS= read -r line; do
            case "$line" in
                *"Success"*|*"Downloaded"*)
                    log_info "[Mod ${MOD_ID}] $line"
                    ;;
                *"Error"*|*"error"*|*"FAILED"*)
                    log_error "[Mod ${MOD_ID}] $line"
                    ;;
                *)
                    log_debug "[Mod ${MOD_ID}] $line"
                    ;;
            esac
        done; then
        INSTALLED_MODS+=("$MOD_ID")
        log_info "Mod ${MOD_ID} installed successfully"
    else
        FAILED_MODS+=("$MOD_ID")
        log_warn "Failed to download mod ${MOD_ID}"
    fi
done

# Summary
log_info "Mod installation complete"
log_info "  Installed: ${#INSTALLED_MODS[@]}"
log_info "  Failed: ${#FAILED_MODS[@]}"

if [ ${#FAILED_MODS[@]} -gt 0 ]; then
    log_warn "Failed mods: ${FAILED_MODS[*]}"
fi

# Don't fail the entire startup for mod failures
exit 0
