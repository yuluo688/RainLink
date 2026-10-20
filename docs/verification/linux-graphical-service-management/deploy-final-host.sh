set -euo pipefail
cp /var/tmp/rainlink-gui-evidence/rainlink.log /var/tmp/rainlink-gui-evidence/first-fixed-host-application.log
cp /var/tmp/rainlink-gui-evidence/login-session.log /var/tmp/rainlink-gui-evidence/first-fixed-host-login-session.log
systemctl stop rainlink-gui-qa.service
rm -f /run/rainlink-gui-command.sh
mv /opt/rainlink-gui/RainLink/rainlink-host /opt/rainlink-gui/rainlink-host-first-fix
mv /opt/rainlink-gui/rainlink-host-final /opt/rainlink-gui/RainLink/rainlink-host
chmod 755 /opt/rainlink-gui/RainLink/rainlink-host
sha256sum /opt/rainlink-gui/RainLink/rainlink-host > /var/tmp/rainlink-gui-evidence/final-host.log
systemctl start rainlink-gui-qa.service
chvt 8
sleep 5
export DISPLAY=:91
window=$(xdotool search --onlyvisible --name '^RainLink$')
xdotool windowsize "$window" 960 640
xdotool windowmove "$window" 160 140
xdotool mousemove --window "$window" 35 434 click 1
sleep 4
xdotool mousemove --window "$window" 170 340 click 1
sleep 4
xdotool mousemove --window "$window" 700 500 click --repeat 6 --delay 150 5
sleep 3
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
