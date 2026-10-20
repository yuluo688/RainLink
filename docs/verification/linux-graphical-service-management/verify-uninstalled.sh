set -euo pipefail
python3 - <<'PY'
import subprocess,json,pathlib,time
for attempt in range(15):
    p=subprocess.Popen(['runuser','-u','rainlinkgui','--','/opt/rainlink-gui/RainLink/rainlink-host','manage-tun-service'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    p.stdin.write(json.dumps({'id':1,'method':'status'})+'\n');p.stdin.flush()
    r=json.loads(p.stdout.readline());p.stdin.close();p.wait(timeout=15)
    assert p.returncode==0,p.stderr.read()
    if r['result']['state']=='missing':break
    time.sleep(1)
s=r['result'];assert s['state']=='missing' and not s['enabled'] and not s['active'],r
for f in ['/usr/libexec/rainlink/rainlink-host','/usr/libexec/rainlink/sing-box','/etc/systemd/system/rainlink-tun.socket','/etc/systemd/system/rainlink-tun@.service']:
    assert not pathlib.Path(f).exists(),f
r['noManagedExecutablesOrUnits']=True
pathlib.Path('/var/tmp/rainlink-gui-evidence/uninstalled-status.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(r,ensure_ascii=False))
PY
ps -eo uid,pid,ppid,comm,args | awk '$4 ~ /rainlink|pkexec|lxpolkit/ {print}' > /var/tmp/rainlink-gui-evidence/processes-after-uninstall.log
find /var/lib/rainlink /usr/libexec/rainlink -maxdepth 3 -printf '%m %u:%g %p\n' > /var/tmp/rainlink-gui-evidence/uninstalled-files.log
/opt/rainlink-gui/RainLink/rainlink-host status > /var/tmp/rainlink-gui-evidence/host-status.json
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
