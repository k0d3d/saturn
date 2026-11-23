#!/usr/bin/env bash
# Install the Saturn data skill into OpenCode. No sudo; lives outside the plugin dir.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
skills_root="${OPENCODE_SKILLS_DIR:-$HOME/.config/opencode/skills}"
target="$skills_root/saturn"
source="$repo_dir/skills/saturn"
[[ -f "$source/SKILL.md" ]] || { echo "Missing $source/SKILL.md" >&2; exit 1; }
mkdir -p "$skills_root"
if [[ -e "$target" && ! -L "$target" ]]; then
  backup="$skills_root/saturn.before-saturn-$(date +%s)"
  mv -- "$target" "$backup"
  echo "Existing skill backed up to $backup"
fi
ln -sfn "$source" "$target"
printf 'Saturn skill installed at %s\n' "$target"
