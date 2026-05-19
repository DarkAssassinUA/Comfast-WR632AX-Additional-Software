install_ufan() {
  local BIN="/usr/sbin/ufan"
  local INIT="/etc/init.d/ufan"
  local CONF="/etc/sysupgrade.conf"

  # 1. Проверка: существуют ли файлы в системе
  if [ -f "$BIN" ] || [ -f "$INIT" ]; then
    printf "\nФайлы ufan уже найдены в системе. Выберите действие:\n"
    printf "  [1] Переустановить (скачать заново и перезапустить)\n"
    printf "  [2] Удалить полностью\n"
    printf "  [3] Отмена\n"
    printf "Ваш выбор (1/2/3): "
    read -r choice
    case "$choice" in
      2)
        echo "Остановка службы и удаление файлов..."
        service ufan stop 2>/dev/null
        service ufan disable 2>/dev/null
        rm -f "$BIN" "$INIT"
        # Удаляем записи из sysupgrade.conf (используем # как разделитель для sed)
        sed -i '\#/usr/sbin/ufan#d' "$CONF" 2>/dev/null
        sed -i '\#/etc/init.d/ufan#d' "$CONF" 2>/dev/null
        echo "Удаление успешно завершено."
        return 0
        ;;
      1)
        echo "Начинаем переустановку..."
        service ufan stop 2>/dev/null
        ;;
      *)
        echo "Действие отменено."
        return 0
        ;;
    esac
  fi

  # 2. Скачивание файлов с проверкой на ошибки
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

  # 3. Запуск службы
  echo "Включение и запуск службы ufan..."
  service ufan enable
  service ufan start

  # 4. Вопрос о выживаемости файлов при обновлении (sysupgrade)
  printf "\nСохранять эти файлы при будущем обновлении прошивки роутера? (y/n) [по умолчанию: y]: "
  read -r keep
  if [ "$keep" != "n" ] && [ "$keep" != "N" ]; then
    grep -qF "$BIN" "$CONF" || echo "$BIN" >> "$CONF"
    grep -qF "$INIT" "$CONF" || echo "$INIT" >> "$CONF"
    echo "Файлы успешно добавлены в список сохранения ($CONF)."
  else
    echo "Файлы НЕ будут сохраняться при обновлении прошивки."
  fi

  echo -e "\nГотово! Установка ufan успешно завершена."
}

# Запуск функции
install_ufan