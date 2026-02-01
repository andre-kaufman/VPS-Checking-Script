#!/bin/bash

# Comprehensive VPS testing script
# Checks: performance, stability, configuration compliance

echo "=================================================="
echo "   COMPREHENSIVE VPS TESTING"
echo "   Date: $(date)"
echo "=================================================="
echo ""

# Create results directory
RESULTS_DIR="/root/vps_test_results_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"
LOG_FILE="$RESULTS_DIR/test_report.txt"

# Logging function
log() {
    echo "$1" | tee -a "$LOG_FILE"
}

# ==========================================
# 1. SYSTEM INFORMATION
# ==========================================
log "=========================================="
log "1. SYSTEM INFORMATION"
log "=========================================="
log ""

log "=== Operating System ==="
uname -a | tee -a "$LOG_FILE"
if [ -f /etc/os-release ]; then
    cat /etc/os-release | tee -a "$LOG_FILE"
fi
log ""

log "=== Hostname ==="
hostname | tee -a "$LOG_FILE"
log ""

log "=== Uptime ==="
uptime | tee -a "$LOG_FILE"
log ""

# ==========================================
# 2. CONFIGURATION CHECK
# ==========================================
log "=========================================="
log "2. CONFIGURATION CHECK"
log "=========================================="
log ""

log "=== CPU ==="
lscpu | tee -a "$LOG_FILE"
log ""
log "Number of cores: $(nproc)" | tee -a "$LOG_FILE"
log "CPU Model: $(grep 'model name' /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)" | tee -a "$LOG_FILE"
log ""

log "=== RAM ==="
free -h | tee -a "$LOG_FILE"
log ""
TOTAL_RAM=$(free -m | awk '/Mem:/ {print $2}')
log "Total RAM: ${TOTAL_RAM} MB" | tee -a "$LOG_FILE"
log ""

log "=== Disk Space ==="
df -h | tee -a "$LOG_FILE"
log ""
lsblk | tee -a "$LOG_FILE"
log ""

log "=== Network Interfaces ==="
ip addr | tee -a "$LOG_FILE"
log ""

# ==========================================
# 3. INSTALL REQUIRED TOOLS
# ==========================================
log "=========================================="
log "3. INSTALLING TESTING TOOLS"
log "=========================================="
log ""

# Detect package manager
if command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt-get"
    UPDATE_CMD="apt-get update -qq"
    INSTALL_CMD="apt-get install -y -qq"
elif command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
    UPDATE_CMD="yum update -y -q"
    INSTALL_CMD="yum install -y -q"
elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
    UPDATE_CMD="dnf update -y -q"
    INSTALL_CMD="dnf install -y -q"
else
    log "WARNING: Package manager not found!"
    PKG_MANAGER="none"
fi

# Install tools
if [ "$PKG_MANAGER" != "none" ]; then
    log "Updating package list..."
    $UPDATE_CMD > /dev/null 2>&1
    
    log "Installing required tools..."
    TOOLS="sysbench iperf3 curl wget hdparm stress-ng htop iotop nethogs"
    
    for tool in $TOOLS; do
        if ! command -v $tool &> /dev/null; then
            log "Installing $tool..."
            $INSTALL_CMD $tool > /dev/null 2>&1 || log "Failed to install $tool"
        fi
    done
    log ""
fi

# ==========================================
# 4. CPU PERFORMANCE TEST
# ==========================================
log "=========================================="
log "4. CPU PERFORMANCE TEST"
log "=========================================="
log ""

if command -v sysbench &> /dev/null; then
    log "Running sysbench CPU test (single-threaded)..."
    sysbench cpu --cpu-max-prime=20000 --threads=1 run | tee -a "$LOG_FILE"
    log ""
    
    log "Running sysbench CPU test (multi-threaded, all cores)..."
    sysbench cpu --cpu-max-prime=20000 --threads=$(nproc) run | tee -a "$LOG_FILE"
    log ""
else
    log "sysbench not installed, skipping CPU test"
fi

# ==========================================
# 5. RAM PERFORMANCE TEST
# ==========================================
log "=========================================="
log "5. RAM PERFORMANCE TEST"
log "=========================================="
log ""

if command -v sysbench &> /dev/null; then
    log "Running sysbench memory test..."
    sysbench memory --memory-block-size=1K --memory-total-size=10G run | tee -a "$LOG_FILE"
    log ""
else
    log "sysbench not installed, skipping RAM test"
fi

# ==========================================
# 6. DISK PERFORMANCE TEST
# ==========================================
log "=========================================="
log "6. DISK PERFORMANCE TEST"
log "=========================================="
log ""

TEST_DIR="$RESULTS_DIR/disk_test"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

log "=== Write test (dd) ==="
log "Writing 1GB test file..."
dd if=/dev/zero of=testfile bs=1M count=1024 oflag=direct 2>&1 | tee -a "$LOG_FILE"
log ""

log "=== Read test (dd) ==="
log "Reading 1GB test file..."
dd if=testfile of=/dev/null bs=1M count=1024 iflag=direct 2>&1 | tee -a "$LOG_FILE"
log ""

if command -v sysbench &> /dev/null; then
    log "=== sysbench: random read/write test ==="
    sysbench fileio --file-total-size=2G prepare > /dev/null 2>&1
    sysbench fileio --file-total-size=2G --file-test-mode=rndrw --time=60 run | tee -a "$LOG_FILE"
    sysbench fileio --file-total-size=2G cleanup > /dev/null 2>&1
    log ""
fi

# IOPS test
log "=== IOPS test (4K random read) ==="
if command -v fio &> /dev/null; then
    fio --name=random-read --ioengine=libaio --iodepth=16 --rw=randread --bs=4k --direct=1 --size=1G --numjobs=1 --runtime=60 --time_based | tee -a "$LOG_FILE"
else
    log "fio not installed, using alternative method"
    log "Approximate IOPS test (4K blocks)..."
    dd if=/dev/zero of=iops_test bs=4k count=10000 oflag=direct 2>&1 | tee -a "$LOG_FILE"
fi
log ""

# Cleanup
rm -f testfile iops_test
cd - > /dev/null

# ==========================================
# 7. NETWORK TEST
# ==========================================
log "=========================================="
log "7. NETWORK CONNECTION TEST"
log "=========================================="
log ""

log "=== Ping to main DNS servers ==="
log "Google DNS (8.8.8.8):"
ping -c 5 8.8.8.8 | tee -a "$LOG_FILE"
log ""
log "Cloudflare DNS (1.1.1.1):"
ping -c 5 1.1.1.1 | tee -a "$LOG_FILE"
log ""

log "=== Download speed test ==="
log "Downloading 100MB file..."
wget -O /dev/null http://speedtest.tele2.net/100MB.zip 2>&1 | tee -a "$LOG_FILE"
log ""

if command -v curl &> /dev/null; then
    log "=== Speedtest from different locations ==="
    log "Speedtest via curl..."
    curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 - --simple 2>&1 | tee -a "$LOG_FILE"
    log ""
fi

# ==========================================
# 8. UPTIME & STABILITY
# ==========================================
log "=========================================="
log "8. UPTIME AND STABILITY"
log "=========================================="
log ""

log "=== Reboot history ==="
last reboot | head -10 | tee -a "$LOG_FILE"
log ""

log "=== Current system load average ==="
uptime | tee -a "$LOG_FILE"
log ""

log "=== Top processes by CPU ==="
ps aux --sort=-%cpu | head -10 | tee -a "$LOG_FILE"
log ""

log "=== Top processes by RAM ==="
ps aux --sort=-%mem | head -10 | tee -a "$LOG_FILE"
log ""

# ==========================================
# 9. STRESS TEST (optional)
# ==========================================
log "=========================================="
log "9. STRESS TEST (30 seconds)"
log "=========================================="
log ""

read -p "Run stress test? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command -v stress-ng &> /dev/null; then
        log "Running stress-ng for 30 seconds..."
        log "CPU stress..."
        stress-ng --cpu $(nproc) --timeout 30s --metrics-brief | tee -a "$LOG_FILE"
        log ""
        
        log "RAM stress..."
        stress-ng --vm 2 --vm-bytes 80% --timeout 30s --metrics-brief | tee -a "$LOG_FILE"
        log ""
        
        log "Disk I/O stress..."
        stress-ng --io 4 --timeout 30s --metrics-brief | tee -a "$LOG_FILE"
        log ""
    else
        log "stress-ng not installed, skipping stress test"
    fi
else
    log "Stress test skipped by user"
fi

# ==========================================
# 10. VIRTUALIZATION TYPE
# ==========================================
log "=========================================="
log "10. VIRTUALIZATION TYPE"
log "=========================================="
log ""

if command -v systemd-detect-virt &> /dev/null; then
    VIRT_TYPE=$(systemd-detect-virt)
    log "Virtualization type: $VIRT_TYPE"
elif [ -f /proc/cpuinfo ]; then
    if grep -q "QEMU" /proc/cpuinfo; then
        log "Virtualization type: KVM/QEMU"
    elif grep -q "hypervisor" /proc/cpuinfo; then
        log "Virtualization type: hypervisor detected"
    else
        log "Virtualization type: possibly bare metal or OpenVZ"
    fi
else
    log "Could not determine virtualization type"
fi
log ""

# ==========================================
# 11. FINAL REPORT
# ==========================================
log "=========================================="
log "11. FINAL REPORT"
log "=========================================="
log ""

log "Testing completed!"
log "Results saved to: $RESULTS_DIR"
log ""

log "=== Quick summary ==="
log "CPU cores: $(nproc)"
log "RAM: ${TOTAL_RAM} MB"
log "Disk root: $(df -h / | awk 'NR==2 {print $2}')"
log "Virtualization: ${VIRT_TYPE:-unknown}"
log ""

log "=== Result files ==="
ls -lh "$RESULTS_DIR" | tee -a "$LOG_FILE"
log ""

log "To view full report:"
log "cat $LOG_FILE"
log ""

echo "=================================================="
echo "   TESTING COMPLETED"
echo "   Report: $LOG_FILE"
echo "=================================================="
