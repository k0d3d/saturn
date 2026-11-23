from contextlib import redirect_stdout
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


calendar = load('calendar_sync', ROOT / 'scripts' / 'calendar_sync.py')
caldav = load('caldav_provider', ROOT / 'caldav_provider.py')


class CalendarSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='saturn-calendar-')
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        workspace = base / 'saturn' / 'workspace.json'
        workspace.parent.mkdir(parents=True)
        workspace.write_text(json.dumps({
            'version': 2, 'tasks': [], 'notes': {}, 'notesV2': [], 'events': [], 'activity': {},
            'focus': {'title': 'Open focus', 'duration': 1500, 'elapsed': 0, 'running': False},
            'sync': {'providers': {}, 'conflicts': [], 'tombstones': []}, 'insights': {},
            'calendarSource': 'caldav',
        }))
        self.workspace = workspace
        self.patches = [patch.object(calendar, 'WORKSPACE', workspace)]
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)

    def call(self, mode):
        stream = io.StringIO()
        with redirect_stdout(stream):
            calendar.main([mode])
        return json.loads(stream.getvalue())

    def state(self):
        return json.loads(self.workspace.read_text())

    def test_pull_creates_local_events_from_caldav(self):
        feed = {'events': [{'uid': 'uid-1', 'title': 'Dentist', 'start': '2026-11-24T09:00:00Z',
                            'end': '2026-11-24T10:00:00Z', 'all_day': False}]}
        with patch.object(calendar, 'provider_call', return_value=feed) as call:
            result = self.call('sync')
        self.assertEqual(result['pulled'], 1)
        self.assertEqual(call.call_args_list[0].args, ('caldav', 'sync'))
        local = self.state()['events'][0]
        self.assertEqual(local['externalId'], 'uid-1')
        self.assertEqual(local['source'], 'caldav')

    def test_local_event_is_pushed_to_provider(self):
        state = self.state()
        state['events'] = [{'id': 'local-1', 'title': 'Launch', 'start': 1795500000000,
                            'end': 1795503600000, 'all_day': False, 'source': 'local',
                            'externalId': None, 'archived': False, 'createdAt': 1, 'updatedAt': 1}]
        self.workspace.write_text(json.dumps(state))
        with patch.object(calendar, 'provider_call', return_value={'events': []}) as call:
            result = self.call('sync')
        self.assertEqual(result['pushed'], 1)
        self.assertTrue(any(c.args[1] == 'create' for c in call.call_args_list))
        self.assertEqual(self.state()['events'][0]['source'], 'caldav')

    def test_status_is_read_only(self):
        before = self.workspace.read_text()
        result = self.call('status')
        self.assertEqual(result['source'], 'caldav')
        self.assertEqual(self.workspace.read_text(), before)

    def test_ics_parsing_handles_utc_and_all_day(self):
        ics = 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:abc\r\nSUMMARY:Trip\r\nDTSTART;VALUE=DATE:20261125\r\nDTEND;VALUE=DATE:20261126\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n'
        event = caldav.parse_ics(ics)
        self.assertEqual(event['uid'], 'abc')
        self.assertEqual(event['title'], 'Trip')
        self.assertTrue(event['all_day'])

    def test_caldav_settings_require_https(self):
        with self.assertRaises(caldav.CaldavError):
            caldav.settings({'url': 'http://mail.example.com/caldav', 'username': 'a', 'password': 'b'})
        config = caldav.settings({'url': 'https://mail.example.com/caldav/', 'username': 'me@example.com', 'password': 'secret'})
        self.assertEqual(config['url'], 'https://mail.example.com/caldav/')


if __name__ == '__main__':
    unittest.main()
