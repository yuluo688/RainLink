#!/bin/bash
set -euo pipefail
export DISPLAY=:91 GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1
export XDG_CURRENT_DESKTOP=GNOME XDG_SESSION_TYPE=x11 NO_AT_BRIDGE=1
export LANG=C.UTF-8 LC_ALL=C.UTF-8
evidence=/var/tmp/rainlink-gui-evidence
Xvfb :91 -screen 0 1600x1000x24 -nolisten tcp > "$evidence/xvfb.log" 2>&1 &
xvfb_pid=$!
trap 'kill "$xvfb_pid" 2>/dev/null || true' EXIT
for retry in {1..100}; do if xdpyinfo >/dev/null 2>&1; then break; fi; sleep 0.1; done
xdpyinfo >/dev/null
openbox > "$evidence/openbox.log" 2>&1 &
gnome-keyring-daemon --unlock --components=secrets < /run/rainlink-gui-password > "$evidence/keyring.log" 2>&1
printf 'isolated' | secret-tool store --label='RainLink GUI QA' rainlink-gui ready
[[ "$(secret-tool lookup rainlink-gui ready)" == isolated ]]
secret-tool clear rainlink-gui ready
/usr/bin/lxpolkit > "$evidence/authentication-agent.log" 2>&1 &
agent_pid=$!
sleep 1
kill -0 "$agent_pid"
loginctl show-session "$XDG_SESSION_ID" > "$evidence/login-session.log"
printf 'GUI_SESSION_READY\n' > "$evidence/session-ready.log"
/opt/rainlink-gui/RainLink/rainlink > "$evidence/rainlink.log" 2>&1 &
app_pid=$!
printf '%s\n' "$app_pid" > "$evidence/application.pid"
wait "$app_pid"
printf 'APPLICATION_EXITED=0\n' > "$evidence/application-exit.log"
while [[ ! -f /run/rainlink-gui-finish ]]; do sleep 1; done
