#!/bin/bash
set -euo pipefail
mkdir -p /mnt/qa-seed /opt/rainlink-gui
mount -t vfat -o rw /dev/disk/by-label/CIDATA /mnt/qa-seed
finish() {
  result=$?
  trap - EXIT
  systemctl stop rainlink-gui-qa.service || true
  journalctl -b --no-pager -u rainlink-gui-qa.service > /mnt/qa-seed/desktop-session-journal.log || true
  journalctl -b --no-pager -u polkit.service > /mnt/qa-seed/polkit-journal.log || true
  journalctl -b --no-pager -u 'rainlink-tun*' > /mnt/qa-seed/tun-journal.log || true
  if [[ -d /var/tmp/rainlink-gui-evidence ]]; then
    cp /var/tmp/rainlink-gui-evidence/* /mnt/qa-seed/ || true
  fi
  printf '%s\n' "$result" > /mnt/qa-seed/guest-result.txt
  sync
  systemctl --no-block poweroff
  exit "$result"
}
trap finish EXIT
systemctl start qemu-guest-agent.service || true
export DEBIAN_FRONTEND=noninteractive
cat > /etc/apt/sources.list.d/debian.sources <<'SOURCES'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://deb.debian.org/debian-security
Suites: trixie-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SOURCES
timeout 240 apt-get -o Acquire::Retries=1 -o Acquire::https::Timeout=25 update > /mnt/qa-seed/apt-update.log 2>&1
timeout 900 apt-get -o Dpkg::Use-Pty=0 -o Acquire::Retries=1 -o Acquire::https::Timeout=25 install -y --no-install-recommends \
  xvfb openbox xdotool x11-utils dbus-x11 lxpolkit pkexec polkitd qemu-guest-agent \
  libgtk-3-0t64 libgl1-mesa-dri libstdc++6 libsecret-tools gnome-keyring \
  gsettings-desktop-schemas dconf-cli python3 python3-gi gir1.2-gtk-3.0 kbd > /mnt/qa-seed/apt-install.log 2>&1
systemctl restart qemu-guest-agent.service
printf 'GUI_DEPENDENCIES_READY\n'
sha256sum /mnt/qa-seed/rainlink-preview.tar.xz > /mnt/qa-seed/gui-package-input.log
tar -xf /mnt/qa-seed/rainlink-preview.tar.xz -C /opt/rainlink-gui
cp /mnt/qa-seed/desktop-session.sh /opt/rainlink-gui/desktop-session.sh
chmod 755 /opt/rainlink-gui/desktop-session.sh
useradd --uid 2000 --create-home --shell /bin/bash rainlinkgui
install -d -m 700 -o rainlinkgui -g rainlinkgui /var/tmp/rainlink-gui-evidence
python3 - <<'PY'
import os, secrets, subprocess
password = secrets.token_urlsafe(28)
subprocess.run(['chpasswd'], input=f'rainlinkgui:{password}\n', text=True, check=True)
fd = os.open('/run/rainlink-gui-password', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as stream:
    stream.write(password)
os.chown('/run/rainlink-gui-password', 2000, 2000)
PY
cat > /etc/polkit-1/rules.d/44-rainlink-graphical-qa.rules <<'RULES'
function rainlinkGuiQA(action, subject) {
  var program = action.lookup('program') || '';
  return action.id === 'org.freedesktop.policykit.exec' && subject.user === 'rainlinkgui' && /^\/proc\/[0-9]+\/exe$/.test(program);
}
polkit.addRule(function(action, subject) {
  if (rainlinkGuiQA(action, subject)) return polkit.Result.AUTH_ADMIN;
});
polkit.addAdminRule(function(action, subject) {
  if (rainlinkGuiQA(action, subject)) return ['unix-user:rainlinkgui'];
});
RULES
systemctl restart polkit.service
cat > /etc/systemd/system/rainlink-gui-qa.service <<'UNIT'
[Unit]
Description=RainLink isolated graphical QA session
After=systemd-user-sessions.service systemd-logind.service
[Service]
User=rainlinkgui
PAMName=login
TTYPath=/dev/tty8
StandardInput=tty
StandardOutput=journal
StandardError=journal
TTYReset=yes
Environment=DISPLAY=:91 XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=GNOME
ExecStart=/usr/bin/dbus-run-session -- /bin/bash /opt/rainlink-gui/desktop-session.sh
TimeoutStopSec=120
KillMode=control-group
UNIT
systemctl daemon-reload
systemctl start rainlink-gui-qa.service
chvt 8
for retry in {1..180}; do
  if [[ -f /var/tmp/rainlink-gui-evidence/session-ready.log ]]; then break; fi
  systemctl is-active --quiet rainlink-gui-qa.service
  sleep 1
done
test -f /var/tmp/rainlink-gui-evidence/session-ready.log
printf 'GRAPHICAL_RAINLINK_READY\n'
for retry in {1..1800}; do
  if [[ -f /run/rainlink-gui-finish ]]; then exit 0; fi
  sleep 1
done
printf 'GUI QA timed out waiting for controller\n' >&2
exit 1
