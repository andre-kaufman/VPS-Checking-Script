#!/bin/bash

# Комплексный скрипт тестирования VPS
# Проверяет: производительность, стабильность, соответствие конфигурации

echo "=================================================="
echo "   КОМПЛЕКСНОЕ ТЕСТИРОВАНИЕ VPS"
echo "   Дата: $(date)"
echo "=================================================="
echo ""

# Создаем директорию для результатов
RESULTS_DIR="/root/vps_test_results_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"
LOG_FILE="$RESULTS_DIR/test_report.txt"

# Функция логирования
log() {
    echo "$1" | tee -a "$LOG_FILE"
}

# ==========================================
# 1. ИНФОРМАЦИЯ О СИСТЕМЕ
# ==========================================
log "=========================================="
log "1. ИНФОРМАЦИЯ О СИСТЕМЕ"
log "=========================================="
log ""

log "=== Операционная система ==="
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
# 2. ПРОВЕРКА КОНФИГУРАЦИИ
# ==========================================
log "=========================================="
log "2. ПРОВЕРКА КОНФИГУРАЦИИ"
log "=========================================="
log ""

log "=== CPU (процессор) ==="
lscpu | tee -a "$LOG_FILE"
log ""
log "Количество ядер: $(nproc)" | tee -a "$LOG_FILE"
log "Модель CPU: $(grep 'model name' /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)" | tee -a "$LOG_FILE"
log ""

log "=== RAM (оперативная память) ==="
free -h | tee -a "$LOG_FILE"
log ""
TOTAL_RAM=$(free -m | awk '/Mem:/ {print $2}')
log "Общая память: ${TOTAL_RAM} MB" | tee -a "$LOG_FILE"
log ""

log "=== Дисковое пространство ==="
df -h | tee -a "$LOG_FILE"
log ""
lsblk | tee -a "$LOG_FILE"
log ""

log "=== Сетевые интерфейсы ==="
ip addr | tee -a "$LOG_FILE"
log ""

# ==========================================
# 3. УСТАНОВКА НЕОБХОДИМЫХ УТИЛИТ
# ==========================================
log "=========================================="
log "3. УСТАНОВКА УТИЛИТ ДЛЯ ТЕСТИРОВАНИЯ"
log "=========================================="
log ""

# Определяем пакетный менеджер
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
    log "ПРЕДУПРЕЖДЕНИЕ: Пакетный менеджер не найден!"
    PKG_MANAGER="none"
fi

# Установка утилит
if [ "$PKG_MANAGER" != "none" ]; then
    log "Обновление списка пакетов..."
    $UPDATE_CMD > /dev/null 2>&1
    
    log "Установка необходимых утилит..."
    TOOLS="sysbench iperf3 curl wget hdparm stress-ng htop iotop nethogs"
    
    for tool in $TOOLS; do
        if ! command -v $tool &> /dev/null; then
            log "Установка $tool..."
            $INSTALL_CMD $tool > /dev/null 2>&1 || log "Не удалось установить $tool"
        fi
    done
    log ""
fi

# ==========================================
# 4. ТЕСТ CPU (производительность процессора)
# ==========================================
log "=========================================="
log "4. ТЕСТ ПРОИЗВОДИТЕЛЬНОСТИ CPU"
log "=========================================="
log ""

if command -v sysbench &> /dev/null; then
    log "Запуск sysbench CPU тест (однопоточный)..."
    sysbench cpu --cpu-max-prime=20000 --threads=1 run | tee -a "$LOG_FILE"
    log ""
    
    log "Запуск sysbench CPU тест (многопоточный, все ядра)..."
    sysbench cpu --cpu-max-prime=20000 --threads=$(nproc) run | tee -a "$LOG_FILE"
    log ""
else
    log "sysbench не установлен, пропуск CPU теста"
fi

# ==========================================
# 5. ТЕСТ RAM (тест памяти)
# ==========================================
log "=========================================="
log "5. ТЕСТ ПРОИЗВОДИТЕЛЬНОСТИ RAM"
log "=========================================="
log ""

if command -v sysbench &> /dev/null; then
    log "Запуск sysbench RAM тест (скорость памяти)..."
    sysbench memory --memory-block-size=1K --memory-total-size=10G run | tee -a "$LOG_FILE"
    log ""
else
    log "sysbench не установлен, пропуск RAM теста"
fi

# ==========================================
# 6. ТЕСТ ДИСКА (производительность диска)
# ==========================================
log "=========================================="
log "6. ТЕСТ ПРОИЗВОДИТЕЛЬНОСТИ ДИСКА"
log "=========================================="
log ""

# Создаем тестовую директорию
TEST_DIR="$RESULTS_DIR/disk_test"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

log "=== Тест записи (dd) ==="
log "Тестовая запись 1GB..."
dd if=/dev/zero of=testfile bs=1M count=1024 oflag=direct 2>&1 | tee -a "$LOG_FILE"
log ""

log "=== Тест чтения (dd) ==="
log "Тестовое чтение 1GB..."
dd if=testfile of=/dev/null bs=1M count=1024 iflag=direct 2>&1 | tee -a "$LOG_FILE"
log ""

if command -v sysbench &> /dev/null; then
    log "=== sysbench: тест случайного чтения/записи ==="
    sysbench fileio --file-total-size=2G prepare > /dev/null 2>&1
    sysbench fileio --file-total-size=2G --file-test-mode=rndrw --time=60 run | tee -a "$LOG_FILE"
    sysbench fileio --file-total-size=2G cleanup > /dev/null 2>&1
    log ""
fi

# IOPS тест
log "=== Тест IOPS (случайное чтение 4K блоками) ==="
if command -v fio &> /dev/null; then
    fio --name=random-read --ioengine=libaio --iodepth=16 --rw=randread --bs=4k --direct=1 --size=1G --numjobs=1 --runtime=60 --time_based | tee -a "$LOG_FILE"
else
    log "fio не установлен, используем альтернативный метод"
    # Простой IOPS тест через dd
    log "Примерный IOPS тест (4K блоки)..."
    dd if=/dev/zero of=iops_test bs=4k count=10000 oflag=direct 2>&1 | tee -a "$LOG_FILE"
fi
log ""

# Очистка
rm -f testfile iops_test
cd - > /dev/null

# ==========================================
# 7. ТЕСТ СЕТИ (скорость интернета)
# ==========================================
log "=========================================="
log "7. ТЕСТ СЕТЕВОГО ПОДКЛЮЧЕНИЯ"
log "=========================================="
log ""

log "=== Ping к основным DNS ==="
log "Google DNS (8.8.8.8):"
ping -c 5 8.8.8.8 | tee -a "$LOG_FILE"
log ""
log "Cloudflare DNS (1.1.1.1):"
ping -c 5 1.1.1.1 | tee -a "$LOG_FILE"
log ""

log "=== Скорость загрузки (download speed) ==="
log "Тест загрузки 100MB файла..."
wget -O /dev/null http://speedtest.tele2.net/100MB.zip 2>&1 | tee -a "$LOG_FILE"
log ""

if command -v curl &> /dev/null; then
    log "=== Тест с разных локаций ==="
    log "Speedtest через curl..."
    curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 - --simple 2>&1 | tee -a "$LOG_FILE"
    log ""
fi

# ==========================================
# 8. МОНИТОРИНГ UPTIME (проверка стабильности)
# ==========================================
log "=========================================="
log "8. UPTIME И СТАБИЛЬНОСТЬ"
log "=========================================="
log ""

log "=== История загрузки системы ==="
last reboot | head -10 | tee -a "$LOG_FILE"
log ""

log "=== Средняя загрузка системы (Load Average) ==="
uptime | tee -a "$LOG_FILE"
log ""

log "=== Текущие процессы (топ по CPU) ==="
ps aux --sort=-%cpu | head -10 | tee -a "$LOG_FILE"
log ""

log "=== Текущие процессы (топ по RAM) ==="
ps aux --sort=-%mem | head -10 | tee -a "$LOG_FILE"
log ""

# ==========================================
# 9. СТРЕСС-ТЕСТ (опционально)
# ==========================================
log "=========================================="
log "9. СТРЕСС-ТЕСТ (30 секунд)"
log "=========================================="
log ""

read -p "Запустить стресс-тест? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command -v stress-ng &> /dev/null; then
        log "Запуск stress-ng на 30 секунд..."
        log "Нагрузка на CPU..."
        stress-ng --cpu $(nproc) --timeout 30s --metrics-brief | tee -a "$LOG_FILE"
        log ""
        
        log "Нагрузка на RAM..."
        stress-ng --vm 2 --vm-bytes 80% --timeout 30s --metrics-brief | tee -a "$LOG_FILE"
        log ""
        
        log "Нагрузка на диск..."
        stress-ng --io 4 --timeout 30s --metrics-brief | tee -a "$LOG_FILE"
        log ""
    else
        log "stress-ng не установлен, пропуск стресс-теста"
    fi
else
    log "Стресс-тест пропущен пользователем"
fi

# ==========================================
# 10. ПРОВЕРКА ВИРТУАЛИЗАЦИИ
# ==========================================
log "=========================================="
log "10. ТИП ВИРТУАЛИЗАЦИИ"
log "=========================================="
log ""

if command -v systemd-detect-virt &> /dev/null; then
    VIRT_TYPE=$(systemd-detect-virt)
    log "Тип виртуализации: $VIRT_TYPE"
elif [ -f /proc/cpuinfo ]; then
    if grep -q "QEMU" /proc/cpuinfo; then
        log "Тип виртуализации: KVM/QEMU"
    elif grep -q "hypervisor" /proc/cpuinfo; then
        log "Тип виртуализации: обнаружен гипервизор"
    else
        log "Тип виртуализации: возможно, физический сервер или OpenVZ"
    fi
else
    log "Не удалось определить тип виртуализации"
fi
log ""

# ==========================================
# 11. ИТОГОВЫЙ ОТЧЕТ
# ==========================================
log "=========================================="
log "11. ИТОГОВЫЙ ОТЧЕТ"
log "=========================================="
log ""

log "Тестирование завершено!"
log "Результаты сохранены в: $RESULTS_DIR"
log ""

log "=== Краткая сводка ==="
log "CPU ядер: $(nproc)"
log "RAM: ${TOTAL_RAM} MB"
log "Диск: $(df -h / | awk 'NR==2 {print $2}')"
log "Виртуализация: $VIRT_TYPE"
log ""

log "=== Файлы с результатами ==="
ls -lh "$RESULTS_DIR" | tee -a "$LOG_FILE"
log ""

log "Для просмотра полного отчета:"
log "cat $LOG_FILE"
log ""

echo "=================================================="
echo "   ТЕСТИРОВАНИЕ ЗАВЕРШЕНО"
echo "   Отчет: $LOG_FILE"
echo "=================================================="
