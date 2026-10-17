#!/usr/bin/env bash
# Tests network observation and locked-core policy lifecycle in disposable
# mount, PID and network namespaces. Run on a Linux QA host with root access.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || { echo "Run on a Linux QA host as root." >&2; exit 2; }
for tool in go python3 ip unshare mount setpriv; do
  command -v "$tool" >/dev/null || { echo "Required tool unavailable: $tool" >&2; exit 2; }
done
[[ -c /dev/net/tun ]] || { echo "TUN device unavailable." >&2; exit 2; }
qa="$repo_root/build/qa/linuxnet"
case "${1:-}" in
  "") ;;
  --managed-host|--permission-logs)
    if [[ "$1" == --permission-logs ]]; then
      qa="$repo_root/build/qa/linux-logs"
    else
      qa="$repo_root/build/qa/linux-managed-host"
    fi
    export RAINLINK_TEST_MANAGER_NAMESPACE=isolated
    for tool in /usr/bin/dbus-run-session /usr/bin/dbus-send /usr/bin/gnome-keyring-daemon /usr/bin/dconf /usr/bin/gsettings; do
      [[ -x "$tool" ]] || { echo "Managed-host fixture requires: $tool" >&2; exit 2; }
    done
    ;;
  *) echo "Usage: $0 [--managed-host|--permission-logs]" >&2; exit 2 ;;
esac
mkdir -p "$qa"
export GOTOOLCHAIN="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["goVersion"])' "$repo_root/tools/core.lock.json")"
case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  *) echo "Locked-core Linux TUN acceptance currently requires amd64." >&2; exit 2 ;;
esac
python3 "$repo_root/tools/setup_core.py" --platform "linux-$arch"
cp "$repo_root/build/core-tests/linux-$arch/sing-tun.test" "$qa/managed-core.test"
(
  cd "$repo_root/native/host"
  go vet ./internal/linuxnet ./internal/linuxprocess ./internal/linuxipc ./internal/linuxtun ./internal/session
  go test -c -o "$qa/linuxnet.test" ./internal/linuxnet
  go test -c -o "$qa/linuxtun.test" ./internal/linuxtun
  go test -c -o "$qa/linuxprocess.test" ./internal/linuxprocess
  go test -c -o "$qa/linuxipc.test" ./internal/linuxipc
  go test -c -o "$qa/session.test" ./internal/session
  go build -trimpath -o "$qa/rainlink-host" ./cmd/rainlink-host
)
parent_namespace="$(readlink /proc/self/ns/net)"
unshare --mount --net --pid --fork --mount-proc --kill-child=SIGKILL -- /bin/sh "$repo_root/tools/fixtures/linux_network_namespace.sh" "$qa" "$repo_root/build/host/linux-$arch/sing-box" "$parent_namespace"
echo "Namespace tests passed. This does not enable production Linux TUN or validate a desktop authorization prompt."
