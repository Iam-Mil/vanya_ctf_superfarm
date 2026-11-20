# CHEATSHEET — короткие команды на все случаи

## Жюри и флаги

```bash
export GAME_URL=http://10.10.10.10
export TEAM_TOKEN=<токен из письма>          # в ~/creds.txt, chmod 600

curl -s $GAME_URL/api/client/config/ | jq          # реальные параметры игры
curl -s $GAME_URL/api/client/teams/ | jq -r '.[] | "\(.ip)  \(.name)"'
curl -s $GAME_URL/api/client/attack_data/ | jq    # публичные flag ids

# ручная сдача:
echo 'FLAG...' | python3 forcad/thrower.py
# или curl'ом (максимум 100 флагов за раз, ≤2 запросов/сек!):
curl -X PUT $GAME_URL/flags -H "X-Team-Token: $TEAM_TOKEN" \
     -H 'Content-Type: application/json' -d '["FLAG...","FLAG..."]'
```

Ответы жюри: `Flag accepted! Earned N flag points!` / `already stolen` /
`invalid or too old` / `your own` / `Game is not available` (игра не началась).

## Vulnbox: первые минуты (защитник)

```bash
passwd                                          # 1. сменить пароль
# 2. ключи (pubkey сгенерён на Kali заранее):
mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo "<pubkey>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
# 3. отключить пароли — ТОЛЬКО после проверки входа по ключу в новом терминале:
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\n' \
  > /etc/ssh/sshd_config.d/10-hard.conf && sshd -t && systemctl restart ssh

sudo ./vulnbox/harden.sh --pubkey ~/pub.key --allow-ssh <ip_kali_1> <ip_kali_2> --apply-firewall
sudo ./vulnbox/inventory.sh                      # карта сервисов + бэкап-архив
rsync -av root@10.2.X.2:/root/vulnbox_backup_*.tar.gz ~/vb_backups/   # копия №2 на Kali
```

## Vulnbox: разведка

```bash
ss -tulpn                                        # слушающие порты
docker ps && docker compose ls                   # сервисы в docker
systemctl list-units --type=service --state=running
ls -la /opt /srv /var/www
grep -rniE 'secret|password|key|token' /opt /srv | head -50
# как видят вас другие (с Kali):
nmap -sS -p- 10.2.X.2
# кто нас долбит прямо сейчас (все атаки идут с 10.2.X.1 — по IP не понять кто):
tcpdump -i any -A dst port <порт_сервиса> | head -100
```

## Vulnbox: iptables (Ubuntu server = nftables-бэкенд)

```bash
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp -s <ip_kali> --dport 22 -j ACCEPT   # только точные IP!
iptables -A INPUT -p tcp --dport 22 -j DROP
iptables -A INPUT -p tcp --dport <неиспользуемый_порт> -j DROP
iptables -nL --line-numbers                        # посмотреть
iptables -D INPUT <номер>                          # удалить правило (откат)
apt install -y iptables-persistent && netfilter-persistent save   # пережить ребут
# НИКОГДА: iptables -P INPUT DROP  (без нужды) и бан 10.2.X.1 / 10.10.10.10
```

## Kali: атака

```bash
python3 forcad/forcad.py teams                   # цели
python3 forcad/forcad.py attack-data | head      # зацепки
python3 sploits/my_sploit.py 10.2.Y.2            # одиночный прогон (печатает флаги)
python3 sploits/my_sploit.py 10.2.Y.2 | python3 forcad/thrower.py   # сразу в жюри

# локальный полигон: сервис из исходников на своей машине
cd services/<имя> && docker compose up -d && cd -
python3 sploits/my_sploit.py 127.0.0.1
```

## Ферма (капитан)

```bash
# 1. config: repos/S4DFarm/server/app/config.py
#    'SYSTEM_PROTOCOL': 'forcad_http',
#    'SYSTEM_URL': 'http://10.10.10.10/flags',
#    'TEAM_TOKEN': '<токен>',
#    'FLAG_FORMAT': r'[A-Z0-9]{31}=',
#    'TEAMS': <python3 farm/gen_teams.py>,
#    'SERVER_PASSWORD': '<свой пароль фермы>',
# 2. наш протокол:
cp farm/forcad_http.py repos/S4DFarm/server/app/protocols/
# 3. запуск (docker ставится так: apt install -y docker.io docker-compose-v2):
cd repos/S4DFarm && docker compose up --build -d     # UI на :5137
```

## neo (раздача сплойтов по Kali команды)

```bash
# сервер (капитан, docker):
cd tools/neo_server_2.4.2
# в configs/server/config.yml: farm.url = http://<ip_капитана>:5137,
#   farm.password = <SERVER_PASSWORD фермы>, grpc_auth_key = <общий ключ>
docker compose up -d server

# клиенты (каждая Kali amd64, без docker — нужен только python3+requests):
tar xzf tools/neo_client_2.4.2_linux_amd64.tar.gz
#   client_config.yml: host: <ip_капитана>:5005, grpc_auth_key: <тот же>
./neo run                                          # начать атаковать свою долю команд
./neo add my_sploit.py --id my_sploit -i 2m -t 30s # залить/обновить сплойт всем
./neo tail my_sploit                               # логи прогонов
./neo update my_sploit -i 90s                      # поменять интервал
./neo disable my_sploit                            # выключить сплойт
```

## Прокси (если нужен внешний интернет)

```bash
source /etc/profile.d/ctf-proxy.sh        # после setup_kali.sh
curl -s http://10.10.10.10:8080/cert -o ctf-proxy.crt
# браузер: поставить сертификат по инструкции на :8080
```

## Статусы на борде (чекер)

| Код | Статус | Что значит |
|---|---|---|
| 101 | UP | всё ок |
| 102 | CORRUPT | флаг лежит, но данные вокруг изменились/сломаны |
| 103 | MUMBLE | сервис отвечает не по сценарию |
| 104 | DOWN | не отвечает / падает |
| 110 | CHECK_FAILED | сам чекер упал (обычно не ваша вина, но редко) |

## Чекер руками (если дают чекеры или для локального полигона)

```bash
./checker.py check <ip>
./checker.py put <ip> <flag_id> <flag> <vuln>   # 101=OK, 102/103/104/110 — плохо
./checker.py get <ip> <flag_id> <flag> <vuln>
```

## Формат флага

`[A-Z0-9]{31}=` — 31 символ из A-Z/0-9 + `=`. Первая буква = первая буква
имени сервиса. Окно жизни: 10 минут (5 раундов × 2 мин).
