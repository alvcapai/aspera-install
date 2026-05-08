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
NC='\033[0m' # No Color

# Configuration
OUTPUT_FILE="${1:-aspera-server-config.json}"
ASPERA_DIR="/opt/aspera"
ASPERA_DATA_DIR="/aspera/data"

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
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

# Function to display configuration summary
display_summary() {
    print_info "Configuration exported to: $OUTPUT_FILE"
    echo ""
    echo "=========================================="
    echo "  Aspera Server Configuration Summary"
    echo "=========================================="
    echo ""
    
    # Parse and display key information
    if command -v jq &>/dev/null; then
        echo "Server Information:"
        jq -r '.server | "  Private IP: \(.private_ip)\n  Public IP: \(.public_ip)\n  Hostname: \(.hostname)"' "$OUTPUT_FILE"
        echo ""
        
        echo "Transfer Users:"
        jq -r '.transfer_users[] | "  - \(.username) (\(.home_dir))"' "$OUTPUT_FILE"
        echo ""
        
        echo "Services:"
        jq -r '.services | "  Aspera Node: \(.asperanoded)\n  SSH: \(.ssh)"' "$OUTPUT_FILE"
        echo ""
    else
        print_warning "Install 'jq' for better JSON formatting"
        cat "$OUTPUT_FILE"
    fi
    
    echo ""
    echo "Next Steps:"
    echo "1. Transfer this file to the client machine:"
    echo "   scp $OUTPUT_FILE user@client:/tmp/"
    echo ""
    echo "2. On the client, run:"
    echo "   ./aspera-configure-client.sh /tmp/$OUTPUT_FILE"
    echo ""
}

# Main execution
main() {
    print_info "Starting Aspera server configuration export..."
    echo ""
    
    check_root
    check_aspera_installed
    
    print_info "Collecting server information..."
    generate_config_json
    
    # Validate JSON
    if command -v jq &>/dev/null; then
        if jq empty "$OUTPUT_FILE" 2>/dev/null; then
            print_success "Configuration file generated successfully"
        else
            print_error "Generated JSON is invalid"
            exit 1
        fi
    else
        print_warning "Cannot validate JSON (jq not installed)"
    fi
    
    # Set appropriate permissions
    chmod 644 "$OUTPUT_FILE"
    
    display_summary
    
    print_success "Export completed successfully!"
}

# Run main function
main "$@"

# Made with Bob
