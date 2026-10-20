set -euo pipefail
python3 - <<'PY'
import subprocess,json,pathlib,hashlib
p=subprocess.Popen(['runuser','-u','rainlinkgui','--','/opt/rainlink-gui/RainLink/rainlink-host','manage-tun-service'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
p.stdin.write(json.dumps({'id':1,'method':'status'})+'\n');p.stdin.flush()
r=json.loads(p.stdout.readline());p.stdin.close();p.wait(timeout=15)
assert p.returncode==0,p.stderr.read()
s=r['result'];assert s['state']=='current' and s['enabled'] and s['active'],r
paths=['/usr/libexec/rainlink/rainlink-host','/usr/libexec/rainlink/sing-box']
r['files']={f:hashlib.sha256(pathlib.Path(f).read_bytes()).hexdigest() for f in paths}
assert r['files'][paths[0]]==hashlib.sha256(pathlib.Path('/opt/rainlink-gui/RainLink/rainlink-host').read_bytes()).hexdigest()
assert r['files'][paths[1]]==hashlib.sha256(pathlib.Path('/opt/rainlink-gui/RainLink/sing-box').read_bytes()).hexdigest()
pathlib.Path('/var/tmp/rainlink-gui-evidence/installed-status.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(r,ensure_ascii=False))
PY
systemctl is-active rainlink-tun.socket
systemctl is-enabled rainlink-tun.socket
find /var/lib/rainlink /usr/libexec/rainlink -maxdepth 2 -printf '%m %u:%g %p\n' > /var/tmp/rainlink-gui-evidence/installed-files.log
export DISPLAY=:91
window=$(xdotool search --onlyvisible --name '^RainLink$')
xdotool mousemove --window "$window" 700 500 click --repeat 3 --delay 150 5
sleep 2
set -euo pipefail
export DISPLAY=:91 GDK_BACKEND=x11 NO_AT_BRIDGE=1
for retry in {1..80}; do
  if xdotool search --onlyvisible --name '^RainLink$' >/dev/null 2>&1; then break; fi
  sleep 0.25
done
window=$(xdotool search --onlyvisible --name '^RainLink$')
xdotool getwindowgeometry --shell "$window"
python3 - <<'PY'
import gi
gi.require_version('Gdk', '3.0')
from gi.repository import Gdk
root=Gdk.get_default_root_window()
image=Gdk.pixbuf_get_from_window(root,0,0,root.get_width(),root.get_height())
assert image is not None
image.savev('/var/tmp/rainlink-gui-evidence/desktop-current.png','png',[],[])
PY
cat /var/tmp/rainlink-gui-evidence/rainlink.log
loginctl list-sessions --no-pager
