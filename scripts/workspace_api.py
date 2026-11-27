#!/usr/bin/env python3
"""Offline agent access to Saturn's local workspace.

The running shell is the preferred writer: use `saturn data ...` instead. This
helper is for agents and scripts running without the shell. It takes an
exclusive lock, validates the schema, writes atomically and keeps a backup.
"""
import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import initialize  # noqa: E402
from tags import from_title as tags_from_title  # noqa: E402
from settings import normalise as normalise_settings  # noqa: E402

DATA_HOME = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share')
DATA_DIR = DATA_HOME / 'saturn'
WORKSPACE = DATA_DIR / 'workspace.json'
LOCK = DATA_DIR / '.workspace.lock'
BACKUPS = DATA_HOME / 'omaowl-backups'
DAY = re.compile(r'^\d{4}-\d{2}-\d{2}$')
WRITE_COMMANDS = {'add-task', 'complete-task', 'archive-task', 'restore-task', 'set-due', 'set-tags',
                  'add-note', 'update-note', 'pin-note', 'archive-note', 'restore-note', 'settings-set'}


def output(payload):
    print(json.dumps(payload, ensure_ascii=False))


def fail(message, code=2):
    output({'ok': False, 'error': message})
    raise SystemExit(code)


@contextmanager
def locked(exclusive=False):
    DATA_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(LOCK, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def shell_live():
    try:
        result = subprocess.run(['omarchy-shell', 'saturn', 'status'],
                                capture_output=True, timeout=1.5)
        return result.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def read_state():
    if not WORKSPACE.exists():
        initialize.initialize(DATA_DIR, DATA_HOME / 'omaowl', BACKUPS)
    try:
        raw = WORKSPACE.read_text()
        return initialize.migrate(json.loads(raw))
    except (ValueError, json.JSONDecodeError, OSError) as error:
        fail(f'Saved workspace could not be read: {error}. Original file preserved.')


def write_state(state, command):
    state.setdefault('sync', {})
    audit = state['sync'].setdefault('audit', [])
    audit.append({'at': int(__import__('time').time() * 1000), 'command': command[:60]})
    del audit[:-200]
    raw = json.dumps(state, indent=2, ensure_ascii=False) + '\n'
    backup = BACKUPS / f'agent-{date.today().isoformat()}-{os.getpid()}'
    backup.mkdir(parents=True, exist_ok=True, mode=0o700)
    if WORKSPACE.exists():
        (backup / 'workspace.json').write_bytes(WORKSPACE.read_bytes())
    fd, temporary = tempfile.mkstemp(dir=DATA_DIR, prefix='.workspace-', suffix='.json')
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(raw)
        os.chmod(temporary, 0o600)
        os.replace(temporary, WORKSPACE)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def valid_day(value):
    return isinstance(value, str) and bool(DAY.match(value))


def parse_due(text, today=None):
    value = str(text or '').strip()
    base = date.fromisoformat(today) if valid_day(today) else date.today()
    if value == 'today':
        return base.isoformat()
    if value == 'tomorrow':
        return (base + timedelta(days=1)).isoformat()
    if valid_day(value):
        return value
    return None


def clean_tags(value):
    raw = value if isinstance(value, list) else re.split(r'[,;#\s]+', str(value or ''))
    seen, tags = set(), []
    for item in raw:
        tag = str(item or '').strip().lstrip('#').lower()[:32]
        if tag and tag not in seen and len(tags) < 12:
            seen.add(tag)
            tags.append(tag)
    return tags


def find(items, item_id):
    return next((item for item in items if item.get('id') == item_id), None)


def search(state, query, limit=80):
    results = []
    for note in state.get('notesV2', []):
        haystack = ' '.join([str(note.get('title', '')), str(note.get('body', '')),
                             str(note.get('date') or ''), ' '.join(note.get('tags', []))]).lower()
        if all(term in haystack for term in str(query or '').lower().split()):
            results.append({'id': note['id'], 'title': note.get('title', ''),
                            'source': 'library', 'date': note.get('date'),
                            'archived': note.get('archived', False), 'pinned': note.get('pinned', False)})
    for day, body in state.get('notes', {}).items():
        if str(query or '').lower() in (day + ' ' + str(body)).lower():
            results.append({'id': 'daily:' + day, 'title': 'Daily note · ' + day,
                            'source': 'daily', 'date': day, 'archived': False, 'pinned': False})
    return results[:min(max(int(limit), 1), 100)]


def main(argv):
    if not argv:
        fail('A command is required. Try: get, tasks-list, add-task, notes-list, add-note, search')
    command = argv[0]
    args = argv[1:]
    if command not in WRITE_COMMANDS and command not in {'get', 'status', 'sync-status', 'settings', 'tasks-list', 'notes-list', 'search'}:
        fail('Unknown data command')
    if command in WRITE_COMMANDS and shell_live():
        fail('Saturn shell is running; use `saturn data ...` so the live workspace stays in sync', 3)
    with locked(exclusive=command in WRITE_COMMANDS):
        state = read_state()
        if command == 'get':
            output(state)
        elif command == 'status':
            output({'ready': True, 'schema': state.get('version'), 'tasks': len(state.get('tasks', [])),
                    'notes': len(state.get('notesV2', [])) + len(state.get('notes', {}))})
        elif command == 'sync-status':
            output(state.get('sync', {}))
        elif command == 'settings':
            output(state.get('settings', {}))
        elif command == 'settings-set':
            try:
                raw = json.loads(args[0] if args else '{}')
            except (ValueError, TypeError):
                fail('Settings must be a JSON object')
            if not isinstance(raw, dict):
                fail('Settings must be a JSON object')
            state['settings'] = normalise_settings(raw)
            write_state(state, command)
            output({'ok': True, 'settings': state['settings']})
        elif command == 'tasks-list':
            output(state.get('tasks', []))
        elif command == 'notes-list':
            output(state.get('notesV2', []))
        elif command == 'search':
            output(search(state, args[0] if args else '', args[1] if len(args) > 1 else 80))
        elif command == 'add-task':
            if not args or not args[0].strip():
                fail('A task title is required')
            title = args[0].strip()[:500]
            due = parse_due(args[1] if len(args) > 1 else '', state.get('today'))
            match = re.search(r'\s+(today|tomorrow|\d{4}-\d{2}-\d{2})\s*$', title, re.I)
            if match and not due:
                due = parse_due(match.group(1))
                title = title[:match.start()].strip()
            stamp = int(__import__('time').time() * 1000)
            task = {'id': __import__('uuid').uuid4().hex[:14], 'title': title, 'done': False,
                    'completedAt': 0, 'due': due, 'createdAt': stamp, 'updatedAt': stamp,
                    'archived': False, 'archivedAt': 0, 'body': '', 'tags': tags_from_title(title),
                    'source': 'local', 'externalId': None}
            state.setdefault('tasks', []).insert(0, task)
            write_state(state, command)
            output({'ok': True, 'id': task['id'], 'due': due})
        elif command in {'complete-task', 'archive-task', 'restore-task', 'set-due', 'set-tags', 'pin-note', 'archive-note', 'restore-note'}:
            if not args:
                fail('An id is required')
            collection = state.get('tasks', []) if command in {'complete-task', 'archive-task', 'restore-task', 'set-due', 'set-tags'} else state.get('notesV2', [])
            item = find(collection, args[0])
            if not item:
                fail('No such id')
            stamp = int(__import__('time').time() * 1000)
            if command == 'complete-task':
                item['done'] = not item.get('done', False)
                item['completedAt'] = stamp if item['done'] else 0
            elif command in {'archive-task', 'archive-note'}:
                item['archived'] = True
                if 'archivedAt' in item:
                    item['archivedAt'] = stamp
            elif command in {'restore-task', 'restore-note'}:
                item['archived'] = False
                if 'archivedAt' in item:
                    item['archivedAt'] = 0
            elif command == 'set-due':
                item['due'] = parse_due(args[1] if len(args) > 1 else '')
            elif command == 'set-tags':
                item['tags'] = clean_tags(args[1] if len(args) > 1 else '')
            elif command == 'pin-note':
                item['pinned'] = not item.get('pinned', False)
            item['updatedAt'] = stamp
            write_state(state, command)
            output({'ok': True, 'id': args[0]})
        elif command in {'add-note', 'update-note'}:
            if command == 'add-note' and (not args or not args[0].strip()):
                fail('A note title is required')
            stamp = int(__import__('time').time() * 1000)
            if command == 'add-note':
                note = {'id': __import__('uuid').uuid4().hex[:14], 'title': args[0].strip()[:200],
                        'body': (args[1] if len(args) > 1 else '')[:20000],
                        'tags': clean_tags(args[2] if len(args) > 2 else []),
                        'date': None, 'createdAt': stamp, 'updatedAt': stamp,
                        'archived': False, 'pinned': False}
                if len(args) > 3 and valid_day(args[3]):
                    note['date'] = args[3]
                state.setdefault('notesV2', []).insert(0, note)
                write_state(state, command)
                output({'ok': True, 'id': note['id']})
            else:
                note = find(state.get('notesV2', []), args[0] if args else '')
                if not note:
                    fail('No such note id')
                note['title'] = (args[1] if len(args) > 1 else note['title']).strip()[:200]
                note['body'] = (args[2] if len(args) > 2 else note.get('body', ''))[:20000]
                if len(args) > 3:
                    note['tags'] = clean_tags(args[3])
                note['updatedAt'] = stamp
                write_state(state, command)
                output({'ok': True, 'id': note['id']})


if __name__ == '__main__':
    main(sys.argv[1:])
