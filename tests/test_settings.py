import unittest

from scripts import settings


class SettingsTest(unittest.TestCase):
    def test_fresh_settings_enable_a_lean_deepseek_schedule(self):
        self.assertEqual(settings.fresh(), {
            'llm': {
                'enabled': True,
                'model': 'opencode/deepseek-v4.1-flash-free',
                'hours': [9, 18],
                'batch': 20,
                'timeout': 120,
                'prompt': '',
            }
        })

    def test_normalise_fills_missing_and_invalid_fields_but_keeps_valid_choices(self):
        value = settings.normalise({
            'llm': {'model': 'custom/model', 'hours': [7, 99], 'batch': 5, 'nonsense': True}
        })
        self.assertTrue(value['llm']['enabled'])
        self.assertEqual(value['llm']['model'], 'custom/model')
        self.assertEqual(value['llm']['hours'], [9, 18])
        self.assertEqual(value['llm']['batch'], 5)
        self.assertEqual(value['llm']['timeout'], 120)
        self.assertEqual(settings.normalise(None)['llm']['hours'], [9, 18])
        self.assertTrue(settings.normalise({'llm': None})['llm']['enabled'])

    def test_an_empty_schedule_is_valid(self):
        self.assertEqual(settings.normalise({'llm': {'hours': []}})['llm']['hours'], [])

    def test_fresh_and_migrated_workspaces_both_carry_settings(self):
        import initialize
        self.assertEqual(initialize.fresh()['settings'], settings.fresh())
        migrated = initialize.migrate(initialize.fresh())
        self.assertEqual(migrated['settings'], settings.fresh())

    def test_offline_api_can_read_and_update_settings(self):
        import importlib.util
        from pathlib import Path
        from contextlib import redirect_stdout
        import io
        import json
        import tempfile
        from unittest.mock import patch

        root = Path(__file__).resolve().parent.parent
        spec = importlib.util.spec_from_file_location('workspace_api', root / 'scripts' / 'workspace_api.py')
        api = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(api)
        with tempfile.TemporaryDirectory(prefix='saturn-settings-') as folder:
            base = Path(folder)
            data = base / 'saturn'
            patches = [
                patch.object(api, 'DATA_HOME', base), patch.object(api, 'DATA_DIR', data),
                patch.object(api, 'WORKSPACE', data / 'workspace.json'),
                patch.object(api, 'LOCK', data / '.workspace.lock'),
                patch.object(api, 'BACKUPS', base / 'backups'),
                patch.object(api, 'shell_live', return_value=False),
            ]
            for item in patches:
                item.start()
            try:
                stream = io.StringIO()
                with redirect_stdout(stream):
                    api.main(['settings'])
                self.assertEqual(json.loads(stream.getvalue()), settings.fresh())
                stream = io.StringIO()
                with redirect_stdout(stream):
                    api.main(['settings-set', json.dumps({'llm': {'hours': [7]}})])
                self.assertTrue(json.loads(stream.getvalue())['ok'])
                stream = io.StringIO()
                with redirect_stdout(stream):
                    api.main(['settings'])
                self.assertEqual(json.loads(stream.getvalue())['llm']['hours'], [7])
            finally:
                for item in patches:
                    item.stop()


if __name__ == '__main__':
    unittest.main()
