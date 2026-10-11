"""Install the optional Blip preview and mark-read IPC extension, preserving local changes."""
from pathlib import Path
import argparse
import datetime
import os
import shutil


def patch_preview(text):
    if 'function previews(): string' in text:
        return text
    replacements = [
        ('  property bool automationOn: false', '  property bool pulsePreviewsOn: false\n  property bool automationOn: false'),
        ('      var t = text()\n      root.otpAutofill', '      var t = text()\n      root.pulsePreviewsOn = PulsePreview.enabled(t)\n      root.otpAutofill'),
        ('onLoadFailed: { root.otpAutofill = false; root.automationOn = false;', 'onLoadFailed: { root.pulsePreviewsOn = false; root.otpAutofill = false; root.automationOn = false;'),
        ('    function threads(): string', '    function previews(): string { return JSON.stringify(PulsePreview.snapshot(root.pulsePreviewsOn, root.online, root.threads)) }\n    function threads(): string'),
    ]
    for old, new in replacements:
        if text.count(old) != 1:
            raise ValueError('Blip version differs from the supported preview bridge; no files changed.')
        text = text.replace(old, new)
    return 'import "PulsePreview.mjs" as PulsePreview\n' + text


def patch(text):
    text = patch_preview(text)
    if 'function pulseRead(chat: string, seen: string): string' in text:
        return text
    replacements = [
        ('  property bool pulsePreviewsOn: false', '  property bool pulseMarkReadOn: false\n  property bool pulsePreviewsOn: false'),
        ('      root.pulsePreviewsOn = PulsePreview.enabled(t)', '      root.pulseMarkReadOn = PulsePreview.readEnabled(t)\n      root.pulsePreviewsOn = PulsePreview.enabled(t)'),
        ('onLoadFailed: { root.pulsePreviewsOn = false;', 'onLoadFailed: { root.pulseMarkReadOn = false; root.pulsePreviewsOn = false;'),
        ('    function previews(): string', '''    function pulseRead(chat: string, seen: string): string {
      var error = PulsePreview.readRequest(root.pulseMarkReadOn, root.online, root.threads, chat, seen)
      if (error) return JSON.stringify({ok:false,error:error})
      root.markThreadRead(chat, seen)
      return JSON.stringify({ok:true})
    }
    function previews(): string'''),
    ]
    for old, new in replacements:
        if text.count(old) != 1:
            raise ValueError('Blip version differs from the supported read bridge; no files changed.')
        text = text.replace(old, new)
    return text


def install(directory):
    widget = directory / 'BarWidget.qml'
    original = widget.read_text()
    updated = patch(original)
    backup = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'omaowl-backups' / ('blip-preview-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    backup.mkdir(parents=True, mode=0o700)
    shutil.copy2(widget, backup / widget.name)
    shutil.copy2(Path(__file__).parent / 'blip-preview/PulsePreview.mjs', directory / 'PulsePreview.mjs')
    widget.write_text(updated)
    print('Blip preview/read bridge installed. Backup: ' + str(backup))
    print('Set pulse_previews=on and optionally pulse_mark_read=on in bridge.conf; restart the Omarchy shell.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path.home() / '.config/omarchy/plugins/nixfred.blip')
    install(parser.parse_args().directory)
