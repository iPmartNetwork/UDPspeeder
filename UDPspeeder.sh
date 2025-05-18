#!/bin/bash

set -e

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
NC="\033[0m"

UDPSPEEDER_URL_AMD64="https://github.com/Azumi67/Wangyu_azumi_UDP/releases/download/cores/speederv2_amd64"
UDPSPEEDER_URL_ARM64="https://github.com/Azumi67/Wangyu_azumi_UDP/releases/download/cores/speederv2_arm64"
UDPSPEEDER_BIN="/usr/local/bin/speederv2"

function detect_arch() {
    arch=$(uname -m)
    if [[ $arch == "x86_64" ]]; then
        echo "amd64"
    elif [[ $arch == "aarch64" ]]; then
        echo "arm64"
    else
        echo "Unsupported arch"
        exit 1
    fi
}

function download_udpspeeder() {
    if [ -f "$UDPSPEEDER_BIN" ]; then
        echo -e "${GREEN}UDPSpeeder binary already exists.${NC}"
        return
    fi
    ARCH=$(detect_arch)
    echo -e "${YELLOW}Downloading UDPSpeeder for $ARCH...${NC}"
    if [[ $ARCH == "amd64" ]]; then
        wget -O "$UDPSPEEDER_BIN" "$UDPSPEEDER_URL_AMD64"
    elif [[ $ARCH == "arm64" ]]; then
        wget -O "$UDPSPEEDER_BIN" "$UDPSPEEDER_URL_ARM64"
    fi
    chmod +x "$UDPSPEEDER_BIN"
    echo -e "${GREEN}UDPSpeeder installed at $UDPSPEEDER_BIN${NC}"
}

function create_speederv2_service() {
    local mode=$1
    local tun_port=$2
    local local_port=$3
    local password=$4
    local fec=$5
    local mode_id=$6
    local timeout=$7
    local mtu=$8
    local instance_name=$9

    SERVICE_FILE="/etc/systemd/system/speederv2_${instance_name}.service"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=UDPSpeeder instance $instance_name
After=network.target

[Service]
ExecStart=$UDPSPEEDER_BIN $mode -l0.0.0.0:$tun_port -r127.0.0.1:$local_port --mode $mode_id --timeout $timeout --mtu $mtu $fec -k "$password"
Restart=always
User=root
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable speederv2_${instance_name}.service
    systemctl restart speederv2_${instance_name}.service
    echo -e "${GREEN}speederv2_${instance_name} systemd service created and started.${NC}"
}

function setup_server() {
    echo -e "${YELLOW}--- UDPSpeeder Server Setup ---${NC}"
    read -p "Tunnel Listen Port (e.g. 4096): " TUNNEL_PORT
    read -p "WireGuard/UDP Local Port (e.g. 51820): " LOCAL_PORT
    read -p "Password: " PASSWORD
    read -p "Enable FEC? (yes/no, default yes): " FEC
    FEC=${FEC,,}
    if [[ "$FEC" == "no" ]]; then
        FEC_OPT="--disable-fec"
    else
        FEC_OPT="-f20:10"
    fi
    read -p "Mode (0 or 1, default 1): " MODE_ID
    MODE_ID=${MODE_ID:-1}
    read -p "Timeout (default 1): " TIMEOUT
    TIMEOUT=${TIMEOUT:-1}
    read -p "MTU (default 1250): " MTU
    MTU=${MTU:-1250}
    read -p "Instance name (e.g. wg0): " INSTANCE

    create_speederv2_service "-s" "$TUNNEL_PORT" "$LOCAL_PORT" "$PASSWORD" "$FEC_OPT" "$MODE_ID" "$TIMEOUT" "$MTU" "$INSTANCE"
}

function setup_client() {
    echo -e "${YELLOW}--- UDPSpeeder Client Setup ---${NC}"
    read -p "Local UDP Port to bind (e.g. 51820): " LOCAL_PORT
    read -p "Server Public IP: " SERVER_IP
    read -p "Server Tunnel Listen Port (e.g. 4096): " SERVER_PORT
    read -p "Password: " PASSWORD
    read -p "Enable FEC? (yes/no, default yes): " FEC
    FEC=${FEC,,}
    if [[ "$FEC" == "no" ]]; then
        FEC_OPT="--disable-fec"
    else
        FEC_OPT="-f20:10"
    fi
    read -p "Mode (0 or 1, default 1): " MODE_ID
    MODE_ID=${MODE_ID:-1}
    read -p "Timeout (default 1): " TIMEOUT
    TIMEOUT=${TIMEOUT:-1}
    read -p "MTU (default 1250): " MTU
    MTU=${MTU:-1250}
    read -p "Instance name (e.g. wg0): " INSTANCE

    SERVICE_FILE="/etc/systemd/system/speederv2_${INSTANCE}.service"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=UDPSpeeder Client $INSTANCE
After=network.target

[Service]
ExecStart=$UDPSPEEDER_BIN -c -l0.0.0.0:$LOCAL_PORT -r${SERVER_IP}:${SERVER_PORT} --mode $MODE_ID --timeout $TIMEOUT --mtu $MTU $FEC_OPT -k "$PASSWORD"
Restart=always
User=root
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable speederv2_${INSTANCE}.service
    systemctl restart speederv2_${INSTANCE}.service
    echo -e "${GREEN}speederv2_${INSTANCE} client systemd service created and started.${NC}"
}

function main_menu() {
    download_udpspeeder
    echo -e "${YELLOW}UDPSpeeder Manager${NC}"
    echo "1) Setup Server"
    echo "2) Setup Client"
    echo "3) Exit"
    read -p "Choose: " CHOICE
    case "$CHOICE" in
        1) setup_server ;;
        2) setup_client ;;
        *) exit 0 ;;
    esac
}

main_menu
