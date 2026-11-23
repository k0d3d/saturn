from contextlib import redirect_stdout
from pathlib import Path
import importlib.util
import io
import json
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('vault_sync', ROOT / 'scripts' / 'vault_sync.py')
vault = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vault)


class VaultSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='saturn-vault-')
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        workspace = base / 'saturn' / 'workspace.json'
        workspace.parent.mkdir(parents=True)
        workspace.write_text(json.dumps({
            'version': 2,
            'tasks': [{'id': 'task1', 'title': 'Ship Saturn', 'done': False, 'completedAt': 0,
                       'due': '2026-11-24', 'createdAt': 1, 'updatedAt': 10, 'archived': False,
                       'archivedAt': 0, 'body': 'Initial body', 'tags': ['work'],
                       'source': 'local', 'externalId': None}],
            'notes': {'2026-11-23': 'Daily text'},
            'notesV2': [], 'activity': {},
            'focus': {'title': 'Open focus', 'duration': 1500, 'elapsed': 0, 'running': False},
            'sync': {'providers': {}, 'conflicts': [], 'tombstones': []}, 'insights': {},
        }, indent=2))
        self.workspace = workspace
        self.vault_dir = base / 'vault'
        patches = [
            patch.object(vault, 'WORKSPACE', workspace),
            patch.object(vault, 'VAULT', self.vault_dir),
            patch.object(vault, 'ensure_git'),
        ]
        for item in patches:
            item.start()
            self.addCleanup(item.stop)

    def call(self, mode):
        stream = io.StringIO()
        with redirect_stdout(stream):
            vault.main([mode])
        return json.loads(stream.getvalue())

    def state(self):
        return json.loads(self.workspace.read_text())

    def file_for(self, item_id):
        for path in self.vault_dir.glob('*/*.md'):
            parsed = vault.parse(path.read_text())
            if parsed and parsed[0].get('id') == item_id:
                return path
        raise AssertionError(f'no vault file for {item_id}')

    def test_push_creates_task_and_daily_files(self):
        result = self.call('push')
        self.assertTrue(result['ok'])
        task_path = self.file_for('task1')
        meta, body = vault.parse(task_path.read_text())
        self.assertEqual(meta['title'], 'Ship Saturn')
        self.assertEqual(meta['due'], '2026-11-24')
        self.assertEqual(body, 'Initial body')
        self.assertTrue(self.file_for('daily:2026-11-23').exists())
        self.assertIn('task1', self.state()['sync']['vault']['base'])

    def test_pull_applies_external_edit_when_local_unchanged(self):
        self.call('push')
        path = self.file_for('task1')
        meta, body = vault.parse(path.read_text())
        meta['updatedAt'] = meta['updatedAt'] + 100
        path.write_text(vault.render(meta, 'Edited in vault'))
        result = self.call('pull')
        self.assertTrue(result['pulled'])
        self.assertEqual(self.state()['tasks'][0]['body'], 'Edited in vault')
        self.assertIsNotNone(self.state()['sync']['vault'].get('lastSync'))

    def test_two_sided_change_is_conflict_and_local_wins(self):
        self.call('push')
        path = self.file_for('task1')
        meta, body = vault.parse(path.read_text())
        meta['updatedAt'] = meta['updatedAt'] + 300
        path.write_text(vault.render(meta, 'Vault version'))
        local = self.state()
        local['tasks'][0]['body'] = 'Local version'
        local['tasks'][0]['updatedAt'] = meta['updatedAt'] - 100
        self.workspace.write_text(json.dumps(local))
        result = self.call('pull')
        self.assertEqual(result['conflicts'], 1)
        self.assertEqual(self.state()['tasks'][0]['body'], 'Local version')
        self.assertIn('task1', (self.vault_dir / 'conflicts.md').read_text())

    def test_missing_vault_file_creates_tombstone_and_archives(self):
        self.call('push')
        self.file_for('task1').unlink()
        self.call('pull')
        state = self.state()
        self.assertTrue(state['tasks'][0]['archived'])
        self.assertEqual(state['sync']['tombstones'][0]['id'], 'task1')

    def test_status_is_read_only(self):
        self.call('push')
        before = self.workspace.read_text()
        result = self.call('status')
        self.assertEqual(result['mode'], 'status')
        self.assertEqual(self.workspace.read_text(), before)


if __name__ == '__main__':
    unittest.main()
