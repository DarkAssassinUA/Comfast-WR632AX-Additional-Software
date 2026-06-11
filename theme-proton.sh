#!/bin/sh

VERSION="1.0"
THEME_DIR="/www/luci-static/proton2025"

# Функция получения установленной версии темы
get_installed_version() {
  if [ -d "$THEME_DIR" ]; then
    if command -v apk >/dev/null; then
      apk info luci-theme-proton2025 2>/dev/null | head -n 1 | sed 's/luci-theme-proton2025-//' | cut -d' ' -f1
    elif command -v opkg >/dev/null; then
      opkg status luci-theme-proton2025 2>/dev/null | grep -i "^Version:" | cut -d' ' -f2
    else
      echo "установлена (версия неизвестна)"
    fi
  else
    echo "не установлена"
  fi
}

# Функция очистки кэша LuCI
clear_luci_cache() {
  echo "Очистка кэша LuCI..."
  rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null
}

# Функция вывода статуса и меню
show_menu() {
  installed_ver=$(get_installed_version)
  echo "=================================================="
  echo "  Установщик темы Proton2025 для LuCI"
  echo "  Версия скрипта: $VERSION"
  echo "=================================================="
  echo "Текущий статус:"
  echo "  Тема Proton2025:       $installed_ver"
  echo "--------------------------------------------------"
  echo "Выберите действие:"
  echo "  [1] Установить / Обновить тему Proton2025"
  echo "  [2] Удалить тему Proton2025 полностью"
  echo "  [99] Проверить обновления скрипта и темы"
  echo "  [0] Выход"
  echo "=================================================="
  printf "Ваш выбор: "
}

# Функция установки темы
install_theme() {
  echo -e "\n--- Установка темы Proton2025 ---"
  echo "Запрос последней версии с GitHub..."
  
  release_json=$(wget --no-check-certificate -qO- https://api.github.com/repos/ChesterGoodiny/luci-theme-proton2025/releases/latest)
  latest_version=$(echo "$release_json" | tr ',' '\n' | grep "^\"tag_name\":" | cut -d'"' -f4)
  
  if [ -z "$latest_version" ]; then
    echo "Ошибка: Не удалось определить версию на GitHub. Проверьте интернет-соединение."
    return 1
  fi

  echo "Последняя доступная версия: $latest_version"

  if command -v apk >/dev/null; then
    apk_url=$(echo "$release_json" | tr ',' '\n' | grep "browser_download_url" | grep -i "\.apk" | cut -d'"' -f4)
    if [ -z "$apk_url" ]; then
      echo "Ошибка: Не удалось найти ссылку на APK в релизах."
      return 1
    fi
    echo "Скачивание APK файла..."
    TEMP_APK="/tmp/luci-theme-proton2025.apk"
    if ! wget --no-check-certificate -qO "$TEMP_APK" "$apk_url"; then
      echo "Ошибка: Не удалось скачать APK."
      return 1
    fi
    echo "Установка через apk..."
    if apk add --allow-untrusted "$TEMP_APK"; then
      echo "Тема успешно установлена!"
      rm -f "$TEMP_APK"
      clear_luci_cache
    else
      echo "Ошибка установки пакета."
      rm -f "$TEMP_APK"
      return 1
    fi

  elif command -v opkg >/dev/null; then
    ipk_url=$(echo "$release_json" | tr ',' '\n' | grep "browser_download_url" | grep -i "\.ipk" | cut -d'"' -f4)
    if [ -z "$ipk_url" ]; then
      echo "Ошибка: Не удалось найти ссылку на IPK в релизах."
      return 1
    fi
    echo "Скачивание IPK файла..."
    TEMP_IPK="/tmp/luci-theme-proton2025.ipk"
    if ! wget --no-check-certificate -qO "$TEMP_IPK" "$ipk_url"; then
      echo "Ошибка: Не удалось скачать IPK."
      return 1
    fi
    echo "Установка через opkg..."
    if opkg install "$TEMP_IPK"; then
      echo "Тема успешно установлена!"
      rm -f "$TEMP_IPK"
      clear_luci_cache
    else
      echo "Ошибка установки пакета."
      rm -f "$TEMP_IPK"
      return 1
    fi
  else
    echo "Ошибка: Пакетный менеджер apk или opkg не найден."
    return 1
  fi
}

# Функция удаления темы
uninstall_theme() {
  echo -e "\n--- Удаление темы Proton2025 ---"
  if [ ! -d "$THEME_DIR" ]; then
    echo "Тема Proton2025 не установлена."
    return 0
  fi

  printf "Вы действительно хотите удалить тему Proton2025? (y/n) [n]: "
  read -r confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Удаление отменено."
    return 0
  fi

  echo "Удаление файлов..."
  if command -v apk >/dev/null; then
    apk del luci-theme-proton2025
  elif command -v opkg >/dev/null; then
    opkg remove luci-theme-proton2025
  else
    echo "Пакетный менеджер не найден. Принудительное удаление файлов..."
    rm -rf "$THEME_DIR"
    rm -f /etc/config/proton2025
  fi

  clear_luci_cache
  echo "Тема успешно удалена."
}

# Функция проверки обновлений самого скрипта
check_script_updates() {
  local is_startup="$1"
  if [ "$is_startup" != "startup" ]; then
    echo -e "\n--- Проверка обновлений установщика ---"
  fi
  TEMP_FILE="/tmp/proton_installer_new.sh"
  
  if wget --no-check-certificate -qO "$TEMP_FILE" "https://raw.githubusercontent.com/DarkAssassinUA/Comfast-WR632AX-Additional-Software/main/theme-proton.sh"; then
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
        echo "Не удалось распознать версию в загруженном файле."
      fi
    fi
    rm -f "$TEMP_FILE"
  else
    if [ "$is_startup" != "startup" ]; then
      echo "Ошибка: Не удалось загрузить версию установщика с GitHub."
    fi
  fi
}

# Функция проверки обновлений темы
check_theme_updates() {
  local is_startup="$1"
  if [ "$is_startup" != "startup" ]; then
    echo -e "\n--- Проверка обновлений темы ---"
  fi

  if [ ! -d "$THEME_DIR" ]; then
    if [ "$is_startup" != "startup" ]; then
      echo "Тема Proton2025 не установлена."
    fi
    return 0
  fi

  if [ "$is_startup" != "startup" ]; then
    echo "Запрос последней версии темы с GitHub..."
  fi

  latest_version=$(wget --no-check-certificate -qO- https://api.github.com/repos/ChesterGoodiny/luci-theme-proton2025/releases/latest | tr ',' '\n' | grep "^\"tag_name\":" | cut -d'"' -f4)
  
  if [ -n "$latest_version" ]; then
    installed_version=$(get_installed_version)
    clean_latest=$(echo "$latest_version" | cut -d'-' -f1 | cut -d'_' -f1 | sed 's/[^0-9.]//g')
    clean_installed=$(echo "$installed_version" | cut -d'-' -f1 | cut -d'_' -f1 | sed 's/[^0-9.]//g')

    if [ "$clean_latest" != "$clean_installed" ] && [ -n "$clean_latest" ]; then
      printf "\n[Обновление темы] Доступна новая версия темы: $latest_version (установлена: $installed_version).\nОбновить тему? (y/n) [y]: "
      read -r update_choice
      if [ "$update_choice" != "n" ] && [ "$update_choice" != "N" ]; then
        install_theme
      fi
    else
      if [ "$is_startup" != "startup" ]; then
        echo "У вас установлена актуальная версия темы ($installed_version)."
      fi
    fi
  else
    if [ "$is_startup" != "startup" ]; then
      echo "Не удалось проверить версию темы на GitHub."
    fi
  fi
}

# Проверка обновлений при запуске
check_script_updates startup
check_theme_updates startup

# Основной цикл работы меню
while true; do
  show_menu
  read -r choice
  case "$choice" in
    1)
      install_theme
      ;;
    2)
      uninstall_theme
      ;;
    99)
      check_script_updates
      check_theme_updates
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
