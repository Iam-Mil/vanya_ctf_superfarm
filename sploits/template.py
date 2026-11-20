#!/usr/bin/env python3
"""
Шаблон сплойта под ферму (S4DFarm / neo) и thrower.

Контракт фермы: сплойт запускается как `./sploit.py <ip_команды>`
(единственный аргумент — IP), флаги печатаем в STDOUT построчно —
их заберёт ферма или `python3 thrower.py`.

Флаги печатаём с flush=True: ферма читает вывод построчно в реальном времени.

Две стратегии:
  A) PFR-сервисы (у InnoCTF обычно такие): публичные flag ids лежат
     в attack_data — берём готовые зацепки, не тратим раунды на перебор.
  B) Слепой сервис: сами регистрируемся и вытаскиваем флаги
     (как divnik в 2020 — полный перебор юзеров/курсов).

Локальный тест перед выносом на чужие боксы:
    python3 sploit.py 127.0.0.1     # если сервис поднят локально в docker
"""

import os
import sys

sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             "..", "forcad"))
import requests  # noqa: E402

from forcad import extract_flags, flag_ids_for  # noqa: E402

# ------------------------- настройки под сервис ---------------------------
SERVICE = "service_name"   # имя сервиса, как оно называется в attack_data
PORT = 8080                # порт сервиса на вулнбоксе
TIMEOUT = 10
# ---------------------------------------------------------------------------


def exploit(host: str, flag_ids):
    """
    Здесь вся атака. Возвращает список флагов.
    """
    base = f"http://{host}:{PORT}"
    s = requests.Session()
    s.timeout = TIMEOUT

    # ===== ПРИМЕР A: используем flag ids из attack_data ==================
    # Чекер explorers-типа кладёт флаг в объект с известным публичным id
    # (route_id / post_N / username), а приватно держит креды.
    # if not flag_ids:
    #     return []
    # flags = []
    # for public_id in flag_ids:
    #     r = s.get(f"{base}/api/objects/{public_id}")   # уязвимая ручка
    #     flags += extract_flags(r.text)
    # return flags

    # ===== ПРИМЕР B: слепой сервис, сами всё находим =====================
    # u, p = rnd_string(10) + "_user", "Passw0rd!"
    # s.post(f"{base}/api/register", json={"username": u, "password": p})
    # token = s.post(f"{base}/api/login", json={"username": u, "password": p}).json()["token"]
    # r = s.get(f"{base}/api/objects", headers={"Authorization": f"Bearer {token}"})
    # return extract_flags(r.text)

    # Пока шаблон ничего не делает:
    print(f"[*] host={host} flag_ids={flag_ids!r} — замените exploit()",
          file=sys.stderr)
    return []


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <ip_команды>", file=sys.stderr)
        sys.exit(1)
    host = sys.argv[1]

    # Зацепки из attack_data (для pfr-сервисов). Не падаем, если эндпоинт
    # недоступен или сервис не pfr — тогда атакуем вслепую.
    try:
        ids = flag_ids_for(SERVICE, host)
    except Exception as e:
        print(f"[!] attack_data недоступен ({e}), атакую вслепую",
              file=sys.stderr)
        ids = []

    try:
        flags = exploit(host, ids)
    except requests.RequestException as e:
        print(f"[!] сетевая ошибка: {e}", file=sys.stderr)
        sys.exit(1)

    for flag in flags:
        print(flag, flush=True)


if __name__ == "__main__":
    main()
