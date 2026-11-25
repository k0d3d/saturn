#!/usr/bin/env python3
"""Local-first knowledge graph for Saturn, backed by SQLite.

workspace.json owns item content; this database owns relationships. Agent edges
are authoritative and survive reindexing. Tag and wiki edges are regenerated
from workspace content on every command, so deleted or renamed content never
leaves stale implicit links behind.
"""
import json
import os
import re
import shutil
import sqlite3
import sys
import time
from collections import deque
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import initialize  # noqa: E402

DATA_HOME = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share')
WORKSPACE = DATA_HOME / 'saturn' / 'workspace.json'
BACKUPS = DATA_HOME / 'omaowl-backups'
RELATION = re.compile(r'^[a-z0-9][a-z0-9_-]{0,39}$')
WIKI = re.compile(r'\[\[([^\[\]]{1,200})\]\]')
KEY = re.compile(r'^(task|note|daily|event|tag):[A-Za-z0-9_.:@-]{1,200}$')


def emit(value):
    print(json.dumps(value, ensure_ascii=False))


def db_path():
    return DATA_HOME / 'saturn' / 'graph.sqlite'


def connect():
    path = db_path()
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    db = sqlite3.connect(path, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA busy_timeout=10000')
    db.execute('PRAGMA journal_mode=WAL')
    db.executescript('''
        CREATE TABLE IF NOT EXISTS meta (
            key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS nodes (
            key TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            archived INTEGER NOT NULL DEFAULT 0,
            stale INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS edges (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            src TEXT NOT NULL,
            dst TEXT NOT NULL,
            relation TEXT NOT NULL,
            origin TEXT NOT NULL,
            label TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            UNIQUE(src, dst, relation));
        CREATE INDEX IF NOT EXISTS edges_src ON edges(src);
        CREATE INDEX IF NOT EXISTS edges_dst ON edges(dst);
    ''')
    os.chmod(path, 0o600)
    return db


def now():
    return int(time.time() * 1000)


def read_workspace():
    if not WORKSPACE.exists():
        initialize.initialize(WORKSPACE.parent, DATA_HOME / 'omaowl', BACKUPS)
    try:
        return initialize.migrate(json.loads(WORKSPACE.read_text()))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        raise RuntimeError(f'Workspace could not be read: {error}') from None


def desired_nodes(state):
    nodes = {}
    for task in state.get('tasks', []):
        nodes['task:' + task['id']] = (task.get('title', ''), bool(task.get('archived')),
                                      task.get('updatedAt', 0))
    for note in state.get('notesV2', []):
        nodes['note:' + note['id']] = (note.get('title', ''), bool(note.get('archived')),
                                      note.get('updatedAt', 0))
    for day, body in state.get('notes', {}).items():
        nodes['daily:' + day] = (f'Daily note · {day}', False, 0)
    for event in state.get('events', []):
        nodes['event:' + event['id']] = (event.get('title', ''), bool(event.get('archived')),
                                        event.get('updatedAt', 0))
    tags = set()
    for item in state.get('tasks', []) + state.get('notesV2', []):
        tags.update(tag for tag in item.get('tags', []) if isinstance(tag, str) and tag.strip())
    for tag in sorted(tags):
        nodes['tag:' + tag[:80]] = (tag[:80], False, 0)
    return nodes


def wiki_targets(state):
    targets = []
    for task in state.get('tasks', []):
        targets.append(('task:' + task['id'], task.get('body', '')))
    for note in state.get('notesV2', []):
        targets.append(('note:' + note['id'], note.get('body', '')))
    for day, body in state.get('notes', {}).items():
        targets.append(('daily:' + day, body))
    for key, body in targets:
        for raw in WIKI.findall(body or ''):
            targets_only = raw.strip()
            if targets_only:
                yield key, targets_only


def resolve(db, reference):
    ref = str(reference or '').strip().strip('[]')
    if not ref or len(ref) > 200:
        return None
    if KEY.match(ref) and db.execute('SELECT 1 FROM nodes WHERE key=?', (ref,)).fetchone():
        return ref
    rows = db.execute('SELECT key FROM nodes WHERE lower(title)=lower(?) AND stale=0',
                      (ref,)).fetchall()
    if len(rows) == 1:
        return rows[0]['key']
    return None


def refresh():
    state = read_workspace()
    wanted = desired_nodes(state)
    stamp = now()
    db = connect()
    try:
        with db:
            for key, (title, archived, updated) in wanted.items():
                db.execute('''INSERT INTO nodes(key, kind, title, archived, stale, updated_at)
                              VALUES(?,?,?,?,0,?)
                              ON CONFLICT(key) DO UPDATE SET
                                kind=excluded.kind, title=excluded.title,
                                archived=excluded.archived, stale=0,
                                updated_at=excluded.updated_at''',
                           (key, key.split(':', 1)[0], title[:500], int(archived), updated))
            for row in db.execute("SELECT key FROM nodes WHERE stale=0 AND key NOT LIKE 'tag:%'"):
                if row['key'] not in wanted:
                    db.execute('UPDATE nodes SET stale=1, archived=1 WHERE key=?', (row['key'],))
            db.execute("DELETE FROM edges WHERE origin IN ('wiki','tag')")
            for task in state.get('tasks', []) + state.get('notesV2', []):
                key = ('task:' if 'completedAt' in task else 'note:') + task['id']
                for tag in task.get('tags', []):
                    tag_key = 'tag:' + str(tag)[:80]
                    if tag_key in wanted:
                        db.execute('''INSERT OR IGNORE INTO edges
                                      (src,dst,relation,origin,label,created_at,updated_at)
                                      VALUES(?,?,?,?,?,?,?)''',
                                   (key, tag_key, 'tagged', 'tag', str(tag)[:80], stamp, stamp))
            for key, raw in wiki_targets(state):
                target = resolve(db, raw)
                if target and target != key:
                    db.execute('''INSERT OR IGNORE INTO edges
                                  (src,dst,relation,origin,label,created_at,updated_at)
                                  VALUES(?,?,?,?,?,?,?)''',
                               (key, target, 'references', 'wiki', raw[:200], stamp, stamp))
            db.execute('INSERT INTO meta(key,value) VALUES(?,?) '
                       'ON CONFLICT(key) DO UPDATE SET value=excluded.value',
                       ('last_refresh', str(stamp)))
        return {'ok': True, 'refreshed': stamp}
    finally:
        db.close()


def node_row(db, key):
    row = db.execute('SELECT * FROM nodes WHERE key=?', (key,)).fetchone()
    if not row:
        return {'key': key, 'kind': key.split(':', 1)[0], 'title': '',
                'archived': False, 'stale': True}
    return {'key': row['key'], 'kind': row['kind'], 'title': row['title'],
            'archived': bool(row['archived']), 'stale': bool(row['stale'])}


def link(src, relation, dst, label=''):
    if not RELATION.match(str(relation or '')):
        return {'ok': False, 'error': 'Relation must be 1-40 lowercase letters, digits, - or _'}
    refresh()
    db = connect()
    try:
        source, target = resolve(db, src), resolve(db, dst)
        if not source or not target:
            return {'ok': False, 'error': 'One or both nodes could not be resolved uniquely'}
        if source == target:
            return {'ok': False, 'error': 'A node cannot link to itself'}
        stamp = now()
        with db:
            db.execute('''INSERT INTO edges(src,dst,relation,origin,label,created_at,updated_at)
                          VALUES(?,?,?,?,?,?,?)
                          ON CONFLICT(src,dst,relation) DO UPDATE SET
                            origin='agent', label=excluded.label, updated_at=excluded.updated_at''',
                       (source, target, relation, 'agent', str(label or '')[:200], stamp, stamp))
        return {'ok': True, 'src': source, 'dst': target, 'relation': relation, 'origin': 'agent'}
    finally:
        db.close()


def unlink(src, relation, dst):
    refresh()
    db = connect()
    try:
        source, target = resolve(db, src), resolve(db, dst)
        if not source or not target:
            return {'ok': False, 'error': 'One or both nodes could not be resolved uniquely'}
        with db:
            cursor = db.execute('DELETE FROM edges WHERE src=? AND dst=? AND relation=?',
                                (source, target, relation))
        return {'ok': True, 'deleted': cursor.rowcount}
    finally:
        db.close()


def neighbours(start, depth=1, relation=None):
    depth = max(1, min(int(depth or 1), 4))
    refresh()
    db = connect()
    try:
        origin = resolve(db, start)
        if not origin:
            return {'ok': False, 'error': 'Node could not be resolved uniquely'}
        seen = {origin: 0}
        queue = deque([(origin, 0)])
        found = []
        while queue:
            key, level = queue.popleft()
            if level >= depth:
                continue
            rows = db.execute('SELECT * FROM edges WHERE src=? OR dst=?', (key, key)).fetchall()
            for edge in rows:
                if relation and edge['relation'] != relation:
                    continue
                other = edge['dst'] if edge['src'] == key else edge['src']
                if other in seen:
                    continue
                seen[other] = level + 1
                queue.append((other, level + 1))
                row = node_row(db, other)
                row.update({'depth': level + 1, 'relation': edge['relation'],
                            'origin': edge['origin'], 'label': edge['label']})
                found.append(row)
        found.sort(key=lambda row: (row['depth'], row['key']))
        return {'ok': True, 'root': origin, 'nodes': found}
    finally:
        db.close()


def path(source, target, max_depth=6):
    max_depth = max(1, min(int(max_depth or 6), 8))
    refresh()
    db = connect()
    try:
        start, finish = resolve(db, source), resolve(db, target)
        if not start or not finish:
            return {'ok': False, 'error': 'One or both nodes could not be resolved uniquely'}
        if start == finish:
            return {'ok': True, 'path': [start]}
        queue = deque([(start, [start])])
        seen = {start}
        while queue:
            key, route = queue.popleft()
            if len(route) > max_depth:
                continue
            for edge in db.execute('SELECT src,dst FROM edges WHERE src=? OR dst=?', (key, key)):
                other = edge['dst'] if edge['src'] == key else edge['src']
                if other == finish:
                    return {'ok': True, 'path': route + [other]}
                if other not in seen:
                    seen.add(other)
                    queue.append((other, route + [other]))
        return {'ok': True, 'path': None, 'error': 'No path found'}
    finally:
        db.close()


def status():
    db = connect()
    try:
        counts = {row['origin']: row['n'] for row in
                  db.execute('SELECT origin, count(*) AS n FROM edges GROUP BY origin')}
        row = db.execute('SELECT value FROM meta WHERE key=?', ('last_refresh',)).fetchone()
        return {'ok': True, 'nodes': db.execute('SELECT count(*) FROM nodes').fetchone()[0],
                'edges': db.execute('SELECT count(*) FROM edges').fetchone()[0],
                'by_origin': counts, 'last_refresh': int(row['value']) if row else None,
                'database': str(db_path())}
    finally:
        db.close()


def backup():
    target = BACKUPS / f'graph-{date.today().isoformat()}-{os.getpid()}.sqlite'
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    source = connect()
    destination = sqlite3.connect(target)
    try:
        source.backup(destination)
    finally:
        destination.close()
        source.close()
    os.chmod(target, 0o600)
    return {'ok': True, 'path': str(target)}


def forget(key):
    db = connect()
    try:
        target = resolve(db, key)
        if not target:
            return {'ok': False, 'error': 'Node could not be resolved uniquely'}
        with db:
            db.execute('DELETE FROM edges WHERE src=? OR dst=?', (target, target))
            db.execute('DELETE FROM nodes WHERE key=?', (target,))
        return {'ok': True, 'key': target}
    finally:
        db.close()


def listing(kind):
    db = connect()
    try:
        if kind == 'edges':
            rows = db.execute('''SELECT src,dst,relation,origin,label FROM edges
                                 ORDER BY src,dst,relation''').fetchall()
            return {'ok': True, 'edges': [dict(row) for row in rows]}
        rows = db.execute('SELECT key,kind,title,archived,stale FROM nodes ORDER BY key').fetchall()
        return {'ok': True, 'nodes': [dict(row, archived=bool(row['archived']),
                                          stale=bool(row['stale'])) for row in rows]}
    finally:
        db.close()


def main(argv):
    command = argv[0] if argv else 'status'
    args = argv[1:]
    try:
        if command == 'reindex':
            result = refresh()
        elif command == 'link':
            result = link(*(args + [''] * (4 - len(args)))[:4])
        elif command == 'unlink':
            result = unlink(*(args + [''] * (3 - len(args)))[:3])
        elif command in ('neighbors', 'neighbours'):
            result = neighbours(args[0] if args else '', args[1] if len(args) > 1 else 1,
                                args[2] if len(args) > 2 else None)
        elif command == 'path':
            result = path(args[0] if args else '', args[1] if len(args) > 1 else '',
                          args[2] if len(args) > 2 else 6)
        elif command == 'status':
            result = status()
        elif command == 'backup':
            result = backup()
        elif command == 'forget':
            result = forget(args[0] if args else '')
        elif command == 'list':
            result = listing(args[0] if args else 'nodes')
        elif command == 'resolve':
            db = connect()
            try:
                key = resolve(db, args[0] if args else '')
            finally:
                db.close()
            result = {'ok': bool(key), 'key': key}
        else:
            result = {'ok': False, 'error': 'Unknown graph command'}
    except (OSError, sqlite3.Error, ValueError, RuntimeError) as error:
        result = {'ok': False, 'error': str(error)[:300]}
    emit(result)
    if not result.get('ok'):
        raise SystemExit(2)


if __name__ == '__main__':
    main(sys.argv[1:])
