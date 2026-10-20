set -u
cat /proc/sys/kernel/yama/ptrace_scope
cat > /run/rainlink-gui-command.sh <<'ACTION'
set -u
printf 'session_capability_diagnostic\n'
readlink /proc/4998/exe; printf 'readlink_exit=%s\n' "$?"
cat /proc/self/status | sed -n '/Uid:/p;/Gid:/p;/Cap/p;/NoNewPrivs/p'
python3 - <<'PY'
import subprocess
p=subprocess.run(['/usr/bin/pkexec','--disable-internal-agent','/proc/4998/exe','manage-tun-elevated','diagnostic'],capture_output=True,text=True,env={'PATH':'/usr/sbin:/usr/bin:/sbin:/bin','LANG':'C','LC_ALL':'C'},cwd='/')
print('path_pkexec_exit',p.returncode)
print('stdout',p.stdout)
print('stderr',p.stderr)
PY
ACTION
sleep 2
cat /var/tmp/rainlink-gui-evidence/session-command.log
cp /var/tmp/rainlink-gui-evidence/session-command.log /var/tmp/rainlink-gui-evidence/inherited-capability-failure.log