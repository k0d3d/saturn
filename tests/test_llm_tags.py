import json
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

from scripts import llm_tags, settings, tags


class LlmTagsTest(unittest.TestCase):
    def setUp(self):
        self.llm = settings.fresh()['llm']

    def test_title_hash_tracks_the_title_only(self):
        self.assertEqual(llm_tags.title_hash('Buy milk'), llm_tags.title_hash('Buy milk'))
        self.assertNotEqual(llm_tags.title_hash('Buy milk'), llm_tags.title_hash('Buy bread'))

    def test_pending_selects_changed_active_tasks_up_to_the_batch_limit(self):
        state = {'tasks': [
            {'id': 'a', 'title': 'Buy milk', 'tags': [], 'archived': False},
            {'id': 'b', 'title': 'Call dentist', 'tags': ['health'], 'archived': False},
            {'id': 'c', 'title': 'Old done thing', 'tags': [], 'archived': True},
        ]}
        ledger = {'hashes': {'a': llm_tags.title_hash('Buy milk')}}
        self.assertEqual([t['id'] for t in llm_tags.pending_tasks(state, ledger, 20)], ['b'])
        self.assertEqual(llm_tags.pending_tasks(state, ledger, 1), [state['tasks'][1]])

    def test_prompt_asks_for_parseable_json_and_offers_existing_tags(self):
        tasks = [{'id': 'a', 'title': 'Buy milk', 'tags': ['errands']}]
        prompt = llm_tags.build_prompt(tasks, self.llm)
        self.assertIn('a', prompt)
        self.assertIn('Buy milk', prompt)
        self.assertIn('errands', prompt)
        self.assertIn('JSON', prompt)

    def test_model_output_parses_code_fences_and_ignores_unknown_ids(self):
        raw = '```json\n[{"id":"a","tags":["Milk","#Errands","the","milk"]},' \
              '{"id":"zzz","tags":["ghost"]}]\n```'
        parsed = llm_tags.parse_model_output(raw, {'a'})
        self.assertEqual(parsed, {'a': ['milk', 'errands']})

    def test_run_skips_when_disabled_outside_schedule_or_already_run(self):
        state = {'tasks': [{'id': 'a', 'title': 'Buy milk', 'tags': [], 'archived': False}]}
        now = datetime(2026, 11, 27, 9, 30)
        disabled = dict(self.llm, enabled=False)
        self.assertEqual(llm_tags.run(state, disabled, now, ledger={})['status'], 'skipped')
        other_hour = datetime(2026, 11, 27, 12, 0)
        self.assertEqual(llm_tags.run(state, self.llm, other_hour, ledger={})['status'], 'skipped')
        ledger = {'lastHour': '2026-11-27T09', 'hashes': {}}
        self.assertEqual(llm_tags.run(state, self.llm, now, ledger=ledger)['status'], 'skipped')

    def test_run_applies_llm_tags_merged_with_curated_tags_and_updates_ledger(self):
        state = {'tasks': [{'id': 'a', 'title': 'Buy milk', 'tags': ['home'], 'archived': False}]}
        ledger = {'hashes': {}}
        applied = []
        result = llm_tags.run(
            state, self.llm, datetime(2026, 11, 27, 9, 30), ledger=ledger,
            call_model=lambda model, prompt: '[{"id":"a","tags":["milk","errands"]}]',
            apply_tags=lambda item_id, values: applied.append((item_id, values)),
        )
        self.assertEqual(result['status'], 'ok')
        self.assertEqual(result['processed'], 1)
        self.assertEqual(applied, [('a', ['home', 'milk', 'errands'])])
        self.assertEqual(ledger['lastHour'], '2026-11-27T09')
        self.assertEqual(ledger['hashes']['a'], llm_tags.title_hash('Buy milk'))

    def test_shell_apply_pads_the_ipc_arguments(self):
        calls = []
        with patch.object(llm_tags.api, 'shell_live', return_value=True), \
             patch.object(llm_tags.subprocess, 'run', side_effect=lambda *a, **kw: calls.append((a, kw))):
            llm_tags.shell_apply('abc', ['milk', 'errands'])
        self.assertEqual(calls[0][0][0],
                         ['omarchy-shell', 'saturn', 'data', 'set-tags', 'abc', 'milk,errands', '', ''])
        self.assertTrue(calls[0][1]['capture_output'])

    def test_run_keeps_ledger_unchanged_when_the_model_fails(self):
        state = {'tasks': [{'id': 'a', 'title': 'Buy milk', 'tags': [], 'archived': False}]}
        ledger = {'hashes': {}}
        result = llm_tags.run(
            state, self.llm, datetime(2026, 11, 27, 9, 30), ledger=ledger,
            call_model=lambda model, prompt: (_ for _ in ()).throw(RuntimeError('offline')),
            apply_tags=lambda item_id, values: self.fail('should not apply after a model failure'),
        )
        self.assertEqual(result['status'], 'error')
        self.assertEqual(ledger, {'hashes': {}})


class LlmTagsWiringTest(unittest.TestCase):
    def test_cli_exposes_the_scheduled_pass(self):
        root = Path(__file__).resolve().parent.parent
        launcher = (root / 'bin' / 'saturn').read_text()
        self.assertIn('tags)', launcher)
        self.assertIn('llm_tags.py', launcher)
        self.assertIn('tags [run|status]', launcher)

    def test_install_registers_an_hourly_timer(self):
        root = Path(__file__).resolve().parent.parent
        installer = (root / 'scripts' / 'install-desktop.sh').read_text()
        self.assertIn('saturn-llm-tags.timer', installer)
        self.assertIn('OnCalendar=hourly', installer)
        self.assertIn('saturn tags run', installer)


if __name__ == '__main__':
    unittest.main()
