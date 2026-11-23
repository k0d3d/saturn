#!/usr/bin/env python3
"""Install only the dependency needed by the optional Grok live prototype."""
import os
from pathlib import Path
import subprocess
import venv

environment = Path(os.environ.get('XDG_DATA_HOME', Path.home()/'.local/share'))/'saturn-voice/venv'
if not (environment/'bin/python').exists():
    venv.EnvBuilder(with_pip=True).create(environment)
subprocess.run([str(environment/'bin/python'), '-m', 'pip', 'install', 'websockets>=15,<18'], check=True)
print('Ready. Add your xAI API key in Saturn → Connections → Grok live.')
