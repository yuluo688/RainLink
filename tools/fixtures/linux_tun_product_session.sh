#!/bin/bash
set -euo pipefail
export DISPLAY=:91 GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1
export XDG_CURRENT_DESKTOP=GNOME XDG_SESSION_TYPE=x11 NO_AT_BRIDGE=1
export LANG=C.UTF-8 LC_ALL=C.UTF-8
evidence=/var/tmp/rainlink-tun-product
Xvfb :91 -screen 0 1600x1000x24 -nolisten tcp > "$evidence/xvfb.log" 2>&1 &
xvfb_pid=$!
trap 'kill "$xvfb_pid" 2>/dev/null || true' EXIT
for attempt in {1..100}; do if xdpyinfo >/dev/null 2>&1; then break; fi; sleep 0.1; done
xdpyinfo >/dev/null
openbox > "$evidence/openbox.log" 2>&1 &
gnome-keyring-daemon --unlock --components=secrets < /run/rainlink-tun-password > "$evidence/keyring.log" 2>&1
printf isolated | secret-tool store --label='RainLink TUN QA' rainlink-tun ready
[[ "$(secret-tool lookup rainlink-tun ready)" == isolated ]]
secret-tool clear rainlink-tun ready
/usr/bin/lxpolkit > "$evidence/authentication-agent.log" 2>&1 &
sleep 1
loginctl show-session "$XDG_SESSION_ID" > "$evidence/login-session.log"
env -0 > /run/user/2200/rainlink-tun-session-environment
printf 'GUI_SESSION_READY\n' > "$evidence/session-ready.log"
/opt/rainlink-tun-product/RainLink/rainlink > "$evidence/rainlink.log" 2>&1 &
app_pid=$!
printf '%s\n' "$app_pid" > "$evidence/application.pid"
wait "$app_pid"
printf 'APPLICATION_EXITED=0\n' > "$evidence/application-exit.log"
while [[ ! -f /run/rainlink-tun-product-finish ]]; do sleep 1; done
