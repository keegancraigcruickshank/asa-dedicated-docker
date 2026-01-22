#!/bin/bash

source /home/steam/scripts/common.sh

log_info "Configuring server settings"

CONFIG_DIR="${ARK_SERVER_DIR}/ShooterGame/Saved/Config/WindowsServer"
GAME_INI="${CONFIG_DIR}/GameUserSettings.ini"

# Ensure config directory exists
mkdir -p "${CONFIG_DIR}"

# Create or update GameUserSettings.ini with port settings
if [ ! -f "${GAME_INI}" ]; then
    log_info "Creating new GameUserSettings.ini"
    cat > "${GAME_INI}" <<EOF
[ServerSettings]
Port=${GAME_PORT}
RCONPort=${RCON_PORT}
RCONEnabled=${RCON_ENABLED}

[SessionSettings]
SessionName=${SERVER_NAME}

[/Script/Engine.GameSession]
MaxPlayers=${MAX_PLAYERS}
EOF
else
    log_info "Updating existing GameUserSettings.ini"

    # Remove existing port settings
    sed -i '/^Port=/d; /^RCONPort=/d; /^QueryPort=/d' "${GAME_INI}"

    # Ensure [ServerSettings] section exists
    if ! grep -q "^\[ServerSettings\]" "${GAME_INI}"; then
        echo "[ServerSettings]" >> "${GAME_INI}"
    fi

    # Add port settings under [ServerSettings]
    sed -i "/^\[ServerSettings\]/a Port=${GAME_PORT}\nRCONPort=${RCON_PORT}" "${GAME_INI}"
fi

log_info "Configured ports: Game=${GAME_PORT}, RCON=${RCON_PORT}"

# Set file permissions
chmod 644 "${GAME_INI}"

log_info "Server configuration complete"
