#!/usr/bin/env bash
# =============================================================================
# install.sh — поставить всё необходимое на свежую машину (Ubuntu/Debian/Kali).
#
#   sudo bash install.sh
#
# Лог подробный: каждый шаг пишет, что делает и сколько секунд прошло
# от старта; apt/pip показывают свой живой вывод; в конце — сводка
# с версиями. Упавшее видно сразу и не глушит остальные шаги
# (кроме docker — без него дальше никак).
#
# На игре, если машина ходит в интернет через прокси оргов, ПЕРЕД запуском:
#   export http_proxy=http://10.10.10.10:8080
#   export https_proxy=http://10.10.10.10:8080
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

# --- 1. осмотр ---------------------------------------------------------------
say "1/6. Осмотр машины"
PRETTY=""; . /etc/os-release 2>/dev/null && PRETTY="$PRETTY_NAME"
step "дистрибутив: ${PRETTY:-неизвестный}"
step "архитектура: $(uname -m)"
step "CPU: $(nproc 2>/dev/null) ядер, RAM: $(free -h 2>/dev/null | awk '/Mem:/{print $2}')"
step "диск свободно: $(df -h . 2>/dev/null | awk 'NR==2{print $4}')"
command -v apt-get >/dev/null \
    || die "это не Debian/Ubuntu/Kali — ставь руками: docker, docker-compose, python3-pip"

# --- 2. индексы apt ------------------------------------------------------------
say "2/6. Обновляю индексы пакетов (apt update) — живой вывод ниже"
apt-get update || warn "apt update не прошёл — продолжаю (сеть/прокси? см. шапку)"

# --- 3. пакеты ------------------------------------------------------------------
say "3/6. Пакеты — по одному; уже стоящие не трогаю"
for pkg in docker.io python3-pip rsync jq nmap tcpdump curl; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        ok "$pkg: уже стоит ($(dpkg -s "$pkg" | awk '/^Version:/{print $2; exit}'))"
        continue
    fi
    printf '    --> ставлю %s (вывод apt ниже):\n' "$pkg"
    if apt-get install -y "$pkg"; then
        ok "$pkg: установлен ($(dpkg -s "$pkg" | awk '/^Version:/{print $2; exit}'))"
    else
        warn "$pkg НЕ поставился — не критично, продолжаю. Повторить позже:"
        step "apt-get install --fix-missing $pkg"
    fi
done

# --- 4. docker --------------------------------------------------------------------
say "4/6. Docker-демон"
if ! docker info >/dev/null 2>&1; then
    step "демон не отвечает — пробую запустить через systemd..."
    systemctl enable --now docker 2>/dev/null || service docker start 2>/dev/null || true
    sleep 3
fi
docker info >/dev/null 2>&1 \
    && ok "docker-демон: работает" \
    || die "docker-демон не отвечает — смотри: systemctl status docker"
ok "версия: $(docker --version 2>/dev/null)"

if docker compose version >/dev/null 2>&1; then
    ok "docker compose: $(docker compose version 2>/dev/null | head -1)"
else
    step "compose v2 не найден — ставлю..."
    apt-get install -y docker-compose-v2 || apt-get install -y docker-compose || true
    docker compose version >/dev/null 2>&1 \
        && ok "docker compose: $(docker compose version 2>/dev/null | head -1)" \
        || die "docker compose так и не появился"
fi

# --- 5. python ------------------------------------------------------------------------
say "5/6. Python-зависимости"
if python3 -c 'import requests' 2>/dev/null; then
    ok "requests: уже есть $(python3 -c 'import requests; print(requests.__version__)' 2>/dev/null)"
else
    step "ставлю requests (вывод pip ниже)..."
    pip3 install requests && ok "requests: установлен" || warn "requests не поставился — критично для сплойтов!"
fi
if python3 -c 'import checklib' 2>/dev/null; then
    ok "checklib: уже есть"
else
    step "checklib нет — качаю с гитхаба оргов (вывод pip ниже; нужен не всем сплойтам)..."
    pip3 install --break-system-packages git+https://github.com/pomo-mondreganto/checklib 2>/dev/null \
    || pip3 install git+https://github.com/pomo-mondreganto/checklib \
        && ok "checklib: установлен" \
        || warn "checklib не поставился — нужен не всем; на месте повторить через прокси"
fi

# --- 6. сводка --------------------------------------------------------------------------
say "6/6. Сводка"
printf '    %-14s %s\n' \
    "docker"     "$(docker --version 2>/dev/null | cut -d, -f1)" \
    "compose"    "$(docker compose version 2>/dev/null | awk '{print $4}')" \
    "python3"    "$(python3 --version 2>/dev/null)" \
    "jq"         "$(jq --version 2>/dev/null)" \
    "nmap"       "$(nmap --version 2>/dev/null | head -1 | awk '{print $3}')" \
    "requests"   "$(python3 -c 'import requests; print(requests.__version__)' 2>/dev/null || echo нет)" \
    "checklib"   "$(python3 -c 'import checklib; print("импортируется")' 2>/dev/null || echo нет)"
printf '    %-14s %s c от старта скрипта\n' "время" "$SECONDS"

cat <<'EOF'

=====================================================
 Готово. Что дальше:

 ДЕНЬ ИГРЫ:               PLAYBOOK.md  (+ CHEATSHEET.md под рукой)
 ФЕРМА (у капитана):      repos/S4DFarm — уже с протоколом forcad_http
                           и конфигом под ForcAD; сменить TEAM_TOKEN/TEAMS
                           и: docker compose up --build -d   (UI :5137)
=====================================================
EOF
