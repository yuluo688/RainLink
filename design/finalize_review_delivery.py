"""Verify the current native review repair and refresh the 23-screen delivery."""
from pathlib import Path
from datetime import datetime, timezone
from collections import Counter
import hashlib
import json
import shutil
import zipfile
from PIL import Image

base = Path(__file__).resolve().parent
root = base / 'exports/compact-v7.5'
current = root / 'review-fixes'
audit = json.loads((current / 'live-audit.json').read_text(encoding='utf-8'))
assert audit['reviewFix']['screensAdded'] == 0
assert not audit['reviewFixVerification']['errors']
assert not audit['reviewFixVerification']['smallMobileTargets']
assert not audit['overflow'], audit['overflow']
assert not audit['untranslatedDisplayCopy'], audit['untranslatedDisplayCopy']
assert len(audit['desktop']) == 12 and len(audit['mobile']) == 11
assert audit['reviewFixVerification']['pageCount'] == 3
assert len(audit['reviewFixVerification']['protocols']) == 8
assert audit['reviewFix']['finalPolish'] == '9'
assert not audit['reviewFix']['connectionTerminology']['remainingText']
assert not audit['reviewFix']['connectionTerminology']['remainingNames']
assert audit['reviewFix']['overviewGrid']['verified']
assert all(s['delta'] < .1 and s['widthDelta'] < .1 for s in audit['reviewFix']['overviewGrid']['states'])

summary = {'verifiedAt': datetime.now(timezone.utc).isoformat()}
for platform in ('desktop', 'mobile', 'system'):
    data = json.loads((current / f'prototype-{platform}.json').read_text(encoding='utf-8'))
    assert not data['truncated']
    actions, unresolved = Counter(), []
    for c in data['connections']:
        for r in c.get('reactions', []):
            for action in r.get('actions', []):
                actions[action.get('navigation', action['type'])] += 1
                if 'destinationId' in action and action.get('destination', {}).get('status') != 'resolved':
                    unresolved.append(c['id'])
    assert not unresolved, (platform, unresolved)
    summary[platform] = {'nodesScanned': data['nodesScanned'], 'connectedNodes': len(data['connections']), 'actions': dict(actions), 'unresolved': []}
    audit['livePrototypeVerification'][platform] = dict(summary[platform], unscannedScreens=[])
    shutil.copy2(current / f'prototype-{platform}.json', root / f'prototype-review-{platform}.json')
    shutil.copy2(current / f'prototype-{platform}.json', root / f'prototype-{platform}.json')

for platform, size in [('desktop', (1440, 900)), ('mobile', (786, 1704))]:
    pictures = list((current / platform).glob('*.png'))
    assert len(pictures) == len(audit[platform]), (platform, len(pictures))
    for picture in pictures:
        with Image.open(picture) as im:
            assert im.size == size, (picture, im.size)
            im.verify()
        shutil.copy2(picture, root / platform / picture.name)

for picture in (current / 'system').glob('*.png'):
    with Image.open(picture) as im:
        im.verify()
    shutil.copy2(picture, root / 'system' / picture.name)

for picture in (current / 'states').glob('*.png'):
    with Image.open(picture) as im:
        im.verify()

native = current / 'RainLink-reviewed.fig'
verified_at = datetime.fromisoformat(audit['reviewFixVerification']['verifiedAt'].replace('Z', '+00:00'))
assert native.stat().st_mtime >= verified_at.timestamp(), 'Native backup predates the latest Figma repair'
with zipfile.ZipFile(native) as z:
    assert z.testzip() is None
    assert z.read('canvas.fig')[:8] == b'fig-kiwi'
audit['nativeBackup'] = {'bytes': native.stat().st_size, 'sha256': hashlib.sha256(native.read_bytes()).hexdigest(), 'zipCrc': 'passed', 'canvasHeader': 'fig-kiwi'}
audit['cloudSync'] = 'unverified'
audit['screenshotVerification'] = {'desktopFiles': 12, 'mobileFiles': 11, 'pngIntegrity': 'passed', 'reviewRepair': True}
audit['screenshotVerification']['stateFiles'] = len(list((current / 'states').glob('*.png')))
for name in ['RainLink.fig', 'RainLink-final.fig', 'RainLink-zh-CN.fig']:
    shutil.copy2(native, base / 'exports' / name)
shutil.copy2(native, root / 'RainLink-v7.5-zh-CN.fig')
for target in [current / 'verification.json', root / 'verification.json', base / 'exports/verification.json']:
    target.write_text(json.dumps(audit, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
(current / 'prototype-summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(json.dumps({'nativeBytes': native.stat().st_size, 'sha256': audit['nativeBackup']['sha256'], 'productScreens': 23, 'protocols': 8, 'unresolvedTargets': 0}))
