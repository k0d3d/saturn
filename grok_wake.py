"""Local Hey Saturn detection handing buffered speech to a Grok session.

No local TTS or command planner. A bounded RAM buffer preserves speech while the
cloud connection starts. One stdin reader owns control messages across sessions.
"""
import asyncio
import collections
import contextlib
import json
from pathlib import Path
import signal
import sys
import time

from grok_audio import unload_stale
from pulse_voice import (WAKE_MODEL, RATE, CHUNK, emit, wake_found, wake_spoken,
                         transcribe, unlocked, dictation_busy, playback_active)


WAKE_WINDOW = 12  # chunks of 0.2 s kept from before the wake phrase was recognized
CHIME = Path(__file__).resolve().parent/'assets/wake.wav'


async def chime():
    """Confirm the wake phrase audibly. It ends before the cloud microphone opens."""
    with contextlib.suppress(OSError):
        await asyncio.create_subprocess_exec(
            'paplay', '--client-name=Saturn wake chime', str(CHIME),
            stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)


class WakeCapture:
    def __init__(self, model, recognizer_type):
        self.recognizer = recognizer_type(model, RATE, json.dumps(['hey saturn', '[unk]']))
        self.queue = asyncio.Queue(maxsize=160)
        self.preroll = collections.deque(maxlen=30)
        self.pending = []
        self.replay = collections.deque()
        self.process = None
        self.reader = None

    async def start(self):
        # No device is named, so the stream follows the system's default microphone when it changes.
        self.process = await asyncio.create_subprocess_exec(
            'parec', '--raw', '--format=s16le', '--rate='+str(RATE), '--channels=1',
            '--latency-msec=100', '--client-name=Saturn Grok wake listener',
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        self.reader = asyncio.create_task(self.read())

    async def read(self):
        try:
            while True:
                data = await self.process.stdout.readexactly(CHUNK)
                if self.queue.full():
                    self.queue.get_nowait()
                self.queue.put_nowait(data)
        except asyncio.IncompleteReadError as exc:
            if exc.partial:
                if self.queue.full():
                    self.queue.get_nowait()
                self.queue.put_nowait(exc.partial[:len(exc.partial)//2*2])
            if self.queue.full():
                self.queue.get_nowait()
            self.queue.put_nowait(None)

    def reset(self):
        self.recognizer.Reset()
        self.preroll.clear()
        self.pending = []
        self.replay.clear()
        while not self.queue.empty():
            self.queue.get_nowait()

    async def wait(self, stopped, forced=None):
        next_guard = 0
        blocked = True
        previous = None
        while not stopped.is_set():
            now = time.monotonic()
            if now >= next_guard:
                blocked = await asyncio.to_thread(lambda: not unlocked() or dictation_busy() or playback_active())
                next_guard = time.monotonic()+0.5
                if blocked != previous:
                    emit('state', state='paused' if blocked else 'armed',
                         text='Wake listening paused while locked, dictating or playing audio' if blocked else 'Say “Hey Saturn” to talk to Grok')
                    previous = blocked
            if forced and forced.is_set():
                # A key press stands in for the wake phrase, even while audio is playing.
                forced.clear()
                if await asyncio.to_thread(lambda: unlocked() and not dictation_busy()):
                    self.reset()
                    emit('wake')
                    return True
            if blocked:
                self.reset()
                await asyncio.sleep(0.1)
                continue
            try:
                data = self.replay.popleft() if self.replay else await asyncio.wait_for(self.queue.get(), 0.2)
            except asyncio.TimeoutError:
                if self.reader.done():
                    raise RuntimeError('Wake microphone capture stopped.')
                continue
            if data is None:
                raise RuntimeError('Wake microphone capture stopped.')
            self.preroll.append(data)
            complete = self.recognizer.AcceptWaveform(data)
            result = json.loads(self.recognizer.Result() if complete else self.recognizer.PartialResult())
            if not wake_found(result.get('text', result.get('partial', ''))):
                continue
            # Only the last moments hold the phrase. Earlier speech would confuse
            # the check and has no business reaching the cloud.
            self.pending = list(self.preroll)[-WAKE_WINDOW:]
            # Retain the last consonant and any command spoken immediately after
            # the wake phrase, including audio arriving during verification.
            tail = []
            for _ in range(6):
                if stopped.is_set():
                    return False
                try:
                    data = self.replay.popleft() if self.replay else await asyncio.wait_for(self.queue.get(), 0.25)
                except asyncio.TimeoutError:
                    break
                if data is None:
                    raise RuntimeError('Wake microphone capture stopped.')
                tail.append(data)
            self.pending += tail
            try:
                text = await asyncio.to_thread(transcribe, b''.join(self.pending), timeout=10)
                accepted = wake_spoken(text)
            except Exception:
                accepted = False
            emit('wake_check', result='accepted' if accepted else 'not_confirmed')
            if accepted and not stopped.is_set():
                allowed = await asyncio.to_thread(lambda: unlocked() and not dictation_busy() and not playback_active())
                if allowed:
                    emit('wake')
                    return True
                self.reset()
                continue
            # A false alarm must not swallow a real "Hey Saturn" said right after it:
            # listen again to the audio that followed, and keep what arrived meanwhile.
            self.recognizer.Reset()
            self.pending = []
            self.replay.extendleft(reversed(tail))
        return False

    async def finish(self):
        if self.process and self.process.returncode is None:
            with contextlib.suppress(ProcessLookupError):
                self.process.terminate()
            await self.process.wait()
        if self.reader:
            await self.reader
        parts, self.pending = self.pending, []
        while not self.queue.empty():
            data = self.queue.get_nowait()
            if data:
                parts.append(data)
        return b''.join(parts)


async def listen_for_wake(session_type, url, key):
    from vosk import Model, KaldiRecognizer, SetLogLevel
    from websockets.asyncio.client import connect
    if not key:
        raise RuntimeError('Add your xAI key before enabling Hey Saturn.')
    if not WAKE_MODEL.is_dir():
        raise RuntimeError('Run scripts/setup-voice.py to install the Hey Saturn wake model.')
    stopped = asyncio.Event()
    forced = asyncio.Event()
    active = None
    def stop():
        stopped.set()
        if active:
            active.stop.set()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop)

    async def controls():
        reader = asyncio.StreamReader(limit=32768)
        transport, _ = await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
        try:
            while line := await reader.readline():
                try:
                    control = json.loads(line)
                    if control.get('type') == 'quit':
                        stop()
                        return
                    if active:
                        await active.handle_control(control)
                    elif control.get('type') == 'wake':
                        forced.set()
                except (ValueError, AttributeError):
                    continue
        finally:
            transport.close()
            stop()

    control_task = asyncio.create_task(controls())
    capture = None
    try:
        SetLogLevel(-1)
        with contextlib.suppress(OSError, RuntimeError, asyncio.TimeoutError):
            await unload_stale()
        emit('state', state='starting', text='Starting Hey Saturn for Grok…')
        model = await asyncio.to_thread(Model, str(WAKE_MODEL))
        failures = 0
        while not stopped.is_set():
            capture = WakeCapture(model, KaldiRecognizer)
            ended_by_user = False
            try:
                await capture.start()
                forced.clear()
                if not await capture.wait(stopped, forced):
                    break
                await chime()
                emit('state', state='starting', text='Connecting to Grok…')
                async with connect(url, additional_headers={'Authorization': 'Bearer '+key},
                                   open_timeout=10, close_timeout=2, max_size=2**22) as ws:
                    if stopped.is_set():
                        break
                    active = session_type(ws, input_rate=RATE, wake_capture=capture)
                    await active.run(external_controls=True)
                    ended_by_user = active.end_requested
                failures = 0
            except Exception as exc:
                # Always-on listening must survive one bad conversation: a dropped
                # network, a rejected session or a microphone that went away.
                if stopped.is_set():
                    break
                failures += 1
                emit('error', error=(str(exc) if isinstance(exc, RuntimeError) else 'Could not reach Grok.')+' Hey Saturn will keep listening.')
                with contextlib.suppress(asyncio.TimeoutError):
                    await asyncio.wait_for(stopped.wait(), min(30, 2**failures))
            finally:
                active = None
                await capture.finish()
                capture = None
            if ended_by_user:
                stop()
            # Idle/lock/maximum duration ends cloud streaming, then returns to
            # local wake detection. Explicit quit ends the microphone entirely.
    finally:
        stop()
        control_task.cancel()
        await asyncio.gather(control_task, return_exceptions=True)
        if capture:
            await capture.finish()
