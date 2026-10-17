from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json

BASE = Path(__file__).resolve().parent
ROOT = BASE / 'exports' / 'groups-v3'
BG, TEXT, MUTED, MINT = '#080d12', '#eef5f4', '#8196a3', '#86e5c3'
RESAMPLE = getattr(Image, 'Resampling', Image).LANCZOS
FONT = 'C:/Windows/Fonts/msyh.ttc'
BOLD = 'C:/Windows/Fonts/msyhbd.ttc'
audit = json.loads((ROOT / 'verification.json').read_text(encoding='utf-8'))
copy = json.loads((BASE / 'plugin/zh-CN.json').read_text(encoding='utf-8'))
names = json.loads((BASE / 'plugin/zh-names.json').read_text(encoding='utf-8'))

def font(size, bold=False):
    return ImageFont.truetype(BOLD if bold else FONT, size)

def slug(key):
    return key.lower().replace(' ', '-')

def label(key):
    return copy.get(key, names.get(key, key))

def sheet(platform, keys, index):
    columns, width = (2, 720) if platform == 'desktop' else (5, 314)
    height = round(width * (900/1440 if platform == 'desktop' else 852/393))
    pad, caption, top = 28, 44, 82
    rows = (len(keys) + columns - 1) // columns
    canvas = Image.new('RGB', (pad + columns*(width+pad), top+rows*(height+caption+pad)), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((pad, 20), f'RainLink / {"桌面端" if platform=="desktop" else "移动端"}  {index:02d}', font=font(27, True), fill=TEXT)
    for i, key in enumerate(keys):
        x, y = pad+(i%columns)*(width+pad), top+(i//columns)*(height+caption+pad)
        draw.text((x, y), label(key), font=font(19), fill=MUTED)
        im = Image.open(ROOT/platform/f'{slug(key)}.png').convert('RGB').resize((width, height), RESAMPLE)
        canvas.paste(im, (x, y+caption))
    canvas.save(ROOT/f'qa-{platform}-{index:02d}.png')

for platform, per in [('desktop', 4), ('mobile', 5)]:
    keys = list(audit[platform])
    for i in range(0, len(keys), per):
        sheet(platform, keys[i:i+per], i//per+1)

canvas = Image.new('RGB', (1900, 1050), BG)
draw = ImageDraw.Draw(canvas)
draw.text((64, 44), 'RainLink', font=font(58, True), fill=TEXT)
draw.text((66, 120), '添加即归组，选择即可连接。', font=font(24), fill=MUTED)
draw.text((1428, 67), '桌面端 + 移动端', font=font(18, True), fill=MINT)
draw.text((1428, 100), '中文原生 Figma 设计', font=font(16), fill=MUTED)
im = Image.open(ROOT/'desktop/profiles.png').convert('RGB').resize((1152, 720), RESAMPLE)
canvas.paste(im, (64, 207))
for name, title, x in [('profiles', '分组', 1260), ('move-group', '移动节点', 1578)]:
    im = Image.open(ROOT/f'mobile/{name}.png').convert('RGB').resize((282, 612), RESAMPLE)
    canvas.paste(im, (x, 261))
    draw.text((x, 222), f'移动端 / {title}', font=font(18), fill=MUTED)
draw.text((64, 973), '订阅自动成组   /   单个节点进入未分组   /   仅未分组可移动   /   默认简体中文', font=font(20), fill=MUTED)
canvas.save(ROOT/'RainLink-overview.png')
print(f'Created overview and review sheets: {len(audit["desktop"])} desktop / {len(audit["mobile"])} mobile.')
