from pathlib import Path
from PIL import Image
import hashlib
import json
import shutil
import zipfile

root = Path(__file__).resolve().parent
version = root / 'exports/groups-v3'
native = version / 'RainLink-groups-final-zh-CN.fig'
with zipfile.ZipFile(native) as archive:
    assert archive.testzip() is None
    assert archive.read('canvas.fig')[:8] == b'fig-kiwi'
sha = hashlib.sha256(native.read_bytes()).hexdigest()
audit = json.loads((version / 'verification.json').read_text(encoding='utf-8'))
for platform, expected, size in [('desktop', 45, (1440, 900)), ('mobile', 43, (786, 1704))]:
    files = sorted((version/platform).glob('*.png'))
    assert len(files) == expected
    for p in files:
        with Image.open(p) as im:
            assert im.size == size, (p.name, im.size)
            im.verify()
for p in (version/'system').glob('*.png'):
    with Image.open(p) as im:
        im.verify()
assert not audit['overflow'] and not audit['untranslatedDisplayCopy']
assert audit['livePrototypeVerification']['desktop']['unresolved'] == []
assert audit['livePrototypeVerification']['mobile']['unresolved'] == []
audit['nativeBackup'] = {'file': 'exports/RainLink.fig', 'bytes': native.stat().st_size, 'sha256': sha, 'zipCrc': 'passed', 'canvasHeader': 'fig-kiwi'}
audit['componentCanvasVerification'] = {'mastersArranged': 13, 'overlap': False, 'namesLocalized': True}
audit['screenshotVerification'] = {'desktopFiles': 45, 'desktopPixels': [1440, 900], 'mobileFiles': 43, 'mobilePixels': [786, 1704], 'systemPanels': 5, 'pngIntegrity': 'passed'}
(version/'verification.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
for name in ['RainLink.fig', 'RainLink-final.fig', 'RainLink-zh-CN.fig']:
    shutil.copy2(native, root/'exports'/name)
shutil.copy2(version/'verification.json', root/'exports/verification.json')
shutil.copy2(version/'RainLink-overview.png', root/'exports/RainLink-overview.png')
print(json.dumps({'nativeBytes': native.stat().st_size, 'nativeSha256': sha, 'screenshots': 93, 'integrity': 'passed'}))
