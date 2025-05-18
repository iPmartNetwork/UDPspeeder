#!/bin/bash

set -e

# Colors
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"
NC="\033[0m"

BIN_DIR="/usr/local/bin"
BIN_PATH="${BIN_DIR}/speederv2"

# Detect system architecture
detect_arch() {
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        echo "amd64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        echo "arm64"
    else
        echo -e "${RED}Unsupported architecture: $ARCH${NC}"
        exit 1
    fi
}

# Download the correct binary based on architecture
download_udpspeeder() {
    ARCH=$(detect_arch)
    URL="https://github.com/iPmartNetwork/UDPspeeder/releases/latest/download/speederv2_${ARCH}"
    if [[ -f "$BIN_PATH" ]]; then
        echo -e "${GREEN}UDPspeeder binary already exists.${NC}"
        return
    fi
    echo -e "${YELLOW}Downloading UDPspeeder binary for ${ARCH}...${NC}"
    wget -O "$BIN_PATH" "$URL"
    chmod +x "$BIN_PATH"
    echo -e "${GREEN}UDPspeeder binary installed at $BIN_PATH${NC}"
}

# Create a systemd service for server
create_speederv2_service() {
    local mode=$1
    local tun_port=$2
    local local_port=$3
    local password=$4
    local fec=$5
    local mode_id=$6
    local timeout=$7
    local mtu=$8
    local instance=$9

    SERVICE_FILE="/etc/systemd/system/speederv2_${instance}.service"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=UDPspeeder instance $instance
After=network.target

[Service]
ExecStart=$BIN_PATH $mode -l0.0.0.0:$tun_port -r127.0.0.1:$local_port --mode $mode_id --timeout $timeout --mtu $mtu $fec -k "$password"
Restart=always
User=root
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable speederv2_${instance}.service
    systemctl restart speederv2_${instance}.service
    echo -e "${GREEN}Service speederv2_${instance} started and enabled.${NC}"
}

# Create a systemd service for client
create_speederv2_client_service() {
    local local_port=$1
    local server_ip=$2
    local server_port=$3
    local password=$4
    local fec=$5
    local mode_id=$6
    local timeout=$7
    local mtu=$8
    local instance=$9

    SERVICE_FILE="/etc/systemd/system/speederv2_${instance}.service"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=UDPspeeder client $instance
After=network.target

[Service]
ExecStart=$BIN_PATH -c -l0.0.0.0:$local_port -r${server_ip}:${server_port} --mode $mode_id --timeout $timeout --mtu $mtu $fec -k "$password"
Restart=always
User=root
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable speederv2_${instance}.service
    systemctl restart speederv2_${instance}.service
    echo -e "${GREEN}Client service speederv2_${instance} started and enabled.${NC}"
}

# Remove a systemd service
remove_service() {
    local instance=$1
    systemctl stop speederv2_${instance}.service 2>/dev/null || true
    systemctl disable speederv2_${instance}.service 2>/dev/null || true
    rm -f "/etc/systemd/system/speederv2_${instance}.service"
    systemctl daemon-reload
    echo -e "${YELLOW}Service speederv2_${instance} removed.${NC}"
}

# Service status
status_service() {
    local instance=$1
    systemctl status speederv2_${instance}.service --no-pager
}

# Server setup menu
setup_server() {
    echo -e "${CYAN}--- UDPspeeder Server Setup ---${NC}"
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

# Client setup menu
setup_client() {
    echo -e "${CYAN}--- UDPspeeder Client Setup ---${NC}"
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

    create_speederv2_client_service "$LOCAL_PORT" "$SERVER_IP" "$SERVER_PORT" "$PASSWORD" "$FEC_OPT" "$MODE_ID" "$TIMEOUT" "$MTU" "$INSTANCE"
}

# Main menu
main_menu() {
    download_udpspeeder
    while true; do
        echo -e "${YELLOW}========= UDPspeeder Manager =========${NC}"
        echo "1) Setup Server"
        echo "2) Setup Client"
        echo "3) Remove Service"
        echo "4) Service Status"
        echo "5) Exit"
        read -p "Choose: " CHOICE
        case "$CHOICE" in
            1) setup_server ;;
            2) setup_client ;;
            3) read -p "Instance name to remove: " INS; remove_service "$INS" ;;
            4) read -p "Instance name to check status: " INS; status_service "$INS" ;;
            5) exit 0 ;;
            *) echo -e "${RED}Invalid choice${NC}";;
        esac
    done
}

main_menu
