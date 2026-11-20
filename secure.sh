#!/usr/bin/env bash
# =============================================================================
# secure.sh — обезопасить машину по чек-листу оргов (InnoCTF A&D).
#
#   sudo ./secure.sh [--pubkey FILE]... [--gen-key] [--password 'PASS']
#                    [--strict] [--yes]
#
# Что делает (запускать ОТ ROOT на КАЖДОЙ машине — вулнбоксе и своих Kali):
#   1. МЕНЯЕТ ПАРОЛЬ (рандомный, если не задан) — печатает его СОХРАНИ
#   2. КЛЮЧИ SSH:
#        --gen-key : создаёт НОВУЮ пару на этой машине; приватник печатается —
#                    забери его на свою Kali (или scp — команда печатается)
#        --pubkey F: добавляет твой публичный ключ с Kali (можно несколько)
#   3. УДАЛЯЕТ ЛИШНИЕ КЛЮЧИ: authorized_keys переписывается только нашими
#      ключами (старый сохраняется в бэкап)
#   4. ПО УМОЛЧАНИЮ вход остаётся ДВУМЯ СПОСОБАМИ: по ключу И по новому
#      паролю (никто не запрётся). Полный чек-лист оргов — флаг --strict:
#      вход по паролю отключается, НО только после автопроверки входа
#      по ключу (проверка не прошла — не отключаем, ничего не ломаем).
#
# ГЛАВНОЕ ПРАВИЛО: не закрывай текущую сессию, пока не проверил вход
# по ключу из другого терминала!
# =============================================================================
set -uo pipefail

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[1;32mOK\033[0m  %s\n' "$*"; }
warn() { printf '    \033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m[X] %s\033[0m\n' "$*" >&2; exit 1; }

PUBKEYS=()
GEN_KEY=0
GIVEN_PASS=""
STRICT=0
ASSUME_YES=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pubkey)    PUBKEYS+=("$2"); shift 2 ;;
        --gen-key)   GEN_KEY=1; shift ;;
        --password)  GIVEN_PASS="$2"; shift 2 ;;
        --strict)    STRICT=1; shift ;;
        --yes|-y)    ASSUME_YES=1; shift ;;
        -h|--help)   grep '^#' "$0" | head -20; exit 0 ;;
        *) die "неизвестный аргумент: $1 (см. --help)" ;;
    esac
done

[[ $EUID -eq 0 ]] || die "запусти от root: sudo $0"
TARGET_USER="${SUDO_USER:-root}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TS=$(date +%s)
SSH_DIR="$TARGET_HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

say "1/4. Пароль для пользователя: $TARGET_USER"
if [[ -n "$GIVEN_PASS" ]]; then
    NEW_PASS="$GIVEN_PASS"
else
    NEW_PASS=$(openssl rand -hex 12 2>/dev/null || head -c 12 /dev/urandom | xxd -p)
fi
echo "$TARGET_USER:$NEW_PASS" | chpasswd \
    || die "не смог сменить пароль (chpasswd)"
# локальная копия на случай «потеряли чат»:
umask 077; echo "$TS $TARGET_USER $NEW_PASS" > /root/.ctf_passwd_backup
printf '\n    ╔══════════════════════════════════════════╗\n'
printf     '    ║  НОВЫЙ ПАРОЛЬ (запиши в чат/creds.txt!):  ║\n'
printf     '    ║                                          ║\n'
printf     '    ║        %s        ║\n' "$NEW_PASS"
printf     '    ╚══════════════════════════════════════════╝\n\n'
ok "пароль изменён; резервная копия: /root/.ctf_passwd_backup (root-only)"

say "2/4. SSH-ключи: добавляем наши"
mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"; chown "$TARGET_USER" "$SSH_DIR"
touch "$AUTH_KEYS"
# бэкап старых ключей перед чисткой
[[ -s "$AUTH_KEYS" ]] && cp -a "$AUTH_KEYS" "$AUTH_KEYS.bak.$TS" \
    && ok "старый authorized_keys: $AUTH_KEYS.bak.$TS"

NEW_KEYS=()
if [[ $GEN_KEY -eq 1 ]]; then
    KEY="$SSH_DIR/ctf_ed25519"
    ssh-keygen -q -t ed25519 -N "" -C "ctf-$TARGET_USER-$(hostname)" -f "$KEY" <<<y >/dev/null 2>&1 || true
    if [[ -f "$KEY" ]]; then
        chown "$TARGET_USER" "$KEY" "$KEY.pub"
        NEW_KEYS+=("$KEY.pub")
        ok "создана пара: $KEY"
        warn "ПРИВАТНИК нужно забрать на свою машину — команда:"
        printf  '        scp %s@%s:%s ~/.ssh/ && chmod 600 ~/.ssh/ctf_ed25519\n\n' \
            "$TARGET_USER" "$(hostname -I 2>/dev/null | awk '{print $1}')" "$KEY"
        warn "или скопируй содержимое приватника в чат команды (только в свой!):"
        printf  '        -----BEGIN OPENSSH PRIVATE KEY-----\n'
        sed 's/^/        /' "$KEY"
        printf  '        -----END OPENSSH PRIVATE KEY-----\n\n'
    else
        warn "ssh-keygen не смог создать ключ"
    fi
fi
for pk in "${PUBKEYS[@]:-}"; do
    [[ -z "$pk" ]] && continue
    if [[ -f "$pk" ]]; then
        NEW_KEYS+=("$pk")
        ok "добавляется: $pk"
    elif [[ "$pk" == ssh-* ]]; then
        # ключ передан прямо строкой
        echo "$pk" > "$SSH_DIR/.incoming.pub"; NEW_KEYS+=("$SSH_DIR/.incoming.pub")
        ok "добавлен ключ, переданный строкой"
    else
        warn "нет файла: $pk — пропускаю"
    fi
done

say "3/4. Удаляем лишние ключи (оставляем только наши)"
BEFORE=$(wc -l < "$AUTH_KEYS" 2>/dev/null || echo 0)
: > "$AUTH_KEYS"
for k in "${NEW_KEYS[@]:-}"; do
    [[ -z "$k" || ! -f "$k" ]] && continue
    cat "$k" >> "$AUTH_KEYS"
done
rm -f "$SSH_DIR/.incoming.pub"
chmod 600 "$AUTH_KEYS"; chown "$TARGET_USER" "$AUTH_KEYS"
AFTER=$(wc -l < "$AUTH_KEYS")
ok "было строк: $BEFORE -> стало: $AFTER (только наши ключи)"
[[ "$BEFORE" != "$AFTER" && -f "$AUTH_KEYS.bak.$TS" ]] \
    && ok "удалённые — в бэкапе $AUTH_KEYS.bak.$TS"

say "4/4. Вход по паролю"
SSHD_CONF_DIR=/etc/ssh/sshd_config.d
if [[ $STRICT -eq 1 ]]; then
    # автопроверка входа по ключу ДО отключения пароля
    TESTED=0
    for k in "${NEW_KEYS[@]:-}"; do
        [[ -z "$k" || ! -f "$k" ]] && continue
        PRIV="${k%.pub}"
        [[ -f "$PRIV" ]] || continue
        if command -v ssh >/dev/null; then
            ssh -i "$PRIV" -o BatchMode=yes -o StrictHostKeyChecking=no \
                -o ConnectTimeout=7 ${TARGET_USER}@localhost true 2>/dev/null \
                && TESTED=1 && break
        fi
    done
    if [[ $TESTED -eq 1 ]]; then
        mkdir -p "$SSHD_CONF_DIR"
        cat > "$SSHD_CONF_DIR/10-ctf-strict.conf" <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
EOF
        sshd -t 2>/dev/null && { systemctl restart ssh 2>/dev/null || systemctl restart sshd; } \
            && ok "парольный вход ОТКЛЮЧЁН (вход только по ключу)" \
            || warn "sshd не перезапустился — конфиг применится при рестарте"
    else
        warn "автопроверка входа по ключу НЕ прошла — парольный вход НЕ отключаю."
        warn "проверь ключ руками из другого терминала, затем: sudo $0 --strict"
    fi
else
    ok "по умолчанию оставлены ДВА способа: ключ + новый пароль (никто не запрётся)"
    echo "    полный чек-лист оргов (отключить пароль) — после проверки ключа:"
    echo "        sudo $0 --strict"
fi

cat <<EOF

=============================================================
 Готово для $(hostname):
   пользователь:   $TARGET_USER
   пароль:         новый (см. выше / /root/.ctf_passwd_backup)
   ключи:          только наши ($AFTER шт.)
   вход по паролю: $([[ $STRICT -eq 1 ]] && echo "отключён (--strict)" || echo "включён (новый пароль)")

 СЛЕДУЮЩИЙ ШАГ — не закрывая эту сессию, из ДРУГОГО терминала:
   ssh $TARGET_USER@$(hostname -I 2>/dev/null | awk '{print $1}')    # по новому паролю
   ssh -i <твой_ключ> $TARGET_USER@$(hostname -I 2>/dev/null | awk '{print $1}')   # по ключу
 Оба зашли? всё. Не зашёл ключ — верни бэкап:
   cp $AUTH_KEYS.bak.$TS $AUTH_KEYS
=============================================================
EOF
