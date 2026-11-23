"""Exercise the installer in a fake user home, with shell integration stubbed."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent

class InstallTests(unittest.TestCase):
    def test_install_refusal_and_backup_preserve_workspace(self):
        with tempfile.TemporaryDirectory(prefix='saturn-install-') as temp:
            base = Path(temp); source = base/'source'; home = base/'home with spaces'; bins = base/'bin'
            source.mkdir(); home.mkdir(); bins.mkdir()
            for name in ['install.sh', 'initialize.py', 'manifest.json', 'Service.qml', 'BarWidget.qml']:
                shutil.copy2(ROOT/name, source/name)
            for name in ['scripts', 'bin', 'assets']:
                shutil.copytree(ROOT/name, source/name)
            for command in ['omarchy', 'omarchy-shell']:
                path = bins/command
                path.write_text('#!/bin/sh\nexit 0\n'); path.chmod(0o755)
            env = {**os.environ, 'HOME': str(home), 'XDG_DATA_HOME': str(home/'.local/share'),
                   'XDG_CONFIG_HOME': str(home/'.config'), 'PATH': f'{bins}:/usr/bin:/bin',
                   'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null'}
            def run(args, check=True, cwd=source):
                return subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True, check=check)
            run(['git','init','-b','main'])
            run(['git','add','.'])
            run(['git','-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-m','Fixture'])
            run(['bash','install.sh','--local','--no-enable'])
            target=home/'.config/omarchy/plugins/k0d3d.saturn'
            self.assertTrue((target/'.git').is_dir())
            self.assertTrue((home/'.local/bin/saturn').is_symlink())
            self.assertTrue((home/'.local/bin/omapulse').is_symlink())
            self.assertTrue((home/'.local/bin/omaowl').is_symlink())
            self.assertTrue((home/'.local/share/applications/saturn.desktop').is_file())
            self.assertEqual(json.loads((target/'manifest.json').read_text())['id'], 'k0d3d.saturn')
            state=home/'.local/share/saturn/workspace.json'
            self.assertEqual(json.loads(state.read_text())['version'], 2)
            state.write_text('{"notes":{"today":"Keep this note"}}')
            (target/'local-customization.txt').write_text('Keep this code')
            legacy = home/'.local/share/applications/omaowl.desktop'
            legacy.write_text('[Desktop Entry]\nName=Saturn\n')
            self.assertNotEqual(run(['bash','install.sh','--local','--no-enable'],check=False).returncode,0)
            self.assertTrue((target/'local-customization.txt').exists())
            run(['bash','install.sh','--local','--adopt','--no-enable'])
            self.assertEqual(json.loads(state.read_text())['notes']['today'],'Keep this note')
            backups=list((home/'.local/share/omaowl-backups').glob('*/k0d3d.saturn/local-customization.txt'))
            self.assertEqual(len(backups),1)
            self.assertEqual(backups[0].read_text(),'Keep this code')
            self.assertFalse(legacy.exists())
            self.assertTrue(list((home/'.local/share/omaowl-backups').glob('launcher-*/omaowl.desktop')))
            self.assertIn('Saturn',run([str(home/'.local/bin/saturn'),'--version']).stdout)
            self.assertIn(json.loads((ROOT/'manifest.json').read_text())['version'],run([str(home/'.local/bin/saturn'),'--version']).stdout)
