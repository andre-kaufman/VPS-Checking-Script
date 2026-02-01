#!/bin/bash

# Script for monitoring VPS uptime and availability
# Runs in the background and checks availability every 5 minutes

MONITOR_DIR="/root/uptime_monitor"
LOG_FILE="$MONITOR_DIR/uptime_log.txt"
STATS_FILE="$MONITOR_DIR/uptime_stats.txt"

# Create directory if it doesn't exist
mkdir -p "$MONITOR_DIR"

# Logging function
log_status() {
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$TIMESTAMP - $1" >> "$LOG_FILE"
}

# Availability check function
check_availability() {
    # Check internet connectivity
    if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        INTERNET="OK"
    else
        INTERNET="FAIL"
    fi
    
    # Get CPU load average (1-minute)
    CPU_LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    
    # RAM usage percentage
    RAM_USED=$(free | awk '/Mem:/ {printf "%.0f", ($3/$2)*100}')
    
    # Disk usage percentage (root partition)
    DISK_USED=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    
    # System uptime
    UPTIME=$(uptime -p)
    
    # Log the status
    log_status "Internet: $INTERNET | CPU Load: $CPU_LOAD | RAM: ${RAM_USED}% | Disk: ${DISK_USED}% | Uptime: $UPTIME"
}

# Generate statistics function
generate_stats() {
    echo "========================================" > "$STATS_FILE"
    echo "UPTIME MONITORING STATISTICS" >> "$STATS_FILE"
    echo "Generated: $(date)" >> "$STATS_FILE"
    echo "========================================" >> "$STATS_FILE"
    echo "" >> "$STATS_FILE"
    
    # Total checks
    TOTAL_CHECKS=$(grep -c "Internet:" "$LOG_FILE")
    echo "Total checks: $TOTAL_CHECKS" >> "$STATS_FILE"
    
    # Successful checks
    SUCCESS_CHECKS=$(grep -c "Internet: OK" "$LOG_FILE")
    echo "Successful checks: $SUCCESS_CHECKS" >> "$STATS_FILE"
    
    # Failed checks
    FAIL_CHECKS=$(grep -c "Internet: FAIL" "$LOG_FILE")
    echo "Failed checks: $FAIL_CHECKS" >> "$STATS_FILE"
    
    # Uptime percentage
    if [ $TOTAL_CHECKS -gt 0 ]; then
        UPTIME_PERCENT=$(awk "BEGIN {printf \"%.2f\", ($SUCCESS_CHECKS/$TOTAL_CHECKS)*100}")
        echo "Uptime percentage: ${UPTIME_PERCENT}%" >> "$STATS_FILE"
    fi
    
    echo "" >> "$STATS_FILE"
    echo "Last 10 entries:" >> "$STATS_FILE"
    tail -10 "$LOG_FILE" >> "$STATS_FILE"
}

# Main monitoring loop
main_loop() {
    echo "Starting uptime monitoring..."
    echo "Logs are saved to: $LOG_FILE"
    echo "Statistics: $STATS_FILE"
    echo ""
    echo "To stop: kill $(cat $MONITOR_DIR/monitor.pid 2>/dev/null)"
    
    # Save PID
    echo $$ > "$MONITOR_DIR/monitor.pid"
    
    # Initial log entry
    log_status "=== MONITORING STARTED ==="
    
    # Infinite loop
    while true; do
        check_availability
        generate_stats
        sleep 300  # 5 minutes
    done
}

# Handle command-line arguments
case "$1" in
    start)
        if [ -f "$MONITOR_DIR/monitor.pid" ]; then
            PID=$(cat "$MONITOR_DIR/monitor.pid")
            if ps -p $PID > /dev/null 2>&1; then
                echo "Monitoring is already running (PID: $PID)"
                exit 1
            fi
        fi
        nohup $0 run > /dev/null 2>&1 &
        echo "Monitoring started in background"
        echo "PID: $!"
        ;;
    stop)
        if [ -f "$MONITOR_DIR/monitor.pid" ]; then
            PID=$(cat "$MONITOR_DIR/monitor.pid")
            kill $PID 2>/dev/null
            rm -f "$MONITOR_DIR/monitor.pid"
            echo "Monitoring stopped"
        else
            echo "Monitoring is not running"
        fi
        ;;
    status)
        if [ -f "$MONITOR_DIR/monitor.pid" ]; then
            PID=$(cat "$MONITOR_DIR/monitor.pid")
            if ps -p $PID > /dev/null 2>&1; then
                echo "Monitoring is running (PID: $PID)"
                echo ""
                cat "$STATS_FILE" 2>/dev/null || echo "Statistics not yet generated"
            else
                echo "Process not found (PID in file: $PID)"
            fi
        else
            echo "Monitoring is not running"
        fi
        ;;
    run)
        main_loop
        ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        echo ""
        echo "  start  - start monitoring in background"
        echo "  stop   - stop monitoring"
        echo "  status - show status and statistics"
        exit 1
        ;;
esac
