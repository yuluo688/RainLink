from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json

BASE = Path(__file__).resolve().parent
ROOT = BASE / 'exports' / 'design-md-v5'
BG, TEXT, MUTED, MINT = '#0F1011', '#F4F4F6', '#969AA3', '#8ADCBF'
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
    if ' · ' in key:
        return ' · '.join(label(part) for part in key.split(' · '))
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
        caption_text=label(key)
        caption_font=font(19)
        measure=lambda value: draw.textbbox((0,0),value,font=caption_font)[2] if hasattr(draw,'textbbox') else draw.textsize(value,font=caption_font)[0]
        while measure(caption_text)>width-20:
            caption_text=caption_text[:-2]+'…'
        draw.text((x, y), caption_text, font=font(19), fill=MUTED)
        im = Image.open(ROOT/platform/f'{slug(key)}.png').convert('RGB').resize((width, height), RESAMPLE)
        canvas.paste(im, (x, y+caption))
    canvas.save(ROOT/f'qa-{platform}-{index:02d}.png')

for platform, per in [('desktop', 4), ('mobile', 5)]:
    keys = list(audit[platform])
    for i in range(0, len(keys), per):
        sheet(platform, keys[i:i+per], i//per+1)

canvas = Image.new('RGB', (2000, 900), BG)
draw = ImageDraw.Draw(canvas)
draw.text((48, 36), 'RainLink', font=font(52, True), fill=TEXT)
draw.text((50, 112), '节点与分组，回归列表本身。', font=font(24), fill=MUTED)
draw.text((1330, 57), 'Linear / Vercel / Raycast', font=font(22), fill=MINT)
draw.text((1330, 93), 'awesome-design-md 规范适配', font=font(18), fill=MUTED)
for key, caption, x in [('nodes','节点 · 协议、延迟与操作对齐',48), ('profiles','分组 · 选中目标与查看节点',1024)]:
    draw.text((x, 181), caption, font=font(20), fill=MUTED)
    im = Image.open(ROOT/'desktop'/f'{key}.png').convert('RGB').resize((928,580), RESAMPLE)
    canvas.paste(im, (x,228))
draw.text((48, 842), '中文默认   /   订阅自动归组   /   概览控制 VPN 与代理模式   /   可视化代理链', font=font(20), fill=MUTED)
canvas.save(ROOT/'RainLink-overview.png')
canvas = Image.new('RGB',(1748,1140),BG)
draw = ImageDraw.Draw(canvas)
draw.text((40,30),'RainLink / 移动端',font=font(42,True),fill=TEXT)
for key,caption,x in [('disconnected','概览',40),('profiles','分组',466),('nodes','节点',892),('chain-editor','可视化编排',1318)]:
    draw.text((x,119),caption,font=font(20),fill=MUTED)
    im=Image.open(ROOT/'mobile'/f'{key}.png').convert('RGB').resize((393,852),RESAMPLE)
    canvas.paste(im,(x,165))
draw.text((40,1062),'相同设计语言，适配触控与移动列表。',font=font(23),fill=MUTED)
canvas.save(ROOT/'RainLink-mobile-overview.png')
print('Generated Design.md previews and review sheets.')
