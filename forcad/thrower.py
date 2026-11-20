#!/usr/bin/env python3
"""
thrower — ручная/автоматическая сдача флагов в ForcAD.

Читает флаги из stdin (по одному в строке или просто текстом — флаги
выковыриваются regex'ом), помнит уже сданные в state-файле, чтобы не
тратить лимиты на повторы, и пачками по <=100 отправляет в жюри.

Использование:
    echo "AAAA...=" | python3 thrower.py
    cat sploit_out.txt | python3 thrower.py
    python3 thrower.py flags.txt

    python3 thrower.py --clear-state   # забыть всё, что сдавали

Ответы жюри (из кода ForcAD):
    Flag accepted! Earned N flag points!
    Flag is invalid or too old.   / Flag is too old
    Flag is your own
    Flag already stolen
    Game is not available.            -> игру ещё не начали, повторить позже
    Cannot submit flags while service is down  (если включён volga_attacks_mode)

ВНИМАНИЕ: если флаги уже сдаёт ферма (S4DFarm/neo) — thrower параллельно
не запускайте, будете дублить сдачи и жечь лимиты. Либо ферма, либо thrower.
"""

import argparse
import json
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from forcad import extract_flags, submit_flags, summarize  # noqa: E402

DEFAULT_STATE = os.path.expanduser(os.environ.get(
    "THROWER_STATE", "~/.thrower_state.json"))

# Эти ответы помечаем в state: повторно слать смысла нет.
# 'Game is not available' и 'service is down' НЕ помечаем — надо повторить.
DONE_MARKERS = (
    "accepted",
    "invalid",
    "too old",
    "your own",
    "already stolen",
)


def load_state(path):
    try:
        with open(path) as f:
            return set(json.load(f))
    except (OSError, ValueError):
        return set()


def save_state(path, done):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(sorted(done), f)
    os.replace(tmp, path)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file", nargs="?", default="-",
                    help="файл с флагами (по умолчанию stdin)")
    ap.add_argument("--state", default=DEFAULT_STATE,
                    help=f"state-файл (по умолчанию {DEFAULT_STATE})")
    ap.add_argument("--clear-state", action="store_true",
                    help="забыть историю сданных флагов")
    args = ap.parse_args()

    if args.clear_state:
        save_state(args.state, set())
        print("[thrower] state очищен")
        return

    raw = sys.stdin.read() if args.file == "-" else open(args.file).read()
    flags = extract_flags(raw)
    if not flags:
        print("[thrower] флагов не найдено")
        return

    done = load_state(args.state)
    fresh, seen = [], []
    for f in flags:
        (seen if f in done else fresh).append(f)

    if seen:
        print(f"[thrower] пропускаю {len(seen)} уже обработанных ранее")
    if not fresh:
        print("[thrower] новых флагов нет")
        return

    print(f"[thrower] сдаю {len(fresh)} флагов в жюри...")
    results = submit_flags(fresh, verbose=False)
    if not results:
        print("[thrower] жюри ничего не ответило (ошибка выше?)")
        return

    accepted = 0
    newly_done = set(seen)
    for item in results:
        msg = item["msg"]
        print(f"  {item['flag']}  ->  {msg}")
        accepted += "accepted" in msg.lower()
        if any(m in msg.lower() for m in DONE_MARKERS):
            newly_done.add(item["flag"])

    ok, bad, points = summarize(results)
    save_state(args.state, newly_done)
    print(f"[thrower] ИТОГО: принято {accepted}, отвергнуто {bad}, "
          f"заработано ~{points:.0f} очков")


if __name__ == "__main__":
    main()
