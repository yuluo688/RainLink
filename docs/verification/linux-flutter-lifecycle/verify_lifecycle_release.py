import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tarfile
import tempfile
import time

output = Path('/qa/output/linux-lifecycle/release')
output.mkdir(parents=True, exist_ok=True)
root = Path(tempfile.mkdtemp(prefix='rainlink-lifecycle-release-'))
destination = root / 'Rain Link'
destination.mkdir()
archive = Path('/work/RainLink/build/RainLink-linux-x64-preview.tar.xz')
with tarfile.open(archive) as bundle:
    for member in bundle.getmembers():
        target = (destination / member.name).resolve()
        assert member.isfile() and target.is_relative_to(destination)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(bundle.extractfile(member).read())
        target.chmod(member.mode)
executable = destination / 'RainLink/rainlink'
env = dict(os.environ, XDG_CONFIG_HOME=str(root/'config'),
           XDG_DATA_HOME=str(root/'data'), XDG_STATE_HOME=str(root/'state'),
           G_DEBUG='fatal-warnings')
env.pop('NO_AT_BRIDGE', None)
panel_env = dict(env)
panel_env.pop('G_DEBUG')
result = {'archiveSha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
          'isolatedRoot': str(root), 'exitCodes': [], 'hideRestoreCycles': 0,
          'strictGtkWarnings': True, 'fixturePreferencesOnly': True}
app = None
window = None

def command(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=10).stdout.strip()

def wait_for(predicate, reason):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if predicate():
            return
        if app and app.poll() is not None:
            raise RuntimeError(f'App exited during {reason}: {app.returncode}')
        time.sleep(.1)
    raise RuntimeError(reason)

def open_app():
    global app, window
    number = len(result['exitCodes']) + 1
    log = (output/f'launch-{number}.log').open('w')
    app = subprocess.Popen([str(executable)], env=env, stdout=log, stderr=log)
    log.close()
    def find_window():
        global window
        found = subprocess.run(['xdotool','search','--onlyvisible','--pid',str(app.pid),
                                '--name','^RainLink$'], capture_output=True, text=True, timeout=3)
        if found.returncode == 0:
            window = found.stdout.splitlines()[-1]
            return True
        return False
    wait_for(find_window, 'Window did not appear')
    command('xdotool','windowactivate','--sync',window)
    time.sleep(2)
    command('import','-window','root',str(output/f'launch-{number}.png'))

def close_button():
    geometry = dict(line.split('=',1) for line in command(
        'xdotool','getwindowgeometry','--shell',window).splitlines())
    for x,y in [(160,180),(300,500),(800,28),(80,180)]:
        command('xdotool','mousemove','--window',window,str(x),str(y))
        time.sleep(.08)
    command('xdotool','mousemove','--window',window,str(int(geometry['WIDTH'])-22),'28','click','1')

def tray(method, *args, menu=False):
    return command('gdbus','call','--session','--dest',f'org.kde.StatusNotifierItem-{app.pid}-1',
                   '--object-path','/StatusNotifierMenu' if menu else '/StatusNotifierItem',
                   '--method',('com.canonical.dbusmenu.' if menu else 'org.kde.StatusNotifierItem.')+method,
                   *args)

def visible():
    return 'Map State: IsViewable' in command('xwininfo','-id',window)

panel_log = (output/'panel.log').open('w')
panel = subprocess.Popen(['xfce4-panel','--disable-wm-check'], env=panel_env,
                         stdout=panel_log, stderr=panel_log)
panel_log.close()
try:
    open_app()
    close_button()
    result['exitCodes'].append(app.wait(timeout=20))
    assert result['exitCodes'][-1] == 0
    databases = list((root/'data').rglob('rainlink.sqlite'))
    assert len(databases) == 1
    fixture = dict(autoConnect=False, showTray=True, connectionNotifications=False,
                   subscriptionExpiryNotifications=False, closeBehavior='tray')
    with sqlite3.connect(databases[0]) as db:
        db.execute('INSERT INTO preferences(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
                   ('general.preferences',json.dumps(fixture)))
    for repeat in range(2):
        open_app()
        for _ in range(2):
            close_button()
            wait_for(lambda: not visible(), 'Close button did not hide to tray')
            assert app.poll() is None
            tray('Activate','0','0')
            wait_for(visible, 'Tray activation did not restore window')
            result['hideRestoreCycles'] += 1
        command('import','-window','root',str(output/f'tray-restored-{repeat+1}.png'))
        tray('Event','4','clicked','<0>','0', menu=True)
        result['exitCodes'].append(app.wait(timeout=20))
        assert result['exitCodes'][-1] == 0
    diagnostic_logs = [(output/f'launch-{i}.log').read_text() for i in range(1,4)]
    unexpected = ['CRITICAL','WARNING','weak_unref','No engine to send','G_IS_OBJECT','SIGSEGV']
    assert all(not any(token in log for token in unexpected) for log in diagnostic_logs)
    result['gtkCriticalOrWarning'] = False
    result['implicitViewDiagnosticRetained'] = ["The implicit view cannot be removed" in log for log in diagnostic_logs]
    result['completed'] = True
    (output/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
finally:
    if app and app.poll() is None:
        app.terminate()
        app.wait(timeout=10)
    if panel.poll() is None:
        subprocess.run(['xfce4-panel','--quit'], env=panel_env, check=True, timeout=10)
        panel.wait(timeout=10)
