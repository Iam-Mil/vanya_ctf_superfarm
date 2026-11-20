#!/usr/bin/env bash
# =============================================================================
# setup_kali.sh — настройка Kali (атакующей машины) перед стартом.
#
#   sudo ./setup_kali.sh            # прокси + софт + ключ + проверка жюри
#
# Настраивает:
#   1. Прокси-сервер оргов http://10.10.10.10:8080 (сертификат + env)
#   2. Базовый софт
#   3. SSH-ключ команды (если ещё нет)
#   4. Проверку связи с жюри (scoreboard, attack_data)
# =============================================================================
set -uo pipefail

PROXY="http://10.10.10.10:8080"
JURY="http://10.10.10.10"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }

[[ $EUID -eq 0 ]] || { echo "Запусти от root: sudo $0"; exit 1; }

# --- 1. Прокси -----------------------------------------------------------------
say "1/4. Прокси $PROXY"
echo "Скачиваю сертификат прокси..."
curl -s -o /tmp/ctf-proxy.crt "$PROXY/cert" || warn "не смог скачать $PROXY/cert"
if [[ -s /tmp/ctf-proxy.crt ]]; then
    cp /tmp/ctf-proxy.crt /usr/local/share/ca-certificates/ctf-proxy.crt
    update-ca-certificates 2>&1 | tail -2
fi

cat > /etc/profile.d/ctf-proxy.sh <<EOF
export http_proxy="$PROXY"
export https_proxy="$PROXY"
export HTTP_PROXY="$PROXY"
export HTTPS_PROXY="$PROXY"
export no_proxy="localhost,127.0.0.1,10.2.0.0/8,10.10.10.10"
export NO_PROXY="localhost,127.0.0.1,10.2.0.0/8,10.10.10.10"
EOF
chmod 0644 /etc/profile.d/ctf-proxy.sh

# apt через прокси (только если понадобится докачать пакеты на месте)
cat > /etc/apt/apt.conf.d/95ctfproxy <<EOF
Acquire::http::Proxy "$PROXY";
Acquire::https::Proxy "$PROXY";
EOF

echo "env-переменные применятся в НОВОЙ сессии шелла (source /etc/profile.d/ctf-proxy.sh)"
warn "Помни: через прокси разрешены только HTTP GET и ограниченный список сайтов."
warn "Всё тяжёлое (образы, пакеты) качаем ЗАРАНЕЕ, не на игре."

# --- 2. Софт -------------------------------------------------------------------
say "2/4. Софт"
apt-get update -qq 2>/dev/null || warn "apt update не прошёл (прокси/сеть)"
apt-get install -y -qq jq nmap sqlmap curl rsync python3-pip 2>/dev/null \
    || warn "что-то не поставилось — разберись руками"
python3 -c 'import requests' 2>/dev/null || pip3 install -q requests

# checklib ставим с гитхаба оргов (он нужен не всем сплойтам; на месте
# GitHub через прокси оргов доступен):
if ! python3 -c 'import checklib' 2>/dev/null; then
    pip3 install -q git+https://github.com/pomo-mondreganto/checklib 2>/dev/null \
        || echo "[!] checklib не поставился — он нужен не всем сплойтам, можно повторить позже"
fi

# --- 3. SSH-ключ команды ---------------------------------------------------------
say "3/4. SSH-ключ"
if [[ ! -f /root/.ssh/id_ed25519 ]]; then
    ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519 -C "innctf-$(hostname)"
fi
echo "Публичный ключ (его добавить на вулнбокс через harden.sh):"
cat /root/.ssh/id_ed25519.pub

# --- 4. Проверка жюри --------------------------------------------------------------
say "4/4. Проверка связи с жюри $JURY"
echo "— scoreboard:"
curl -s -m 5 "$JURY/api/client/config/" | head -c 300; echo; echo
echo "— команды:"
curl -s -m 5 "$JURY/api/client/teams/" | jq -r '.[] | "\(.ip)  \(.name)"' 2>/dev/null \
    | head -15 || warn "жюри не отвечает — проверь сеть/адрес"
echo
echo "— attack_data:"
curl -s -m 5 "$JURY/api/client/attack_data/" | head -c 300; echo

say "Kali готова. Свой IP: $(ip -4 addr show | grep -oP '10\.2\.\d+\.\d+' | head -1)"
echo "Запиши его — он пойдёт в --allow-ssh на вулнбоксе."
