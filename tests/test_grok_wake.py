import asyncio
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import AsyncMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import grok_wake as wake
import grok_voice as grok


class Recognizer:
    def __init__(self, *args):
        pass
    def Reset(self):
        pass
    def AcceptWaveform(self, data):
        return False
    def PartialResult(self):
        return json.dumps({'partial':'hey saturn'})


class WakeTests(unittest.IsolatedAsyncioTestCase):
    def test_omarchy_lock_screen_counts_as_locked(self):
        import pulse_voice
        from types import SimpleNamespace
        answers = {'loginctl': 'no\n', 'omarchy-shell': 'true\n'}
        def run(args, **kwargs):
            return SimpleNamespace(returncode=0, stdout=answers[args[0]])
        with patch.object(pulse_voice.subprocess, 'run', side_effect=run), patch.object(pulse_voice.shutil, 'which', return_value='/usr/bin/omarchy-shell'):
            self.assertFalse(pulse_voice.unlocked())
            answers['omarchy-shell'] = 'false\n'
            self.assertTrue(pulse_voice.unlocked())
            answers['loginctl'] = 'yes\n'
            self.assertFalse(pulse_voice.unlocked())

    async def test_confirmed_wake_keeps_the_command_audio(self):
        capture = wake.WakeCapture(None, Recognizer)
        for data in [b'wake', *[b'tail']*6, b'question']:
            capture.queue.put_nowait(data)
        with patch.object(wake, 'unlocked', return_value=True), patch.object(wake, 'dictation_busy', return_value=False), patch.object(wake, 'playback_active', return_value=False), patch.object(wake, 'transcribe', return_value='Hey Saturn, what is the weather?'), patch.object(wake, 'emit') as output:
            self.assertTrue(await capture.wait(asyncio.Event()))
        self.assertIn('wake', [call.args[0] for call in output.call_args_list])
        self.assertEqual(await capture.finish(), b'wake'+b'tail'*6+b'question')
        self.assertEqual(await capture.finish(), b'')

    async def test_unconfirmed_wake_never_opens_grok(self):
        capture = wake.WakeCapture(None, Recognizer)
        for _ in range(7):
            capture.queue.put_nowait(b'audio')
        stopped = asyncio.Event()
        def reject(*args, **kwargs):
            stopped.set()
            return 'Hey Paul'
        with patch.object(wake, 'unlocked', return_value=True), patch.object(wake, 'dictation_busy', return_value=False), patch.object(wake, 'playback_active', return_value=False), patch.object(wake, 'transcribe', side_effect=reject), patch.object(wake, 'emit') as output:
            self.assertFalse(await capture.wait(stopped))
        self.assertNotIn('wake', [call.args[0] for call in output.call_args_list])
        self.assertEqual(await capture.finish(), b'')

    async def test_false_alarm_does_not_swallow_the_real_wake_phrase(self):
        class Hears(Recognizer):
            def AcceptWaveform(self, data):
                self.last = data; return False
            def PartialResult(self):
                return json.dumps({'partial': 'hey saturn' if self.last in (b'noise', b'wake') else ''})
        capture = wake.WakeCapture(None, Hears)
        for data in [b'noise', b'wake', *[b'tail']*6, b'question']:
            capture.queue.put_nowait(data)
        heard = []
        def check(pcm, **kwargs):
            heard.append(pcm)
            return 'Hey Saturn, open Slack.' if len(heard) == 2 else 'Okay, let me check.'
        with patch.object(wake, 'unlocked', return_value=True), patch.object(wake, 'dictation_busy', return_value=False), patch.object(wake, 'playback_active', return_value=False), patch.object(wake, 'transcribe', side_effect=check), patch.object(wake, 'emit'):
            self.assertTrue(await capture.wait(asyncio.Event()))
        self.assertTrue(heard[1].startswith(b'noisewake'))
        self.assertIn(b'question', await capture.finish())

    async def test_wake_phrase_is_found_after_earlier_speech(self):
        self.assertTrue(wake.wake_spoken('be fine for tomorrow. Hey Saturn, open Slack'))
        self.assertTrue(wake.wake_spoken('Hey, polls.'))
        self.assertFalse(wake.wake_spoken('Hey Paul, open Slack'))
        self.assertFalse(wake.wake_spoken('check my saturn'))

    async def test_key_press_starts_a_conversation_without_the_phrase(self):
        class Silent(Recognizer):
            def PartialResult(self):
                return json.dumps({'partial': ''})
        capture = wake.WakeCapture(None, Silent)
        forced = asyncio.Event(); forced.set()
        with patch.object(wake, 'unlocked', return_value=True), patch.object(wake, 'dictation_busy', return_value=False), patch.object(wake, 'playback_active', return_value=True), patch.object(wake, 'emit') as output:
            self.assertTrue(await capture.wait(asyncio.Event(), forced))
        self.assertIn('wake', [call.args[0] for call in output.call_args_list])
        self.assertFalse(forced.is_set())

    async def test_wake_session_uses_correct_pcm_rate(self):
        session = grok.Session(None, input_rate=16000, wake_capture=object())
        config = grok.session_config(session.input_rate)['session']
        self.assertEqual(config['audio']['input']['format']['rate'], 16000)
        self.assertEqual(config['audio']['output']['format']['rate'], 24000)
        self.assertEqual(config['voice'], 'ara')

    async def test_wake_idle_rearms_instead_of_disabling_microphone(self):
        session = grok.Session(None, wake_capture=object())
        with patch.object(grok, 'unlocked', return_value=False), patch.object(grok, 'emit') as output:
            await session.guard()
        self.assertTrue(session.stop.is_set())
        self.assertFalse(session.end_requested)
        self.assertEqual(output.call_args.args[0], 'session_idle')

    async def test_ending_the_conversation_rearms_wake_listening(self):
        session = grok.Session(None, wake_capture=object())
        with patch.object(grok, 'emit') as output:
            await session.tool({'name': 'end_session', 'call_id': 'c1', 'arguments': '{}'})
        self.assertTrue(session.stop.is_set())
        self.assertFalse(session.end_requested)
        self.assertEqual(output.call_args.args[0], 'session_idle')

    async def test_failed_conversation_keeps_wake_listening(self):
        waits = []
        class Capture:
            def __init__(self, *args): pass
            async def start(self): pass
            async def wait(self, stopped, forced=None):
                waits.append(1)
                return len(waits) < 3
            async def finish(self): return b''
        class Connection:
            async def __aenter__(self): raise OSError('network down')
            async def __aexit__(self, *args): pass
        modules = {'vosk': type(sys)('vosk'), 'websockets.asyncio.client': type(sys)('client')}
        modules['vosk'].Model = lambda path: object()
        modules['vosk'].KaldiRecognizer = Recognizer
        modules['vosk'].SetLogLevel = lambda level: None
        modules['websockets.asyncio.client'].connect = lambda *args, **kwargs: Connection()
        loop = asyncio.get_running_loop()
        async def no_stdin(*args): raise OSError()
        async def no_delay(awaitable, timeout):
            awaitable.close()
            raise asyncio.TimeoutError()
        with patch.dict(sys.modules, modules), patch.object(wake, 'WakeCapture', Capture), \
             patch.object(wake, 'emit') as output, patch.object(loop, 'connect_read_pipe', no_stdin), \
             patch.object(wake, 'chime', new_callable=AsyncMock) as sound, \
             patch.object(loop, 'add_signal_handler'), patch.object(wake.asyncio, 'wait_for', no_delay), \
             patch.object(type(wake.WAKE_MODEL), 'is_dir', return_value=True):
            await wake.listen_for_wake(grok.Session, 'wss://example.invalid', 'key')
        self.assertEqual(len(waits), 3)
        self.assertEqual(sound.await_count, 2)
        errors = [call for call in output.call_args_list if call.args[0] == 'error']
        self.assertEqual(len(errors), 2)
        self.assertIn('keep listening', errors[0].kwargs['error'])

    async def test_quit_control_disables_wake_session(self):
        session = grok.Session(None, wake_capture=object())
        await session.handle_control({'type':'quit'})
        self.assertTrue(session.stop.is_set())
        self.assertTrue(session.end_requested)


if __name__ == '__main__':
    unittest.main()
