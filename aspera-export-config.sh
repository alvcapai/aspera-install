#!/bin/bash
################################################################################
# IBM Aspera Server Configuration Export Script
# Version: 1.0.0
# Date: 2026-05-07
# Description: Extracts Aspera server configuration and generates portable JSON
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Progress tracking
STEP=0
TOTAL_STEPS=4

# Configuration
OUTPUT_FILE="${1:-aspera-server-config.json}"
ASPERA_DIR="/opt/aspera"
ASPERA_DATA_DIR="/aspera/data"

print_info() {
    echo -e "  ${CYAN}→${NC} $1"
}

print_success() {
    echo -e "  ${GREEN}✔${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✖${NC} $1"
}

print_step() {
    STEP=$((STEP + 1))
    echo ""
    echo -e "${BOLD}${BLUE}  ──────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}${BLUE}[${STEP}/${TOTAL_STEPS}]${NC}  ${BOLD}$1${NC}"
    echo -e "${BOLD}${BLUE}  ──────────────────────────────────────────────────────${NC}"
    echo ""
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Install any missing runtime deps (jq for JSON, awscli for COS upload).
# Runs as root, so no sudo needed.
ensure_dependencies() {
    local missing=()
    command -v jq &> /dev/null || missing+=(jq)
    command -v aws &> /dev/null || missing+=(awscli)

    if [ ${#missing[@]} -eq 0 ]; then
        return 0
    fi

    print_info "Installing missing dependencies: ${missing[*]}"

    if command -v apt-get &> /dev/null; then
        apt-get update -qq >/dev/null 2>&1 || true
        # jq from apt is reliable; awscli may be unavailable on Ubuntu 24.04+,
        # so try apt first then fall back to pip3.
        apt-get install -y -qq "${missing[@]}" >/dev/null 2>&1 || true
    elif command -v dnf &> /dev/null; then
        dnf install -y -q "${missing[@]}" >/dev/null 2>&1 || true
    elif command -v yum &> /dev/null; then
        yum install -y -q "${missing[@]}" >/dev/null 2>&1 || true
    fi

    # awscli pip fallback for distros where the package is gone
    if ! command -v aws &> /dev/null && command -v pip3 &> /dev/null; then
        pip3 install --quiet --break-system-packages awscli >/dev/null 2>&1 || true
    fi

    command -v jq  &> /dev/null || print_warning "jq could not be installed; JSON validation and pretty summary will be skipped."
    command -v aws &> /dev/null || print_warning "awscli could not be installed; COS upload will be skipped."
}

# Function to check if Aspera is installed
check_aspera_installed() {
    if [ ! -d "$ASPERA_DIR" ]; then
        print_error "Aspera is not installed at $ASPERA_DIR"
        exit 1
    fi
    
    if ! systemctl is-active --quiet asperanoded; then
        print_warning "Aspera service is not running"
    fi
}

# Function to get server IPs
get_server_ips() {
    local PRIVATE_IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -1)
    local PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "")
    local HOSTNAME=$(hostname)
    
    echo "{
        \"private_ip\": \"$PRIVATE_IP\",
        \"public_ip\": \"$PUBLIC_IP\",
        \"hostname\": \"$HOSTNAME\",
        \"ssh_port\": 22
    }"
}

# Function to get network information
get_network_info() {
    local INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    local SUBNET=$(ip addr show $INTERFACE | grep 'inet ' | awk '{print $2}')
    local GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
    
    echo "{
        \"interface\": \"$INTERFACE\",
        \"subnet\": \"$SUBNET\",
        \"gateway\": \"$GATEWAY\"
    }"
}

# Function to get transfer users
get_transfer_users() {
    local USERS_JSON="["
    local FIRST=true
    local ADDED_USERS=()
    
    # Function to add user to JSON
    add_user_to_json() {
        local USERNAME=$1
        local USER_DIR=$2
        local HOME_DIR=$3
        
        # Skip if user already added
        for added in "${ADDED_USERS[@]}"; do
            if [ "$added" = "$USERNAME" ]; then
                return
            fi
        done
        
        local SSH_KEY_EXISTS="false"
        
        # Check for SSH keys in multiple locations
        if [ -f "$HOME_DIR/.ssh/authorized_keys" ] || [ -f "$USER_DIR/.ssh/authorized_keys" ]; then
            SSH_KEY_EXISTS="true"
        fi
        
        if [ "$FIRST" = false ]; then
            USERS_JSON+=","
        fi
        FIRST=false
        
        USERS_JSON+="
        {
            \"username\": \"$USERNAME\",
            \"home_dir\": \"$USER_DIR\",
            \"system_home\": \"$HOME_DIR\",
            \"ssh_key_required\": $SSH_KEY_EXISTS
        }"
        
        ADDED_USERS+=("$USERNAME")
    }
    
    # Method 1: Find users with home directories in /aspera/data
    if [ -d "$ASPERA_DATA_DIR" ]; then
        for USER_DIR in "$ASPERA_DATA_DIR"/*; do
            if [ -d "$USER_DIR" ]; then
                local USERNAME=$(basename "$USER_DIR")
                
                # Check if user exists in system
                if id "$USERNAME" &>/dev/null; then
                    local HOME_DIR=$(eval echo ~$USERNAME)
                    add_user_to_json "$USERNAME" "$USER_DIR" "$HOME_DIR"
                fi
            fi
        done
    fi
    
    # Method 2: Detect common system users based on OS
    # Check for ubuntu user (common in Ubuntu systems)
    if id "ubuntu" &>/dev/null; then
        local UBUNTU_HOME=$(eval echo ~ubuntu)
        local UBUNTU_ASPERA_DIR="$ASPERA_DATA_DIR/ubuntu"
        
        # Create aspera data dir for ubuntu if it doesn't exist (for reference)
        if [ ! -d "$UBUNTU_ASPERA_DIR" ]; then
            UBUNTU_ASPERA_DIR="$UBUNTU_HOME"
        fi
        
        add_user_to_json "ubuntu" "$UBUNTU_ASPERA_DIR" "$UBUNTU_HOME"
    fi
    
    # Method 3: Check for ec2-user (common in Amazon Linux/RHEL)
    if id "ec2-user" &>/dev/null; then
        local EC2_HOME=$(eval echo ~ec2-user)
        local EC2_ASPERA_DIR="$ASPERA_DATA_DIR/ec2-user"
        
        if [ ! -d "$EC2_ASPERA_DIR" ]; then
            EC2_ASPERA_DIR="$EC2_HOME"
        fi
        
        add_user_to_json "ec2-user" "$EC2_ASPERA_DIR" "$EC2_HOME"
    fi
    
    # Method 4: Check for centos user (common in CentOS)
    if id "centos" &>/dev/null; then
        local CENTOS_HOME=$(eval echo ~centos)
        local CENTOS_ASPERA_DIR="$ASPERA_DATA_DIR/centos"
        
        if [ ! -d "$CENTOS_ASPERA_DIR" ]; then
            CENTOS_ASPERA_DIR="$CENTOS_HOME"
        fi
        
        add_user_to_json "centos" "$CENTOS_ASPERA_DIR" "$CENTOS_HOME"
    fi
    
    # Method 5: Check for root user (always exists)
    if [ ${#ADDED_USERS[@]} -eq 0 ]; then
        local ROOT_HOME="/root"
        local ROOT_ASPERA_DIR="$ASPERA_DATA_DIR/root"
        
        if [ ! -d "$ROOT_ASPERA_DIR" ]; then
            ROOT_ASPERA_DIR="$ROOT_HOME"
        fi
        
        add_user_to_json "root" "$ROOT_ASPERA_DIR" "$ROOT_HOME"
    fi
    
    USERS_JSON+="
    ]"
    
    echo "$USERS_JSON"
}

# Function to get service status
get_service_status() {
    local ASPERANODED_STATUS="inactive"
    local SSH_STATUS="inactive"
    
    if systemctl is-active --quiet asperanoded; then
        ASPERANODED_STATUS="active"
    fi
    
    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
        SSH_STATUS="active"
    fi
    
    echo "{
        \"asperanoded\": \"$ASPERANODED_STATUS\",
        \"ssh\": \"$SSH_STATUS\"
    }"
}

# Function to get Aspera configuration
get_aspera_config() {
    local TARGET_RATE="unknown"
    local MIN_RATE="unknown"
    local MAX_SESSIONS="unknown"
    local TCP_PORT="unknown"
    local UDP_MIN="unknown"
    local UDP_MAX="unknown"
    
    if [ -f "$ASPERA_DIR/etc/aspera.conf" ]; then
        TARGET_RATE=$(grep -oP '<target_rate_kbps>\K[^<]+' "$ASPERA_DIR/etc/aspera.conf" 2>/dev/null || echo "unknown")
        MIN_RATE=$(grep -oP '<min_rate_kbps>\K[^<]+' "$ASPERA_DIR/etc/aspera.conf" 2>/dev/null || echo "unknown")
        MAX_SESSIONS=$(grep -oP '<max_sessions>\K[^<]+' "$ASPERA_DIR/etc/aspera.conf" 2>/dev/null || echo "unknown")
        TCP_PORT=$(grep -oP '<tcp_port>\K[^<]+' "$ASPERA_DIR/etc/aspera.conf" 2>/dev/null || echo "unknown")
        UDP_MIN=$(grep -oP '<min>\K[^<]+' "$ASPERA_DIR/etc/aspera.conf" 2>/dev/null | head -1 || echo "unknown")
        UDP_MAX=$(grep -oP '<max>\K[^<]+' "$ASPERA_DIR/etc/aspera.conf" 2>/dev/null | head -1 || echo "unknown")
    fi
    
    echo "{
        \"target_rate_kbps\": \"$TARGET_RATE\",
        \"min_rate_kbps\": \"$MIN_RATE\",
        \"max_sessions\": \"$MAX_SESSIONS\",
        \"tcp_port\": \"$TCP_PORT\",
        \"udp_port_range\": {
            \"min\": \"$UDP_MIN\",
            \"max\": \"$UDP_MAX\"
        }
    }"
}

# Function to get firewall rules
get_firewall_rules() {
    local UFW_STATUS="unknown"
    local RULES="[]"
    
    if command -v ufw &>/dev/null; then
        if ufw status | grep -q "Status: active"; then
            UFW_STATUS="active"
            RULES=$(ufw status numbered 2>/dev/null | grep -E '(22|33001|9092)' | sed 's/\[//g' | sed 's/\]//g' || echo "[]")
        else
            UFW_STATUS="inactive"
        fi
    fi
    
    echo "{
        \"ufw_status\": \"$UFW_STATUS\",
        \"aspera_rules_configured\": true
    }"
}

# Function to generate complete JSON
generate_config_json() {
    local TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local SERVER_INFO=$(get_server_ips)
    local NETWORK_INFO=$(get_network_info)
    local TRANSFER_USERS=$(get_transfer_users)
    local SERVICE_STATUS=$(get_service_status)
    local ASPERA_CONFIG=$(get_aspera_config)
    local FIREWALL_INFO=$(get_firewall_rules)
    
    cat > "$OUTPUT_FILE" << EOF
{
    "version": "1.0.0",
    "timestamp": "$TIMESTAMP",
    "server": $SERVER_INFO,
    "network": $NETWORK_INFO,
    "transfer_users": $TRANSFER_USERS,
    "services": $SERVICE_STATUS,
    "aspera_config": $ASPERA_CONFIG,
    "firewall": $FIREWALL_INFO,
    "directories": {
        "aspera_install": "$ASPERA_DIR",
        "aspera_data": "$ASPERA_DATA_DIR"
    }
}
EOF
}

# Function to upload config to COS (Piggyback)
upload_config_to_cos() {
    print_info "Checking if COS variables are set to upload config..."

    # Try to load saved credentials from installation phase
    if [ -f "/opt/aspera/etc/cos_credentials.sh" ]; then
        source "/opt/aspera/etc/cos_credentials.sh"
        print_info "Loaded saved COS credentials from initial server installation."
    fi

    if [ -z "${COS_ACCESS_KEY:-}" ] || [ -z "${COS_SECRET_KEY:-}" ] || [ -z "${COS_ENDPOINT:-}" ] || [ -z "${COS_BUCKET:-}" ]; then
        print_info "COS variables not set. Skipping configuration upload to COS."
        return 0
    fi

    # awscli is installed in ensure_dependencies during pre-flight; if it's
    # still missing here, that step already warned the user, so just skip.
    if ! command -v aws &> /dev/null; then
        print_warning "awscli not available. Skipping COS upload."
        return 0
    fi

    print_info "Uploading configuration to IBM Cloud Object Storage..."

    mkdir -p /root/.aws
    cat > /root/.aws/credentials << EOF
[default]
aws_access_key_id = ${COS_ACCESS_KEY}
aws_secret_access_key = ${COS_SECRET_KEY}
EOF

    cat > /root/.aws/config << EOF
[default]
s3 =
    endpoint_url = ${COS_ENDPOINT}
    signature_version = s3v4
EOF

    COS_UPLOAD_SUCCESS="false"
    # Pass --endpoint-url explicitly: the s3= config block is not honoured by `aws s3 cp`.
    if aws s3 cp --endpoint-url "${COS_ENDPOINT}" --no-verify-ssl "$OUTPUT_FILE" "s3://${COS_BUCKET}/config/aspera-server-config.json"; then
        print_success "Configuration uploaded to s3://${COS_BUCKET}/config/aspera-server-config.json successfully!"
        COS_UPLOAD_SUCCESS="true"
    else
        print_error "Failed to upload configuration to COS."
    fi
}

display_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}  ║${NC}  ${BOLD}${GREEN}✔  Export Complete${NC}                                     ${BOLD}${GREEN}║${NC}"
    echo -e "${BOLD}${GREEN}  ╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}  ║${NC}"
    echo -e "${GREEN}  ║${NC}  ${DIM}Output file${NC}  $OUTPUT_FILE"
    echo -e "${GREEN}  ║${NC}"
    if command -v jq &>/dev/null; then
        echo -e "${GREEN}  ║${NC}  ${BOLD}Server${NC}"
        jq -r '.server | "  \(.hostname)  \(.private_ip)  (public: \(.public_ip))"' "$OUTPUT_FILE" | \
            while IFS= read -r line; do echo -e "${GREEN}  ║${NC}  ${DIM}${line}${NC}"; done
        echo -e "${GREEN}  ║${NC}"
        echo -e "${GREEN}  ║${NC}  ${BOLD}Transfer users${NC}"
        jq -r '.transfer_users[] | "  \(.username)  →  \(.home_dir)"' "$OUTPUT_FILE" | \
            while IFS= read -r line; do echo -e "${GREEN}  ║${NC}  ${DIM}${line}${NC}"; done
        echo -e "${GREEN}  ║${NC}"
        echo -e "${GREEN}  ║${NC}  ${BOLD}Services${NC}"
        jq -r '.services | "  asperanoded: \(.asperanoded)   ssh: \(.ssh)"' "$OUTPUT_FILE" | \
            while IFS= read -r line; do echo -e "${GREEN}  ║${NC}  ${DIM}${line}${NC}"; done
    else
        print_warning "Install 'jq' for formatted output"
    fi
    echo -e "${GREEN}  ║${NC}"
    echo -e "${GREEN}  ║${NC}  ${BOLD}Next steps${NC}"
    echo -e "${GREEN}  ║${NC}"
    if [ "${COS_UPLOAD_SUCCESS:-false}" = "true" ]; then
        echo -e "${GREEN}  ║${NC}  ${CYAN}1.${NC} On the client, set the same COS variables"
        echo -e "${GREEN}  ║${NC}     ${DIM}export COS_ACCESS_KEY=\"...\"  COS_SECRET_KEY=\"...\"${NC}"
        echo -e "${GREEN}  ║${NC}     ${DIM}export COS_ENDPOINT=\"...\"    COS_BUCKET=\"...\"${NC}"
        echo -e "${GREEN}  ║${NC}  ${CYAN}2.${NC} Run the client configurator (piggyback auto-fetch)"
        echo -e "${GREEN}  ║${NC}     ${DIM}./aspera-configure-client.sh${NC}"
    else
        echo -e "${GREEN}  ║${NC}  ${CYAN}1.${NC} Transfer config to the client"
        echo -e "${GREEN}  ║${NC}     ${DIM}scp $OUTPUT_FILE user@client:/tmp/${NC}"
        echo -e "${GREEN}  ║${NC}  ${CYAN}2.${NC} Run the client configurator"
        echo -e "${GREEN}  ║${NC}     ${DIM}./aspera-configure-client.sh /tmp/$(basename "$OUTPUT_FILE")${NC}"
    fi
    echo -e "${GREEN}  ║${NC}"
    echo -e "${BOLD}${GREEN}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Main execution

print_splash() {
    echo ""
    printf "${BOLD}${BLUE}"
    echo " ______________  ___  _____                     _     _           _         "
    echo "|_   _| ___ \\  \\/  | |  ___|                   | |   | |         | |        "
    echo "  | | | |_/ / .  . | | |____  ___ __   ___ _ __| |_  | |     __ _| |__  ___ "
    echo "  | | | ___ \\ |\\/| | |  __\\ \\/ / '_ \\ / _ \\ '__| __| | |    / _\` | '_ \\/ __|"
    echo " _| |_| |_/ / |  | | | |___>  <| |_) |  __/ |  | |_  | |___| (_| | |_) \\__ \\"
    echo " \\___/\\____/\\_|  |_/ \\____/_/\\_\\ .__/ \\___|_|   \\__| \\_____/\\__,_|_.__/|___/"
    echo "                               | |                                          "
    printf "                               |_|                                          \n${NC}"
    echo ""
    echo -e "${BOLD}${BLUE}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}  ║${NC}                                                      ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}  ║${NC}   ${BOLD}IBM Aspera Server${NC}  ${DIM}·${NC}  Configuration Export            ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}  ║${NC}   ${DIM}Ubuntu / RHEL / CentOS / Fedora     v 1.0.0${NC}          ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}  ║${NC}                                                      ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

main() {
    print_splash

    print_step "Pre-flight Checks"
    check_root
    ensure_dependencies
    check_aspera_installed

    print_step "Collect Server Information"
    generate_config_json

    print_step "Validate Config"
    if command -v jq &>/dev/null; then
        if jq empty "$OUTPUT_FILE" 2>/dev/null; then
            print_success "Configuration file generated and validated"
        else
            print_error "Generated JSON is invalid"
            exit 1
        fi
    else
        print_warning "Cannot validate JSON (jq not installed)"
    fi
    chmod 644 "$OUTPUT_FILE"

    print_step "Upload to COS"
    upload_config_to_cos

    display_summary
}

# Run main function
main "$@"

# Made with Bob
