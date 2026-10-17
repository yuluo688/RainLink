"""Build review sheets from this plan's live Figma exports."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
FONT = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 20)
GROUPS = [
    ('desktop-main-a', 'desktop', [('dashboard', '概览'), ('nodes', '节点'), ('groups', '分组'), ('rules', '规则')], (864, 540), 2),
    ('desktop-main-b', 'desktop', [('connections', '实时连接'), ('traffic', '流量'), ('logs', '日志'), ('settings', '设置')], (864, 540), 2),
    ('desktop-dialogs', 'desktop', [('import', '添加订阅 / 节点'), ('chain', '代理链'), ('move-node', '移动节点'), ('subscription', '订阅信息')], (864, 540), 2),
    ('mobile-main-a', 'mobile', [('home', '首页'), ('nodes', '节点'), ('groups', '分组'), ('traffic', '流量')], (393, 852), 4),
    ('mobile-main-b', 'mobile', [('settings', '设置'), ('quick-select', '快速选择'), ('dns', 'DNS'), ('chain', '代理链')], (393, 852), 4),
    ('mobile-dialogs', 'mobile', [('import', '添加'), ('move-node', '移动节点'), ('subscription', '订阅信息')], (393, 852), 3),
]

for name, platform, pages, size, columns in GROUPS:
    width, height = size
    rows = (len(pages) + columns - 1) // columns
    canvas = Image.new('RGB', (24 + columns * (width + 16), 24 + rows * (height + 52)), '#232428')
    draw = ImageDraw.Draw(canvas)
    for i, (key, title) in enumerate(pages):
        x = 16 + i % columns * (width + 16)
        y = 12 + i // columns * (height + 52)
        draw.text((x, y), title, font=FONT, fill='#f4f4f6')
        with Image.open(ROOT / 'ui' / platform / (key + '.png')) as source:
            rgb = Image.new('RGB', source.size, '#0f1011')
            rgb.paste(source.convert('RGB'), (0, 0))
            if source.mode == 'RGBA':
                rgb.paste(source, (0, 0), source.getchannel('A'))
            canvas.paste(rgb.resize(size, getattr(Image, 'Resampling', Image).LANCZOS), (x, y + 36))
    canvas.save(ROOT / 'ui' / (name + '.png'))

print('Created six review sheets from 23 live Figma exports.')
