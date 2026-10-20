#!/bin/bash
# Disposable VM only: a fresh graphical user, private origin and real polkit.
set -euo pipefail
[[ "${RAINLINK_TEST_TUN_PRODUCT:-}" == disposable-vm ]] || exit 2
[[ "$(id -u)" == 0 && "$(cat /proc/1/comm)" == systemd ]] || exit 2
for tool in ip python3 Xvfb openbox xdotool lxpolkit gnome-keyring-daemon secret-tool; do
  command -v "$tool" >/dev/null || { echo "Missing VM fixture dependency: $tool" >&2; exit 2; }
done
evidence=/var/tmp/rainlink-tun-product
application=/opt/rainlink-tun-product
fixture_route_metric=1
mkdir -p /mnt/qa-seed "$application"
mount -t vfat -o rw /dev/disk/by-label/CIDATA /mnt/qa-seed
finish() {
  result=$?
  trap - EXIT
  systemctl stop rainlink-tun-product-qa.service || true
  "$application/RainLink/rainlink-host" uninstall-tun > "$evidence/cleanup-uninstall.log" 2>&1 || result=1
  for name in origin socks; do
    if [[ -f "$evidence/$name.pid" ]]; then kill "$(cat "$evidence/$name.pid")" 2>/dev/null || true; fi
  done
  ip route del default via 10.77.0.2 dev rqa0 2>/dev/null || true
  ip -6 route del default via fd77::2 dev rqa0 2>/dev/null || true
  ip link del rqa0 2>/dev/null || true
  ip netns del rainlink-origin 2>/dev/null || true
  journalctl -b --no-pager -u rainlink-tun-product-qa.service > "$evidence/session-journal.log" || result=1
  journalctl -b --no-pager -u polkit.service > "$evidence/polkit-journal.log" || result=1
  journalctl -b --no-pager -u 'rainlink-tun*' > "$evidence/tun-journal.log" || result=1
  ip -j -d link show > "$evidence/final-links.json"
  ip -j -4 rule show > "$evidence/final-rules4.json"
  ip -j -6 rule show > "$evidence/final-rules6.json"
  find /run/rainlink /var/lib/rainlink -maxdepth 3 -type f -printf '%p\n' > "$evidence/final-files.log" 2>/dev/null || true
  cp "$evidence/"* /mnt/qa-seed/
  printf '%s\n' "$result" > /mnt/qa-seed/guest-result.txt
  sync
  systemctl --no-block poweroff
  exit "$result"
}
useradd --uid 2200 --create-home --shell /bin/bash rainlinktun
useradd --uid 2201 --create-home --shell /bin/bash rainlinktraffic
install -d -m 755 -o rainlinktun -g rainlinktun "$evidence"
trap finish EXIT
tar -xf /mnt/qa-seed/rainlink-preview.tar.xz -C "$application"
cp /mnt/qa-seed/linux_tun_product_{network.py,session.sh,snapshot.py} "$application/"
chmod 755 "$application/linux_tun_product_session.sh"
sha256sum "$application/RainLink/"{rainlink,rainlink-host,sing-box} > "$evidence/product-inputs.log"
systemctl restart qemu-guest-agent.service
ip -j -d link show > "$evidence/initial-links.json"
ip -j -4 rule show > "$evidence/initial-rules4.json"
ip -j -6 rule show > "$evidence/initial-rules6.json"
python3 - "$fixture_route_metric" <<'PY'
import json, subprocess, sys
metric = int(sys.argv[1])
for family in ('-4', '-6'):
    routes = json.loads(subprocess.check_output(['ip', '-j', family, 'route', 'show', 'table', 'main']))
    if any(route.get('dst') == 'default' and route.get('metric', 0) <= metric for route in routes):
        raise SystemExit('QA requires a higher-priority default route; existing defaults will not be replaced.')
PY
ip netns add rainlink-origin
ip link add rqa0 type veth peer name rqa1
ip link set rqa1 netns rainlink-origin
ip addr add 10.77.0.1/24 dev rqa0
ip -6 addr add fd77::1/64 dev rqa0 nodad
ip link set rqa0 up
ip netns exec rainlink-origin ip addr add 10.77.0.2/24 dev rqa1
ip netns exec rainlink-origin ip -6 addr add fd77::2/64 dev rqa1 nodad
ip netns exec rainlink-origin ip link set rqa1 up
ip netns exec rainlink-origin ip link set lo up
ip netns exec rainlink-origin ip addr add 10.78.0.2/32 dev lo
ip netns exec rainlink-origin ip -6 addr add fd78::2/128 dev lo nodad
# IPv6 coerces metric 0 to 1024, which loses to the VM's metric-100 RA route.
# Metric 1 keeps both families on the private fixture without replacing routes.
ip route add default via 10.77.0.2 dev rqa0 metric "$fixture_route_metric"
ip -6 route add default via fd77::2 dev rqa0 metric "$fixture_route_metric"
python3 - "$application" <<'PY'
import json, os, secrets, subprocess, sys
from pathlib import Path
password = secrets.token_urlsafe(28)
subprocess.run(['chpasswd'], input=f'rainlinktun:{password}\n', text=True, check=True)
with open('/run/rainlink-tun-password', 'x') as stream:
    stream.write(password)
os.chmod('/run/rainlink-tun-password', 0o600)
os.chown('/run/rainlink-tun-password', 2200, 2200)
node_password = secrets.token_hex(20)
with open('/run/rainlink-tun-node-link', 'x') as stream:
    stream.write(f'socks5://tunqa:{node_password}@10.77.0.2:1080#Linux-TUN-QA')
os.chmod('/run/rainlink-tun-node-link', 0o600)
configuration = {'log': {'level': 'info'}, 'inbounds': [
    {'type': 'socks', 'tag': 'fixture', 'listen': '::', 'listen_port': 1080,
     'users': [{'username': 'tunqa', 'password': node_password}]}],
    'outbounds': [{'type': 'direct'}]}
config = Path('/run/rainlink-tun-origin.json')
config.write_text(json.dumps(configuration))
config.chmod(0o600)
PY
ip netns exec rainlink-origin python3 "$application/linux_tun_product_network.py" serve --output "$evidence/origin-receipts.jsonl" > "$evidence/origin.log" 2>&1 &
printf '%s\n' "$!" > "$evidence/origin.pid"
ip netns exec rainlink-origin "$application/RainLink/sing-box" run -c /run/rainlink-tun-origin.json > "$evidence/socks.log" 2>&1 &
printf '%s\n' "$!" > "$evidence/socks.pid"
for attempt in {1..100}; do
  if grep -q ORIGIN_RECEIPTS_READY "$evidence/origin.log"; then break; fi
  sleep 0.1
done
grep -q ORIGIN_RECEIPTS_READY "$evidence/origin.log"
runuser -u rainlinktraffic -- python3 "$application/linux_tun_product_network.py" probe --prefix before-tun --output /tmp/rainlink-tun-baseline.json
cp /tmp/rainlink-tun-baseline.json "$evidence/baseline-traffic.json"
cat > /etc/polkit-1/rules.d/44-rainlink-tun-product-qa.rules <<'RULES'
function rainlinkTunProductQA(action, subject) {
  return subject.user === 'rainlinktun' &&
    ((action.id === 'org.freedesktop.policykit.exec' && /^\/proc\/[0-9]+\/exe$/.test(action.lookup('program') || '')) ||
      action.id === 'org.rainlink.tun.manage');
}
polkit.addRule(function(action, subject) {
  if (rainlinkTunProductQA(action, subject)) return polkit.Result.AUTH_ADMIN;
});
polkit.addAdminRule(function(action, subject) {
  if (rainlinkTunProductQA(action, subject)) return ['unix-user:rainlinktun'];
});
RULES
systemctl restart polkit.service
cat > /etc/systemd/system/rainlink-tun-product-qa.service <<'UNIT'
[Unit]
Description=RainLink isolated product TUN QA
After=systemd-user-sessions.service systemd-logind.service
[Service]
User=rainlinktun
PAMName=login
TTYPath=/dev/tty8
StandardInput=tty
StandardOutput=journal
StandardError=journal
TTYReset=yes
Environment=DISPLAY=:91 XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=GNOME
ExecStart=/usr/bin/dbus-run-session -- /bin/bash /opt/rainlink-tun-product/linux_tun_product_session.sh
TimeoutStopSec=60
KillMode=control-group
UNIT
systemctl daemon-reload
systemctl start rainlink-tun-product-qa.service
chvt 8
for attempt in {1..180}; do
  if [[ -f "$evidence/session-ready.log" ]]; then break; fi
  systemctl is-active --quiet rainlink-tun-product-qa.service
  sleep 1
done
[[ -f "$evidence/session-ready.log" ]]
printf 'TUN_PRODUCT_GUI_READY\n'
for attempt in {1..3000}; do
  if [[ -f /run/rainlink-tun-product-finish ]]; then
    [[ "$(cat /run/rainlink-tun-product-finish)" == 0 ]]
    exit 0
  fi
  sleep 1
done
echo 'Product fixture did not receive its completion receipt.' >&2
exit 1
