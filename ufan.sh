#!/bin/sh

VERSION="1.4"
UFAN_VERSION="2.0.2"
BIN="/usr/sbin/ufan"
INIT="/etc/init.d/ufan"
CONF="/etc/sysupgrade.conf"
FAN_SCRIPT="/usr/share/collectd/pwmfan.sh"
FAN_LUCI_JS="/www/luci-static/resources/statistics/rrdtool/definitions/exec.js"
COLLECTD_CONF="/etc/collectd.conf"
UFAN_VER_FILE="/etc/ufan.version"

# Функция получения установленной версии uFan
get_installed_ufan_version() {
  if [ -f "$BIN" ]; then
    if [ -f "$UFAN_VER_FILE" ]; then
      cat "$UFAN_VER_FILE"
    else
      echo "2.0.2" # Дефолт для старых ручных установок
    fi
  else
    echo "не установлен"
  fi
}

# Функция получения последней доступной версии uFan с GitHub
fetch_latest_ufan_version() {
  wget --no-check-certificate -qO- https://api.github.com/repos/andros-ua/ufan/releases/latest | sed -n 's/.*"tag_name":"\([^"]*\)".*/\1/p'
}

# Функция проверки статуса установки компонентов
check_status() {
  if [ -f "$BIN" ] && [ -f "$INIT" ]; then
    local_ufan_ver=$(get_installed_ufan_version)
    status_ufan="Установлен ($local_ufan_ver)"
  else
    status_ufan="Не установлен"
  fi

  if [ -f "$FAN_SCRIPT" ] && [ -f "$FAN_LUCI_JS" ]; then
    status_fan="Установлен"
  else
    status_fan="Не установлен"
  fi
}

# Функция вывода меню
show_menu() {
  check_status
  echo "=================================================="
  echo "  Установщик uFan для Comfast WR-632AX"
  echo "  Версия скрипта: $VERSION"
  echo "=================================================="
  echo "Текущий статус компонентов:"
  echo "  Служба uFan:            $status_ufan (доступна v$UFAN_VERSION)"
  echo "  Мониторинг вентилятора: $status_fan"
  echo "--------------------------------------------------"
  echo "Выберите действие:"
  echo "  [1] Установить / Переустановить uFan"
  echo "  [2] Установить / Обновить мониторинг кулера"
  echo "  [3] Удалить uFan и мониторинг полностью"
  echo "  [99] Проверить обновления скрипта и uFan"
  echo "  [0] Выход"
  echo "=================================================="
  printf "Ваш выбор: "
}

# Функция настройки автосохранения при обновлении (sysupgrade)
ask_sysupgrade() {
  printf "\nСохранять установленные файлы при будущем обновлении прошивки роутера? (y/n) [по умолчанию: y]: "
  read -r keep
  if [ "$keep" != "n" ] && [ "$keep" != "N" ]; then
    # Добавление uFan в sysupgrade
    if [ -f "$BIN" ]; then
      grep -qF "$BIN" "$CONF" || echo "$BIN" >> "$CONF"
    fi
    if [ -f "$INIT" ]; then
      grep -qF "$INIT" "$CONF" || echo "$INIT" >> "$CONF"
    fi
    if [ -f "$UFAN_VER_FILE" ]; then
      grep -qF "$UFAN_VER_FILE" "$CONF" || echo "$UFAN_VER_FILE" >> "$CONF"
    fi
    # Добавление Fan monitoring в sysupgrade если они есть
    if [ -f "$FAN_SCRIPT" ]; then
      grep -qF "$COLLECTD_CONF" "$CONF" || echo "$COLLECTD_CONF" >> "$CONF"
      grep -qF "$FAN_SCRIPT" "$CONF" || echo "$FAN_SCRIPT" >> "$CONF"
      grep -qF "$FAN_LUCI_JS" "$CONF" || echo "$FAN_LUCI_JS" >> "$CONF"
    fi
    echo "Файлы успешно добавлены в список сохранения ($CONF)."
  else
    echo "Файлы НЕ будут сохраняться при обновлении прошивки."
  fi
}

# Функция установки uFan
install_ufan() {
  echo -e "\n--- Установка uFan ---"
  
  echo "Определение последней версии uFan на GitHub..."
  latest_ufan=$(fetch_latest_ufan_version)
  if [ -z "$latest_ufan" ]; then
    latest_ufan="$UFAN_VERSION" # Фолбэк на дефолтную версию из скрипта
  fi
  
  echo "Установка uFan версии $latest_ufan..."

  if [ -f "$BIN" ] || [ -f "$INIT" ]; then
    echo "Остановка запущенной службы ufan..."
    service ufan stop 2>/dev/null
  fi

  echo "Скачивание исполняемого файла..."
  if ! wget --no-check-certificate -qO "$BIN" "https://github.com/andros-ua/ufan/raw/refs/heads/main/usr/sbin/ufan"; then
    echo "Ошибка: Не удалось скачать $BIN. Проверьте интернет или ссылку."
    return 1
  fi
  chmod +x "$BIN"

  echo "Скачивание скрипта инициализации..."
  if ! wget --no-check-certificate -qO "$INIT" "https://github.com/andros-ua/ufan/raw/refs/heads/main/etc/init.d/ufan"; then
    echo "Ошибка: Не удалось скачать $INIT. Проверьте интернет или ссылку."
    return 1
  fi
  chmod +x "$INIT"

  # Запись установленной версии
  echo "$latest_ufan" > "$UFAN_VER_FILE"

  echo "Включение и запуск службы ufan..."
  service ufan enable 2>/dev/null || /etc/init.d/ufan enable 2>/dev/null
  service ufan start 2>/dev/null || /etc/init.d/ufan start 2>/dev/null

  echo "Установка ufan успешно завершена."
  ask_sysupgrade
}

# Функция установки мониторинга кулера
install_fan_monitoring() {
  echo -e "\n--- Установка мониторинга кулера ---"
  echo "Установка зависимостей мониторинга..."
  if command -v apk >/dev/null; then
    apk update 2>/dev/null
    apk add luci-app-statistics collectd-mod-exec
  elif command -v opkg >/dev/null; then
    opkg update
    opkg install luci-app-statistics collectd-mod-exec
  else
    echo "Предупреждение: не найден пакетный менеджер (apk или opkg). Пропуск установки пакетов."
  fi

  wget_ok=1
  echo "Скачивание скрипта pwmfan.sh..."
  mkdir -p "$(dirname "$FAN_SCRIPT")"
  if ! wget --no-check-certificate -qO "$FAN_SCRIPT" "https://github.com/andros-ua/ufan/raw/refs/heads/main/usr/share/collectd/pwmfan.sh"; then
    echo "Ошибка: Не удалось скачать $FAN_SCRIPT. Мониторинг вентилятора не будет установлен."
    wget_ok=0
  else
    chmod +x "$FAN_SCRIPT"
  fi

  if [ "$wget_ok" -eq 1 ]; then
    echo "Скачивание конфигурации rrdtool/definitions/exec.js..."
    mkdir -p "$(dirname "$FAN_LUCI_JS")"
    if ! wget --no-check-certificate -qO "$FAN_LUCI_JS" "https://github.com/andros-ua/ufan/raw/refs/heads/main/www/luci-static/resources/statistics/rrdtool/definitions/exec.js"; then
      echo "Ошибка: Не удалось скачать $FAN_LUCI_JS. Мониторинг вентилятора не будет установлен."
      wget_ok=0
      rm -f "$FAN_SCRIPT"
    fi
  fi

  if [ "$wget_ok" -eq 1 ]; then
    # Настройка collectd.conf
    if [ -f "$COLLECTD_CONF" ]; then
      if ! grep -qF "$FAN_SCRIPT" "$COLLECTD_CONF"; then
        echo "Настройка $COLLECTD_CONF..."
        cat >> "$COLLECTD_CONF" << 'EOF'

LoadPlugin exec
<Plugin exec>
        Exec "nobody:nogroup" "/usr/share/collectd/pwmfan.sh"
</Plugin>
EOF
      fi
      echo "Перезапуск службы collectd..."
      service collectd restart 2>/dev/null || /etc/init.d/collectd restart 2>/dev/null
    else
      echo "Предупреждение: $COLLECTD_CONF не найден. collectd не настроен."
    fi
    echo "Установка мониторинга вентилятора успешно завершена."
    ask_sysupgrade
  else
    return 1
  fi
}

# Функция удаления всего установленного
uninstall_all() {
  echo -e "\n--- Полное удаление uFan и мониторинга кулера ---"
  printf "Вы действительно хотите удалить все компоненты? (y/n) [n]: "
  read -r confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Удаление отменено."
    return 0
  fi

  echo "Остановка службы ufan..."
  service ufan stop 2>/dev/null
  service ufan disable 2>/dev/null
  rm -f "$BIN" "$INIT" "$UFAN_VER_FILE"

  echo "Удаление файлов мониторинга вентилятора..."
  rm -f "$FAN_SCRIPT" "$FAN_LUCI_JS"
  if [ -f "$COLLECTD_CONF" ]; then
    sed -i '\#/usr/share/collectd/pwmfan.sh#d' "$COLLECTD_CONF" 2>/dev/null
    echo "Перезапуск службы collectd..."
    service collectd restart 2>/dev/null || /etc/init.d/collectd restart 2>/dev/null
  fi

  # Удаляем записи из sysupgrade.conf
  echo "Очистка записей в $CONF..."
  sed -i '\#/usr/sbin/ufan#d' "$CONF" 2>/dev/null
  sed -i '\#/etc/init.d/ufan#d' "$CONF" 2>/dev/null
  sed -i '\#/etc/ufan.version#d' "$CONF" 2>/dev/null
  sed -i '\#/etc/collectd.conf#d' "$CONF" 2>/dev/null
  sed -i '\#/usr/share/collectd/pwmfan.sh#d' "$CONF" 2>/dev/null
  sed -i '\#/www/luci-static/resources/statistics/rrdtool/definitions/exec.js#d' "$CONF" 2>/dev/null

  echo "Все компоненты успешно удалены."
}

# Функция проверки обновлений самого установщика (скрипта)
check_updates() {
  local is_startup="$1"
  if [ "$is_startup" != "startup" ]; then
    echo -e "\n--- Проверка обновлений установщика ---"
  fi
  TEMP_FILE="/tmp/ufan_new.sh"
  
  if wget --no-check-certificate -qO "$TEMP_FILE" "https://raw.githubusercontent.com/DarkAssassinUA/Comfast-WR632AX-Additional-Software/main/ufan.sh"; then
    new_version=$(grep "^VERSION=" "$TEMP_FILE" | cut -d'"' -f2)
    if [ -n "$new_version" ]; then
      if [ "$new_version" != "$VERSION" ]; then
        printf "\n[Обновление скрипта] Доступна новая версия установщика: $new_version (текущая: $VERSION).\nОбновить установщик? (y/n) [y]: "
        read -r update_choice
        if [ "$update_choice" != "n" ] && [ "$update_choice" != "N" ]; then
          echo "Обновление файла скрипта..."
          mv "$TEMP_FILE" "$0"
          chmod +x "$0"
          echo "Скрипт успешно обновлен. Пожалуйста, запустите его заново."
          exit 0
        fi
      else
        if [ "$is_startup" != "startup" ]; then
          echo "У вас уже установлена последняя версия установщика ($VERSION)."
        fi
      fi
    else
      if [ "$is_startup" != "startup" ]; then
        echo "Не удалось распознать версию в загруженном файле установщика."
      fi
    fi
    rm -f "$TEMP_FILE"
  else
    if [ "$is_startup" != "startup" ]; then
      echo "Ошибка: Не удалось загрузить последнюю версию установщика с GitHub."
    fi
  fi
}

# Функция проверки обновлений бинарного файла uFan
check_ufan_updates() {
  local is_startup="$1"
  if [ "$is_startup" != "startup" ]; then
    echo -e "\n--- Проверка обновлений uFan ---"
  fi

  if [ ! -f "$BIN" ]; then
    if [ "$is_startup" != "startup" ]; then
      echo "Служба uFan не установлена в системе. Пропуск."
    fi
    return 0
  fi

  if [ "$is_startup" != "startup" ]; then
    echo "Проверка последней версии uFan на GitHub..."
  fi

  latest_ufan=$(fetch_latest_ufan_version)
  if [ -n "$latest_ufan" ]; then
    installed_ufan=$(get_installed_ufan_version)
    # Очищаем префиксы (v. / v) для корректного сравнения версий
    clean_latest=$(echo "$latest_ufan" | sed 's/[^0-9.]//g')
    clean_installed=$(echo "$installed_ufan" | sed 's/[^0-9.]//g')

    if [ "$clean_latest" != "$clean_installed" ] && [ -n "$clean_latest" ]; then
      printf "\n[Обновление uFan] Доступна новая версия uFan: $latest_ufan (установлена: $installed_ufan).\nОбновить бинарный файл uFan? (y/n) [y]: "
      read -r ufan_update_choice
      if [ "$ufan_update_choice" != "n" ] && [ "$ufan_update_choice" != "N" ]; then
        echo "Обновление бинарного файла uFan..."
        service ufan stop 2>/dev/null
        if wget --no-check-certificate -qO "$BIN" "https://github.com/andros-ua/ufan/raw/refs/heads/main/usr/sbin/ufan"; then
          chmod +x "$BIN"
          echo "$latest_ufan" > "$UFAN_VER_FILE"
          service ufan start 2>/dev/null
          echo "Служба uFan успешно обновлена до версии $latest_ufan."
        else
          echo "Ошибка: Не удалось загрузить обновленный бинарный файл uFan."
          # Пытаемся запустить обратно старый
          service ufan start 2>/dev/null
        fi
      fi
    else
      if [ "$is_startup" != "startup" ]; then
        echo "У вас установлена актуальная версия uFan ($installed_ufan)."
      fi
    fi
  else
    if [ "$is_startup" != "startup" ]; then
      echo "Не удалось получить версию uFan с GitHub."
    fi
  fi
}

# Проверка обновлений при запуске
check_updates startup
check_ufan_updates startup

# Основной цикл работы меню
while true; do
  show_menu
  read -r choice
  case "$choice" in
    1)
      install_ufan
      ;;
    2)
      install_fan_monitoring
      ;;
    3)
      uninstall_all
      ;;
    99)
      check_updates
      check_ufan_updates
      ;;
    0)
      echo "Выход из установщика."
      exit 0
      ;;
    *)
      echo "Неверный ввод. Пожалуйста, выберите число из меню."
      ;;
  esac
  printf "\nНажмите Enter, чтобы продолжить..."
  read -r _
done
