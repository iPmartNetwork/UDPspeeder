#!/bin/bash

set -e

# Theme/colors
ENABLE_COLOR=1
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"
NC="\033[0m"

function cecho() {
    if [[ "$ENABLE_COLOR" -eq 1 ]]; then
        echo -e "$1"
    else
        echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g'
    fi
}

BIN_DIR="/usr/local/bin"
BIN_PATH="${BIN_DIR}/speederv2"
SYSTEMD_DIR="/etc/systemd/system"
BACKUP_FILE="/root/udpspeeder_services_backup.tar.gz"

detect_arch() {
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        echo "amd64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        echo "arm64"
    else
        cecho "${RED}Unsupported architecture: $ARCH${NC}"
        exit 1
    fi
}

download_udpspeeder() {
    ARCH=$(detect_arch)
    URL="https://github.com/iPmartNetwork/UDPspeeder/releases/latest/download/speederv2_${ARCH}"
    cecho "${YELLOW}Downloading UDPspeeder binary for ${ARCH}...${NC}"
    wget -O "$BIN_PATH" "$URL"
    chmod +x "$BIN_PATH"
    cecho "${GREEN}UDPspeeder binary installed at $BIN_PATH${NC}"
}

update_udpspeeder() {
    cecho "${YELLOW}Updating UDPspeeder binary...${NC}"
    rm -f "$BIN_PATH"
    download_udpspeeder
    cecho "${GREEN}UDPspeeder binary updated!${NC}"
}

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

    SERVICE_FILE="$SYSTEMD_DIR/speederv2_${instance}.service"
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
    cecho "${GREEN}Service speederv2_${instance} started and enabled.${NC}"
}

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

    SERVICE_FILE="$SYSTEMD_DIR/speederv2_${instance}.service"
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
    cecho "${GREEN}Client service speederv2_${instance} started and enabled.${NC}"
}

remove_service() {
    local instance=$1
    systemctl stop speederv2_${instance}.service 2>/dev/null || true
    systemctl disable speederv2_${instance}.service 2>/dev/null || true
    rm -f "$SYSTEMD_DIR/speederv2_${instance}.service"
    systemctl daemon-reload
    cecho "${YELLOW}Service speederv2_${instance} removed.${NC}"
}

status_service() {
    local instance=$1
    systemctl status speederv2_${instance}.service --no-pager
}

restart_service() {
    local instance=$1
    systemctl restart speederv2_${instance}.service
    cecho "${GREEN}Service speederv2_${instance} restarted.${NC}"
}

list_services() {
    cecho "${CYAN}--- All UDPspeeder Instances ---${NC}"
    ls $SYSTEMD_DIR/speederv2_*.service 2>/dev/null | while read svc; do
        svc_name=$(basename "$svc" | cut -d. -f1)
        is_active=$(systemctl is-active $svc_name 2>/dev/null)
        line=" - ${svc_name} : ${is_active}"
        [[ "$is_active" == "active" ]] && cecho "${GREEN}${line}${NC}" || cecho "${RED}${line}${NC}"
    done
}

view_logs() {
    read -p "Instance name to view logs: " INS
    if [ -z "$INS" ]; then
        cecho "${RED}Instance name is required.${NC}"
        return
    fi
    cecho "${YELLOW}--- Showing live logs for speederv2_${INS}.service (Press Ctrl+C to quit) ---${NC}"
    journalctl -u speederv2_${INS}.service -f
}

backup_services() {
    cecho "${YELLOW}Backing up all UDPspeeder services...${NC}"
    tar -czvf "$BACKUP_FILE" $SYSTEMD_DIR/speederv2_*.service 2>/dev/null || true
    cecho "${GREEN}Backup completed: $BACKUP_FILE${NC}"
}

restore_services() {
    if [[ ! -f "$BACKUP_FILE" ]]; then
        cecho "${RED}No backup file found at $BACKUP_FILE${NC}"
        return
    fi
    cecho "${YELLOW}Restoring UDPspeeder services...${NC}"
    tar -xzvf "$BACKUP_FILE" -C /
    systemctl daemon-reload
    cecho "${GREEN}Restore completed.${NC}"
}

toggle_theme() {
    if [[ "$ENABLE_COLOR" -eq 1 ]]; then
        ENABLE_COLOR=0
        cecho "${YELLOW}Switched to plain (no-color) mode.${NC}"
    else
        ENABLE_COLOR=1
        cecho "${GREEN}Switched to colorful mode.${NC}"
    fi
}

# NETWORK OPTIMIZATION MENU
network_optimization() {
    cecho "${YELLOW}Applying UDP and TCP buffer optimizations...${NC}"
    sysctl -w net.core.rmem_max=2500000
    sysctl -w net.core.wmem_max=2500000

    if modprobe tcp_bbr 2>/dev/null; then
        sysctl -w net.core.default_qdisc=fq
        sysctl -w net.ipv4.tcp_congestion_control=bbr
        cecho "${GREEN}TCP BBR congestion control enabled!${NC}"
    else
        cecho "${RED}BBR is not supported on this kernel. Skipping BBR.${NC}"
    fi
    cecho "${GREEN}Network optimization settings applied.${NC}"
}

setup_server() {
    cecho "${CYAN}--- UDPspeeder Server Setup ---${NC}"
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

setup_client() {
    cecho "${CYAN}--- UDPspeeder Client Setup ---${NC}"
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

main_menu() {
    if [[ ! -f "$BIN_PATH" ]]; then
        download_udpspeeder
    fi
    while true; do
        cecho "${YELLOW}========= UDPspeeder Manager =========${NC}"
        cecho "1) Setup Server"
        cecho "2) Setup Client"
        cecho "3) Remove Service"
        cecho "4) Service Status"
        cecho "5) List All Instances"
        cecho "6) View Live Logs"
        cecho "7) Restart Instance"
        cecho "8) Backup All Services"
        cecho "9) Restore Services from Backup"
        cecho "10) Update UDPspeeder Binary"
        cecho "11) Switch Theme (Color/Plain)"
        cecho "12) Network Optimization (Reduce Ping/Jitter)"
        cecho "13) Exit"
        read -p "Choose: " CHOICE
        case "$CHOICE" in
            1) setup_server ;;
            2) setup_client ;;
            3) read -p "Instance name to remove: " INS; remove_service "$INS" ;;
            4) read -p "Instance name to check status: " INS; status_service "$INS" ;;
            5) list_services ;;
            6) view_logs ;;
            7) read -p "Instance name to restart: " INS; restart_service "$INS" ;;
            8) backup_services ;;
            9) restore_services ;;
            10) update_udpspeeder ;;
            11) toggle_theme ;;
            12) network_optimization ;;
            13) exit 0 ;;
            *) cecho "${RED}Invalid choice${NC}";;
        esac
    done
}

main_menu
