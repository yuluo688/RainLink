set -euo pipefail
export DISPLAY=:91
window=$(xdotool search --onlyvisible --name '^RainLink$')
xdotool mousemove --window "$window" 335 580 click 1
sleep 2
python3 - <<'PY'
import gi
gi.require_version('Gdk', '3.0')
from gi.repository import Gdk
root = Gdk.get_default_root_window()
image = Gdk.pixbuf_get_from_window(root, 0, 0, root.get_width(), root.get_height())
assert image is not None
image.savev('/var/tmp/rainlink-gui-evidence/canonical-install-confirm.png', 'png', [], [])
PY
