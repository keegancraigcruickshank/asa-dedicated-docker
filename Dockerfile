# ARK: Survival Ascended Dedicated Server - Wine Edition
# Must run on x86_64 - ARK server is a Windows x86_64 binary
FROM --platform=linux/amd64 debian:bookworm-slim

LABEL maintainer="Cloud Pixel Studios"
LABEL description="ARK: Survival Ascended Dedicated Server using Wine"
LABEL org.opencontainers.image.source="https://github.com/cloudpixelstudios/asa-dedicated-docker"
LABEL org.opencontainers.image.license="MIT"

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        gnupg2 \
        software-properties-common \
        lib32gcc-s1 \
        libstdc++6:i386 \
        xvfb \
        xauth \
        winbind \
        cabextract \
        unzip \
        tar \
        jq \
        procps \
        locales \
        netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Generate locale
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Install Wine from WineHQ
RUN mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable && \
    rm -rf /var/lib/apt/lists/*

# Create steam user and directories
RUN useradd -m -s /bin/bash -u 1000 steam && \
    mkdir -p /home/steam/steamcmd \
             /home/steam/ark-server \
             /home/steam/ark-cluster \
             /home/steam/.wine \
             /home/steam/status \
             /home/steam/logs && \
    chown -R steam:steam /home/steam

# Install SteamCMD
USER steam
WORKDIR /home/steam/steamcmd
RUN curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf -

# Set up Wine prefix
ENV WINEPREFIX=/home/steam/.wine \
    WINEARCH=win64 \
    WINEDEBUG=-all

# Initialize Wine prefix (this takes a while but speeds up first run)
RUN wineboot --init && \
    wineserver --wait

USER root

# Copy scripts
COPY --chown=steam:steam scripts/ /home/steam/scripts/
RUN chmod +x /home/steam/scripts/*.sh

# Environment variables for server configuration
ENV SERVER_NAME="ARK Server" \
    SERVER_PASSWORD="" \
    ADMIN_PASSWORD="adminpassword" \
    MAP="TheIsland_WP" \
    MAX_PLAYERS=70 \
    GAME_PORT=7777 \
    RCON_PORT=27020 \
    RCON_ENABLED="True" \
    MODS="" \
    CUSTOM_SERVER_ARGS="" \
    AUTO_UPDATE="true" \
    SKIP_VALIDATION="false" \
    CLUSTER_ID="" \
    CLUSTER_DIR_OVERRIDE="" \
    HEALTHCHECK_ENABLED="true" \
    LOG_LEVEL="INFO"

# Expose ports
# 7777/udp - Game port
# 27020/tcp - RCON port
EXPOSE 7777/udp 27020/tcp

# Volumes
# /home/steam/ark-server - Server installation and data
# /home/steam/ark-cluster - Cluster shared data for cross-ark transfers
# /home/steam/logs - Persistent logs
VOLUME ["/home/steam/ark-server", "/home/steam/ark-cluster", "/home/steam/logs"]

# Health check - checks the status file written by our scripts
# This allows the manager to know the true state of the server
HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=3 \
    CMD /home/steam/scripts/healthcheck.sh || exit 1

USER steam
WORKDIR /home/steam

ENTRYPOINT ["/home/steam/scripts/entrypoint.sh"]
