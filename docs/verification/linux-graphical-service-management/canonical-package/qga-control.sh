#!/bin/sh
set -eu
for entry in /proc/[0-9]*/comm; do
  read name < "$entry" || continue
  case "$name" in qemu-system-x86*)
    root="${entry%/comm}/root"
    if [ -f "$root/qa/meta-data" ] && /bin/grep -Fx 'instance-id: rainlink-graphical-20261020-02' "$root/qa/meta-data" >/dev/null; then
      exec "$root/qa/qga-client" "$root/run/qga.sock" "$root/qa/qga-request.json"
    fi
    ;;
  esac
done
printf 'Matching graphical QA VM is not running\n' >&2
exit 1
