#!/bin/bash
set -euo pipefail
cd /work/RainLink/app
flutter --no-version-check --suppress-analytics test --no-pub integration_test/overview_connection_test.dart -d linux --dart-define=RAINLINK_HOST_PATH=/work/overview-final-unpacked/RainLink/rainlink-host --dart-define=RAINLINK_VISUAL_OUTPUT=/qa/output/overview-connection-linux --reporter expanded > /qa/output/overview-connection-linux.log 2>&1
printf 'FINAL_LINUX_OVERVIEW_CONNECTION_PASSED\n'
flutter --no-version-check --suppress-analytics test --no-pub integration_test/ui_alignment_test.dart -d linux --dart-define=RAINLINK_VISUAL_OUTPUT=/qa/output/overview-layout-linux --reporter expanded > /qa/output/overview-layout-linux.log 2>&1
printf 'FINAL_LINUX_54_LAYOUT_FIXTURES_PASSED\n'
export XDG_DATA_HOME=/work/overview-release-user-data
/work/overview-final-unpacked/RainLink/rainlink > /qa/output/overview-release-stdout.log 2>&1 &
release_pid=$!
for retry in {1..100}; do
  if xdotool search --onlyvisible --name '^RainLink$' >/dev/null 2>&1; then break; fi
  sleep 0.1
done
sleep 2
python3 /qa/capture_native.py overview-final-release-960
window=$(xdotool search --onlyvisible --name '^RainLink$')
xdotool mousemove --window "$window" 928 28 click 1
wait "$release_pid"
for process in rainlink-host sing-box; do
  if pgrep -u "$(id -u)" -x "$process"; then
    printf 'Release left a child process: %s\n' "$process" >&2
    exit 1
  fi
done
printf 'FINAL_LINUX_AOT_WINDOW_AND_CLOSE_PASSED\n'
