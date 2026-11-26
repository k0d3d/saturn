from pathlib import Path
import ast
import json
import subprocess

root = Path(__file__).resolve().parent.parent
for path in [*root.glob('*.py'), *root.glob('scripts/*.py')]:
    ast.parse(path.read_text(), filename=str(path))
for path in [root/'install.sh', *root.glob('scripts/*.sh'), *root.glob('bin/*')]:
    subprocess.run(['bash', '-n', str(path)], check=True)
for path in [*root.glob('*.js'), root/'site/site.js', root/'scripts/build-site.cjs']:
    subprocess.run(['node', '--check', str(path)], check=True)
assert (root/'skills/saturn/SKILL.md').read_text().startswith('---\nname: saturn')
assert (root/'UX.md').is_file()
dashboard = (root/'Dashboard.qml').read_text()
assert 'import "Visual.js" as Visual' in dashboard
assert 'import QtQuick.Effects' in dashboard
assert 'active: dash.notesLoaded' in dashboard
assert 'active: dash.connectionsLoaded' in dashboard
assert 'active: dash.mailLoaded' in dashboard
assert 'compactBoard' not in (root/'OwlWindow.qml').read_text()
manifest = json.loads((root/'manifest.json').read_text())
assert manifest['version'] == json.loads((root/'package.json').read_text())['version']
for path in manifest['entryPoints'].values():
    assert (root/path).is_file()
print('Python, shell, website syntax and package metadata passed.')
