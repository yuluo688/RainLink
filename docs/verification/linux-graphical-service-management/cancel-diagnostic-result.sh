set -euo pipefail
export DISPLAY=:91
window=$(xdotool search --onlyvisible --name '^Authentication$')
xdotool windowactivate "$window"
xdotool key Escape
sleep 2
cat /var/tmp/rainlink-gui-evidence/session-command.log
cp /var/tmp/rainlink-gui-evidence/session-command.log /var/tmp/rainlink-gui-evidence/polkit-cancel-exit-diagnostic.log