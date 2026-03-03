# Создаем рабочую директорию
mkdir-p ~/bash_lesson/backup_example 
cd ~/bash_lesson/backup_example

# Создаем файлы для резервирования
mkdir-p test_data/{documents,images,configs}
echo "Это важный документ" > test_data/documents/doc1.txt
echo "Конфигурационный файл" > test_data/configs/app.cfg
touch test data/images/{img1.png,img2.jpg}

nano backup helper.sh

#!/bin/bash

# Скрипт для создания резервных копий

#Цвета для вывода (опционально, для наглядности) 
RED='\033[0;31m' 
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Базовые переменные
BACKUP_DIR="$HOME/backups"
LOG_FILE="$BACKUP_
_DIR/backup.log"
TIMESTAMP=$(date+"%Y%m%d %H%M%S").

# Проверяем, передан ли аргумент с директорией для бэкапа
if [$#-eq 0]; then
 echo-e "${RED}Ошибка: Укажите директорию для резервного копирования${NC)"
 echo "Пример:./backup_helper.sh/path/to/directory"
 exit 1
fi

SOURCE_DIR="$1"

# Проверяем существование исходной директории
if [!-d "$SOURCE_DIR" I; then
 echo-e "${RED}Ошибка: Директория "$SOURCE_DIR' не существует$(NC}"
 exit 1
fi

# Создаем директорию для бэкапов, если её нет
mkdir-p "$BACKUP_DIR"
# Функция для логирования
log_message) {
 echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
 echo-e "${GREEN}[LOG)$(NC} $1"
}

# Начало работы
log_message "== Запуск резервного копирования=="
Los_message "Источник: $SOURCE_DIR"

# Проверяем свободное место на диске (минимум 100 МБ)
MIN_SPACE_MB=100
AVAILABLE_SPACE=$(df "$BACKUP_DIR" | awk 'NR==2 (print $4}')
AVAILABLE_SPACE_MB=$((AVAILABLE_SPACE / 1024))

if ["$AVAILABLE_SPACE_MB"-It "$MIN_SPACE_MB" 1; then
log_message "${YELLOW}Внимание: Мало свободного места ($AVAILABLE_SPACE_МВ МБ)
${NC}"
 read -р "Продолжить? (у/п): " -n 1 -г
 echo
 if [I ! $REPLY =~ ^[Yy]$ Il; then
  log_message "Резервное копирование отменено пользователем"
  exit 1
 fi 
fi

# Создаем имя архива
BASENAME=$(basename "$SOURCE_DIR")
BACKUP_FILE="$BACKUP_DIR/${BASENAME)_backup_$TIMESTAMP.tar.gz"

# Создаем архив 
log_message "Создание архива: $BACKUP_FILE"
tar -czf "$BACKUP_FILE" -C "$(dirname "$SOURCE_DIR"" "$(basename "$SOURCE_DIR")" 2>> "
$LOG_FILE"

# Проверяем успешность создания
if [$? -eq 0 ]; then
 FILE_SIZE=$(du-h "$BACKUP_FILE" | cut -f1)
 log_message "Архив успешно создан: $BACKUP_FILE (SFILE_SIZE)"
else
 log_message "${RED}Ошибка при создании архива${NC}"
 exit 1
fi 
echo "Размер: $(du-h "$BACKUP_FILE" | cut-f1)"
echo "Файлов в архиве: $(tar -tzf "$BACKUP_FILE" | wc-1)"
echo "Контрольная сумма (md5): $(md5sum "$BACKUP_FILE" | cut -d"'-f1)"

# "Отправляем уведомление" (имитация)
echo "=== УВЕДОМЛЕНИЕ ===" > "SBACKUP_DIR/last _notification.txt"
echo "Резервная копия $BASENAME создана успешно" >> "$BACKUP_DIR/last_notification.txt"

echo "Время: S(date)" >> "$BACKUP_DIR/last_notification.txt"
echo "Файл: $BACKUP_FILE" >> "$BACKUP_DIR/last_notification.txt"

log_message "Резервное копирование завершено успешно!"
log_message "Лог сохранен: $LOG_FILE"

# Вывод последних 5 записей лога 
echo-e "\n${YELLOW}Последние записи в логе:${NC}"
tail-5 "$LOG_ FILE"
