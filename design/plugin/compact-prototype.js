// Compact the actual document: interactions live in component variants, not copies
// of the entire application. Existing principal screen IDs are retained.
const R7_MAIN_D=['Dashboard','Nodes','Profiles','Rules','Connections','Traffic','Logs','Settings'];
const R7_MAIN_M=['Home','Nodes','Profiles','Traffic','Settings','Quick switch','DNS','Chain editor'];
const r7Sets=[],r7Changes=[];
const r7Click=(id,navigation='CHANGE_TO')=>[{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:id,navigation,transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false}]}];
const r7Timer=id=>[{trigger:{type:'AFTER_TIMEOUT',timeout:1.2},actions:[{type:'NODE',destinationId:id,navigation:'CHANGE_TO',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18}}]}];
async function r7Clear(root){for(const n of [root,...root.findAll(n=>'reactions'in n)])if('setReactionsAsync'in n&&n.reactions.length)await n.setReactionsAsync([]);}
function r7Body(name,w){return component(name,c=>{c.layoutMode='VERTICAL';c.resize(w,1);c.primaryAxisSizingMode='AUTO';c.counterAxisSizingMode='FIXED';c.itemSpacing=12;c.clipsContent=false;c.setPluginData('rainlink-compact-component','7.0');});}
function r7VariantSet(name,children,columns=3){const set=figma.combineAsVariants(children,dsPage);r6Name(set,name);set.layoutMode='NONE';const maxW=Math.max(...children.map(c=>c.width)),maxH=Math.max(...children.map(c=>c.height));children.forEach((c,i)=>{c.x=24+(i%columns)*(maxW+32);c.y=24+Math.floor(i/columns)*(maxH+40);});set.resize(48+Math.min(columns,children.length)*(maxW+32)-32,48+Math.ceil(children.length/columns)*(maxH+40)-40);r7Sets.push(set);return set;}
function r7Instance(c,name){return r6Name(c.createInstance(),name);}
function r7CloneBody(screen,c){const content=uFind(screen,'Content');for(const n of content.children)if(r5Name(n)!=='Page header'){const clone=n.clone();add(c,clone);if(clone.type==='INSTANCE'&&['代理链交互编排','连接开关与出口'].includes(r5Name(clone))){const detached=clone.detachInstance();for(const child of [...detached.children])add(c,child);detached.remove();}}}
async function r7Home(mobile){
 const reg=mobile?registry.mobile:registry.desktop,base=reg[mobile?'Home':'Dashboard'],w=mobile?353:1120,variants={};
 for(const state of ['关闭','连接中','开启','断开中']){
  const off=state==='关闭'||state==='连接中',src=off?reg.Disconnected:(reg['已连接 · 主订阅 · 东京 · 樱花']||base),c=r7Body('连接='+state,w);const saved=!off&&base.getPluginData('rainlink-r7-home-source');if(saved){const original=await figma.getNodeByIdAsync(saved);for(const n of original.children)add(c,n.clone());}else r7CloneBody(src,c);await r7Clear(c);
  const network=uFind(c,'概览出口与模式');if(network){const parent=network.parent,i=parent.children.indexOf(network);network.remove();parent.insertChild(i,r6NetworkInstance(mobile,state==='开启','规则',state.endsWith('中')?'检测中':'已获取'));}
  if(state.endsWith('中'))for(const t of c.findAll(n=>n.type==='TEXT')){if(['VPN 已开启','VPN 已关闭'].includes(t.characters))r6Copy(t,state==='连接中'?'正在连接…':'正在断开…');if(['开启 VPN','关闭 VPN'].includes(t.characters))r6Copy(t,'处理中…');}
  variants[state]=c;
 }
 r7VariantSet('交互 / '+(mobile?'移动端':'桌面端')+' / 连接开关',Object.values(variants),2);
 for(const [state,c]of Object.entries(variants)){
  const power=c.findOne(n=>n.getPluginData('rainlink-control-kind')==='vpn-power');
  if(power&&!state.endsWith('中'))await power.setReactionsAsync(r7Click(variants[state==='开启'?'断开中':'连接中'].id));
  if(state.endsWith('中'))await c.setReactionsAsync(r7Timer(variants[state==='连接中'?'开启':'关闭'].id));
 }
 const content=uFind(base,'Content');if(!base.getPluginData('rainlink-r7-home-source')){const source=r7Body('原始概览内容 / '+(mobile?'移动端':'桌面端'),w);r7CloneBody(reg['已连接 · 主订阅 · 东京 · 樱花']||base,source);base.setPluginData('rainlink-r7-home-source',source.id);source.setPluginData('rainlink-compact-component','source');source.visible=false;}for(const n of [...content.children])if(r5Name(n)!=='Page header')n.remove();add(content,r7Instance(variants['开启'],'连接开关与出口'));r7Changes.push(base.id);
 return {set:variants['开启'].parent.id,states:Object.fromEntries(Object.entries(variants).map(([k,v])=>[k,v.id]))};
}
async function r7Groups(mobile){
 const reg=mobile?registry.mobile:registry.desktop,w=mobile?353:1120,variants={},names=['主订阅','备用订阅','未分组','旅行订阅'];
 for(const selected of names){
  const c=r7Body('选中='+selected,w);
  for(const [name,data,count,type]of [['主订阅',G_MAIN[0],8,'订阅'],['备用订阅',G_BACKUP[0],3,'订阅'],['未分组',G_LOOSE[0],3,'未分组'],['旅行订阅',G_MAIN[2],4,'订阅']]){
   const n=instance('Group / '+(mobile?'Mobile':'Desktop'));r6Name(n,'Group · '+name);for(const [field,value]of [['组名称',name],['组信息',count+' 个节点 · '+(type==='订阅'?'订阅自动更新':'手动添加')],['组当前节点',data.name],['组延迟',data.ping+' ms']])r6Copy(uFind(n,field),value);const check=uFind(n,'分组选中');if(check){check.setBoundVariable('visible',null);check.visible=name===selected;}r6GroupInfo(n,mobile,R6_INFO[name]);
   fill(n,name===selected?'PrimarySurface':'Surface');stroke(n,name===selected?'Primary':'Stroke');add(c,n);
  }
  variants[selected]=c;await r7Clear(c);
 }
 r7VariantSet('交互 / '+(mobile?'移动端':'桌面端')+' / 分组选择',Object.values(variants),2);
 for(const c of Object.values(variants))for(const card of c.children){const group=r5Name(card).slice(8);await card.setReactionsAsync(group===c.name.slice(3)?[]:r7Click(variants[group].id));}
 const build=b=>{add(b,r7Instance(variants['主订阅'],'分组选择列表'),r6Text('订阅自动成组 · 单个节点默认进入未分组',12,'Muted','Regular',w));};
 if(mobile)gM('Profiles','分组','点击选中，在概览开启 VPN',build,'Profiles','M/Import profile',true);else gD('Profiles','分组','选择分组与节点，在概览开启 VPN。',build,'Profiles',uButton('添加','D/Import profile','Primary','plus'));
 if(mobile&&reg['Quick switch']){const b=uFind(reg['Quick switch'],'Content');for(const n of [...b.children])n.remove();add(b,r7Instance(variants['主订阅'],'分组选择列表'),r6Text('选中即可，返回概览后开启 VPN。',12,'Muted','Regular',353),uButton('返回概览','M/Home','Secondary','grid',353));}
 r7Changes.push(reg.Profiles.id);return variants['主订阅'].parent.id;
}
async function r7Nodes(mobile){
 const reg=mobile?registry.mobile:registry.desktop,w=mobile?353:1120,groups={'主订阅':G_MAIN,'备用订阅':G_BACKUP,'未分组':G_LOOSE,'旅行订阅':G_MAIN.slice(0,4)},variants={};
 for(const [group,data]of Object.entries(groups))for(let selected=0;selected<data.length;selected++){
  const c=r7Body('分组='+group+', 选中='+selected,w),tabs=row('节点分组选项',w,40,6);
  for(const name of Object.keys(groups)){const t=center(rad(row('选择节点分组 · '+name,mobile?83:140,36,0,0,name===group?'PrimarySurface':'Raised'),8));add(t,r6Text(name,13,name===group?'Primary':'Secondary'));add(tabs,t);}add(c,tabs);
  if(!mobile)add(c,r5TableHeader());
  for(let i=0;i<data.length;i++){const n=gNode(data[i],mobile,i===selected,group==='未分组');r6Name(n,'选择节点 · '+i);add(c,n);}
  c.itemSpacing=mobile?12:0;await r7Clear(c);variants[group+'/'+selected]=c;
 }
 r7VariantSet('交互 / '+(mobile?'移动端':'桌面端')+' / 节点选择',Object.values(variants),mobile?4:3);
 for(const [key,c]of Object.entries(variants)){
  const [group,selected]=key.split('/');
  for(const name of Object.keys(groups))await uFind(c,'选择节点分组 · '+name).setReactionsAsync(name===group?[]:r7Click(variants[name+'/0'].id));
  for(const n of c.children.filter(n=>r5Name(n).startsWith('选择节点 · '))){const index=r5Name(n).slice(7);await n.setReactionsAsync(index===selected?[]:r7Click(variants[group+'/'+index].id));}
 }
 const speeds={};for(const state of ['测速','测量中…','测速完成']){const c=r7Body('状态='+state,100);add(c,r6Button(state,'Secondary','speed',100));speeds[state]=c;}r7VariantSet('交互 / '+(mobile?'移动端':'桌面端')+' / 测速',Object.values(speeds),3);await speeds['测速'].children[0].setReactionsAsync(r7Click(speeds['测量中…'].id));await speeds['测量中…'].setReactionsAsync(r7Timer(speeds['测速完成'].id));await speeds['测速完成'].children[0].setReactionsAsync(r7Click(speeds['测量中…'].id));
 const build=b=>{const bar=between(row('节点操作',w,44,8)),actions=row('节点操作按钮',null,44,8);add(actions,uButton('代理链',(mobile?'M/':'D/')+'Chain editor','Secondary','link'),r7Instance(speeds['测速'],'测速操作'));add(bar,uButton('全部分组',(mobile?'M/':'D/')+'Profiles','Ghost','folder'),actions);add(b,bar,r7Instance(variants['主订阅/0'],'节点分组与选择'));};
 if(mobile)gM('Nodes','节点','选择节点后，在概览开启 VPN',build,'Nodes','M/Profiles');else gD('Nodes','节点','按分组浏览，点击仅更换选择。',build,'Nodes',uButton('添加','D/Import profile','Primary','plus'));
 r7Changes.push(reg.Nodes.id);return variants['主订阅/0'].parent.id;
}
async function r7Dialogs(mobile){
 const reg=mobile?registry.mobile:registry.desktop,platform=mobile?'移动端':'桌面端',w=mobile?393:520,variants={};
 for(const [key,mode,state]of [['订阅','subscription','empty'],['订阅已填','subscription','ready'],['导入中','subscription','loading'],['订阅错误','subscription','error'],['单个节点','manual','ready'],...(mobile?[['扫码','qr','ready']]:[])]){
  const source=masters['弹窗 / '+platform+' / '+mode+' / '+state],c=source.clone();dsPage.appendChild(c);r6Name(c,'状态='+key);c.setPluginData('rainlink-compact-component','7.0');await r7Clear(c);variants[key]=c;
 }
 for(const [key,title,copy]of [['订阅成功','订阅已导入','已自动创建「旅行订阅」，包含 4 个节点。名称随订阅更新。'],['节点成功','节点已添加','「备用 HTTP」已放入未分组，可在节点列表移动到其他组。']]){
  const c=r7Body('状态='+key,w);fill(c,'Surface');stroke(c);rad(c,24);c.paddingTop=c.paddingBottom=24;c.paddingLeft=c.paddingRight=24;c.itemSpacing=16;add(c,r6Badge('完成','Success'),r6Text(title,24,'Text','Medium'),r6Text(copy,14,'Secondary','Regular',w-48),r6Button('完成','Primary',null,w-48));variants[key]=c;
 }
 r7VariantSet('交互 / '+platform+' / 添加弹窗',Object.values(variants),3);
 for(const [key,c]of Object.entries(variants))for(const n of c.findAll(n=>'setReactionsAsync'in n)){
  const label=r5Name(n);let next;
  if(label==='方式 · 订阅')next='订阅';else if(label==='方式 · 单个节点')next='单个节点';
  else if(['输入 · 订阅链接','按钮 · 粘贴链接','按钮 · 识别示例二维码'].includes(label))next='订阅已填';
  else if(label==='按钮 · 扫码导入')next='扫码';else if(label==='按钮 · 返回链接导入')next='订阅';
  else if(label==='确认导入订阅'&&['订阅已填','订阅错误'].includes(key))next='导入中';
  else if(label==='按钮 · 添加节点')next='节点成功';
  if(next&&next!==key)await n.setReactionsAsync(r7Click(variants[next].id));
  else if(['关闭弹窗','按钮 · 取消','按钮 · 完成'].includes(label))await n.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'CLOSE'}]}]);
 }
 await variants['导入中'].setReactionsAsync(r7Timer(variants['订阅成功'].id));
 r6Overlay(mobile,'Import profile',variants['订阅']);
 const info=r7Body('弹窗 / '+platform+' / 全部订阅信息',w);fill(info,'Surface');stroke(info);rad(info,24);info.paddingLeft=info.paddingRight=24;info.paddingTop=info.paddingBottom=24;info.itemSpacing=16;
 add(info,r6Text('订阅信息',22,'Text','Medium'),r6Text('套餐信息由订阅服务返回',12,'Muted','Regular',w-48));
 for(const group of ['主订阅','备用订阅','旅行订阅']){const d=R6_INFO[group],card=borderCard('订阅套餐 · '+group,w-48,null,16,8,'Raised');rad(card,12);add(card,between(add(row('订阅名称与状态',w-80,24),r6Text(group,15,'Text','Medium'),r6Badge(d.status,d.tone==='Primary'?'Success':d.tone==='Warning'?'Warning':'Neutral'))),r6Text(d.used?d.used+' / '+d.total+' GB · 剩余 '+d.remaining+' GB':'流量未提供',13,'Secondary','Regular',w-80),r6Text(d.expires?d.expires+' 到期':'到期时间未提供',12,'Muted','Regular',w-80));if(d.used)add(card,r6Text('↑ '+d.up+'　↓ '+d.down+' · '+d.updated+' 更新',11,'Muted','Regular',w-80));add(info,card);}add(info,r6Button('完成','Primary',null,w-48));
 for(const n of info.findAll(n=>r5Name(n)==='按钮 · 完成'))await n.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'CLOSE'}]}]);r6Overlay(mobile,'Subscription info · 主订阅',info);
 const moves={};for(const state of ['选择分组','主订阅','备用订阅']){const moved=state!=='选择分组',c=r7Body('状态='+state,w);fill(c,'Surface');stroke(c);rad(c,24);c.paddingLeft=c.paddingRight=24;c.paddingTop=c.paddingBottom=24;c.itemSpacing=16;add(c,r6Text(moved?'已移入'+state:'移动到分组',22,'Text','Medium'),r6Text(moved?'办公 HTTP 已归组；之后不再显示移动入口。':'仅未分组节点可以移动',13,'Muted','Regular',w-48));if(!moved)for(const name of ['主订阅','备用订阅'])add(c,r6Button(name,'Secondary','folder',w-48));add(c,r6Button(moved?'完成':'取消','Primary',null,w-48));moves[state]=c;}
 r7VariantSet('交互 / '+platform+' / 移动节点',Object.values(moves),3);for(const n of moves['选择分组'].findAll(n=>'setReactionsAsync'in n))if(['按钮 · 主订阅','按钮 · 备用订阅'].includes(r5Name(n)))await n.setReactionsAsync(r7Click(moves[r5Name(n).slice(5)].id));for(const c of Object.values(moves))for(const n of c.findAll(n=>['按钮 · 完成','按钮 · 取消'].includes(r5Name(n))))await n.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'CLOSE'}]}]);r6Overlay(mobile,'Move group',moves['选择分组']);
 for(const key of ['Import profile','Subscription info · 主订阅','Move group']){const scrim=uFind(reg[key],'关闭弹窗遮罩');await scrim.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'CLOSE'}]}]);r7Changes.push(reg[key].id);}return variants['订阅'].parent.id;
}
async function r7Chains(mobile){
 const reg=mobile?registry.mobile:registry.desktop,w=mobile?353:1120,keys=['Chain editor','Chain reordered','Chain tested','Chain reverse tested','Chain empty'],variants={};
 for(const key of keys){const c=r7Body('状态='+key.replace('Chain ','').replace('editor','默认').replace('reordered','调整顺序').replace('tested','测试通过').replace('empty','缺少出口'),w);r7CloneBody(reg[key],c);if(mobile){const footer=uFind(reg[key],'Fixed chain actions');if(footer)add(c,footer.children[0].clone());}variants[key]=c;}
 r7VariantSet('交互 / '+(mobile?'移动端':'桌面端')+' / 代理链编排',Object.values(variants),mobile?3:2);
 for(const [key,c]of Object.entries(variants))for(const n of c.findAll(n=>'setReactionsAsync'in n&&n.reactions.length)){const rr=JSON.parse(JSON.stringify(n.reactions));let changed=false;for(const r of rr)for(const a of r.actions||[])if(a.type==='NODE'&&a.navigation==='NAVIGATE'){const target=Object.keys(reg).find(k=>reg[k].id===a.destinationId),next=variants[target]||(target==='Chain picker'?variants['Chain editor']:null);if(next){a.destinationId=next.id;a.navigation='CHANGE_TO';changed=true;}}if(changed){for(const r of rr)r.actions=(r.actions||[]).filter(a=>!(a.type==='NODE'&&a.navigation==='CHANGE_TO'&&a.destinationId===c.id));try{await n.setReactionsAsync(rr.filter(r=>r.actions.length));}catch(e){throw new Error('链路组件 '+key+' / '+n.name+' → '+JSON.stringify(rr)+': '+String(e));}}}
 const screen=reg['Chain editor'],b=uFind(screen,'Content');for(const n of [...b.children])if(r5Name(n)!=='Page header')n.remove();add(b,r7Instance(variants['Chain editor'],'代理链交互编排'));const footer=uFind(screen,'Fixed chain actions');if(footer)footer.remove();r7Changes.push(screen.id);return variants['Chain editor'].parent.id;
}
function r7Section(page,name,nodes,columns,y){const section=figma.createSection();page.appendChild(section);r6Name(section,name);section.setPluginData('rainlink-compact-section','7.0');section.x=0;section.y=y;section.fills=[{type:'SOLID',color:{r:.075,g:.08,b:.087}}];const w=Math.max(...nodes.map(n=>n.width)),h=Math.max(...nodes.map(n=>n.height));nodes.forEach((n,i)=>{section.appendChild(n);n.x=48+(i%columns)*(w+80);n.y=80+Math.floor(i/columns)*(h+100);});section.resizeWithoutConstraints(96+columns*(w+80)-80,128+Math.ceil(nodes.length/columns)*(h+100)-100);return section;}
function r7Arrange(){for(const [reg,page,main]of [[registry.desktop,desktopPage,R7_MAIN_D],[registry.mobile,mobilePage,R7_MAIN_M]]){const one=r7Section(page,'01 · 主要画面 · 4 × 2',main.map(k=>reg[k]),4,0);const support=Object.keys(reg).filter(k=>!main.includes(k));r7Section(page,'02 · 必要弹窗与代理链',support.map(k=>reg[k]),4,one.height+200);for(const n of page.children)if(n.type==='TEXT')n.visible=false;}}
async function r7Remap(old){
 const kept=new Set([...Object.values(registry.desktop),...Object.values(registry.mobile)].map(n=>n.id));
 const maps={};for(const [platform,reg]of [['desktop',registry.desktop],['mobile',registry.mobile]])for(const [key,id]of Object.entries(old[platform])){
  let target=key;if(!reg[key])target=/Import|Manual node|QR import/.test(key)?'Import profile':key.startsWith('Subscription info')?'Subscription info · 主订阅':/Move group|New group/.test(key)?'Move group':/Chain/.test(key)?'Chain editor':/选择分组|Source success|Manual success|Import success|Moved$|Groups custom|Quick switch/.test(key)?'Profiles':/Nodes|group|grouped|选择节点|added nodes|Moved backup|Moved nodes/.test(key)?'Nodes':/Rule editor/.test(key)?'Rules':/Profile editor|Appearance/.test(key)?'Settings':platform==='mobile'?'Home':'Dashboard';
  maps[id]={id:reg[target].id,key:target};
 }
 let rewritten=0;for(const root of [...Object.values(registry.desktop),...Object.values(registry.mobile),dsPage])for(const node of root.findAll(n=>'setReactionsAsync'in n&&n.reactions.length)){
  const rr=JSON.parse(JSON.stringify(node.reactions));let changed=false;
  if(root===dsPage){let changed=false;for(const r of rr){const before=(r.actions||[]).length;r.actions=(r.actions||[]).filter(a=>!(a.type==='NODE'&&a.navigation!=='CHANGE_TO'&&maps[a.destinationId]));if(r.actions.length!==before)changed=true;}if(changed)await node.setReactionsAsync(rr.filter(r=>r.actions.length));continue;}
  for(const r of rr)for(const a of r.actions||[])if(a.type==='NODE'&&a.destinationId&&maps[a.destinationId]&&a.navigation!=='CHANGE_TO'){
   const dest=maps[a.destinationId];if(a.destinationId!==dest.id){a.destinationId=dest.id;changed=true;}
   if(['Import profile','Subscription info · 主订阅','Move group'].includes(dest.key)&&a.navigation!=='OVERLAY'){a.navigation='OVERLAY';changed=true;}
  }
  if(changed){for(const r of rr)r.actions=(r.actions||[]).filter(a=>!(a.type==='NODE'&&a.navigation==='NAVIGATE'&&a.destinationId===root.id));try{await node.setReactionsAsync(rr.filter(r=>r.actions.length));}catch(e){throw new Error('精简路由 '+root.name+' / '+node.name+' → '+JSON.stringify(rr)+': '+String(e));}rewritten++;}
 }
 return {rewritten,kept:[...kept]};
}
async function r7WireScreens(){
 const valid=new Set([...Object.values(registry.desktop),...Object.values(registry.mobile)].map(n=>n.id));
 for(const link of uLinks){if(!link.node||link.node.removed)continue;let root=link.node;while(root.parent&&root.parent.type!=='PAGE')root=root.parent;if(!valid.has(root.id))continue;const [p,...k]=link.target.split('/'),reg=p==='M'?registry.mobile:registry.desktop,key=k.join('/');const dest=reg[key]||(/Chain/.test(key)?reg['Chain editor']:/Import|Manual/.test(key)?reg['Import profile']:/Nodes|group/.test(key)?reg.Nodes:reg.Profiles);if(dest.id===root.id)continue;await link.node.setReactionsAsync(r7Click(dest.id,['Import profile','Move group','Subscription info · 主订阅'].includes(key)?'OVERLAY':'NAVIGATE'));}
 for(const reg of [registry.desktop,registry.mobile])for(const screen of Object.values(reg))for(const n of screen.findAll(n=>'setReactionsAsync'in n)){
  const name=r5Name(n);let key;
  if(name==='未分组节点移动'&&n.visible)key='Move group';else if(name==='查看订阅信息'&&n.visible)key='Subscription info · 主订阅';
  else if(n.type==='INSTANCE'&&!n.reactions.some(r=>(r.actions||[]).some(a=>a.navigation==='CHANGE_TO'))){const texts=n.findAll(t=>t.type==='TEXT').map(t=>t.characters);if(texts.length===1){const label=texts[0];if(label==='节点')key='Nodes';else if(['选择分组','切换分组','管理分组','全部分组','返回分组'].includes(label))key='Profiles';else if(['代理链','编排代理链'].includes(label))key='Chain editor';else if(label==='返回节点')key='Nodes';else if(label==='添加')key='Import profile';else if(label==='保存并选中')key=reg===registry.mobile?'Home':'Dashboard';}}
  if(key&&reg[key].id!==screen.id)await n.setReactionsAsync(r7Click(reg[key].id,['Import profile','Move group','Subscription info · 主订阅'].includes(key)?'OVERLAY':'NAVIGATE'));
 }
}
async function r7CompactMain(){
 figma.showUI('<body style="padding:24px;background:#151617;color:#c0c2c8;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#8adcbf">RainLink / 精简画布</h2><p id="s">将整页状态合并为组件交互…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:480,height:170});
 await r5Yield();await r5Initialize();figma.skipInvisibleInstanceChildren=false;Object.assign(C,R5_COLORS);
 if(figma.root.getPluginData('rainlink-compact-version')==='7.0'){await r7FinishMain();return;}
 for(const n of [...dsPage.children])if(n.type==='COMPONENT_SET'&&n.children.some(c=>c.getPluginData('rainlink-compact-component')==='7.0'))n.remove();
 const collections=await figma.variables.getLocalVariableCollectionsAsync();collection=collections.find(c=>/Colors \/ Dark|颜色 \/ 深色/.test(c.name));lightCollection=collections.find(c=>/Colors \/ Light|颜色 \/ 浅色/.test(c.name));darkMode=collection.defaultModeId;for(const variable of await figma.variables.getLocalVariablesAsync('COLOR')){const key=Object.keys(R5_TOKEN_NAMES).find(k=>variable.name===k||variable.name===R5_TOKEN_NAMES[k]);if(key)(variable.variableCollectionId===lightCollection.id?lightVars:vars)[key]=variable;}
 gInteractionCollection=collections.find(c=>c.name==='RainLink / 交互状态');for(const variable of await figma.variables.getLocalVariablesAsync())if(variable.variableCollectionId===gInteractionCollection.id)gVars[variable.name]=variable;
 const prior=JSON.parse(figma.root.getPluginData('rainlink-report')),old={desktop:{...prior.desktop},mobile:{...prior.mobile}},home={},selection={};
 await r6NetworkLibrary();
 for(const mobile of [false,true]){const platform=mobile?'mobile':'desktop';figma.ui.postMessage({status:'合并'+(mobile?'移动端':'桌面端')+'的选择、弹窗与连接状态…'});home[platform]=await r7Home(mobile);await r7Dialogs(mobile);selection[platform]={groups:await r7Groups(mobile),nodes:await r7Nodes(mobile),chains:await r7Chains(mobile)};}
 const removed=[];for(const [reg,main]of [[registry.desktop,R7_MAIN_D],[registry.mobile,R7_MAIN_M]]){const keep=new Set([...main,'Chain editor','Import profile','Subscription info · 主订阅','Move group']);for(const key of Object.keys(reg))if(!keep.has(key)){removed.push({key,id:reg[key].id,node:reg[key]});delete reg[key];}}
 figma.ui.postMessage({status:'重接精简后的原型并移除重复整页稿…'});const routes=await r7Remap(old);await r7WireScreens();for(const x of removed)x.node.remove();
 r7Arrange();const ys={desktop:8000,mobile:8000};for(const set of r7Sets){const mobile=set.name.includes('移动端'),platform=mobile?'mobile':'desktop';set.x=mobile?4400:0;set.y=ys[platform];ys[platform]+=set.height+180;}
 desktopPage.flowStartingPoints=[{nodeId:registry.desktop.Dashboard.id,name:'桌面端 / 主要交互'},{nodeId:registry.desktop.Profiles.id,name:'桌面端 / 添加与自动归组'}];mobilePage.flowStartingPoints=[{nodeId:registry.mobile.Home.id,name:'移动端 / 主要交互'},{nodeId:registry.mobile.Profiles.id,name:'移动端 / 添加与自动归组'}];
 const report=await r5AuditDocument();report.version='7.0';report.desktop=Object.fromEntries(Object.entries(registry.desktop).map(([k,n])=>[k,n.id]));report.mobile=Object.fromEntries(Object.entries(registry.mobile).map(([k,n])=>[k,n.id]));report.counts={desktop:Object.keys(registry.desktop).length,mobile:Object.keys(registry.mobile).length,components:dsPage.findAll(n=>n.type==='COMPONENT').length};
 report.compactCanvas={previousScreens:Object.keys(old.desktop).length+Object.keys(old.mobile).length,removedFullScreens:removed.length,mainDesktop:R7_MAIN_D,mainMobile:R7_MAIN_M,homeStates:home,selectionComponents:selection,rewrittenRoutes:routes.rewritten,statesAreComponentVariants:true,crossPageSelection:'Representative Figma interactions; local interactive state is not a runtime shared store'};
 report.subscriptionDialogs.changedScreenIds=r7Changes;report.subscriptionDialogs.overlayIds=[...Object.values(registry.desktop),...Object.values(registry.mobile)].filter(n=>n.getPluginData('rainlink-dialog')).map(n=>n.id);report.egress.powerTransitions=home;delete report.nativeBackup;delete report.screenshotVerification;report.livePrototypeVerification={status:'pending compact rescan'};
 for(const panel of dsPage.children.filter(n=>n.type==='FRAME'))for(const t of panel.findAll(n=>n.type==='TEXT')){if(/164|162|225|223|326|448|3810/.test(t.characters)&&!isTechnicalText(t.characters))r6Copy(t,t.characters.replace(/164|225/g,'12').replace(/162|223/g,'11').replace(/326|448/g,'23').replace(/3810/g,'组件交互'));}
 await r71ApplyHomeControls(report);await r72ApplyDensity(report);const controlsAudit=await r5AuditDocument();report.overflow=controlsAudit.overflow;report.untranslatedDisplayCopy=controlsAudit.untranslatedDisplayCopy;
 const audit=uFind(dsPage,'Delivery / Native audit');audit.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);audit.visible=false;figma.root.setPluginData('rainlink-report',JSON.stringify(report));figma.root.setPluginData('rainlink-compact-version','7.0');
 await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Dashboard];figma.viewport.scrollAndZoomIntoView(figma.currentPage.selection);figma.notify('已精简：桌面 8 个主页面，移动 8 个主要画面；移除 '+removed.length+' 个重复状态稿。');figma.closePlugin();
}
async function r7FinishMain(){
 figma.showUI('<body style="padding:24px;background:#151617;color:#c0c2c8;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#8adcbf">RainLink / 精简稿核验</h2><p id="s">保留现有画面，核验导航、中文与原型…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:480,height:170});
 await r5Initialize();figma.skipInvisibleInstanceChildren=false;
 // Repair controls created after localization, whose base text is still "按钮".
 for(const page of [desktopPage,mobilePage,dsPage])for(const n of page.findAll(n=>n.type==='INSTANCE'&&r5Name(n).startsWith('Button · '))){
  const label=r5Name(n).slice(9),text=uFind(n,'Label'),slot=uFind(n,'Icon slot');
  if(text){r6Copy(text,label);text.visible=!!label;}
  const symbol={'添加':'plus','全部分组':'folder','代理链':'link','返回概览':'grid'}[label];
  if(slot&&(symbol||!label)){slot.visible=true;if(symbol&&icons[symbol])slot.swapComponent(icons[symbol]);}
 }
 const groupHeader=uFind(registry.mobile.Profiles,'Page header'),nodeHeader=uFind(registry.mobile.Nodes,'Page header');
 for(const header of [groupHeader,nodeHeader]){
  const title=header.children.find(n=>n.type==='FRAME'),back=header.children.find(n=>n.type==='INSTANCE');
  if(back){back.primaryAxisSizingMode='FIXED';back.resize(40,44);}
  if(header===nodeHeader&&!header.children.some(n=>r5Name(n)==='按钮 · 添加节点')){
   const addNode=r6Button('','Ghost','plus',40);r6Name(addNode,'按钮 · 添加节点');add(header,addNode);await addNode.setReactionsAsync(r7Click(registry.mobile['Import profile'].id,'OVERLAY'));
  }
  const width=header===nodeHeader?249:301;if(title){title.resize(width,title.height);for(const t of title.findAll(n=>n.type==='TEXT')){t.resize(width,t.height);t.textAutoResize='HEIGHT';}}
 }
 for(const reg of [registry.desktop,registry.mobile])for(const screen of Object.values(reg))for(const n of screen.findAll(n=>n.type==='INSTANCE')){
  const name=r5Name(n),label=name.startsWith('Button · ')?name.slice(9):'',route={'添加':'Import profile','全部分组':'Profiles','代理链':'Chain editor','返回概览':reg===registry.mobile?'Home':'Dashboard'}[label];
  if(route&&reg[route].id!==screen.id)await n.setReactionsAsync(r7Click(reg[route].id,route==='Import profile'?'OVERLAY':'NAVIGATE'));
 }
 const report=JSON.parse(figma.root.getPluginData('rainlink-report')),names={Dashboard:'概览',Home:'首页',Nodes:'节点',Profiles:'分组',Rules:'规则',Connections:'连接',Traffic:'流量',Logs:'日志',Settings:'设置','Quick switch':'快速选择',DNS:'DNS 设置','Chain editor':'代理链编排','Import profile':'添加弹窗','Move group':'移动节点弹窗','Subscription info · 主订阅':'订阅信息弹窗'},nav={概览:'Dashboard',首页:'Home',节点:'Nodes',分组:'Profiles',规则:'Rules',连接:'Connections',流量:'Traffic',日志:'Logs',设置:'Settings'};
 for(const [reg,page,platform]of [[registry.desktop,desktopPage,'桌面端'],[registry.mobile,mobilePage,'移动端']]){
  for(const screen of Object.values(reg)){
   screen.name=platform+' / '+names[screen.getPluginData('rainlink').split('/').slice(1).join('/')];
   for(const t of screen.findAll(n=>n.type==='TEXT'&&n.characters==='Connected'))r6Copy(t,'已连接');
   const side=uFind(screen,'Primary navigation'),bottom=uFind(screen,'Mobile / Bottom navigation');
   for(const n of [...(side?.children||[]),...(bottom?.children||[])]){const label=n.findOne(t=>t.type==='TEXT'&&nav[t.characters]);if(label&&reg[nav[label.characters]])await n.setReactionsAsync(reg[nav[label.characters]].id===screen.id?[]:r7Click(reg[nav[label.characters]].id,'NAVIGATE'));}
   for(const n of screen.findAll(n=>'setReactionsAsync'in n)){
    if(r5Name(n)==='未分组节点移动')await n.setReactionsAsync(r7Click(reg['Move group'].id,'OVERLAY'));
    if(n.type==='INSTANCE'&&screen===reg.Home){const texts=n.findAll(t=>t.type==='TEXT');if(texts.length===1&&texts[0].characters==='选择')await n.setReactionsAsync(r7Click(reg['Quick switch'].id,'NAVIGATE'));}
   }
  }
  for(const n of [...page.children])if(n.type!=='SECTION')n.remove();
 }
 for(const set of dsPage.children.filter(n=>n.type==='COMPONENT_SET'&&r5Name(n).endsWith('节点选择'))){
  const groups={'主订阅':G_MAIN,'备用订阅':G_BACKUP,'未分组':G_LOOSE,'旅行订阅':G_MAIN.slice(0,4)};
  for(const c of set.children){const group=c.name.match(/^分组=([^,]+)/)?.[1];for(const row of c.children.filter(n=>r5Name(n).startsWith('选择节点 · '))){const data=groups[group]?.[Number(r5Name(row).slice(7))],tag=uFind(row,'节点协议');if(data&&tag)r6Copy(tag.findOne(n=>n.type==='TEXT'),data.p);}}
 }
 // Restore chain controls after maintenance reruns; no additional full screen is made.
 for(const set of dsPage.children.filter(n=>n.type==='COMPONENT_SET'&&r5Name(n).endsWith('代理链编排'))){
  const parts=set.children,normal=parts.find(c=>/默认/.test(c.name)),reorder=parts.find(c=>/调整顺序/.test(c.name)),tested=parts.find(c=>/测试通过/.test(c.name)&&!/reverse/.test(c.name)),reverse=parts.find(c=>/reverse/.test(c.name)),empty=parts.find(c=>/缺少出口/.test(c.name));
  for(const c of parts)for(const n of c.findAll(n=>n.type==='INSTANCE')){const texts=n.findAll(t=>t.type==='TEXT').map(t=>t.characters);if(texts.length!==1)continue;const label=texts[0],swapped=c===reorder||c===reverse;let next;if(['测试链路','测试整链'].includes(label))next=swapped?reverse:tested;else if(['上移','下移'].includes(label)&&n.opacity>.5)next=swapped?normal:reorder;else if(label==='移除')next=empty;else if(['更换节点','选择出口节点'].includes(label))next=normal;if(next&&next.id!==c.id)await n.setReactionsAsync(r7Click(next.id));else if(['保存并选中','保存代理链','选中代理链'].includes(label))await n.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'BACK'}]}]);}
 }
 await r71ApplyHomeControls(report);
 await r72ApplyDensity(report);
 const audit=await r5AuditDocument();report.overflow=audit.overflow;report.untranslatedDisplayCopy=audit.untranslatedDisplayCopy;report.compactCanvas.maintenanceCompleted=true;report.compactCanvas.controlLabelsRestored=true;report.counts.components=dsPage.findAll(n=>n.type==='COMPONENT').length;
 const text=uFind(dsPage,'Delivery / Native audit');text.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);text.visible=false;figma.root.setPluginData('rainlink-report',JSON.stringify(report));await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Dashboard];figma.viewport.scrollAndZoomIntoView(figma.currentPage.selection);figma.notify('精简完成 · 16 个主要画面 · 7 个必要弹窗与编排画面');figma.closePlugin();
}
