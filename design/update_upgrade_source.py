from pathlib import Path
import json

root=Path(__file__).resolve().parent/'plugin'
p=root/'source-chain-upgrade.js'
s=p.read_text(encoding='utf-8')
s=s.replace('c.resize(664,112)','c.resize(664,100)').replace('c.resize(w,112)','c.resize(w,100)')
s=s.replace('c.resize(w,mobile?164:128)','c.resize(w,mobile?164:160)').replace('c.resize(w,mobile?158:140)','c.resize(w,160)')
s=s.replace("between(add(row('Source actions',632,null),uSmall('订阅更新只影响此来源的节点。'),btn('查看节点','Ghost','S','arrow')))", 'null')
s=s.replace("const protocol=uField('协议','HTTP',676);uLink(protocol,'D/Manual node');", '')
s=s.replace("borderCard('Unified node inventory',1120,null,20,8)","borderCard('Unified node inventory',1120,null,20,0)")
s=s.replace('i===1||i===2?172:132','i===1||i===2?168:128')
p.write_text(s,encoding='utf-8')
p=root/'zh-CN.json'
copy=json.loads(p.read_text(encoding='utf-8'))
copy.update({'Profiles':'节点来源','Import profile':'添加来源','Profile editor':'高级内核配置','Apply profile':'保存内核设置','Your configuration is ready':'选择连接目标即可开始','Your configurations, together.':'订阅与手动节点集中管理。'})
copy.update({'Chains':'代理链','Manual node':'手动添加节点','Manual error':'手动节点 · 输入校验','Manual success':'手动节点 · 已保存','Subscription import':'导入订阅','Source success':'订阅导入成功','Chain editor':'代理链编排','Chain empty':'代理链 · 待添加出口','Chain picker':'选择代理链跳点','Chain reordered':'代理链 · 调整顺序','Chain tested':'代理链 · 测试通过','Chain unavailable':'代理链 · 需要修复','Chain connected':'代理链 · 已连接'})
p.write_text(json.dumps(copy,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Upgrade source and Chinese labels updated.')
