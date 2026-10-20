set -euo pipefail
export DISPLAY=:91
window=$(xdotool search --onlyvisible --name '^RainLink$')
xdotool mousemove --window "$window" 928 28 click 1
for retry in {1..120}; do
  if [[ -f /var/tmp/rainlink-gui-evidence/application-exit.log ]]; then break; fi
  sleep 0.25
done
grep -qx 'APPLICATION_EXITED=0' /var/tmp/rainlink-gui-evidence/application-exit.log
if xdotool search --onlyvisible --name '^RainLink$|^Authentication$' >/dev/null 2>&1; then
  printf 'A RainLink or authentication window survived exit\n' >&2
  exit 1
fi
python3 - <<'PY'
import json
from pathlib import Path
import os
survivors = []
for proc in Path('/proc').iterdir():
    if not proc.name.isdecimal():
        continue
    try:
        executable = os.readlink(proc / 'exe')
        comm = (proc / 'comm').read_text().strip()
        if comm in {'rainlink', 'rainlink-host', 'pkexec', 'sing-box'}:
            survivors.append({'pid': int(proc.name), 'comm': comm, 'executable': executable})
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        continue
assert not survivors, survivors
status = json.loads(Path('/var/tmp/rainlink-gui-evidence/host-status.json').read_text())
assert status['capabilities']['tun'] is False
remaining = sorted(str(p) for p in Path('/var/lib/rainlink/tun-install').iterdir())
assert remaining == ['/var/lib/rainlink/tun-install/install.lock'], remaining
result = {'applicationExitCode': 0, 'noApplicationOrManagementProcesses': True,
          'noAuthenticationWindow': True, 'publicTun': False,
          'remainingInstallEntries': remaining, 'noPendingTransaction': True}
Path('/var/tmp/rainlink-gui-evidence/final-status.json').write_text(
    json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
PY
loginctl show-session 1 > /var/tmp/rainlink-gui-evidence/final-login-session.log
find /var/lib/rainlink /usr/libexec/rainlink -maxdepth 3 -printf '%m %u:%g %p\n' > /var/tmp/rainlink-gui-evidence/final-files.log
cat /var/tmp/rainlink-gui-evidence/rainlink.log
touch /run/rainlink-gui-finish
