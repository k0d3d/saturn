"""Exercise the realtime lifecycle without credentials, microphone or network."""
import asyncio
import base64
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import AsyncMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import grok_voice as grok
import grok_audio


class Socket:
    def __init__(self):
        self.events = asyncio.Queue()
        self.sent = []

    async def send(self, raw):
        self.sent.append(json.loads(raw))

    def __aiter__(self):
        return self

    async def __anext__(self):
        value = await self.events.get()
        if value is None:
            raise StopAsyncIteration
        return json.dumps(value)


class CredentialTests(unittest.TestCase):
    def test_private_atomic_key_storage_and_no_disclosure(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)/'config/grok-api-key'
            with patch.object(grok, 'KEY_FILE', target), patch.dict(os.environ, {'XAI_API_KEY': ''}):
                grok.save_key('example-secret')
                self.assertEqual(grok.api_key(), 'example-secret')
                self.assertEqual(target.stat().st_mode & 0o777, 0o600)
                self.assertNotIn('example-secret', json.dumps(grok.status()))
                grok.save_key('replacement-secret')
                self.assertEqual(target.read_text().strip(), 'replacement-secret')
                self.assertEqual(list(target.parent.iterdir()), [target])

    def test_invalid_key_does_not_replace_existing(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)/'key'
            target.write_text('existing')
            with patch.object(grok, 'KEY_FILE', target):
                for value in ('', 'two words', 'bad\nheader', None):
                    with self.assertRaises(ValueError):
                        grok.save_key(value)
                self.assertEqual(target.read_text(), 'existing')


class RealtimeTests(unittest.IsolatedAsyncioTestCase):
    async def test_spoken_interruption_preserves_the_new_utterance(self):
        ws = Socket(); session = grok.Session(ws)
        session.audio.duplex = True
        session.response_id = 'old'; session.speaking = True
        session.output.put_nowait((0, b'old-audio'))
        ws.events.put_nowait({'type': 'input_audio_buffer.speech_started'})
        ws.events.put_nowait(None)
        with patch.object(grok, 'emit'):
            with self.assertRaises(RuntimeError):
                await session.receive()
        self.assertTrue(session.output.empty())
        self.assertFalse(session.speaking)
        self.assertEqual(session.mic_after, 0)
        self.assertNotIn({'type': 'input_audio_buffer.clear'}, ws.sent)
        self.assertNotIn({'type': 'response.cancel'}, ws.sent)

    async def test_echo_devices_are_session_scoped_without_changing_defaults(self):
        audio = grok_audio.EchoAudio()
        with patch.object(grok_audio, 'pactl', new_callable=AsyncMock) as control:
            control.side_effect = ['', 'physical_mic', 'physical_speaker', '1234', '']
            await audio.prepare()
            self.assertTrue(audio.duplex)
            self.assertIn('source_master=physical_mic', control.call_args.args)
            self.assertIn('sink_master=physical_speaker', control.call_args.args)
            self.assertIn('source_properties="priority.session=0"', control.call_args.args)
            await audio.close()
            control.assert_awaited_with('unload-module', '1234')
            self.assertFalse(audio.duplex)
            self.assertFalse(any(call.args[0].startswith('set-default') for call in control.call_args_list))

    async def test_echo_modules_from_dead_sessions_are_removed(self):
        modules = ('7\tmodule-echo-cancel\tsource_name=pulse_grok_999999999_mic sink_name=pulse_grok_999999999_speaker\n'
                   '8\tmodule-echo-cancel\tsource_name=pulse_grok_'+str(os.getpid())+'_mic\n'
                   '9\tmodule-echo-cancel\tsource_name=someone_elses_mic')
        with patch.object(grok_audio, 'pactl', new_callable=AsyncMock) as control:
            control.side_effect = [modules, '']
            await grok_audio.unload_stale()
        self.assertEqual([call.args for call in control.call_args_list], [('list', 'short', 'modules'), ('unload-module', '7')])

    async def test_local_weather_does_not_delegate_to_codex(self):
        ws = Socket(); session = grok.Session(ws)
        with patch.object(grok, 'local_weather', return_value={'ok': True, 'location': 'Danvers'}), patch.object(grok, 'emit') as output:
            await session.tool({'name': 'get_local_weather', 'call_id': 'weather1', 'arguments': '{}'})
        self.assertFalse(any(call.args[0] == 'tool_request' for call in output.call_args_list))
        self.assertEqual(json.loads(ws.sent[0]['item']['output'])['location'], 'Danvers')

    async def test_audio_event_aliases_transcripts_and_turn_timing(self):
        for audio_type in ('response.audio.delta', 'response.output_audio.delta'):
            ws = Socket(); session = grok.Session(ws)
            emitted = []
            events = [
                {'type': 'session.updated'},
                {'type': 'input_audio_buffer.speech_stopped'},
                {'type': 'conversation.item.input_audio_transcription.completed', 'transcript': 'Hello'},
                {'type': 'response.created', 'response': {'id': 'r1'}},
                {'type': audio_type, 'response_id': 'r1', 'item_id': 'i1', 'delta': base64.b64encode(b'\0\0'*480).decode()},
                {'type': 'response.output_audio_transcript.done', 'response_id': 'r1', 'transcript': 'Hi'},
                {'type': 'response.done', 'response': {'id': 'r1', 'status': 'completed'}},
            ]
            for event in events:
                ws.events.put_nowait(event)
            ws.events.put_nowait(None)
            with patch.object(grok, 'emit', side_effect=lambda event, **kw: emitted.append((event, kw))):
                with self.assertRaisesRegex(RuntimeError, 'disconnected'):
                    await session.receive()
            self.assertTrue(session.ready.is_set())
            self.assertIsNotNone(session.turn_end)
            self.assertEqual(session.output.get_nowait(), (0, b'\0\0'*480))
            self.assertEqual(session.output.get_nowait(), (0, None))
            self.assertIn(('transcript', {'text': 'Hello'}), emitted)
            self.assertIn(('reply', {'text': 'Hi'}), emitted)

    async def test_interrupt_discards_queued_and_late_audio(self):
        ws = Socket(); session = grok.Session(ws)
        session.response_id = 'old'; session.speaking = True
        session.output.put_nowait((0, b'old-audio'))
        with patch.object(grok, 'emit'):
            await session.interrupt()
            ws.events.put_nowait({'type': 'response.output_audio.delta', 'response_id': 'old', 'delta': 'AAAA'})
            ws.events.put_nowait(None)
            with self.assertRaises(RuntimeError):
                await session.receive()
        self.assertTrue(session.output.empty())
        self.assertFalse(session.speaking)
        self.assertIn({'type': 'response.cancel'}, ws.sent)
        self.assertIn({'type': 'input_audio_buffer.clear'}, ws.sent)

    async def test_interrupt_terminates_player_even_while_draining(self):
        ws = Socket(); session = grok.Session(ws)
        ended = asyncio.Event()
        class Player:
            returncode = None
            stdin = type('Input', (), {'close': lambda self: None})()
            async def wait(self):
                await ended.wait()
                return 0
            def terminate(self):
                self.returncode = -15
                ended.set()
        player = Player(); session.player = player
        draining = asyncio.create_task(session.close_player(drain=True))
        await asyncio.sleep(0)
        with patch.object(grok, 'emit'):
            await asyncio.wait_for(session.interrupt(), 0.2)
        await draining
        self.assertTrue(ended.is_set())
        self.assertIsNone(session.player)

    async def test_tool_result_returns_to_grok_without_execution_in_backend(self):
        ws = Socket(); session = grok.Session(ws)
        def output(event, **values):
            if event == 'tool_request':
                self.assertEqual(values['text'], 'open my browser')
                session.pending[values['call_id']].set_result({'ok': True, 'text': 'Browser opened.'})
        with patch.object(grok, 'emit', side_effect=output):
            await session.tool({'name': 'pulse_request', 'call_id': 'c1', 'arguments': '{"request":"open my browser"}'})
        item = ws.sent[0]['item']
        self.assertEqual(item['call_id'], 'c1')
        self.assertTrue(json.loads(item['output'])['ok'])
        self.assertEqual(ws.sent[1], {'type': 'response.create'})
        self.assertFalse(session.pending)

    async def test_direct_actions_run_in_order_and_stop_at_a_failure(self):
        ws = Socket(); session = grok.Session(ws); seen = []
        def output(event, **values):
            if event == 'tool_request':
                seen.append(values['action']['kind'])
                ok = values['action']['kind'] != 'focus_app'
                session.pending[values['call_id']].set_result({'ok': ok, 'text': 'Done.' if ok else 'No open window matches that.'})
        steps = [{'kind': 'set_volume', 'number': 30}, {'kind': 'focus_app', 'value': 'slack'}, {'kind': 'screenshot'}]
        with patch.object(grok, 'emit', side_effect=output):
            await session.tool({'name': 'desktop_actions', 'call_id': 'c1', 'arguments': json.dumps({'actions': steps})})
        self.assertEqual(seen, ['set_volume', 'focus_app'])
        result = json.loads(ws.sent[0]['item']['output'])
        self.assertFalse(result['ok'])
        self.assertIn('remaining steps were not run', result['text'])
        self.assertFalse(session.pending or session.working)

    async def test_direct_actions_are_checked_before_any_step_runs(self):
        for steps in ([{'kind': 'set_volume', 'number': 30}, {'kind': 'shell', 'value': 'rm -rf ~'}],
                      [{'kind': 'complete_task', 'value': ''}], [{'kind': 'set_volume', 'number': 500}],
                      [{'kind': 'open_url', 'value': 'file:///etc/passwd'}], [], [{'kind': 'screenshot'}]*9):
            ws = Socket(); session = grok.Session(ws)
            with patch.object(grok, 'emit') as emit:
                await session.tool({'name': 'desktop_actions', 'call_id': 'c1', 'arguments': json.dumps({'actions': steps})})
            emit.assert_not_called()
            self.assertFalse(json.loads(ws.sent[0]['item']['output'])['ok'])

    async def test_personal_info_is_read_without_the_planner(self):
        ws = Socket(); session = grok.Session(ws)
        def output(event, **values):
            if event == 'tool_request':
                self.assertEqual(values['query'], 'calendar')
                self.assertNotIn('text', values)
                session.pending[values['call_id']].set_result({'ok': True, 'text': '9:00 AM to 9:30 AM: Standup'})
        with patch.object(grok, 'emit', side_effect=output):
            await session.tool({'name': 'get_personal_info', 'call_id': 'c1', 'arguments': '{"topic":"calendar"}'})
            await session.tool({'name': 'get_personal_info', 'call_id': 'c2', 'arguments': '{"topic":"passwords"}'})
        self.assertIn('Standup', json.loads(ws.sent[0]['item']['output'])['text'])
        self.assertFalse(json.loads(ws.sent[2]['item']['output'])['ok'])

    def test_main_bot_is_saved_by_full_name_and_unknown_names_are_refused(self):
        with tempfile.TemporaryDirectory() as folder, \
             patch.object(grok.agents, 'BOT_FILE', Path(folder)/'oma-pulse/grok-bot'), \
             patch.object(grok.agents, 'bots', return_value=[{'id': 'b1', 'name': 'Forge'}, {'id': 'b3', 'name': 'Zeus (Chief of Staff)'}]):
            self.assertEqual(grok.agents.default_bot(), '')
            self.assertEqual(grok.agents.save_default_bot(' zeus '), 'Zeus (Chief of Staff)')
            self.assertEqual(grok.status()['defaultBot'], 'Zeus (Chief of Staff)')
            with self.assertRaises(ValueError):
                grok.agents.save_default_bot('nobody')
            self.assertEqual(grok.agents.default_bot(), 'Zeus (Chief of Staff)')
            self.assertEqual(grok.agents.save_default_bot(''), '')
            self.assertEqual(grok.agents.default_bot(), '')

    async def test_agent_task_is_sent_as_spoken_and_bad_requests_send_nothing(self):
        ws = Socket(); session = grok.Session(ws)
        with patch.object(grok, 'emit'), patch.object(grok.agents, 'announce') as announce, \
             patch.object(grok.agents, 'choose', side_effect=grok.AssistantError('No agent matches.')), \
             patch.object(grok.agents, 'grok_bot', return_value='Sent to the Grok Bot app.') as bot, \
             patch.object(grok.agents, 'bots', return_value=[{'id': 'b1', 'name': 'Forge'}, {'id': 'b2', 'name': 'Hermes'}, {'id': 'b3', 'name': 'Zeus (Chief of Staff)'}]), \
             patch.object(grok.agents, 'default_bot', side_effect=['Zeus (Chief of Staff)', '']), \
             patch.object(grok.asyncio, 'create_subprocess_exec', new=AsyncMock()) as spawn:
            await session.tool({'name': 'ask_agent', 'call_id': 'c1', 'arguments': '{"agent":"grok_bot","task":"Say  hi"}'})
            await session.tool({'name': 'ask_agent', 'call_id': 'c0', 'arguments': '{"agent":"grok_bot","task":"Open chat"}'})
            await session.tool({'name': 'ask_agent', 'call_id': 'c2', 'arguments': '{"agent":"the big one","task":"Fix it"}'})
            await session.tool({'name': 'ask_agent', 'call_id': 'c3', 'arguments': '{"agent":"grok_bot","task":""}'})
            await session.tool({'name': 'ask_agent', 'call_id': 'c4', 'arguments': '{"agent":"Forge","task":"Ship it"}'})
        bot.assert_any_call('Say hi', {'id': 'b3', 'name': 'Zeus (Chief of Staff)'})
        bot.assert_any_call('Open chat', None)
        bot.assert_called_with('Ship it', {'id': 'b1', 'name': 'Forge'})
        announce.assert_called_with('Forge in Grok Bot', 'Ship it')
        self.assertEqual(bot.call_count, 3)
        spawn.assert_not_called()
        results = [json.loads(sent['item']['output'])['ok'] for sent in ws.sent if sent['type'] == 'conversation.item.create']
        self.assertEqual(results, [True, True, False, False, True])

    async def test_agent_references_resolve_to_one_running_agent(self):
        roster = [{'pane': 'w1:p1', 'tab': '22', 'kind': 'codex', 'status': 'idle', 'title': 'Fix'},
                  {'pane': 'w1:p2', 'tab': '23', 'kind': 'codex', 'status': 'blocked', 'title': 'Ship'},
                  {'pane': 'w1:p3', 'tab': '25', 'kind': 'claude', 'status': 'idle', 'title': 'Docs'}]
        with patch.object(grok.agents, 'roster', return_value=roster), patch.object(grok.agents, 'windows', return_value=[]):
            self.assertEqual(grok.agents.choose('Codex 22')['pane'], 'w1:p1')
            self.assertEqual(grok.agents.choose('claude')['pane'], 'w1:p3')
            self.assertEqual(grok.agents.choose('claude', fresh=True)['pane'], '')
            self.assertEqual(grok.agents.choose('gemini')['status'], 'new')
            for bad in ('codex', '23', 'the big one'):
                with self.assertRaises(grok.AssistantError):
                    grok.agents.choose(bad)

    async def test_invalid_tool_cannot_dispatch_to_desktop(self):
        ws = Socket(); session = grok.Session(ws)
        with patch.object(grok, 'emit') as emit:
            await session.tool({'name': 'shell', 'call_id': 'c1', 'arguments': '{}'})
        emit.assert_not_called()
        self.assertFalse(json.loads(ws.sent[0]['item']['output'])['ok'])

    async def test_server_error_does_not_echo_response_secrets(self):
        ws = Socket(); session = grok.Session(ws)
        ws.events.put_nowait({'type': 'error', 'error': {'message': 'secret-token'}})
        with self.assertRaises(RuntimeError) as error:
            await session.receive()
        self.assertNotIn('secret-token', str(error.exception))

    async def test_lock_ends_session(self):
        session = grok.Session(Socket())
        with patch.object(grok, 'unlocked', return_value=False), patch.object(grok, 'emit'):
            await asyncio.wait_for(session.guard(), 1)
        self.assertTrue(session.stop.is_set())

    async def test_end_session_tool_stops_without_another_response(self):
        ws = Socket(); session = grok.Session(ws)
        with patch.object(grok, 'emit'):
            await session.tool({'name': 'end_session', 'call_id': 'c1', 'arguments': '{}'})
        self.assertTrue(session.stop.is_set())
        self.assertEqual(ws.sent, [])


if __name__ == '__main__':
    unittest.main()
