#!/bin/bash
# Runs exclusively inside the disposable cloud image created by the QA runner.
set -euo pipefail
mkdir -p /mnt/qa-seed /opt/rainlink-qa
mount -t vfat -o rw /dev/disk/by-label/CIDATA /mnt/qa-seed
finish() {
  result=$?
  trap - EXIT
  journalctl -b --no-pager -u 'rainlink-tun*' > /mnt/qa-seed/systemd-journal.log || true
  cp /var/log/cloud-init-output.log /mnt/qa-seed/cloud-output.log || true
  printf '%s\n' "$result" > /mnt/qa-seed/guest-result.txt
  sync
  systemctl --no-block poweroff
  exit "$result"
}
trap finish EXIT
for name in rainlink-host linuxinstall.test sing-box; do
  cp "/mnt/qa-seed/$name" "/opt/rainlink-qa/$name"
  chmod 755 "/opt/rainlink-qa/$name"
done
sha256sum /opt/rainlink-qa/rainlink-host /opt/rainlink-qa/linuxinstall.test /opt/rainlink-qa/sing-box > /mnt/qa-seed/guest-inputs.log
printf 'Real systemd VM: %s\n' "$(uname -sr)"
systemctl --version
export DEBIAN_FRONTEND=noninteractive
if [ ! -x /usr/bin/pkcheck ]; then
  timeout 180 apt-get -o Acquire::Retries=1 -o Acquire::http::Timeout=20 update > /mnt/qa-seed/apt-update.log 2>&1
  timeout 180 apt-get -o Acquire::Retries=1 -o Acquire::http::Timeout=20 install -y --no-install-recommends polkitd > /mnt/qa-seed/apt-install.log 2>&1
fi
systemctl show rainlink-tun.socket --all --no-pager --property=LoadState,ActiveState,UnitFileState,FragmentPath,DropInPaths > /mnt/qa-seed/raw-unit-state.log 2>&1 || true
RAINLINK_TEST_REAL_SYSTEMD=disposable-vm /opt/rainlink-qa/linuxinstall.test -test.v -test.run='^TestRealSystemdInstallation$' -test.timeout=300s > /mnt/qa-seed/real-systemd-tests.log 2>&1
cat /mnt/qa-seed/real-systemd-tests.log
