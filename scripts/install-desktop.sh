#!/usr/bin/env bash
set -euo pipefail
plugin_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$HOME/.local/bin" "$data_dir/applications" "$data_dir/icons/hicolor/scalable/apps"
# All launcher names follow plugin updates. The old names keep existing shortcuts working.
for name in saturn omapulse omaowl; do
  if [[ -e "$HOME/.local/bin/$name" && ! -L "$HOME/.local/bin/$name" ]]; then
    cp -p "$HOME/.local/bin/$name" "$HOME/.local/bin/$name.before-saturn-$(date +%s)"
  fi
  ln -sfn "$plugin_dir/bin/saturn" "$HOME/.local/bin/$name"
done
cp "$plugin_dir/assets/saturn.svg" "$data_dir/icons/hicolor/scalable/apps/saturn.svg"
# Retire only the old launcher created by this plugin, keeping a backup.
legacy="$data_dir/applications/omaowl.desktop"
if [[ -f "$legacy" ]] && grep -Eq '^Name=(Oma Owl|Oma Pulse|Saturn)$' "$legacy"; then
  backup="$data_dir/omaowl-backups/launcher-$(date +%s)-$$"
  mkdir -p "$backup"
  mv -- "$legacy" "$backup/omaowl.desktop"
fi
# Desktop entries quote paths differently from shell commands.
python3 - "$plugin_dir/bin/saturn" "$data_dir/applications/saturn.desktop" <<'PY'
from pathlib import Path
import sys
exe = sys.argv[1].replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%')
Path(sys.argv[2]).write_text(f'''[Desktop Entry]
Type=Application
Name=Saturn
Comment=Tasks, focus, notes, calendar and mail, within reach
Exec="{exe}" open
Icon=saturn
Terminal=false
Categories=Office;
Keywords=productivity;focus;notes;calendar;mail;
Actions=Dashboard;Command;Assistant;

[Desktop Action Dashboard]
Name=Full workspace
Exec="{exe}" dashboard

[Desktop Action Command]
Name=Command bar
Exec="{exe}" command

[Desktop Action Assistant]
Name=Assistant
Exec="{exe}" assistant
''')
PY
if command -v update-desktop-database >/dev/null; then update-desktop-database "$data_dir/applications"; fi
printf 'App launcher installed. Open Saturn from your application menu.\n'
