from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parent
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 18)
groups = [
    ('desktop-main-a', 'desktop', [('dashboard', '概览'), ('nodes', '节点'), ('profiles', '分组'), ('rules', '规则')], (720, 450), 2),
    ('desktop-main-b', 'desktop', [('connections', '连接'), ('traffic', '流量'), ('logs', '日志'), ('settings', '设置')], (720, 450), 2),
    ('mobile-main-a', 'mobile', [('home', '首页'), ('nodes', '节点'), ('profiles', '分组'), ('traffic', '流量')], (393, 852), 4),
    ('mobile-main-b', 'mobile', [('settings', '设置'), ('quick-switch', '快速选择'), ('dns', 'DNS'), ('chain-editor', '代理链')], (393, 852), 4),
    ('desktop-dialogs', 'desktop', [('import-profile', '添加'), ('chain-editor', '代理链'), ('move-group', '移动分组'), ('subscription-info-·-主订阅', '订阅信息')], (720, 450), 2),
    ('mobile-dialogs', 'mobile', [('import-profile', '添加'), ('move-group', '移动分组'), ('subscription-info-·-主订阅', '订阅信息')], (393, 852), 3),
]
for name, platform, pages, (width, height), cols in groups:
    rows = (len(pages) + cols - 1) // cols
    canvas = Image.new('RGB', (24 + cols * (width + 16), 24 + rows * (height + 46)), '#232428')
    draw = ImageDraw.Draw(canvas)
    for i, (key, label) in enumerate(pages):
        x, y = 16 + (i % cols) * (width + 16), 12 + (i // cols) * (height + 46)
        draw.text((x, y), label, font=font, fill='#F4F4F6')
        with Image.open(root / 'assets/live' / platform / (key + '.png')) as im:
            rgb = Image.new('RGB', im.size, '#0F1011')
            if im.mode == 'RGBA':
                rgb.paste(im, mask=im.getchannel('A'))
            else:
                rgb.paste(im.convert('RGB'))
            canvas.paste(rgb.resize((width, height), getattr(Image, 'Resampling', Image).LANCZOS), (x, y + 30))
    canvas.save(root / 'assets' / (name + '.png'))
print('Created 6 contact sheets from 23 live Figma exports.')
