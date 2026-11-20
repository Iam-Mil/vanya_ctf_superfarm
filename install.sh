#!/usr/bin/env bash
# =============================================================================
# install.sh — поставить всё необходимое на свежую машину (Ubuntu/Debian/Kali).
#
#   sudo bash install.sh
#
# Лог подробный: шаги с таймингом, живой вывод apt/pip, версии, сводка.
#
# DOCKER ставится по сценариям (знаем, что он капризный):
#   1) уже стоит и работает            → пропускаем
#   2) apt-пакет дистрибутива          → Kali: docker.io+docker-compose,
#                                       Ubuntu/Debian: docker.io+docker-compose-v2
#   3) официальный скрипт get.docker.com (нужен интернет)
#   4) ничего не вышло → печатаем РУЧНЫЕ команды под твой дистрибутив
#
# На игре интернета может не быть → docker ставится ЗАРАНЕЕ (дома).
# Все образы уже в репозитории: на игре `sudo bash offline.sh`.
# =============================================================================
set -uo pipefail

SECONDS=0
say()  { printf '\n\033[1;36m==> [%3ds] %s\033[0m\n' "$SECONDS" "$*"; }
ok()   { printf '    \033[1;32mOK\033[0m  %s\n' "$*"; }
step() { printf '        %s\n' "$*"; }
warn() { printf '    \033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m[X] %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "запусти от root: sudo bash install.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

DISTRO=""; . /etc/os-release 2>/dev/null && DISTRO="${ID:-unknown}"
SUDO_USER="${SUDO_USER:-$USER}"

# --- 1. осмотр ---------------------------------------------------------------
say "1/7. Осмотр машины"
PRETTY=""; . /etc/os-release 2>/dev/null && PRETTY="$PRETTY_NAME"
step "дистрибутив: ${PRETTY:-неизвестный} (id=$DISTRO)"
step "архитектура: $(uname -m)"
step "CPU: $(nproc 2>/dev/null) ядер, RAM: $(free -h 2>/dev/null | awk '/Mem:/{print $2}')"
step "диск свободно: $(df -h . 2>/dev/null | awk 'NR==2{print $4}')"
command -v apt-get >/dev/null \
    || die "это не Debian/Ubuntu/Kali — смотри DOCKER.md, раздел «ручная установка»"

say "2/7. Обновляю индексы пакетов (apt update) — живой вывод ниже"
apt-get update || warn "apt update не прошёл — продолжаю (сеть/прокси? см. шапку)"

# --- 3. базовые пакеты (docker отдельно, см. шаг 4) ---------------------------
say "3/7. Базовые пакеты — по одному; уже стоящие не трогаю"
for pkg in python3-pip rsync jq nmap tcpdump curl git; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        ok "$pkg: уже стоит ($(dpkg -s "$pkg" | awk '/^Version:/{print $2; exit}'))"
        continue
    fi
    printf '    --> ставлю %s (вывод apt ниже):\n' "$pkg"
    if apt-get install -y "$pkg"; then
        ok "$pkg: установлен ($(dpkg -s "$pkg" | awk '/^Version:/{print $2; exit}'))"
    else
        warn "$pkg НЕ поставился — не критично. Повторить позже:"
        step "apt-get install --fix-missing $pkg"
    fi
done

# --- 4. DOCKER: мульти-сценарии ------------------------------------------------
say "4/7. Docker-движок (сценарии: уже есть → apt → официальный скрипт → ручной)"
if docker info >/dev/null 2>&1; then
    ok "docker уже установлен и демон работает"
else
    if command -v docker >/dev/null; then
        step "docker есть, но демон не отвечает — пробую запустить..."
        systemctl enable --now docker 2>/dev/null || service docker start 2>/dev/null || true
        sleep 3
    fi
    if ! docker info >/dev/null 2>&1; then
        step "сценарий A: apt-пакет дистрибутива (docker.io)..."
        apt-get install -y docker.io || true
        systemctl enable --now docker 2>/dev/null || service docker start 2>/dev/null || true
        sleep 3
    fi
    if ! docker info >/dev/null 2>&1; then
        step "сценарий B: официальный установщик (нужен интернет)..."
        warn "на игре интернета может не быть — если это game day, ставь docker ДО игры!"
        curl -fsSL https://get.docker.com | sh || warn "официальный скрипт не сработал"
        systemctl enable --now docker 2>/dev/null || service docker start 2>/dev/null || true
        sleep 3
    fi
    if docker info >/dev/null 2>&1; then
        ok "docker установлен и демон работает"
    else
        warn "автоустановка не удалась. РУЧНЫЕ КОМАНДЫ для твоего случая:"
        cat <<EOFMANUAL
    ─────────────── РУЧНАЯ УСТАНОВКА DOCKER ───────────────
    Kali (проверенный путь):
        sudo apt-get update
        sudo apt-get install -y docker.io docker-compose
        sudo systemctl enable --now docker
    Ubuntu / Debian:
        sudo apt-get update
        sudo apt-get install -y docker.io docker-compose-v2
        sudo systemctl enable --now docker
    Любой дистрибутив (нужен интернет):
        curl -fsSL https://get.docker.com | sh
        sudo systemctl enable --now docker
    Если падает apt со старыми пакетами:
        sudo apt-get --fix-broken install
        sudo apt-get remove -y docker docker-engine containerd runc || true
        (и повторить установку)
    Проверка:        sudo docker info && sudo docker compose version
    Права без sudo:  sudo usermod -aG docker $SUDO_USER   # затем ВЫЙТИ и зайти снова
    Подробности и лечение ошибок: DOCKER.md
    ────────────────────────────────────────────────────────
EOFMANUAL
        die "docker не установился — выполни команды выше и запусти install.sh снова"
    fi
fi
ok "версия: $(docker --version 2>/dev/null)"

# --- 5. compose v2 ---------------------------------------------------------------
say "5/7. Docker compose v2"
if docker compose version >/dev/null 2>&1; then
    ok "docker compose: $(docker compose version 2>/dev/null | head -1)"
else
    step "compose не найден — ставлю (имя пакета зависит от дистрибутива)..."
    apt-get install -y docker-compose-v2 || apt-get install -y docker-compose || true
    if docker compose version >/dev/null 2>&1; then
        ok "docker compose: $(docker compose version 2>/dev/null | head -1)"
    else
        warn "compose не появился. РУЧНОЙ ПУТЬ:"
        step "Kali:      sudo apt-get install -y docker-compose"
        step "Ubuntu/Deb: sudo apt-get install -y docker-compose-v2"
        step "Напрямую бинарником (https://github.com/docker/compose/releases):"
        step '  sudo mkdir -p /usr/local/lib/docker/cli-plugins'
        step '  sudo cp <compose-binary> /usr/local/lib/docker/cli-plugins/docker-compose'
        step "Подробнее: DOCKER.md"
        die "docker compose обязателен для фермы"
    fi
fi

# --- 6. python ------------------------------------------------------------------------
say "6/7. Python-зависимости"
if python3 -c 'import requests' 2>/dev/null; then
    ok "requests: уже есть $(python3 -c 'import requests; print(requests.__version__)' 2>/dev/null)"
else
    step "ставлю requests (вывод pip ниже)..."
    pip3 install requests && ok "requests: установлен" || warn "requests не поставился — критично для сплойтов!"
fi
if python3 -c 'import checklib' 2>/dev/null; then
    ok "checklib: уже есть"
else
    step "checklib нет — качаю с гитхаба (вывод pip ниже; нужен не всем сплойтам)..."
    pip3 install --break-system-packages git+https://github.com/pomo-mondreganto/checklib 2>/dev/null \
    || pip3 install git+https://github.com/pomo-mondreganto/checklib \
        && ok "checklib: установлен" \
        || warn "checklib не поставился — нужен не всем; на месте повторить через прокси"
fi

# --- 7. сводка --------------------------------------------------------------------------
say "7/7. Сводка"
printf '    %-14s %s\n' \
    "docker"     "$(docker --version 2>/dev/null | cut -d, -f1)" \
    "compose"    "$(docker compose version 2>/dev/null | awk '{print $4}')" \
    "python3"    "$(python3 --version 2>/dev/null)" \
    "jq"         "$(jq --version 2>/dev/null)" \
    "nmap"       "$(nmap --version 2>/dev/null | head -1 | awk '{print $3}')" \
    "requests"   "$(python3 -c 'import requests; print(requests.__version__)' 2>/dev/null || echo нет)" \
    "checklib"   "$(python3 -c 'import checklib; print("импортируется")' 2>/dev/null || echo нет)"
printf '    %-14s %s c от старта скрипта\n' "время" "$SECONDS"
[[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]] && \
    printf '    %-14s %s\n' "подсказка" "чтобы docker без sudo: usermod -aG docker $SUDO_USER (затем перелогин)"

cat <<'EOF'

####################################################################
#                                                                  #
#   УСТАНОВКА ЗАВЕРШЕНА — ЧТО И ГДЕ ПОМЕНЯТЬ ДАЛЬШЕ                #
#                                                                  #
####################################################################

 ГДЕ МЕНЯТЬ КОНФИГ ФЕРМЫ (у капитана):

     файл:  repos/S4DFarm/server/app/config.py

     TEAM_TOKEN    = '...'   <-- ТОКЕН КОМАНДЫ ИЗ ПИСЬМА ОРГОВ
     SYSTEM_URL    = 'http://10.10.10.10/flags'   <-- на ИГРЕ
                     http://127.0.0.1:8080/flags  <-- на репетиции-лабе
     TEAMS         = {...}   <-- GAME_URL=http://10.10.10.10 \
                                  python3 farm/gen_teams.py
                     вставить вывод в config.py и ВЫЧЕРКНУТЬ свою команду
     SERVER_PASSWORD (в .env рядом с docker-compose)  <-- пароль морды


 КАК ЗАПУСТИТЬ ФЕРМУ:

     С ИНТЕРНЕТОМ (сборка с нуля):
         cd repos/S4DFarm
         echo 'SERVER_PASSWORD=свой_пароль' > .env
         sudo docker compose up --build -d

     БЕЗ ИНТЕРНЕТА (на игре — все образы уже в репо!):
         sudo bash offline.sh


 КАК ГНАТЬ СПЛОЙТ ЧЕРЕЗ ФЕРМУ:

     cd repos/S4DFarm/client
     python3 start_sploit.py sploits/<мой_сплойт>.py \
        --server-url http://127.0.0.1:5137 \
        --server-pass <пароль> \
        --attack-period 110        <-- на игре (раунд 2 мин)


 ПОДРОБНО:
     DOCKER.md     <-- docker: все сценарии установки и лечение ошибок
     FARM.md       <-- про ферму ВСЁ (настройка/запуск/ошибки)
     SPLOITS.md    <-- сплойты: классы уязвимостей, скелеты, отладка
     PLAYBOOK.md   <-- план дня игры по минутам
     CHEATSHEET.md <-- все команды на одной странице
####################################################################
EOF
