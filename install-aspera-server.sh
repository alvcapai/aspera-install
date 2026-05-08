#!/bin/bash
################################################################################
# IBM Aspera HSTS Server Installation Script
# Version: 1.0.0
# Date: 2026-05-07
# Description: Automated installation of IBM Aspera HSTS on Ubuntu 22.04
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
ASPERA_VERSION="4.4.7.2224"
ASPERA_PACKAGE_DEB="ibm-aspera-hsts-${ASPERA_VERSION}-linux-64-release.deb"
ASPERA_PACKAGE_RPM="ibm-aspera-hsts-${ASPERA_VERSION}-linux-64-release.rpm"
ASPERA_INSTALL_DIR="/opt/aspera"
ASPERA_DATA_DIR="/aspera/data"
ASPERA_CACHE_DIR="/aspera/cache"
ASPERA_LOG_DIR="/aspera/logs"

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

# Function to detect OS and package manager
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
        ASPERA_PACKAGE="${ASPERA_PACKAGE_DEB}"
        print_info "Package manager: apt (Debian/Ubuntu)"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        ASPERA_PACKAGE="${ASPERA_PACKAGE_RPM}"
        print_info "Package manager: yum (RHEL/CentOS)"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        ASPERA_PACKAGE="${ASPERA_PACKAGE_RPM}"
        print_info "Package manager: dnf (RHEL/CentOS/Fedora)"
    else
        print_error "No supported package manager found (apt, yum, or dnf)"
        exit 1
    fi
}

# Function to update system
update_system() {
    print_info "Updating system packages..."
    
    case "$PKG_MANAGER" in
        apt)
            apt-get update -qq
            apt-get upgrade -y -qq
            ;;
        yum)
            yum update -y -q
            ;;
        dnf)
            dnf update -y -q
            ;;
    esac
    
    print_success "System updated successfully"
}

# Function to install dependencies
install_dependencies() {
    print_info "Installing required dependencies..."
    
    case "$PKG_MANAGER" in
        apt)
            apt-get install -y -qq \
                wget \
                curl \
                net-tools \
                openssh-server \
                ufw \
                iptables \
                rsync \
                openssl \
                awscli
            ;;
        yum|dnf)
            $PKG_MANAGER install -y -q \
                wget \
                curl \
                net-tools \
                openssh-server \
                firewalld \
                iptables \
                rsync \
                openssl \
                awscli
            ;;
    esac
    
    print_success "Dependencies installed successfully"
}

# Function to download Aspera HSTS
download_aspera() {
    print_info "Attempting to acquire IBM Aspera HSTS ${ASPERA_VERSION}..."
    cd /tmp
    
    if [ -f "${ASPERA_PACKAGE}" ]; then
        print_success "Package ${ASPERA_PACKAGE} already exists locally. Skipping download."
        return 0
    fi
    
    # Try custom COS bucket if variables are set
    if [ -n "${ASPERA_COS_BIN_URL:-}" ] || ([ -n "${COS_ACCESS_KEY:-}" ] && [ -n "${COS_ENDPOINT:-}" ]); then
        print_info "COS configuration detected. Attempting to download from internal storage..."
        
        # Ensure AWS CLI is installed
        if ! command -v aws &> /dev/null; then
            print_warning "awscli not found. Installing temporarily to download package..."
            if [ "$PKG_MANAGER" = "apt" ]; then
                apt-get install -y -qq awscli
            else
                yum install -y awscli
            fi
        fi
        
        # Setup temp credentials if necessary
        if [ -n "${COS_ACCESS_KEY:-}" ]; then
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
            
            local S3_TARGET="s3://${COS_BUCKET}/binaries/${ASPERA_PACKAGE}"
            if [ -n "${ASPERA_COS_BIN_URL:-}" ]; then
                S3_TARGET="${ASPERA_COS_BIN_URL}"
            fi
            
            print_info "Downloading from ${S3_TARGET}..."
            if aws s3 cp "${S3_TARGET}" "/tmp/${ASPERA_PACKAGE}"; then
                print_success "Aspera HSTS downloaded successfully from internal COS"
                return 0
            else
                print_error "Failed to download from COS: ${S3_TARGET}"
            fi
        fi
    fi
    
    # Try public web URL if provided
    if [ -n "${ASPERA_DOWNLOAD_URL:-}" ]; then
        print_info "Downloading from custom URL: ${ASPERA_DOWNLOAD_URL}"
        if wget -q --show-progress "${ASPERA_DOWNLOAD_URL}" -O "/tmp/${ASPERA_PACKAGE}"; then
            print_success "Aspera HSTS downloaded successfully"
            return 0
        fi
    fi
    
    print_error "Could not acquire Aspera HSTS package (${ASPERA_PACKAGE})."
    print_error "IBM Fix Central requires IBMid entitlement and cannot be scraped directly."
    print_error "Please download the package manually and place it in /tmp/${ASPERA_PACKAGE}"
    print_error "OR set ASPERA_DOWNLOAD_URL environment variable to a valid direct link."
    print_error "OR configure COS credentials and place the binary in s3://\${COS_BUCKET}/binaries/"
    exit 1
}

# Function to install Aspera HSTS
install_aspera() {
    print_info "Installing IBM Aspera HSTS..."
    cd /tmp
    
    case "$PKG_MANAGER" in
        apt)
            dpkg -i "${ASPERA_PACKAGE}" || {
                print_error "Failed to install Aspera HSTS"
                exit 1
            }
            ;;
        yum|dnf)
            $PKG_MANAGER install -y "${ASPERA_PACKAGE}" || {
                print_error "Failed to install Aspera HSTS"
                exit 1
            }
            ;;
    esac
    
    print_success "Aspera HSTS installed successfully"
}

# Function to create directories
create_directories() {
    print_info "Creating Aspera directories..."
    
    mkdir -p "${ASPERA_DATA_DIR}"
    mkdir -p "${ASPERA_CACHE_DIR}"
    mkdir -p "${ASPERA_LOG_DIR}"
    
    chown -R aspera:aspera "${ASPERA_DATA_DIR}"
    chown -R aspera:aspera "${ASPERA_CACHE_DIR}"
    chown -R aspera:aspera "${ASPERA_LOG_DIR}"
    
    chmod 755 "${ASPERA_DATA_DIR}"
    chmod 755 "${ASPERA_CACHE_DIR}"
    chmod 755 "${ASPERA_LOG_DIR}"
    
    print_success "Directories created successfully"
}

# Function to configure firewall
configure_firewall() {
    print_info "Configuring firewall rules..."
    
    case "$PKG_MANAGER" in
        apt)
            # Enable UFW if not already enabled
            if ! ufw status | grep -q "Status: active"; then
                print_info "Enabling UFW firewall..."
                ufw --force enable
            fi
            
            # Allow SSH
            ufw allow 22/tcp comment 'SSH'
            
            # Allow Aspera ports
            ufw allow 33001/tcp comment 'Aspera TCP'
            ufw allow 33001:33050/udp comment 'Aspera UDP FASP'
            ufw allow 443/tcp comment 'HTTPS Web UI'
            
            # Reload firewall
            ufw reload
            ;;
        yum|dnf)
            # Enable and start firewalld
            systemctl enable firewalld
            systemctl start firewalld
            
            # Allow SSH
            firewall-cmd --permanent --add-service=ssh
            
            # Allow Aspera ports
            firewall-cmd --permanent --add-port=33001/tcp
            firewall-cmd --permanent --add-port=33001-33050/udp
            firewall-cmd --permanent --add-port=443/tcp
            
            # Reload firewall
            firewall-cmd --reload
            ;;
    esac
    
    print_success "Firewall configured successfully"
}

# Function to generate encryption token
generate_token() {
    print_info "Generating encryption token..."
    TOKEN=$(openssl rand -base64 32)
    echo "${TOKEN}"
}

# Function to create basic aspera.conf
create_aspera_conf() {
    print_info "Creating basic aspera.conf configuration..."
    
    local TOKEN=$(generate_token)
    local CONF_FILE="${ASPERA_INSTALL_DIR}/etc/aspera.conf"
    
    # Backup existing config if present
    if [ -f "${CONF_FILE}" ]; then
        cp "${CONF_FILE}" "${CONF_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    cat > "${CONF_FILE}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<CONF version="2">
  <!-- Global Settings -->
  <server>
    <transfer>
      <!-- Cache directory -->
      <cache_dir>${ASPERA_CACHE_DIR}</cache_dir>
      
      <!-- Throughput limits -->
      <target_rate_kbps>10000000</target_rate_kbps>
      <min_rate_kbps>100000</min_rate_kbps>
      
      <!-- Connection limits -->
      <max_sessions>100</max_sessions>
      
      <!-- Timeout -->
      <idle_timeout>300</idle_timeout>
      
      <!-- Encryption -->
      <cipher>aes-256</cipher>
      
      <!-- Authentication token -->
      <token_encryption_key>${TOKEN}</token_encryption_key>
    </transfer>
    
    <!-- Network settings -->
    <network>
      <!-- UDP ports for FASP -->
      <udp_port_range>
        <min>33001</min>
        <max>33050</max>
      </udp_port_range>
      
      <!-- TCP port -->
      <tcp_port>33001</tcp_port>
    </network>
    
    <!-- Logging -->
    <logging>
      <level>info</level>
      <file>${ASPERA_LOG_DIR}/aspera.log</file>
      <max_size>100M</max_size>
      <rotate>10</rotate>
    </logging>
    
    <!-- Security -->
    <security>
      <!-- Disable anonymous -->
      <anonymous_user_enabled>false</anonymous_user_enabled>
    </security>
  </server>
  
  <!-- User configuration -->
  <users>
    <user name="aspera">
      <authorization>
        <transfer>
          <read_allowed>true</read_allowed>
          <write_allowed>true</write_allowed>
          <dir_allowed>true</dir_allowed>
        </transfer>
      </authorization>
      <storage>
        <path>${ASPERA_DATA_DIR}</path>
      </storage>
    </user>
  </users>
</CONF>
EOF
    
    chown aspera:aspera "${CONF_FILE}"
    chmod 640 "${CONF_FILE}"
    
    print_success "aspera.conf created successfully"
    print_info "Encryption token: ${TOKEN}"
}

# Function to start Aspera services
start_services() {
    print_info "Starting Aspera services..."
    
    systemctl daemon-reload
    systemctl enable asperanoded
    systemctl restart asperanoded
    
    sleep 5
    
    if systemctl is-active --quiet asperanoded; then
        print_success "Aspera services started successfully"
    else
        print_error "Failed to start Aspera services"
        print_info "Check logs: journalctl -u asperanoded -n 50"
        exit 1
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
    
    # Check service status
    if systemctl is-active --quiet asperanoded; then
        print_success "asperanoded service is running"
    else
        print_error "asperanoded service is not running"
        exit 1
    fi
    
    # Check listening ports
    if netstat -tuln | grep -q ":9092"; then
        print_success "Aspera Node API listening on port 9092"
    else
        print_warning "Aspera Node API not listening on port 9092"
    fi
}

# Function to configure COS and upload SSH key (Piggyback)
configure_cos_and_upload_key() {
    print_info "Configuring COS and generating Aspera SSH key..."
    
    # Ensure aspera-user exists
    if ! id "aspera-user" &>/dev/null; then
        useradd -m -d ${ASPERA_DATA_DIR}/aspera-user -s /bin/bash aspera-user
        mkdir -p ${ASPERA_DATA_DIR}/aspera-user/.ssh
        chown aspera-user:aspera-user ${ASPERA_DATA_DIR}/aspera-user/.ssh
    fi

    # Generate SSH key if not exists
    local SSH_KEY="${ASPERA_DATA_DIR}/aspera-user/.ssh/id_rsa"
    if [ ! -f "$SSH_KEY" ]; then
        sudo -u aspera-user ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -N "" -q
        cat "${SSH_KEY}.pub" >> "${ASPERA_DATA_DIR}/aspera-user/.ssh/authorized_keys"
        chmod 600 "${ASPERA_DATA_DIR}/aspera-user/.ssh/authorized_keys"
    fi

    # Check for COS variables
    if [ -z "${COS_ACCESS_KEY:-}" ] || [ -z "${COS_SECRET_KEY:-}" ] || [ -z "${COS_ENDPOINT:-}" ] || [ -z "${COS_BUCKET:-}" ]; then
        print_warning "COS variables not set. Skipping key upload. Set COS_ACCESS_KEY, COS_SECRET_KEY, COS_ENDPOINT, COS_BUCKET to enable auto-upload."
        return 0
    fi

    # Configure AWS CLI for COS
    print_info "Uploading key to IBM Cloud Object Storage..."
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

    # Upload the key
    aws s3 cp "$SSH_KEY" "s3://${COS_BUCKET}/keys/aspera_rsa" || {
        print_error "Failed to upload SSH key to COS"
        return 1
    }
    
    print_success "SSH key uploaded to s3://${COS_BUCKET}/keys/aspera_rsa successfully!"
}

# Function to display summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "  IBM Aspera HSTS Installation Complete"
    echo "=========================================="
    echo ""
    echo "Installation Directory: ${ASPERA_INSTALL_DIR}"
    echo "Data Directory: ${ASPERA_DATA_DIR}"
    echo "Cache Directory: ${ASPERA_CACHE_DIR}"
    echo "Log Directory: ${ASPERA_LOG_DIR}"
    echo ""
    echo "Configuration File: ${ASPERA_INSTALL_DIR}/etc/aspera.conf"
    echo ""
    echo "Service Status:"
    systemctl status asperanoded --no-pager | head -5
    echo ""
    echo "Next Steps:"
    echo "1. Configure license: ${ASPERA_INSTALL_DIR}/bin/asconfigurator -x \"set_license_key;<YOUR_LICENSE_KEY>\""
    echo "2. Create transfer users: useradd -m -d ${ASPERA_DATA_DIR}/username username"
    echo "3. Test transfers from client"
    echo ""
    echo "Useful Commands:"
    echo "- Check service: systemctl status asperanoded"
    echo "- View logs: journalctl -u asperanoded -f"
    echo "- Check config: ${ASPERA_INSTALL_DIR}/bin/asnodeadmin -c"
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
    print_info "Starting IBM Aspera HSTS installation..."
    echo ""
    
    check_root
    detect_os
    update_system
    install_dependencies
    download_aspera
    install_aspera
    create_directories
    configure_firewall
    create_aspera_conf
    start_services
    verify_installation
    configure_cos_and_upload_key
    display_summary
    
    print_success "Installation completed successfully!"
}

# Run main function
main "$@"

# Made with Bob
