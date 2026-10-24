#!/usr/bin/env python3
"""Capture an authorized on-screen marketing canvas, never a window snapshot."""
import argparse
import json
import struct
import subprocess
import sys
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--interactive', action='store_true', help='Select the canvas rectangle manually; do not press Space.')
parser.add_argument('--dry-run', action='store_true', help='Validate the request and print the capture command without running it.')
args = parser.parse_args()
output = args.output.resolve(strict=True)
request = json.loads((output / 'screen-region-request.json').read_text())
assert request['bundleIdentifier'] == 'studio.cuatro.tildone.marketing-preview'
assert request['asset'] == 'screenshot-6' and request['compositionRevision'] == 3
assert request['canvasFullyOnScreen'] and request['canvasWithinVisibleFrame']
assert request['locale'] in {'en-US', 'es-ES', 'fr-FR', 'zh-Hans'}
rect = request['rect']
assert set(rect) == {'x', 'y', 'width', 'height'}
assert all(type(value) is int for value in rect.values())
assert rect['width'] == 1440 and rect['height'] == 900
assert request['rawFile'] == 'native-frames/screen-region-native.png'
token = request['sceneToken']
assert len(token) == 36 and all(c in '0123456789abcdefABCDEF-' for c in token)
raw = output / request['rawFile']
temporary = raw.with_name('screen-region-in-progress-' + token + '.png')
command = ['/usr/sbin/screencapture', '-x', '-t', 'png']
if args.interactive:
    command += ['-i', '-s']
else:
    command += ['-R' + ','.join(str(rect[key]) for key in ('x', 'y', 'width', 'height'))]
command.append(str(temporary))
if args.dry_run:
    print(json.dumps({'command': command, 'rect': rect, 'interactive': args.interactive}, indent=2))
    raise SystemExit(0)
if args.interactive:
    print('Select the complete marketing canvas by dragging its rectangle. Do not press Space (window mode).', flush=True)
else:
    print('Capturing the visible canvas rectangle with macOS screencapture.', flush=True)
result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
if result.returncode or not temporary.is_file():
    print(result.stderr.strip(), file=sys.stderr)
    print('Rectangle capture failed or was cancelled. The scene remains open. If macOS requested Screen Recording permission for Terminal, allow it and retry. You can also use the manual English launcher to select the rectangle yourself.', file=sys.stderr)
    raise SystemExit(1)
header = temporary.read_bytes()[:33]
assert header[:8] == b'\x89PNG\r\n\x1a\n' and header[12:16] == b'IHDR'
width, height = struct.unpack('>II', header[16:24])
if abs(width / height - 1.6) > 0.002:
    print('The selected rectangle must cover the complete 1440 × 900 marketing canvas. The scene remains open.', file=sys.stderr)
    raise SystemExit(1)
temporary.replace(raw)
ack = {
    'sceneToken': token, 'rawFile': request['rawFile'],
    'method': 'macos-screencapture-interactive-region' if args.interactive else 'macos-screencapture-region',
    'sourceWidth': width, 'sourceHeight': height,
}
ack_path = output / 'screen-region-complete.json'
ack_temporary = output / 'screen-region-complete.tmp'
ack_temporary.write_text(json.dumps(ack, indent=2) + '\n')
ack_temporary.replace(ack_path)
print('Screen rectangle captured; finishing the native export.', flush=True)
