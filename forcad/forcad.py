#!/usr/bin/env python3
"""
Клиент API ForcAD (InnoCTF Junior final).

Настройка через переменные окружения:
    GAME_URL    — адрес жюри, по умолчанию http://10.10.10.10
    TEAM_TOKEN  — токен команды из письма оргов (обязателен для сдачи флагов)
    FLAG_RE     — regex флага, по умолчанию формат ForcAD [A-Z0-9]{31}=

Проверено по коду ForcAD (актуальная версия):
  * GET  /api/client/teams/        — список команд и их IP
  * GET  /api/client/tasks/        — список сервисов
  * GET  /api/client/config/       — round_time, flag_lifetime и пр.
  * GET  /api/client/attack_data/  — публичные flag ids {сервис: {ip_команды: [данные]}}
  * PUT  /flags                    — сдача флагов, заголовок X-Team-Token,
                                     JSON-массив строк, максимум 100 штук за запрос.
                                     Лимит nginx: 2 запроса/сек на токен, 10 соединений с IP.
"""

import os
import re
import time
import requests

GAME_URL = os.environ.get("GAME_URL", "http://10.10.10.10").rstrip("/")
TEAM_TOKEN = os.environ.get("TEAM_TOKEN", "")
FLAG_RE = re.compile(os.environ.get("FLAG_RE", r"[A-Z0-9]{31}="))

TIMEOUT = 10
PUT_PAUSE = 0.6  # держимся ниже лимита 2 запроса/сек на токен
CHUNK = 100      # максимум флагов в одном запросе (лимит ForcAD)


def require_token():
    if not TEAM_TOKEN:
        raise SystemExit(
            "TEAM_TOKEN не задан. Экспортируйте: export TEAM_TOKEN=<ваш токен из письма>"
        )


def _get(path: str):
    r = requests.get(f"{GAME_URL}{path}", timeout=TIMEOUT)
    r.raise_for_status()
    return r.json()


def get_teams():
    """[{id, name, ip, highlighted, active}, ...]"""
    return _get("/api/client/teams/")


def get_active_teams():
    """Только активные команды: [{name, ip}, ...] — цели для сплойтов."""
    return [
        {"name": t["name"], "ip": t["ip"]}
        for t in get_teams()
        if t.get("active", True)
    ]


def get_tasks():
    return _get("/api/client/tasks/")


def get_config():
    """Конфиг игры: round_time, flag_lifetime, game_hardness, start_time..."""
    return _get("/api/client/config/")


def get_attack_data():
    """
    {имя_сервиса: {ip_команды: [public_flag_data, ...]}}
    Работает только для сервисов с чекером pfr, иначе null.
    """
    data = _get("/api/client/attack_data/")
    return data or {}


def flag_ids_for(service: str, host: str):
    """Публичные flag ids конкретного сервиса на конкретной команде."""
    return (get_attack_data().get(service) or {}).get(host, [])


def extract_flags(text: str):
    """Выковыривает флаги из любого текста/HTML/JSON-ответа."""
    return FLAG_RE.findall(text or "")


def submit_flags(flags, verbose=True):
    """
    Сдаёт флаги в жюри. Возвращает список ответов
    [{"flag": ..., "msg": "[FLAG] Flag accepted! Earned N flag points!"}, ...].

    Дубликаты внутри одного вызова убираются. Пустой список — сразу [].
    """
    require_token()
    if isinstance(flags, str):
        flags = [flags]
    flags = list(dict.fromkeys(f.strip() for f in flags if f and f.strip()))
    if not flags:
        return []

    results = []
    for i in range(0, len(flags), CHUNK):
        chunk = flags[i:i + CHUNK]
        r = requests.put(
            f"{GAME_URL}/flags",
            headers={"X-Team-Token": TEAM_TOKEN},
            json=chunk,
            timeout=TIMEOUT,
        )
        r.raise_for_status()
        results.extend(r.json())
        if verbose:
            for item in results[-len(chunk):]:
                print(f"[thrower] {item['flag']} -> {item['msg']}")
        if i + CHUNK < len(flags):
            time.sleep(PUT_PAUSE)
    return results


def summarize(results):
    """Краткая статистика по ответам жюри."""
    ok = sum(1 for r in results if "accepted" in r["msg"].lower())
    points = 0
    for r in results:
        m = re.search(r"Earned ([\d.]+)", r["msg"])
        if m:
            points += float(m.group(1))
    return ok, len(results) - ok, points


if __name__ == "__main__":
    import json
    import sys

    cmd = sys.argv[1] if len(sys.argv) > 1 else "config"
    if cmd == "config":
        print(json.dumps(get_config(), indent=2, default=str))
    elif cmd == "teams":
        for t in get_teams():
            mark = "" if t.get("active", True) else "  [неактивна]"
            print(f"{t['ip']:>14}  {t['name']}{mark}")
    elif cmd == "tasks":
        for t in get_tasks():
            print(f"{t['name']}: {t}")
    elif cmd == "attack-data":
        print(json.dumps(get_attack_data(), indent=2))
    else:
        print(__doc__)
