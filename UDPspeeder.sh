#!/bin/bash
# Automatic install & setup for speederv2 (UDPspeeder) from official GitHub release

set -e

RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[93m'
CYAN='\033[96m'
NC='\033[0m'

# Architecture detection
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)   ARCH_TAG="amd64" ;;
    i386|i686) ARCH_TAG="x86" ;;
    aarch64)  ARCH_TAG="arm64" ;;
    armv7l)   ARCH_TAG="arm" ;;
    armv6l)   ARCH_TAG="arm" ;;
    mips)     ARCH_TAG="mips" ;;
    mipsle)   ARCH_TAG="mipsle" ;;
    *)        echo -e "${RED}Unknown architecture: $ARCH${NC}"; exit 1 ;;
esac

echo -e "${CYAN}Fetching latest speederv2 release for $ARCH_TAG...${NC}"

# Fetch latest release JSON and find the right binary
RELEASE_JSON=$(curl -s https://api.github.com/repos/wangyu-/UDPspeeder/releases/latest)
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep "browser_download_url" | grep "$ARCH_TAG" | grep -v ".tar.gz" | cut -d '"' -f 4 | head -n1)

if [ -z "$DOWNLOAD_URL" ]; then
    echo -e "${RED}Could not find a suitable binary for architecture: $ARCH_TAG${NC}"
    exit 1
fi

echo -e "${YELLOW}Downloading: $DOWNLOAD_URL${NC}"
curl -L -o speederv2 "$DOWNLOAD_URL"
chmod +x speederv2
sudo mv speederv2 /usr/local/bin/speederv2

echo -e "${GREEN}speederv2 installed to /usr/local/bin/speederv2!${NC}"

# === Create systemd service ===

echo -e "${CYAN}\n--- Configure speederv2 as a systemd service ---${NC}"
echo "Select run mode:"
echo "1) Server"
echo "2) Client"
read -rp "Your choice (1/2): " MODE

if [[ "$MODE" == "1" ]]; then
    read -rp "Listen port (e.g. 4096): " LISTEN_PORT
    read -rp "Local UDP (WireGuard/OpenVPN) port (e.g. 51820): " WG_PORT
    read -rp "Password: " PASSWD
    read -rp "Mode (0/1, default 1): " SPD_MODE
    SPD_MODE=${SPD_MODE:-1}
    read -rp "Timeout (default 1): " TIMEOUT
    TIMEOUT=${TIMEOUT:-1}
    read -rp "MTU (default 1250): " MTU
    MTU=${MTU:-1250}
    read -rp "Enable FEC? (yes/no, default yes): " FEC
    FEC=${FEC,,}
    [[ "$FEC" == "no" ]] && FEC_OPT="--disable-fec" || FEC_OPT="-f20:10"
    SERVICE_CMD="/usr/local/bin/speederv2 -s -l0.0.0.0:${LISTEN_PORT} --mode ${SPD_MODE} --timeout ${TIMEOUT} --mtu ${MTU} -r127.0.0.1:${WG_PORT} ${FEC_OPT} -k \"${PASSWD}\""
elif [[ "$MODE" == "2" ]]; then
    read -rp "Local UDP port (e.g. 51820): " WG_PORT
    read -rp "Server public IP: " SERVER_IP
    read -rp "Server speederv2 port (e.g. 4096): " SERVER_PORT
    read -rp "Password: " PASSWD
    read -rp "Mode (0/1, default 1): " SPD_MODE
    SPD_MODE=${SPD_MODE:-1}
    read -rp "Timeout (default 1): " TIMEOUT
    TIMEOUT=${TIMEOUT:-1}
    read -rp "MTU (default 1250): " MTU
    MTU=${MTU:-1250}
    read -rp "Enable FEC? (yes/no, default yes): " FEC
    FEC=${FEC,,}
    [[ "$FEC" == "no" ]] && FEC_OPT="--disable-fec" || FEC_OPT="-f20:10"
    SERVICE_CMD="/usr/local/bin/speederv2 -c -l0.0.0.0:${WG_PORT} -r${SERVER_IP}:${SERVER_PORT} --mode ${SPD_MODE} --timeout ${TIMEOUT} --mtu ${MTU} ${FEC_OPT} -k \"${PASSWD}\""
else
    echo -e "${RED}Invalid selection!${NC}"
    exit 2
fi

echo -e "${CYAN}Creating systemd service...${NC}"

sudo tee /etc/systemd/system/speederv2.service > /dev/null <<EOF
[Unit]
Description=UDPspeeder (speederv2) Service
After=network.target

[Service]
ExecStart=${SERVICE_CMD}
Restart=always
User=root
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable speederv2
sudo systemctl restart speederv2

echo -e "${GREEN}speederv2 systemd service is now active!${NC}"
echo -e "${YELLOW}Check status: sudo systemctl status speederv2${NC}"
