from pathlib import Path
from PIL import Image
import hashlib
import json
import shutil
import zipfile

root=Path(__file__).resolve().parent
version=root/'exports/subscription-v6'
native=version/'RainLink-v6-zh-CN.fig'
with zipfile.ZipFile(native) as archive:
    assert archive.testzip() is None
    assert archive.read('canvas.fig')[:8]==b'fig-kiwi'
sha=hashlib.sha256(native.read_bytes()).hexdigest()
audit=json.loads((version/'verification.json').read_text(encoding='utf-8'))
for platform,size in [('desktop',(1440,900)),('mobile',(786,1704))]:
    files=list((version/platform).glob('*.png'))
    assert len(files)==len(audit[platform]),(platform,len(files),len(audit[platform]))
    for path in files:
        with Image.open(path) as im:
            assert im.size==size,(path.name,im.size)
            im.verify()
for path in (version/'system').glob('*.png'):
    with Image.open(path) as im: im.verify()
assert not audit['overflow'] and not audit['untranslatedDisplayCopy']
assert audit['subscriptionDialogs']['addIsOverlay']
assert audit['subscriptionDialogs']['subscriptionNameFieldRemoved']
assert audit['egress']['usesDetectedEgress'] and audit['egress']['nodeRegionNotUsed']
assert audit['egress']['fixtureDataOnly'] and audit['egress']['noLiveNetworkRequest']
assert audit['egress']['powerTransitions']
for platform in ['desktop','mobile']:
    assert not audit['livePrototypeVerification'][platform]['unresolved']
    assert not audit['livePrototypeVerification'][platform]['unscannedScreens']
assert audit['v6SemanticVerification']['overlayEntryCount']>0
assert audit['v6SemanticVerification']['overlayCloseCount']>0
assert audit['v6SemanticVerification']['modeChangesInvalidateEgress']
assert audit['v6SemanticVerification']['countryIconsVerified']
audit['nativeBackup']={'file':'exports/RainLink.fig','bytes':native.stat().st_size,'sha256':sha,'zipCrc':'passed','canvasHeader':'fig-kiwi'}
audit['screenshotVerification']={'desktopFiles':len(audit['desktop']),'desktopPixels':[1440,900],'mobileFiles':len(audit['mobile']),'mobilePixels':[786,1704],'systemPanels':len(list((version/'system').glob('*.png'))),'pngIntegrity':'passed'}
(version/'verification.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for name in ['RainLink.fig','RainLink-final.fig','RainLink-zh-CN.fig']:
    shutil.copy2(native,root/'exports'/name)
for name in ['verification.json','RainLink-overview.png','RainLink-mobile-overview.png','RainLink-subscriptions.png']:
    shutil.copy2(version/name,root/'exports'/name)
print(json.dumps({'nativeBytes':native.stat().st_size,'nativeSha256':sha,'integrity':'passed'}))
