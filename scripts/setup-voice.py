#!/usr/bin/env python3
"""Install optional local wake-word and spoken-reply models in user storage."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import urllib.request
import venv
import zipfile

data=Path(os.environ.get('XDG_DATA_HOME',Path.home()/'.local/share'))/'oma-pulse-voice'
models=data/'models'; models.mkdir(parents=True,exist_ok=True)
environment=data/'venv'
if not (environment/'bin/python').exists(): venv.EnvBuilder(with_pip=True).create(environment)
python=str(environment/'bin/python')
subprocess.run([python,'-m','pip','install','vosk==0.3.45','piper-tts==1.8.0'],check=True)
name='vosk-model-small-en-us-0.15'
if not (models/name/'am/final.mdl').exists():
    with tempfile.TemporaryDirectory(prefix='pulse-model-') as temporary:
        archive=Path(temporary)/'wake.zip'
        urllib.request.urlretrieve('https://alphacephei.com/vosk/models/'+name+'.zip',archive)
        with zipfile.ZipFile(archive) as package:
            for entry in package.infolist():
                target=(models/entry.filename).resolve()
                if not target.is_relative_to(models.resolve()) or not entry.filename.startswith(name+'/'):
                    raise RuntimeError('Unexpected path in wake model archive')
            package.extractall(models)
if not (models/'en_GB-alan-medium.onnx').exists() or not (models/'en_GB-alan-medium.onnx.json').exists():
    subprocess.run([python,'-m','piper.download_voices','en_GB-alan-medium','--data-dir',str(models)],check=True)
print('Local voice models ready. Requires parec, paplay, pactl, Voxtype with base.en, and an unlocked desktop.')
print('Enable Hey Pulse in Oma Pulse → Connections, or run omapulse voiceEnable.')
