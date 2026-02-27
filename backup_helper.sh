#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEFAULT_BACKUP_DIR="$HOME/backups"
MAX_BACKUP_AGE_DAYS=7
LOG_FILE=""
BACKUP_DIR=""
SOURCE_DIR=""
BACKUP_FILE=""
TIMESTAMP=""
BACKUP_NAME=""

show_help() {
    cat << EOF
${BLUE}=================================================================${NC}
${GREEN}СКРИПТ АВТОМАТИЧЕСКОГО РЕЗЕРВНОГО КОПИРОВАНИЯ${NC}
${BLUE}=================================================================${NC}

${YELLOW}ИСПОЛЬЗОВАНИЕ:${NC}
    $0 [ОПЦИИ] <исходный_каталог> [каталог_назначения]

${YELLOW}ОБЯЗАТЕЛЬНЫЕ АРГУМЕНТЫ:${NC}
    <исходный_каталог>      Каталог для копирования

${YELLOW}ОПЦИОНАЛЬНЫЕ АРГУМЕНТЫ:${NC}
    [каталог_назначения]    Каталог для сохранения бэкапов
                             (по умолчанию: $DEFAULT_BACKUP_DIR)

${YELLOW}ОПЦИИ:${NC}
    -h, --help              Показать справку
    -d, --days ЧИСЛО        Удалять бэкапы старше ЧИСЛО дней
                             (по умолчанию: $MAX_BACKUP_AGE_DAYS)
    -l, --log ФАЙЛ          Указать путь к файлу лога
    -q, --quiet             Тихий режим
    -v, --verbose           Подробный режим

${YELLOW}ПРИМЕРЫ:${NC}
    $0 ./test_data
    $0 ./test_data /mnt/backups
    $0 -d 14 ./test_data
    $0 --help

${BLUE}=================================================================${NC}
EOF
    exit 0
}

log_message() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    if [ "$QUIET_MODE" != "true" ]; then
        case "$level" in
            "ERROR")
                echo -e "${RED}[$timestamp] [$level] $message${NC}"
                ;;
            "WARNING")
                echo -e "${YELLOW}[$timestamp] [$level] $message${NC}"
                ;;
            "SUCCESS")
                echo -e "${GREEN}[$timestamp] [$level] $message${NC}"
                ;;
            *)
                if [ "$VERBOSE_MODE" = "true" ] || [ "$level" = "INFO" ]; then
                    echo -e "${BLUE}[$timestamp] [$level] $message${NC}"
                fi
                ;;
        esac
    fi
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_message "Команда '$1' не найдена" "ERROR"
        return 1
    fi
    return 0
}

check_recent_backup() {
    local source_dir="$1"
    local backup_dir="$2"
    local hours="${3:-1}"
    
    log_message "Проверка бэкапов за последние $hours часы" "INFO"
    
    local source_basename=$(basename "$source_dir")
    local recent_backups=$(find "$backup_dir" -name "backup_${source_basename}_*.tar.gz" -type f -mmin -$((hours * 60)) 2>/dev/null)
    
    if [ -n "$recent_backups" ]; then
        local backup_count=$(echo "$recent_backups" | wc -l)
        log_message "Найдено $backup_count свежих бэкапов" "WARNING"
        
        if [ "$QUIET_MODE" != "true" ]; then
            echo -e -n "${YELLOW}Свежий бэкап уже существует. Продолжить? (y/N): ${NC}"
            read -r answer
            if [[ ! "$answer" =~ ^[YyДд]$ ]]; then
                log_message "Операция отменена" "INFO"
                exit 0
            fi
        fi
    else
        log_message "Свежих бэкапов не найдено" "INFO"
    fi
}

cleanup_old_backups() {
    local backup_dir="$1"
    local days="$2"
    
    log_message "Проверка бэкапов старше $days дней" "INFO"
    
    if [ ! -d "$backup_dir" ]; then
        log_message "Директория не существует: $backup_dir" "WARNING"
        return
    fi
    
    local old_backups=$(find "$backup_dir" -name "backup_*.tar.gz" -type f -mtime +$days 2>/dev/null)
    
    if [ -n "$old_backups" ]; then
        local backup_count=$(echo "$old_backups" | wc -l)
        local total_size=$(find "$backup_dir" -name "backup_*.tar.gz" -type f -mtime +$days -exec du -ch {} + | grep total$ | cut -f1)
        
        log_message "Найдено $backup_count старых бэкапов ($total_size)" "WARNING"
        
        find "$backup_dir" -name "backup_*.tar.gz" -type f -mtime +$days -delete 2>/dev/null
        log_message "Удалено $backup_count старых бэкапов" "SUCCESS"
        
        find "$backup_dir" -name "backup_checksums.md5" -type f -mtime +$days -delete 2>/dev/null
    else
        log_message "Старых бэкапов не найдено" "INFO"
    fi
}

check_disk_space() {
    local source_dir="$1"
    local backup_dir="$2"
    
    log_message "Проверка свободного места" "INFO"
    
    check_command "df" || return 1
    check_command "du" || return 1
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        AVAILABLE_SPACE=$(df -k "$backup_dir" | awk 'NR==2 {print $4}')
    else
        AVAILABLE_SPACE=$(df --output=avail "$backup_dir" 2>/dev/null | tail -n1)
        if [ -z "$AVAILABLE_SPACE" ]; then
            AVAILABLE_SPACE=$(df "$backup_dir" | awk 'NR==2 {print $4}')
        fi
    fi
    
    SOURCE_SIZE=$(du -sk "$source_dir" 2>/dev/null | awk '{print $1}')
    
    if [ -z "$SOURCE_SIZE" ]; then
        log_message "Не удалось определить размер" "ERROR"
        return 1
    fi
    
    REQUIRED_SPACE=$((SOURCE_SIZE + SOURCE_SIZE / 5))
    
    local available_mb=$((AVAILABLE_SPACE / 1024))
    local required_mb=$((REQUIRED_SPACE / 1024))
    
    log_message "Доступно: ${available_mb} МБ, Требуется: ${required_mb} МБ" "INFO"
    
    if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
        log_message "Недостаточно места! Нужно ещё $(( (REQUIRED_SPACE - AVAILABLE_SPACE) / 1024 )) МБ" "ERROR"
        return 1
    fi
    
    log_message "Места достаточно" "SUCCESS"
    return 0
}

create_backup() {
    local source_dir="$1"
    local backup_file="$2"
    
    log_message "Создание архива: $(basename "$backup_file")" "INFO"
    
    check_command "tar" || return 1
    
    if tar -czf "$backup_file" -C "$(dirname "$source_dir")" "$(basename "$source_dir")" 2>> "$LOG_FILE"; then
        local archive_size=$(du -h "$backup_file" | cut -f1)
        log_message "Архив создан ($archive_size)" "SUCCESS"
        return 0
    else
        log_message "Ошибка при создании архива" "ERROR"
        return 1
    fi
}

get_archive_info() {
    local archive_file="$1"
    
    if [ ! -f "$archive_file" ]; then
        log_message "Архив не найден" "ERROR"
        return 1
    fi
    
    local archive_size=$(du -h "$archive_file" | cut -f1)
    local file_count=$(tar -tzf "$archive_file" 2>/dev/null | wc -l)
    local md5_sum=""
    
    if check_command "md5sum" &>/dev/null; then
        md5_sum=$(md5sum "$archive_file" | cut -d' ' -f1)
    elif check_command "md5" &>/dev/null; then
        md5_sum=$(md5 -q "$archive_file")
    fi
    
    echo -e "${GREEN}Информация об архиве:${NC}"
    echo "  Размер: $archive_size"
    echo "  Файлов: $file_count"
    if [ -n "$md5_sum" ]; then
        echo "  MD5: $md5_sum"
    fi
}

create_notification() {
    local backup_file="$1"
    local notification_file="$2"
    
    local archive_size=$(du -h "$backup_file" | cut -f1)
    local file_count=$(tar -tzf "$backup_file" 2>/dev/null | wc -l)
    
    cat > "$notification_file" << EOF
========================================
РЕЗЕРВНОЕ КОПИРОВАНИЕ
========================================
Время: $(date '+%Y-%m-%d %H:%M:%S')
Статус: УСПЕШНО
Файл: $(basename "$backup_file")
Размер: $archive_size
Файлов: $file_count
Лог: $LOG_FILE
========================================
EOF
    
    log_message "Уведомление сохранено" "INFO"
}

QUIET_MODE="false"
VERBOSE_MODE="false"
DAYS="$MAX_BACKUP_AGE_DAYS"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -d|--days)
            if [[ "$2" =~ ^[0-9]+$ ]]; then
                DAYS="$2"
                shift 2
            else
                echo -e "${RED}Ошибка: после -d должно быть число${NC}"
                exit 1
            fi
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -q|--quiet)
            QUIET_MODE="true"
            shift
            ;;
        -v|--verbose)
            VERBOSE_MODE="true"
            shift
            ;;
        -*)
            echo -e "${RED}Неизвестная опция: $1${NC}"
            show_help
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo -e "${RED}Ошибка: не указан исходный каталог${NC}"
    show_help
fi

SOURCE_DIR="$1"
BACKUP_DIR="${2:-$DEFAULT_BACKUP_DIR}"

if [ -z "$LOG_FILE" ]; then
    LOG_FILE="$BACKUP_DIR/backup.log"
fi

mkdir -p "$(dirname "$LOG_FILE")"

log_message "===================================" "INFO"
log_message "ЗАПУСК РЕЗЕРВНОГО КОПИРОВАНИЯ" "INFO"
log_message "===================================" "INFO"
log_message "Исходный каталог: $SOURCE_DIR" "INFO"
log_message "Каталог бэкапов: $BACKUP_DIR" "INFO"
log_message "Удаление старых бэкапов: старше $DAYS дней" "INFO"

mkdir -p "$BACKUP_DIR" 2>/dev/null
if [ $? -ne 0 ]; then
    log_message "Не удалось создать директорию: $BACKUP_DIR" "ERROR"
    exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
    log_message "Исходный каталог не существует: $SOURCE_DIR" "ERROR"
    exit 1
fi

check_recent_backup "$SOURCE_DIR" "$BACKUP_DIR" 1

if ! check_disk_space "$SOURCE_DIR" "$BACKUP_DIR"; then
    exit 1
fi

cleanup_old_backups "$BACKUP_DIR" "$DAYS"

SOURCE_BASENAME=$(basename "$SOURCE_DIR")
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="backup_${SOURCE_BASENAME}_${TIMESTAMP}.tar.gz"
BACKUP_FILE="$BACKUP_DIR/$BACKUP_NAME"

if ! create_backup "$SOURCE_DIR" "$BACKUP_FILE"; then
    exit 1
fi

get_archive_info "$BACKUP_FILE"

if check_command "md5sum" &>/dev/null; then
    md5sum "$BACKUP_FILE" >> "$BACKUP_DIR/backup_checksums.md5"
elif check_command "md5" &>/dev/null; then
    md5 -r "$BACKUP_FILE" >> "$BACKUP_DIR/backup_checksums.md5"
fi

create_notification "$BACKUP_FILE" "$BACKUP_DIR/last_notification.txt"

log_message "===================================" "SUCCESS"
log_message "РЕЗЕРВНОЕ КОПИРОВАНИЕ ЗАВЕРШЕНО" "SUCCESS"
log_message "===================================" "SUCCESS"
log_message "Бэкап: $BACKUP_FILE" "INFO"
log_message "Лог: $LOG_FILE" "INFO"

if [ "$QUIET_MODE" != "true" ]; then
    echo -e "\n${YELLOW}Последние 5 записей лога:${NC}"
    tail -5 "$LOG_FILE"
fi

exit 0