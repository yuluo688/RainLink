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
case "$(uname -m)" in
  x86_64) core_arch=amd64 ;;
  arm64|aarch64) core_arch=arm64 ;;
  *) echo "Unsupported desktop architecture" >&2; exit 2 ;;
esac
host_directory="$repo_root/build/host/$core_os-$core_arch"
host_binary="$host_directory/rainlink-host"
case "$task" in
  check)
    cd "$repo_root/native/host"
    unformatted="$(gofmt -l cmd internal)"
    [[ -z "$unformatted" ]] || { echo "Run gofmt: $unformatted" >&2; exit 1; }
    go vet ./...
    go test ./...
    ;;
  run|smoke)
    if [[ "$device" == linux ]]; then
      python3 "$repo_root/tools/setup_core.py" --platform "$core_os-$core_arch"
      if [[ ":${XDG_CURRENT_DESKTOP:-}:" == *:KDE:* || "${RAINLINK_BUILD_KDE_PROXY:-0}" == 1 ]]; then
        bash "$repo_root/tools/build_kde_proxy.sh" "$host_directory"
      fi
    fi
    mkdir -p "$host_directory"
    (cd "$repo_root/native/host" && go build -trimpath -o "$host_binary" ./cmd/rainlink-host)
    ;;
  generate) ;;
  *) echo "Usage: bash tools/dev.sh [run|check|smoke|generate]" >&2; exit 2 ;;
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
esac
