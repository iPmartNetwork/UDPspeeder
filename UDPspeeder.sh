#!/bin/bash
# Pro UDPspeeder installer & manager (multi-instance, advanced menu)
set -e

# Colors
RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[93m'
CYAN='\033[96m'
NC='\033[0m'

# Arch detection
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)   BIN_NAME="speederv2_amd64" ;;
    i386|i686) BIN_NAME="speederv2_x86" ;;
    aarch64)  BIN_NAME="speederv2_arm64" ;;
    armv7l|armv6l) BIN_NAME="speederv2_arm" ;;
    mips)     BIN_NAME="speederv2_mips" ;;
    mipsle)   BIN_NAME="speederv2_mipsle" ;;
    *) echo -e "${RED}Unknown architecture: $ARCH${NC}"; exit 1 ;;
esac

UDPSPEEDER_BIN="/usr/local/bin/speederv2"
REPO="iPmartNetwork/UDPspeeder"

# Root check
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Please run this script as root.${NC}"; exit 1
fi

# Dependency check/install
for pkg in curl tar grep awk lsof systemctl; do
    if ! command -v $pkg &>/dev/null; then
        echo -e "${YELLOW}Installing missing dependency: $pkg${NC}"
        if command -v apt &>/dev/null; then
            apt update -y && apt install -y $pkg
        elif command -v yum &>/dev/null; then
            yum install -y $pkg
        else
            echo -e "${RED}Supported package manager not found (apt or yum).${NC}"
            exit 1
        fi
    fi
done

# Download & install speederv2
install_udpspeeder() {
    echo -e "${CYAN}Fetching latest UDPspeeder release...${NC}"
    RELEASE_JSON=$(curl -s https://api.github.com/repos/${REPO}/releases/latest)
    ASSET_URL=$(echo "$RELEASE_JSON" | grep "browser_download_url" | grep "speederv2_binaries.tar.gz" | cut -d '"' -f 4)
    if [ -z "$ASSET_URL" ]; then
        echo -e "${RED}Could not find speederv2_binaries.tar.gz in the latest release!${NC}"
        exit 1
    fi

    WORKDIR=$(mktemp -d)
    cd "$WORKDIR"
    echo -e "${YELLOW}Downloading binaries: $ASSET_URL${NC}"
    curl -L -o speederv2_binaries.tar.gz "$ASSET_URL"
    tar -xzf speederv2_binaries.tar.gz
    if [ ! -f "$BIN_NAME" ]; then
        echo -e "${RED}Binary for your architecture ($BIN_NAME) not found!${NC}"; exit 1
    fi
    chmod +x "$BIN_NAME"
    mv "$BIN_NAME" "$UDPSPEEDER_BIN"
    cd / && rm -rf "$WORKDIR"
    echo -e "${GREEN}speederv2 installed to $UDPSPEEDER_BIN${NC}"
}

# Port in use?
check_port() {
    lsof -i UDP:"$1" -n | grep LISTEN || true
}

# Create/manage multi-instance services
create_service() {
    read -rp "Instance name (no spaces, e.g. udp1): " NAME
    if [[ -z "$NAME" ]]; then echo -e "${RED}Instance name required.${NC}"; return; fi
    read -rp "Mode (1=Server, 2=Client): " MODE
    if [[ "$MODE" == "1" ]]; then
        read -rp "Listen port (UDP): " LISTEN_PORT
        check_port "$LISTEN_PORT" && echo -e "${RED}Port $LISTEN_PORT already in use!${NC}" && return
        read -rp "Forward to local port (UDP, e.g. 51820): " WG_PORT
        read -rp "Password: " PASSWD
        read -rp "Mode (0/1, default 1): " SPD_MODE; SPD_MODE=${SPD_MODE:-1}
        read -rp "Timeout (default 1): " TIMEOUT; TIMEOUT=${TIMEOUT:-1}
        read -rp "MTU (default 1250): " MTU; MTU=${MTU:-1250}
        read -rp "Enable FEC? (yes/no, default yes): " FEC; FEC=${FEC,,}
        [[ "$FEC" == "no" ]] && FEC_OPT="--disable-fec" || FEC_OPT="-f20:10"
        SERVICE_CMD="$UDPSPEEDER_BIN -s -l0.0.0.0:${LISTEN_PORT} --mode ${SPD_MODE} --timeout ${TIMEOUT} --mtu ${MTU} -r127.0.0.1:${WG_PORT} ${FEC_OPT} -k \"${PASSWD}\""
    elif [[ "$MODE" == "2" ]]; then
        read -rp "Local UDP port: " WG_PORT
        check_port "$WG_PORT" && echo -e "${RED}Port $WG_PORT already in use!${NC}" && return
        read -rp "Server public IP: " SERVER_IP
        read -rp "Server speederv2 port: " SERVER_PORT
        read -rp "Password: " PASSWD
        read -rp "Mode (0/1, default 1): " SPD_MODE; SPD_MODE=${SPD_MODE:-1}
        read -rp "Timeout (default 1): " TIMEOUT; TIMEOUT=${TIMEOUT:-1}
        read -rp "MTU (default 1250): " MTU; MTU=${MTU:-1250}
        read -rp "Enable FEC? (yes/no, default yes): " FEC; FEC=${FEC,,}
        [[ "$FEC" == "no" ]] && FEC_OPT="--disable-fec" || FEC_OPT="-f20:10"
        SERVICE_CMD="$UDPSPEEDER_BIN -c -l0.0.0.0:${WG_PORT} -r${SERVER_IP}:${SERVER_PORT} --mode ${SPD_MODE} --timeout ${TIMEOUT} --mtu ${MTU} ${FEC_OPT} -k \"${PASSWD}\""
    else
        echo -e "${RED}Invalid selection!${NC}"; return
    fi

    SERVICE_FILE="/etc/systemd/system/speederv2-${NAME}.service"
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=UDPspeeder Service ($NAME)
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
    sudo systemctl enable speederv2-"$NAME"
    sudo systemctl restart speederv2-"$NAME"
    echo -e "${GREEN}Service speederv2-${NAME} started and enabled.${NC}"
}

list_services() {
    echo -e "${CYAN}Active UDPspeeder Instances:${NC}"
    systemctl list-units --type=service --all | grep speederv2- | awk '{print $1, $4}'
}

service_status() {
    read -rp "Instance name: " NAME
    sudo systemctl status speederv2-"$NAME"
}

show_logs() {
    read -rp "Instance name: " NAME
    sudo journalctl -u speederv2-"$NAME" --no-pager -n 50
}

remove_service() {
    read -rp "Instance name to remove: " NAME
    sudo systemctl stop speederv2-"$NAME" || true
    sudo systemctl disable speederv2-"$NAME" || true
    sudo rm -f /etc/systemd/system/speederv2-"$NAME".service
    sudo systemctl daemon-reload
    echo -e "${GREEN}Removed service speederv2-${NAME}${NC}"
}

uninstall_udpspeeder() {
    sudo pkill -f "$UDPSPEEDER_BIN" || true
    sudo rm -f "$UDPSPEEDER_BIN"
    sudo systemctl daemon-reload
    echo -e "${GREEN}UDPspeeder uninstalled.${NC}"
}

main_menu() {
    while true; do
        clear
        echo -e "${CYAN}====== Pro UDPspeeder Manager ======${NC}"
        echo -e "${YELLOW}1) Install/Update UDPspeeder"
        echo -e "2) Create new UDPspeeder instance"
        echo -e "3) List UDPspeeder instances"
        echo -e "4) Show service status"
        echo -e "5) Show service logs"
        echo -e "6) Remove UDPspeeder instance"
        echo -e "7) Uninstall UDPspeeder"
        echo -e "0) Exit${NC}"
        echo
        read -p "Select an option [0-7]: " opt
        case $opt in
            1) install_udpspeeder ;;
            2) create_service ;;
            3) list_services; read -n1 -r -p "Press any key..." ;;
            4) service_status; read -n1 -r -p "Press any key..." ;;
            5) show_logs; read -n1 -r -p "Press any key..." ;;
            6) remove_service ;;
            7) uninstall_udpspeeder ;;
            0) exit 0 ;;
            *) echo -e "${RED}Invalid option!${NC}"; sleep 1 ;;
        esac
    done
}

main_menu
