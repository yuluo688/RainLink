set -euo pipefail
export DISPLAY=:91
window=$(xdotool search --onlyvisible --name '^RainLink$')
xdotool mousemove --window "$window" 35 434 click 1
sleep 3
xdotool mousemove --window "$window" 170 340 click 1
sleep 3
xdotool mousemove --window "$window" 700 500 click --repeat 6 --delay 150 5
sleep 2
python3 - <<'PY'
import gi
gi.require_version('Gdk', '3.0')
from gi.repository import Gdk
root = Gdk.get_default_root_window()
image = Gdk.pixbuf_get_from_window(root, 0, 0, root.get_width(), root.get_height())
assert image is not None
image.savev('/var/tmp/rainlink-gui-evidence/canonical-engine-before.png', 'png', [], [])
PY
