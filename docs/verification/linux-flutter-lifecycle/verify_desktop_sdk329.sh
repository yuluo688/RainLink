#!/bin/bash
set -euo pipefail
export PATH=/home/rainlinkqa/flutter-3.29.3/bin:/opt/go/bin:$PATH
export FLUTTER_ROOT=/home/rainlinkqa/flutter-3.29.3
unset NO_AT_BRIDGE
export XDG_CONFIG_HOME=/tmp/rainlink-desktop-integration-sdk329/config
export XDG_DATA_HOME=/tmp/rainlink-desktop-integration-sdk329/data
export XDG_STATE_HOME=/tmp/rainlink-desktop-integration-sdk329/state
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
output=/qa/output/linux-lifecycle/desktop-integration
mkdir -p "$output"
xfce4-panel --disable-wm-check > "$output/panel.log" 2>&1 &
panel_pid=$!
dunst > "$output/dunst.log" 2>&1 &
dunst_pid=$!
cleanup() {
  kill "$panel_pid" "$dunst_pid" 2>/dev/null || true
  wait "$panel_pid" "$dunst_pid" 2>/dev/null || true
}
trap cleanup EXIT
cd /work/RainLink/app
flutter --no-version-check --suppress-analytics test \
  integration_test/linux_desktop_integration_test.dart -d linux --no-pub \
  --dart-define=RAINLINK_TEST_DESKTOP=isolated \
  --dart-define=RAINLINK_HOST_PATH=/work/RainLink/build/host/linux-amd64/rainlink-host \
  --dart-define=RAINLINK_VISUAL_OUTPUT="$output" > "$output/test.log" 2>&1
printf 'DESKTOP_SDK329_VERIFIED\n'
