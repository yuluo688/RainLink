set -euo pipefail
export DISPLAY=:91
xdotool mousemove 790 515 click 1
for retry in {1..60}; do
  if xdotool search --onlyvisible --name '^Authentication$' >/dev/null 2>&1; then break; fi
  sleep 0.25
done
window=$(xdotool search --onlyvisible --name '^Authentication$')
xdotool windowactivate --sync "$window"
python3 - <<'PY'
import gi
gi.require_version('Gdk', '3.0')
from gi.repository import Gdk
root = Gdk.get_default_root_window()
image = Gdk.pixbuf_get_from_window(root, 0, 0, root.get_width(), root.get_height())
assert image is not None
image.savev('/var/tmp/rainlink-gui-evidence/canonical-polkit-install.png', 'png', [], [])
PY
xdotool type --clearmodifiers --delay 40 --file /run/rainlink-gui-password
xdotool key Return
for retry in {1..90}; do
  if systemctl is-active --quiet rainlink-tun.socket; then break; fi
  sleep 0.5
done
systemctl is-active rainlink-tun.socket
systemctl is-enabled rainlink-tun.socket
sleep 3
