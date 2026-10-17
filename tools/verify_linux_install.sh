#!/usr/bin/env bash
# Synthetic service-driver acceptance; never install into the calling system.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || { echo "Run on a Linux QA host as root." >&2; exit 2; }
qa="$repo_root/build/qa/linux-install"
mkdir -p "$qa"
(
  cd "$repo_root/native/host"
  go vet ./internal/rootfs ./internal/linuxinstall ./internal/linuxtun ./cmd/rainlink-host
  go test -c -o "$qa/rootfs.test" ./internal/rootfs
  go test -c -o "$qa/linuxinstall.test" ./internal/linuxinstall
  go test -c -o "$qa/linuxtun.test" ./internal/linuxtun
  go build -trimpath -o "$qa/rainlink-host" ./cmd/rainlink-host
)
cp "$repo_root/build/host/linux-amd64/sing-box" "$qa/sing-box"
parent_namespace="$(readlink /proc/self/ns/net)"
unshare --mount --net --pid --fork --mount-proc --kill-child=SIGKILL -- /bin/sh "$repo_root/tools/fixtures/linux_install_namespace.sh" "$qa" "$parent_namespace"
echo "Installation transaction fixtures passed. Actual systemd/polkit acceptance remains separate."
