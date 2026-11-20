# DOCKER.md — установка docker во всех сценариях + лечение ошибок

Docker — самая капризная часть всей подготовки: на Kali/Ubuntu/Debian он
ставится по-разному, а compose v2 прячется под разными именами пакетов.
Здесь все рабочие пути + разбор типовых ошибок.

---

## 0. Правило номер один

**Docker ставится ДО игры, дома, с интернетом.** На игре сеть может быть
закрыта — там docker не нужен, но и не ставится. Чек-лист вечера, на
каждой Kali:

```bash
sudo bash install.sh          # поставит всё, включая docker (сценарии ниже внутри)
docker info | head -3         # демон жив?
docker compose version        # compose v2 есть?
```

Образы на игру тянуть не надо — все уже в этом репозитории (`images/`):
на игре `sudo bash offline.sh` поднимет ферму без сети вообще.

## 1. Kali (проверенный путь — так ставили на нашей VM)

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose
sudo systemctl enable --now docker
docker info | head -3 && docker compose version
```

**Критичная деталь Kali:** compose v2 тут называется пакетом
`docker-compose` (в Ubuntu — `docker-compose-v2`). Поставишь его из
чужого репозитория — легко поймать старую **compose v1** (питонью,
`docker-compose` через дефис) — она **не подходит**: нужен именно
`docker compose` (через пробел, v2).

## 2. Ubuntu / Debian

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
```

## 3. Официальный способ (любой дистрибутив, нужен интернет)

```bash
curl -fsSL https://get.docker.com | sh
sudo systemctl enable --now docker
```

Скрипт сам определяет дистрибутив. Не нравится пайп в sh — руками:
ключи + репозиторий `download.docker.com` → `apt-get install docker-ce
docker-compose-plugin`.

## 4. Compose v2 не появился — бинарник руками

Скачать с `https://github.com/docker/compose/releases` (файл вида
`compose-linux-x86_64`) и положить как плагин:

```bash
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo cp compose-linux-x86_64 /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version
```

(без sudo — можно в `~/.docker/cli-plugins/docker-compose`)

## 5. Права: docker без sudo

```bash
sudo usermod -aG docker $USER
```

**Обязательно перелогиниться** — группа применяется только при новом
входе (или `newgrp docker` в текущей сессии). Проверка: `docker info`
без sudo.

## 6. Типовые ошибки: симптом → причина → лечение

| Симптом | Причина | Лечение |
|---|---|---|
| `Cannot connect to the Docker daemon at unix:///var/run/docker.sock` | демон не запущен | `sudo systemctl enable --now docker`; не помогло — `journalctl -u docker --no-pager \| tail -20` и читать |
| `permission denied ... /var/run/docker.sock` | не root и не в группе docker | `sudo ...` или `usermod -aG docker $USER` + **перелогин** (§5) |
| `docker: 'compose' is not a docker command` | нет compose v2 | пакет из §1/§2 (имя зависит от дистрибутива) или бинарник из §4 |
| стоит `docker-compose` (v1, python), а `docker compose` не работает | это старая v1 | v1 НЕ подходит; поставить v2 (§1/§4) |
| apt: `dependency conflicts` / `held broken packages` | конфликт версий/остатки старых пакетов | `sudo apt-get --fix-broken install`; `sudo apt-get remove -y docker docker-engine containerd runc` и повторить §1 |
| после установки всё равно старая версия | дубли в системе | `dpkg -l \| grep -i docker` — снести всё лишнее, поставить заново одним пакетом |
| демон падает на старте | несовместимые containerd/runc | смотреть `journalctl -u docker`; ставить согласованный `docker.io` из репо дистрибутива (§1/§2), не смешивать с docker-ce |
| в VM/WSL демон не стартует | выключен systemd (WSL) | WSL: `/etc/wsl.conf` → `[boot] systemd=true` + `wsl --shutdown`; в нормальных VM просто работает |
| `docker compose up` висит на `Pulling` | нет интернета / прокси не настроен | это СБОРКА: на игре не собирай, используй `sudo bash offline.sh` (образы в репо); для сборки дома — `export http_proxy=... https_proxy=...` |

## 7. Сценарий игры: apt есть, git есть, Docker Hub — не факт

Реальные условия завтра: apt и git доступны, а пул образов из Docker Hub —
под вопросом. Отсюда правила:

- **docker ставится apt'ом** (§1/§2) — это не требует Docker Hub;
- **образы НЕ тянуть из Docker Hub**: путь `docker compose up --build`
  на игре НЕ используем (он качает базовые образы + PyPI + npm);
- вместо него: **`sudo bash offline.sh`** — он ставит docker/compose через
  apt, если их нет, загружает все образы из `images/` (docker load) и
  поднимает ферму без сборки;
- python для сплойтов: `requests` на Kali есть из коробки; если вдруг нет —
  в `images/wheelhouse/` лежат колёса: `pip3 install --no-index
  --find-links images/wheelhouse requests` (без PyPI).

Проверить офлайн-готовность машины (без Docker Hub):

```bash
cat images/farm_stack.tar.gz.part-* | sudo docker load   # образы из репо
```

## 8. Проверка после установки — три команды

```bash
docker info | head -3                # 1. демон жив
docker compose version              # 2. compose v2
cat images/farm_stack.tar.gz.part-* | sudo docker load   # 3. офлайн-стек:
                                     # образы фермы загрузились из репо (без сети!)
```

Третья команда — сразу и проверка офлайн-готовности: если она прошла,
на игре у тебя всё поднимется без единого байта из интернета
(`sudo bash offline.sh`).
