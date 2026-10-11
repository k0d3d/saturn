"""Local unread feeds and explicit per-conversation read actions. Content lives only in memory and stdout."""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import re
import urllib.error
import urllib.parse
import urllib.request


class FeedError(Exception):
    pass


def config_path():
    return Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'omaowl' / 'beeper.json'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise FeedError('Beeper redirected the local request. Check its API settings.')


def beeper_request(path, token, body=None):
    # Fixed loopback origin; never send the credential through a proxy or redirect.
    request = urllib.request.Request('http://127.0.0.1:23373' + path,
        data=None if body is None else json.dumps(body).encode(),
        headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(request, timeout=4) as response:
            data = response.read(8 * 1024 * 1024 + 1)
        if len(data) > 8 * 1024 * 1024:
            raise FeedError('Beeper returned too much data.')
        return json.loads(data)
    except urllib.error.HTTPError as error:
        if error.code in (401, 403):
            raise FeedError('Beeper rejected the token. Reconnect in Connections.') from None
        raise FeedError('Beeper could not complete the request.') from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise FeedError('Open Beeper and enable its Desktop API on port 23373.') from None


def token_value():
    try:
        return json.loads(config_path().read_text()).get('token', '')
    except (OSError, ValueError):
        return ''


def save_token(token):
    if not isinstance(token, str) or not token.strip() or len(token) > 8192 or '\n' in token or '\r' in token:
        raise FeedError('Enter a valid Beeper Desktop API token.')
    token = token.strip()
    beeper_request('/v1/chats?limit=1', token)
    path = config_path()
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.beeper-')
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump({'token': token}, stream)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def beeper_row(chat):
    unread = max(0, int(chat.get('unreadCount') or 0))
    if not chat.get('id') or (not unread and not chat.get('isMarkedUnread')) or chat.get('mergedIntoChatID'):
        return None
    preview = chat.get('preview') or {}
    return {'id': str(chat['id']), 'source': 'beeper', 'network': str(chat.get('network') or 'Beeper'),
        'name': str(chat.get('title') or 'Conversation'), 'preview': str(preview.get('text') or 'Open conversation')[:500],
        'timestamp': str(chat.get('lastActivity') or preview.get('timestamp') or ''), 'unread': max(1, unread),
        'messageId': str(preview.get('id') or '')}


def beeper_feed():
    token = token_value()
    if not token:
        return {'connected': False, 'rows': [], 'error': 'Connect Beeper in Connections to include Slack and your other chats.'}
    rows, seen, cursors = [], set(), set()
    cursor = ''
    for _ in range(10):
        query = {'limit': 200}
        if cursor:
            query.update(cursor=cursor, direction='before')
        page = beeper_request('/v1/chats?' + urllib.parse.urlencode(query), token)
        for chat in page.get('items', []):
            row = beeper_row(chat)
            if row and row['id'] not in seen:
                rows.append(row)
                seen.add(row['id'])
        if not page.get('hasMore'):
            return {'connected': True, 'rows': rows, 'error': ''}
        cursor = page.get('oldestCursor')
        if not cursor or cursor in cursors:
            break
        cursors.add(cursor)
    return {'connected': True, 'rows': rows, 'error': 'Showing unread chats among the first 2,000 recent conversations; more may remain.'}


def blip_ipc(method, *args):
    try:
        result = subprocess.run(['qs', '-p', '/usr/share/omarchy/shell', 'ipc', 'call', 'nixfred.blip', method, *args],
            capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        raise FeedError('Blip is unavailable. Enable its Omarchy plugin.') from None
    if result.returncode:
        raise FeedError('Blip needs the updated preview/read bridge. See the connection guide.')
    return result.stdout.strip()


def blip_feed():
    response = json.loads(blip_ipc('previews'))
    if not response.get('enabled'):
        raise FeedError('Enable pulse_previews=on in Blip’s bridge.conf for unread previews.')
    return {'connected': True, 'rows': response.get('rows', []),
        'error': '' if response.get('online') else 'Blip’s Mac bridge is offline. These previews may be out of date.'}


def safe_feed(fetch):
    try:
        return fetch()
    except FeedError as error:
        return {'connected': False, 'rows': [], 'error': str(error)}
    except (ValueError, TypeError, KeyError):
        return {'connected': False, 'rows': [], 'error': 'Could not read the message provider response.'}


def blip_read_saved(chat, seen):
    # Blip's metadata ledger contains read watermarks, never message bodies.
    try:
        state = json.loads((Path.home() / '.local/state/blip/state.json').read_text())
        return max(state.get('readMark', ''), state.get('readMarks', {}).get(chat, '')) >= seen
    except (OSError, ValueError, TypeError):
        return False


def mark_read(request, chat):
    if request.get('source') == 'blip':
        seen = request.get('timestamp', '')
        if not isinstance(seen, str) or not re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z', seen):
            raise FeedError('Refresh this conversation before marking it read.')
        result = json.loads(blip_ipc('pulseRead', chat, seen))
        if not result.get('ok'):
            raise FeedError(result.get('error') or 'Blip could not mark this conversation read.')
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if blip_read_saved(chat, seen):
                return {'ok': True, 'remove': True}
            time.sleep(0.2)
        raise FeedError('Blip has not confirmed the read change yet. Refresh to check or retry.')
    if request.get('source') == 'beeper':
        message_id = request.get('messageId', '')
        if not isinstance(message_id, str) or not message_id or len(message_id) > 1024:
            raise FeedError('This preview has no message ID. Open it in Beeper to mark it read.')
        result = beeper_request('/v1/chats/' + urllib.parse.quote(chat, safe='') + '/read', token_value(), {'messageID': message_id})
        if result.get('id') != chat or 'unreadCount' not in result:
            raise FeedError('Beeper did not confirm the read change. Refresh to check.')
        return {'ok': True, 'remove': result['unreadCount'] == 0 and not result.get('isMarkedUnread', False)}
    raise FeedError('Unknown message source.')


def dispatch(request):
    action = request.get('action', 'sync')
    if action == 'sync':
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            blip = pool.submit(safe_feed, blip_feed) if request.get('blipEnabled', True) is True else None
            beeper = pool.submit(safe_feed, beeper_feed) if request.get('beeperEnabled', False) is True else None
            disabled={'connected':False,'rows':[],'error':''}
            return {'ok': True, 'blip': blip.result() if blip else disabled, 'beeper': beeper.result() if beeper else disabled, 'beeperConfigured': bool(token_value())}
    if action == 'connect':
        save_token(request.get('token'))
        return {'ok': True, 'beeperConfigured': True}
    if action == 'disconnect':
        config_path().unlink(missing_ok=True)
        return {'ok': True, 'beeperConfigured': False}
    if action in ('open', 'read'):
        chat = request.get('id', '')
        if not isinstance(chat, str) or not chat or len(chat) > 1024 or any(ord(c) < 32 for c in chat):
            raise FeedError('Invalid conversation.')
        if action == 'read':
            return mark_read(request, chat)
        if request.get('source') == 'blip':
            if blip_ipc('goto', chat) != 'shown':
                raise FeedError('Blip could not open this conversation. Refresh and try again.')
        elif request.get('source') == 'beeper':
            if not beeper_request('/v1/focus', token_value(), {'chatID': chat}).get('success'):
                raise FeedError('Beeper could not open this conversation.')
        else:
            raise FeedError('Unknown message source.')
        return {'ok': True}
    raise FeedError('Unknown message action.')


if __name__ == '__main__':
    try:
        result = dispatch(json.loads(sys.stdin.readline(16384)))
    except FeedError as error:
        result = {'ok': False, 'error': str(error)}
    except Exception:
        result = {'ok': False, 'error': 'Message connection failed. Check Connections and try again.'}
    print(json.dumps(result))
