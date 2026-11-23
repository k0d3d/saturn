#!/usr/bin/env python3
"""Local-first calendar sync between Saturn, Google Calendar and CalDAV."""
import json
import os
import subprocess
import sys
import tempfile
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import initialize  # noqa: E402

DATA_HOME = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share')
WORKSPACE = DATA_HOME / 'saturn' / 'workspace.json'
HELPER = ROOT / 'providers.py'
ACTION_KEYS = {'create', 'update', 'delete'}


def emit(value):
    print(json.dumps(value, ensure_ascii=False))


def load_state():
    if not WORKSPACE.exists():
        initialize.initialize(WORKSPACE.parent, DATA_HOME / 'omaowl', DATA_HOME / 'omaowl-backups')
    try:
        return initialize.migrate(json.loads(WORKSPACE.read_text()))
    except (ValueError, json.JSONDecodeError, OSError) as error:
        raise RuntimeError(f'Saved workspace could not be read: {error}. Original file preserved.')


def save_state(state):
    raw = json.dumps(state, indent=2, ensure_ascii=False) + '\n'
    fd, temporary = tempfile.mkstemp(dir=WORKSPACE.parent, prefix='.calendar-', suffix='.json')
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(raw)
        os.chmod(temporary, 0o600)
        os.replace(temporary, WORKSPACE)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def provider_call(provider, action, extra=None):
    payload = dict({'provider': provider, 'action': action}, **(extra or {}))
    result = subprocess.run([sys.executable, str(HELPER)], input=json.dumps(payload) + '\n',
                            text=True, capture_output=True, timeout=40)
    if result.returncode != 0:
        raise RuntimeError('Calendar helper failed. Check Connections.')
    reply = json.loads(result.stdout.splitlines()[-1] if result.stdout else '{}')
    if not reply.get('ok'):
        raise RuntimeError(reply.get('error', 'Calendar request failed.'))
    return reply


def millis(value):
    if isinstance(value, (int, float)):
        return int(value)
    parsed = datetime.fromisoformat(str(value).replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp() * 1000)


def normalize(provider, feed):
    rows = []
    if provider == 'google-calendar':
        for event in feed.get('events', []):
            rows.append({'title': event.get('title', ''), 'start': millis(event.get('start_ms', 0)),
                         'end': millis(event.get('end_ms', 0)), 'all_day': bool(event.get('all_day')),
                         'externalId': str(event.get('start_ms', 0)) + ':' + str(event.get('title', '')),
                         'source': 'google'})
    else:
        for event in feed.get('events', []):
            rows.append({'title': event.get('title', ''), 'start': millis(event.get('start')),
                         'end': millis(event.get('end')), 'all_day': bool(event.get('all_day')),
                         'externalId': event.get('uid', ''), 'source': 'caldav'})
    return rows


def remote_payload(event):
    return {'title': event.get('title', ''),
            'start': datetime.fromtimestamp(event['start'] / 1000, tz=timezone.utc).isoformat(),
            'end': datetime.fromtimestamp(event.get('end', event['start']) / 1000, tz=timezone.utc).isoformat(),
            'externalId': event.get('externalId', '')}


def same_event(local, incoming):
    return (local.get('title') == incoming.get('title') and local.get('start') == incoming.get('start')
            and local.get('end') == incoming.get('end'))


def note_conflict(state, item_id, field):
    conflicts = state.setdefault('sync', {}).setdefault('conflicts', [])
    conflicts.append({'at': int(time.time() * 1000), 'id': item_id, 'field': field,
                      'local': 'workspace', 'vault': 'calendar'})
    del conflicts[:-200]


def main(argv):
    mode = argv[0] if argv else 'sync'
    if mode not in {'sync', 'status'}:
        emit({'ok': False, 'error': 'Use sync or status'})
        raise SystemExit(2)
    state = load_state()
    source = state.get('calendarSource', 'omacal')
    sync = state.setdefault('sync', {}).setdefault('calendar', {})
    if mode == 'status':
        emit({'ok': True, 'source': source, 'events': len(state.get('events', [])),
              'lastSync': sync.get('lastSync'), 'errors': sync.get('errors', [])[-3:]})
        return
    if source not in {'google', 'caldav'}:
        emit({'ok': True, 'source': source, 'pulled': 0, 'pushed': 0, 'note': 'No remote calendar configured'})
        return
    provider = 'google-calendar' if source == 'google' else 'caldav'
    remote_key = 'google' if source == 'google' else 'caldav'
    pulled = pushed = 0
    try:
        feed = provider_call(provider, 'sync')
        incoming = normalize(provider, feed)
        index = {(e.get('source'), e.get('externalId')): e for e in incoming}
        events = state.setdefault('events', [])
        base = sync.setdefault('base', {})
        for row in incoming:
            key = (row['source'], row['externalId'])
            local = next((e for e in events if e.get('source') == row['source']
                          and e.get('externalId') == row['externalId']), None)
            if not local:
                local = {'id': uuid.uuid4().hex[:14], 'title': row['title'], 'start': row['start'],
                         'end': row['end'], 'all_day': row['all_day'], 'source': row['source'],
                         'externalId': row['externalId'], 'archived': False,
                         'createdAt': int(time.time() * 1000), 'updatedAt': int(time.time() * 1000)}
                events.insert(0, local)
                pulled += 1
            elif not same_event(local, row):
                previous = base.get(local['id'], 0)
                if local.get('updatedAt', 0) > previous:
                    note_conflict(state, local['id'], 'event')
                else:
                    local.update({'title': row['title'], 'start': row['start'], 'end': row['end'],
                                  'all_day': row['all_day'], 'updatedAt': int(time.time() * 1000)})
                    pulled += 1
            base[local['id']] = local.get('updatedAt', 0)
        for event in list(events):
            if event.get('source') not in (remote_key, 'local', None, ''):
                continue
            if event.get('archived') and event.get('externalId'):
                provider_call(provider, 'delete', remote_payload(event))
                event['externalId'] = None
                pushed += 1
            elif not event.get('archived') and not event.get('externalId'):
                result = provider_call(provider, 'create', remote_payload(event))
                event['externalId'] = result.get('externalId', '')
                event['source'] = remote_key
                event['updatedAt'] = int(time.time() * 1000)
                pushed += 1
        sync['lastSync'] = int(time.time() * 1000)
        sync['errors'] = []
        save_state(state)
    except (RuntimeError, ValueError, subprocess.TimeoutExpired, OSError) as error:
        errors = sync.setdefault('errors', [])
        errors.append({'at': int(time.time() * 1000), 'error': str(error)[:300]})
        del errors[:-20]
        save_state(state)
    emit({'ok': True, 'source': source, 'pulled': pulled, 'pushed': pushed,
          'events': len(state.get('events', [])), 'conflicts': len(state.get('sync', {}).get('conflicts', []))})


if __name__ == '__main__':
    main(sys.argv[1:])
