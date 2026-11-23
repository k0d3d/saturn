#!/usr/bin/env python3
"""Bidirectional, local-first Markdown mirror for Saturn's workspace.

Vault files use a JSON front matter block between `---` lines. The workspace
stays authoritative: on a two-sided change the local record wins and the
conflict is logged, never silently dropped. No credentials are ever written.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import initialize  # noqa: E402

DATA_HOME = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share')
WORKSPACE = DATA_HOME / 'saturn' / 'workspace.json'
VAULT = Path(os.environ.get('SATURN_VAULT') or Path.home() / 'Documents' / 'saturn')
MAX_FILE = 200_000
SAFE_ID = re.compile(r'^[A-Za-z0-9_-]+$')
SAFE_DATE = re.compile(r'^\d{4}-\d{2}-\d{2}$')
KINDS = {'tasks', 'notes', 'daily', 'tombstones'}


def log(message):
    print(json.dumps({'ok': False, 'error': message}), flush=True)


def day_from(ms):
    if not isinstance(ms, (int, float)) or ms <= 0:
        return 'undated'
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).date().isoformat()


def slug(title, item_id):
    base = re.sub(r'[^a-z0-9]+', '-', str(title or '').lower()).strip('-')[:48] or 'note'
    return f'{base}-{item_id}'


def load_state():
    if not WORKSPACE.exists():
        initialize.initialize(WORKSPACE.parent, DATA_HOME / 'omaowl', DATA_HOME / 'omaowl-backups')
    try:
        return initialize.migrate(json.loads(WORKSPACE.read_text()))
    except (ValueError, json.JSONDecodeError, OSError) as error:
        raise RuntimeError(f'Saved workspace could not be read: {error}. Original file preserved.')


def save_state(state):
    raw = json.dumps(state, indent=2, ensure_ascii=False) + '\n'
    fd, temporary = tempfile.mkstemp(dir=WORKSPACE.parent, prefix='.workspace-', suffix='.json')
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(raw)
        os.chmod(temporary, 0o600)
        os.replace(temporary, WORKSPACE)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def render(meta, body):
    front = json.dumps(meta, ensure_ascii=False, sort_keys=True)
    return f'---\n{front}\n---\n{body.strip()}\n'[:MAX_FILE]


def parse(text):
    lines = text.splitlines()
    if len(lines) < 3 or lines[0].strip() != '---':
        return None
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == '---')
        meta = json.loads('\n'.join(lines[1:end]))
        body = '\n'.join(lines[end + 1:])
        return meta, body
    except (StopIteration, ValueError):
        return None


def scan():
    found = {}
    if not VAULT.exists():
        return found
    for kind in KINDS:
        folder = VAULT / kind
        if not folder.is_dir():
            continue
        for path in folder.glob('*.md'):
            try:
                if path.stat().st_size > MAX_FILE:
                    continue
                parsed = parse(path.read_text(errors='replace'))
                if parsed and isinstance(parsed[0], dict) and isinstance(parsed[0].get('id'), str):
                    found[parsed[0]['id']] = (path, parsed[0], parsed[1])
            except OSError:
                continue
    return found


def desired_files(state):
    result = {}
    for task in state.get('tasks', []):
        item_id = task.get('id', '')
        if not SAFE_ID.match(item_id):
            continue
        date = task.get('due') or day_from(task.get('createdAt'))
        if not SAFE_DATE.match(date):
            date = 'undated'
        meta = {'id': item_id, 'kind': 'task', 'title': task.get('title', ''), 'due': task.get('due'),
                'done': bool(task.get('done')), 'archived': bool(task.get('archived')),
                'createdAt': task.get('createdAt', 0), 'updatedAt': task.get('updatedAt', 0),
                'tags': task.get('tags', []), 'source': 'local', 'externalId': task.get('externalId')}
        result[f'tasks/{date}-{item_id}.md'] = render(meta, task.get('body') or '')
    for note in state.get('notesV2', []):
        item_id = note.get('id', '')
        if not SAFE_ID.match(item_id):
            continue
        date = note.get('date') or day_from(note.get('createdAt'))
        if not SAFE_DATE.match(date):
            date = 'undated'
        meta = {'id': item_id, 'kind': 'note', 'title': note.get('title', ''), 'date': note.get('date'),
                'pinned': bool(note.get('pinned')), 'archived': bool(note.get('archived')),
                'createdAt': note.get('createdAt', 0), 'updatedAt': note.get('updatedAt', 0),
                'tags': note.get('tags', [])}
        result[f'notes/{date}-{slug(note.get("title"), item_id)}.md'] = render(meta, note.get('body') or '')
    for day, body in state.get('notes', {}).items():
        if not SAFE_DATE.match(day):
            continue
        item_id = f'daily:{day}'
        meta = {'id': item_id, 'kind': 'daily', 'date': day, 'title': f'Daily note · {day}',
                'updatedAt': 0, 'tags': []}
        result[f'daily/{day}.md'] = render(meta, str(body))
    for tomb in state.get('sync', {}).get('tombstones', []):
        item_id = tomb.get('id', '') if isinstance(tomb, dict) else str(tomb)
        kind = tomb.get('kind', 'task') if isinstance(tomb, dict) else 'task'
        if SAFE_ID.match(item_id):
            result[f'tombstones/{kind}-{item_id}.md'] = render(
                {'id': item_id, 'kind': kind, 'deleted': True, 'at': tomb.get('at', 0)}, '')
    return result


def write_vault(state, files):
    changed = False
    for relative, content in files.items():
        path = VAULT / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() and path.read_text(errors='replace') == content:
            continue
        fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.saturn-', suffix='.md')
        try:
            with os.fdopen(fd, 'w') as stream:
                stream.write(content)
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        changed = True
    return changed


def apply_incoming(state, meta, body):
    item_id = meta['id']
    kind = meta.get('kind')
    updated = meta.get('updatedAt', 0) if isinstance(meta.get('updatedAt', 0), (int, float)) else 0
    sync = state.setdefault('sync', {})
    base = sync.setdefault('vault', {}).setdefault('base', {})
    previous = base.get(item_id, 0)
    if meta.get('deleted'):
        if kind == 'task':
            target = state.get('tasks', [])
        else:
            target = state.get('notesV2', [])
        item = next((i for i in target if i.get('id') == item_id), None)
        changed = False
        if item and not item.get('archived'):
            item['archived'] = True
            changed = True
        if not any(t.get('id') == item_id for t in sync.setdefault('tombstones', [])):
            sync['tombstones'].append({'id': item_id, 'kind': kind, 'at': updated})
            changed = True
        base[item_id] = updated
        return changed
    if kind == 'daily':
        day = meta.get('date', '')
        if not SAFE_DATE.match(day):
            return False
        local = state.setdefault('notes', {}).get(day, '')
        if body.strip() == local.strip():
            return False
        daily_base = sync.get('vault', {}).get('daily', {})
        last = daily_base.get(day) if isinstance(daily_base, dict) else None
        if last is None or local.strip() == str(last).strip():
            state['notes'][day] = body
        else:
            conflicts = sync.setdefault('conflicts', [])
            conflicts.append({'at': updated or 1, 'id': item_id, 'field': 'body',
                              'local': 'workspace', 'vault': 'markdown'})
            del conflicts[:-200]
            return False
        base[item_id] = updated
        return True
    if kind not in {'task', 'note'}:
        return False
    collection = state.setdefault('tasks' if kind == 'task' else 'notesV2', [])
    item = next((i for i in collection if i.get('id') == item_id), None)
    if not item:
        record = {'id': item_id, 'title': str(meta.get('title') or 'Untitled')[0:200],
                  'createdAt': updated, 'updatedAt': updated, 'archived': bool(meta.get('archived')),
                  'tags': meta.get('tags', []) if isinstance(meta.get('tags', []), list) else []}
        if kind == 'task':
            record.update({'done': bool(meta.get('done')), 'completedAt': 0,
                           'due': meta.get('due') if SAFE_DATE.match(str(meta.get('due') or '')) else None,
                           'body': body[:20000], 'createdAt': updated, 'updatedAt': updated,
                           'archivedAt': 0, 'source': 'local', 'externalId': None})
        else:
            record.update({'body': body[:20000], 'date': meta.get('date'),
                           'pinned': bool(meta.get('pinned'))})
        collection.insert(0, record)
        base[item_id] = updated
        return True
    local_updated = item.get('updatedAt', 0)
    if updated > local_updated:
        if local_updated > previous:
            conflicts = sync.setdefault('conflicts', [])
            conflicts.append({'at': updated, 'id': item_id, 'field': 'record',
                              'local': local_updated, 'vault': updated})
            del conflicts[:-200]
            return False
        if kind == 'task':
            item['done'] = bool(meta.get('done'))
            item['due'] = meta.get('due') if SAFE_DATE.match(str(meta.get('due') or '')) else None
            item['archived'] = bool(meta.get('archived'))
            item['body'] = body[:20000]
        else:
            item['title'] = str(meta.get('title') or item.get('title'))[:200]
            item['body'] = body[:20000]
            item['date'] = meta.get('date')
            item['archived'] = bool(meta.get('archived'))
            item['pinned'] = bool(meta.get('pinned'))
        item['tags'] = meta.get('tags', []) if isinstance(meta.get('tags', []), list) else []
        item['updatedAt'] = updated
        base[item_id] = updated
        return True
    base[item_id] = max(previous, local_updated)
    return False


def write_conflicts(state):
    sync = state.get('sync', {})
    conflicts = sync.get('conflicts', [])
    path = VAULT / 'conflicts.md'
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ['# Saturn conflicts', '',
             'Local data wins. Resolve each item in Saturn, then run `saturn vault sync` again.', '']
    for item in conflicts[-200:]:
        lines.append(f'- {item.get("id")} · field: {item.get("field")} · local: {item.get("local")} · vault: {item.get("vault")}')
    text = '\n'.join(lines) + '\n'
    if not path.exists() or path.read_text(errors='replace') != text:
        path.write_text(text)
        return True
    return False


def ensure_git(operation):
    if not VAULT.exists():
        return
    try:
        if subprocess.run(['git', '-C', str(VAULT), 'rev-parse', '--is-inside-work-tree'],
                          capture_output=True).returncode != 0:
            subprocess.run(['git', 'init', '-q', str(VAULT)], capture_output=True, check=True)
        gitignore = VAULT / '.gitignore'
        if not gitignore.exists():
            gitignore.write_text('.saturn-*.md\n.workspace-*\n.lock\n')
        subprocess.run(['git', '-C', str(VAULT), 'add', '-A'], capture_output=True, check=True)
        if subprocess.run(['git', '-C', str(VAULT), 'diff', '--cached', '--quiet']).returncode != 0:
            subprocess.run(['git', '-C', str(VAULT), 'commit', '-q', '-m', f'saturn: {operation}'],
                           capture_output=True)
    except (OSError, subprocess.CalledProcessError):
        pass


def main(argv):
    mode = argv[0] if argv else 'sync'
    if mode not in {'push', 'pull', 'sync', 'status'}:
        log('Use push, pull, sync or status')
        raise SystemExit(2)
    VAULT.mkdir(parents=True, exist_ok=True)
    if not (VAULT / '.git').exists():
        ensure_git('init')
    state = load_state()
    found = scan()
    pulled = False
    if mode in {'pull', 'sync'}:
        for item_id, (path, meta, body) in found.items():
            if not SAFE_ID.match(item_id) and not SAFE_DATE.match(item_id.replace('daily:', '')):
                continue
            pulled = apply_incoming(state, meta, body) or pulled
        known = state.get('sync', {}).get('vault', {}).get('base', {})
        for item_id in known:
            if item_id in found:
                continue
            kind = 'daily' if str(item_id).startswith('daily:') else 'task'
            if any(note.get('id') == item_id for note in state.get('notesV2', [])):
                kind = 'note'
            pulled = apply_incoming(state, {'id': item_id, 'kind': kind, 'deleted': True,
                                            'updatedAt': known.get(item_id, 0)}, '') or pulled
    if pulled:
        vault_meta = state.setdefault('sync', {}).setdefault('vault', {})
        vault_meta['lastSync'] = int(datetime.now(timezone.utc).timestamp() * 1000)
        save_state(state)
    pushed = False
    if mode in {'push', 'sync'}:
        files = desired_files(state)
        sync = state.setdefault('sync', {})
        vault_meta = sync.setdefault('vault', {})
        base = dict(vault_meta.get('base', {}))
        for task in state.get('tasks', []):
            base[task['id']] = task.get('updatedAt', 0)
        for note in state.get('notesV2', []):
            base[note['id']] = note.get('updatedAt', 0)
        expected_daily = {day: str(text) for day, text in state.get('notes', {}).items()}
        daily_changed = vault_meta.get('daily') != expected_daily
        vault_meta['daily'] = expected_daily
        for day in state.get('notes', {}):
            base[f'daily:{day}'] = 0
        for tomb in sync.get('tombstones', []):
            if isinstance(tomb, dict) and tomb.get('id'):
                base[tomb['id']] = tomb.get('at', base.get(tomb['id'], 0))
        metadata_changed = vault_meta.get('base') != base
        vault_meta['base'] = base
        if pulled:
            vault_meta['lastSync'] = int(datetime.now(timezone.utc).timestamp() * 1000)
        if metadata_changed or daily_changed or pulled:
            save_state(state)
        pushed = write_vault(state, files)
    conflict_changed = write_conflicts(state) if mode != 'status' else False
    if mode != 'status':
        ensure_git(mode)
    print(json.dumps({'ok': True, 'mode': mode, 'pulled': pulled, 'pushed': pushed,
                      'conflicts': len(state.get('sync', {}).get('conflicts', [])),
                      'files': len(desired_files(state)), 'conflictFile': conflict_changed,
                      'vault': str(VAULT)}))


if __name__ == '__main__':
    main(sys.argv[1:])
