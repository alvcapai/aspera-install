#!/bin/bash
################################################################################
# IBM Aspera End-to-End Validation Script
# Version: 1.0.0
# Date: 2026-05-07
# Description: Validates complete Aspera setup with comprehensive tests
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
CLIENT_CONFIG_DIR="$HOME/.aspera-client"
CLIENT_CONFIG_FILE="$CLIENT_CONFIG_DIR/client.conf"
TEST_DIR="/tmp/aspera-validation-$$"
REPORT_FILE="$HOME/aspera-validation-report-$(date +%Y%m%d_%H%M%S).txt"
JSON_REPORT_FILE="$HOME/aspera-validation-report-$(date +%Y%m%d_%H%M%S).json"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠ WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
}

print_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

# Function to record test result
record_test() {
    local TEST_NAME="$1"
    local RESULT="$2"
    local MESSAGE="${3:-}"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if [ "$RESULT" = "PASS" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        print_success "$TEST_NAME"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        print_error "$TEST_NAME: $MESSAGE"
    fi
    
    # Log to report file
    echo "[$RESULT] $TEST_NAME: $MESSAGE" >> "$REPORT_FILE"
}

# Function to load client configuration
load_config() {
    if [ ! -f "$CLIENT_CONFIG_FILE" ]; then
        print_error "Client configuration not found: $CLIENT_CONFIG_FILE"
        print_info "Run aspera-configure-client.sh first"
        exit 1
    fi
    
    source "$CLIENT_CONFIG_FILE"
    
    print_info "Loaded configuration:"
    print_info "  Server: $SERVER_HOSTNAME ($SERVER_IP)"
    print_info "  User: $TRANSFER_USER"
    print_info "  SSH Key: $SSH_KEY"
}

# Function to create test directory
setup_test_environment() {
    print_info "Setting up test environment..."
    mkdir -p "$TEST_DIR"
    echo "Test environment: $TEST_DIR" >> "$REPORT_FILE"
}

# Function to cleanup
cleanup() {
    print_info "Cleaning up test files..."
    rm -rf "$TEST_DIR"
}

# Test 1: Network Connectivity
test_network_connectivity() {
    print_test "1. Network Connectivity Tests"
    echo "" >> "$REPORT_FILE"
    echo "=== Network Connectivity Tests ===" >> "$REPORT_FILE"
    
    # Test 1.1: Ping
    if ping -c 3 -W 2 "$SERVER_IP" &>/dev/null; then
        record_test "1.1 Ping to server" "PASS" "Server is reachable"
    else
        record_test "1.1 Ping to server" "FAIL" "Cannot ping server"
    fi
    
    # Test 1.2: SSH Port
    if nc -zv -w 3 "$SERVER_IP" "$SSH_PORT" &>/dev/null; then
        record_test "1.2 SSH port accessibility" "PASS" "Port $SSH_PORT is open"
    else
        record_test "1.2 SSH port accessibility" "FAIL" "Port $SSH_PORT is closed"
    fi
    
    # Test 1.3: Latency
    local LATENCY=$(ping -c 10 -W 2 "$SERVER_IP" 2>/dev/null | grep 'avg' | awk -F'/' '{print $5}')
    if [ -n "$LATENCY" ]; then
        record_test "1.3 Network latency" "PASS" "Average latency: ${LATENCY}ms"
    else
        record_test "1.3 Network latency" "FAIL" "Could not measure latency"
    fi
    
    # Test 1.4: Packet Loss
    local PACKET_LOSS=$(ping -c 20 -W 2 "$SERVER_IP" 2>/dev/null | grep 'packet loss' | awk '{print $6}')
    if [ "$PACKET_LOSS" = "0%" ]; then
        record_test "1.4 Packet loss" "PASS" "No packet loss"
    else
        record_test "1.4 Packet loss" "WARN" "Packet loss: $PACKET_LOSS"
    fi
}

# Test 2: SSH Authentication
test_ssh_authentication() {
    print_test "2. SSH Authentication Tests"
    echo "" >> "$REPORT_FILE"
    echo "=== SSH Authentication Tests ===" >> "$REPORT_FILE"
    
    # Test 2.1: SSH Key Permissions
    if [ "$(stat -c %a "$SSH_KEY" 2>/dev/null)" = "600" ]; then
        record_test "2.1 SSH key permissions" "PASS" "Correct permissions (600)"
    else
        record_test "2.1 SSH key permissions" "FAIL" "Incorrect permissions"
    fi
    
    # Test 2.2: SSH Connection
    if ssh -i "$SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=5 \
        "${TRANSFER_USER}@${SERVER_IP}" 'echo "OK"' &>/dev/null; then
        record_test "2.2 SSH key authentication" "PASS" "Authentication successful"
    else
        record_test "2.2 SSH key authentication" "FAIL" "Authentication failed"
    fi
    
    # Test 2.3: Remote Directory Access
    if ssh -i "$SSH_KEY" -p "$SSH_PORT" "${TRANSFER_USER}@${SERVER_IP}" \
        "[ -d '$TRANSFER_HOME' ] && echo OK" 2>/dev/null | grep -q "OK"; then
        record_test "2.3 Remote directory access" "PASS" "Can access $TRANSFER_HOME"
    else
        record_test "2.3 Remote directory access" "FAIL" "Cannot access $TRANSFER_HOME"
    fi
    
    # Test 2.4: Write Permissions
    local TEST_FILE="aspera-test-$$"
    if ssh -i "$SSH_KEY" -p "$SSH_PORT" "${TRANSFER_USER}@${SERVER_IP}" \
        "touch '$TRANSFER_HOME/$TEST_FILE' && rm '$TRANSFER_HOME/$TEST_FILE'" &>/dev/null; then
        record_test "2.4 Write permissions" "PASS" "Can write to remote directory"
    else
        record_test "2.4 Write permissions" "FAIL" "Cannot write to remote directory"
    fi
}

# Test 3: Aspera Client
test_aspera_client() {
    print_test "3. Aspera Client Tests"
    echo "" >> "$REPORT_FILE"
    echo "=== Aspera Client Tests ===" >> "$REPORT_FILE"
    
    # Test 3.1: ascp Binary
    if [ -f "$ASCP_BIN" ]; then
        local VERSION=$($ASCP_BIN --version 2>&1 | head -1)
        record_test "3.1 ascp binary" "PASS" "Found: $VERSION"
    else
        record_test "3.1 ascp binary" "FAIL" "ascp not found at $ASCP_BIN"
    fi
    
    # Test 3.2: ascp Execution
    if $ASCP_BIN --help &>/dev/null; then
        record_test "3.2 ascp execution" "PASS" "ascp can execute"
    else
        record_test "3.2 ascp execution" "FAIL" "ascp cannot execute"
    fi
}

# Test 4: File Transfer - Upload
test_file_upload() {
    print_test "4. File Transfer Tests - Upload"
    echo "" >> "$REPORT_FILE"
    echo "=== File Transfer Tests - Upload ===" >> "$REPORT_FILE"
    
    # Test 4.1: Small File Upload (10MB)
    local SMALL_FILE="$TEST_DIR/test-10mb"
    dd if=/dev/urandom of="$SMALL_FILE" bs=1M count=10 2>/dev/null
    local SMALL_MD5=$(md5sum "$SMALL_FILE" | awk '{print $1}')
    
    local START_TIME=$(date +%s)
    if $ASCP_BIN -P "$SSH_PORT" -l 1000M -i "$SSH_KEY" \
        "$SMALL_FILE" "${TRANSFER_USER}@${SERVER_IP}:${TRANSFER_HOME}/" &>/dev/null; then
        local END_TIME=$(date +%s)
        local DURATION=$((END_TIME - START_TIME))
        record_test "4.1 Upload 10MB file" "PASS" "Completed in ${DURATION}s"
    else
        record_test "4.1 Upload 10MB file" "FAIL" "Transfer failed"
        return
    fi
    
    # Test 4.2: Verify Upload Integrity
    local REMOTE_MD5=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "${TRANSFER_USER}@${SERVER_IP}" \
        "md5sum '$TRANSFER_HOME/test-10mb'" 2>/dev/null | awk '{print $1}')
    
    if [ "$SMALL_MD5" = "$REMOTE_MD5" ]; then
        record_test "4.2 Upload integrity (MD5)" "PASS" "Checksums match: $SMALL_MD5"
    else
        record_test "4.2 Upload integrity (MD5)" "FAIL" "Checksums mismatch"
    fi
    
    # Test 4.3: Large File Upload (100MB)
    local LARGE_FILE="$TEST_DIR/test-100mb"
    dd if=/dev/urandom of="$LARGE_FILE" bs=1M count=100 2>/dev/null
    local LARGE_MD5=$(md5sum "$LARGE_FILE" | awk '{print $1}')
    
    START_TIME=$(date +%s)
    if $ASCP_BIN -P "$SSH_PORT" -l 1000M -i "$SSH_KEY" \
        "$LARGE_FILE" "${TRANSFER_USER}@${SERVER_IP}:${TRANSFER_HOME}/" &>/dev/null; then
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        local SPEED=$((100 * 8 / DURATION))  # Mbps
        record_test "4.3 Upload 100MB file" "PASS" "Completed in ${DURATION}s (~${SPEED} Mbps)"
    else
        record_test "4.3 Upload 100MB file" "FAIL" "Transfer failed"
    fi
}

# Test 5: File Transfer - Download
test_file_download() {
    print_test "5. File Transfer Tests - Download"
    echo "" >> "$REPORT_FILE"
    echo "=== File Transfer Tests - Download ===" >> "$REPORT_FILE"
    
    # Test 5.1: Download 10MB file
    local DOWNLOAD_FILE="$TEST_DIR/download-10mb"
    local START_TIME=$(date +%s)
    
    if $ASCP_BIN -P "$SSH_PORT" -l 1000M -i "$SSH_KEY" \
        "${TRANSFER_USER}@${SERVER_IP}:${TRANSFER_HOME}/test-10mb" "$DOWNLOAD_FILE" &>/dev/null; then
        local END_TIME=$(date +%s)
        local DURATION=$((END_TIME - START_TIME))
        record_test "5.1 Download 10MB file" "PASS" "Completed in ${DURATION}s"
    else
        record_test "5.1 Download 10MB file" "FAIL" "Transfer failed"
        return
    fi
    
    # Test 5.2: Verify Download Integrity
    local ORIGINAL_MD5=$(md5sum "$TEST_DIR/test-10mb" | awk '{print $1}')
    local DOWNLOAD_MD5=$(md5sum "$DOWNLOAD_FILE" | awk '{print $1}')
    
    if [ "$ORIGINAL_MD5" = "$DOWNLOAD_MD5" ]; then
        record_test "5.2 Download integrity (MD5)" "PASS" "Checksums match: $DOWNLOAD_MD5"
    else
        record_test "5.2 Download integrity (MD5)" "FAIL" "Checksums mismatch"
    fi
    
    # Test 5.3: Bidirectional Transfer Integrity
    if [ "$ORIGINAL_MD5" = "$DOWNLOAD_MD5" ]; then
        record_test "5.3 Bidirectional integrity" "PASS" "Upload and download produce identical files"
    else
        record_test "5.3 Bidirectional integrity" "FAIL" "Files differ after round-trip"
    fi
}

# Test 6: Performance Benchmarks
test_performance() {
    print_test "6. Performance Benchmark Tests"
    echo "" >> "$REPORT_FILE"
    echo "=== Performance Benchmark Tests ===" >> "$REPORT_FILE"
    
    # Test 6.1: Throughput Test
    local PERF_FILE="$TEST_DIR/perf-test-100mb"
    dd if=/dev/zero of="$PERF_FILE" bs=1M count=100 2>/dev/null
    
    local START_TIME=$(date +%s.%N)
    $ASCP_BIN -P "$SSH_PORT" -l 10G -i "$SSH_KEY" \
        "$PERF_FILE" "${TRANSFER_USER}@${SERVER_IP}:${TRANSFER_HOME}/perf-test" &>/dev/null
    local END_TIME=$(date +%s.%N)
    
    local DURATION=$(echo "$END_TIME - $START_TIME" | bc)
    local THROUGHPUT=$(echo "scale=2; 100 * 8 / $DURATION" | bc)
    
    if (( $(echo "$THROUGHPUT > 50" | bc -l) )); then
        record_test "6.1 Throughput benchmark" "PASS" "${THROUGHPUT} Mbps"
    else
        record_test "6.1 Throughput benchmark" "WARN" "Low throughput: ${THROUGHPUT} Mbps"
    fi
    
    # Cleanup remote test file
    ssh -i "$SSH_KEY" -p "$SSH_PORT" "${TRANSFER_USER}@${SERVER_IP}" \
        "rm -f '$TRANSFER_HOME/perf-test'" &>/dev/null
}

# Test 7: Server Status
test_server_status() {
    print_test "7. Server Status Tests"
    echo "" >> "$REPORT_FILE"
    echo "=== Server Status Tests ===" >> "$REPORT_FILE"
    
    # Test 7.1: Aspera Service Status
    local SERVICE_STATUS=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "${TRANSFER_USER}@${SERVER_IP}" \
        "systemctl is-active asperanoded 2>/dev/null || echo 'unknown'")
    
    if [ "$SERVICE_STATUS" = "active" ]; then
        record_test "7.1 Aspera service status" "PASS" "Service is active"
    else
        record_test "7.1 Aspera service status" "FAIL" "Service status: $SERVICE_STATUS"
    fi
    
    # Test 7.2: Disk Space
    local DISK_USAGE=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "${TRANSFER_USER}@${SERVER_IP}" \
        "df -h '$TRANSFER_HOME' | tail -1 | awk '{print \$5}'" 2>/dev/null | tr -d '%')
    
    if [ -n "$DISK_USAGE" ] && [ "$DISK_USAGE" -lt 90 ]; then
        record_test "7.2 Server disk space" "PASS" "Usage: ${DISK_USAGE}%"
    else
        record_test "7.2 Server disk space" "WARN" "High usage: ${DISK_USAGE}%"
    fi
}

# Function to generate JSON report
generate_json_report() {
    cat > "$JSON_REPORT_FILE" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "server": {
        "hostname": "$SERVER_HOSTNAME",
        "ip": "$SERVER_IP"
    },
    "summary": {
        "total_tests": $TESTS_TOTAL,
        "passed": $TESTS_PASSED,
        "failed": $TESTS_FAILED,
        "success_rate": $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_TOTAL" | bc)
    },
    "status": "$([ $TESTS_FAILED -eq 0 ] && echo "PASS" || echo "FAIL")"
}
EOF
}

# Function to display final report
display_report() {
    echo ""
    echo "=========================================="
    echo "  Aspera Validation Report"
    echo "=========================================="
    echo ""
    echo "Server: $SERVER_HOSTNAME ($SERVER_IP)"
    echo "Date: $(date)"
    echo ""
    echo "Test Results:"
    echo "  Total Tests: $TESTS_TOTAL"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo "  Success Rate: $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_TOTAL" | bc)%"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        print_success "All tests passed! Aspera setup is fully functional."
    else
        print_error "$TESTS_FAILED test(s) failed. Review the report for details."
    fi
    
    echo ""
    echo "Detailed Reports:"
    echo "  Text: $REPORT_FILE"
    echo "  JSON: $JSON_REPORT_FILE"
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
    echo "=========================================="
    echo "  IBM Aspera End-to-End Validation"
    echo "=========================================="
    echo ""
    
    # Initialize report
    echo "Aspera Validation Report" > "$REPORT_FILE"
    echo "Generated: $(date)" >> "$REPORT_FILE"
    echo "========================================" >> "$REPORT_FILE"
    
    load_config
    setup_test_environment
    
    # Run all tests
    test_network_connectivity
    test_ssh_authentication
    test_aspera_client
    test_file_upload
    test_file_download
    test_performance
    test_server_status
    
    # Generate reports
    generate_json_report
    display_report
    
    # Cleanup
    cleanup
    
    # Exit with appropriate code
    if [ $TESTS_FAILED -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"

# Made with Bob
