"""Small, explicit desktop context shared by the local and Grok assistants."""
from datetime import datetime
import json
import math
import os
from pathlib import Path
import urllib.parse
import urllib.request

LOCATION_FILE = Path.home()/'.local/state/omarchy/settings/weather.json'


def saved_location():
    try:
        data = json.loads(LOCATION_FILE.read_text())
        name = data['name']
        lat, lon = data['latitude'], data['longitude']
        if not isinstance(name, str) or not name.strip() or len(name) > 160:
            return None
        if type(lat) not in (int, float) or type(lon) not in (int, float):
            return None
        if not math.isfinite(lat) or not math.isfinite(lon) or not -90 <= lat <= 90 or not -180 <= lon <= 180:
            return None
        # City-level context only. This is the user's saved weather location,
        # not a claim of live GPS position.
        return {'name': name.strip(), 'latitude': round(lat, 2), 'longitude': round(lon, 2),
                'source': 'Omarchy saved weather location'}
    except (OSError, ValueError, TypeError, KeyError):
        return None


def desktop_context():
    return {'local_time': datetime.now().astimezone().isoformat(), 'weather_location': saved_location()}


def local_weather():
    place = saved_location()
    if not place:
        return {'ok': False, 'error': 'No weather location is saved. Ask which city to use.'}
    query = urllib.parse.urlencode({
        'latitude': place['latitude'], 'longitude': place['longitude'],
        'current': 'temperature_2m,apparent_temperature,weather_code,wind_speed_10m',
        'daily': 'temperature_2m_max,temperature_2m_min,precipitation_probability_max',
        'temperature_unit': 'fahrenheit', 'wind_speed_unit': 'mph',
        'timezone': 'auto', 'forecast_days': 2})
    url = 'https://api.open-meteo.com/v1/forecast?'+query
    try:
        with urllib.request.urlopen(url, timeout=6) as response:
            data = json.loads(response.read(100000))
        if not isinstance(data.get('current'), dict) or data['current'].get('temperature_2m') is None:
            raise ValueError()
        observed = datetime.fromisoformat(data['current']['time'])
        offset = data.get('utc_offset_seconds', 0)
        if type(offset) not in (int, float):
            raise ValueError()
        from datetime import timezone, timedelta
        observed = observed.replace(tzinfo=timezone(timedelta(seconds=offset)))
        if abs((datetime.now(timezone.utc)-observed).total_seconds()) > 10800:
            raise ValueError()
        return {'ok': True, 'location': place['name'], 'source': 'Open-Meteo', 'source_url': url,
                'timezone': data.get('timezone'), 'current': data['current'],
                'current_units': data.get('current_units'), 'daily': data.get('daily'),
                'daily_units': data.get('daily_units'), 'fetched_at': datetime.now().astimezone().isoformat()}
    except (OSError, ValueError, TypeError, KeyError):
        return {'ok': False, 'location': place['name'],
                'error': 'Current weather could not be verified. Try web_search for this location.'}
