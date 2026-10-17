#!/system/bin/sh
# The QA client runs as shell UID, outside RainLink's excluded application UID.
test_apk=$(pm path dev.rainlink.rainlink.test | head -n 1)
case "$test_apk" in
  package:*) test_apk=${test_apk#package:} ;;
  *) printf 'RainLink instrumentation APK is missing\n'; exit 1 ;;
esac
if [ ! -r "$test_apk" ]; then
  printf 'RainLink instrumentation APK is not readable\n'
  exit 1
fi
CLASSPATH="$test_apk" exec app_process / dev.rainlink.rainlink.core.TunnelRequest \
  "$1" "$2" "${3:-/probe}" "${4:-18080}" 2>&1
