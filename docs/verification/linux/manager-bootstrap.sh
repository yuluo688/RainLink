#!/bin/sh
set -eu
[ "$$" = 1 ] || exit 2
workspace=/mnt/host/c/Users/FalingFliff/Documents/ChatGPT/RainLink
qa="$workspace/build/qa/linux-manager"
parent_namespace=$1
[ "$parent_namespace" != "$(readlink /proc/self/ns/net)" ] || exit 2
mount --make-rprivate /
root=$(mktemp -d /tmp/rainlink-network-qa.XXXXXXXX)
printf 'Ephemeral rootfs mount: %s\n' "$root"
mount -t tmpfs -o size=1200m,mode=0755 tmpfs "$root"
printf '%s  %s\n' 412454ed98025ad9cd910d13f3d448b184e81502baa83180e89f98d0f13674be "$workspace/build/qa/linux/alpine-minirootfs-3.22.2-x86_64.tar.gz" | sha256sum -c -
tar -xzf "$workspace/build/qa/linux/alpine-minirootfs-3.22.2-x86_64.tar.gz" -C "$root"
mkdir -p "$root/proc" "$root/dev" "$root/work" "$root/qa/packages"
mount --bind /proc "$root/proc"
mount --bind /dev "$root/dev"
mount --bind "$workspace" "$root/work"
cp "$qa"/packages/*.apk "$root/qa/packages/"
for filename in "$root"/qa/packages/*.apk; do
  chroot "$root" /sbin/apk --no-network --repositories-file /dev/null verify "/qa/packages/${filename##*/}"
done
chroot "$root" /bin/sh -c 'exec /sbin/apk --no-network --force-non-repository --repositories-file /dev/null add /qa/packages/*.apk'
# Existing installation sentinels exist only in this disposable rootfs.
mkdir -p "$root/usr/libexec/rainlink"
printf 'rainlink-fixture-original-authorizer\n' > "$root/usr/bin/pkcheck"
printf 'rainlink-fixture-original-host\n' > "$root/usr/libexec/rainlink/rainlink-host"
printf 'rainlink-fixture-original-core\n' > "$root/usr/libexec/rainlink/sing-box"
chmod 755 "$root/usr/bin/pkcheck" "$root/usr/libexec/rainlink/rainlink-host" "$root/usr/libexec/rainlink/sing-box"
export RAINLINK_TEST_MANAGER_NAMESPACE=isolated
exec chroot "$root" /bin/sh /work/tools/fixtures/linux_network_namespace.sh /work/build/qa/linux-manager /work/build/host/linux-amd64/sing-box "$parent_namespace"
