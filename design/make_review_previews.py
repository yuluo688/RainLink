"""Make visual QA sheets from the current Figma review-repair exports."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parent / 'exports/compact-v7.5/review-fixes'
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 19)
groups = [
    ('desktop-main-a', 'desktop', ['dashboard', 'nodes', 'profiles', 'rules'], (720, 450), 2),
    ('desktop-main-b', 'desktop', ['connections', 'traffic', 'logs', 'settings'], (720, 450), 2),
    ('mobile-main-a', 'mobile', ['home', 'nodes', 'profiles', 'traffic'], (393, 852), 4),
    ('mobile-main-b', 'mobile', ['settings', 'quick-switch', 'dns', 'chain-editor'], (393, 852), 4),
    ('desktop-dialogs', 'desktop', ['import-profile', 'chain-editor', 'move-group', 'subscription-info-·-主订阅'], (720, 450), 2),
    ('mobile-dialogs', 'mobile', ['import-profile', 'move-group', 'subscription-info-·-主订阅'], (393, 852), 3),
    ('protocols', 'states', ['添加-Shadowsocks', '添加-VLESS', '添加-VMess', '添加-Trojan', '添加-Hysteria', '添加-TUIC', '添加-SOCKS5', '添加-HTTP'], (393, 624), 4),
    ('flows', 'states', ['订阅详情', '订阅编辑', '订阅删除', '订阅获取失败', '代理链添加', '代理链测试失败', '代理链保存', '流量图选点'], (393, 772), 4),
]
out = root / 'sheets'
out.mkdir(exist_ok=True)
for name, platform, keys, (width, height), cols in groups:
    rows = (len(keys) + cols - 1) // cols
    canvas = Image.new('RGB', (24 + cols * (width + 16), 24 + rows * (height + 46)), '#232428')
    draw = ImageDraw.Draw(canvas)
    for i, key in enumerate(keys):
        x, y = 16 + i % cols * (width + 16), 12 + i // cols * (height + 46)
        draw.text((x, y), key, font=font, fill='#f4f4f6')
        source = root / platform / (key + '.png')
        if not source.exists():
            source = root.parent / platform / (key + '.png')
        with Image.open(source) as im:
            image = Image.new('RGB', im.size, '#0f1011')
            image.paste(im.convert('RGB'), mask=im.getchannel('A') if im.mode == 'RGBA' else None)
            image.thumbnail((width, height), getattr(Image, 'Resampling', Image).LANCZOS)
            canvas.paste(image, (x, y + 30))
    canvas.save(out / (name + '.png'))
print('Created 8 review sheets from current Figma exports.')
