#!/bin/bash
################################################################################
# IBM Aspera Connect Client Installation Script
# Version: 1.0.0
# Date: 2026-05-07
# Description: Automated installation of IBM Aspera Connect Client on Ubuntu 22.04
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
ASPERA_VERSION="4.2.19.956"
ASPERA_PACKAGE="ibm-aspera-connect_${ASPERA_VERSION}-HEAD_linux_x86_64.tar.gz"
ASPERA_DOWNLOAD_URL="https://d3gcli72yxqn2z.cloudfront.net/downloads/connect/latest/bin/${ASPERA_PACKAGE}"
ASPERA_INSTALL_DIR="$HOME/.aspera/connect"

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
        print_info "Run as regular user: ./install-aspera-client.sh"
        exit 1
    fi
}

# Function to detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        print_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    
    print_info "Detected OS: $OS $OS_VERSION"
}

# Function to install dependencies
install_dependencies() {
    print_info "Installing required dependencies..."
    
    # Check if sudo is available
    if ! command -v sudo &> /dev/null; then
        print_error "sudo is not available. Please install dependencies manually."
        exit 1
    fi
    
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        wget \
        curl \
        netcat-openbsd \
        openssh-client \
        rsync \
        awscli
    
    print_success "Dependencies installed successfully"
}

# Function to download Aspera Connect
download_aspera() {
    print_info "Downloading IBM Aspera Connect ${ASPERA_VERSION}..."
    cd /tmp
    
    if [ -f "${ASPERA_PACKAGE}" ]; then
        print_warning "Package already exists. Removing old version..."
        rm -f "${ASPERA_PACKAGE}"
    fi
    
    wget -q --show-progress "${ASPERA_DOWNLOAD_URL}" || {
        print_error "Failed to download Aspera Connect"
        exit 1
    }
    
    print_success "Aspera Connect downloaded successfully"
}

# Function to extract and install Aspera Connect
install_aspera() {
    print_info "Installing IBM Aspera Connect..."
    cd /tmp
    
    # Extract the archive
    tar -xzf "${ASPERA_PACKAGE}" || {
        print_error "Failed to extract Aspera Connect"
        exit 1
    }
    
    # Find and run the installer
    INSTALLER=$(ls ibm-aspera-connect_*.sh 2>/dev/null | head -1)
    
    if [ -z "$INSTALLER" ]; then
        print_error "Installer script not found after extraction"
        exit 1
    fi
    
    bash "$INSTALLER" || {
        print_error "Failed to run Aspera Connect installer"
        exit 1
    }
    
    print_success "Aspera Connect installed successfully"
}

# Function to configure PATH
configure_path() {
    print_info "Configuring PATH..."
    
    local SHELL_RC=""
    
    # Detect shell and set appropriate RC file
    if [ -n "${BASH_VERSION:-}" ]; then
        SHELL_RC="$HOME/.bashrc"
    elif [ -n "${ZSH_VERSION:-}" ]; then
        SHELL_RC="$HOME/.zshrc"
    else
        SHELL_RC="$HOME/.profile"
    fi
    
    # Check if PATH is already configured
    if grep -q "\.aspera/connect/bin" "$SHELL_RC" 2>/dev/null; then
        print_info "PATH already configured in $SHELL_RC"
    else
        echo "" >> "$SHELL_RC"
        echo "# IBM Aspera Connect" >> "$SHELL_RC"
        echo "export PATH=\$PATH:\$HOME/.aspera/connect/bin" >> "$SHELL_RC"
        print_success "PATH configured in $SHELL_RC"
        print_info "Run 'source $SHELL_RC' to apply changes"
    fi
}

# Function to download key from COS (Piggyback)
download_key_from_cos() {
    local KEY_PATH="$HOME/.ssh/aspera_transfer_key"
    
    if [ -f "$KEY_PATH" ]; then
        print_info "SSH key already exists locally. Skipping COS download."
        return 0
    fi

    if [ -z "${COS_ACCESS_KEY:-}" ] || [ -z "${COS_SECRET_KEY:-}" ] || [ -z "${COS_ENDPOINT:-}" ] || [ -z "${COS_BUCKET:-}" ]; then
        print_info "COS variables not set. Skipping key download from COS."
        return 0
    fi

    print_info "Downloading Aspera SSH key from IBM Cloud Object Storage..."
    
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

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    # Download the key
    if aws s3 cp "s3://${COS_BUCKET}/keys/aspera_rsa" "$KEY_PATH"; then
        chmod 600 "$KEY_PATH"
        print_success "SSH key downloaded from COS successfully!"
        
        # Cleanup from COS for security
        print_info "Removing SSH key from COS for security..."
        aws s3 rm "s3://${COS_BUCKET}/keys/aspera_rsa" || print_warning "Failed to remove key from COS."
        
        # Cleanup local AWS credentials
        rm -rf ~/.aws
    else
        print_warning "Failed to download SSH key from COS. Will generate a new one."
    fi
}

# Function to generate SSH key for transfers
generate_ssh_key() {
    print_info "Checking SSH key for Aspera transfers..."
    
    local KEY_PATH="$HOME/.ssh/aspera_transfer_key"
    
    if [ -f "$KEY_PATH" ]; then
        print_info "SSH key already exists: $KEY_PATH"
    else
        print_info "Generating SSH key for Aspera transfers..."
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        
        ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "aspera-transfer-$(hostname)" || {
            print_error "Failed to generate SSH key"
            exit 1
        }
        
        chmod 600 "$KEY_PATH"
        chmod 644 "${KEY_PATH}.pub"
        
        print_success "SSH key generated: $KEY_PATH"
        echo ""
        print_info "Public key content (copy this to server):"
        echo "----------------------------------------"
        cat "${KEY_PATH}.pub"
        echo "----------------------------------------"
    fi
}

# Function to verify installation
verify_installation() {
    print_info "Verifying installation..."
    
    # Check if ascp exists
    if [ -f "${ASPERA_INSTALL_DIR}/bin/ascp" ]; then
        print_success "ascp binary found"
        "${ASPERA_INSTALL_DIR}/bin/ascp" --version
    else
        print_error "ascp binary not found"
        exit 1
    fi
    
    # Check if directory structure is correct
    if [ -d "${ASPERA_INSTALL_DIR}" ]; then
        print_success "Installation directory exists: ${ASPERA_INSTALL_DIR}"
    else
        print_error "Installation directory not found"
        exit 1
    fi
}

# Function to test connectivity (optional)
test_connectivity() {
    local SERVER_IP="${1:-}"
    
    if [ -z "$SERVER_IP" ]; then
        print_info "Skipping connectivity test (no server IP provided)"
        return 0
    fi
    
    print_info "Testing connectivity to Aspera server: $SERVER_IP"
    
    # Test ping
    if ping -c 3 -W 2 "$SERVER_IP" &>/dev/null; then
        print_success "Ping to $SERVER_IP successful"
    else
        print_warning "Ping to $SERVER_IP failed"
    fi
    
    # Test SSH port
    if nc -zv -w 3 "$SERVER_IP" 22 &>/dev/null; then
        print_success "SSH port (22) is accessible"
    else
        print_warning "SSH port (22) is not accessible"
    fi
    
    # Test Aspera Node API port
    if nc -zv -w 3 "$SERVER_IP" 9092 &>/dev/null; then
        print_success "Aspera Node API port (9092) is accessible"
    else
        print_warning "Aspera Node API port (9092) is not accessible"
    fi
}

# Function to create test file
create_test_file() {
    print_info "Creating test file for transfer validation..."
    
    local TEST_FILE="/tmp/aspera-test-10mb"
    
    if [ -f "$TEST_FILE" ]; then
        print_info "Test file already exists"
    else
        dd if=/dev/urandom of="$TEST_FILE" bs=1M count=10 2>/dev/null
        print_success "Test file created: $TEST_FILE (10MB)"
    fi
}

# Function to display usage examples
display_usage() {
    echo ""
    echo "=========================================="
    echo "  Aspera Connect Client Usage Examples"
    echo "=========================================="
    echo ""
    echo "Basic Upload:"
    echo "  ~/.aspera/connect/bin/ascp -P 22 -l 1000M -i ~/.ssh/aspera_transfer_key \\"
    echo "    /path/to/file user@server:/destination/"
    echo ""
    echo "Basic Download:"
    echo "  ~/.aspera/connect/bin/ascp -P 22 -l 1000M -i ~/.ssh/aspera_transfer_key \\"
    echo "    user@server:/path/to/file /local/destination/"
    echo ""
    echo "Recursive Directory Transfer:"
    echo "  ~/.aspera/connect/bin/ascp -P 22 -l 1000M -r -i ~/.ssh/aspera_transfer_key \\"
    echo "    /path/to/directory user@server:/destination/"
    echo ""
    echo "With Progress Display:"
    echo "  ~/.aspera/connect/bin/ascp -P 22 -l 1000M -T -i ~/.ssh/aspera_transfer_key \\"
    echo "    /path/to/file user@server:/destination/"
    echo ""
    echo "Common Options:"
    echo "  -P 22          : SSH port (use 22 for standard SSH)"
    echo "  -l 1000M       : Target transfer rate (1000 Mbps)"
    echo "  -i <key>       : SSH private key for authentication"
    echo "  -T             : Display throughput statistics"
    echo "  -r             : Recursive (for directories)"
    echo "  -k 1           : Resume interrupted transfers"
    echo "  -v             : Verbose output for debugging"
    echo ""
}

# Function to display summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "  Aspera Connect Client Installation Complete"
    echo "=========================================="
    echo ""
    echo "Installation Directory: ${ASPERA_INSTALL_DIR}"
    echo "Binary Location: ${ASPERA_INSTALL_DIR}/bin/ascp"
    echo "SSH Key: $HOME/.ssh/aspera_transfer_key"
    echo ""
    echo "Next Steps:"
    echo "1. Copy SSH public key to Aspera server:"
    echo "   cat ~/.ssh/aspera_transfer_key.pub"
    echo "   # Then add to server: ~/.ssh/authorized_keys"
    echo ""
    echo "2. Test connectivity to server:"
    echo "   ping <server-ip>"
    echo "   nc -zv <server-ip> 22"
    echo ""
    echo "3. Test file transfer:"
    echo "   ~/.aspera/connect/bin/ascp -P 22 -l 1000M -i ~/.ssh/aspera_transfer_key \\"
    echo "     /tmp/aspera-test-10mb user@server:/destination/"
    echo ""
    echo "4. Apply PATH changes:"
    echo "   source ~/.bashrc  # or ~/.zshrc"
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
    local SERVER_IP="${1:-}"
    
    print_info "Starting IBM Aspera Connect Client installation..."
    echo ""
    
    check_user
    detect_os
    install_dependencies
    download_aspera
    install_aspera
    configure_path
    download_key_from_cos
    generate_ssh_key
    verify_installation
    create_test_file
    
    if [ -n "$SERVER_IP" ]; then
        test_connectivity "$SERVER_IP"
    fi
    
    display_summary
    display_usage
    
    print_success "Installation completed successfully!"
    echo ""
    print_info "To copy your SSH public key to the server, run:"
    echo "  ssh-copy-id -i ~/.ssh/aspera_transfer_key.pub user@server"
}

# Run main function
main "$@"

# Made with Bob
