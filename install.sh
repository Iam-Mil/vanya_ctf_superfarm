#!/usr/bin/env bash
# =============================================================================
# install.sh — поставить всё необходимое на свежую машину (Ubuntu/Debian/Kali).
#
#   sudo bash install.sh
#
# Ставит: docker + compose v2, python3-pip, rsync, jq, nmap, tcpdump
# и библиотеку checklib (для сплойтов/чекеров) из этого же репозитория.
#
# На игре, если машина ходит в интернет через прокси оргов, ПЕРЕД запуском:
#   export http_proxy=http://10.10.10.10:8080
#   export https_proxy=http://10.10.10.10:8080
# =============================================================================
set -uo pipefail

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m[X] %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "запусти от root: sudo bash install.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

say "1/3. Базовый софт (apt)"
command -v apt-get >/dev/null || die "это не Debian/Ubuntu/Kali — ставь руками: docker, docker-compose, python3-pip"
apt-get update -qq || die "apt update не прошёл — проверь сеть/прокси (см. шапку скрипта)"
apt-get install -y -qq docker.io python3-pip rsync jq nmap tcpdump curl || \
    die "что-то не поставилось — разбирайся по выводу выше"

say "2/3. docker compose v2"
if ! docker compose version &>/dev/null; then
    apt-get install -y -qq docker-compose-v2 || apt-get install -y -qq docker-compose || true
fi
systemctl enable --now docker 2>/dev/null || service docker start 2>/dev/null || true
docker compose version || die "docker compose так и не появился"
docker info >/dev/null 2>&1 || die "docker-демон не отвечает: systemctl status docker"

say "3/3. python-зависимости (requests; checklib опционален)"
python3 -c 'import requests' 2>/dev/null || pip3 install -q requests
# checklib нужен только некоторым сплойтам; качаем с гитхаба оргов
# (на игре GitHub через прокси доступен — см. шапку)
if ! python3 -c 'import checklib' 2>/dev/null; then
    pip3 install -q git+https://github.com/pomo-mondreganto/checklib 2>/dev/null \
        && echo "checklib: OK" \
        || echo "[!] checklib не поставился — он нужен не всем сплойтам; можно повторить позже"
fi

cat <<'EOF'

=====================================================
 Готово. Что дальше:

 РЕПЕТИЦИЯ (по желанию):   поднимается отдельно, вне этого репозитория
 ДЕНЬ ИГРЫ:               PLAYBOOK.md  (+ CHEATSHEET.md под рукой)
 ФЕРМА (у капитана):      repos/S4DFarm — уже с протоколом forcad_http
                           и конфигом под ForcAD; сменить TEAM_TOKEN/TEAMS
                           и: docker compose up --build -d   (UI :5137)
=====================================================
EOF
