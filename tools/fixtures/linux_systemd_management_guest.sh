#!/bin/bash
# Fixed-path service management through real pkexec, inside the disposable VM.
set -euo pipefail
mkdir -p /mnt/qa-seed /opt/rainlink-qa
mount -t vfat -o rw /dev/disk/by-label/CIDATA /mnt/qa-seed
finish() {
  result=$?
  trap - EXIT
  journalctl -b --no-pager -u 'rainlink-tun*' > /mnt/qa-seed/systemd-journal.log || true
  journalctl -b --no-pager -u polkit.service > /mnt/qa-seed/polkit-journal.log || true
  cp /var/log/cloud-init-output.log /mnt/qa-seed/cloud-output.log || true
  printf '%s\n' "$result" > /mnt/qa-seed/guest-result.txt
  sync
  systemctl --no-block poweroff
  exit "$result"
}
trap finish EXIT
for name in rainlink-host linuxmanage.test linuxinstall.test sing-box; do
  cp "/mnt/qa-seed/$name" "/opt/rainlink-qa/$name"
  chmod 755 "/opt/rainlink-qa/$name"
done
mkdir -p /opt/rainlink-qa/previous
cp /mnt/qa-seed/previous-host /opt/rainlink-qa/previous/rainlink-host
chmod 755 /opt/rainlink-qa/previous/rainlink-host
cp /opt/rainlink-qa/sing-box /opt/rainlink-qa/previous/sing-box
cp /mnt/qa-seed/linux_polkit_agent.py /opt/rainlink-qa/linux_polkit_agent.py
sha256sum /opt/rainlink-qa/rainlink-host /opt/rainlink-qa/linuxmanage.test /opt/rainlink-qa/linuxinstall.test /opt/rainlink-qa/sing-box /opt/rainlink-qa/previous/rainlink-host /opt/rainlink-qa/linux_polkit_agent.py > /mnt/qa-seed/guest-inputs.log
printf 'Real service management VM: %s\n' "$(uname -sr)"
systemctl --version
export DEBIAN_FRONTEND=noninteractive
if [ ! -x /usr/bin/pkcheck ]; then
  timeout 180 apt-get -o Acquire::Retries=1 -o Acquire::http::Timeout=20 update > /mnt/qa-seed/apt-update.log 2>&1
  timeout 180 apt-get -o Acquire::Retries=1 -o Acquire::http::Timeout=20 install -y --no-install-recommends polkitd > /mnt/qa-seed/apt-install.log 2>&1
fi
for package in pkexec python3-dbus; do
  archive="/mnt/qa-seed/$package.deb"
  version=$(dpkg-deb -f "$archive" Version)
  [[ $(dpkg-deb -f "$archive" Package) == "$package" ]]
  [[ $(dpkg-deb -f "$archive" Architecture) == amd64 ]]
  expected=$(apt-cache show "$package=$version" | awk '/^SHA256:/{print $2; exit}')
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]]
  printf '%s  %s\n' "$expected" "$archive" | sha256sum --check >> /mnt/qa-seed/signed-dependency-check.log
  timeout 60 dpkg --install "$archive" > "/mnt/qa-seed/$package-install.log" 2>&1
done
# VM-only UID/program/action rules exercise real authorization decisions.
# The protocol agent below requests AUTH_ADMIN but never reads a password.
# It is distinct from an active desktop's graphical authentication agent.
export RAINLINK_TEST_REAL_MANAGEMENT=disposable-vm
export RAINLINK_TEST_MANAGEMENT_EVIDENCE=/mnt/qa-seed
/opt/rainlink-qa/linuxmanage.test -test.v -test.run='^(TestRealSystemdManagementViaOrdinaryBroker|TestRealPolkitManagementAuthenticationCancellation)$' -test.timeout=360s > /mnt/qa-seed/real-systemd-management-tests.log 2>&1
cat /mnt/qa-seed/real-systemd-management-tests.log
export RAINLINK_TEST_REAL_SYSTEMD=disposable-vm
export RAINLINK_TEST_INSTALL_CANCELLATION_EVIDENCE=/mnt/qa-seed
/opt/rainlink-qa/linuxinstall.test -test.v -test.run='^TestRealSystemdCancellationAtDurableBoundaries$' -test.timeout=540s > /mnt/qa-seed/real-systemd-cancellation-tests.log 2>&1
cat /mnt/qa-seed/real-systemd-cancellation-tests.log
