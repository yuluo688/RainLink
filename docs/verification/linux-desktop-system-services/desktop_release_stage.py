import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import time

output = Path('/qa/output/desktop-system-services')
root = Path(tempfile.mkdtemp(prefix='rainlink-desktop-release-'))
destination = root / 'Rain Link'
destination.mkdir()
archive = Path('/work/RainLink/build/RainLink-linux-x64-desktop-services.tar.xz')
with tarfile.open(archive) as bundle:
    for member in bundle.getmembers():
        target = (destination / member.name).resolve()
        assert member.isfile() and target.is_relative_to(destination)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(bundle.extractfile(member).read())
        target.chmod(member.mode)
executable = destination / 'RainLink/rainlink'
env = dict(os.environ, XDG_CONFIG_HOME=str(root/'config'),
           XDG_DATA_HOME=str(root/'data'), XDG_STATE_HOME=str(root/'state'))
result = {'isolatedRoot': str(root), 'archiveSha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
          'exitCodes': [], 'preferences': [], 'screenshots': []}
app = None
window = None
panel_log = (output/'release-panel.log').open('w')
panel = subprocess.Popen(['xfce4-panel', '--disable-wm-check'], stdout=panel_log, stderr=panel_log)

def command(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=15).stdout.strip()

def open_app():
    global app, window
    log = (output/f'release-launch-{len(result["exitCodes"])+1}.log').open('w')
    app = subprocess.Popen([str(executable)], env=env, stdout=log, stderr=log)
    window = command('xdotool', 'search', '--sync', '--pid', str(app.pid), '--name', '^RainLink$').splitlines()[-1]
    command('xdotool', 'windowactivate', '--sync', window)
    time.sleep(1)
    return {'pid': app.pid, 'window': window}

def click(x, y):
    command('xdotool', 'mousemove', '--window', window, str(x), str(y), 'click', '1')
    time.sleep(.5)

def close_app():
    if app is None or app.poll() is not None:
        return
    geometry = dict(line.split('=',1) for line in command('xdotool','getwindowgeometry','--shell',window).splitlines())
    click(int(geometry['WIDTH']) - 22, 28)
    result['exitCodes'].append(app.wait(timeout=20))

def preferences():
    files = list((root/'data').rglob('rainlink.sqlite'))
    assert len(files) == 1
    with sqlite3.connect(f'file:{files[0]}?mode=ro', uri=True) as db:
        row = db.execute('SELECT value FROM preferences WHERE key=?', ('general.preferences',)).fetchone()
    value = json.loads(row[0]) if row else None
    result['preferences'].append(value)
    return value

try:
    print(json.dumps({'ready': open_app(), 'root': str(root)}), flush=True)
    for line in sys.stdin:
        request = json.loads(line)
        action = request['action']
        if action == 'click':
            click(request['x'], request['y'])
        elif action == 'resize':
            command('xdotool', 'windowsize', window, '1440', '900')
            command('xdotool', 'windowmove', window, '80', '50')
            time.sleep(.5)
        elif action == 'capture':
            name = request['name']
            assert name.replace('-','').isalnum()
            command('import', '-window', 'root', str(output/f'{name}.png'))
            result['screenshots'].append(name)
        elif action == 'close':
            close_app()
        elif action == 'reopen':
            assert app.poll() is not None
            open_app()
        elif action == 'preferences':
            print(json.dumps({'preferences': preferences()}), flush=True)
        elif action == 'finish':
            close_app()
            assert not (root/'config/autostart/dev.rainlink.rainlink.desktop').exists()
            assert all(code == 0 for code in result['exitCodes'])
            (output/'release-runtime.json').write_text(json.dumps(result, indent=2)+'\n')
            print(json.dumps({'complete': result}), flush=True)
            break
        else:
            raise ValueError('Unknown action')
        print(json.dumps({'done': action}), flush=True)
finally:
    close_app()
    if panel.poll() is None:
        subprocess.run(['xfce4-panel','--quit'], check=True, timeout=10)
        panel.wait(timeout=10)
