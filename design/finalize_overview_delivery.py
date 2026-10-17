from pathlib import Path
from PIL import Image
import hashlib
import json
import shutil
import zipfile

root=Path(__file__).resolve().parent
version=root/'exports/overview-v4'
native=version/'RainLink-overview-final-zh-CN.fig'
with zipfile.ZipFile(native) as archive:
    assert archive.testzip() is None
    assert archive.read('canvas.fig')[:8]==b'fig-kiwi'
sha=hashlib.sha256(native.read_bytes()).hexdigest()
audit=json.loads((version/'verification.json').read_text(encoding='utf-8'))
for platform,size in [('desktop',(1440,900)),('mobile',(786,1704))]:
    files=sorted((version/platform).glob('*.png'))
    assert len(files)==len(audit[platform]), (platform,len(files),len(audit[platform]))
    for p in files:
        with Image.open(p) as im:
            assert im.size==size,(p.name,im.size)
            im.verify()
for p in (version/'system').glob('*.png'):
    with Image.open(p) as im: im.verify()
assert not audit['overflow'] and not audit['untranslatedDisplayCopy']
for platform in ['desktop','mobile']:
    assert not audit['livePrototypeVerification'][platform]['unresolved']
controls=audit['overviewControls']
for edge in controls['stateEdges']:
    assert edge['kind'] in ['select-group','select-node','select-chain','select-group-pending','vpn-power']
assert audit['stateSemanticVerification']['selectionDoesNotConnect']
assert audit['stateSemanticVerification']['powerOnlyOnOverview']
assert audit['stateSemanticVerification']['modeOnlyOnOverview']
assert audit['stateSemanticVerification']['workspaceTextCount']==0
audit['nativeBackup']={'file':'exports/RainLink.fig','bytes':native.stat().st_size,'sha256':sha,'zipCrc':'passed','canvasHeader':'fig-kiwi'}
audit['screenshotVerification']={'desktopFiles':len(audit['desktop']),'desktopPixels':[1440,900],'mobileFiles':len(audit['mobile']),'mobilePixels':[786,1704],'systemPanels':len(list((version/'system').glob('*.png'))),'pngIntegrity':'passed'}
(version/'verification.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for name in ['RainLink.fig','RainLink-final.fig','RainLink-zh-CN.fig']:
    shutil.copy2(native,root/'exports'/name)
shutil.copy2(version/'verification.json',root/'exports/verification.json')
shutil.copy2(version/'RainLink-overview.png',root/'exports/RainLink-overview.png')
print(json.dumps({'nativeBytes':native.stat().st_size,'nativeSha256':sha,'integrity':'passed'}))
