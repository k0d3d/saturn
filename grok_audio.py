"""Session-scoped echo cancellation; never change the desktop's default devices."""
import asyncio
import contextlib
import json
import os
import re


async def pactl(*args):
    process = await asyncio.create_subprocess_exec(
        'pactl', *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
    try:
        output, _ = await asyncio.wait_for(process.communicate(), 3)
        if process.returncode:
            raise RuntimeError('Echo cancellation is unavailable.')
        return output.decode().strip()
    finally:
        if process.returncode is None:
            with contextlib.suppress(ProcessLookupError):
                process.kill()
            await process.wait()


async def unload_stale():
    """Remove echo-cancel modules left behind by sessions that died without cleanup."""
    for line in (await pactl('list', 'short', 'modules')).splitlines():
        owner = re.search(r'source_name=pulse_grok_(\d+)_mic', line)
        module = line.split('\t')[0]
        if owner and module.isdecimal() and not os.path.exists('/proc/'+owner.group(1)):
            await pactl('unload-module', module)


class EchoAudio:
    def __init__(self):
        self.module = None
        # Empty means no device is named, so the stream follows the system default.
        self.source = ''
        self.sink = ''
        self.duplex = False
        self.masters = {}

    async def prepare(self):
        with contextlib.suppress(OSError, RuntimeError, asyncio.TimeoutError):
            await unload_stale()
        source = await pactl('get-default-source')
        sink = await pactl('get-default-sink')
        prefix = 'pulse_grok_'+str(os.getpid())
        self.module = await pactl(
            'load-module', 'module-echo-cancel', 'source_name='+prefix+'_mic',
            'sink_name='+prefix+'_speaker', 'source_master='+source, 'sink_master='+sink,
            'aec_method=webrtc', 'rate=48000', 'channels=1',
            'source_properties="priority.session=0"', 'sink_properties="priority.session=0"')
        if not self.module.isdecimal():
            raise RuntimeError('Echo cancellation could not start.')
        self.source = prefix+'_mic'
        self.sink = prefix+'_speaker'
        self.duplex = True
        self.masters = {'sink': sink, 'source': source}

    async def follow(self):
        """Keep the conversation on the desktop's current devices when the user switches mid-call."""
        while True:
            await asyncio.sleep(1)
            if not self.duplex:
                continue
            with contextlib.suppress(OSError, RuntimeError, ValueError, asyncio.TimeoutError):
                for kind, streams, move in (('sink', 'sink-inputs', 'move-sink-input'),
                                            ('source', 'source-outputs', 'move-source-output')):
                    current = await pactl('get-default-'+kind)
                    if not current or current == self.masters[kind] or current.startswith('pulse_grok_'):
                        continue
                    for stream in json.loads(await pactl('-f', 'json', 'list', streams)):
                        if str(stream.get('owner_module')) == self.module:
                            await pactl(move, str(stream['index']), current)
                    self.masters[kind] = current

    async def close(self):
        if self.module and self.module.isdecimal():
            with contextlib.suppress(OSError, RuntimeError, asyncio.TimeoutError):
                await pactl('unload-module', self.module)
        self.module = None
        self.duplex = False
