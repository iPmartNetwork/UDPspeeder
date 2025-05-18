#!/bin/bash
# UDPSpeeder Professional Manager by iPmart
# Multi-Arch, Systemd Service, Quick Run

RED='\e[91m'; GREEN='\e[92m'; YELLOW='\e[93m'; BLUE='\e[94m'; CYAN='\e[96m'; NC='\e[0m'

if [[ $(id -u) -ne 0 ]]; then
    echo -e "${RED}Please run this script as root.${NC}"; exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)   BIN="speederv2_amd64";;
    i386|i686) BIN="speederv2_x86";;
    aarch64)  BIN="speederv2_arm64";;
    armv7l)   BIN="speederv2_arm";;
    *) echo -e "${RED}Your architecture is not supported!${NC}"; exit 1;;
esac

download_speederv2() {
    echo -e "${BLUE}Fetching the latest speederv2 from iPmartNetwork...${NC}"
    apt-get update -y &>/dev/null
    apt-get install wget curl -y &>/dev/null
    VER=$(curl -s https://api.github.com/repos/iPmartNetwork/UDPRAW-V2/releases/latest | grep tag_name | cut -d\" -f4)
    if [[ -z "$VER" ]]; then
        echo -e "${RED}Could not fetch latest version tag!${NC}"
        exit 1
    fi
    FILE="$BIN"
    URL="https://github.com/iPmartNetwork/UDPRAW-V2/releases/download/${VER}/${FILE}"
    wget -O /usr/bin/speederv2 "$URL" || { echo -e "${RED}Download failed!${NC}"; exit 1; }
    chmod +x /usr/bin/speederv2
    echo -e "${GREEN}speederv2 $VER installed/updated successfully!${NC}"
}

create_service() {
    echo -e "${YELLOW}=== Create a new speederv2 systemd service ===${NC}"
    read -p "Service name (e.g. udps1): " SVCNAME
    read -p "Role (server/client) [s/c]: " ROLE
    if [[ $ROLE == "s" || $ROLE == "S" ]]; then
        MODE="-s"
        read -p "Listen port (e.g. 40000): " PORT
        read -p "Forward to (e.g. 127.0.0.1:51820): " DEST
        read -p "Tunnel password: " PASS
        read -p "FEC option (e.g. -f20:10 or --disable-fec): " FEC
        read -p "Timeout (default 1): " TIMEOUT
        read -p "MTU (default 1250): " MTU
        read -p "Mode (0/1) [default 1]: " UMODE
        [[ -z "$TIMEOUT" ]] && TIMEOUT=1
        [[ -z "$MTU" ]] && MTU=1250
        [[ -z "$UMODE" ]] && UMODE=1
        EXEC="/usr/bin/speederv2 $MODE -l0.0.0.0:$PORT -r$DEST -k \"$PASS\" --mode $UMODE --timeout $TIMEOUT --mtu $MTU $FEC"
    else
        MODE="-c"
        read -p "Local port to listen (e.g. 51820): " LOCAL
        read -p "Server IP:Port (e.g. 1.2.3.4:40000): " REMOTE
        read -p "Tunnel password: " PASS
        read -p "FEC option (e.g. -f20:10 or --disable-fec): " FEC
        read -p "Timeout (default 1): " TIMEOUT
        read -p "MTU (default 1250): " MTU
        read -p "Mode (0/1) [default 1]: " UMODE
        [[ -z "$TIMEOUT" ]] && TIMEOUT=1
        [[ -z "$MTU" ]] && MTU=1250
        [[ -z "$UMODE" ]] && UMODE=1
        EXEC="/usr/bin/speederv2 $MODE -l0.0.0.0:$LOCAL -r$REMOTE -k \"$PASS\" --mode $UMODE --timeout $TIMEOUT --mtu $MTU $FEC"
    fi

    cat > /etc/systemd/system/speederv2-$SVCNAME.service <<EOF
[Unit]
Description=speederv2 Tunnel Service ($SVCNAME)
After=network.target

[Service]
ExecStart=$EXEC
Restart=always
User=root
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now speederv2-$SVCNAME
    echo -e "${GREEN}Service speederv2-$SVCNAME created and started.${NC}"
}

delete_service() {
    read -p "Service name to delete: " SVCNAME
    systemctl stop speederv2-$SVCNAME
    systemctl disable speederv2-$SVCNAME
    rm -f /etc/systemd/system/speederv2-$SVCNAME.service
    systemctl daemon-reload
    echo -e "${YELLOW}Service speederv2-$SVCNAME deleted.${NC}"
}

show_services() {
    echo -e "${CYAN}==== speederv2 systemd services ====${NC}"
    systemctl list-units --type=service | grep speederv2 || echo "No speederv2 services running."
    echo
    read -p "Press Enter to continue..."
}

uninstall_speederv2() {
    rm -f /usr/bin/speederv2
    echo -e "${YELLOW}speederv2 binary deleted.${NC}"
}

run_tunnel() {
    echo -e "${YELLOW}=== Quick Run speederv2 Tunnel ===${NC}"
    read -p "Role (server/client) [s/c]: " ROLE
    if [[ $ROLE == "s" || $ROLE == "S" ]]; then
        MODE="-s"
        read -p "Listen port (e.g. 40000): " PORT
        read -p "Forward to (e.g. 127.0.0.1:51820): " DEST
        read -p "Tunnel password: " PASS
        read -p "FEC option (e.g. -f20:10 or --disable-fec): " FEC
        read -p "Timeout (default 1): " TIMEOUT
        read -p "MTU (default 1250): " MTU
        read -p "Mode (0/1) [default 1]: " UMODE
        [[ -z "$TIMEOUT" ]] && TIMEOUT=1
        [[ -z "$MTU" ]] && MTU=1250
        [[ -z "$UMODE" ]] && UMODE=1
        echo -e "${CYAN}Running speederv2 server...${NC}"
        echo -e "${GREEN}Command:${NC} speederv2 $MODE -l0.0.0.0:$PORT -r$DEST -k \"$PASS\" --mode $UMODE --timeout $TIMEOUT --mtu $MTU $FEC"
        /usr/bin/speederv2 $MODE -l0.0.0.0:$PORT -r$DEST -k "$PASS" --mode $UMODE --timeout $TIMEOUT --mtu $MTU $FEC
    else
        MODE="-c"
        read -p "Local port to listen (e.g. 51820): " LOCAL
        read -p "Server IP:Port (e.g. 1.2.3.4:40000): " REMOTE
        read -p "Tunnel password: " PASS
        read -p "FEC option (e.g. -f20:10 or --disable-fec): " FEC
        read -p "Timeout (default 1): " TIMEOUT
        read -p "MTU (default 1250): " MTU
        read -p "Mode (0/1) [default 1]: " UMODE
        [[ -z "$TIMEOUT" ]] && TIMEOUT=1
        [[ -z "$MTU" ]] && MTU=1250
        [[ -z "$UMODE" ]] && UMODE=1
        echo -e "${CYAN}Running speederv2 client...${NC}"
        echo -e "${GREEN}Command:${NC} speederv2 $MODE -l0.0.0.0:$LOCAL -r$REMOTE -k \"$PASS\" --mode $UMODE --timeout $TIMEOUT --mtu $MTU $FEC"
        /usr/bin/speederv2 $MODE -l0.0.0.0:$LOCAL -r$REMOTE -k "$PASS" --mode $UMODE --timeout $TIMEOUT --mtu $MTU $FEC
    fi
}

while true; do
    clear
    echo -e "${BLUE}=============================================="
    echo -e "        speederv2 (UDPSpeeder) Manager"
    echo -e "==============================================${NC}"
    echo -e "${GREEN}1) Install/Update speederv2"
    echo -e "2) Uninstall speederv2"
    echo -e "3) Create speederv2 systemd service"
    echo -e "4) Delete speederv2 systemd service"
    echo -e "5) Show all speederv2 services"
    echo -e "6) Run a tunnel (quick, not as service)"
    echo -e "7) Exit${NC}"
    read -p "Select an option [1-7]: " CH
    case "$CH" in
        1) download_speederv2;;
        2) uninstall_speederv2;;
        3) create_service;;
        4) delete_service;;
        5) show_services;;
        6) run_tunnel;;
        7) exit 0;;
        *) echo -e "${RED}Invalid selection!${NC}"; sleep 1;;
    esac
done
