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
for name in rainlink-host linuxmanage.test sing-box; do
  cp "/mnt/qa-seed/$name" "/opt/rainlink-qa/$name"
  chmod 755 "/opt/rainlink-qa/$name"
done
sha256sum /opt/rainlink-qa/rainlink-host /opt/rainlink-qa/linuxmanage.test /opt/rainlink-qa/sing-box > /mnt/qa-seed/guest-inputs.log
printf 'Real service management VM: %s\n' "$(uname -sr)"
systemctl --version
export DEBIAN_FRONTEND=noninteractive
if [ ! -x /usr/bin/pkexec ]; then
  timeout 180 apt-get -o Acquire::Retries=1 -o Acquire::http::Timeout=20 update > /mnt/qa-seed/apt-update.log 2>&1
  timeout 180 apt-get -o Acquire::Retries=1 -o Acquire::http::Timeout=20 install -y --no-install-recommends pkexec polkitd > /mnt/qa-seed/apt-install.log 2>&1
fi
# VM-only UID/program/action rules exercise real authorization decisions.
# This is not an active desktop authentication-agent or password-dialog test.
export RAINLINK_TEST_REAL_MANAGEMENT=disposable-vm
export RAINLINK_TEST_MANAGEMENT_EVIDENCE=/mnt/qa-seed
/opt/rainlink-qa/linuxmanage.test -test.v -test.run='^TestRealSystemdManagementViaOrdinaryBroker$' -test.timeout=300s > /mnt/qa-seed/real-systemd-management-tests.log 2>&1
cat /mnt/qa-seed/real-systemd-management-tests.log
