#!/bin/sh
# Root-only installation transaction tests in private mount/PID/net namespaces.
# The service driver is a fixture, not a real systemd or polkit installation.
set -eu
qa=$1
parent_namespace=$2
[ "$(id -u)" = 0 ] && [ "$$" = 1 ] || exit 2
[ "$(readlink /proc/self/ns/net)" != "$parent_namespace" ] || exit 2
mount --make-rprivate /
mount -t tmpfs -o mode=0755,size=256m tmpfs /run
"$qa/rootfs.test" -test.v -test.timeout=60s > "$qa/rootfs-tests.log" 2>&1
"$qa/linuxinstall.test" -test.v -test.timeout=120s > "$qa/install-tests.log" 2>&1
"$qa/linuxtun.test" -test.v -test.run='TestServiceExitSkipsOtherLiveSessionWithoutClaimingIdle|TestIdleConfirmationNeverRecoversOrDiscardsPendingJournal' -test.timeout=30s > "$qa/service-exit-tests.log" 2>&1
printf 'Root filesystem, transactional install, and service-exit tests passed in isolated namespaces.\n'
root=$(mktemp -d /run/rainlink-install-chroot.XXXXXXXX)
workspace=$(cd "$qa/../../.." && pwd)
printf '%s  %s\n' 412454ed98025ad9cd910d13f3d448b184e81502baa83180e89f98d0f13674be "$workspace/build/qa/linux/alpine-minirootfs-3.22.2-x86_64.tar.gz" | sha256sum -c -
tar -xzf "$workspace/build/qa/linux/alpine-minirootfs-3.22.2-x86_64.tar.gz" -C "$root"
mkdir -p "$root/proc" "$root/dev" "$root/qa" "$root/run"
mount --bind /proc "$root/proc"
mount --bind /dev "$root/dev"
for name in rainlink-host linuxinstall.test sing-box; do cp "$qa/$name" "$root/qa/$name"; chmod 755 "$root/qa/$name"; done
printf 'explicit-isolated-fixture\n' > "$root/run/rainlink-install-e2e-enabled"
cat > "$root/usr/bin/systemctl" <<'FIXTURE'
#!/bin/sh
exec /qa/linuxinstall.test -test.run='^TestSystemctlFixtureCommand$' -- "$@"
FIXTURE
cat > "$root/usr/bin/pkcheck" <<'FIXTURE'
#!/bin/sh
# No start request is sent; authorization must never be requested by install.
exit 81
FIXTURE
chmod 755 "$root/usr/bin/systemctl" "$root/usr/bin/pkcheck"
chroot "$root" /qa/linuxinstall.test -test.v -test.run='^TestInstalledCLIWithLockedCoreAndLiveIdleProtocol$' -test.timeout=120s > "$qa/cli-fixture-tests.log" 2>&1
cp "$root/run/rainlink-activation-fixture.log" "$qa/activation-fixture.log"
printf 'Real installer CLI, locked core and idle Unix protocol passed with fixture service activation.\n'
