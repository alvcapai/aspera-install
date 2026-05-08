#!/bin/bash
################################################################################
# IBM Aspera Client Configuration Script
# Version: 1.0.0
# Date: 2026-05-07
# Description: Configures Aspera client using server configuration JSON
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
CONFIG_FILE="${1:-}"
ASPERA_CLIENT_DIR="$HOME/.aspera/connect"
SSH_KEY_PATH="$HOME/.ssh/aspera_transfer_key"
CLIENT_CONFIG_DIR="$HOME/.aspera-client"
CLIENT_CONFIG_FILE="$CLIENT_CONFIG_DIR/server-config.json"

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

# Function to check if running as regular user
check_user() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should NOT be run as root"
        print_info "Run as regular user: ./aspera-configure-client.sh <config-file>"
        exit 1
    fi
}

# Function to fetch config from COS (Piggyback)
fetch_config_from_cos() {
    print_info "Checking if COS variables are set to fetch config..."

    if [ -z "${COS_ACCESS_KEY:-}" ] || [ -z "${COS_SECRET_KEY:-}" ] || [ -z "${COS_ENDPOINT:-}" ] || [ -z "${COS_BUCKET:-}" ]; then
        print_info "COS variables not set. Cannot fetch config from COS."
        return 0
    fi

    # Ensure AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_warning "awscli not found. Cannot fetch config from COS."
        return 0
    fi

    print_info "Fetching configuration from IBM Cloud Object Storage..."
    
    mkdir -p ~/.aws
    cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = ${COS_ACCESS_KEY}
aws_secret_access_key = ${COS_SECRET_KEY}
EOF

    cat > ~/.aws/config << EOF
[default]
s3 =
    endpoint_url = ${COS_ENDPOINT}
    signature_version = s3v4
EOF

    # If no config file was passed as argument, default to a temp file
    if [ -z "$CONFIG_FILE" ]; then
        CONFIG_FILE="/tmp/aspera-server-config.json"
    fi

    # Download the config file
    if aws s3 cp "s3://${COS_BUCKET}/config/aspera-server-config.json" "$CONFIG_FILE"; then
        print_success "Configuration fetched successfully from s3://${COS_BUCKET}/config/aspera-server-config.json!"
        
        # Security cleanup
        print_info "Removing config file from COS for security..."
        aws s3 rm "s3://${COS_BUCKET}/config/aspera-server-config.json" || print_warning "Failed to remove config from COS."
        rm -rf ~/.aws
    else
        print_warning "Failed to fetch configuration from COS."
    fi
}

# Function to validate config file
validate_config_file() {
    if [ -z "$CONFIG_FILE" ]; then
        print_error "Configuration file not provided"
        echo "Usage: $0 <aspera-server-config.json>"
        exit 1
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    # Validate JSON if jq is available
    if command -v jq &>/dev/null; then
        if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
            print_error "Invalid JSON in configuration file"
            exit 1
        fi
    else
        print_warning "jq not installed, skipping JSON validation"
    fi
}

# Function to check if Aspera client is installed
check_aspera_client() {
    if [ ! -d "$ASPERA_CLIENT_DIR" ]; then
        print_error "Aspera Connect Client is not installed"
        print_info "Please run install-aspera-client.sh first"
        exit 1
    fi
    
    if [ ! -f "$ASPERA_CLIENT_DIR/bin/ascp" ]; then
        print_error "ascp binary not found"
        exit 1
    fi
    
    print_success "Aspera Connect Client found"
}

# Function to parse server configuration
parse_server_config() {
    if command -v jq &>/dev/null; then
        SERVER_PRIVATE_IP=$(jq -r '.server.private_ip' "$CONFIG_FILE")
        SERVER_PUBLIC_IP=$(jq -r '.server.public_ip' "$CONFIG_FILE")
        SERVER_HOSTNAME=$(jq -r '.server.hostname' "$CONFIG_FILE")
        SSH_PORT=$(jq -r '.server.ssh_port' "$CONFIG_FILE")
        
        # Get first transfer user
        TRANSFER_USER=$(jq -r '.transfer_users[0].username' "$CONFIG_FILE")
        TRANSFER_HOME=$(jq -r '.transfer_users[0].home_dir' "$CONFIG_FILE")
        
        print_info "Server: $SERVER_HOSTNAME ($SERVER_PRIVATE_IP)"
        print_info "Transfer User: $TRANSFER_USER"
    else
        print_error "jq is required for parsing JSON configuration"
        print_info "Install jq: sudo apt-get install jq"
        exit 1
    fi
}

# Function to test network connectivity
test_connectivity() {
    print_info "Testing network connectivity to server..."
    
    # Test ping
    if ping -c 3 -W 2 "$SERVER_PRIVATE_IP" &>/dev/null; then
        print_success "Ping to $SERVER_PRIVATE_IP successful"
    else
        print_error "Cannot ping server at $SERVER_PRIVATE_IP"
        print_info "Check network connectivity and firewall rules"
        exit 1
    fi
    
    # Test SSH port
    if nc -zv -w 3 "$SERVER_PRIVATE_IP" "$SSH_PORT" &>/dev/null; then
        print_success "SSH port $SSH_PORT is accessible"
    else
        print_error "Cannot connect to SSH port $SSH_PORT"
        print_info "Check server firewall and Network ACLs"
        exit 1
    fi
}

# Function to setup SSH key
setup_ssh_key() {
    print_info "Setting up SSH key for authentication..."
    
    # Check if key already exists
    if [ -f "$SSH_KEY_PATH" ]; then
        print_info "SSH key already exists: $SSH_KEY_PATH"
        
        # Ask if user wants to use existing key
        read -p "Use existing SSH key? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Generating new SSH key..."
            ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "aspera-client-$(hostname)"
        fi
    else
        print_info "Generating new SSH key..."
        mkdir -p "$(dirname "$SSH_KEY_PATH")"
        ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "aspera-client-$(hostname)"
    fi
    
    # Set correct permissions
    chmod 600 "$SSH_KEY_PATH"
    chmod 644 "${SSH_KEY_PATH}.pub"
    
    print_success "SSH key ready: $SSH_KEY_PATH"
}

# Function to copy SSH key to server
copy_ssh_key_to_server() {
    print_info "Copying SSH public key to server..."
    
    # First, check if we can alrfeady authenticate (key might be already there)
    if ssh -i "$SSH_KEY_PATH" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=5 \
        "${TRANSFER_USER}@${SERVER_PRIVATE_IP}" 'echo "OK"' &>/dev/null; then
        print_success "SSH key already configured on server"
        return 0
    fi
    
    echo ""
    print_warning "SSH key needs to be copied to the server"
    print_info "There are two methods to copy the key:"
    echo ""
    echo "Method 1: If you have password access to $TRANSFER_USER@$SERVER_PRIVATE_IP"
    echo "Method 2: If you have root/sudo access to the server"
    echo "Method 3: Manual copy (you copy the key yourself)"
    echo ""
    read -p "Choose method (1/2/3): " -n 1 -r METHOD
    echo ""
    echo ""
    
    case $METHOD in
        1)
            print_info "Attempting to copy key using password authentication..."
            
            # Try ssh-copy-id first
            if command -v ssh-copy-id &>/dev/null; then
                if ssh-copy-id -i "${SSH_KEY_PATH}.pub" -p "$SSH_PORT" "${TRANSFER_USER}@${SERVER_PRIVATE_IP}"; then
                    print_success "SSH key copied successfully"
                    return 0
                fi
            fi
            
            # Fallback: manual copy with password
            print_info "Attempting manual key copy with password..."
            cat "${SSH_KEY_PATH}.pub" | ssh -p "$SSH_PORT" "${TRANSFER_USER}@${SERVER_PRIVATE_IP}" \
                'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
            
            if [ $? -eq 0 ]; then
                print_success "SSH key copied successfully"
                return 0
            else
                print_error "Failed to copy SSH key with password"
            fi
            ;;
            
        2)
            print_info "Using root/sudo access to copy key..."
            echo ""
            print_info "Run this command on the SERVER as root:"
            echo ""
            echo "cat >> /home/${TRANSFER_USER}/.ssh/authorized_keys << 'EOF'"
            cat "${SSH_KEY_PATH}.pub"
            echo "EOF"
            echo "chmod 600 /home/${TRANSFER_USER}/.ssh/authorized_keys"
            echo "chown ${TRANSFER_USER}:${TRANSFER_USER} /home/${TRANSFER_USER}/.ssh/authorized_keys"
            echo ""
            read -p "Press Enter after you've run the command on the server..."
            
            # Test if it worked
            if ssh -i "$SSH_KEY_PATH" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=5 \
                "${TRANSFER_USER}@${SERVER_PRIVATE_IP}" 'echo "OK"' &>/dev/null; then
                print_success "SSH key configured successfully"
                return 0
            else
                print_error "SSH key still not working. Please verify the commands were run correctly."
            fi
            ;;
            
        3)
            print_info "Manual copy instructions:"
            echo ""
            echo "1. Copy this public key:"
            echo "----------------------------------------"
            cat "${SSH_KEY_PATH}.pub"
            echo "----------------------------------------"
            echo ""
            echo "2. On the SERVER, run as root or with sudo:"
            echo "   mkdir -p /home/${TRANSFER_USER}/.ssh"
            echo "   echo '<paste-public-key-here>' >> /home/${TRANSFER_USER}/.ssh/authorized_keys"
            echo "   chmod 700 /home/${TRANSFER_USER}/.ssh"
            echo "   chmod 600 /home/${TRANSFER_USER}/.ssh/authorized_keys"
            echo "   chown -R ${TRANSFER_USER}:${TRANSFER_USER} /home/${TRANSFER_USER}/.ssh"
            echo ""
            read -p "Press Enter after you've copied the key..."
            
            # Test if it worked
            if ssh -i "$SSH_KEY_PATH" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=5 \
                "${TRANSFER_USER}@${SERVER_PRIVATE_IP}" 'echo "OK"' &>/dev/null; then
                print_success "SSH key configured successfully"
                return 0
            else
                print_error "SSH key still not working. Please verify the key was copied correctly."
            fi
            ;;
            
        *)
            print_error "Invalid method selected"
            exit 1
            ;;
    esac
    
    # If we got here, something failed
    print_error "Failed to configure SSH key"
    print_info "Please configure the key manually and run this script again"
    exit 1
}

# Function to test SSH authentication
test_ssh_auth() {
    print_info "Testing SSH authentication..."
    
    if ssh -i "$SSH_KEY_PATH" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=5 \
        "${TRANSFER_USER}@${SERVER_PRIVATE_IP}" 'echo "SSH OK"' &>/dev/null; then
        print_success "SSH authentication successful"
    else
        print_error "SSH authentication failed"
        print_info "Check SSH key permissions and server configuration"
        exit 1
    fi
}

# Function to create client configuration directory
create_client_config() {
    print_info "Creating client configuration..."
    
    mkdir -p "$CLIENT_CONFIG_DIR"
    
    # Copy server config to client config directory
    cp "$CONFIG_FILE" "$CLIENT_CONFIG_FILE"
    
    # Create client-specific config
    cat > "$CLIENT_CONFIG_DIR/client.conf" << EOF
# Aspera Client Configuration
# Generated: $(date)

# Server Information
SERVER_IP=$SERVER_PRIVATE_IP
SERVER_HOSTNAME=$SERVER_HOSTNAME
SSH_PORT=$SSH_PORT

# Transfer User
TRANSFER_USER=$TRANSFER_USER
TRANSFER_HOME=$TRANSFER_HOME

# SSH Key
SSH_KEY=$SSH_KEY_PATH

# Aspera Client
ASCP_BIN=$ASPERA_CLIENT_DIR/bin/ascp
EOF
    
    chmod 644 "$CLIENT_CONFIG_DIR/client.conf"
    print_success "Client configuration created: $CLIENT_CONFIG_DIR/client.conf"
}

# Function to create helper aliases
create_aliases() {
    print_info "Creating helper aliases..."
    
    local ALIAS_FILE="$CLIENT_CONFIG_DIR/aspera-aliases.sh"
    
    cat > "$ALIAS_FILE" << 'EOF'
#!/bin/bash
# Aspera Client Helper Aliases
# Source this file: source ~/.aspera-client/aspera-aliases.sh

# Load configuration
if [ -f ~/.aspera-client/client.conf ]; then
    source ~/.aspera-client/client.conf
fi

# Alias for Aspera upload
aspera-upload() {
    local SOURCE="$1"
    local DEST="${2:-}"
    
    if [ -z "$SOURCE" ]; then
        echo "Usage: aspera-upload <source-file> [destination-path]"
        return 1
    fi
    
    if [ -z "$DEST" ]; then
        DEST="$TRANSFER_HOME/"
    fi
    
    $ASCP_BIN -P $SSH_PORT -l 1000M -i $SSH_KEY \
        "$SOURCE" "${TRANSFER_USER}@${SERVER_IP}:${DEST}"
}

# Alias for Aspera download
aspera-download() {
    local SOURCE="$1"
    local DEST="${2:-.}"
    
    if [ -z "$SOURCE" ]; then
        echo "Usage: aspera-download <remote-file> [local-destination]"
        return 1
    fi
    
    $ASCP_BIN -P $SSH_PORT -l 1000M -i $SSH_KEY \
        "${TRANSFER_USER}@${SERVER_IP}:${SOURCE}" "$DEST"
}

# Alias for Aspera upload with progress
aspera-upload-progress() {
    local SOURCE="$1"
    local DEST="${2:-$TRANSFER_HOME/}"
    
    if [ -z "$SOURCE" ]; then
        echo "Usage: aspera-upload-progress <source-file> [destination-path]"
        return 1
    fi
    
    $ASCP_BIN -P $SSH_PORT -l 1000M -T -i $SSH_KEY \
        "$SOURCE" "${TRANSFER_USER}@${SERVER_IP}:${DEST}"
}

# Alias for SSH to server
aspera-ssh() {
    ssh -i $SSH_KEY -p $SSH_PORT ${TRANSFER_USER}@${SERVER_IP}
}

# Alias for listing remote files
aspera-ls() {
    local PATH="${1:-$TRANSFER_HOME}"
    ssh -i $SSH_KEY -p $SSH_PORT ${TRANSFER_USER}@${SERVER_IP} "ls -lh $PATH"
}

# Show configuration
aspera-config() {
    echo "Aspera Client Configuration:"
    echo "  Server: $SERVER_HOSTNAME ($SERVER_IP)"
    echo "  User: $TRANSFER_USER"
    echo "  SSH Key: $SSH_KEY"
    echo "  Transfer Home: $TRANSFER_HOME"
}

echo "Aspera aliases loaded. Available commands:"
echo "  aspera-upload <file> [dest]       - Upload file to server"
echo "  aspera-download <file> [dest]     - Download file from server"
echo "  aspera-upload-progress <file>     - Upload with progress display"
echo "  aspera-ssh                        - SSH to server"
echo "  aspera-ls [path]                  - List remote files"
echo "  aspera-config                     - Show configuration"
EOF
    
    chmod +x "$ALIAS_FILE"
    
    # Add to bashrc if not already present
    if ! grep -q "aspera-aliases.sh" "$HOME/.bashrc" 2>/dev/null; then
        echo "" >> "$HOME/.bashrc"
        echo "# Aspera Client Aliases" >> "$HOME/.bashrc"
        echo "[ -f ~/.aspera-client/aspera-aliases.sh ] && source ~/.aspera-client/aspera-aliases.sh" >> "$HOME/.bashrc"
        print_success "Aliases added to ~/.bashrc"
    fi
    
    print_info "To use aliases now, run: source ~/.aspera-client/aspera-aliases.sh"
}

# Function to display summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "  Aspera Client Configuration Complete"
    echo "=========================================="
    echo ""
    echo "Server: $SERVER_HOSTNAME ($SERVER_PRIVATE_IP)"
    echo "Transfer User: $TRANSFER_USER"
    echo "SSH Key: $SSH_KEY_PATH"
    echo "Configuration: $CLIENT_CONFIG_DIR"
    echo ""
    echo "Quick Start Commands:"
    echo ""
    echo "1. Load aliases:"
    echo "   source ~/.aspera-client/aspera-aliases.sh"
    echo ""
    echo "2. Upload a file:"
    echo "   aspera-upload /path/to/file"
    echo ""
    echo "3. Download a file:"
    echo "   aspera-download /aspera/data/transfer-user/file"
    echo ""
    echo "4. SSH to server:"
    echo "   aspera-ssh"
    echo ""
    echo "5. Run validation:"
    echo "   ./aspera-validate.sh"
    echo ""
}

# Main execution

# Splash Screen
print_splash() {
    echo -e "${BLUE}"
    echo "  ___ ____  __  __   _____                      _     _          _         "
    echo " |_ _| __ )|  \/  | | ____|_  ___ __   ___ _ __| |_  | |    __ _| |__  ___ "
    echo "  | ||  _ \| |\/| | |  _| \ \/ / '_ \ / _ \ '__| __| | |   / _\` | '_ \/ __|"
    echo "  | || |_) | |  | | | |___ >  <| |_) |  __/ |  | |_  | |__| (_| | |_) \__ \\"
    echo " |___|____/|_|  |_| |_____/_/\_\ .__/ \___|_|   \__| |_____\__,_|_.__/|___/"
    echo "                               |_|                                         "
    echo -e "${NC}"
    echo ""
}

main() {
    print_splash
    print_info "Starting Aspera client configuration..."
    echo ""
    
    check_user
    fetch_config_from_cos
    validate_config_file
    check_aspera_client
    parse_server_config
    test_connectivity
    setup_ssh_key
    copy_ssh_key_to_server
    test_ssh_auth
    create_client_config
    create_aliases
    display_summary
    
    print_success "Configuration completed successfully!"
}

# Run main function
main "$@"

# Made with Bob
