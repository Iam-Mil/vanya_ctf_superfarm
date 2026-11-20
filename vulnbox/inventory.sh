#!/usr/bin/env bash
# =============================================================================
# inventory.sh — карта сервисов на вулнбоксе + бэкапы (запускать от root).
#
#   sudo ./inventory.sh
#
# Ничего не меняет и не ломает. Пишет отчёт в /root/inventory_<ts>.txt
# и собирает tar-бэкап сервисов в /root/vulnbox_backup_<ts>.tar.gz —
# его потом стянуть на Kali (второй экземпляр бэкапа, как требуют орги).
# =============================================================================
set -uo pipefail
TS=$(date +%s)
OUT="/root/inventory_${TS}.txt"

sec() { printf '\n===== %s =====\n' "$*" | tee -a "$OUT"; }
run() { sec "$1"; shift; "$@" 2>&1 | tee -a "$OUT" | head -40; }

: > "$OUT"

run "Слушающие порты (TCP/UDP)"        ss -tulpn
run "Docker-контейнеры"               docker ps -a
run "Docker compose проекты"          docker compose ls
run "Запущенные сервисы systemd"      systemctl list-units --type=service --state=running
run "Процессы (топ по памяти)"         ps aux --sort=-%mem
run "Каталоги сервисов"               ls -la /opt /srv /var/www /home /root 2>/dev/null
run "Nginx конфиги"                   ls -la /etc/nginx/sites-enabled/ 2>/dev/null
run "Cron"                            bash -c 'crontab -l 2>/dev/null; ls /etc/cron.d/ 2>/dev/null'
run "SUID-файлы"                      find / -perm -4000 -type f 2>/dev/null

sec "Секреты в исходниках (первые 50)"
grep -rniE 'secret|password|passwd|api[_-]?key|token' \
    /opt /srv /var/www 2>/dev/null | grep -v Binary | head -50 | tee -a "$OUT"

sec "Открытые порты снаружи (самоскан)"
nmap -sT -p- --open 127.0.0.1 2>/dev/null | tee -a "$OUT"

# ---- бэкап сервисов ----------------------------------------------------------
BACKUP="/root/vulnbox_backup_${TS}.tar.gz"
BACKUP_LIST="/root/backup_list_${TS}.txt"
: > "$BACKUP_LIST"
for d in /opt /srv /var/www /etc/nginx /etc/systemd/system /etc/supervisor \
         /etc/docker /root/.ssh; do
    [[ -e "$d" ]] && echo "$d" >> "$BACKUP_LIST"
done
# отдельные docker-compose файлы где найдутся
find / -maxdepth 4 -name 'docker-compose*.yml' -not -path '/proc/*' 2>/dev/null \
    >> "$BACKUP_LIST"

tar czf "$BACKUP" -T "$BACKUP_LIST" 2>/dev/null \
    && echo "Бэкап: $BACKUP" | tee -a "$OUT" \
    || echo "tar не смог полностью — смотри $BACKUP_LIST" | tee -a "$OUT"

cat <<EOF

Отчёт:   $OUT
Бэкап:   $BACKUP

Стянуть бэкап на Kali (второй экземпляр!):
    rsync -av root@10.2.X.2:/root/vulnbox_backup_${TS}.tar.gz ~/vb_backups/
    rsync -av root@10.2.X.2:/root/backup_* ~/vb_backups/

Дальше:
  1) сопоставь порты из ss -tulpn с сервисами — это порты, которые ДОЛЖНЫ быть открыты;
  2) всё, что слушает лишнее — systemctl disable --now <svc> или iptables-правило;
  3) исходники сервисов читать прямо на Kali — удобнее, чем на боксе.
EOF
