set -euo pipefail
stat -c '%a %U:%G %n' /usr/bin/pkexec /usr/lib/polkit-1/polkit-agent-helper-1
findmnt -T /usr/bin/pkexec
cat /proc/3913/status | sed -n '/Uid:/p;/Gid:/p;/NoNewPrivs/p;/Seccomp/p'
cat /proc/3913/cgroup
ls -l /proc/3913/exe
cat /etc/shells
ls -l /usr/lib/pam.d/polkit-1 /etc/pam.d/polkit-1 2>/dev/null || true
python3 - <<'PY'
from pathlib import Path
p=Path('/opt/rainlink-gui/desktop-session.sh')
s=p.read_text()
s=s.replace('/usr/bin/lxpolkit >', '''(
  last=''
  while [[ ! -f /run/rainlink-gui-finish ]]; do
    if [[ -f /run/rainlink-gui-command.sh ]]; then
      current=$(sha256sum /run/rainlink-gui-command.sh)
      if [[ "$current" != "$last" ]]; then
        last=$current
        /bin/bash /run/rainlink-gui-command.sh > "$evidence/session-command.log" 2>&1
        printf 'command_exit=%s\\n' "$?" >> "$evidence/session-command.log"
      fi
    fi
    sleep 0.25
  done
) &
/usr/bin/lxpolkit >''')
p.write_text(s)
PY
systemctl restart rainlink-gui-qa.service
chvt 8
sleep 3
loginctl list-sessions --no-pager