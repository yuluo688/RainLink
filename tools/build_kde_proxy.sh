#!/usr/bin/env bash
# Builds the unprivileged helper beside the Linux host; never changes settings.
set -euo pipefail
[[ "$(uname -s)" == Linux ]] || { echo "Build the KDE helper on Linux." >&2; exit 2; }
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "Unsupported architecture" >&2; exit 2 ;;
esac
output_directory="${1:-$repo_root/build/host/linux-$arch}"
# Match Flutter's documented Ninja toolchain and keep old Makefile caches valid.
build_directory="$repo_root/build/native/kde-proxy-$arch/ninja"
cmake -G Ninja -S "$repo_root/native/linux/kde_proxy" -B "$build_directory" -DCMAKE_BUILD_TYPE=Release
cmake --build "$build_directory" --parallel 2
install -m 755 -D "$build_directory/rainlink-kde-proxy" "$output_directory/rainlink-kde-proxy"
