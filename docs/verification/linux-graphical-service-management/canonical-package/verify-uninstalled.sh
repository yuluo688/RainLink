set -euo pipefail
python3 - <<'PY'
import json
from pathlib import Path
import subprocess

p = subprocess.Popen(
    ['runuser', '-u', 'rainlinkpkg', '--',
     '/opt/rainlink-gui/RainLink/rainlink-host', 'manage-tun-service'],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
p.stdin.write(json.dumps({'id': 1, 'method': 'status'}) + '\n')
p.stdin.flush()
r = json.loads(p.stdout.readline())
p.stdin.close()
p.wait(timeout=15)
assert p.returncode == 0, p.stderr.read()
s = r['result']
assert s['state'] == 'missing' and not s['enabled'] and not s['active'], r
for f in ['/usr/libexec/rainlink/rainlink-host', '/usr/libexec/rainlink/sing-box',
          '/etc/systemd/system/rainlink-tun.socket', '/etc/systemd/system/rainlink-tun@.service']:
    assert not Path(f).exists(), f
assert list(Path('/var/lib/rainlink/tun-install').iterdir()) == [Path('/var/lib/rainlink/tun-install/install.lock')]
r['noManagedExecutablesOrUnits'] = True
r['noPendingTransaction'] = True
Path('/var/tmp/rainlink-gui-evidence/uninstalled-status.json').write_text(
    json.dumps(r, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(r, ensure_ascii=False))
PY
find /var/lib/rainlink /usr/libexec/rainlink -maxdepth 3 -printf '%m %u:%g %p\n' > /var/tmp/rainlink-gui-evidence/uninstalled-files.log
/opt/rainlink-gui/RainLink/rainlink-host status > /var/tmp/rainlink-gui-evidence/host-status.json
python3 - <<'PY'
import json
from pathlib import Path
status = json.loads(Path('/var/tmp/rainlink-gui-evidence/host-status.json').read_text())
assert status['capabilities']['tun'] is False, status
print('PUBLIC_TUN_FALSE')
PY
export DISPLAY=:91
window=$(xdotool search --onlyvisible --name '^RainLink$')
xdotool mousemove --window "$window" 700 500 click --repeat 4 --delay 150 5
sleep 3
python3 - <<'PY'
import gi
gi.require_version('Gdk', '3.0')
from gi.repository import Gdk
root = Gdk.get_default_root_window()
image = Gdk.pixbuf_get_from_window(root, 0, 0, root.get_width(), root.get_height())
assert image is not None
image.savev('/var/tmp/rainlink-gui-evidence/canonical-uninstalled.png', 'png', [], [])
PY
