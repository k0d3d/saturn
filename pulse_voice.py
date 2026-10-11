"""Local wake listener and speech output. Audio stays in RAM; stdout is JSON IPC."""
import array
import collections
import fcntl
import io
import json
import math
import os
from pathlib import Path
import queue
import re
import select
import shutil
import signal
import subprocess
import sys
import threading
import time
import wave

DATA = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'oma-pulse-voice'
MODELS = DATA / 'models'
WAKE_MODEL = MODELS / 'vosk-model-small-en-us-0.15'
VOICE_MODEL = MODELS / 'en_GB-alan-medium.onnx'
RATE = 16000
CHUNK = 3200
END_SILENCE = 2.0
FOLLOWUP_SILENCE = 2.5
MAX_SPEECH_SECONDS = 60
MIN_COMMAND = 0.8
FOLLOWUP_SECONDS = 15
WAKE_TAIL_CHUNKS = 6
WAKE_VERIFY_TIMEOUT = 10

# Only complete, bounded control phrases can skip Whisper. Free dictation,
# compound requests and uncertain words retain the higher-quality second pass.
FAST_PATTERNS = [
    r'(?:open|show|go to) (?:(?:my|the|oma|pulse) )?(?:pulse|workspace|messages|assistant|connections|insights|notepad|notes|dashboard)',
    r'open (?:(?:my|the) )?(?:browser|terminal|file manager|files|hey|todoist|calendar)',
    r'(?:close|hide|dismiss) (?:oma )?pulse',
    r'(?:mute|unmute)(?: (?:the )?(?:sound|audio|volume))?',
    r'(?:switch to|go to|show) workspace (?:one|two|three|four|five|six|seven|eight|nine|ten)',
    r'(?:play|resume|pause|stop) (?:the )?(?:music|media|playback)',
    r'(?:next|skip)(?: (?:track|song))?', r'(?:previous|last) (?:track|song)',
    r'(?:toggle )?full ?screen',
    r'(?:focus|select)(?: (?:the )?window)? (?:to the )?(?:left|right|up|down)',
    r'(?:pause|resume) (?:the )?(?:focus|timer|focus timer)',
    r'(?:go to sleep|stop listening|voice off|sleep|cancel|never mind|nevermind)',
]
QUANTITY = r'(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|(?:twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)(?: (?:one|two|three|four|five|six|seven|eight|nine))?|hundred)'
FAST_PATTERNS += [r'(?:set )?(?:the )?volume (?:to )?' + QUANTITY + r'(?: percent)?',
                  r'(?:start|set|make|create) (?:me )?(?:a )?' + QUANTITY + r' (?:minute|minutes|hour|hours) (?:focus|focus session|timer)']


def fast_command(results):
    text = command_text(' '.join(part.get('text', '') for part in results))
    words = [word for part in results for word in part.get('result', [])]
    # Wake-word pronunciation is checked by the independent wake recognizer.
    confidence = [word.get('conf', 0) for word in words[2:]]
    if not confidence or min(confidence) < 0.6 or sum(confidence)/len(confidence) < 0.85:
        return ''
    return text if any(re.fullmatch(pattern, text) for pattern in FAST_PATTERNS) else ''


def emit(event, **values):
    print(json.dumps({'event': event, **values}), flush=True)


def wake_found(text):
    return bool(re.search(r'\bhey\s+pulse\b', str(text).lower()))


def confirmed_wake(text):
    # Whisper sometimes spells Pulse as polls/pulls. Accept those narrow
    # phonetic spellings, but not nearby names such as Paul or ordinary mentions.
    return bool(re.match(r'^\s*hey[\s,]+(?:pulse|polls|pulls)\b', str(text), re.I))


def wake_spoken(text):
    # Always-on listening hears whatever came just before the wake phrase, so
    # the phrase may sit anywhere in this short clip, not only at its start.
    return bool(re.search(r'\bhey[\s,]+(?:pulse|polls|pulls)\b', str(text), re.I))


def command_text(text):
    # The wake recognizer must independently hear “hey pulse” first. Allow
    # these phonetic spellings only in the second, command transcription pass.
    match = re.match(r'^\s*hey[\s,]+(?:pulse|pulls|polls)\b[\s,.!?:-]*(.*)$', str(text), re.I | re.S)
    return match[1].strip()[:2000] if match else ''


def transcript_output(text):
    # Voxtype's file CLI prints these progress lines even with --quiet.
    return re.sub(r'^(?:Loading audio file:.*|Audio format:.*|Processing \d+ samples.*)\n?', '', text, flags=re.M).strip()


def spoken_text(text):
    text = re.sub(r'```.*?```', 'Code is shown in Pulse.', str(text), flags=re.S)
    text = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', text)
    text = re.sub(r'https?://\S+', 'link shown in Pulse', text)
    text = re.sub(r'[*_`#]+', '', text)
    text = re.sub(r'\s+', ' ', text).strip()
    if len(text) > 320:
        text = text[:280].rsplit(' ', 1)[0] + '. More details are in Pulse.'
    return text


def rms(data):
    samples = array.array('h', data)
    return math.sqrt(sum(n*n for n in samples) / max(1, len(samples)))


def unlocked():
    try:
        p = subprocess.run(['loginctl', 'show-session', 'auto', '-p', 'LockedHint', '--value'], capture_output=True, text=True, timeout=2)
        if p.returncode != 0 or p.stdout.strip() != 'no':
            return False
        if not shutil.which('omarchy-shell'):
            return True
        # The Omarchy lock screen does not set LockedHint; ask the shell itself.
        p = subprocess.run(['omarchy-shell', 'lock', 'isLocked'], capture_output=True, text=True, timeout=2)
        return p.returncode == 0 and p.stdout.strip() != 'true'
    except (OSError, subprocess.TimeoutExpired):
        return False


def dictation_busy():
    path = Path(os.environ.get('XDG_RUNTIME_DIR', '/run/user/' + str(os.getuid()))) / 'voxtype/state'
    try:
        return path.read_text().strip() not in ('idle', '')
    except OSError:
        return False


def output_audible(monitor):
    """Measure a short output level in RAM; never store or transcribe it."""
    process = None
    try:
        process = subprocess.Popen(['parec', '--raw', '--format=s16le', '--rate=16000', '--channels=1',
                                    '--device='+str(monitor), '--latency-msec=25', '--client-name=Pulse playback guard'],
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        data=bytearray(); deadline=time.monotonic()+0.5
        while len(data) < 3200:
            remaining=deadline-time.monotonic()
            if remaining <= 0 or not select.select([process.stdout], [], [], remaining)[0]: return True
            chunk=os.read(process.stdout.fileno(),3200-len(data))
            if not chunk: return True
            data.extend(chunk)
        return rms(data) > 40
    except OSError:
        return True
    finally:
        if process:
            if process.poll() is None: process.terminate()
            try: process.wait(timeout=0.3)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
            if process.stdout: process.stdout.close()


def playback_active():
    """Open streams alone aren't evidence of sound (browsers keep silent ones)."""
    try:
        result = subprocess.run(['pactl', '-f', 'json', 'list', 'sink-inputs'],
                                capture_output=True, text=True, timeout=1)
        if result.returncode: return True
        streams = json.loads(result.stdout)
        active=[stream for stream in streams if not stream.get('corked', True) and not stream.get('mute', False)
                   and stream.get('properties', {}).get('application.name') != 'Pulse voice'
                   and any(channel.get('value', 0) > 0 for channel in stream.get('volume', {}).values())]
        if not active: return False
        result=subprocess.run(['pactl','-f','json','list','sinks'],capture_output=True,text=True,timeout=1)
        if result.returncode: return True
        sinks={str(sink['index']):sink for sink in json.loads(result.stdout)}
        for index in {str(stream.get('sink')) for stream in active}:
            sink=sinks.get(index)
            if not sink or not sink.get('monitor_source'): return True
            if sink.get('mute',False) or not any(c.get('value',0)>0 for c in sink.get('volume',{}).values()): continue
            # Sound in the ears never reaches the microphone, so headphones need no pause.
            port=next((p for p in sink.get('ports') or [] if p.get('name') == sink.get('active_port')),{})
            if port.get('type') in ('Headphones','Headset'): continue
            if output_audible(sink['monitor_source']): return True
        return False
    except (OSError, subprocess.TimeoutExpired, ValueError, TypeError, AttributeError):
        return True


def transcribe(pcm, timeout=35):
    # Voxtype accepts a WAV path. An inherited memfd provides one without
    # putting microphone recordings or their transcripts on disk.
    data = io.BytesIO()
    with wave.open(data, 'wb') as wav:
        wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(RATE); wav.writeframes(pcm)
    fd = os.memfd_create('pulse-command', os.MFD_CLOEXEC)
    try:
        os.write(fd, data.getvalue()); os.lseek(fd, 0, os.SEEK_SET)
        result = subprocess.run(['voxtype', '-q', '--engine', 'whisper', '--model', 'base.en', '--language', 'en',
                                 'transcribe', '/proc/self/fd/' + str(fd)],
                                pass_fds=(fd,), capture_output=True, text=True, timeout=timeout)
        if result.returncode:
            raise RuntimeError('Speech recognition failed. Try again.')
        return transcript_output(result.stdout)
    finally:
        os.close(fd)


class Listener:
    def __init__(self):
        from vosk import Model, KaldiRecognizer, SetLogLevel
        SetLogLevel(-1)
        self.model = Model(str(WAKE_MODEL))
        self.recognizer = KaldiRecognizer(self.model, RATE, json.dumps(['hey pulse', '[unk]']))
        self.command_recognizer = KaldiRecognizer(self.model, RATE)
        self.command_recognizer.SetWords(True)
        self.command_parts = []
        self.stopping = threading.Event()
        self.speech_cancelled = threading.Event()
        self.speech_lock = threading.Lock()
        self.speech_generation = 0
        self.controls = queue.Queue()
        self.audio = queue.Queue(maxsize=160)
        self.capture = None
        self.playback = None
        self.voice = None
        self.speech_cache = collections.OrderedDict()
        self.paused = False
        self.waiting = False
        self.recording = None
        self.preroll = collections.deque(maxlen=30)
        self.noise = 100.0
        self.levels = collections.deque(maxlen=50)
        self.playback_until = 0
        self.followup_until = 0
        self.is_followup = False
        self.speech_frames = 0
        self.recording_generation = 0
        self.last_draft = ''
        self.wake_retry_at = 0

    def playback_blocked(self):
        now=time.monotonic()
        if playback_active(): self.playback_until=now+1
        return now < self.playback_until

    def reset(self):
        self.recognizer.Reset(); self.preroll.clear(); self.recording = None
        self.command_recognizer.Reset(); self.command_parts = []
        self.is_followup=False; self.speech_frames=0
        self.last_draft=''
        while True:
            try: self.audio.get_nowait()
            except queue.Empty: break

    def stop(self, *_):
        self.stopping.set()
        for process in (self.capture, self.playback):
            if process and process.poll() is None:
                process.terminate()

    def read_audio(self):
        while not self.stopping.is_set():
            data = self.capture.stdout.read(CHUNK)
            if len(data) != CHUNK: break
            try: self.audio.put_nowait(data)
            except queue.Full:
                try: self.audio.get_nowait()
                except queue.Empty: pass
                try: self.audio.put_nowait(data)
                except queue.Full: pass
        self.controls.put({'type':'capture_end'})

    def read_controls(self):
        for line in sys.stdin:
            if len(line) > 16000: continue
            try: self.accept_control(json.loads(line))
            except ValueError: pass
        self.controls.put({'type':'quit'})

    def accept_control(self, control):
        if not isinstance(control, dict): return
        if control.get('type') == 'stop_speaking':
            # Runs on the stdin thread even while synthesis or audio writes block.
            with self.speech_lock:
                self.speech_generation += 1
                self.speech_cancelled.set()
                self.followup_until=0
                if self.playback and self.playback.poll() is None:
                    self.playback.terminate()
            self.controls.put({'type':'end_followup'})
            return
        with self.speech_lock:
            control['generation'] = self.speech_generation
        self.controls.put(control)

    def prepare_voice(self):
        from piper import PiperVoice, SynthesisConfig
        self.voice = PiperVoice.load(str(VOICE_MODEL))
        self.voice_config = SynthesisConfig(length_scale=0.80, noise_scale=0.5, noise_w_scale=0.65)
        # Warm the inference session before accepting the first command.
        self.speech_cache['Ready.'] = list(self.voice.synthesize('Ready.', syn_config=self.voice_config))

    def feed_command(self, data):
        if self.command_recognizer.AcceptWaveform(data):
            self.command_parts.append(json.loads(self.command_recognizer.Result()))

    def verify_wake(self, pcm):
        try:
            accepted=confirmed_wake(transcribe(pcm,timeout=WAKE_VERIFY_TIMEOUT))
            emit('wake_check',result='accepted' if accepted else 'not_confirmed')
            return accepted
        except subprocess.TimeoutExpired:
            emit('wake_check',result='timeout')
            return False
        except (OSError, RuntimeError):
            emit('wake_check',result='unavailable')
            return False

    def wake_audio(self):
        candidate=list(self.preroll)
        # Partial recognition can fire before the final consonant is captured.
        # Include another 600 ms and preserve it as the start of the command.
        deadline=time.monotonic()+1
        for _ in range(WAKE_TAIL_CHUNKS):
            if self.stopping.is_set(): break
            remaining=deadline-time.monotonic()
            if remaining <= 0: break
            try: candidate.append(self.audio.get(timeout=min(remaining,0.25)))
            except queue.Empty: break
        return candidate

    def finish_reply(self, follow_up=False, generation=None):
        self.reset(); self.waiting=False
        with self.speech_lock:
            follow_up=follow_up and not self.stopping.is_set() and (generation is None or generation == self.speech_generation)
            self.followup_until=time.monotonic()+FOLLOWUP_SECONDS if follow_up else 0
        if follow_up: emit('state',state='followup',text='Your turn — reply now, no “Hey Pulse” needed (15 seconds)')
        else: emit('state',state='armed',text='Say “Hey Pulse”')

    def speak(self, text, generation=None, follow_up=False):
        text = spoken_text(text)
        if not text: return
        with self.speech_lock:
            if generation is not None and generation != self.speech_generation:
                self.waiting=False
                emit('state', state='armed', text='Say “Hey Pulse”')
                return
            self.speech_cancelled.clear()
        self.reset()
        emit('state', state='speaking', text=text)
        try:
            if self.voice is None: self.prepare_voice()
            cached = self.speech_cache.get(text)
            chunks = cached if cached is not None else self.voice.synthesize(text, syn_config=self.voice_config)
            generated = []
            for chunk in chunks:
                if self.stopping.is_set() or self.speech_cancelled.is_set(): break
                generated.append(chunk)
                with self.speech_lock:
                    if self.speech_cancelled.is_set(): break
                    if self.playback is None:
                        self.playback = subprocess.Popen(['paplay', '--raw', '--format=s16le', '--rate=' + str(chunk.sample_rate),
                                                         '--channels=1', '--client-name=Pulse voice'], stdin=subprocess.PIPE,
                                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self.playback.stdin.write(chunk.audio_int16_bytes)
                self.playback.stdin.flush()
            if len(text) <= 120 and not self.stopping.is_set() and not self.speech_cancelled.is_set():
                self.speech_cache[text] = generated
                self.speech_cache.move_to_end(text)
                while len(self.speech_cache) > 32: self.speech_cache.popitem(last=False)
            if self.playback:
                self.playback.stdin.close()
                if self.playback.wait(timeout=35): raise RuntimeError('Audio output unavailable.')
        except Exception:
            if not self.speech_cancelled.is_set() and not self.stopping.is_set():
                emit('error', error='Pulse could not speak. Check your audio output.')
        finally:
            if self.playback and self.playback.poll() is None: self.playback.terminate()
            self.playback = None
            # Let speaker echo decay before rearming the wake recognizer.
            self.stopping.wait(0.4)
            self.finish_reply(follow_up and not self.speech_cancelled.is_set(),generation)

    def run(self):
        self.prepare_voice()
        self.capture = subprocess.Popen(['parec', '--raw', '--format=s16le', '--rate=16000', '--channels=1',
            '--latency-msec=100', '--client-name=Pulse wake listener'],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        threading.Thread(target=self.read_audio, daemon=True).start()
        threading.Thread(target=self.read_controls, daemon=True).start()
        emit('state', state='armed', text='Say “Hey Pulse”')
        gate_at=0; blocked=False; last_state=''; pause_reason=''
        try:
            while not self.stopping.is_set():
                try:
                    control=self.controls.get_nowait()
                    kind=control.get('type')
                    if kind in ('quit','capture_end'): break
                    if kind == 'speak': self.speak(control.get('text',''),control.get('generation'),control.get('follow_up') is True); continue
                    if kind == 'pause': self.paused=bool(control.get('value')); self.reset()
                    if kind == 'resume': self.finish_reply(control.get('follow_up') is True,control.get('generation'))
                    if kind == 'end_followup': self.finish_reply()
                except queue.Empty: pass
                now=time.monotonic()
                if now >= gate_at:
                    playing=self.playback_blocked()
                    blocked=playing or not unlocked() or dictation_busy(); gate_at=now+0.5
                    pause_reason='Paused while other audio is playing' if playing else 'Paused while locked or dictating'
                gated=blocked or self.paused
                if gated:
                    self.followup_until=0
                    self.reset()
                    if last_state != pause_reason: emit('state',state='paused',text=pause_reason)
                    last_state=pause_reason; self.stopping.wait(0.1); continue
                if last_state.startswith('Paused'): emit('state',state='armed',text='Say “Hey Pulse”')
                last_state='active'
                try: data=self.audio.get(timeout=0.1)
                except queue.Empty: continue
                if self.waiting: continue
                if self.followup_until and now >= self.followup_until and self.recording is None:
                    self.finish_reply()
                level=rms(data)
                if self.recording is None:
                    self.preroll.append(data)
                    if self.followup_until:
                        # Two voiced chunks reject clicks; keep only a short onset buffer.
                        self.speech_frames=self.speech_frames+1 if level > max(220,self.noise*2.2) else 0
                        if self.speech_frames >= 2:
                            self.recording=list(self.preroll)[-4:];self.started=now;self.last_speech=now
                            self.is_followup=True;self.followup_until=0;self.recording_generation=self.speech_generation
                            emit('state',state='listening',text='Listening to your reply…')
                        continue
                    self.levels.append(level)
                    # A rolling low percentile adapts to steady fan/room noise
                    # without treating every voice peak as the noise floor.
                    self.noise=max(30,sorted(self.levels)[int(len(self.levels)*0.2)])
                    complete=self.recognizer.AcceptWaveform(data)
                    result=json.loads(self.recognizer.Result() if complete else self.recognizer.PartialResult())
                    if now >= self.wake_retry_at and wake_found(result.get('text',result.get('partial',''))) and unlocked() and not dictation_busy() and not self.playback_blocked():
                        generation=self.speech_generation
                        candidate=self.wake_audio()
                        # Keep collecting into the bounded audio queue while the
                        # independent check runs. No HUD, command or reply yet.
                        if not self.verify_wake(b''.join(candidate)):
                            self.wake_retry_at=time.monotonic()+0.5
                            self.reset();continue
                        if self.stopping.is_set() or generation != self.speech_generation or not unlocked() or dictation_busy() or self.playback_blocked():
                            self.reset();continue
                        self.recording=candidate; self.started=time.monotonic(); self.last_speech=self.started
                        self.recording_generation=generation
                        self.command_recognizer.Reset(); self.command_parts=[]
                        self.feed_command(b''.join(self.recording))
                        emit('wake'); emit('state',state='listening',text='Listening…')
                else:
                    self.recording.append(data)
                    self.feed_command(data)
                    if level > max(220,self.noise*2.2): self.last_speech=now
                    elapsed=now-self.started
                    partial=json.loads(self.command_recognizer.PartialResult()).get('partial','')
                    draft=' '.join(p.get('text','') for p in self.command_parts)+' '+partial
                    # Quiet words may sit below the energy threshold. Recognition
                    # progress still counts as speech so they aren't cut off.
                    if draft.strip() and draft.strip() != self.last_draft:
                        self.last_draft=draft.strip(); self.last_speech=now
                    minimum=MIN_COMMAND if self.is_followup or command_text(draft) else 3
                    silence=FOLLOWUP_SILENCE if self.is_followup else END_SILENCE
                    if elapsed >= MAX_SPEECH_SECONDS:
                        # Never execute a clipped request at the duration limit.
                        self.reset(); self.followup_until=0
                        emit('error',error='That reached the one-minute limit. Please try a shorter request.')
                        continue
                    if elapsed >= minimum and now-self.last_speech >= silence:
                        pcm=b''.join(self.recording); self.recording=None
                        emit('state',state='transcribing',text='Understanding…')
                        try:
                            self.command_parts.append(json.loads(self.command_recognizer.FinalResult()))
                            if self.is_followup:
                                raw=transcribe(pcm).strip()[:2000]
                                text=command_text(raw) or raw
                            else: text=fast_command(self.command_parts) or command_text(transcribe(pcm))
                            if text and self.recording_generation == self.speech_generation and not self.stopping.is_set() and unlocked() and not dictation_busy() and not self.playback_blocked():
                                self.waiting=True; emit('transcript',text=text,follow_up=self.is_followup)
                            else: emit('state',state='armed',text='Say “Hey Pulse”, then your command')
                        except Exception:
                            emit('error',error='Could not understand that. Say “Hey Pulse” and try again.')
                        finally: self.reset()
            if not self.stopping.is_set(): emit('error',error='Pulse microphone capture stopped.')
        finally:
            self.stop()
            if self.capture:
                try: self.capture.wait(timeout=2)
                except subprocess.TimeoutExpired: self.capture.kill()


def check():
    ready=WAKE_MODEL.is_dir() and VOICE_MODEL.is_file() and all(shutil.which(name) for name in ('parec','paplay','pactl','voxtype'))
    return {'ready':bool(ready),'error':'' if ready else 'Run the Pulse voice setup script first.'}


def main():
    mode=sys.argv[1] if len(sys.argv)>1 else 'check'
    if mode == 'check': print(json.dumps(check())); return
    if mode == 'transcribe-test':
        with wave.open(sys.argv[2],'rb') as wav:
            if wav.getframerate()!=RATE or wav.getnchannels()!=1 or wav.getsampwidth()!=2: raise ValueError('Expected mono 16 kHz PCM.')
            pcm=wav.readframes(wav.getnframes())
        listener=Listener(); woke=False
        for i in range(0,len(pcm),CHUNK):
            full=listener.recognizer.AcceptWaveform(pcm[i:i+CHUNK])
            r=json.loads(listener.recognizer.Result() if full else listener.recognizer.PartialResult())
            woke=woke or wake_found(r.get('text',r.get('partial','')))
        print(json.dumps({'wake':woke,'command':command_text(transcribe(pcm))})); return
    if mode != 'listen': raise ValueError('Unknown voice mode')
    status=check()
    if not status['ready']: emit('error',error=status['error']); return
    runtime=Path(os.environ.get('XDG_RUNTIME_DIR','/run/user/'+str(os.getuid())))
    with (runtime/'oma-pulse-voice.lock').open('w') as lock:
        try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError: emit('error',error='Pulse voice is already running.'); return
        listener=Listener()
        signal.signal(signal.SIGTERM,listener.stop); signal.signal(signal.SIGINT,listener.stop)
        listener.run()


if __name__ == '__main__':
    try: main()
    except Exception: emit('error',error='Pulse voice could not start. Check voice setup and microphone access.')
