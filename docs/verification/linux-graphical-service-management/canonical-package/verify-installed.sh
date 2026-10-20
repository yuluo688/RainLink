set -euo pipefail
python3 - <<'PY'
import hashlib
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
assert s['state'] == 'current' and s['enabled'] and s['active'], r
expected = {
    'rainlink-host': '3c94988871e41f58fcfa486b7c58ce749b1b2cac6a217ffa9c1cf586f46394e4',
    'sing-box': '640e5293d90b94c71318031284e65cf8121d99ee9c06482f021ed77c9f3fa96d',
}
r['files'] = {}
for name, digest in expected.items():
    path = Path('/usr/libexec/rainlink') / name
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    assert actual == digest, (name, actual)
    assert hashlib.sha256((Path('/opt/rainlink-gui/RainLink') / name).read_bytes()).hexdigest() == digest
    r['files'][str(path)] = actual
Path('/var/tmp/rainlink-gui-evidence/installed-status.json').write_text(
    json.dumps(r, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(r, ensure_ascii=False))
PY
systemctl is-active rainlink-tun.socket
systemctl is-enabled rainlink-tun.socket
find /var/lib/rainlink /usr/libexec/rainlink -maxdepth 2 -printf '%m %u:%g %p\n' > /var/tmp/rainlink-gui-evidence/installed-files.log
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
image.savev('/var/tmp/rainlink-gui-evidence/canonical-installed.png', 'png', [], [])
PY
