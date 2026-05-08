# IBM Aspera Installation Scripts

This directory contains automated installation scripts for IBM Aspera HSTS Server and Client.

## 📋 Available Scripts

### 1. install-aspera-server.sh
Automated installation script for IBM Aspera HSTS Server on Ubuntu 22.04.

**Features:**
- ✅ Automatic OS detection and validation
- ✅ System package updates
- ✅ Dependency installation
- ✅ Aspera HSTS download and installation
- ✅ Directory structure creation (`/aspera/data`, `/aspera/cache`, `/aspera/logs`)
- ✅ UFW firewall configuration
- ✅ Basic `aspera.conf` generation with secure encryption token
- ✅ Service startup and verification
- ✅ Installation summary and next steps

**Usage:**
```bash
# Download the script
wget https://raw.githubusercontent.com/your-repo/aspera-cos-ibmcloud/main/02-runbooks/install-aspera-server.sh

# Make executable
chmod +x install-aspera-server.sh

# Run as root
sudo ./install-aspera-server.sh
```

**Requirements:**
- Ubuntu 22.04 LTS (or compatible)
- Root/sudo access
- Internet connectivity
- Minimum 4GB RAM
- 20GB available disk space

**Post-Installation:**
1. Configure license key
2. Create transfer users
3. Test transfers from client
4. Configure COS integration (if needed)

---

### 2. install-aspera-client.sh
Automated installation script for IBM Aspera Connect Client on Ubuntu 22.04.

**Features:**
- ✅ Automatic OS detection
- ✅ Dependency installation
- ✅ Aspera Connect download and installation
- ✅ PATH configuration
- ✅ SSH key generation for transfers
- ✅ Test file creation
- ✅ Optional connectivity testing to server
- ✅ Usage examples and documentation

**Usage:**
```bash
# Download the script
wget https://raw.githubusercontent.com/your-repo/aspera-cos-ibmcloud/main/02-runbooks/install-aspera-client.sh

# Make executable
chmod +x install-aspera-client.sh

# Run as regular user (NOT root)
./install-aspera-client.sh

# Or with server IP for connectivity test
./install-aspera-client.sh 10.240.0.13
```

**Requirements:**
- Ubuntu 22.04 LTS (or compatible)
- Regular user account (do NOT run as root)
- Internet connectivity
- Network connectivity to Aspera server

**Post-Installation:**
1. Copy SSH public key to server
2. Test connectivity to server
3. Perform test file transfer
4. Apply PATH changes: `source ~/.bashrc`

---

## 🚀 Quick Start Guide

### Complete Setup (Server + Client)

**On Server VM:**
```bash
# 1. Install Aspera Server
sudo ./install-aspera-server.sh

# 2. Create transfer user
sudo useradd -m -d /aspera/data/transfer-user -s /bin/bash transfer-user
sudo passwd transfer-user
sudo usermod -a -G aspera transfer-user
sudo chown -R transfer-user:aspera /aspera/data/transfer-user
sudo chmod 755 /aspera/data/transfer-user

# 3. Setup SSH directory for key-based auth
sudo mkdir -p /aspera/data/transfer-user/.ssh
sudo chmod 700 /aspera/data/transfer-user/.ssh
sudo chown transfer-user:aspera /aspera/data/transfer-user/.ssh
```

**On Client VM:**
```bash
# 1. Install Aspera Client
./install-aspera-client.sh 10.240.0.13

# 2. Copy SSH public key to server
ssh-copy-id -i ~/.ssh/aspera_transfer_key.pub transfer-user@10.240.0.13

# 3. Test transfer
~/.aspera/connect/bin/ascp -P 22 -l 1000M -i ~/.ssh/aspera_transfer_key \
  /tmp/aspera-test-10mb transfer-user@10.240.0.13:/aspera/data/transfer-user/

# 4. Verify on server
ssh transfer-user@10.240.0.13 'ls -lh /aspera/data/transfer-user/'
```

---

## 🔧 Configuration

### Server Configuration

The server script creates a basic `aspera.conf` with these settings:

```xml
<target_rate_kbps>10000000</target_rate_kbps>  <!-- 10 Gbps -->
<min_rate_kbps>100000</min_rate_kbps>          <!-- 100 Mbps -->
<max_sessions>100</max_sessions>
<tcp_port>33001</tcp_port>
<udp_port_range>
  <min>33001</min>
  <max>33050</max>
</udp_port_range>
```

**Firewall Rules Created:**
- Port 22/tcp: SSH
- Port 33001/tcp: Aspera TCP
- Port 33001-33050/udp: Aspera UDP (FASP)
- Port 443/tcp: HTTPS Web UI

### Client Configuration

The client script:
- Installs to: `~/.aspera/connect/`
- Generates SSH key: `~/.ssh/aspera_transfer_key`
- Creates test file: `/tmp/aspera-test-10mb`
- Adds to PATH in `~/.bashrc`

---

## 🚨 Troubleshooting

### Server Installation Issues

**Service fails to start:**
```bash
# Check logs
journalctl -u asperanoded -n 50

# Validate configuration
xmllint --noout /opt/aspera/etc/aspera.conf

# Check ports
sudo netstat -tlnp | grep -E '(9092|33001)'
```

**Firewall blocking:**
```bash
# Check UFW status
sudo ufw status verbose

# Check iptables
sudo iptables -L -n -v
```

### Client Installation Issues

**ascp not found:**
```bash
# Apply PATH changes
source ~/.bashrc

# Or use full path
~/.aspera/connect/bin/ascp --version
```

**Cannot connect to server:**
```bash
# Test connectivity
ping -c 3 <server-ip>
nc -zv <server-ip> 22

# Test SSH
ssh -i ~/.ssh/aspera_transfer_key transfer-user@<server-ip>
```

### Network Connectivity Issues

**VMs in same VPC cannot communicate:**

This is usually caused by IBM Cloud Network ACLs blocking internal traffic.

**Solution:**
1. Go to IBM Cloud Console → VPC Infrastructure → Network ACLs
2. Select the ACL for your subnet
3. Add Inbound rules:
   - Source: `10.240.0.0/24`, Protocol: ALL, Action: ALLOW
4. Add Outbound rules:
   - Destination: `10.240.0.0/24`, Protocol: ALL, Action: ALLOW

---

## 📊 Performance Testing

### Upload Test
```bash
# Create 100MB test file
dd if=/dev/urandom of=/tmp/test-100mb bs=1M count=100

# Transfer with timing
time ~/.aspera/connect/bin/ascp -P 22 -l 1000M -T \
  -i ~/.ssh/aspera_transfer_key \
  /tmp/test-100mb transfer-user@10.240.0.13:/aspera/data/transfer-user/
```

### Download Test
```bash
# Download from server
time ~/.aspera/connect/bin/ascp -P 22 -l 1000M -T \
  -i ~/.ssh/aspera_transfer_key \
  transfer-user@10.240.0.13:/aspera/data/transfer-user/test-100mb /tmp/test-download
```

### Verify Integrity
```bash
# Compare checksums
md5sum /tmp/test-100mb
ssh transfer-user@10.240.0.13 'md5sum /aspera/data/transfer-user/test-100mb'
```

**Expected Performance:**
- 10MB file: ~1 second @ 56+ Mbps
- 100MB file: ~2-3 seconds @ 300+ Mbps
- Checksums should match exactly

---

## 📝 Important Notes

### Port Usage
- **Port 22**: SSH - Used for actual file transfers (use `-P 22`)
- **Port 9092**: Aspera Node API - Management interface
- **Port 33001**: Configured in aspera.conf but NOT directly used for transfers

### Security Best Practices
1. Always use SSH key authentication (not passwords)
2. Restrict transfer user permissions
3. Use private IPs for transfers within VPC
4. Configure firewall rules appropriately
5. Regularly update Aspera software

### Common Mistakes
❌ Using `-P 33001` (wrong - use `-P 22`)
❌ Running client script as root
❌ Forgetting to copy SSH public key to server
❌ Not configuring Network ACLs in IBM Cloud
❌ Using public IPs for internal VPC transfers

---

## 📚 Additional Resources

- [Full Installation Runbook](aspera-hsts-installation.md)
- [IBM Aspera HSTS Documentation](https://www.ibm.com/docs/en/aspera-hsts)
- [Aspera Command Line Reference](https://www.ibm.com/docs/en/aspera-hsts/4.4?topic=tools-ascp-transferring-from-command-line)

---

## 🆘 Support

For issues or questions:
1. Check the [troubleshooting section](aspera-hsts-installation.md#-troubleshooting)
2. Review script output for error messages
3. Check system logs: `journalctl -u asperanoded -n 100`
4. Verify network connectivity and firewall rules

---

**Version**: 1.0.0  
**Last Updated**: 2026-05-07  
**Tested On**: Ubuntu 22.04 LTS