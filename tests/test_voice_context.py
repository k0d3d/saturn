import json
from datetime import datetime, timezone
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import voice_context as context
import grok_voice as grok


class VoiceContextTests(unittest.TestCase):
    def test_saved_location_is_shared_and_rounded(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'weather.json'
            path.write_text('{"name":"Danvers","latitude":42.57509,"longitude":-70.93005}')
            with patch.object(context, 'LOCATION_FILE', path):
                place = context.saved_location()
                self.assertEqual(place['name'], 'Danvers')
                self.assertEqual(place['latitude'], 42.58)
                instructions = grok.session_config()['session']['instructions']
                self.assertIn('Danvers', instructions)
                self.assertIn('local_time', instructions)
                self.assertNotIn('42.57509', instructions)

    def test_invalid_or_missing_location_never_guesses_a_city(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'weather.json'
            with patch.object(context, 'LOCATION_FILE', path):
                self.assertIsNone(context.saved_location())
                for data in ('[]', 'null', 'broken', '{"name":"City","latitude":true,"longitude":0}',
                             '{"name":"City","latitude":91,"longitude":0}',
                             '{"name":"City","latitude":NaN,"longitude":0}'):
                    path.write_text(data)
                    self.assertIsNone(context.saved_location())

    def test_weather_returns_fresh_data_and_units(self):
        place = {'name': 'Danvers', 'latitude': 42.58, 'longitude': -70.93}
        data = {'current': {'time': datetime.now(timezone.utc).isoformat(), 'temperature_2m': 60},
                'utc_offset_seconds': 0, 'current_units': {'temperature_2m': '°F'}, 'daily': {}}
        response = MagicMock()
        response.__enter__.return_value.read.return_value = json.dumps(data).encode()
        with patch.object(context, 'saved_location', return_value=place), patch.object(context.urllib.request, 'urlopen', return_value=response) as fetch:
            result = context.local_weather()
        self.assertTrue(result['ok'])
        self.assertEqual(result['location'], 'Danvers')
        self.assertIn('temperature_unit=fahrenheit', fetch.call_args.args[0])

    def test_stale_weather_is_not_reported_as_current(self):
        response = MagicMock()
        response.__enter__.return_value.read.return_value = b'{"current":{"time":"2000-01-01T12:00","temperature_2m":60}}'
        with patch.object(context, 'saved_location', return_value={'name':'Danvers','latitude':42.58,'longitude':-70.93}), patch.object(context.urllib.request, 'urlopen', return_value=response):
            result = context.local_weather()
        self.assertFalse(result['ok'])
        self.assertNotIn('current', result)


if __name__ == '__main__':
    unittest.main()
