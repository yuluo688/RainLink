from pathlib import Path

root = Path(__file__).resolve().parent / 'plugin'
p = root / 'group-simplification.js'
s = p.read_text(encoding='utf-8')
s = s.replace('function gLibrary(){', "function gLibrary(){\n navIcons[2]='folder';for(const d of G_LOOSE)d.source='未分组';")
s = s.replace("function gGroup(name,count,type,node,mobile=false,detail='Nodes',connected='Dashboard',meta=null){", "function gGroup(name,count,type,node,mobile=false,detail='Nodes',connected='Dashboard',meta=null){if(mobile&&type==='未分组')meta=count+' 个节点 · 手动添加';")
old = "between(add(row('Group toolbar',353,40),uSmall((state==='subscription'?'4':'3')+' 个分组 · '+(state==='subscription'?18:state==='manual'?15:14)+' 个节点','Secondary'),uButton('添加',prefix+'Import profile','Secondary','plus')))"
new = "add(row('Group toolbar',353,28),uSmall((['subscription','custom'].includes(state)?'4':'3')+' 个分组 · '+(state==='subscription'?18:state==='manual'?15:14)+' 个节点','Secondary'))"
s = s.replace(old, new)
s = s.replace("uButton('查看','D/Connections','Ghost')", "uLink(btn('查看','Ghost','S'),'D/Connections')")
s = s.replace("for(const state of ['default','reordered','empty','tested'])", "for(const state of ['default','reordered','empty','tested','reverse-tested'])")
s = s.replace("tested:'Chain tested'}[state],swap=state==='reordered',empty=state==='empty',tested=state==='tested'", "tested:'Chain tested','reverse-tested':'Chain reverse tested'}[state],swap=['reordered','reverse-tested'].includes(state),empty=state==='empty',tested=['tested','reverse-tested'].includes(state)")
s = s.replace("tested?'测试通过 · 整链 46 ms · 出口：日本东京'", "tested?(swap?'测试通过 · 整链 39 ms · 出口：办公 HTTP':'测试通过 · 整链 46 ms · 出口：日本东京')")
s = s.replace("tested?'端到端握手成功 · 46 ms'", "tested?(swap?'端到端握手成功 · 39 ms':'端到端握手成功 · 46 ms')")
s = s.replace("prefix+(tested?'Chain connected':'Chain tested')", "prefix+(tested?(swap?'Chain reverse connected':'Chain connected'):(swap?'Chain reverse tested':'Chain tested'))")
s = s.replace("gHome('Chain connected','主订阅',G_MAIN[0],true,true);", "gHome('Chain connected','主订阅',G_MAIN[0],true,true);gHome('Chain reverse connected','主订阅',G_LOOSE[0],true,'reverse');")
s = s.replace("chain?'办公 HTTP → 东京 · 樱花':data.name", "chain?(chain==='reverse'?'东京 · 樱花 → 办公 HTTP':'办公 HTTP → 东京 · 樱花'):data.name")
s = s.replace("chain?'46':data.ping", "chain==='reverse'?'39':chain?'46':data.ping")
s = s.replace("connectedKey=chain?'Chain connected'", "connectedKey=chain?(chain==='reverse'?'Chain reverse connected':'Chain connected')")
s = s.replace("key==='Chain connected'?'开发代理链':data.name", "['Chain connected','Chain reverse connected'].includes(key)?'开发代理链':data.name")
s = s.replace("key==='Chain connected'?'46':data.ping", "key==='Chain reverse connected'?'39':key==='Chain connected'?'46':data.ping")
s = s.replace(" await gPatchExisting();", " await gPatchExisting();for(const r of [registry.desktop,registry.mobile])if(r['Dashboard light']||r['Home light'])applyLight(r['Dashboard light']||r['Home light']);")
p.write_text(s,encoding='utf-8')

p = root / 'source-chain-polish.js'
s = p.read_text(encoding='utf-8')
s = s.replace("label.includes('保存')?'check':'speed'", "label.includes('连接')?'power':label.includes('添加')?'plus':label.includes('导入')?'download':label.includes('新建')?'folder':label.includes('保存')?'check':'speed'")
p.write_text(s,encoding='utf-8')
print('Group visual refinements applied.')
