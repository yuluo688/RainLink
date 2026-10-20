#!/bin/sh
set -eu
cd /qa
if [ "${1:-run}" = extract ]; then
  result="/qa/systemd-results-$(date +%s)"
  mkdir "$result"
  mcopy -i /qa/seed.img '::/*.log' "$result/"
  mcopy -i /qa/seed.img '::/broker-replacement-*.json' "$result/" || true
mcopy -i /qa/seed.img ::/guest-result.txt "$result/"
  printf 'Extracted guest results: %s\n' "$result"
  exit 0
fi
if [ ! -f /qa/systemd-overlay.qcow2 ]; then
  qemu-img create -f qcow2 -F qcow2 -b /previous/systemd-overlay.qcow2 /qa/systemd-overlay.qcow2
fi
truncate -s 192M /qa/seed.img
mformat -i /qa/seed.img -F -v CIDATA ::
for name in user-data meta-data rainlink-host linuxmanage.test sing-box vm-guest.sh pkexec.deb previous-host python3-dbus.deb linux_polkit_agent.py linuxinstall.test; do
  mcopy -i /qa/seed.img "/qa/$name" "::/$name"
done
# User-mode networking exposes no host listener and touches only this VM.
timeout 900 qemu-system-x86_64 -machine pc,accel=tcg,smm=off -cpu qemu64 -m 1536 -smp 1 -vga none -display none -serial stdio -monitor none -qmp unix:/run/qmp.sock,server=on,wait=off -no-reboot -drive file=/qa/systemd-overlay.qcow2,if=virtio,format=qcow2 -drive file=/qa/seed.img,if=virtio,format=raw -netdev user,id=net0 -device virtio-net-pci,netdev=net0 > /qa/vm-serial.log 2>&1
result="/qa/systemd-results-$(date +%s)"
mkdir "$result"
mcopy -i /qa/seed.img '::/*.log' "$result/"
mcopy -i /qa/seed.img '::/broker-replacement-*.json' "$result/" || true
mcopy -i /qa/seed.img ::/guest-result.txt "$result/"
printf 'Guest results: %s\n' "$result"
[ "$(cat "$result/guest-result.txt")" = 0 ]
