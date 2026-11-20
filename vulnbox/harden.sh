#!/usr/bin/env bash
# =============================================================================
# harden.sh — первые 10 минут на вулнбоксе (InnoCTF Junior final).
#
# Запускать ОТ ROOT на вулнбоксе (10.2.X.2):
#   sudo ./harden.sh --pubkey ~/.ssh/id_ed25519.pub \
#                    --allow-ssh 10.2.X.10 10.2.X.11 10.2.X.12
#
# Что делает (по чек-листу оргов):
#   1. Смена пароля (спросит интерактивно)
#   2. Добавляет ваши SSH-ключи
#   3. Чистит чужие ключи (только с --keep-only-our-keys)
#   4. Отключает вход по паролю (только после РУЧНОЙ проверки входа по ключу!)
#   5. Ставит базовый софт
#   6. Снимает бэкап конфигов
#   7. При --apply-firewall: SSH разрешает только с ваших Kali
#
# Чего НЕ делает (намеренно):
#   * НЕ ставит политику DROP на INPUT — можно случайно положить чекер.
#     Закрывать конкретные ненужные порты — руками по inventory.sh.
# =============================================================================
set -uo pipefail

TS=$(date +%s)
BACKUP_DIR="/root/backup_${TS}"
PUBKEYS=()
ALLOW_SSH=()
KEEP_ONLY=0
APPLY_FIREWALL=0
SSHD_DONE=0

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }

usage() {
    cat <<EOF
Usage: $0 [options]
  --pubkey FILE            добавить публичный ключ (можно несколько раз)
  --allow-ssh IP...        IP ваших Kali, с которых разрешён SSH
  --keep-only-our-keys     оставить в authorized_keys ТОЛЬКО наши ключи
  --apply-firewall         разрешить SSH только с --allow-ssh, остальное к 22 — drop
  --skip-passwd            не менять пароль
  -h                       справка
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pubkey) PUBKEYS+=("$2"); shift 2 ;;
        --allow-ssh) shift
            while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do ALLOW_SSH+=("$1"); shift; done ;;
        --keep-only-our-keys) KEEP_ONLY=1; shift ;;
        --apply-firewall) APPLY_FIREWALL=1; shift ;;
        --skip-passwd) SKIP_PASSWD=1; shift ;;
        -h|--help) usage ;;
        *) warn "неизвестный аргумент: $1"; usage ;;
    esac
done

[[ $EUID -eq 0 ]] || { echo "Запусти от root: sudo $0"; exit 1; }

mkdir -p "$BACKUP_DIR"

# --- 1. Пароль ---------------------------------------------------------------
if [[ -z ${SKIP_PASSWD:-} ]]; then
    say "1/7. Смена пароля текущего пользователя ($USER)"
    read -rp "Сменить пароль сейчас? [Y/n] " ans
    if [[ ! ${ans:-y} =~ ^[Nn] ]]; then
        passwd
    else
        warn "Пароль НЕ сменён — не забудь сделать это вручную!"
    fi
else
    say "1/7. Смена пароля пропущена (--skip-passwd)"
fi

# --- 2. Ключи ----------------------------------------------------------------
say "2/7. Установка SSH-ключей"
for home in /root "$HOME"; do
    sshdir="$home/.ssh"
    [[ -f "$sshdir/authorized_keys" ]] && \
        cp -a "$sshdir/authorized_keys" "$BACKUP_DIR/authorized_keys.$(basename "$home").bak" 2>/dev/null
    mkdir -p "$sshdir"; chmod 700 "$sshdir"
    touch "$sshdir/authorized_keys"; chmod 600 "$sshdir/authorized_keys"
done
for pk in "${PUBKEYS[@]:-}"; do
    [[ -z "$pk" ]] && continue
    [[ -f "$pk" ]] || { warn "нет файла $pk — пропускаю"; continue; }
    key=$(cat "$pk")
    if ! grep -qxF "$key" /root/.ssh/authorized_keys 2>/dev/null; then
        echo "$key" >> /root/.ssh/authorized_keys
        echo "    + добавлен ключ из $pk"
    fi
done
[[ ${#PUBKEYS[@]:-0} -eq 0 ]] && warn "Ключи не переданы (--pubkey) —authorized_keys не трогал"

# --- 3. Чужие ключи -----------------------------------------------------------
if [[ $KEEP_ONLY -eq 1 && ${#PUBKEYS[@]:-0} -gt 0 ]]; then
    say "3/7. Чистка authorized_keys — оставляю только наши ключи"
    cp -a /root/.ssh/authorized_keys "$BACKUP_DIR/authorized_keys.pre-clean"
    : > /root/.ssh/authorized_keys
    for pk in "${PUBKEYS[@]}"; do cat "$pk" >> /root/.ssh/authorized_keys; done
    chmod 600 /root/.ssh/authorized_keys
    echo "   Authorized_keys переписан; старый — в $BACKUP_DIR"
else
    say "3/7. Чистка ключей пропущена (нужны --pubkey И --keep-only-our-keys)"
fi

# --- 4. Отключение парольного входа -------------------------------------------
say "4/7. SSH: отключение входа по паролю"
SSHD_CONF_DIR=/etc/ssh/sshd_config.d
mkdir -p "$SSHD_CONF_DIR"
cat > "$SSHD_CONF_DIR/10-ctf-hardening.conf" <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
EOF
# бэкап и валидация конфига перед рестартом
cp -a /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.bak" 2>/dev/null
if sshd -t 2>/dev/null; then
    systemctl restart ssh 2>/dev/null || systemctl restart sshd
    SSHD_DONE=1
    warn "ПРОВЕРЬ ВХОД ПО КЛЮЧУ В НОВОМ ТЕРМИНАЛЕ (не закрывай текущую сессию!):"
    warn "    ssh -i <ключ> root@10.2.X.2"
else
    warn "sshd -t ругается — конфиг не применяю, смотри:"
    sshd -t
fi

# --- 5. Софт ------------------------------------------------------------------
say "5/7. Установка софта (jq nmap tcpdump rsync python3-pip)"
apt-get update -qq 2>/dev/null
apt-get install -y -qq jq nmap tcpdump rsync python3-pip 2>/dev/null \
    || warn "apt не смог — проверь сеть/прокси, поставь руками"

# --- 6. Бэкап конфигов ---------------------------------------------------------
say "6/7. Бэкап в $BACKUP_DIR"
for p in /etc/ssh/sshd_config /etc/passwd /etc/shadow /etc/group \
         /etc/nginx /etc/systemd/system /etc/crontab /etc/rc.local; do
    [[ -e "$p" ]] && cp -a "$p" "$BACKUP_DIR/" 2>/dev/null
done
(crontab -l 2>/dev/null; for u in $(cut -d: -f1 /etc/passwd); do
    crontab -u "$u" -l 2>/dev/null | sed "s/^/$u: /"
done) > "$BACKUP_DIR/crontabs.txt" 2>/dev/null
echo "    лежит в $BACKUP_DIR (не забудь стянуть на Kali — см. inventory.sh)"

# --- 7. Firewall ---------------------------------------------------------------
say "7/7. Firewall"
if [[ $APPLY_FIREWALL -eq 1 && ${#ALLOW_SSH[@]:-0} -gt 0 ]]; then
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    for ip in "${ALLOW_SSH[@]}"; do
        iptables -A INPUT -p tcp -s "$ip" --dport 22 -j ACCEPT
        echo "    SSH разрешён с $ip"
    done
    iptables -A INPUT -p tcp --dport 22 -j DROP
    warn "Сохранение правил: apt install iptables-persistent && netfilter-persistent save"
    warn "Политика INPUT осталась ACCEPT — сервисы жюри не задеты."
else
    echo "    Пропускаю (нужны --apply-firewall и --allow-ssh)."
    echo "    ВАЖНО: весь трафик других команд приходит со шлюза 10.2.X.1 —"
    echo "    банить по IP атакующих бессмысленно. SSH фильтруем только"
    echo "    белым списком IP ваших Kali, НЕ всей подсети (шлюз тоже в ней)."
fi

say "Готово. Дальше: ./inventory.sh — карта сервисов, портов и бэкапы."
[[ $SSHD_DONE -eq 1 ]] && warn "ЕЩЁ РАЗ: проверь SSH-вход по ключу из нового терминала!"
