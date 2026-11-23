from contextlib import redirect_stdout
from datetime import date, timedelta
from pathlib import Path
import importlib.util
import io
import json
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('workspace_api', ROOT / 'scripts' / 'workspace_api.py')
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)


class WorkspaceApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='saturn-api-')
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.data_dir = base / 'saturn'
        self.patches = [
            patch.object(api, 'DATA_HOME', base),
            patch.object(api, 'DATA_DIR', self.data_dir),
            patch.object(api, 'WORKSPACE', self.data_dir / 'workspace.json'),
            patch.object(api, 'LOCK', self.data_dir / '.workspace.lock'),
            patch.object(api, 'BACKUPS', base / 'omaowl-backups'),
        ]
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)
        shell_patch = patch.object(api, 'shell_live', return_value=False)
        shell_patch.start()
        self.addCleanup(shell_patch.stop)

    def call(self, *args):
        stream = io.StringIO()
        with redirect_stdout(stream):
            api.main(list(args))
        return json.loads(stream.getvalue())

    def test_fresh_state_and_read_only_commands(self):
        state = self.call('get')
        self.assertEqual(state['version'], 2)
        self.assertEqual(state['tasks'], [])
        self.assertEqual(state['notesV2'], [])
        self.assertEqual(self.call('status')['schema'], 2)
        self.assertEqual(self.call('tasks-list'), [])
        self.assertTrue((self.data_dir / '.workspace.lock').exists())

    def test_add_task_sets_tomorrow_and_audits_without_body(self):
        result = self.call('add-task', 'Buy milk tomorrow')
        expected = (date.today() + timedelta(days=1)).isoformat()
        self.assertEqual(result['due'], expected)
        state = self.call('get')
        self.assertEqual(state['tasks'][0]['title'], 'Buy milk')
        self.assertEqual(state['tasks'][0]['due'], expected)
        self.assertEqual(state['sync']['audit'][-1]['command'], 'add-task')
        self.assertEqual(state['tasks'][0]['archived'], False)
        self.assertEqual(len(list((Path(self.temp.name) / 'omaowl-backups').glob('agent-*/workspace.json'))), 1)

    def test_notes_create_search_pin_and_archive(self):
        created = self.call('add-note', 'Voice plan', 'Try OpenCode voice', 'ai, voice', '2026-11-24')
        note_id = created['id']
        found = self.call('search', 'OpenCode')
        self.assertEqual([n['id'] for n in found], [note_id])
        self.assertEqual(self.call('pin-note', note_id)['ok'], True)
        self.assertEqual(self.call('get')['notesV2'][0]['pinned'], True)
        self.assertEqual(self.call('archive-note', note_id)['ok'], True)
        self.assertEqual(self.call('get')['notesV2'][0]['archived'], True)
        self.assertEqual(self.call('restore-note', note_id)['ok'], True)
        self.assertEqual(self.call('get')['notesV2'][0]['archived'], False)

    def test_writes_refuse_while_shell_is_live(self):
        before = self.call('get')
        with patch.object(api, 'shell_live', return_value=True):
            stream = io.StringIO()
            with redirect_stdout(stream), self.assertRaises(SystemExit) as stopped:
                api.main(['add-task', 'Should not appear'])
            self.assertEqual(stopped.exception.code, 3)
        self.assertEqual(json.loads(stream.getvalue())['ok'], False)
        self.assertEqual(self.call('get')['tasks'], before['tasks'])

    def test_invalid_ids_and_empty_titles_are_rejected(self):
        for args in [('add-task', ''), ('complete-task', 'missing'), ('add-note', '')]:
            with self.assertRaises(SystemExit):
                self.call(*args)


if __name__ == '__main__':
    unittest.main()
