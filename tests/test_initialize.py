from pathlib import Path
import importlib.util
import json
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = Path(__file__).resolve().parent / 'fixtures' / 'v1-workspace.json'
spec = importlib.util.spec_from_file_location('initialize', ROOT / 'initialize.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class InitializeTests(unittest.TestCase):
    def test_new_workspace_is_v2_with_private_permissions(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp) / 'saturn'
            module.initialize(folder, Path(temp) / 'legacy', Path(temp) / 'backups')
            state = json.loads((folder / 'workspace.json').read_text())
            self.assertEqual(state['version'], 2)
            self.assertEqual(state['tasks'], [])
            self.assertEqual(state['notes'], {})
            self.assertEqual(state['notesV2'], [])
            self.assertEqual(state['sync'], {'providers': {}, 'conflicts': [], 'tombstones': []})
            self.assertEqual(state['insights'], {})
            self.assertFalse(state['focus']['running'])
            self.assertEqual(folder.stat().st_mode & 0o777, 0o700)
            self.assertEqual((folder / 'workspace.json').stat().st_mode & 0o777, 0o600)
            self.assertFalse((Path(temp) / 'backups').exists())

    def test_existing_or_invalid_data_never_replaced(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'workspace.json'
            for text in ['{"notes":{"today":"Keep my note"}}', 'damaged but recoverable']:
                path.write_text(text)
                module.initialize(temp, Path(temp) / 'legacy', Path(temp) / 'backups')
                self.assertEqual(path.read_text(), text)

    def test_legacy_workspace_migrates_once_with_backup(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            legacy = base / 'omaowl'
            legacy.mkdir()
            original = FIXTURE.read_text()
            (legacy / 'workspace.json').write_text(original)
            folder = base / 'saturn'
            backups = base / 'omaowl-backups'

            target = module.initialize(folder, legacy, backups)
            state = json.loads(target.read_text())
            self.assertEqual(state['version'], 2)
            self.assertEqual(len(state['tasks']), 2)
            open_task, done_task = state['tasks']
            self.assertEqual(open_task['due'], None)
            self.assertEqual(open_task['createdAt'], 0)
            self.assertEqual(open_task['archived'], False)
            self.assertEqual(open_task['tags'], [])
            self.assertEqual(open_task['source'], 'local')
            self.assertEqual(done_task['createdAt'], 1795416635190)
            self.assertEqual(len(state['notesV2']), 0)
            self.assertFalse(state['focus']['running'])
            self.assertEqual(state['messageKeyOnly'], False)
            self.assertEqual(state['sync'], {'providers': {}, 'conflicts': [], 'tombstones': []})
            self.assertEqual((legacy / 'workspace.json').read_text(), original)
            saved = list(backups.glob('migration-*/workspace.json'))
            self.assertEqual(len(saved), 1)
            self.assertEqual(saved[0].read_text(), original)
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)

            # A second start leaves the migrated file alone and makes no new backup.
            module.initialize(folder, legacy, backups)
            self.assertEqual(target.read_text(), json.dumps(state, indent=2) + '\n')
            self.assertEqual(len(list(backups.glob('migration-*/workspace.json'))), 1)

    def test_invalid_legacy_data_is_preserved_byte_for_byte(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            legacy = base / 'omaowl'
            legacy.mkdir()
            broken = '{"version": 1, "tasks": "not a list"}'
            (legacy / 'workspace.json').write_text(broken)
            target = module.initialize(base / 'saturn', legacy, base / 'backups')
            self.assertEqual(target.read_text(), broken)
            self.assertFalse((base / 'backups').exists())

    def test_credentials_migrate_once_with_private_permissions(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            old = base / 'omaowl'
            (old / 'connections').mkdir(parents=True)
            (old / 'connections' / 'gmail.json').write_text('{"token":"secret"}')
            (old / 'todoist.json').write_text('{"key":"secret"}')
            grok = base / 'oma-pulse'
            grok.mkdir()
            (grok / 'grok-api-key').write_text('xai-secret')
            target = base / 'saturn'

            module.migrate_config(target, [old, grok])
            self.assertEqual((target / 'connections' / 'gmail.json').read_text(), '{"token":"secret"}')
            self.assertEqual((target / 'grok-api-key').read_text(), 'xai-secret')
            self.assertEqual(target.stat().st_mode & 0o777, 0o700)
            self.assertEqual((target / 'connections' / 'gmail.json').stat().st_mode & 0o777, 0o600)
            (target / 'grok-api-key').write_text('updated-locally')
            module.migrate_config(target, [old, grok])
            self.assertEqual((target / 'grok-api-key').read_text(), 'updated-locally')

    def test_javascript_and_python_migrations_agree(self):
        script = """
const fs = require('fs'), vm = require('vm');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync('Logic.js', 'utf8'), context);
const raw = fs.readFileSync('tests/fixtures/v1-workspace.json', 'utf8');
process.stdout.write(context.serialize(context.parse(raw)));
"""
        output = subprocess.run(['node', '-e', script], cwd=ROOT, text=True,
                                capture_output=True, check=True).stdout
        expected = json.dumps(module.migrate(json.loads(FIXTURE.read_text())),
                              indent=2, ensure_ascii=False) + '\n'
        self.assertEqual(output, expected)

    def test_migration_rejects_unknown_schema_and_bad_fields(self):
        with self.assertRaises(ValueError):
            module.migrate({'version': 9})
        with self.assertRaises(ValueError):
            module.migrate({'version': 1, 'notesV2': [{'id': 'n', 'title': 'n', 'body': 'b', 'tags': [1]}]})
        focus = {'title': 'Open focus', 'duration': 1500, 'elapsed': 0, 'running': False}
        state = module.migrate({'version': 1, 'focus': focus, 'tasks': [{'id': 'a', 'title': 'a', 'due': '2026-11-24'}]})
        self.assertEqual(state['tasks'][0]['due'], '2026-11-24')
        self.assertIsNone(module.migrate({'version': 1, 'focus': focus, 'tasks': [{'id': 'a', 'title': 'a', 'due': 'tomorrow'}]})['tasks'][0]['due'])


if __name__ == '__main__':
    unittest.main()
