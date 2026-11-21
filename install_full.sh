#!/usr/bin/env bash
# =============================================================================
# install_full.sh — РЕЗЕРВНЫЙ установщик: сценарий «git + apt + PyPI открыты».
#
#   sudo bash install_full.sh
#
# Запускать ПОСЛЕ install.sh (apt-софт и docker ставит он; этот — только
# python-добро). Если PyPI закрыт — честно об этом скажет и выйдет:
# базового набора (requests уже есть + wheelhouse в репо) хватает для боя.
#
# Что дотягивает, раз уж есть PyPI:
#   pwntools       — эксплойты (pwn.*), если пригодится что-то сетевое/бинарное
#   beautifulsoup4, lxml — парсинг HTML (когда флаг надо выковырять из верстаки)
#   PyJWT          — разбор/подделка JWT-токенов
#   gevent, Faker  — то, на чём написаны чекеры оргов (для отладки своих сценариев)
#   + checklib с гитхаба (на PyPI его нет)
# =============================================================================
set -uo pipefail

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[1;32mOK\033[0m  %s\n' "$*"; }
warn() { printf '    \033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m[X] %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "запусти от root: sudo bash $0"

say "1/3. Проверяю, открыт ли PyPI (8 секунд)"
if curl -s -m 8 -o /dev/null https://pypi.org/simple/; then
    ok "PyPI отвечает"
else
    die "PyPI недоступен — это НОРМАЛЬНО на игре: сидим на базовом наборе
        (requests уже есть; если нет — wheelhouse в images/). Этот скрипт не нужен."
fi

say "2/3. Ставлю пакеты (по одному, падение одного не валит остальные)"
PIP() {
    pip3 install --break-system-packages "$@" 2>/dev/null \
    || pip3 install "$@" 2>/dev/null \
    || pip3 install "$@"
}
PYPI_PKGS=(requests pwntools beautifulsoup4 lxml PyJWT gevent Faker)
for pkg in "${PYPI_PKGS[@]}"; do
    printf '    --> %s...\n' "$pkg"
    if PIP "$pkg"; then
        ok "$pkg"
    else
        warn "$pkg не поставился — продолжаю (он не обязателен для боя)"
    fi
done

# checklib живёт на гитхабе (на PyPI нет):
printf '    --> checklib (с гитхаба)...\n'
if PIP git+https://github.com/pomo-mondreganto/checklib; then
    ok "checklib"
else
    warn "checklib не поставился — нужен не всем сплойтам (SPLOITS.md живёт на stdlib+requests)"
fi

say "3/3. Сводка"
for m in requests pwn bs4 lxml jwt gevent faker checklib; do
    if python3 -c "import $m" 2>/dev/null; then
        ok "python: $m — работает"
    else
        warn "python: $m — нет (не критично)"
    fi
done
cat <<'EOF'

=====================================================
 Готово. Зачем это всё в бою:
   pwn.*        — эксплойты/протоколы, если requests мало
   bs4 / lxml   — вытаскивать флаги из HTML
   jwt          — разбирать/подделывать токены сервисов
   gevent/Faker — как у чекеров оргов (отладка сценариев)
 База боя прежняя: сплойты пишутся на requests (SPLOITS.md).
=====================================================
EOF
