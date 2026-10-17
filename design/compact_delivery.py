from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import argparse
import hashlib
import json
import shutil
import zipfile

base = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--finalize', action='store_true')
parser.add_argument('--version', choices=['7.0', '7.1', '7.2', '7.3', '7.4', '7.5'], default='7.5')
args = parser.parse_args()
root = base / ('exports/compact-v7' if args.version == '7.0' else f'exports/compact-v{args.version}')
audit = json.loads((root/'verification.json').read_text(encoding='utf-8'))
font_path = 'C:/Windows/Fonts/msyh.ttc'

def font(size):
    return ImageFont.truetype(font_path, size)

def slug(key):
    return key.lower().replace(' ', '-')

def insert(canvas, platform, key, xy, size):
    with Image.open(root/platform/f'{slug(key)}.png') as im:
        canvas.paste(im.convert('RGB').resize(size, getattr(Image, 'Resampling', Image).LANCZOS), xy)

canvas = Image.new('RGB', (2000, 1140), '#0F1011')
draw = ImageDraw.Draw(canvas)
draw.text((48, 30), 'RainLink / 精简版', font=font(44), fill='#F4F4F6')
draw.text((48, 100), '同页完成选择与连接，保留必要页面和弹窗。', font=font(24), fill='#969AA3')
insert(canvas, 'desktop', 'Dashboard', (48, 180), (1440, 900))
insert(canvas, 'mobile', 'Home', (1540, 180), (393, 852))
canvas.save(root/'RainLink-overview.png')

canvas = Image.new('RGB', (1748, 1110), '#0F1011')
draw = ImageDraw.Draw(canvas)
draw.text((40, 24), 'RainLink / 移动端', font=font(40), fill='#F4F4F6')
for key, label, x in [('Home', 'IP 与国旗', 40), ('Nodes', '分组与节点选择', 466), ('Profiles', '流量与有效期', 892), ('Chain editor', '可视化代理链', 1318)]:
    draw.text((x, 112), label, font=font(20), fill='#969AA3')
    insert(canvas, 'mobile', key, (x, 156), (393, 852))
canvas.save(root/'RainLink-mobile-overview.png')

canvas = Image.new('RGB', (2000, 900), '#0F1011')
draw = ImageDraw.Draw(canvas)
draw.text((48, 24), 'RainLink / 添加与订阅', font=font(40), fill='#F4F4F6')
insert(canvas, 'desktop', 'Profiles', (48, 140), (1144, 715))
insert(canvas, 'mobile', 'Profiles', (1232, 140), (329, 713))
insert(canvas, 'mobile', 'Import profile', (1600, 140), (329, 713))
canvas.save(root/'RainLink-subscriptions.png')

if args.version in ['7.2', '7.3', '7.4', '7.5']:
    canvas = Image.new('RGB', (906, 1040), '#0F1011')
    draw = ImageDraw.Draw(canvas)
    draw.text((40, 24), 'RainLink / 紧凑列表', font=font(30), fill='#F4F4F6')
    draw.text((40, 72), '分组保留用量与到期信息，节点详情集中在节点列表。', font=font(17), fill='#969AA3')
    for key, label, x in [('Profiles', '分组 108 px · 未分组 66 px', 40), ('Nodes', '节点 72 px · 列表间距 8 px', 473)]:
        draw.text((x, 112), label, font=font(16), fill='#969AA3')
        insert(canvas, 'mobile', key, (x, 148), (393, 852))
    canvas.save(root/'RainLink-compact-lists.png')

if args.version in ['7.3', '7.4', '7.5']:
    canvas = Image.new('RGB', (1520, 1060), '#0F1011')
    draw = ImageDraw.Draw(canvas)
    draw.text((40, 22), 'RainLink / 桌面紧凑列表', font=font(32), fill='#F4F4F6')
    draw.text((40, 76), '分组 126 → 72 px   ·   节点 68 → 56 px   ·   分组间距 8 px', font=font(19), fill='#969AA3')
    insert(canvas, 'desktop', 'Profiles', (40, 128), (1440, 900))
    canvas.save(root/'RainLink-desktop-compact.png')

if args.version in ['7.4', '7.5']:
    canvas = Image.new('RGB', (2000, 1110), '#0F1011')
    draw = ImageDraw.Draw(canvas)
    draw.text((40, 24), 'RainLink / 节点搜索', font=font(38), fill='#F4F4F6')
    draw.text((40, 86), '搜索全部分组的节点名称、协议或地区，支持清空与无结果状态。', font=font(22), fill='#969AA3')
    insert(canvas, 'desktop', 'Nodes', (40, 154), (1440, 900))
    insert(canvas, 'mobile', 'Nodes', (1540, 154), (393, 852))
    canvas.save(root/'RainLink-node-search.png')

if args.version == '7.5':
    canvas = Image.new('RGB', (2000, 1110), '#0F1011')
    draw = ImageDraw.Draw(canvas)
    draw.text((40, 24), 'RainLink / 设置', font=font(38), fill='#F4F4F6')
    draw.text((40, 86), '通用、外观、网络、核心引擎、更新与关于，两端保持统一。', font=font(22), fill='#969AA3')
    insert(canvas, 'desktop', 'Settings', (40, 154), (1440, 900))
    insert(canvas, 'mobile', 'Settings', (1540, 154), (393, 852))
    canvas.save(root/'RainLink-settings.png')

if args.finalize:
    for platform, size in [('desktop', (1440, 900)), ('mobile', (786, 1704))]:
        files = list((root/platform).glob('*.png'))
        assert len(files) == len(audit[platform]), (platform, len(files), len(audit[platform]))
        for path in files:
            with Image.open(path) as im:
                assert im.size == size, (path.name, im.size)
                im.verify()
    assert audit['version'] == args.version
    assert len(audit['desktop']) == 12 and len(audit['mobile']) == 11
    assert audit['compactCanvas']['removedFullScreens'] == 425
    assert not audit['overflow'] and not audit['untranslatedDisplayCopy']
    for platform in ['desktop', 'mobile']:
        assert not audit['livePrototypeVerification'][platform]['unresolved']
        assert not audit['livePrototypeVerification'][platform]['unscannedScreens']
    if args.version == '7.0':
        assert audit['v7SemanticVerification']['overlayEntryCount'] > 0
        assert audit['v7SemanticVerification']['changeToCount'] > 0
        assert audit['v7SemanticVerification']['countryIconsVerified']
    else:
        assert audit['homeNetworkControls']['screensAdded'] == 0
        assert all(item['fits'] for item in audit['homeNetworkControls']['fit'])
        assert audit['homeNetworkControlsVerification']['independent']
        assert not audit['homeNetworkControlsVerification']['errors']
        assert audit['v71SemanticVerification']['countryIconsVerified']
        assert audit['v71SemanticVerification']['settingsControlsRemoved']
        if args.version in ['7.2', '7.3', '7.4', '7.5']:
            assert not audit['listDensity']['groupNodeNamesVisible']
            assert max(audit['listDensity']['mobileGroupHeights']) <= 109
            assert audit['listDensity']['mobileNodeHeight'] == 72
        if args.version in ['7.3', '7.4', '7.5']:
            assert audit['listDensity']['desktopSubscriptionHeight'] == 72
            assert audit['listDensity']['desktopNodeHeight'] == 56
            assert set(audit['listDensity']['desktopGroupHeights']) == {72}
        if args.version in ['7.4', '7.5']:
            assert audit['nodeSearch']['scope'] == 'all groups'
            assert audit['nodeSearch']['screensAdded'] == 0
            assert audit['nodeSearch']['samples']['http'] == audit['nodeSearch']['samples']['  HTTP  ']
            assert not audit['nodeSearch']['samples']['zzzz']
        if args.version == '7.5':
            assert audit['settingsUI']['screensAdded'] == 0
            assert audit['settingsUI']['desktopCategoryCount'] == 6
            assert audit['settingsUI']['defaultLanguage'] == '简体中文'
            assert not audit['settingsUIVerification']['errors']
            assert audit['settingsUIVerification']['pageCount'] == 3
            assert audit['settingsUIVerification']['productScreens'] == 23
            assert audit['settingsUIVerification']['systemProxyAndTunAbsentFromSettings']
            assert not audit['livePrototypeVerification']['system']['unresolved']
            if 'backNavigationVerification' in audit:
                assert not audit['backNavigationVerification']['errors']
                assert not audit['backNavigationVerification']['residualTextReturns']
                assert audit['backNavigationVerification']['placement'] == 'top-left'
                assert audit['backNavigationVerification']['interactiveArrows'] == 24
    native = root / ('RainLink-v7-zh-CN.fig' if args.version == '7.0' else f'RainLink-v{args.version}-zh-CN.fig')
    with zipfile.ZipFile(native) as archive:
        assert archive.testzip() is None
        assert archive.read('canvas.fig')[:8] == b'fig-kiwi'
    sha = hashlib.sha256(native.read_bytes()).hexdigest()
    audit['nativeBackup'] = {'bytes': native.stat().st_size, 'sha256': sha, 'zipCrc': 'passed', 'canvasHeader': 'fig-kiwi'}
    audit['screenshotVerification'] = {'desktopFiles': 12, 'mobileFiles': 11, 'pngIntegrity': 'passed'}
    (root/'verification.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    for name in ['RainLink.fig', 'RainLink-final.fig', 'RainLink-zh-CN.fig']:
        shutil.copy2(native, base/'exports'/name)
    for name in ['verification.json', 'RainLink-overview.png', 'RainLink-mobile-overview.png', 'RainLink-subscriptions.png']:
        shutil.copy2(root/name, base/'exports'/name)
    if args.version in ['7.2', '7.3', '7.4', '7.5']:
        shutil.copy2(root/'RainLink-compact-lists.png', base/'exports/RainLink-compact-lists.png')
    if args.version in ['7.3', '7.4', '7.5']:
        shutil.copy2(root/'RainLink-desktop-compact.png', base/'exports/RainLink-desktop-compact.png')
    if args.version in ['7.4', '7.5']:
        shutil.copy2(root/'RainLink-node-search.png', base/'exports/RainLink-node-search.png')
    if args.version == '7.5':
        shutil.copy2(root/'RainLink-settings.png', base/'exports/RainLink-settings.png')
    print(json.dumps({'nativeBytes': native.stat().st_size, 'sha256': sha, 'screens': 23}))
else:
    print('Created compact previews from native Figma exports.')
