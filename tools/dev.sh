#!/usr/bin/env bash
set -euo pipefail

task="${1:-run}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${FLUTTER_ROOT:-}" ]]; then
  flutter_command="$FLUTTER_ROOT/bin/flutter"
  dart_command="$FLUTTER_ROOT/bin/dart"
else
  flutter_command="$(command -v flutter)"
  dart_command="$(command -v dart)"
fi
case "$(uname -s)" in
  Darwin) device=macos; core_os=darwin ;;
  Linux) device=linux; core_os=linux ;;
  *) echo "Use tools/dev.ps1 on Windows." >&2; exit 2 ;;
esac
if [[ "$device" == linux ]]; then
  # The management broker clears capabilities across Go runtime threads. Keep
  # the host in pure Go so AllThreadsSyscall can include every native thread.
  export CGO_ENABLED=0
fi
case "$(uname -m)" in
  x86_64) core_arch=amd64 ;;
  arm64|aarch64) core_arch=arm64 ;;
  *) echo "Unsupported desktop architecture" >&2; exit 2 ;;
esac
if [[ "$task" == package && "$device" == macos ]]; then
  echo "macOS DMG signing and notarization are not implemented; use build for a local development app." >&2
  exit 2
fi
if [[ "$device" == linux && ( "$task" == build || "$task" == package ) ]]; then
  [[ "$core_arch" == amd64 ]] || {
    echo "Linux release packaging currently requires x64 and a locked Linux core." >&2
    exit 2
  }
fi
host_directory="$repo_root/build/host/$core_os-$core_arch"
host_binary="$host_directory/rainlink-host"
if [[ "$device" == macos ]]; then
  host_binary="$repo_root/build/macos/$core_arch/runtime/rainlink-host"
fi
case "$task" in
  check)
    cd "$repo_root/native/host"
    unformatted="$(gofmt -l cmd internal)"
    [[ -z "$unformatted" ]] || { echo "Run gofmt: $unformatted" >&2; exit 1; }
    go vet ./...
    go test ./...
    python3 "$repo_root/tools/test_core_sources.py"
    python3 "$repo_root/tools/test_package_windows.py"
    python3 "$repo_root/tools/test_package_linux.py"
    python3 "$repo_root/tools/test_build_macos.py"
    ;;
  run|smoke|build|package)
    if [[ "$device" == macos ]]; then
      python3 "$repo_root/tools/build_macos.py" prepare --arch "$core_arch"
    fi
    if [[ "$device" == linux ]]; then
      python3 "$repo_root/tools/setup_core.py" --platform "$core_os-$core_arch"
      if [[ "$task" == build || "$task" == package || ":${XDG_CURRENT_DESKTOP:-}:" == *:KDE:* || "${RAINLINK_BUILD_KDE_PROXY:-0}" == 1 ]]; then
        bash "$repo_root/tools/build_kde_proxy.sh" "$host_directory"
      fi
      mkdir -p "$host_directory"
      (cd "$repo_root/native/host" && go build -trimpath -o "$host_binary" ./cmd/rainlink-host)
    fi
    ;;
  generate) ;;
  *) echo "Usage: bash tools/dev.sh [run|check|smoke|generate|build|package]" >&2; exit 2 ;;
esac

cd "$repo_root/app"
flutter_flags=(--no-version-check --suppress-analytics)
"$flutter_command" "${flutter_flags[@]}" pub get --enforce-lockfile
"$dart_command" run tool/generate_build_info.dart
case "$task" in
  check)
    "$dart_command" format --output=none --set-exit-if-changed lib test integration_test tool
    "$flutter_command" "${flutter_flags[@]}" analyze --no-pub
    "$flutter_command" "${flutter_flags[@]}" test --no-pub
    ;;
  generate) "$dart_command" run build_runner build --delete-conflicting-outputs ;;
  run) "$flutter_command" "${flutter_flags[@]}" run -d "$device" "--dart-define=RAINLINK_HOST_PATH=$host_binary" ;;
  smoke) "$flutter_command" "${flutter_flags[@]}" test integration_test/desktop_smoke_test.dart -d "$device" "--dart-define=RAINLINK_HOST_PATH=$host_binary" ;;
  build|package)
    if [[ "$device" == macos ]]; then
      "$flutter_command" "${flutter_flags[@]}" build macos --release --no-pub
      python3 "$repo_root/tools/build_macos.py" bundle --arch "$core_arch"
      exit 0
    fi
    "$flutter_command" "${flutter_flags[@]}" build linux --release --no-pub
    release="$repo_root/app/build/linux/x64/release/bundle"
    for name in rainlink-host rainlink-kde-proxy sing-box; do
      install -m 755 "$host_directory/$name" "$release/$name"
    done
    for name in sing-box-source.zip sing-box-LICENSE.txt; do
      install -m 644 "$host_directory/$name" "$release/$name"
    done
    install -m 644 -D "$repo_root/app/linux/runner/resources/rainlink.png" \
      "$release/data/icons/hicolor/512x512/apps/dev.rainlink.rainlink.png"
    install -m 644 "$repo_root/app/linux/packaging/dev.rainlink.rainlink.desktop" "$release/"
    package_flags=()
    if [[ "$task" == build ]]; then package_flags+=(--manifest-only); fi
    sdk_root="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve().parent.parent)' "$flutter_command")"
    python3 "$repo_root/tools/package_linux.py" --flutter-root "$sdk_root" "${package_flags[@]}"
    ;;
esac
