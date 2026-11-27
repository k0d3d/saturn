#!/usr/bin/env python3
"""Scheduled LLM refinement of task tags.

The deterministic pass in Tags.js tags a task the moment it is added. This
script runs at configured hours of the day, sends changed titles to OpenCode's
DeepSeek model, and merges the returned tags back into Saturn. Tags become
graph nodes in saturn_graph.py, so refining tags also refines graph edges.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import settings as config_settings  # noqa: E402
import tags  # noqa: E402
import workspace_api as api  # noqa: E402

LEDGER = 'llm-tags.json'


def output(payload):
    print(json.dumps(payload, ensure_ascii=False))


def title_hash(title):
    return hashlib.sha256(str(title or '').encode('utf-8')).hexdigest()[:16]


def load_ledger():
    path = api.DATA_DIR / LEDGER
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        data = {}
    if not isinstance(data, dict):
        data = {}
    if not isinstance(data.get('hashes'), dict):
        data['hashes'] = {}
    return data


def save_ledger(ledger):
    path = api.DATA_DIR / LEDGER
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.llm-tags-', suffix='.json')
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(json.dumps(ledger, indent=2, ensure_ascii=False) + '\n')
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def pending_tasks(state, ledger, limit=20):
    """Active tasks whose title changed since the last successful pass."""
    hashes = ledger.get('hashes', {})
    rows = []
    for task in state.get('tasks', []):
        if not isinstance(task, dict) or task.get('archived'):
            continue
        task_id = str(task.get('id') or '')
        title = str(task.get('title') or '')
        if not task_id or not title.strip():
            continue
        if hashes.get(task_id) == title_hash(title):
            continue
        rows.append(task)
        if len(rows) >= max(int(limit), 1):
            break
    return rows


def build_prompt(tasks, llm, vocabulary=None):
    lines = [
        'You label tasks for a local knowledge graph. Reply with ONLY a JSON array, no prose and no code fences.',
        'Each item must be {"id":"<id>","tags":["tag", ...]} with 1-4 short lowercase tags.',
        'Reuse a tag from the existing vocabulary when it fits; otherwise propose a new one.',
        'Do not include dates, stopwords or the task id as a tag.',
    ]
    if vocabulary:
        lines.append('Existing tags: ' + ', '.join(vocabulary[:80]))
    lines.append('Tasks:')
    for task in tasks:
        lines.append('- id=%s | title=%s | current=%s' % (
            task.get('id', ''), task.get('title', ''), ', '.join(task.get('tags') or [])))
    return '\n'.join(lines)


def parse_model_output(raw, valid_ids):
    """Pull a JSON array out of a model response, ignoring prose and bad ids."""
    match = re.search(r'\[[\s\S]*\]', str(raw or ''))
    if not match:
        return {}
    try:
        data = json.loads(match.group(0))
    except ValueError:
        return {}
    if not isinstance(data, list):
        return {}
    result = {}
    for item in data:
        if not isinstance(item, dict) or str(item.get('id') or '') not in valid_ids:
            continue
        if not isinstance(item.get('tags'), list):
            continue
        cleaned = tags.clean(item['tags'])
        if cleaned:
            result[str(item['id'])] = cleaned
    return result


def opencode_call(model, prompt, timeout):
    """Run one headless OpenCode prompt and join its text events."""
    command = ['opencode', 'run', '--archived', '--format', 'json', '--model', model, prompt]
    completed = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    if completed.returncode != 0:
        raise RuntimeError((completed.stderr or 'opencode failed').strip().splitlines()[-1][:200])
    pieces = []
    for line in completed.stdout.splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get('type') == 'text':
            part = event.get('part') or {}
            if isinstance(part.get('text'), str):
                pieces.append(part['text'])
    return ''.join(pieces)


def shell_apply(task_id, values):
    """Write tags through the live shell when present, else through the offline API."""
    joined = ','.join(values)
    if api.shell_live():
        # The shell's data() IPC takes five fixed positional arguments.
        subprocess.run(['omarchy-shell', 'saturn', 'data', 'set-tags', task_id, joined, '', ''],
                       check=True, capture_output=True, timeout=15)
    else:
        with api.locked(exclusive=True):
            api.main(['set-tags', task_id, joined])


def run(state=None, llm=None, now=None, ledger=None, call_model=None, apply_tags=None):
    if state is None:
        state = api.read_state()
    if llm is None:
        llm = (state.get('settings') or {}).get('llm') or config_settings.fresh()['llm']
    llm = config_settings.normalise({'llm': llm})['llm']
    now = now or datetime.now()
    if not llm['enabled']:
        return {'status': 'skipped', 'reason': 'disabled', 'processed': 0}
    if now.hour not in llm['hours']:
        return {'status': 'skipped', 'reason': 'hour', 'processed': 0}
    own_ledger = ledger is None
    if own_ledger:
        ledger = load_ledger()
    hour_key = now.strftime('%Y-%m-%dT%H')
    if ledger.get('lastHour') == hour_key:
        return {'status': 'skipped', 'reason': 'already-ran', 'processed': 0}
    tasks = pending_tasks(state, ledger, llm['batch'])
    if not tasks:
        ledger['lastHour'] = hour_key
        if own_ledger:
            save_ledger(ledger)
        return {'status': 'ok', 'reason': 'empty', 'processed': 0}
    vocabulary = sorted({tag for task in state.get('tasks', [])
                         for tag in (task.get('tags') or []) if isinstance(tag, str)})
    prompt = build_prompt(tasks, llm, vocabulary)
    model_fn = call_model or (lambda model, text: opencode_call(model, text, llm['timeout']))
    apply_fn = apply_tags or shell_apply
    try:
        raw = model_fn(llm['model'], prompt)
        parsed = parse_model_output(raw, {str(t['id']) for t in tasks})
        applied = {}
        for task in tasks:
            proposed = parsed.get(str(task['id']))
            if not proposed:
                continue
            merged = tags.merge_tags(task.get('tags') or [], ' '.join(proposed))
            apply_fn(str(task['id']), merged)
            applied[str(task['id'])] = merged
    except Exception as error:
        return {'status': 'error', 'reason': str(error)[:200], 'processed': 0}
    for task in tasks:
        ledger['hashes'][str(task['id'])] = title_hash(task.get('title'))
    ledger['lastHour'] = hour_key
    if own_ledger:
        save_ledger(ledger)
    return {'status': 'ok', 'processed': len(applied), 'tags': applied}


def main(argv=None):
    argv = list(argv if argv is not None else sys.argv[1:])
    command = argv[0] if argv else 'run'
    if command == 'status':
        state = api.read_state()
        llm = config_settings.normalise(state.get('settings'))['llm']
        ledger = load_ledger()
        output({'enabled': llm['enabled'], 'model': llm['model'], 'hours': llm['hours'],
                'lastHour': ledger.get('lastHour'),
                'pending': len(pending_tasks(state, ledger, llm['batch']))})
        return 0
    if command == 'run':
        result = run()
        output(result)
        return 0 if result['status'] != 'error' else 1
    output({'ok': False, 'error': 'Use: tags [run|status]'})
    return 2


if __name__ == '__main__':
    raise SystemExit(main())
