from pathlib import Path
import hashlib
import json
import zipfile

root=Path(__file__).resolve().parent
output=root/'RainLink-Design-Package.zip'
backup=root/'exports/RainLink.fig'
if not backup.exists() or backup.stat().st_size < 100_000:
    raise RuntimeError('Native .fig backup is missing or incomplete')
audit=json.loads((root/'exports/verification.json').read_text(encoding='utf-8'))
assert hashlib.sha256(backup.read_bytes()).hexdigest() == audit['nativeBackup']['sha256']
files=[root/'README.md',root.parent/'DESIGN.md',backup,root/'exports/verification.json',root/'exports/RainLink-overview.png',root/'exports/RainLink-mobile-overview.png',root/'exports/RainLink-subscriptions.png']
version=root/('exports/compact-v7' if audit['version']=='7.0' else 'exports/compact-v'+audit['version'])
if not audit.get('reviewFix'):
    files += sorted(version.glob('RainLink-*-canvas.png'))
files += sorted(version.glob('prototype-*.json'))
files += sorted((version/'desktop').glob('*.png'))
files += sorted((version/'mobile').glob('*.png'))
files += sorted((version/'system').glob('*.png'))
files += sorted((root/'plugin').glob('*.js')) + sorted((root/'plugin').glob('zh*.json')) + [root/'plugin/locale-recovery.json',root/'plugin/manifest.json',root/'update_source.py',root/'update_group_labels.py',root/'prepare_overview_v4.py',root/'make_designmd_previews.py',root/'finalize_designmd_delivery.py',root/'package_delivery.py']
files += sorted((root/'reference/awesome-design-md').glob('*.md'))
files += [root/'prepare_subscription_delivery.py',root/'make_subscription_previews.py',root/'finalize_subscription_delivery.py']
files += [root/'compact_delivery.py',root/'finalize_navigation_delivery.py']
if audit.get('reviewFix'):
    files += [root/'finalize_review_delivery.py',root/'make_review_previews.py',root/'reviews/2026-10-15/修复说明.md']
    files += sorted((version/'review-fixes').glob('*.json'))
    files += sorted((version/'review-fixes/states').glob('*.png'))
    files += sorted((version/'review-fixes/sheets').glob('*.png'))
files += [root/'home-controls-update.md']
if audit['version'] in ['7.2', '7.3', '7.4', '7.5']:
    files += [root/'exports/RainLink-compact-lists.png']
if audit['version'] in ['7.3', '7.4', '7.5']:
    files += [root/'exports/RainLink-desktop-compact.png']
if audit['version'] in ['7.4', '7.5']:
    files += [root/'exports/RainLink-node-search.png']
if audit['version'] == '7.5':
    files += [root/'exports/RainLink-settings.png']
with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as archive:
    for path in files:
        archive.write(path,'RainLink/'+('DESIGN.md' if path==root.parent/'DESIGN.md' else str(path.relative_to(root)).replace('\\','/')))
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
print(f'{output}: {output.stat().st_size:,} bytes / {len(files)} files')
