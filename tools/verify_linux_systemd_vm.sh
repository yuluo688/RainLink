#!/usr/bin/env bash
# Real systemd install acceptance. Only virtual disks are modified; the guest
# has no host folders, devices, credentials or inbound network ports shared.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == Linux ]] || { echo "Run on a Linux QA host." >&2; exit 2; }
for tool in go python3 qemu-system-x86_64 qemu-img mformat mcopy timeout; do
  command -v "$tool" >/dev/null || { echo "Required QA tool unavailable: $tool" >&2; exit 2; }
done
test_binary=linuxinstall.test
test_package=linuxinstall
guest_source=linux_systemd_guest.sh
result_log=real-systemd-tests.log
case "${1:-}" in
  "") ;;
  --permission-logs)
    test_binary=session.test
    test_package=session
    guest_source=linux_systemd_logs_guest.sh
    result_log=real-systemd-log-tests.log
    ;;
  --service-management)
    test_binary=linuxmanage.test
    test_package=linuxmanage
    guest_source=linux_systemd_management_guest.sh
    result_log=real-systemd-management-tests.log
    ;;
  *) echo "Usage: $0 [--permission-logs|--service-management]" >&2; exit 2 ;;
esac
cache="$repo_root/build/qa/linux-install/vm-cache"
mkdir -p "$cache"
python3 - "$repo_root/tools/linux_systemd_qa.lock.json" "$cache" <<'PY'
import hashlib, json, pathlib, sys, urllib.request
lock = json.loads(pathlib.Path(sys.argv[1]).read_text())
path = pathlib.Path(sys.argv[2]) / lock['imageName']
def digest(filename):
    value = hashlib.sha512()
    with open(filename, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()
if not path.exists():
    temporary = path.with_suffix('.download')
    with urllib.request.urlopen(lock['imageUrl'], timeout=30) as response, open(temporary, 'wb') as stream:
        for chunk in iter(lambda: response.read(1024 * 1024), b''):
            stream.write(chunk)
    if digest(temporary) != lock['sha512']:
        raise SystemExit('QA image does not match reviewed lock; upstream latest may have changed.')
    temporary.replace(path)
if digest(path) != lock['sha512']:
    raise SystemExit('Cached QA image does not match the reviewed lock.')
print('Official QA image SHA512 verified.')
PY
run="$repo_root/build/qa/linux-systemd/$(date +%Y%m%dT%H%M%S)-$$"
mkdir -p "$run/results"
export GOTOOLCHAIN="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["goVersion"])' "$repo_root/tools/core.lock.json")"
(
  cd "$repo_root/native/host"
  GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go test -c -o "$run/$test_binary" "./internal/$test_package"
  GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -o "$run/rainlink-host" ./cmd/rainlink-host
)
cp "$repo_root/build/host/linux-amd64/sing-box" "$run/sing-box"
cp "$repo_root/tools/fixtures/$guest_source" "$run/guest.sh"
cat > "$run/user-data" <<'CLOUD'
#cloud-config
hostname: rainlink-disposable-qa
manage_etc_hosts: true
ssh_pwauth: false
runcmd:
  - [mkdir, -p, /mnt/qa-bootstrap]
  - [mount, -t, vfat, -o, ro, /dev/disk/by-label/CIDATA, /mnt/qa-bootstrap]
  - [cp, /mnt/qa-bootstrap/guest.sh, /run/rainlink-qa.sh]
  - [umount, /mnt/qa-bootstrap]
  - [bash, /run/rainlink-qa.sh]
CLOUD
printf 'instance-id: rainlink-systemd-%s\nlocal-hostname: rainlink-disposable-qa\n' "$(date +%s)-$$" > "$run/meta-data"
qemu-img create -f qcow2 -F qcow2 -b "$cache/debian-13-genericcloud-amd64.qcow2" "$run/overlay.qcow2"
truncate -s 192M "$run/seed.img"
mformat -i "$run/seed.img" -F -v CIDATA ::
for name in user-data meta-data rainlink-host "$test_binary" sing-box guest.sh; do mcopy -i "$run/seed.img" "$run/$name" "::/$name"; done
# smm=off avoids a SeaBIOS SMM stall under nested TCG. This is virtual firmware
# configuration, independent of the product's kernel or privilege requirements.
result=0
timeout 720 qemu-system-x86_64 -machine pc,accel=tcg,smm=off -cpu qemu64 -m 1536 -smp 1 -vga none -display none -serial stdio -monitor none -no-reboot \
  -drive "file=$run/overlay.qcow2,if=virtio,format=qcow2" \
  -drive "file=$run/seed.img,if=virtio,format=raw" \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 > "$run/serial.log" 2>&1 || result=$?
if [[ "$result" != 0 ]]; then echo "VM failed ($result); evidence retained in $run" >&2; exit "$result"; fi
mcopy -i "$run/seed.img" '::/*.log' "$run/results/"
if [[ "$test_package" == session ]]; then mcopy -i "$run/seed.img" '::/*.json' "$run/results/"; fi
mcopy -i "$run/seed.img" ::/guest-result.txt "$run/results/"
cat "$run/results/$result_log"
[[ "$(cat "$run/results/guest-result.txt")" == 0 ]] || { echo "Guest acceptance failed; evidence retained in $run" >&2; exit 1; }
echo "Real systemd acceptance passed. Desktop polkit authentication prompts remain a separate test. Evidence: $run"
