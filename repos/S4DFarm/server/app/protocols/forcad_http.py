"""
Протокол сдачи флагов для S4DFarm → ForcAD (HTTP-приёмник).

Кладётся в:  repos/S4DFarm/server/app/protocols/forcad_http.py
             (рядом с ructf_http.py и т.п.)

И в server/app/config.py меняется:
    'SYSTEM_PROTOCOL': 'forcad_http',
    'SYSTEM_URL': 'http://10.10.10.10/flags',
    'TEAM_TOKEN': '<ваш team token из письма>',
    'FLAG_FORMAT': r'[A-Z0-9]{31}=',

Проверено по коду приёмника ForcAD (backend/services/http_receiver/views.py):
    PUT /flags, заголовок X-Team-Token, тело — JSON-массив строк (<=100).
    Ответ: [{"msg": "[FLAG] ...", "flag": ...}, ...]
    Сообщения:
      Flag accepted! Earned N flag points!
      Flag is invalid or too old. / Flag is too old
      Flag is your own
      Flag already stolen
      Game is not available.                  (игра ещё не началась)
      Cannot submit flags while service is down (volga_attacks_mode)

Для DestructiveFarm импорты другие ('from server.models import ...'),
для S4DFarm — как ниже (см. их ructf_http.py).
"""

import logging

import requests

from models import FlagStatus, SubmitResult

logger = logging.getLogger(__name__)

TIMEOUT = 10
CHUNK = 100  # ForcAD: максимум 100 флагов в одном запросе

RESPONSES = {
    FlagStatus.ACCEPTED: ['accepted'],
    FlagStatus.REJECTED: [
        'invalid',
        'too old',
        'your own',
        'already stolen',
        'team_not_found',
    ],
    # всё, что стоит повторить позже
    FlagStatus.QUEUED: [
        'game not started',
        'not available',
        'service is down',
        'no such flag',
    ],
}


def submit_flags(flags, config):
    url = config['SYSTEM_URL']
    token = config['TEAM_TOKEN']
    all_flags = [item.flag for item in flags]

    for i in range(0, len(all_flags), CHUNK):
        chunk = all_flags[i:i + CHUNK]
        try:
            r = requests.put(
                url,
                headers={'X-Team-Token': token},
                json=chunk,
                timeout=TIMEOUT,
            )
            r.raise_for_status()
            responses = r.json()
        except Exception as e:
            logger.error('ForcAD submit failed: %r', e)
            # фермa повторит партию на следующем тике
            for item in flags[i:i + CHUNK]:
                yield SubmitResult(item.flag, FlagStatus.QUEUED, repr(e))
            continue

        unknown = set()
        for item, resp in zip(flags[i:i + CHUNK], responses):
            msg = str(resp.get('msg', '')).strip()
            msg = msg.replace('[{}] '.format(item.flag), '')
            low = msg.lower()

            found = FlagStatus.QUEUED
            for status, substrings in RESPONSES.items():
                if any(s in low for s in substrings):
                    found = status
                    break
            else:
                if msg not in unknown:
                    unknown.add(msg)
                    logger.warning('Unknown ForcAD response: %s', msg)

            yield SubmitResult(item.flag, found, msg)
