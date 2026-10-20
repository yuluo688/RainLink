#!/bin/sh
set -eu
[ "$$" = 1 ] || exit 2
workspace=/mnt/host/c/Users/FalingFliff/Documents/ChatGPT/RainLink
qa="$workspace/build/qa/linux-manage/vm-broker-write-20261020-01"
mount --make-rprivate /
root=$(mktemp -d /tmp/rainlink-qemu.XXXXXXXX)
mount -t tmpfs -o size=512m,mode=0755 tmpfs "$root"
tar -xzf "$workspace/build/qa/linux/alpine-minirootfs-3.22.2-x86_64.tar.gz" -C "$root"
mkdir -p "$root/proc" "$root/dev" "$root/qa" "$root/packages"
mount --bind /proc "$root/proc"
mount --bind /dev "$root/dev"
mount --bind "$qa" "$root/qa"
cp /etc/resolv.conf "$root/etc/resolv.conf"
cp "$workspace/build/qa/linux-install/vm-cache/packages/"*.apk "$root/packages/"
for filename in "$root/packages/"*.apk; do
  chroot "$root" /sbin/apk --no-network --repositories-file /dev/null verify "/packages/${filename##*/}"
done
chroot "$root" /bin/sh -c 'exec /sbin/apk --no-network --force-non-repository --repositories-file /dev/null add /packages/*.apk'
mkdir -p "$root/previous" "$root/qa/vm-cache"
mount --bind "$workspace/build/qa/linux-install" "$root/previous"
mount -o remount,bind,ro "$root/previous"
mount --bind "$workspace/build/qa/linux-install/vm-cache" "$root/qa/vm-cache"
mount -o remount,bind,ro "$root/qa/vm-cache"
chroot "$root" /bin/sh /qa/vm-inner.sh "${1:-run}"
