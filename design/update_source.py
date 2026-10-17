from pathlib import Path
import json

root = Path(__file__).resolve().parent / 'plugin'
path = root / 'code.js'
source = path.read_text(encoding='utf-8')
marker = '// This source is incorporated into code.js by the update script before deployment.'
base = source.split(marker)[0]
old = "n.textAutoResize=w?'HEIGHT':'WIDTH_AND_HEIGHT';if(w)n.resize(w,Math.ceil(size*1.45));return n;}"
new = "if(w){n.resize(w,Math.ceil(size*1.45));n.textAutoResize='HEIGHT';}else n.textAutoResize='WIDTH_AND_HEIGHT';return n;}"
assert old in base or new in base
base = base.replace(old, new)
base=base.replace("function instance(name){const n=masters[name].createInstance();n.name=name;return n;}","function instance(name){const n=masters[name].createInstance();n.name=name;n.setPluginData('rainlink-canonical-name',name);return n;}")
base=base.replace("n.name='Button · '+s;return n;}","n.name='Button · '+s;n.setPluginData('rainlink-canonical-name',n.name);return n;}")
base=base.replace("t.characters=s;if(color)","t.characters=s;t.setPluginData('rainlink-original-text',s);if(color)")
base=base.replace("x.type==='TEXT'&&x.name===name", "x.type==='TEXT'&&(x.getPluginData('rainlink-canonical-name')||x.name)===name")
base=base.replace("x.name==='Icon slot'", "(x.getPluginData('rainlink-canonical-name')||x.name)==='Icon slot'")
base=base.replace("x.name==='Label'", "(x.getPluginData('rainlink-canonical-name')||x.name)==='Label'")
old_end = "figma.notify('RainLink ready · '+registry.counts.desktop+' Desktop · '+registry.counts.mobile+' Mobile · '+registry.counts.components+' components');figma.closePlugin();"
base = base.replace(old_end, "await refineMain();return;")

refine_path=root/'refinement.js'
refine=refine_path.read_text(encoding='utf-8')
old_network="const network=find(screen,'Network');if(network&&screen.name==='Desktop / Settings'){resize(network,876,224);resize(find(screen,'Settings layout'),1120,694);}"
new_network="const network=screen.findOne(n=>n.type==='FRAME'&&n.name==='Network'&&n.parent.name==='General settings');if(network&&screen.name==='Desktop / Settings'){resize(network,876,224);resize(find(screen,'Settings layout'),1120,694);resize(find(screen,'Settings navigation').children.find(n=>n.name==='Network'),196,40);}"
refine=refine.replace(old_network,new_network)
point=" const overflow=[];"
assert point in refine
refine=refine.replace(point," await finalizeDocument();\n"+point,1) if ' await finalizeDocument();' not in refine else refine
refine_path.write_text(refine,encoding='utf-8')
restore_point=' await figma.loadAllPagesAsync();'
if 'await restoreLocaleBaseline();' not in refine:
    refine=refine.replace(restore_point,restore_point+'await restoreLocaleBaseline();',1)
if 'await localizeDocument();' not in refine:
    refine=refine.replace(" await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Dashboard];", " await localizeDocument();\n await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Dashboard];",1)
refine_path.write_text(refine,encoding='utf-8')
final_path=root/'finalization.js'
final=final_path.read_text(encoding='utf-8')
if 'await restoreLocaleBaseline();' not in final:
    final=final.replace(restore_point,restore_point+'await restoreLocaleBaseline();',1)
if 'await localizeDocument();' not in final:
    final=final.replace('const report=await finalizeDocument();','const report=await finalizeDocument();await localizeDocument();',1)
final_path.write_text(final,encoding='utf-8')
copy=json.loads((root/'zh-CN.json').read_text(encoding='utf-8'))
names=json.loads((root/'zh-names.json').read_text(encoding='utf-8'))
locale='\nconst ZH_COPY='+json.dumps(copy,ensure_ascii=False)+';\nconst ZH_NAMES='+json.dumps(names,ensure_ascii=False)+';\n'+(root/'localization.js').read_text(encoding='utf-8')
upgrade=(root/'source-chain-upgrade.js').read_text(encoding='utf-8')
upgrade='\nconst PRE_UPGRADE_TEXT='+json.dumps(json.loads((root/'locale-recovery.json').read_text(encoding='utf-8')),ensure_ascii=False)+';\n'+upgrade
upgrade+='\n'+(root/'source-chain-polish.js').read_text(encoding='utf-8')
upgrade+='\n'+(root/'group-simplification.js').read_text(encoding='utf-8')
upgrade+='\n'+(root/'overview-controls.js').read_text(encoding='utf-8')
upgrade+='\n'+(root/'overview-plan-repair.js').read_text(encoding='utf-8')
upgrade+='\n'+(root/'design-md-polish.js').read_text(encoding='utf-8')
upgrade+='\n'+(root/'subscription-dialogs.js').read_text(encoding='utf-8')
upgrade+='\n'+(root/'egress-status.js').read_text(encoding='utf-8')
upgrade+='\n'+(root/'compact-prototype.js').read_text(encoding='utf-8')
upgrade+='\n'+(root/'home-network-controls.js').read_text(encoding='utf-8')
upgrade+='\n'+(root/'compact-list-density.js').read_text(encoding='utf-8')
upgrade+='\n'+(root/'node-search.js').read_text(encoding='utf-8')
upgrade+='\n'+(root/'settings-complete.js').read_text(encoding='utf-8')
upgrade+='\n'+(root/'navigation-back.js').read_text(encoding='utf-8')
upgrade+='\n'+(root/'known-issues.js').read_text(encoding='utf-8')
upgrade+='\n'+(root/'connection-copy.js').read_text(encoding='utf-8')
# Build and maintenance commands also produce the latest source/chain model.
refine=refine.replace(' await localizeDocument();',' await uInitialize();await simplifyGroupsDocument();\n await localizeDocument();')
final=final.replace('await localizeDocument();','await uInitialize();await simplifyGroupsDocument();await localizeDocument();')
ending="\n(figma.command==='reviewfix'||figma.command==='settingsui'||figma.command==='backnav'?r77ReviewFixMain():figma.command==='nodesearch'?r74SearchMain():figma.command==='density'?r72DensityMain():figma.command==='homeoffline'?r71DesktopOfflineMain():figma.command==='homeprobe'?r71ProbeMain():figma.command==='homecontrols'?r71HomeControlsMain():figma.command==='compact'?r7CompactMain():figma.command==='subscriptions'?r6SubscriptionMain():figma.command==='designmd'?r5PolishMain():figma.command==='touchup'?gTouchupMain():figma.command==='probe'?gPrototypePlanProbe():figma.command==='repair'?gFinalizeStaticMain():figma.command==='groups'||figma.command==='sources'?groupSimplificationMain():figma.command==='localize'?localizeMain():figma.command==='finalize'?finalizeMain():figma.command==='refine'?refineMain():main()).catch(e=>{console.error('RainLink 设计更新失败',e);figma.ui.postMessage({status:'更新失败：'+String(e && e.message || e)+' '+String(e && e.stack || '')});figma.notify('RainLink: '+String(e && (e.message||e.stack) || e),{error:true,timeout:15000});});\n"
path.write_text(base+refine+'\n'+final+locale+'\n'+upgrade+ending,encoding='utf-8')
manifest=json.loads((root/'manifest.json').read_text(encoding='utf-8'))
manifest['menu']=[{'name':'应用 Design.md 规范并简化列表','command':'designmd'},{'name':'修正概览导航与旧模式入口','command':'touchup'},{'name':'概览统一控制连接与代理模式','command':'groups'},{'name':'修复与核验概览原型','command':'repair'},{'name':'检查原型方案能力','command':'probe'},{'name':'设为中文并原位更新','command':'localize'},{'name':'重建完整设计（默认中文）','command':'build'},{'name':'优化与核验','command':'refine'},{'name':'原位完成设计','command':'finalize'}]
manifest['menu'].insert(0, {'name':'添加改为弹窗并显示订阅信息','command':'subscriptions'})
manifest['menu'].insert(0, {'name':'精简画布与组件交互','command':'compact'})
manifest['menu'].insert(0, {'name':'系统代理与 TUN 模式移到首页','command':'homecontrols'})
manifest['menu'].insert(0, {'name':'紧凑桌面与移动端列表','command':'density'})
manifest['menu'].insert(0, {'name':'添加两端节点搜索','command':'nodesearch'})
manifest['menu'].insert(0, {'name':'补全两端设置 UI','command':'settingsui'})
manifest['menu'].insert(0, {'name':'统一返回箭头至左上角','command':'backnav'})
manifest['menu'].insert(0, {'name':'修复 UI 评估中的已知问题','command':'reviewfix'})
manifest['menu'].append({'name':'诊断当前概览缓存','command':'homeprobe'})
manifest['menu'].append({'name':'离线更新桌面概览','command':'homeoffline'})
(root/'manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print('Source synchronized: Simplified Chinese default; in-place localization preserves IDs.')
