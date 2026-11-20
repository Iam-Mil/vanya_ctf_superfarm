#!/usr/bin/env bash
# =============================================================================
# backup.sh — бэкап/восстановление сервисов вулнбокса (InnoCTF A&D).
#
#   sudo ./backup.sh create [имя]      # собрать полный архив (по умолчанию manual)
#   sudo ./backup.sh snap ФАЙЛ...      # микро-бэкап перед патчем: ФАЙЛ -> ФАЙЛ.bak.<ts>
#   sudo ./backup.sh restore АРХИВ     # распаковать в /root/restore_*/ и показать,
#                                      # что куда возвращать (сам НЕ перезаписывает!)
#
# Что собирает create:
#   - исходники и конфиги: /opt /srv /var/www /etc/nginx /etc/systemd/...
#   - все docker-compose файлы на диске
#   - данные: все bind-монтирования и docker-тома (postgres/mongo данные!)
#   - карту контейнеров (docker ps + docker inspect) — знать, как всё устроено
#   - дампы БД (pg_dumpall/mongodump, по возможности)
#
# Файлы кладутся в /root/backups/<имя>_<ts>.tgz — их СТАНЯЙ НА КАЛИ (см. вывод).
# =============================================================================
set -uo pipefail

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[1;32mOK\033[0m  %s\n' "$*"; }
warn() { printf '    \033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m[X] %s\033[0m\n' "$*" >&2; exit 1; }

CMD="${1:-help}"
[[ $EUID -eq 0 ]] || die "запусти от root: sudo $0 $CMD"

# --- snap: микро-бэкап файла перед правкой ------------------------------------
if [[ "$CMD" == "snap" ]]; then
    [[ $# -ge 2 ]] || die "укажи файл(ы): sudo $0 snap app.py"
    shift
    for f in "$@"; do
        if [[ -f "$f" ]]; then
            cp -a "$f" "$f.bak.$(date +%s)" && ok "$f -> $f.bak.$(date +%s)"
        else
            warn "нет файла: $f"
        fi
    done
    exit 0
fi

# --- create: полный архив ------------------------------------------------------
if [[ "$CMD" == "create" ]]; then
    NAME="${2:-manual}"
    TS=$(date +%Y%m%d_%H%M%S)
    OUT="/root/backups"
    STAGE=$(mktemp -d)
    ARCHIVE="$OUT/${NAME}_${TS}.tgz"
    mkdir -p "$OUT" "$STAGE/volumes" "$STAGE/dbdumps"

    say "1/5. Карта контейнеров"
    docker ps -a > "$STAGE/manifest.txt" 2>/dev/null || true
    {
        echo "# manifest: $(hostname) @ $(date)"
        echo
        docker ps -a
    } > "$STAGE/manifest.txt" 2>/dev/null || true
    docker inspect $(docker ps -aq 2>/dev/null) > "$STAGE/containers.json" 2>/dev/null || true
    ok "docker ps + docker inspect записаны"

    say "2/5. Исходники и конфиги"
    SRC_TAR="$STAGE/sources_and_configs.tar"
    CREATED_SOURCES=0
    for d in /opt /srv /var/www /etc/nginx /etc/supervisor \
             /etc/systemd/system /etc/cron.d /etc/crontab; do
        [[ -e "$d" ]] || continue
        tar rf "$SRC_TAR" "$d" 2>/dev/null && CREATED_SOURCES=1 || true
    done
    # все docker-compose на диске (обычно рядом с исходниками)
    find / -maxdepth 4 \( -name 'docker-compose*.yml' -o -name 'compose.yml' \) \
        -not -path '/proc/*' -not -path '/sys/*' -not -path '/var/lib/docker/*' \
        2>/dev/null | sort > "$STAGE/compose_files.list" || true
    while IFS= read -r f; do
        [[ -f "$f" ]] && tar rf "$SRC_TAR" "$f" 2>/dev/null || true
    done < "$STAGE/compose_files.list"
    [[ $CREATED_SOURCES -eq 1 ]] && ok "исходники/конфиги собраны" || warn "стандартных каталогов не нашлось (смотри manifest.txt)"

    say "3/5. Данные сервисов: bind-монтирования и docker-тома"
    # 3а. bind-монтирования (каталоги хоста, прокинутые в контейнеры)
    docker ps -q 2>/dev/null | xargs -r docker inspect \
        --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{"\n"}}{{end}}{{end}}' \
        2>/dev/null | sort -u | while IFS= read -r src; do
        [[ -z "$src" || ! -e "$src" ]] && continue
        slug=$(echo "$src" | tr '/' '_' | sed 's/^_//')
        tar czf "$STAGE/volumes/bind_${slug}.tgz" -C / "$src" 2>/dev/null \
            && ok "bind: $src" || warn "bind не смог: $src"
    done
    # 3б. именованные docker-тома
    docker volume ls -q 2>/dev/null | while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        docker run --rm -v "$v":/_data -v "$STAGE/volumes":/_out alpine \
            tar czf "/_out/volume_${v}.tgz" -C /_data . >/dev/null 2>&1 \
            && ok "том: $v" || warn "том не смог: $v"
    done

    say "4/5. Дампы БД (по возможности)"
    # postgres
    docker ps --format '{{.Names}}' 2>/dev/null | while IFS= read -r c; do
        img=$(docker inspect -f '{{.Config.Image}}' "$c" 2>/dev/null || true)
        if [[ "$img" == *postgres* ]]; then
            PGU=$(docker exec "$c" printenv POSTGRES_USER 2>/dev/null || echo postgres)
            docker exec "$c" pg_dumpall -U "$PGU" 2>/dev/null \
                | gzip > "$STAGE/dbdumps/${c}_pg_dump.sql.gz" \
                && ok "pg_dumpall: $c"
        fi
        if [[ "$img" == *mongo* ]]; then
            docker exec "$c" mongodump --archive --gzip 2>/dev/null \
                > "$STAGE/dbdumps/${c}_mongo.archive.gz" \
                && ok "mongodump: $c"
        fi
    done

    say "5/5. Собираю архив"
    tar czf "$ARCHIVE" -C "$STAGE" . || die "не смог создать $ARCHIVE"
    rm -rf "$STAGE"
    SIZE=$(du -h "$ARCHIVE" | cut -f1)
    ok "архив: $ARCHIVE ($SIZE)"

    IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    cat <<EOF

=============================================================
 ГОТОВО: $ARCHIVE ($SIZE)

 СТЯНУТЬ НА КАЛИ (обязательно! бэкап на боксе может умереть
 вместе с боксом):
     rsync -av root@$IP:/root/backups/ ~/vb_backups/
     # или одну копию:
     scp root@$IP:$ARCHIVE ~/vb_backups/

 ВОССТАНОВИТЬ (на боксе):
     sudo ./backup.sh restore $ARCHIVE
=============================================================
EOF
    exit 0
fi

# --- restore: распаковать и объяснить, что куда ---------------------------------
if [[ "$CMD" == "restore" ]]; then
    ARCHIVE="${2:-}"
    [[ -f "$ARCHIVE" ]] || die "укажи архив: sudo $0 restore /root/backups/<имя>.tgz"
    DEST="/root/restore_$(basename "$ARCHIVE" .tggz 2>/dev/null || basename "$ARCHIVE" .tgz)_$(date +%s)"
    mkdir -p "$DEST"
    say "Распаковываю в $DEST (не трогаю живые файлы!)"
    tar xzf "$ARCHIVE" -C "$DEST" || die "архив битый?"

    say "Содержимое"
    ( cd "$DEST" && find . -maxdepth 2 | sort | sed 's/^/    /' | head -25 )
    cat <<EOF

=============================================================
 ЧТО ДАЛЬШЕ (по возрастанию риска):

 1. ПОСМОТРЕТЬ: все исходники/конфиги лежат в $DEST/sources_and_configs.tar
    (внутри — пути как на диске). Распаковать для просмотра:
        tar xf $DEST/sources_and_configs.tar -C /tmp/look

 2. ТОЧЕЧНЫЙ ОТКАТ (например, вернуть один файл):
        tar xf $DEST/sources_and_configs.tar -C / путь/к/файлу
    (перезапишет текущий — сначала, если он дорог, сделай его снап:
        sudo ./backup.sh snap /путь/к/файлу )

 3. ПОЛНОЕ ВОССТАНОВЛЕНИЕ ДАННЫХ СЕРВИСОВ:
        for v in $DEST/volumes/*.tgz; do echo "== $v"; tar tzf \$v | head -5; done
    каждый volumes/*.tgz — содержимое одного каталога/тома
    (bind-архивы содержат исходный путь: tar xzf <файл>.tgz -C / вернёт
     данные на место; тома — через docker run --rm -v <имя_тома>:/_data ...)

 4. ПОСЛЕ ВОССТАНОВЛЕНИЯ ИСХОДНИКОВ сервис надо пересобрать:
        cd <каталог docker-compose> && docker compose up --build -d

 ВАЖНО: перед большим восстановлением сделай свежий бэкап текущего:
        sudo ./backup.sh create before-restore
=============================================================
EOF
    exit 0
fi

# --- help -----------------------------------------------------------------------
grep '^#' "$0" | head -20
