from pathlib import Path
import json
root=Path(__file__).resolve().parent
path=root/'plugin/group-simplification.js'
source=path.read_text(encoding='utf-8')
source=source.replace('const report=await localizeDocument();await figma.setCurrentPageAsync', 'const report=gV4Report(await localizeDocument());await figma.setCurrentPageAsync')
source=source.replace('RainLink / 简化分组</h2>', 'RainLink / 概览控制</h2>')
source=source.replace('正在更新自动归组、连接、移动及可视化代理链…','正在更新选择、VPN 开关及代理模式…')
source=source.replace('重绘分组与连接页面…','重绘概览、分组与节点选择…')
source=source.replace('分组已简化 · ','概览控制已更新 · ')
path.write_text(source,encoding='utf-8')
labels={
 'Mode global':'概览 · 全局模式','Mode direct':'概览 · 直连模式','Pending selection':'概览 · 新选择待应用',
 'Overview':'概览','Proxy mode':'代理模式','Proxy mode heading':'代理模式标题','Proxy mode options':'代理模式选项',
 'Proxy mode desktop':'桌面端代理模式','Overview target':'概览连接目标','VPN control':'VPN 连接控制',
 'VPN power button':'VPN 开关','VPN mode caption':'VPN 模式说明','Selection summary':'当前选择',
 'Selection heading':'选择状态标题','Pending target summary':'待应用的选择','Group copy':'分组文案',
 'Group selection footer':'分组选择底栏','Routing overview shortcut':'代理模式概览入口','App status':'应用状态',
 'Quick switch':'选择分组','桌面端 / 概览开启 VPN':'桌面端 / 概览开启 VPN','移动端 / 概览开启 VPN':'移动端 / 概览开启 VPN',
}
for name in ['zh-CN.json','zh-names.json']:
 p=root/'plugin'/name
 data=json.loads(p.read_text(encoding='utf-8'));data.update(labels)
 p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Prepared overview controls and Chinese labels.')
