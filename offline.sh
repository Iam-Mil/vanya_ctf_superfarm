#!/usr/bin/env bash
# =============================================================================
# offline.sh — ПОЛНЫЙ ОФЛАЙН-ПОДЪЁМ ФЕРМЫ.
#
#   sudo bash offline.sh
#
# Без Docker Hub, без PyPI, без npm: все образы уже в репозитории
# (images/), скрипт их загружает (docker load) и поднимает ферму
# без сборки (docker compose up --no-build).
#
# Обычный путь (`docker compose up --build`) тянет из интернета:
#   Docker Hub — python:3.9-slim, node:20-slim, nginx:1.21.0-alpine,
#                postgres:14.1-alpine, redis:7.2.0-alpine
#   PyPI       — зависимости фермы (flask, celery, psycopg2, ...)
#   npm        — pnpm + node_modules фронта
# Этот скрипт не использует НИЧЕГО из сети.
#
# NB: правки КОДА фермы работают и так (server/app примонтирован в
# контейнеры volume'ом). Пересборка нужна только при смене requirements.
# =============================================================================
set -euo pipefail

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m[X] %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "запусти от root: sudo bash offline.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

say "1/4. Проверяю образы в images/"
PARTS=$(ls images/farm_stack.tar.gz.part-* 2>/dev/null | wc -l)
[[ "$PARTS" -gt 0 ]] || die "нет images/farm_stack.tar.gz.part-* — репозиторий клонирован не полностью?"
echo "    найдено частей: $PARTS"

say "2/4. Загружаю образы (docker load)"
cat images/farm_stack.tar.gz.part-* | docker load
if [[ -f images/neo_server.tar.gz ]]; then
    echo "    + neo-сервер..."
    docker load -i images/neo_server.tar.gz
fi

say "3/4. Проверяю конфиг фермы"
cd repos/S4DFarm
if [[ ! -f .env ]]; then
    die "нет .env! Сначала: echo 'SERVER_PASSWORD=свой_пароль' > .env (см. FARM.md)"
fi
if grep -q "PASTE_TEAM_TOKEN_HERE" server/app/config.py; then
    die "в server/app/config.py не вписан TEAM_TOKEN (токен команды из письма!). См. FARM.md §2"
fi
echo "    .env и config.py — ок"

say "4/4. Поднимаю ферму (без сборки и без сети)"
# -p s4dfarm — фиксируем имя проекта, чтобы совпало с загруженными образами
docker compose -p s4dfarm up -d --no-build
docker compose -p s4dfarm ps

IP=$(hostname -I 2>/dev/null | awk '{print $1}')
cat <<EOF

=============================================================
 Ферма поднята ОФЛАЙН.

 Морда:        http://${IP:-<ip_этой_машины>}:5137   (пароль из .env)
 Клиент:       cd repos/S4DFarm/client
               python3 start_sploit.py sploits/<мой>.py \\
                   --server-url http://${IP:-127.0.0.1}:5137 \\
                   --server-pass <пароль> --attack-period 110

 Дальше: FARM.md (настройка/запуск), SPLOITS.md (сплойты)
=============================================================
EOF
