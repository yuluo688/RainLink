set -euo pipefail
python3 - <<'PY'
import subprocess,json,pathlib,hashlib
p=subprocess.Popen(['runuser','-u','rainlinkgui','--','/opt/rainlink-gui/RainLink/rainlink-host','manage-tun-service'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
p.stdin.write(json.dumps({'id':1,'method':'status'})+'\n');p.stdin.flush()
r=json.loads(p.stdout.readline());p.stdin.close();p.wait(timeout=15)
assert p.returncode==0,p.stderr.read()
s=r['result'];assert s['state']=='missing' and not s['enabled'] and not s['active'],r
assert not pathlib.Path('/usr/libexec/rainlink/rainlink-host').exists()
residual=[]
for entry in pathlib.Path('/proc').iterdir():
    if not entry.name.isdigit(): continue
    try: args=(entry/'cmdline').read_bytes().split(b'\0')
    except (FileNotFoundError,PermissionError): continue
    if args and args[0] in [b'/opt/rainlink-gui/RainLink/rainlink',b'/opt/rainlink-gui/RainLink/rainlink-host',b'/proc/self/fd/3']:
        residual.append((entry.name,args))
assert not residual,residual
r['noApplicationOrManagementProcesses']=True
r['finalHostSha256']=hashlib.sha256(pathlib.Path('/opt/rainlink-gui/RainLink/rainlink-host').read_bytes()).hexdigest()
pathlib.Path('/var/tmp/rainlink-gui-evidence/final-status.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(r,ensure_ascii=False))
PY
/opt/rainlink-gui/RainLink/rainlink-host status > /var/tmp/rainlink-gui-evidence/final-host-status.json
find /var/lib/rainlink /usr/libexec/rainlink -maxdepth 3 -printf '%m %u:%g %p\n' > /var/tmp/rainlink-gui-evidence/final-files.log
loginctl show-session 7 > /var/tmp/rainlink-gui-evidence/final-login-session.log
dpkg-query -W -f='${binary:Package} ${Version}\n' libgtk-3-0t64 libegl1 libgl1 libgles2 libgl1-mesa-dri lxpolkit polkitd systemd > /var/tmp/rainlink-gui-evidence/graphical-package-versions.log
cat /var/tmp/rainlink-gui-evidence/final-files.log
cat /var/tmp/rainlink-gui-evidence/application-exit.log
touch /run/rainlink-gui-finish