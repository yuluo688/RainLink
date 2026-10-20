#!/bin/bash
set -euo pipefail
export PATH=/opt/flutter/bin:/opt/go/bin:$PATH
export FLUTTER_ROOT=/opt/flutter
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn PUB_HOSTED_URL=https://pub.flutter-io.cn
export CMAKE_BUILD_PARALLEL_LEVEL=2
repo_root=/work/RainLink
flutter_command=/opt/flutter/bin/flutter
dart_command=/opt/flutter/bin/dart
host_directory="$repo_root/build/host/linux-amd64"
task=package
cd "$repo_root/app"
flutter_flags=(--no-version-check --suppress-analytics)
"$flutter_command" "${flutter_flags[@]}" pub get --offline --enforce-lockfile
"$dart_command" run tool/generate_build_info.dart
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
printf "OFFLINE_LINUX_PACKAGE_COMPLETED\n"
