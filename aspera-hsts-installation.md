# Runbook: IBM Aspera HSTS Installation

## 📋 Overview

This runbook provides step-by-step instructions for installing and performing the initial configuration of IBM Aspera High-Speed Transfer Server (HSTS) on a VSI in IBM Cloud VPC.

## ⏱️ Estimated Time

- **Installation**: 30-45 minutes
- **Basic configuration**: 30 minutes
- **Testing**: 15-30 minutes
- **Total**: 1.5-2 hours

## 📋 Prerequisites

### Infrastructure
- [ ] VSI provisioned and accessible via SSH
- [ ] Floating IP assigned to the VSI
- [ ] Security Groups configured
- [ ] Data volume mounted at `/aspera/cache`
- [ ] Network connectivity validated

### Credentials and Licenses
- [ ] Valid IBM Aspera HSTS license
- [ ] Root/sudo access on the VSI
- [ ] SSH key configured

### Required Information
```
VSI Floating IP: _______________
VSI Private IP: _______________
COS Endpoint: _______________
COS Access Key: _______________
COS Secret Key: _______________
COS Bucket Name: _______________
```

## 🚀 Installation

### Quick Installation with Scripts

For automated installation, use the provided scripts:

**Server Installation:**
```bash
# Download and run the server installation script
wget https://raw.githubusercontent.com/your-repo/aspera-cos-ibmcloud/main/02-runbooks/install-aspera-server.sh
chmod +x install-aspera-server.sh
sudo ./install-aspera-server.sh
```

**Client Installation:**
```bash
# Download and run the client installation script
wget https://raw.githubusercontent.com/your-repo/aspera-cos-ibmcloud/main/02-runbooks/install-aspera-client.sh
chmod +x install-aspera-client.sh
./install-aspera-client.sh [server-ip]  # Optional: provide server IP for connectivity test
```

**Script Features:**
- ✅ Automatic OS detection
- ✅ Dependency installation
- ✅ Aspera download and installation
- ✅ Directory structure creation
- ✅ Firewall configuration
- ✅ Basic aspera.conf generation
- ✅ Service startup and verification
- ✅ SSH key generation (client)
- ✅ Connectivity testing (client)

### Manual Installation Steps

If you prefer manual installation or need to customize the process, follow these steps:

### Step 1: Connect to the VSI

```bash
# Connect via SSH
ssh -i ~/.ssh/aspera-key root@<FLOATING_IP>

# Or for Ubuntu
ssh -i ~/.ssh/aspera-key ubuntu@<FLOATING_IP>

# If Ubuntu, switch to root
sudo su -
```

### Step 2: Update Operating System

#### Ubuntu 22.04
```bash
# Update repositories
apt update

# Update packages
apt upgrade -y

# Install dependencies
apt install -y \
  wget \
  curl \
  perl \
  libdigest-md5-perl \
  libaio1 \
  rsync \
  net-tools \
  vim \
  htop \
  iotop

# Reboot if kernel was updated
reboot
```

#### RHEL/CentOS 8
```bash
# Update system
yum update -y

# Install dependencies
yum install -y \
  wget \
  curl \
  perl \
  perl-Digest-MD5 \
  libaio \
  rsync \
  net-tools \
  vim \
  htop \
  iotop

# Reboot if necessary
reboot
```

### Step 3: Download Aspera HSTS

```bash
# Create temporary directory
mkdir -p /tmp/aspera-install
cd /tmp/aspera-install

# Option 1: Direct download (if you have access)
# Note: URL may vary, check with IBM
wget https://d3gcli72yxqn2z.cloudfront.net/downloads/connect/latest/bin/ibm-aspera-hsts-4.4.2.309-linux-64-release.rpm

# Option 2: Upload local file
# From your local machine:
# scp -i ~/.ssh/aspera-key ibm-aspera-hsts-*.rpm root@<FLOATING_IP>:/tmp/aspera-install/

# Option 3: Via IBM Aspera Download Portal
# 1. Access: https://www.ibm.com/aspera/downloads
# 2. Log in with IBM ID
# 3. Download IBM Aspera HSTS for Linux
# 4. Upload to the VSI
```

### Step 4: Install Aspera HSTS

#### Ubuntu/Debian
```bash
# Convert RPM to DEB (if necessary)
apt install -y alien
alien -d ibm-aspera-hsts-*.rpm

# Install
dpkg -i ibm-aspera-hsts_*.deb

# Resolve dependencies if there is an error
apt install -f -y
```

#### RHEL/CentOS
```bash
# Install RPM
rpm -ivh ibm-aspera-hsts-*.rpm

# Or using yum
yum localinstall -y ibm-aspera-hsts-*.rpm
```

### Step 5: Verify Installation

```bash
# Check installed version
/opt/aspera/bin/ascp -A

# Check services
systemctl status asperanoded
systemctl status asperacentral

# Check created directories
ls -la /opt/aspera/
ls -la /opt/aspera/etc/
ls -la /opt/aspera/var/

# Check aspera user created
id aspera
```

## ⚙️ Initial Configuration

### Step 6: Configure License

#### Method 1: License File
```bash
# Copy license file
# From your local machine:
scp -i ~/.ssh/aspera-key aspera-license.txt root@<FLOATING_IP>:/opt/aspera/etc/

# On the VSI:
chmod 644 /opt/aspera/etc/aspera-license.txt
chown root:root /opt/aspera/etc/aspera-license.txt

# Restart service
systemctl restart asperanoded

# Verify license
/opt/aspera/bin/ascp -A
```

#### Method 2: Activation Key
```bash
# Activate with key
/opt/aspera/bin/aslicense --activate <ACTIVATION_KEY>

# Check status
/opt/aspera/bin/aslicense --show

# Expected output example:
# License Type: Perpetual
# Licensed To: Company Name
# Max Throughput: 10 Gbps
# Max Connections: 100
```

### Step 7: Configure Directories

```bash
# Create directory structure
mkdir -p /aspera/data
mkdir -p /aspera/cache
mkdir -p /aspera/logs
mkdir -p /aspera/config

# Set permissions
chown -R aspera:aspera /aspera/
chmod 755 /aspera/data
chmod 755 /aspera/cache
chmod 755 /aspera/logs

# Verify cache volume mount
df -h /aspera/cache
```

### Step 8: Configure aspera.conf

```bash
# Backup original configuration
cp /opt/aspera/etc/aspera.conf /opt/aspera/etc/aspera.conf.backup

# Edit configuration
vim /opt/aspera/etc/aspera.conf
```

#### Recommended Minimum Configuration

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CONF version="2">
  <!-- Global Settings -->
  <server>
    <transfer>
      <!-- Cache directory -->
      <cache_dir>/aspera/cache</cache_dir>
      
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
      <token_encryption_key>CHANGE_THIS_TO_RANDOM_STRING</token_encryption_key>
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
      <file>/aspera/logs/aspera.log</file>
      <max_size>100M</max_size>
      <rotate>10</rotate>
    </logging>
    
    <!-- Security -->
    <security>
      <!-- Allowed IPs (whitelist) -->
      <allowed_clients>
        <client>203.0.113.0/24</client>
        <client>198.51.100.0/24</client>
      </allowed_clients>
      
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
        <path>/aspera/data</path>
      </storage>
    </user>
  </users>
</CONF>
```

#### Generate Secure Encryption Token

```bash
# Generate random string for token_encryption_key
openssl rand -base64 32

# Copy output and replace in aspera.conf
# Example: CHANGE_THIS_TO_RANDOM_STRING
```

### Step 9: Configure Aspera Users

```bash
# Create transfer user
useradd -m -d /aspera/data/aspera-user -s /bin/bash aspera-user

# Set password
passwd aspera-user

# Add to aspera group
usermod -a -G aspera aspera-user

# Configure home directory
chown -R aspera-user:aspera /aspera/data/aspera-user
chmod 700 /aspera/data/aspera-user

# Create .ssh directory for key authentication
mkdir -p /aspera/data/aspera-user/.ssh
chmod 700 /aspera/data/aspera-user/.ssh
chown aspera-user:aspera /aspera/data/aspera-user/.ssh
```

### Step 10: Configure SSH for Aspera

```bash
# Edit sshd_config
vim /etc/ssh/sshd_config

# Add/modify:
# Allow password authentication (temporary for testing)
PasswordAuthentication yes

# Allow key authentication (recommended)
PubkeyAuthentication yes

# SFTP subsystem (should already exist)
Subsystem sftp /usr/lib/openssh/sftp-server

# Restart SSH
systemctl restart sshd
```

### Step 11: Configure Local Firewall

```bash
# Ubuntu (UFW)
ufw allow 22/tcp
ufw allow 33001/tcp
ufw allow 33001:33050/udp
ufw allow 443/tcp
ufw enable

# RHEL/CentOS (firewalld)
firewall-cmd --permanent --add-port=22/tcp
firewall-cmd --permanent --add-port=33001/tcp
firewall-cmd --permanent --add-port=33001-33050/udp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --reload
```

### Step 12: Start Aspera Services

```bash
# Enable services to start on boot
systemctl enable asperanoded
systemctl enable asperacentral

# Start services
systemctl start asperanoded
systemctl start asperacentral

# Check status
systemctl status asperanoded
systemctl status asperacentral

# Check logs
tail -f /opt/aspera/var/log/aspera-scp-transfer.log
tail -f /aspera/logs/aspera.log
```

## 🔧 Advanced Configuration

### Configure HTTPS (Web UI)

```bash
# Generate self-signed certificate (for testing)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /opt/aspera/etc/aspera-server-key.pem \
  -out /opt/aspera/etc/aspera-server-cert.pem \
  -subj "/C=BR/ST=SP/L=SaoPaulo/O=Company/CN=aspera.example.com"

# Set permissions
chmod 600 /opt/aspera/etc/aspera-server-key.pem
chmod 644 /opt/aspera/etc/aspera-server-cert.pem

# Configure in aspera.conf
# Add inside <server>:
<web>
  <enabled>true</enabled>
  <port>443</port>
  <ssl>
    <enabled>true</enabled>
    <certificate>/opt/aspera/etc/aspera-server-cert.pem</certificate>
    <private_key>/opt/aspera/etc/aspera-server-key.pem</private_key>
  </ssl>
</web>

# Restart service
systemctl restart asperanoded
```

### Configure COS Integration (Preparation)

```bash
# Install AWS CLI (S3-compatible tool) for testing with IBM COS
# Note: AWS CLI is used only as an S3-compatible client. This is a 100% IBM Cloud environment.
pip3 install awscli

# Configure IBM COS credentials
mkdir -p ~/.aws
cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = <COS_ACCESS_KEY>
aws_secret_access_key = <COS_SECRET_KEY>
EOF

cat > ~/.aws/config << EOF
[default]
region = eu-de
s3 =
    endpoint_url = https://s3.private.eu-de.cloud-object-storage.appdomain.cloud
    signature_version = s3v4
EOF

# Test connectivity with COS
aws s3 ls s3://aspera-data-bucket/

# Create synchronization script (example)
cat > /opt/aspera/bin/sync-to-cos.sh << 'EOF'
#!/bin/bash
SOURCE_DIR="/aspera/data"
BUCKET="s3://aspera-data-bucket"
ENDPOINT="https://s3.private.eu-de.cloud-object-storage.appdomain.cloud"

aws s3 sync $SOURCE_DIR $BUCKET \
  --endpoint-url $ENDPOINT \
  --delete \
  --exclude ".*" \
  --exclude "tmp/*"
EOF

chmod +x /opt/aspera/bin/sync-to-cos.sh
```

## ✅ Validation and Testing

### Test 1: Verify Services

```bash
# Service status
systemctl status asperanoded
systemctl status asperacentral

# Check open ports
netstat -tlnp | grep 33001
ss -tlnp | grep 33001

# Check processes
ps aux | grep aspera
```

### Test 2: Local Transfer Test

```bash
# Create test file
dd if=/dev/urandom of=/tmp/test-file-1gb bs=1M count=1024

# Transfer using ascp (local)
/opt/aspera/bin/ascp \
  -P 33001 \
  -l 1000M \
  /tmp/test-file-1gb \
  aspera-user@localhost:/aspera/data/

# Verify transferred file
ls -lh /aspera/data/test-file-1gb
```

### Test 3: Remote Transfer Test

```bash
# From a client machine (with Aspera Connect installed):
ascp \
  -P 33001 \
  -l 1000M \
  test-file.txt \
  aspera-user@<FLOATING_IP>:/aspera/data/

# Or via SSH/SCP for basic testing:
scp test-file.txt aspera-user@<FLOATING_IP>:/aspera/data/
```

### Test 4: Performance Test

```bash
# Throughput test
/opt/aspera/bin/ascp \
  -T \
  -l 10G \
  /tmp/test-file-1gb \
  aspera-user@localhost:/aspera/data/test-throughput.dat

# Check performance logs
tail -f /opt/aspera/var/log/aspera-scp-transfer.log
```

### Test 5: COS Connectivity Test

```bash
# Upload to COS
aws s3 cp /tmp/test-file-1gb s3://aspera-data-bucket/test/ \
  --endpoint-url https://s3.private.eu-de.cloud-object-storage.appdomain.cloud

# Download from COS
aws s3 cp s3://aspera-data-bucket/test/test-file-1gb /tmp/test-download \
  --endpoint-url https://s3.private.eu-de.cloud-object-storage.appdomain.cloud

# Verify
ls -lh /tmp/test-download
md5sum /tmp/test-file-1gb /tmp/test-download
```

## 📊 Post-Installation Monitoring

### Configure Basic Monitoring

```bash
# Install monitoring tools
apt install -y sysstat

# Enable statistics collection
systemctl enable sysstat
systemctl start sysstat

# Create monitoring script
cat > /opt/aspera/bin/monitor.sh << 'EOF'
#!/bin/bash
echo "=== Aspera Status ==="
systemctl status asperanoded --no-pager
echo ""
echo "=== Disk Usage ==="
df -h /aspera/cache /aspera/data
echo ""
echo "=== Active Transfers ==="
ps aux | grep ascp | grep -v grep
echo ""
echo "=== Network Stats ==="
netstat -s | grep -i udp
EOF

chmod +x /opt/aspera/bin/monitor.sh

# Execute
/opt/aspera/bin/monitor.sh
```

### Configure Logrotate

```bash
# Create logrotate configuration
cat > /etc/logrotate.d/aspera << 'EOF'
/aspera/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 aspera aspera
    sharedscripts
    postrotate
        systemctl reload asperanoded > /dev/null 2>&1 || true
    endscript
}

/opt/aspera/var/log/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 aspera aspera
}
EOF

# Test configuration
logrotate -d /etc/logrotate.d/aspera
```

## 🔒 Basic Hardening

### Apply Security Settings

```bash
# Disable password authentication (after configuring SSH keys)
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# Configure fail2ban
apt install -y fail2ban

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = 22
logpath = /var/log/auth.log

[aspera]
enabled = true
port = 33001
logpath = /opt/aspera/var/log/aspera-scp-transfer.log
maxretry = 5
EOF

systemctl enable fail2ban
systemctl start fail2ban

# Limit root access
echo "PermitRootLogin no" >> /etc/ssh/sshd_config
systemctl restart sshd
```

## 📝 Post-Installation Documentation

### Information to Document

```bash
# Create documentation file
cat > /root/aspera-installation-info.txt << EOF
=== IBM Aspera HSTS Installation Info ===
Date: $(date)
Hostname: $(hostname)
Private IP: $(hostname -I | awk '{print $1}')
Floating IP: <FLOATING_IP>

Aspera Version: $(/opt/aspera/bin/ascp -A | head -1)
License Type: <LICENSE_TYPE>

Directories:
- Data: /aspera/data
- Cache: /aspera/cache
- Logs: /aspera/logs
- Config: /opt/aspera/etc

Users:
- aspera-user (transfer user)

Ports:
- TCP: 22 (SSH), 33001 (Aspera), 443 (HTTPS)
- UDP: 33001-33050 (FASP)

COS Integration:
- Endpoint: https://s3.private.eu-de.cloud-object-storage.appdomain.cloud
- Bucket: aspera-data-bucket

Next Steps:
1. Configure integration with COS
2. Setup monitoring and alerts
3. Configure backup procedures
4. Test with production workload
EOF

cat /root/aspera-installation-info.txt
```

## ✅ Final Checklist

### Installation
- [ ] Operating system updated
- [ ] Aspera HSTS installed
- [ ] License activated and validated
- [ ] Services started and enabled

### Configuration
- [ ] aspera.conf configured
- [ ] Directories created and permissions set
- [ ] Transfer users created
- [ ] Firewall configured
- [ ] HTTPS configured (if required)

### Testing
- [ ] Local transfer tested
- [ ] Remote transfer tested
- [ ] Performance validated
- [ ] COS connectivity tested
- [ ] Logs verified

### Security
- [ ] IP whitelist configured
- [ ] SSH key authentication configured
- [ ] fail2ban installed and configured
- [ ] SSL certificates configured

### Operations
- [ ] Basic monitoring configured
- [ ] Logrotate configured
- [ ] Documentation created
- [ ] Configuration backup performed

## 🚨 Troubleshooting

### Service does not start

**Symptoms:**
- `systemctl start asperanoded` fails
- Service shows "activating" but never reaches "active"
- Timeout errors during service start

**Common Causes and Solutions:**

1. **Malformed XML in aspera.conf**
   ```bash
   # Check for XML syntax errors
   xmllint --noout /opt/aspera/etc/aspera.conf
   
   # Common issues:
   # - Incorrect closing tags (e.g., <> instead of </tag>)
   # - Missing closing tags
   # - Invalid XML structure
   
   # View service logs for specific errors
   journalctl -u asperanoded -n 100 --no-pager | grep -i error
   ```

2. **Missing or incorrect directories**
   ```bash
   # Verify all directories exist and have correct permissions
   ls -la /aspera/data /aspera/cache /aspera/logs
   
   # Recreate if missing
   sudo mkdir -p /aspera/{data,cache,logs}
   sudo chown -R aspera:aspera /aspera
   sudo chmod 755 /aspera/{data,cache,logs}
   ```

3. **Port conflicts**
   ```bash
   # Check if ports are already in use
   sudo netstat -tlnp | grep -E '(9092|33001)'
   sudo ss -tlnp | grep -E '(9092|33001)'
   
   # Kill conflicting processes if found
   sudo kill <PID>
   ```

4. **License issues**
   ```bash
   # Check license status
   /opt/aspera/bin/asconfigurator -x "get_license_info"
   
   # Reapply license if needed
   /opt/aspera/bin/asconfigurator -x "set_license_key;<YOUR_KEY>"
   ```

### Transfer fails

**Symptoms:**
- Connection refused errors
- Timeout during transfer
- Authentication failures

**Diagnostic Steps:**

1. **Network Connectivity Issues**
   ```bash
   # Test basic connectivity
   ping -c 3 <server-ip>
   
   # Test SSH port (Aspera uses SSH for transfers)
   nc -zv <server-ip> 22
   telnet <server-ip> 22
   
   # Test from client to server
   ssh -i ~/.ssh/aspera_transfer_key user@<server-ip>
   ```

2. **Firewall Blocking Traffic**
   ```bash
   # On SERVER - Check UFW status
   sudo ufw status verbose
   
   # Check iptables rules
   sudo iptables -L -n -v | grep -E '(22|33001|9092)'
   
   # Verify packets are reaching the server
   sudo iptables -L -n -v | grep <client-ip>
   # Look for packet counters - if 0, packets aren't arriving
   
   # Add specific allow rule for client IP
   sudo ufw allow from <client-ip>
   sudo ufw reload
   ```

3. **IBM Cloud Network ACLs Blocking Traffic**
   ```bash
   # This was a critical issue in our deployment
   # Symptoms:
   # - Firewall rules correct but no packets arriving
   # - iptables shows 0 packets from client
   # - Ping fails between VMs in same subnet
   
   # Solution: Configure Network ACLs in IBM Cloud Console
   # 1. Go to: VPC Infrastructure → Network ACLs
   # 2. Find ACL for your subnet
   # 3. Add INBOUND rules:
   #    - Source: 10.240.0.0/24, Protocol: ALL, Action: ALLOW
   # 4. Add OUTBOUND rules:
   #    - Destination: 10.240.0.0/24, Protocol: ALL, Action: ALLOW
   ```

4. **SSH Key Authentication Issues**
   ```bash
   # Verify key permissions on CLIENT
   chmod 600 ~/.ssh/aspera_transfer_key
   chmod 644 ~/.ssh/aspera_transfer_key.pub
   
   # Verify authorized_keys on SERVER
   sudo cat /home/transfer-user/.ssh/authorized_keys
   sudo chmod 700 /home/transfer-user/.ssh
   sudo chmod 600 /home/transfer-user/.ssh/authorized_keys
   sudo chown -R transfer-user:transfer-user /home/transfer-user/.ssh
   
   # Test SSH connection directly
   ssh -i ~/.ssh/aspera_transfer_key -v transfer-user@<server-ip>
   ```

5. **Permission Issues**
   ```bash
   # Check destination directory permissions
   ls -la /aspera/data/transfer-user
   
   # Fix permissions
   sudo chown transfer-user:aspera /aspera/data/transfer-user
   sudo chmod 755 /aspera/data/transfer-user
   ```

### Low performance

**Symptoms:**
- Transfer speeds below expected
- High latency
- Packet loss

**Diagnostic and Solutions:**

1. **Network Bandwidth Issues**
   ```bash
   # Check network interface statistics
   ifconfig ens3
   ip -s link show ens3
   
   # Monitor real-time bandwidth
   iftop -i ens3
   nethogs
   
   # Test raw network performance
   iperf3 -s  # On server
   iperf3 -c <server-ip>  # On client
   
   # Check for packet loss
   ping -c 100 <server-ip> | grep loss
   ```

2. **Disk I/O Bottleneck**
   ```bash
   # Monitor disk I/O
   iostat -x 1 10
   iotop -o
   
   # Check disk usage
   df -h /aspera
   
   # Test disk write speed
   dd if=/dev/zero of=/aspera/data/test bs=1M count=1024 oflag=direct
   ```

3. **Aspera Configuration Limits**
   ```bash
   # Check current rate limits
   grep -E '(target_rate|min_rate)' /opt/aspera/etc/aspera.conf
   
   # Increase limits if needed (edit aspera.conf)
   <target_rate_kbps>10000000</target_rate_kbps>  <!-- 10 Gbps -->
   <min_rate_kbps>100000</min_rate_kbps>          <!-- 100 Mbps -->
   
   # Restart service after changes
   sudo systemctl restart asperanoded
   ```

4. **Client-side Rate Limiting**
   ```bash
   # Increase transfer rate on client
   ascp -l 10G ...  # For 10 Gbps target
   
   # Use adaptive rate
   ascp -l 10G -m 100M ...  # Target 10G, minimum 100M
   ```

### Aspera Service Shows "Malformed XML" Error

**Symptoms:**
```
ERR Error reading configuration file ... Malformed XML?
ERR Failed to load conf
ERR Unable to find/load conf file
```

**Solution:**
```bash
# Validate XML syntax
xmllint --noout /opt/aspera/etc/aspera.conf

# Common XML errors found in our deployment:
# 1. Incorrect closing tag: <token_encryption_key>value<>
#    Should be: <token_encryption_key>value</token_encryption_key>

# 2. Misplaced sections (e.g., <web> outside <CONF>)
#    Ensure all sections are properly nested

# 3. Missing closing tags
#    Every opening tag must have a closing tag

# Backup and fix
sudo cp /opt/aspera/etc/aspera.conf /opt/aspera/etc/aspera.conf.backup
sudo nano /opt/aspera/etc/aspera.conf

# After fixing, restart service
sudo systemctl restart asperanoded
sudo systemctl status asperanoded
```

### No Connectivity Between Client and Server in Same VPC

**Symptoms:**
- Ping fails between VMs
- All ports show as closed/filtered
- VMs are in same subnet but cannot communicate

**Root Cause:**
IBM Cloud Network ACLs blocking internal VPC traffic

**Solution:**
```bash
# 1. Verify both VMs are in same subnet
ip addr show | grep inet

# 2. Check local firewall (should show rules but 0 packets)
sudo iptables -L -n -v

# 3. Configure Network ACLs in IBM Cloud Console:
#    a. Navigate to: VPC Infrastructure → Network ACLs
#    b. Select the ACL attached to your subnet
#    c. Add Inbound Rules:
#       - Priority: 1
#       - Source: 10.240.0.0/24 (your subnet)
#       - Protocol: ALL
#       - Action: ALLOW
#    d. Add Outbound Rules:
#       - Priority: 1
#       - Destination: 10.240.0.0/24 (your subnet)
#       - Protocol: ALL
#       - Action: ALLOW

# 4. Test connectivity after ACL changes
ping -c 3 <other-vm-ip>
nc -zv <other-vm-ip> 22
```

### Port 33001 Shows "Connection Refused"

**Important Note:**
Aspera HSTS uses **SSH (port 22)** for file transfers, not port 33001 directly. Port 33001 is configured in aspera.conf but the actual transfers use SSH protocol.

**Expected Behavior:**
```bash
# Port 22 should be accessible
nc -zv <server-ip> 22
# Connection to <server-ip> 22 port [tcp/ssh] succeeded!

# Port 33001 may show refused (this is normal)
nc -zv <server-ip> 33001
# Connection refused (expected if not listening)

# Port 9092 (Node API) should be listening
nc -zv <server-ip> 9092
# Connection to <server-ip> 9092 port succeeded!
```

**Transfer Command:**
```bash
# Use -P 22 (SSH port), not -P 33001
ascp -P 22 -l 1000M -i ~/.ssh/key file user@server:/destination/
```
## 🖥️ Aspera Client Installation and Configuration

### Overview

This section covers the installation of IBM Aspera Connect Client on a separate VSI to enable high-speed file transfers to the Aspera HSTS server.

### Prerequisites

- Client VSI provisioned in the same VPC as the Aspera server
- SSH access to the client VSI
- Network connectivity between client and server (same subnet recommended)

### Client Information

```
Client VSI IP (Public): 52.118.149.247
Client VSI IP (Private): 10.240.0.14
Server VSI IP (Private): 10.240.0.13
Subnet: 10.240.0.0/24
```

### Step 1: Connect to Client VSI

```bash
# Connect via SSH
ssh -i ~/.ssh/id_ed25519 ubuntu@52.118.149.247
```

### Step 2: Download Aspera Connect

```bash
# Create temporary directory
cd /tmp

# Download Aspera Connect for Linux
wget https://d3gcli72yxqn2z.cloudfront.net/downloads/connect/latest/bin/ibm-aspera-connect_4.2.19.956-HEAD_linux_x86_64.tar.gz

# Verify download
ls -lh ibm-aspera-connect_*.tar.gz
```

### Step 3: Extract and Install

```bash
# Extract the archive
tar -xzf ibm-aspera-connect_4.2.19.956-HEAD_linux_x86_64.tar.gz

# Run the installer
bash ibm-aspera-connect_4.2.19.956-HEAD_linux_x86_64.sh

# Installation will be in: /home/ubuntu/.aspera/connect/
```

### Step 4: Verify Installation

```bash
# Check installation directory
ls -la ~/.aspera/connect/bin/

# Verify ascp version
~/.aspera/connect/bin/ascp --version

# Expected output:
# IBM Aspera Connect version 4.2.19 (956)
# ascp version 4.4.7.956
```

### Step 5: Add to PATH (Optional)

```bash
# Add to .bashrc for permanent PATH
echo 'export PATH=$PATH:~/.aspera/connect/bin' >> ~/.bashrc
source ~/.bashrc

# Verify
which ascp
```

### Step 6: Test Network Connectivity

```bash
# Test connectivity to Aspera server using private IP
ping -c 3 10.240.0.13

# Test Aspera port (TCP 33001)
nc -zv 10.240.0.13 33001

# Test UDP ports (if nc supports UDP)
nc -zvu 10.240.0.13 33001
```

### Step 7: Configure Transfer User on Server

Before testing transfers, ensure a transfer user exists on the Aspera server:

```bash
# On the Aspera server (10.240.0.13 / 169.48.153.114)
ssh -i ~/.ssh/id_ed25519 ubuntu@169.48.153.114

# Create transfer user
sudo useradd -m -d /aspera/data/transfer-user -s /bin/bash transfer-user

# Set password
sudo passwd transfer-user

# Add to aspera group
sudo usermod -a -G aspera transfer-user

# Set permissions
sudo chown -R transfer-user:aspera /aspera/data/transfer-user
sudo chmod 755 /aspera/data/transfer-user

# Create .ssh directory for key-based auth (recommended)
sudo mkdir -p /aspera/data/transfer-user/.ssh
sudo chmod 700 /aspera/data/transfer-user/.ssh
sudo chown transfer-user:aspera /aspera/data/transfer-user/.ssh
```

### Step 8: Test File Transfer

#### Create Test File

```bash
# On the client (52.118.149.247)
# Create a 10MB test file
dd if=/dev/urandom of=/tmp/test-file-10mb bs=1M count=10

# Verify file
ls -lh /tmp/test-file-10mb
```

#### Transfer Using Password Authentication

```bash
# Transfer file to server using private IP
~/.aspera/connect/bin/ascp \
  -P 33001 \
  -l 1000M \
  /tmp/test-file-10mb \
  transfer-user@10.240.0.13:/aspera/data/transfer-user/

# You will be prompted for the password
```

#### Transfer Using SSH Key Authentication (Recommended)

```bash
# On the client, generate SSH key if not exists
ssh-keygen -t ed25519 -f ~/.ssh/aspera_transfer_key -N ""

# Copy public key to server
ssh-copy-id -i ~/.ssh/aspera_transfer_key.pub transfer-user@10.240.0.13

# Or manually:
# cat ~/.ssh/aspera_transfer_key.pub
# Then on server: echo "<public_key>" >> /aspera/data/transfer-user/.ssh/authorized_keys

# Transfer with key authentication
~/.aspera/connect/bin/ascp \
  -P 33001 \
  -l 1000M \
  -i ~/.ssh/aspera_transfer_key \
  /tmp/test-file-10mb \
  transfer-user@10.240.0.13:/aspera/data/transfer-user/
```

### Step 9: Verify Transfer on Server

```bash
# On the server
ssh -i ~/.ssh/id_ed25519 ubuntu@169.48.153.114

# Check transferred file
ls -lh /aspera/data/transfer-user/test-file-10mb

# Verify file integrity (compare checksums)
md5sum /aspera/data/transfer-user/test-file-10mb
```

### Step 10: Performance Testing

```bash
# Create larger test file (1GB)
dd if=/dev/urandom of=/tmp/test-file-1gb bs=1M count=1024

# Transfer with performance monitoring
~/.aspera/connect/bin/ascp \
  -T \
  -P 33001 \
  -l 10G \
  -i ~/.ssh/aspera_transfer_key \
  /tmp/test-file-1gb \
  transfer-user@10.240.0.13:/aspera/data/transfer-user/

# Options explained:
# -T: Enable throughput display
# -P: SSH port (33001 for Aspera)
# -l: Target transfer rate (10G = 10 Gbps)
# -i: SSH private key
```

### Common Transfer Options

```bash
# Basic transfer
ascp -P 33001 <source> <user>@<host>:<destination>

# With target rate limit
ascp -P 33001 -l 1000M <source> <user>@<host>:<destination>

# With minimum rate
ascp -P 33001 -l 1000M -m 100M <source> <user>@<host>:<destination>

# Recursive directory transfer
ascp -P 33001 -r <source_dir> <user>@<host>:<destination_dir>

# Resume interrupted transfer
ascp -P 33001 -k 1 <source> <user>@<host>:<destination>

# Verbose output for debugging
ascp -P 33001 -v <source> <user>@<host>:<destination>

# With encryption
ascp -P 33001 --overwrite=always <source> <user>@<host>:<destination>
```

## 🔧 Client Configuration Best Practices

### Security Considerations

1. **Use SSH Key Authentication**
   - More secure than password authentication
   - Enables automated transfers
   - Easier to manage and rotate

2. **Restrict Transfer User Permissions**
   ```bash
   # On server, limit user to specific directory
   sudo chown root:root /aspera/data/transfer-user
   sudo chmod 755 /aspera/data/transfer-user
   ```

3. **Configure Firewall Rules**
   ```bash
   # On client (if UFW is enabled)
   sudo ufw allow out 33001/tcp
   sudo ufw allow out 33001:33050/udp
   ```

### Network Optimization

1. **Use Private IPs**
   - Always use private IPs (10.240.0.x) for transfers within VPC
   - Faster and no egress charges

2. **Adjust Transfer Rate**
   ```bash
   # For 1 Gbps network
   ascp -l 1000M ...
   
   # For 10 Gbps network
   ascp -l 10G ...
   ```

3. **Monitor Network Performance**
   ```bash
   # Check network stats during transfer
   iftop -i ens3
   
   # Monitor bandwidth
   nethogs
   ```

## ✅ Client Installation Checklist

- [ ] Client VSI accessible via SSH
- [ ] Aspera Connect downloaded and installed
- [ ] ascp command verified and working
- [ ] Network connectivity to server confirmed
- [ ] Transfer user created on server
- [ ] SSH key authentication configured
- [ ] Test file transfer successful
- [ ] Performance test completed
- [ ] Firewall rules configured (if needed)
- [ ] Documentation updated with client details

## 🚨 Client Troubleshooting

### Transfer Fails with "Connection Refused"

**Symptoms:**
- `ascp` command fails immediately
- Error: "Connection refused" or "No route to host"
- Cannot connect to server

**Diagnostic Steps:**

1. **Verify Network Connectivity**
   ```bash
   # Test basic connectivity
   ping -c 3 10.240.0.13
   
   # If ping fails, check:
   # - Both VMs in same subnet
   # - Network ACLs configured correctly
   # - Security Groups allow traffic
   ```

2. **Check SSH Port (Port 22, not 33001)**
   ```bash
   # Aspera uses SSH for transfers
   nc -zv 10.240.0.13 22
   
   # Should show: Connection to 10.240.0.13 22 port [tcp/ssh] succeeded!
   ```

3. **Verify Server Firewall**
   ```bash
   # On server - check if client IP is allowed
   sudo ufw status verbose | grep 10.240.0.14
   
   # Add rule if missing
   sudo ufw allow from 10.240.0.14
   sudo ufw reload
   ```

4. **Check IBM Cloud Network ACLs**
   ```bash
   # If firewall is correct but still no connectivity:
   # Problem is likely Network ACLs in IBM Cloud
   
   # Solution: Configure in IBM Cloud Console
   # VPC Infrastructure → Network ACLs → Your ACL
   # Add rules to allow traffic between subnet IPs
   ```

5. **Test SSH Connection Directly**
   ```bash
   # This should work before trying ascp
   ssh -i ~/.ssh/aspera_transfer_key transfer-user@10.240.0.13
   
   # If SSH works, ascp should work too
   ```

### Slow Transfer Speeds

**Symptoms:**
- Transfer speed below expected
- Throughput not reaching network capacity
- Long transfer times

**Solutions:**

1. **Increase Target Rate**
   ```bash
   # Default may be too conservative
   ascp -P 22 -l 10G -i ~/.ssh/aspera_transfer_key file user@server:/dest/
   
   # For 1 Gbps network: -l 1000M
   # For 10 Gbps network: -l 10G
   ```

2. **Check Network Performance**
   ```bash
   # Test raw network speed
   iperf3 -s  # On server
   iperf3 -c 10.240.0.13  # On client
   
   # Check for packet loss
   ping -c 100 10.240.0.13 | grep loss
   
   # Monitor bandwidth during transfer
   iftop -i ens3
   ```

3. **Verify Server Configuration**
   ```bash
   # On server - check rate limits
   grep target_rate /opt/aspera/etc/aspera.conf
   
   # Should be high enough (e.g., 10000000 for 10 Gbps)
   ```

4. **Use Performance Options**
   ```bash
   # Enable throughput display
   ascp -P 22 -l 10G -T -i ~/.ssh/aspera_transfer_key file user@server:/dest/
   
   # Set minimum rate
   ascp -P 22 -l 10G -m 100M -i ~/.ssh/aspera_transfer_key file user@server:/dest/
   ```

### Authentication Failures

**Symptoms:**
- "Permission denied (publickey)"
- "Authentication failed"
- SSH key not accepted

**Solutions:**

1. **Fix SSH Key Permissions**
   ```bash
   # On client
   chmod 600 ~/.ssh/aspera_transfer_key
   chmod 644 ~/.ssh/aspera_transfer_key.pub
   chmod 700 ~/.ssh
   ```

2. **Verify Public Key on Server**
   ```bash
   # On server
   sudo cat /aspera/data/transfer-user/.ssh/authorized_keys
   
   # Should contain your public key
   cat ~/.ssh/aspera_transfer_key.pub  # Compare with server
   ```

3. **Fix Server-side Permissions**
   ```bash
   # On server
   sudo chmod 700 /aspera/data/transfer-user/.ssh
   sudo chmod 600 /aspera/data/transfer-user/.ssh/authorized_keys
   sudo chown -R transfer-user:transfer-user /aspera/data/transfer-user/.ssh
   ```

4. **Test SSH Connection**
   ```bash
   # This must work before ascp will work
   ssh -i ~/.ssh/aspera_transfer_key -v transfer-user@10.240.0.13
   
   # Use -v for verbose output to debug issues
   ```

5. **Re-copy SSH Key**
   ```bash
   # If key is corrupted, re-copy
   ssh-copy-id -i ~/.ssh/aspera_transfer_key.pub transfer-user@10.240.0.13
   
   # Or manually:
   cat ~/.ssh/aspera_transfer_key.pub | ssh transfer-user@10.240.0.13 'cat >> ~/.ssh/authorized_keys'
   ```

### "Port 33001 Connection Refused" (Expected Behavior)

**Important:** This is **normal behavior**. Aspera HSTS uses SSH (port 22) for transfers, not port 33001 directly.

**Correct Usage:**
```bash
# Use -P 22 (SSH port)
ascp -P 22 -l 1000M -i ~/.ssh/aspera_transfer_key file user@server:/dest/

# NOT -P 33001 (this will fail)
```

**Port Functions:**
- **Port 22**: SSH - Used for actual file transfers
- **Port 9092**: Aspera Node API - Management interface
- **Port 33001**: Configured in aspera.conf but not directly accessible

### Transfer Works but Files Not Appearing

**Symptoms:**
- `ascp` reports success
- Files not found in destination directory
- No error messages

**Solutions:**

1. **Check Destination Path**
   ```bash
   # Verify destination directory exists
   ssh -i ~/.ssh/aspera_transfer_key transfer-user@10.240.0.13 'ls -la /aspera/data/transfer-user/'
   
   # Check if files are in user's home directory instead
   ssh -i ~/.ssh/aspera_transfer_key transfer-user@10.240.0.13 'ls -la ~/'
   ```

2. **Use Absolute Paths**
   ```bash
   # Always use full paths
   ascp -P 22 -l 1000M -i ~/.ssh/aspera_transfer_key \
     /local/file \
     transfer-user@10.240.0.13:/aspera/data/transfer-user/filename
   ```

3. **Check Permissions**
   ```bash
   # Verify user can write to destination
   ssh -i ~/.ssh/aspera_transfer_key transfer-user@10.240.0.13 'touch /aspera/data/transfer-user/test'
   ```

### Performance Validation Results

Based on our testing with 100MB files:

**Expected Performance:**
- **10MB file**: ~1 second @ 56+ Mbps
- **100MB file**: ~2-3 seconds @ 300+ Mbps
- **Checksum verification**: Files should have identical MD5 hashes

**Test Commands:**
```bash
# Create test file
dd if=/dev/urandom of=/tmp/test-100mb bs=1M count=100

# Upload test
time ascp -P 22 -l 1000M -i ~/.ssh/aspera_transfer_key \
  /tmp/test-100mb transfer-user@10.240.0.13:/aspera/data/transfer-user/

# Download test
time ascp -P 22 -l 1000M -i ~/.ssh/aspera_transfer_key \
  transfer-user@10.240.0.13:/aspera/data/transfer-user/test-100mb /tmp/test-download

# Verify integrity
md5sum /tmp/test-100mb /tmp/test-download
```

## 📚 References

- [IBM Aspera HSTS Documentation](https://www.ibm.com/docs/en/aspera-hsts)
- [Aspera Configuration Guide](https://www.ibm.com/docs/en/aspera-hsts/4.4?topic=configuration-asperaconf)
- [Aspera Command Line](https://www.ibm.com/docs/en/aspera-hsts/4.4?topic=tools-ascp-transferring-from-command-line)

---

**Last Updated**: 2026-05-07
**Version**: 1.2.0

**Changelog:**
- v1.2.0 (2026-05-07): Added automated installation scripts, enhanced troubleshooting with Network ACL issues, detailed client troubleshooting
- v1.1.0 (2026-05-07): Added Aspera Client installation and configuration
- v1.0.0 (2026-05-07): Initial version with server installation

**Installation Scripts:**
- [`install-aspera-server.sh`](install-aspera-server.sh) - Automated server installation
- [`install-aspera-client.sh`](install-aspera-client.sh) - Automated client installation

**Next Steps**: Proceed with [Aspera-COS Integration](integracao-aspera-cos.md)