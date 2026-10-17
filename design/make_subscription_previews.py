from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json

BASE = Path(__file__).resolve().parent
ROOT = BASE / 'exports/subscription-v6'
BG, TEXT, MUTED, MINT = '#0F1011', '#F4F4F6', '#969AA3', '#8ADCBF'
FONT, BOLD = 'C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/msyhbd.ttc'
RESAMPLE = Image.Resampling.LANCZOS
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

def insert(canvas, platform, key, xy, size):
    with Image.open(ROOT/platform/f'{slug(key)}.png') as im:
        canvas.paste(im.convert('RGB').resize(size, RESAMPLE), xy)

# Native Figma exports are composed here only for presentation / visual QA.
canvas=Image.new('RGB',(2000,1140),BG)
draw=ImageDraw.Draw(canvas)
draw.text((48,30),'RainLink',font=font(48,True),fill=TEXT)
draw.text((48,100),'当前出口一眼可见，添加只需一个弹窗。',font=font(24),fill=MUTED)
draw.text((48,164),'概览 · 公网 IP、国家与国旗',font=font(20),fill=MINT)
insert(canvas,'desktop','Dashboard',(48,204),(1440,900))
draw.text((1540,164),'移动端 · 紧凑概览',font=font(20),fill=MINT)
insert(canvas,'mobile','Home',(1540,204),(393,852))
canvas.save(ROOT/'RainLink-overview.png')

canvas=Image.new('RGB',(1748,1140),BG)
draw=ImageDraw.Draw(canvas)
draw.text((40,30),'RainLink / 移动端',font=font(42,True),fill=TEXT)
for key,caption,x in [('Home','IP 与国旗',40),('Profiles','订阅用量与有效期',466),('添加订阅预览','添加订阅弹窗',892),('添加单个节点预览','单个节点弹窗',1318)]:
    draw.text((x,119),caption,font=font(20),fill=MUTED)
    insert(canvas,'mobile',key,(x,165),(393,852))
draw.text((40,1062),'默认中文 / 订阅自动命名成组 / 单节点进入未分组 / 真实出口检测行为',font=font(20),fill=MUTED)
canvas.save(ROOT/'RainLink-mobile-overview.png')

canvas=Image.new('RGB',(2000,1520),BG)
draw=ImageDraw.Draw(canvas)
draw.text((48,28),'RainLink / 添加与订阅',font=font(38,True),fill=TEXT)
for key,caption,x,y in [('Profiles','分组 · 流量与到期时间',48,114),('添加订阅预览','订阅 · 无需填写分组名',1024,114),('添加单个节点预览','单节点 · 进入未分组',48,814),('订阅详情预览','订阅详情 · 套餐与更新时间',1024,814)]:
    draw.text((x,y),caption,font=font(20),fill=MUTED)
    insert(canvas,'desktop',key,(x,y+42),(928,580))
canvas.save(ROOT/'RainLink-subscriptions.png')

for platform,per,columns,width in [('desktop',4,2,720),('mobile',5,5,314)]:
    height=round(width*(900/1440 if platform=='desktop' else 852/393))
    keys=list(audit[platform])
    for page,start in enumerate(range(0,len(keys),per),1):
        batch=keys[start:start+per]
        rows=(len(batch)+columns-1)//columns
        sheet=Image.new('RGB',(28+columns*(width+28),82+rows*(height+72)),BG)
        d=ImageDraw.Draw(sheet)
        d.text((28,20),f'RainLink / {"桌面端" if platform=="desktop" else "移动端"} {page:02d}',font=font(27,True),fill=TEXT)
        for i,key in enumerate(batch):
            x,y=28+(i%columns)*(width+28),82+(i//columns)*(height+72)
            caption=label(key)
            while d.textbbox((0,0),caption,font=font(17))[2]>width-16:
                caption=caption[:-2]+'…'
            d.text((x,y),caption,font=font(17),fill=MUTED)
            insert(sheet,platform,key,(x,y+44),(width,height))
        sheet.save(ROOT/f'qa-{platform}-{page:02d}.png')
print('Generated V6 previews and contact sheets from native Figma exports.')
