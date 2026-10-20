set -euo pipefail
export DISPLAY=:91
window=$(xdotool search --onlyvisible --name '^Authentication$')
xdotool windowactivate "$window"
xdotool key Escape
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
