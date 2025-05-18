#!/bin/bash

# Colors
RED='\e[91m'
GREEN='\e[92m'
YELLOW='\e[93m'
CYAN='\e[96m'
NC='\e[0m'

UDPSPEEDER_PATH="/usr/local/bin/speederv2"
SERVICE_PATH="/etc/systemd/system/udpspeeder.service"
ARCH=$(uname -m)

# Architecture mapping
detect_arch() {
    case "$ARCH" in
        x86_64)  BIN_NAME="speederv2_amd64";;
        i386|i686)  BIN_NAME="speederv2_x86";;
        armv7l)  BIN_NAME="speederv2_arm";;
        armv6l)  BIN_NAME="speederv2_arm";;
        aarch64)  BIN_NAME="speederv2_arm64";;
        mips)     BIN_NAME="speederv2_mips";;
        mipsle)   BIN_NAME="speederv2_mipsle";;
        s390x)    BIN_NAME="speederv2_s390x";;
        ppc64le)  BIN_NAME="speederv2_ppc64le";;
        *) echo -e "${RED}Unsupported architecture: $ARCH${NC}"; exit 1;;
    esac
}

# Root check
[[ $EUID -ne 0 ]] && echo -e "${RED}Please run as root.${NC}" && exit 1

# Check package manager
if command -v apt-get &>/dev/null; then
    PKG="apt-get"
elif command -v yum &>/dev/null; then
    PKG="yum"
else
    echo -e "${RED}Supported package manager not found (apt-get or yum).${NC}"
    exit 1
fi

install_udpspeeder() {
    detect_arch
    $PKG update -y && $PKG install wget curl tar -y
    echo -e "${CYAN}Fetching latest UDPspeeder release version...${NC}"
    LATEST_VER=$(curl -s https://api.github.com/repos/wangyu-/UDPspeeder/releases/latest | grep 'tag_name' | head -n1 | cut -d\" -f4)
    if [[ -z "$LATEST_VER" ]]; then
        echo -e "${RED}Failed to fetch latest version!${NC}"
        exit 1
    fi
    echo -e "${CYAN}Downloading UDPspeeder $LATEST_VER for $BIN_NAME...${NC}"
    TMP_DIR=$(mktemp -d)
    wget -q --show-progress --https-only -O "$TMP_DIR/udpspeeder.tar.gz" "https://github.com/wangyu-/UDPspeeder/releases/download/$LATEST_VER/speederv2_binaries.tar.gz"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Download failed!${NC}"
        rm -rf "$TMP_DIR"
        exit 1
    fi
    tar -xzf "$TMP_DIR/udpspeeder.tar.gz" -C "$TMP_DIR"
    if [[ ! -f "$TMP_DIR/$BIN_NAME" ]]; then
        echo -e "${RED}Binary for your architecture not found!${NC}"
        rm -rf "$TMP_DIR"
        exit 1
    fi
    mv -f "$TMP_DIR/$BIN_NAME" "$UDPSPEEDER_PATH"
    chmod +x "$UDPSPEEDER_PATH"
    rm -rf "$TMP_DIR"
    echo -e "${GREEN}UDPspeeder installed successfully! Run: speederv2 --help${NC}"
}

uninstall_udpspeeder() {
    systemctl stop udpspeeder 2>/dev/null
    rm -f "$UDPSPEEDER_PATH"
    rm -f "$SERVICE_PATH"
    systemctl daemon-reload
    echo -e "${GREEN}UDPspeeder uninstalled and service removed.${NC}"
}

start_udpspeeder() {
    if ! [ -f "$UDPSPEEDER_PATH" ]; then
        echo -e "${RED}UDPspeeder not installed!${NC}"
        return
    fi
    read -p "$(echo -e ${YELLOW}Enter speederv2 parameters (e.g. -l0.0.0.0:4096 -r127.0.0.1:1080 -f20:10 -k passwd):${NC} ) " PARAMS
    nohup "$UDPSPEEDER_PATH" $PARAMS > /var/log/udpspeeder.log 2>&1 &
    sleep 1
    pgrep -f "$UDPSPEEDER_PATH" >/dev/null && echo -e "${GREEN}UDPspeeder started!${NC}" || echo -e "${RED}Failed to start!${NC}"
}

stop_udpspeeder() {
    pkill -f "$UDPSPEEDER_PATH" && echo -e "${GREEN}UDPspeeder stopped.${NC}" || echo -e "${YELLOW}No running UDPspeeder found.${NC}"
}

status_udpspeeder() {
    if pgrep -f "$UDPSPEEDER_PATH" >/dev/null; then
        echo -e "${GREEN}UDPspeeder is running.${NC}"
    else
        echo -e "${YELLOW}UDPspeeder is not running.${NC}"
    fi
}

create_service() {
    if ! [ -f "$UDPSPEEDER_PATH" ]; then
        echo -e "${RED}UDPspeeder not installed!${NC}"
        return
    fi
    read -p "$(echo -e ${YELLOW}Enter speederv2 parameters for service (e.g. -l0.0.0.0:4096 -r127.0.0.1:1080 -f20:10 -k passwd):${NC} ) " PARAMS
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=UDPspeeder Service
After=network.target

[Service]
Type=simple
ExecStart=$UDPSPEEDER_PATH $PARAMS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable udpspeeder
    systemctl restart udpspeeder
    echo -e "${GREEN}UDPspeeder service created and started.${NC}"
}

remove_service() {
    systemctl stop udpspeeder 2>/dev/null
    systemctl disable udpspeeder 2>/dev/null
    rm -f "$SERVICE_PATH"
    systemctl daemon-reload
    echo -e "${GREEN}UDPspeeder systemd service removed.${NC}"
}

while true; do
    clear
    echo -e "${CYAN}==================== UDPspeeder Manager ====================${NC}"
    echo -e "${YELLOW}1) Install UDPspeeder"
    echo -e "2) Uninstall UDPspeeder"
    echo -e "3) Start UDPspeeder (manual/foreground)"
    echo -e "4) Stop UDPspeeder"
    echo -e "5) Status"
    echo -e "6) Create systemd service (autostart)"
    echo -e "7) Remove systemd service"
    echo -e "0) Exit${NC}"
    echo
    read -p "Select an option [0-7]: " OPTION
    case $OPTION in
        1) install_udpspeeder ;;
        2) uninstall_udpspeeder ;;
        3) start_udpspeeder ;;
        4) stop_udpspeeder ;;
        5) status_udpspeeder; read -n1 -r -p "Press any key to continue..." ;;
        6) create_service ;;
        7) remove_service ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid selection!${NC}"; sleep 1 ;;
    esac
done
