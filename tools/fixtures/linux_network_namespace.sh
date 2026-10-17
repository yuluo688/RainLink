#!/bin/sh
# Called only inside verify_linux_network.sh's disposable namespaces.
set -eu
[ "$(id -u)" = 0 ] || exit 2
[ "$#" = 3 ] || exit 2
output=$1
core=$2
parent_namespace=$3
current_namespace=$(readlink /proc/self/ns/net)
[ -n "$parent_namespace" ] && [ "$parent_namespace" != "$current_namespace" ] || exit 2
# Make accidental invocation without unshare fail before any network mutation.
[ "$(readlink /proc/self/ns/pid)" != "$(readlink /proc/1/ns/pid)" ] && exit 2
[ "$$" = 1 ] || { echo "Run as PID 1 in the disposable namespace." >&2; exit 2; }
mount --make-rprivate /
# Recovery state is root-owned in /run. Network namespaces alone do not
# isolate that directory or a desktop's system bus.
mount -t tmpfs -o size=4m,mode=0755 tmpfs /run
printf '%s' "$current_namespace" > /run/rainlink-test-netns
mkdir -p "$output/results"
# A user's checkout may live under a 0700 home. Stage only fixture binaries in
# a private tmpfs so ordinary-user checks never need access to that home.
qa=$(mktemp -d /tmp/rainlink-network-run.XXXXXXXX)
mount -t tmpfs -o size=128m,mode=0755 tmpfs "$qa"
cp "$output/linuxnet.test" "$output/linuxtun.test" "$output/linuxprocess.test" "$output/linuxipc.test" "$output/session.test" "$output/managed-core.test" "$output/rainlink-host" "$qa/"
cp "$core" "$qa/sing-box"
core="$qa/sing-box"
chmod 755 "$qa/linuxnet.test" "$qa/linuxtun.test" "$qa/linuxprocess.test" "$qa/linuxipc.test" "$qa/session.test" "$qa/managed-core.test" "$qa/rainlink-host" "$core"
# Mount/PID/network namespaces alone do not isolate writes to /usr. Build a
# private view before the synthetic authorizer or installed helper is created.
# Keep original entries accessible via a pinned bind mount; only bin/pkcheck
# and libexec/rainlink are replaced, entirely inside this private tmpfs.
mkdir -p "$qa/original-usr" "$qa/fixture-usr/bin" "$qa/fixture-usr/libexec/rainlink"
mount --bind /usr "$qa/original-usr"
for entry in "$qa/original-usr/"* "$qa/original-usr/".[!.]* "$qa/original-usr/"..?*; do
  [ -e "$entry" ] || [ -L "$entry" ] || continue
  name=${entry##*/}
  case "$name" in bin|libexec) continue ;; esac
  ln -s "$entry" "$qa/fixture-usr/$name"
done
for directory in bin libexec; do
  for entry in "$qa/original-usr/$directory/"* "$qa/original-usr/$directory/".[!.]* "$qa/original-usr/$directory/"..?*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name=${entry##*/}
    case "$directory/$name" in bin/pkcheck|libexec/rainlink) continue ;; esac
    ln -s "$entry" "$qa/fixture-usr/$directory/$name"
  done
done
mount --bind "$qa/fixture-usr" /usr
mkdir -p "$qa/results"
mount --bind "$output/results" "$qa/results"
chmod 755 "$qa/results"
chown 65534:65534 "$qa/results"
printf 'Kernel: %s\nParent network namespace: %s\nFixture network namespace: %s\nFixture PID: %s\n' "$(uname -sr)" "$parent_namespace" "$current_namespace" "$$"
printf '%s\n' "$current_namespace" > "$output/fixture-netns.txt"
export RAINLINK_TEST_PARENT_NETNS="$parent_namespace"
export RAINLINK_TEST_NETWORK_NAMESPACE=isolated
export RAINLINK_TEST_NETWORK_EVIDENCE_DIR="$qa/results"
export RAINLINK_TEST_CORE_PATH="$core"
XDG_CURRENT_DESKTOP=RainLink-Unsupported setpriv --reuid=65534 --regid=65534 --clear-groups "$qa/rainlink-host" status > "$qa/results/host-status.json"

ip link set lo up
ip link add uplink0 type veth peer name uplink1
ip link add backup0 type veth peer name backup1
for device in uplink0 uplink1 backup0 backup1; do ip link set "$device" up; done
ip address add 192.0.2.2/24 dev uplink0
ip address add 198.51.100.2/24 dev backup0
ip -6 address add 2001:db8:1::2/64 dev uplink0 nodad
ip -6 address add 2001:db8:2::2/64 dev backup0 nodad
ip route add default via 192.0.2.1 dev uplink0 metric 40
ip route add default via 198.51.100.1 dev backup0 metric 70
ip -6 route add default via 2001:db8:1::1 dev uplink0 metric 40
ip -6 route add default via 2001:db8:2::1 dev backup0 metric 20

ip tuntap add dev rl-fixture mode tun
ip link set rl-fixture up
ip address add 172.30.255.1/30 dev rl-fixture
ip -6 address add fdfe:dcba:9877::1/126 dev rl-fixture nodad
# Tunnels must not become the upstream just because they have a lower metric.
ip route add default dev rl-fixture metric 1
ip -6 route add default dev rl-fixture metric 1
ip route add default dev rl-fixture table 100001
ip -6 route add default dev rl-fixture table 100001
ip rule add priority 30000 table 100001
ip -6 rule add priority 30000 table 100001

# New veth interfaces create link-local IPv6 addresses asynchronously. Finish
# their actual DAD before taking the exact baseline; never filter route deltas
# out of lifecycle comparisons or mistake fixture startup for TUN recovery.
dad_attempt=0
while [ -n "$(ip -6 -o address show tentative)" ]; do
  dad_attempt=$((dad_attempt+1))
  [ "$dad_attempt" -le 40 ] || { echo "Fixture IPv6 DAD did not complete." >&2; exit 2; }
  sleep 0.1
done
[ -z "$(ip -6 -o address show dadfailed)" ] || { echo "Fixture IPv6 DAD failed." >&2; exit 2; }
RAINLINK_TEST_TUN_HOLDER=isolated "$qa/linuxnet.test" -test.run='^TestIsolatedTUNFixtureHolder$' -test.timeout=30s > "$qa/tun-holder.log" 2>&1 &
tun_holder=$!
holder_attempt=0
while [ "$(head -n 1 "$qa/tun-holder.log")" != 'TUN fixture attached' ]; do
  holder_attempt=$((holder_attempt+1))
  [ "$holder_attempt" -le 40 ] || { cat "$qa/tun-holder.log" >&2; exit 2; }
  sleep 0.05
done

save_ip_state() {
  ip -j -details link show > "$qa/results/ip-links-$1.json"
  ip -j -4 route show table all > "$qa/results/ip-routes4-$1.json"
  ip -j -6 route show table all > "$qa/results/ip-routes6-$1.json"
  ip -j -4 rule show > "$qa/results/ip-rules4-$1.json"
  ip -j -6 rule show > "$qa/results/ip-rules6-$1.json"
}
save_original_install_inputs() {
  for relative in bin/pkcheck libexec/rainlink libexec/rainlink/rainlink-host libexec/rainlink/sing-box; do
    path="$qa/original-usr/$relative"
    printf '%s\n' "$relative"
    if [ -L "$path" ]; then
      stat -c '%f %u %g %s %Y' "$path"
      readlink "$path"
    elif [ -f "$path" ]; then
      stat -c '%f %u %g %s %Y' "$path"
      sha256sum < "$path"
    elif [ -e "$path" ]; then
      stat -c '%f %u %g %s %Y' "$path"
    else
      printf 'absent\n'
    fi
  done > "$qa/results/original-install-inputs-$1.txt"
}
save_original_install_inputs before
save_ip_state attached
export RAINLINK_TEST_NETWORK_STAGE=attached
setpriv --reuid=65534 --regid=65534 --clear-groups "$qa/linuxnet.test" -test.v -test.timeout=60s > "$qa/results/ordinary-tests.log" 2>&1
setpriv --reuid=65534 --regid=65534 --clear-groups "$qa/linuxtun.test" -test.v -test.timeout=60s > "$qa/results/lease-unit-tests.log" 2>&1
setpriv --reuid=65534 --regid=65534 --clear-groups "$qa/linuxprocess.test" -test.v -test.timeout=30s > "$qa/results/process-tests.log" 2>&1
setpriv --reuid=65534 --regid=65534 --clear-groups "$qa/linuxipc.test" -test.v -test.timeout=30s > "$qa/results/ipc-tests.log" 2>&1
setpriv --reuid=65534 --regid=65534 --clear-groups "$qa/managed-core.test" -test.run='^TestRainLink' -test.v -test.timeout=30s > "$qa/results/managed-core-unit-tests.log" 2>&1
setpriv --reuid=65534 --regid=65534 --clear-groups "$qa/session.test" -test.run='^Test(TUN|CancelledTUN|LinuxTUN|IsolatedDiagnosticsCannotStartTUN)' -test.v -test.timeout=30s > "$qa/results/tun-plan-tests.log" 2>&1

ip link delete rl-fixture
kill -TERM "$tun_holder"
wait "$tun_holder"
save_ip_state removed
export RAINLINK_TEST_NETWORK_STAGE=removed
setpriv --reuid=65534 --regid=65534 --clear-groups "$qa/linuxnet.test" -test.run='^TestIsolatedKernelRoutesRulesAndInterfaceRemoval$' -test.v -test.timeout=15s > "$qa/results/removed-tests.log" 2>&1
ip rule delete priority 30000 table 100001
ip -6 rule delete priority 30000 table 100001

# The core is only elevated inside these namespaces. The production capability
# remains disabled until its dedicated permission and recovery path is ready.
export RAINLINK_TEST_ROOT_TUN_NAMESPACE=isolated
export RAINLINK_TEST_CORE_PATH="$core"
"$qa/linuxipc.test" -test.run='^TestIsolatedRoot' -test.v -test.timeout=30s > "$qa/results/ipc-root-tests.log" 2>&1
mkdir -p /usr/libexec/rainlink
cp "$qa/rainlink-host" /usr/libexec/rainlink/rainlink-host
cp "$core" /usr/libexec/rainlink/sing-box
chmod 755 /usr/libexec/rainlink /usr/libexec/rainlink/rainlink-host /usr/libexec/rainlink/sing-box
"$qa/session.test" -test.run='^TestIsolatedLinuxTUNPermissionLifecycle$' -test.v -test.count=3 -test.timeout=90s > "$qa/results/permission-lifecycle-tests.log" 2>&1
"$qa/session.test" -test.run='^TestIsolatedLinuxTUNNativeClient' -test.v -test.count=3 -test.timeout=90s > "$qa/results/tun-native-client-tests.log" 2>&1
"$qa/session.test" -test.run='^TestIsolatedLinuxTUNLoggedClient' -test.v -test.count=3 -test.timeout=60s > "$qa/results/tun-logged-client-tests.log" 2>&1
"$qa/session.test" -test.run='^TestIsolatedLinuxTUNNativeClientLifecycle$/^cancel-start$' -test.v -test.count=20 -test.timeout=30s > "$qa/results/tun-native-cancellation-tests.log" 2>&1
"$qa/session.test" -test.run='^TestIsolatedLinuxTUNForwarding$' -test.v -test.count=3 -test.timeout=120s > "$qa/results/tun-forwarding-tests.log" 2>&1
"$qa/linuxnet.test" -test.run='^Test(LockedLinuxCoreTUNGracefulAndKilledPolicyState|IsolatedExactPolicyDeletionPreservesOtherOwners)$' -test.v -test.timeout=60s > "$qa/results/core-policy-tests.log" 2>&1
"$qa/linuxtun.test" -test.run='^TestIsolated(TUNLeaseAndDeadGuardianRecovery|ManagedCoreCollisionAndForeignOwner)$' -test.v -test.timeout=60s > "$qa/results/lease-kernel-tests.log" 2>&1
"$qa/linuxtun.test" -test.run='^TestIsolatedTUNWatchdog' -test.v -test.count=5 -test.timeout=60s > "$qa/results/watchdog-kernel-tests.log" 2>&1
if [ "${RAINLINK_TEST_MANAGER_NAMESPACE:-}" = isolated ]; then
  cp "$(dirname "$0")/linux_tun_manager_session.sh" "$qa/manager-session.sh"
  chmod 755 "$qa/manager-session.sh"
  export RAINLINK_TEST_MANAGER_SESSION_SCRIPT="$qa/manager-session.sh"
  export RAINLINK_TEST_HOST_PATH="$qa/rainlink-host"
  "$qa/session.test" -test.run='^TestIsolatedLinuxTUNManagerLifecycle$' -test.v -test.timeout=120s > "$qa/results/manager-lifecycle-tests.log" 2>&1
fi
save_ip_state core-killed
save_original_install_inputs after
cmp "$qa/results/original-install-inputs-before.txt" "$qa/results/original-install-inputs-after.txt"
printf 'Original authorizer and installed helper metadata/content unchanged.\n'
printf 'Ordinary-user observations, exclusive leases, exact policy deletion, and locked-core recovery tests passed.\n'
# Exiting PID 1 also kills any failed fixture descendants and releases all
# network state. No host route/rule flush or global device cleanup is used.
