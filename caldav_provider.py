"""Minimal CalDAV adapter for cPanel-style calendar servers (stdlib only).

JSON lines in/out. Credentials stay in ~/.config/saturn/connections/caldav.json.
"""
import base64
import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.parse as url
import urllib.request
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

MAX_BYTES = 4_194_304


class CaldavError(Exception):
    pass


def config_path():
    return (Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) /
            'saturn' / 'connections' / 'caldav.json')


def settings(args):
    endpoint = str(args.get('url', '')).strip()
    parsed = url.urlparse(endpoint)
    if parsed.scheme != 'https' or not parsed.netloc:
        raise CaldavError('Use an HTTPS CalDAV URL, for example https://mail.example.com/caldav/')
    username = str(args.get('username', '')).strip()
    password = str(args.get('password', ''))
    if not username or not password:
        raise CaldavError('Enter your CalDAV username and app password.')
    return {'url': endpoint.rstrip('/') + '/', 'username': username[:320], 'password': password[:512]}


def request(config, method, path='', body=None, etag=None):
    base = url.urlparse(config['url'])
    target = url.urljoin(config['url'], path)
    parsed = url.urlparse(target)
    if (parsed.scheme != 'https' or parsed.netloc != base.netloc or
            not parsed.path.startswith(base.path) or parsed.query or parsed.fragment or
            parsed.username or parsed.password):
        raise CaldavError('Event URL is outside the configured calendar.')
    auth = base64.b64encode(f"{config['username']}:{config['password']}".encode()).decode()
    headers = {'Authorization': 'Basic ' + auth, 'User-Agent': 'Saturn/0.8 CalDAV'}
    if body is not None:
        headers['Content-Type'] = 'text/calendar; charset=utf-8'
    if method == 'PROPFIND':
        headers['Depth'] = '1'
        headers['Content-Type'] = 'application/xml; charset=utf-8'
    if etag:
        headers['If-Match'] = etag
    req = urllib.request.Request(target, data=body.encode() if body is not None else None,
                                 headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=25) as response:
            raw = response.read(MAX_BYTES + 1)
            if len(raw) > MAX_BYTES:
                raise CaldavError('Calendar response was too large.')
            return response.status, raw.decode('utf-8', 'replace'), dict(response.headers)
    except urllib.error.HTTPError as error:
        if error.code in (401, 403):
            raise CaldavError('CalDAV sign-in failed. Check your username and app password.') from None
        if error.code == 404:
            raise CaldavError('CalDAV URL not found. Check the endpoint from your cPanel account.') from None
        raise CaldavError(f'CalDAV request failed ({error.code}).') from None
    except (OSError, ValueError):
        raise CaldavError('Could not reach the CalDAV server. Check the URL and connection.') from None


def check(config):
    request(config, 'OPTIONS')
    return {'ok': True, 'connected': True}


def parse_time(value, timezone=None):
    value = (value or '').strip()
    if not value:
        return None
    if len(value) == 8 and value.isdigit():
        return dt.datetime.strptime(value, '%Y%m%d').replace(tzinfo=dt.timezone.utc), True
    match = re.match(r'^(\d{8})T(\d{6})(Z)?$', value)
    if not match:
        return None
    text = f'{match.group(1)}T{match.group(2)}' + ('+00:00' if match.group(3) else '')
    try:
        parsed = dt.datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        try:
            zone = ZoneInfo(timezone) if timezone else dt.timezone.utc
        except ZoneInfoNotFoundError:
            return None
        parsed = parsed.replace(tzinfo=zone)
    return parsed, False


def unfold(text):
    return re.sub(r'\r?\n[ \t]', '', text)


def parse_ics(text):
    event = {}
    in_event = False
    for line in unfold(text).splitlines():
        if line == 'BEGIN:VEVENT':
            in_event = True
        elif line == 'END:VEVENT':
            break
        elif not in_event:
            continue
        key, _, value = line.partition(':')
        name = key.split(';')[0]
        if name == 'SUMMARY':
            event['title'] = value[:256]
        elif name == 'UID':
            event['uid'] = value[:200]
        elif name in ('DTSTART', 'DTEND'):
            zone = re.search(r'(?:^|;)TZID=([^;:]+)', key, re.I)
            parsed = parse_time(value, zone.group(1).strip('"') if zone else None)
            if parsed:
                event[name.lower()] = parsed[0]
                if name == 'DTSTART':
                    event['all_day'] = parsed[1]
        elif name == 'STATUS' and value.upper() == 'CANCELLED':
            event['cancelled'] = True
    if event.get('cancelled') or not event.get('uid') or not event.get('dtstart'):
        return None
    event['dtend'] = event.get('dtend') or event['dtstart'] + dt.timedelta(hours=1)
    return event


def sync(config, days=8):
    status, listing, _ = request(config, 'PROPFIND', body=(
        '<?xml version="1.0"?><D:propfind xmlns:D="DAV:"><D:prop><D:getetag/></D:prop></D:propfind>'),
    )
    if status not in (200, 207):
        raise CaldavError('Could not list calendar events.')
    try:
        document = ET.fromstring(listing)
        resources = [(response.findtext('{DAV:}href'),
                      response.findtext('.//{DAV:}getetag'))
                     for response in document.findall('.//{DAV:}response')]
    except ET.ParseError:
        raise CaldavError('Invalid calendar listing from the server.') from None
    events = []
    limit = 200
    for raw_href, etag in resources:
        if len(events) >= limit:
            break
        if not raw_href:
            continue
        href = url.unquote(raw_href)
        if url.urlparse(href).path.rstrip('/') == url.urlparse(config['url']).path.rstrip('/'):
            continue
        _, text, _ = request(config, 'GET', path=href)
        item = parse_ics(text)
        if not item:
            continue
        start, end = item['dtstart'], item['dtend']
        if end.date() < dt.datetime.now(dt.timezone.utc).date():
            continue
        if start.date() > dt.datetime.now(dt.timezone.utc).date() + dt.timedelta(days=days):
            continue
        events.append({'uid': item['uid'], 'href': href, 'etag': etag,
                       'title': item.get('title', '(Untitled event)'),
                       'start': start.astimezone(dt.timezone.utc).isoformat(),
                       'end': end.astimezone(dt.timezone.utc).isoformat(),
                       'all_day': bool(item.get('all_day')), 'calendar': 'CalDAV'})
    return {'events': events, 'connected': True}


def to_ics(event):
    def stamp(value):
        parsed = dt.datetime.fromisoformat(str(value).replace('Z', '+00:00'))
        return parsed.astimezone(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    uid = str(event.get('externalId') or uuid.uuid4().hex)[:200]
    title = str(event.get('title') or 'Untitled')[0:256].replace('\\', '\\\\').replace(',', '\\,').replace(';', '\\;').replace('\n', '\\n')
    return '\r\n'.join(['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Saturn//CalDAV//EN',
                        'BEGIN:VEVENT', 'UID:' + uid,
                        'DTSTAMP:' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ'),
                        'DTSTART:' + stamp(event.get('start')),
                        'DTEND:' + stamp(event.get('end') or event.get('start')),
                        'SUMMARY:' + title, 'END:VEVENT', 'END:VCALENDAR', ''])


def write_event(config, event, create=True):
    uid = str(event.get('externalId') or uuid.uuid4().hex)[:200]
    path = (uid + '.ics') if create else event.get('href')
    if not path:
        raise CaldavError('Calendar event has no resource URL; refresh before editing.')
    if create:
        status, _, headers = request(config, 'PUT', path=path, body=to_ics(dict(event, externalId=uid)))
    else:
        status, _, headers = request(config, 'PUT', path=path, body=to_ics(event), etag=event.get('etag'))
    if status not in (200, 201, 204):
        raise CaldavError('The calendar rejected the event.')
    return {'ok': True, 'externalId': uid,
            'href': url.urlparse(url.urljoin(config['url'], path)).path,
            'etag': headers.get('ETag')}


def delete_event(config, event):
    uid = str(event.get('externalId') or '')
    if not uid:
        raise CaldavError('This event has no external id.')
    status, _, _ = request(config, 'DELETE', path=uid + '.ics', etag=event.get('etag'))
    if status not in (200, 204):
        raise CaldavError('The calendar rejected the deletion.')
    return {'ok': True, 'externalId': uid}


def run(args):
    action = args.get('action')
    if action == 'connect':
        config = settings(args)
        config.update(check(config))
        return config
    config = json.loads(config_path().read_text()) if config_path().exists() else {}
    if not config.get('url'):
        raise CaldavError('Connect a CalDAV calendar in Connections first.')
    if action == 'sync':
        return sync(config, int(args.get('days', 8)))
    if action == 'create':
        return write_event(config, args, True)
    if action == 'update':
        return write_event(config, args, False)
    if action == 'delete':
        return delete_event(config, args)
    raise CaldavError('Unknown CalDAV action.')
