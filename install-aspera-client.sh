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
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Progress tracking
STEP=0
TOTAL_STEPS=8

# Configuration variables
ASPERA_VERSION="4.2.19.956"
ASPERA_PACKAGE="ibm-aspera-connect_${ASPERA_VERSION}-HEAD_linux_x86_64.tar.gz"
ASPERA_DOWNLOAD_URL="https://d3gcli72yxqn2z.cloudfront.net/downloads/connect/latest/bin/${ASPERA_PACKAGE}"
ASPERA_INSTALL_DIR="$HOME/.aspera/connect"

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
    
    # Detect package manager
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
        print_info "Package manager: apt (Debian/Ubuntu)"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        print_info "Package manager: yum (RHEL/CentOS)"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        print_info "Package manager: dnf (RHEL/CentOS/Fedora)"
    else
        print_error "Unsupported OS. Neither apt nor yum/dnf found."
        exit 1
    fi
}

# Function to install dependencies
install_dependencies() {
    print_info "Installing required dependencies..."

    # Check if sudo is available
    if ! command -v sudo &> /dev/null; then
        print_error "sudo is not available. Please install dependencies manually."
        exit 1
    fi

    if [ "$PKG_MANAGER" = "apt" ]; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq \
            wget \
            curl \
            netcat-openbsd \
            openssh-client \
            rsync \
            python3 \
            bc \
            jq
    elif [ "$PKG_MANAGER" = "yum" ] || [ "$PKG_MANAGER" = "dnf" ]; then
        # RHEL/CentOS/Rocky equivalents
        sudo $PKG_MANAGER install -y -q \
            wget \
            curl \
            nc \
            openssh-clients \
            rsync \
            tar \
            procps-ng \
            python3 \
            bc \
            jq
    fi

    # awscli is installed separately because the distro-provided package is
    # unavailable on Ubuntu 24.04+ and most RHEL default repos.
    install_awscli || print_warning "awscli could not be installed; COS piggyback will be unavailable."

    print_success "Dependencies installed successfully"
}

# Robust awscli installer — tries multiple methods, returns 0 if `aws` is on PATH.
# Client runs as a regular user, so we use sudo for system-level methods.
install_awscli() {
    if command -v aws &> /dev/null; then
        return 0
    fi

    # 1. Native package manager
    case "${PKG_MANAGER:-}" in
        apt)     sudo apt-get install -y -qq awscli >/dev/null 2>&1 || true ;;
        yum|dnf) sudo $PKG_MANAGER install -y -q awscli >/dev/null 2>&1 || true ;;
    esac
    command -v aws &> /dev/null && return 0

    # 2. pip3 --user (no sudo needed; respects PEP 668 via --break-system-packages)
    if command -v pip3 &> /dev/null; then
        pip3 install --quiet --user --break-system-packages awscli >/dev/null 2>&1 || true
    fi
    # Add ~/.local/bin to PATH for current shell so subsequent calls find aws
    [ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"
    command -v aws &> /dev/null && return 0

    # 3. pip --user
    if command -v pip &> /dev/null; then
        pip install --quiet --user --break-system-packages awscli >/dev/null 2>&1 || true
    fi
    command -v aws &> /dev/null && return 0

    # 4. Bootstrap pip via ensurepip --user, then install
    if command -v python3 &> /dev/null; then
        python3 -m ensurepip --user >/dev/null 2>&1 || true
        python3 -m pip install --quiet --user --break-system-packages awscli >/dev/null 2>&1 || true
    fi
    command -v aws &> /dev/null && return 0

    return 1
}

# Function to download Aspera Connect
download_aspera() {
    print_info "Acquiring IBM Aspera Connect ${ASPERA_VERSION}..."

    # Prefer /tmp, but fall back to a user-owned dir if the existing file
    # there is not writable (common when a previous sudo'd run left a
    # root-owned copy and /tmp's sticky bit blocks deletion).
    DOWNLOAD_DIR="/tmp"
    if [ -e "/tmp/${ASPERA_PACKAGE}" ] && [ ! -w "/tmp/${ASPERA_PACKAGE}" ]; then
        DOWNLOAD_DIR="$HOME/.cache/aspera-install"
        mkdir -p "$DOWNLOAD_DIR"
        print_warning "/tmp/${ASPERA_PACKAGE} is not writable; using $DOWNLOAD_DIR instead."
    fi
    cd "$DOWNLOAD_DIR"

    if [ -f "${ASPERA_PACKAGE}" ] && [ -s "${ASPERA_PACKAGE}" ]; then
        print_success "Package already present at ${DOWNLOAD_DIR}/${ASPERA_PACKAGE}. Skipping download."
        return 0
    fi

    # Remove any stale zero-byte file left from an interrupted download
    [ -f "${ASPERA_PACKAGE}" ] && rm -f "${ASPERA_PACKAGE}" 2>/dev/null || true

    wget -q --show-progress "${ASPERA_DOWNLOAD_URL}" || {
        print_error "Failed to download Aspera Connect"
        exit 1
    }

    print_success "Aspera Connect downloaded successfully"
}

# Function to extract and install Aspera Connect
install_aspera() {
    print_info "Installing IBM Aspera Connect..."
    cd "${DOWNLOAD_DIR:-/tmp}"
    
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
    chmod 600 ~/.aws/credentials

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    local cos_error
    # Pass --endpoint-url directly; the config s3= block is not honoured by aws s3 cp
    if cos_error=$(aws s3 cp \
            --endpoint-url "${COS_ENDPOINT}" \
            --no-verify-ssl \
            "s3://${COS_BUCKET}/keys/aspera_rsa" "$KEY_PATH" 2>&1); then
        chmod 600 "$KEY_PATH"
        print_success "SSH key downloaded from COS successfully!"

        print_info "Removing SSH key from COS for security..."
        aws s3 rm \
            --endpoint-url "${COS_ENDPOINT}" \
            --no-verify-ssl \
            "s3://${COS_BUCKET}/keys/aspera_rsa" || print_warning "Failed to remove key from COS."
    else
        print_warning "Failed to download SSH key from COS. Will generate a new one."
        print_warning "COS error: ${cos_error}"
        rm -f "$KEY_PATH"
    fi

    # Always clean up local credentials regardless of outcome
    rm -rf ~/.aws
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
        echo -e "  ${BOLD}Public key${NC} ${DIM}— copy this to ~/.ssh/authorized_keys on the server${NC}"
        echo -e "${DIM}  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄${NC}"
        cat "${KEY_PATH}.pub"
        echo -e "${DIM}  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄${NC}"
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

display_usage() {
    echo -e "${BOLD}  Quick Reference${NC}"
    echo -e "${DIM}  ──────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${CYAN}Upload${NC}"
    echo -e "  ${DIM}ascp -P 22 -l 1000M -i ~/.ssh/aspera_transfer_key \\${NC}"
    echo -e "  ${DIM}  /path/to/file user@server:/destination/${NC}"
    echo ""
    echo -e "  ${CYAN}Download${NC}"
    echo -e "  ${DIM}ascp -P 22 -l 1000M -i ~/.ssh/aspera_transfer_key \\${NC}"
    echo -e "  ${DIM}  user@server:/path/to/file /local/destination/${NC}"
    echo ""
    echo -e "  ${CYAN}Recursive directory${NC}"
    echo -e "  ${DIM}ascp -P 22 -l 1000M -r -i ~/.ssh/aspera_transfer_key \\${NC}"
    echo -e "  ${DIM}  /path/to/directory user@server:/destination/${NC}"
    echo ""
    echo -e "  ${BOLD}Common flags${NC}"
    echo -e "  ${DIM}──────────────────────────────────────────────────────${NC}"
    echo -e "  ${CYAN}-P 22   ${NC}  SSH port"
    echo -e "  ${CYAN}-l 1000M${NC}  Target transfer rate"
    echo -e "  ${CYAN}-i <key>${NC}  SSH private key"
    echo -e "  ${CYAN}-T      ${NC}  Show throughput statistics"
    echo -e "  ${CYAN}-r      ${NC}  Recursive (directories)"
    echo -e "  ${CYAN}-k 1    ${NC}  Resume interrupted transfers"
    echo -e "  ${CYAN}-v      ${NC}  Verbose / debug output"
    echo ""
}

display_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}  ║${NC}  ${BOLD}${GREEN}✔  Installation Complete${NC}                               ${BOLD}${GREEN}║${NC}"
    echo -e "${BOLD}${GREEN}  ╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}  ║${NC}"
    echo -e "${GREEN}  ║${NC}  ${DIM}Directory${NC}   ${ASPERA_INSTALL_DIR}"
    echo -e "${GREEN}  ║${NC}  ${DIM}Binary${NC}      ${ASPERA_INSTALL_DIR}/bin/ascp"
    echo -e "${GREEN}  ║${NC}  ${DIM}SSH Key${NC}     $HOME/.ssh/aspera_transfer_key"
    echo -e "${GREEN}  ║${NC}"
    echo -e "${GREEN}  ║${NC}  ${BOLD}Next steps${NC}"
    echo -e "${GREEN}  ║${NC}"
    echo -e "${GREEN}  ║${NC}  ${CYAN}1.${NC} Apply PATH changes"
    echo -e "${GREEN}  ║${NC}     ${DIM}source ~/.bashrc${NC}"
    echo -e "${GREEN}  ║${NC}"
    echo -e "${GREEN}  ║${NC}  ${CYAN}2.${NC} Copy public key to the Aspera server"
    echo -e "${GREEN}  ║${NC}     ${DIM}cat ~/.ssh/aspera_transfer_key.pub${NC}"
    echo -e "${GREEN}  ║${NC}"
    echo -e "${GREEN}  ║${NC}  ${CYAN}3.${NC} Run a test transfer"
    echo -e "${GREEN}  ║${NC}     ${DIM}ascp -P 22 -l 1000M -i ~/.ssh/aspera_transfer_key \\${NC}"
    echo -e "${GREEN}  ║${NC}     ${DIM}  /tmp/aspera-test-10mb user@server:/destination/${NC}"
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
    echo -e "${BOLD}${BLUE}  ║${NC}   ${BOLD}IBM Aspera Connect Client${NC}  ${DIM}·${NC}  Automated Installer   ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}  ║${NC}   ${DIM}Ubuntu / RHEL / CentOS / Fedora     v 1.0.0${NC}          ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}  ║${NC}                                                      ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

main() {
    print_splash
    local SERVER_IP="${1:-}"

    print_step "Pre-flight Checks"
    check_user
    detect_os

    print_step "Install Dependencies"
    install_dependencies

    print_step "Download Aspera Connect"
    download_aspera

    print_step "Install Aspera Connect"
    install_aspera

    print_step "Configure PATH"
    configure_path

    print_step "SSH Key Setup"
    download_key_from_cos
    generate_ssh_key

    print_step "Verify Installation"
    verify_installation

    print_step "Create Test Assets"
    create_test_file

    if [ -n "$SERVER_IP" ]; then
        echo ""
        echo -e "${BOLD}${BLUE}  ──────────────────────────────────────────────────────${NC}"
        echo -e "  ${BOLD}${BLUE}[+]${NC}  ${BOLD}Connectivity Test${NC}"
        echo -e "${BOLD}${BLUE}  ──────────────────────────────────────────────────────${NC}"
        echo ""
        test_connectivity "$SERVER_IP"
    fi

    display_summary
    display_usage
}

# Run main function
main "$@"

# Made with Bob
