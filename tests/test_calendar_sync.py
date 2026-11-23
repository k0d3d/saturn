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
        with patch.object(calendar, 'provider_call', side_effect=[
                {'events': []}, {'ok': True, 'externalId': 'new-uid'}]) as call:
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

    def test_google_feed_uses_stable_provider_id(self):
        row = {'id': 'google-123', 'title': 'Planning', 'start_ms': 1795500000000,
               'end_ms': 1795503600000, 'all_day': False}
        result = calendar.normalize('google-calendar', {'events': [row]})
        self.assertEqual(result[0]['externalId'], 'google-123')

    def test_local_edit_updates_remote_once(self):
        state = self.state()
        state['events'] = [{'id': 'e1', 'title': 'Changed', 'start': 1795500000000,
                            'end': 1795503600000, 'source': 'caldav', 'externalId': 'uid-1',
                            'updatedAt': 200, 'createdAt': 1, 'archived': False}]
        state['sync']['calendar'] = {'base': {'e1': {'title': 'Original', 'start': 1795500000000,
                                                    'end': 1795503600000}}}
        self.workspace.write_text(json.dumps(state))
        feed = {'events': [{'uid': 'uid-1', 'title': 'Original', 'start': '2026-11-24T05:00:00Z',
                            'end': '2026-11-24T06:00:00Z'}]}
        # Match the local timestamp precisely.
        feed['events'][0]['start'] = calendar.datetime.fromtimestamp(1795500000, calendar.timezone.utc).isoformat()
        feed['events'][0]['end'] = calendar.datetime.fromtimestamp(1795503600, calendar.timezone.utc).isoformat()
        def reply(provider, action, extra=None):
            return feed if action == 'sync' else {'ok': True, 'externalId': 'uid-1'}
        with patch.object(calendar, 'provider_call', side_effect=reply) as call:
            self.assertEqual(self.call('sync')['pushed'], 1)
            self.assertEqual(self.call('sync')['pushed'], 0)
        self.assertEqual([c.args[1] for c in call.call_args_list].count('update'), 1)

    def test_two_sided_change_keeps_local_and_logs_conflict(self):
        state = self.state()
        state['events'] = [{'id': 'e1', 'title': 'Mine', 'start': 1795500000000,
                            'end': 1795503600000, 'source': 'caldav', 'externalId': 'uid-1',
                            'updatedAt': 200, 'createdAt': 1, 'archived': False}]
        state['sync']['calendar'] = {'base': {'e1': {'title': 'Original', 'start': 1795500000000,
                                                    'end': 1795503600000}}}
        self.workspace.write_text(json.dumps(state))
        feed = {'events': [{'uid': 'uid-1', 'title': 'Theirs',
                            'start': calendar.datetime.fromtimestamp(1795500000, calendar.timezone.utc).isoformat(),
                            'end': calendar.datetime.fromtimestamp(1795503600, calendar.timezone.utc).isoformat()}]}
        with patch.object(calendar, 'provider_call', return_value=feed) as call:
            result = self.call('sync')
        self.assertEqual(result['conflicts'], 1)
        self.assertEqual(self.state()['events'][0]['title'], 'Mine')
        self.assertEqual(self.state()['sync']['conflicts'][0]['remote']['title'], 'Theirs')
        self.assertFalse(any(c.args[1] == 'update' for c in call.call_args_list))
        # A repeated sync must not duplicate the same conflict entry.
        with patch.object(calendar, 'provider_call', return_value=feed):
            self.call('sync')
        self.assertEqual(len(self.state()['sync']['conflicts']), 1)

    def test_editing_after_conflict_pushes_local_resolution(self):
        state = self.state()
        state['events'] = [{'id': 'e1', 'title': 'Mine', 'start': 1795500000000,
                            'end': 1795503600000, 'source': 'caldav', 'externalId': 'uid-1',
                            'updatedAt': 200, 'createdAt': 1, 'archived': False,
                            'syncConflict': {'local': {'title': 'Mine', 'start': 1795500000000,
                                                       'end': 1795503600000},
                                             'remote': {'title': 'Theirs', 'start': 1795500000000,
                                                        'end': 1795503600000}}}]
        state['sync']['calendar'] = {'base': {'e1': {'title': 'Original', 'start': 1795500000000,
                                                    'end': 1795503600000}}}
        self.workspace.write_text(json.dumps(state))
        state['events'][0]['title'] = 'Resolved'
        self.workspace.write_text(json.dumps(state))
        feed = {'events': [{'uid': 'uid-1', 'title': 'Theirs',
                            'start': calendar.datetime.fromtimestamp(1795500000, calendar.timezone.utc).isoformat(),
                            'end': calendar.datetime.fromtimestamp(1795503600, calendar.timezone.utc).isoformat()}]}
        with patch.object(calendar, 'provider_call', side_effect=[feed, {'ok': True}]):
            self.assertEqual(self.call('sync')['pushed'], 1)
        self.assertNotIn('syncConflict', self.state()['events'][0])

    def test_failed_provider_sync_reports_failure(self):
        with patch.object(calendar, 'provider_call', side_effect=RuntimeError('Offline')):
            result = self.call('sync')
        self.assertFalse(result['ok'])
        self.assertIn('Offline', result['error'])
        self.assertEqual(len(self.state()['sync']['calendar']['errors']), 1)

    def test_archiving_imported_event_does_not_delete_remote(self):
        state = self.state()
        state['events'] = [{'id': 'e1', 'title': 'Private', 'start': 1795500000000,
                            'end': 1795503600000, 'source': 'caldav', 'externalId': 'uid-1',
                            'updatedAt': 200, 'createdAt': 1, 'archived': True}]
        state['sync']['calendar'] = {'base': {'e1': {'title': 'Private', 'start': 1795500000000,
                                                    'end': 1795503600000}}}
        self.workspace.write_text(json.dumps(state))
        with patch.object(calendar, 'provider_call', return_value={'events': []}) as call:
            self.assertTrue(self.call('sync')['ok'])
        self.assertEqual([c.args[1] for c in call.call_args_list], ['sync'])

    def test_caldav_request_resolves_absolute_href_under_configured_origin(self):
        config = {'url': 'https://example.com/dav/calendars/me/work/', 'username': 'me', 'password': 'secret'}
        class Response:
            status = 200
            headers = {}
            def __enter__(self): return self
            def __exit__(self, *args): return False
            def read(self, count): return b'BEGIN:VCALENDAR\r\nEND:VCALENDAR'
        with patch.object(caldav.urllib.request, 'urlopen', return_value=Response()) as opener:
            caldav.request(config, 'GET', '/dav/calendars/me/work/one.ics')
        self.assertEqual(opener.call_args.args[0].full_url,
                         'https://example.com/dav/calendars/me/work/one.ics')
        with self.assertRaises(caldav.CaldavError):
            caldav.request(config, 'GET', 'https://evil.example/steal')

    def test_caldav_sync_preserves_href_and_etag(self):
        config = {'url': 'https://example.com/dav/work/', 'username': 'me', 'password': 'secret'}
        xml = ('<d:multistatus xmlns:d="DAV:"><d:response>'
               '<d:href>/dav/work/first.ics</d:href>'
               '<d:propstat><d:prop><d:getetag>"version-1"</d:getetag></d:prop></d:propstat>'
               '</d:response></d:multistatus>')
        ics = ('BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:uid-different-from-filename\r\n'
               'SUMMARY:Work\r\nDTSTART:20261124T090000Z\r\nDTEND:20261124T100000Z\r\n'
               'END:VEVENT\r\nEND:VCALENDAR\r\n')
        with patch.object(caldav, 'request', side_effect=[(207, xml, {}), (200, ics, {})]) as req:
            with patch.object(caldav.dt, 'datetime', wraps=caldav.dt.datetime) as clock:
                clock.now.return_value = caldav.dt.datetime(2026, 11, 23, tzinfo=caldav.dt.timezone.utc)
                result = caldav.sync(config)
        self.assertEqual(result['events'][0]['href'], '/dav/work/first.ics')
        self.assertEqual(result['events'][0]['etag'], '"version-1"')
        self.assertEqual(req.call_args_list[1].kwargs['path'], '/dav/work/first.ics')

    def test_caldav_update_uses_href_and_etag(self):
        config = {'url': 'https://example.com/dav/work/', 'username': 'me', 'password': 'secret'}
        event = {'externalId': 'different-uid', 'href': '/dav/work/first.ics',
                 'etag': '"version-1"', 'title': 'Updated',
                 'start': '2026-11-24T09:00:00Z', 'end': '2026-11-24T10:00:00Z'}
        with patch.object(caldav, 'request', return_value=(204, '', {})) as req:
            caldav.write_event(config, event, create=False)
        self.assertEqual(req.call_args.kwargs['path'], '/dav/work/first.ics')
        self.assertEqual(req.call_args.kwargs['etag'], '"version-1"')

    def test_caldav_tzid_uses_named_timezone(self):
        event = caldav.parse_ics('BEGIN:VEVENT\r\nUID:one\r\nSUMMARY:Morning\r\n'
                                 'DTSTART;TZID=America/New_York:20261124T090000\r\n'
                                 'DTEND;TZID=America/New_York:20261124T100000\r\nEND:VEVENT\r\n')
        self.assertEqual(event['dtstart'].isoformat(), '2026-11-24T09:00:00-05:00')

    def test_caldav_import_preserves_resource_identity_for_updates(self):
        row = {'uid': 'uid-1', 'href': '/dav/work/some-file.ics', 'etag': '"v1"',
               'title': 'Meeting', 'start': '2026-11-24T09:00:00Z',
               'end': '2026-11-24T10:00:00Z'}
        normalized = calendar.normalize('caldav', {'events': [row]})[0]
        self.assertEqual(calendar.remote_payload(normalized)['href'], row['href'])
        self.assertEqual(calendar.remote_payload(normalized)['etag'], row['etag'])


if __name__ == '__main__':
    unittest.main()
