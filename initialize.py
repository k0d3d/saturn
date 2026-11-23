#!/usr/bin/env python3
"""Create private first-run storage and migrate legacy v1 data without replacing it."""
import json
import os
import re
import shutil
from datetime import datetime
from pathlib import Path

DATA_HOME = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share')
DATA_DIR = DATA_HOME / 'saturn'
LEGACY_DIR = DATA_HOME / 'omaowl'
BACKUP_DIR = DATA_HOME / 'omaowl-backups'
CONFIG_HOME = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
CONFIG_DIR = CONFIG_HOME / 'saturn'
LEGACY_CONFIG_DIRS = [CONFIG_HOME / 'omaowl', CONFIG_HOME / 'oma-pulse']
DAY = re.compile(r'^\d{4}-\d{2}-\d{2}$')


def fresh():
    """A v2 workspace with no user data."""
    return {
        'version': 2,
        'tasks': [],
        'notes': {},
        'notesV2': [],
        'activity': {},
        'focus': {'title': 'Open focus', 'duration': 1500, 'elapsed': 0, 'running': False},
        'sync': {'providers': {}, 'conflicts': [], 'tombstones': []},
        'insights': {},
    }


def _finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and value >= 0


def _date(value):
    return value if isinstance(value, str) and DAY.match(value) else None


def _string_list(value, field):
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ValueError(f'Unrecognized {field}')
    return value


def migrate(state):
    """Upgrade a v1 (or already-v2) workspace in memory. Unknown keys survive."""
    if not isinstance(state, dict):
        raise ValueError('Unrecognized workspace data')
    version = state.get('version', 1)
    if version not in (1, 2):
        raise ValueError(f'Unrecognized workspace version: {version}')
    if not isinstance(state.get('tasks', []), list):
        raise ValueError('Unrecognized tasks')

    result = dict(state)
    result['version'] = 2

    tasks = []
    for raw in state.get('tasks', []):
        if not isinstance(raw, dict) or not isinstance(raw.get('id'), str) or not isinstance(raw.get('title'), str):
            raise ValueError('Unrecognized task')
        task = dict(raw)
        task['due'] = _date(task.get('due'))
        task.setdefault('createdAt', task.get('completedAt') if _finite(task.get('completedAt')) else 0)
        task.setdefault('updatedAt', task.get('completedAt') if _finite(task.get('completedAt')) else 0)
        task.setdefault('archived', False)
        task.setdefault('archivedAt', 0)
        task.setdefault('body', '')
        task.setdefault('tags', [])
        task.setdefault('source', 'local')
        task.setdefault('externalId', None)
        if not isinstance(task['archived'], bool) or not _finite(task['archivedAt']):
            raise ValueError('Unrecognized task archive state')
        _string_list(task['tags'], 'task tags')
        tasks.append(task)
    result['tasks'] = tasks

    notes = state.get('notes', {})
    if not isinstance(notes, dict) or any(not isinstance(value, str) for value in notes.values()):
        raise ValueError('Unrecognized daily notes')
    result['notes'] = notes

    notes_v2 = state.get('notesV2', [])
    if not isinstance(notes_v2, list):
        raise ValueError('Unrecognized notes')
    library = []
    for raw in notes_v2:
        if not isinstance(raw, dict) or not isinstance(raw.get('id'), str) or not isinstance(raw.get('title'), str) or not isinstance(raw.get('body'), str):
            raise ValueError('Unrecognized note')
        note = dict(raw)
        note['date'] = _date(note.get('date'))
        note.setdefault('tags', [])
        note.setdefault('createdAt', 0)
        note.setdefault('updatedAt', 0)
        note.setdefault('archived', False)
        note.setdefault('pinned', False)
        _string_list(note['tags'], 'note tags')
        if (not _finite(note['createdAt']) or not _finite(note['updatedAt'])
                or not isinstance(note['archived'], bool) or not isinstance(note['pinned'], bool)):
            raise ValueError('Unrecognized note metadata')
        library.append(note)
    result['notesV2'] = library

    activity = state.get('activity', {})
    if not isinstance(activity, dict) or any(not _finite(value) for value in activity.values()):
        raise ValueError('Unrecognized focus activity')
    result['activity'] = activity

    focus = state.get('focus', {})
    if not isinstance(focus, dict) or not isinstance(focus.get('title'), str) or not _finite(focus.get('duration', 0)) or not _finite(focus.get('elapsed', 0)):
        raise ValueError('Unrecognized focus state')
    result['focus'] = dict(focus, running=False)

    for source in ['mailSource', 'calendarSource']:
        if source in state and not isinstance(state[source], str):
            raise ValueError(f'Unrecognized {source}')

    sync = state.get('sync', {})
    if not isinstance(sync, dict):
        raise ValueError('Unrecognized sync metadata')
    result['sync'] = {
        'providers': sync.get('providers', {}),
        'conflicts': sync.get('conflicts', []),
        'tombstones': sync.get('tombstones', []),
    }
    for field in ['providers', 'conflicts', 'tombstones']:
        if not isinstance(result['sync'][field], (dict if field == 'providers' else list)):
            raise ValueError(f'Unrecognized sync {field}')

    insights = state.get('insights', {})
    if not isinstance(insights, dict):
        raise ValueError('Unrecognized insights')
    result['insights'] = insights
    return result


def _atomic_write(path, text):
    """Create a private file once, never replacing what is already there."""
    folder = path.parent
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return False
    with os.fdopen(fd, 'w') as stream:
        stream.write(text)
    return True


def _backup(source, backup_root):
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    target = backup_root / f'migration-{stamp}' / source.name
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    shutil.copy2(source, target)
    return target


def initialize(folder=None, legacy=None, backups=None):
    """Prepare Saturn storage. A legacy workspace is migrated once, never deleted."""
    target_dir = Path(folder) if folder is not None else DATA_DIR
    target = target_dir / 'workspace.json'
    target_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    if target.exists():
        return target

    legacy_file = (Path(legacy) if legacy is not None else LEGACY_DIR) / 'workspace.json'
    if not legacy_file.exists():
        _atomic_write(target, json.dumps(fresh(), indent=2) + '\n')
        return target

    raw = legacy_file.read_text()
    try:
        migrated = migrate(json.loads(raw))
        text = json.dumps(migrated, indent=2, ensure_ascii=False) + '\n'
        _backup(legacy_file, Path(backups) if backups is not None else BACKUP_DIR)
    except (ValueError, json.JSONDecodeError):
        # Damaged data is preserved byte-for-byte; the shell reports the error.
        text = raw
    _atomic_write(target, text)
    return target


def migrate_config(target=None, legacies=None):
    """Move private credentials once, preserving permissions; never overwrite."""
    destination = Path(target) if target is not None else CONFIG_DIR
    if destination.exists():
        return destination
    sources = [Path(item) for item in (legacies if legacies is not None else LEGACY_CONFIG_DIRS)]
    sources = [item for item in sources if item.is_dir()]
    if sources:
        shutil.copytree(sources[0], destination, symlinks=False, copy_function=shutil.copy2)
        for extra in sources[1:]:
            shutil.copytree(extra, destination, dirs_exist_ok=True, symlinks=False,
                            copy_function=shutil.copy2)
    else:
        destination.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(destination, 0o700)
    for path in destination.rglob('*'):
        os.chmod(path, 0o700 if path.is_dir() else 0o600)
    return destination


if __name__ == '__main__':
    initialize()
    migrate_config()
