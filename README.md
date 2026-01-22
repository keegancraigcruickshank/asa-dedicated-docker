# ARK: Survival Ascended Dedicated Server (Docker)

A Docker image for running an ARK: Survival Ascended dedicated server. Works on any x86_64 platform (Linux, Windows, macOS) that supports Docker - the container runs the Windows server binary via Wine internally.

## Features

- Runs the Windows ARK: Survival Ascended server on Linux via Wine
- Automatic server installation and updates via SteamCMD
- Full status tracking with JSON status file
- Graceful shutdown handling
- Cluster support for multi-server setups
- Health checks for container orchestration
- Clean, filtered logging

## Requirements

- Docker (with Docker Compose v2 recommended)
- **x86_64 architecture** — Linux, Windows, or macOS (ARM/Apple Silicon is not supported)
- Minimum 16GB RAM recommended
- ~15GB disk space for server files

## Quick Start

### Using Docker Compose (Recommended)

```yaml
services:
  ark-server:
    image: cloudpixelstudios/asa-dedicated-docker:latest
    container_name: ark-server
    restart: unless-stopped
    ports:
      - "7777:7777/udp"
      - "27020:27020/tcp"
    volumes:
      - ark-server-data:/home/steam/ark-server
      - ark-cluster-data:/home/steam/ark-cluster
      - ark-logs:/home/steam/logs
    environment:
      - SERVER_NAME=My ARK Server
      - ADMIN_PASSWORD=changeme
      - MAP=TheIsland_WP
      - MAX_PLAYERS=70

volumes:
  ark-server-data:
  ark-cluster-data:
  ark-logs:
```

```bash
docker compose up -d
```

### Using Docker Run

```bash
docker run -d \
  --name ark-server \
  -p 7777:7777/udp \
  -p 27020:27020/tcp \
  -v ark-server-data:/home/steam/ark-server \
  -v ark-cluster-data:/home/steam/ark-cluster \
  -v ark-logs:/home/steam/logs \
  -e SERVER_NAME="My ARK Server" \
  -e ADMIN_PASSWORD="changeme" \
  -e MAP="TheIsland_WP" \
  cloudpixelstudios/asa-dedicated-docker:latest
```

## Environment Variables

### Server Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_NAME` | `ARK Server` | Server name shown in server browser |
| `SERVER_PASSWORD` | *(empty)* | Password required to join (leave empty for no password) |
| `ADMIN_PASSWORD` | `adminpassword` | Password for admin/RCON access |
| `MAP` | `TheIsland_WP` | Map to load (see [Maps](#maps) below) |
| `MAX_PLAYERS` | `70` | Maximum concurrent players |
| `MODS` | *(empty)* | Comma-separated CurseForge mod IDs |
| `CUSTOM_SERVER_ARGS` | *(empty)* | Additional command line arguments |

### Network Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `GAME_PORT` | `7777` | UDP port for game traffic |
| `RCON_PORT` | `27020` | TCP port for RCON |
| `RCON_ENABLED` | `True` | Enable RCON for remote administration |

### Update Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `AUTO_UPDATE` | `true` | Automatically check for updates on container start |
| `SKIP_VALIDATION` | `false` | Skip file validation during updates (faster but less safe) |

### Cluster Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_ID` | *(empty)* | Cluster identifier for cross-server transfers |
| `CLUSTER_DIR_OVERRIDE` | *(empty)* | Custom cluster directory path |

### Other Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `HEALTHCHECK_ENABLED` | `true` | Enable Docker health checks |
| `LOG_LEVEL` | `INFO` | Log verbosity: `DEBUG`, `INFO`, `WARN`, `ERROR` |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| `7777` | UDP | Game port (client connections) |
| `27020` | TCP | RCON port (remote administration) |

## Volumes / Storage Paths

| Container Path | Description |
|----------------|-------------|
| `/home/steam/ark-server` | Server installation and save data (~15GB) |
| `/home/steam/ark-cluster` | Cluster shared data for cross-server transfers |
| `/home/steam/logs` | Persistent server logs |
| `/home/steam/status` | Status files (JSON) for monitoring |

## Maps

Available maps for the `MAP` environment variable:

| Map | Value |
|-----|-------|
| The Island | `TheIsland_WP` |
| Scorched Earth | `ScorchedEarth_WP` |
| The Center | `TheCenter_WP` |
| Aberration | `Aberration_WP` |
| Extinction | `Extinction_WP` |
| Ragnarok | `Ragnarok_WP` |
| Valguero | `Valguero_WP` |
| Genesis Part 1 | `Genesis_WP` |
| Genesis Part 2 | `Gen2_WP` |
| Crystal Isles | `CrystalIsles_WP` |
| Lost Island | `LostIsland_WP` |
| Fjordur | `Fjordur_WP` |

## Server Status

The container writes a JSON status file to `/home/steam/status/server.status`:

```json
{
    "status": "running",
    "message": "Server fully operational",
    "timestamp": "2026-01-22 05:42:44",
    "pid": "440",
    "server_name": "My ARK Server",
    "map": "TheIsland_WP",
    "game_port": "7777",
    "rcon_port": "27020",
    "uptime_seconds": 234,
    "uptime": "3m 54s",
    "build_id": "21578538",
    "progress": null,
    "download": {
        "current_bytes": null,
        "total_bytes": null
    }
}
```

### Status Values

| Status | Description |
|--------|-------------|
| `initializing` | Container is starting up |
| `updating_steamcmd` | SteamCMD client is updating |
| `downloading` | Server files are being downloaded |
| `validating` | Server files are being validated |
| `installing_mods` | Mods are being installed |
| `starting` | Server process is starting |
| `running` | Server is fully operational and advertising |
| `stopping` | Server is shutting down gracefully |
| `stopped` | Server has stopped |
| `error` | An error occurred |

### Checking Status

```bash
docker exec ark-server cat /home/steam/status/server.status
```

## Cluster Setup

To run multiple servers in a cluster for cross-ARK transfers:

```yaml
services:
  ark-island:
    image: cloudpixelstudios/asa-dedicated-docker:latest
    environment:
      - SERVER_NAME=Island Server
      - MAP=TheIsland_WP
      - CLUSTER_ID=mycluster
      - GAME_PORT=7777
      - RCON_PORT=27020
    ports:
      - "7777:7777/udp"
      - "27020:27020/tcp"
    volumes:
      - ark-island-data:/home/steam/ark-server
      - ark-cluster-shared:/home/steam/ark-cluster

  ark-scorched:
    image: cloudpixelstudios/asa-dedicated-docker:latest
    environment:
      - SERVER_NAME=Scorched Server
      - MAP=ScorchedEarth_WP
      - CLUSTER_ID=mycluster
      - GAME_PORT=7778
      - RCON_PORT=27021
    ports:
      - "7778:7778/udp"
      - "27021:27021/tcp"
    volumes:
      - ark-scorched-data:/home/steam/ark-server
      - ark-cluster-shared:/home/steam/ark-cluster

volumes:
  ark-island-data:
  ark-scorched-data:
  ark-cluster-shared:
```

## Logs

View container logs:

```bash
docker logs -f ark-server
```

View ARK server log file:

```bash
docker exec ark-server tail -f /home/steam/ark-server/ShooterGame/Saved/Logs/ShooterGame.log
```

## Building Locally

```bash
git clone https://github.com/cloudpixelstudios/asa-dedicated-docker-docker.git
cd asa-dedicated-docker
docker build -t asa-dedicated .
```

## Troubleshooting

### Server won't start

1. Check logs: `docker logs ark-server`
2. Ensure you have enough RAM (16GB+ recommended)
3. Verify ports aren't in use: `netstat -tulpn | grep 7777`

### Server not appearing in browser

1. Ensure port 7777/udp is forwarded through your firewall/router
2. Wait for the server to fully start (check for "advertising for join" in logs)
3. Verify the server status: `docker exec ark-server cat /home/steam/status/server.status`

### Slow first start

The first start takes longer because:
1. SteamCMD downloads ~12GB of server files
2. Wine initializes its prefix

Subsequent starts are much faster.

---

## License

MIT — do whatever you want, just don't sue me :)
