#!/bin/bash

# Скрипт мониторинга uptime и доступности VPS
# Запускается в фоне и проверяет доступность каждые 5 минут

MONITOR_DIR="/root/uptime_monitor"
LOG_FILE="$MONITOR_DIR/uptime_log.txt"
STATS_FILE="$MONITOR_DIR/uptime_stats.txt"

# Создаем директорию
mkdir -p "$MONITOR_DIR"

# Функция для логирования
log_status() {
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$TIMESTAMP - $1" >> "$LOG_FILE"
}

# Функция для проверки доступности
check_availability() {
    # Проверяем доступность интернета
    if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        INTERNET="OK"
    else
        INTERNET="FAIL"
    fi
    
    # Проверяем загрузку CPU
    CPU_LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    
    # Проверяем использование RAM
    RAM_USED=$(free | awk '/Mem:/ {printf "%.0f", ($3/$2)*100}')
    
    # Проверяем использование диска
    DISK_USED=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    
    # Время работы
    UPTIME=$(uptime -p)
    
    # Логируем
    log_status "Internet: $INTERNET | CPU Load: $CPU_LOAD | RAM: ${RAM_USED}% | Disk: ${DISK_USED}% | Uptime: $UPTIME"
}

# Функция для генерации статистики
generate_stats() {
    echo "========================================" > "$STATS_FILE"
    echo "СТАТИСТИКА UPTIME МОНИТОРИНГА" >> "$STATS_FILE"
    echo "Сгенерировано: $(date)" >> "$STATS_FILE"
    echo "========================================" >> "$STATS_FILE"
    echo "" >> "$STATS_FILE"
    
    # Всего проверок
    TOTAL_CHECKS=$(grep -c "Internet:" "$LOG_FILE")
    echo "Всего проверок: $TOTAL_CHECKS" >> "$STATS_FILE"
    
    # Успешных проверок
    SUCCESS_CHECKS=$(grep -c "Internet: OK" "$LOG_FILE")
    echo "Успешных проверок: $SUCCESS_CHECKS" >> "$STATS_FILE"
    
    # Неудачных проверок
    FAIL_CHECKS=$(grep -c "Internet: FAIL" "$LOG_FILE")
    echo "Неудачных проверок: $FAIL_CHECKS" >> "$STATS_FILE"
    
    # Процент uptime
    if [ $TOTAL_CHECKS -gt 0 ]; then
        UPTIME_PERCENT=$(awk "BEGIN {printf \"%.2f\", ($SUCCESS_CHECKS/$TOTAL_CHECKS)*100}")
        echo "Uptime процент: ${UPTIME_PERCENT}%" >> "$STATS_FILE"
    fi
    
    echo "" >> "$STATS_FILE"
    echo "Последние 10 записей:" >> "$STATS_FILE"
    tail -10 "$LOG_FILE" >> "$STATS_FILE"
}

# Основной цикл мониторинга
main_loop() {
    echo "Запуск uptime мониторинга..."
    echo "Логи сохраняются в: $LOG_FILE"
    echo "Статистика: $STATS_FILE"
    echo ""
    echo "Для остановки: kill $(cat $MONITOR_DIR/monitor.pid 2>/dev/null)"
    
    # Сохраняем PID
    echo $$ > "$MONITOR_DIR/monitor.pid"
    
    # Начальная запись
    log_status "=== МОНИТОРИНГ ЗАПУЩЕН ==="
    
    # Бесконечный цикл
    while true; do
        check_availability
        generate_stats
        sleep 300  # 5 минут
    done
}

# Запуск в зависимости от аргумента
case "$1" in
    start)
        if [ -f "$MONITOR_DIR/monitor.pid" ]; then
            PID=$(cat "$MONITOR_DIR/monitor.pid")
            if ps -p $PID > /dev/null 2>&1; then
                echo "Мониторинг уже запущен (PID: $PID)"
                exit 1
            fi
        fi
        nohup $0 run > /dev/null 2>&1 &
        echo "Мониторинг запущен в фоне"
        echo "PID: $!"
        ;;
    stop)
        if [ -f "$MONITOR_DIR/monitor.pid" ]; then
            PID=$(cat "$MONITOR_DIR/monitor.pid")
            kill $PID 2>/dev/null
            rm -f "$MONITOR_DIR/monitor.pid"
            echo "Мониторинг остановлен"
        else
            echo "Мониторинг не запущен"
        fi
        ;;
    status)
        if [ -f "$MONITOR_DIR/monitor.pid" ]; then
            PID=$(cat "$MONITOR_DIR/monitor.pid")
            if ps -p $PID > /dev/null 2>&1; then
                echo "Мониторинг работает (PID: $PID)"
                echo ""
                cat "$STATS_FILE" 2>/dev/null || echo "Статистика еще не сгенерирована"
            else
                echo "Процесс не найден (PID в файле: $PID)"
            fi
        else
            echo "Мониторинг не запущен"
        fi
        ;;
    run)
        main_loop
        ;;
    *)
        echo "Использование: $0 {start|stop|status}"
        echo ""
        echo "  start  - запустить мониторинг в фоне"
        echo "  stop   - остановить мониторинг"
        echo "  status - показать статус и статистику"
        exit 1
        ;;
esac
