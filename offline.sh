#!/usr/bin/env bash
# =============================================================================
# offline.sh — ПОЛНЫЙ ПОДЪЁМ ФЕРМЫ НА МАШИНЕ «ТОЛЬКО GIT + APT».
#
#   sudo bash offline.sh
#
# Рассчитан на завтрашний сценарий: apt и git доступны, Docker Hub / PyPI /
# npm — НЕ факт. Поэтому:
#   0) python-зависимости для сплойтов — из локального wheelhouse (без PyPI)
#   1) docker engine — из apt, если его нет (ставится без Docker Hub)
#   2) docker compose v2 — из apt, если нет
#   3) ОБРАЗЫ — из images/ (docker load), БЕЗ Docker Hub
#   4) ферма поднимается БЕЗ сборки (docker compose up --no-build)
#
# Всё, что нужно для игры, уже в репозитории.
# =============================================================================
set -euo pipefail

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()  { printf '    \033[1;32mOK\033[0m  %s\n' "$*"; }
warn(){ printf '    \033[1;33m[!]\033[0m %s\n' "$*"; }
die() { printf '\n\033[1;31m[X] %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "запусти от root: sudo bash offline.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# --- 0. python для сплойтов (без PyPI) --------------------------------------
say "0/5. Python: requests (локальный wheelhouse, без PyPI)"
if python3 -c 'import requests' 2>/dev/null; then
    ok "requests уже есть $(python3 -c 'import requests; print(requests.__version__)' 2>/dev/null)"
else
    step() { :; }
    pip3 install --break-system-packages --no-index --find-links images/wheelhouse requests 2>/dev/null \
    || pip3 install --no-index --find-links images/wheelhouse requests \
        && ok "requests: установлен из wheelhouse" \
        || warn "requests не поставился — на Kali он обычно есть из коробки; проверь: python3 -c 'import requests'"
fi

# --- 1. docker engine --------------------------------------------------------
say "1/5. Docker-движок (apt — без Docker Hub)"
if docker info >/dev/null 2>&1; then
    ok "docker уже установлен и работает"
else
    warn "docker не найден — ставлю через apt (интернет до репозиториев дистрибутива есть)"
    if command -v docker >/dev/null; then
        systemctl enable --now docker 2>/dev/null || service docker start 2>/dev/null || true
        sleep 3
    fi
    if ! docker info >/dev/null 2>&1; then
        apt-get update -qq || true
        apt-get install -y docker.io \
            || die "docker через apt не встал: команды для ручной установки — DOCKER.md §1-§3"
        systemctl enable --now docker 2>/dev/null || true
        sleep 3
    fi
    docker info >/dev/null 2>&1 \
        && ok "docker: установлен и демон работает" \
        || die "демон docker не поднялся: systemctl status docker / journalctl -u docker (см. DOCKER.md §6)"
fi
ok "версия: $(docker --version 2>/dev/null)"

# --- 2. compose v2 ---------------------------------------------------------------
say "2/5. Docker compose v2 (apt)"
if docker compose version >/dev/null 2>&1; then
    ok "docker compose: $(docker compose version 2>/dev/null | head -1)"
else
    apt-get update -qq || true
    apt-get install -y docker-compose-v2 || apt-get install -y docker-compose \
        || die "compose не встал через apt: DOCKER.md §4 (бинарник вручную)"
    docker compose version >/dev/null 2>&1 \
        && ok "docker compose: $(docker compose version 2>/dev/null | head -1)" \
        || die "compose v2 так и не появился — DOCKER.md §4"
fi

# --- 3. образы из репозитория (замена Docker Hub) --------------------------------
say "3/5. Образы фермы из images/ (docker load, БЕЗ Docker Hub)"
PARTS=$(ls images/farm_stack.tar.gz.part-* 2>/dev/null | wc -l)
[[ "$PARTS" -gt 0 ]] || die "нет images/farm_stack.tar.gz.part-* — репозиторий клонирован не полностью?"
echo "    частей: $PARTS — загружаю (это минута-другая)..."
cat images/farm_stack.tar.gz.part-* | docker load
if [[ -f images/neo_server.tar.gz ]]; then
    echo "    + neo-сервер..."
    docker load -i images/neo_server.tar.gz
fi
ok "образы в системе (postgres, redis, ферма целиком)"

# --- 4. конфиг фермы -----------------------------------------------------------------
say "4/5. Проверяю конфиг фермы"
cd repos/S4DFarm
if [[ ! -f .env ]]; then
    die "нет .env! Сначала: echo 'SERVER_PASSWORD=свой_пароль' > .env (см. FARM.md §2)"
fi
if grep -q "PASTE_TEAM_TOKEN_HERE" server/app/config.py; then
    die "в server/app/config.py не вписан TEAM_TOKEN (токен команды из письма!). См. FARM.md §2"
fi
if grep -q "10\.10\.10\.10" server/app/config.py; then
    ok "SYSTEM_URL уже смотрит на жюри (10.10.10.10)"
else
    warn "проверь SYSTEM_URL в config.py: на игре должно быть http://10.10.10.10/flags"
fi
echo "    .env и config.py — ок"

# --- 5. подъём ------------------------------------------------------------------------
say "5/5. Поднимаю ферму (без сборки и без Docker Hub)"
docker compose -p s4dfarm up -d --no-build
docker compose -p s4dfarm ps

IP=$(hostname -I 2>/dev/null | awk '{print $1}')
cat <<EOF

=============================================================
 ФЕРМА ПОДНЯТА ОФЛАЙН (Docker Hub/PyPI/npm не использовались).

 Морда:        http://${IP:-<ip_этой_машины>}:5137   (пароль из .env)
 Клиент:       cd repos/S4DFarm/client
               python3 start_sploit.py sploits/<мой>.py \\
                   --server-url http://${IP:-127.0.0.1}:5137 \\
                   --server-pass <пароль> --attack-period 110
 Neo-сервер (по желанию, образ загружен):
               cd tools/neo_server_2.4.2
               (настроить configs/server/config.yml — см. пример рядом)
               sudo docker compose up -d --no-build server

 Дальше: FARM.md (ферма), SPLOITS.md (сплойты), PLAYBOOK.md (план дня)
=============================================================
EOF
