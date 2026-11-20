#!/usr/bin/env python3
"""
Генерирует словарь TEAMS для config.py фермы (S4DFarm) из API жюри.

Использование:
    python3 gen_teams.py > teams_snippet.txt
    # потом руками вставить содержимое в repos/S4DFarm/server/app/config.py
    # вместо дефолтного 'TEAMS': {...}

Неактивные команды пропускаются — их не атакуем.
Адрес жюри берётся из переменной GAME_URL (по умолчанию http://10.10.10.10).
"""

import json
import os
import urllib.request

GAME_URL = os.environ.get("GAME_URL", "http://10.10.10.10").rstrip("/")

try:
    data = json.load(urllib.request.urlopen(f"{GAME_URL}/api/client/teams/",
                                           timeout=10))
except Exception as e:
    raise SystemExit(f"Не удалось получить список команд: {e}")

print("TEAMS = {")
for t in data:
    if not t.get("active", True):
        continue
    print(f"    {t['name']!r}: {t['ip']!r},")
print("}")
