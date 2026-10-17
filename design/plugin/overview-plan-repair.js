async function gPrototypePlanProbe(){
 await figma.loadAllPagesAsync();
 const page=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='desktop');
 const group=page.findOne(n=>n.getPluginData('rainlink-control-kind')==='select-group');
 const variable=(await figma.variables.getLocalVariablesAsync('STRING')).find(v=>v.name==='选择/分组');
 let result='SET_VARIABLE: supported';
 try{await group.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'SET_VARIABLE',variableId:variable.id,variableValue:{type:'STRING',value:'备用订阅'}}]}]);}
 catch(e){result='SET_VARIABLE: '+String(e.message||e);}
 figma.showUI('<body style="background:#10181e;color:#86e5c3;padding:20px;font:13px sans-serif">'+result+'</body>',{width:520,height:160});
}
const gStaticTargets=new Map();
const gStaticNodes={
 'Nodes':['主订阅',G_MAIN], 'Nodes tested':['主订阅',G_MAIN],
 'Backup group':['备用订阅',G_BACKUP], 'Ungrouped':['未分组',G_LOOSE],
 'Ungrouped after move':['未分组',G_LOOSE.slice(1)],
 'Moved nodes':['主订阅',[...G_MAIN,G_LOOSE[0]]], 'Moved backup':['备用订阅',[...G_BACKUP,G_LOOSE[0]]],
 'Customgroup':['开发环境',[G_LOOSE[0]]], 'Travel group':['旅行订阅',[G_MAIN[2],G_MAIN[0],G_MAIN[1],G_MAIN[3]]],
 'Manual added nodes':['未分组',[...G_LOOSE,{name:'备用 HTTP',p:'HTTP',region:'自定义',code:'CN',ping:'16',server:'proxy.backup.example.com:8080'}]]
};
function gStaticText(n,s){if(!n)return;n.setBoundVariable('characters',null);n.characters=s;n.setPluginData('rainlink-original-text',s);}
function gStaticKey(group,node){return group+' · '+node.name;}
function gStaticClone(source,key,reg,page,prefix){
 let n=reg[key];if(n)n.remove();n=source.clone();page.appendChild(n);n.name=(prefix==='D/'?'Desktop / ':'Mobile / ')+key;n.setPluginData('rainlink-canonical-name',n.name);n.setPluginData('rainlink',prefix==='D/'?'desktop/'+key:'mobile/'+key);n.setPluginData('rainlink-group-version','4.0');reg[key]=n;return n;
}
function gUnbindInteractionState(root){
 const ids=new Set(Object.values(gVars).map(v=>v.id));
 for(const n of [root,...root.findAll(()=>true)]){
  const bound=n.boundVariables||{};
  for(const field of ['characters','visible','opacity'])if(bound[field]&&ids.has(bound[field].id))n.setBoundVariable(field,null);
  for(const field of ['fills','strokes'])if(field in n&&Array.isArray(n[field]))n[field]=n[field].map(p=>{
   const a=p.boundVariables&&p.boundVariables.color;
   if(!a||!ids.has(a.id))return p;
   const v=Object.values(gVars).find(v=>v.id===a.id),value=v.valuesByMode[gInteractionCollection.defaultModeId];
   return {type:'SOLID',color:{r:value.r,g:value.g,b:value.b},opacity:p.opacity===undefined?1:p.opacity};
  });
 }
}
function gStaticChosen(screen,group,data){
 for(const c of screen.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Group · '))){
  const chosen=(c.getPluginData('rainlink-canonical-name')||c.name)==='Group · '+group;
  const check=uFind(c,'分组选中');if(check)check.visible=chosen;fill(c,chosen?'PrimarySurface':'Surface');
 }
 const summary=uFind(screen,'Selection summary');
 if(summary){const ts=summary.children.filter(n=>n.type==='TEXT');gStaticText(ts[0],group);gStaticText(ts[1],data.name);}
 screen.setPluginData('rainlink-chosen-target',gStaticKey(group,data));
}
function gStaticNodeChosen(screen,group,data){
 for(const c of screen.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Group node / '))){
  const t=uFind(c,'节点名称'),selected=t&&t.characters===data.name,check=uFind(c,'节点选中');
  if(check)check.visible=selected;fill(c,selected?'PrimarySurface':'Surface');stroke(c,selected?'Primary':'Stroke');
 }
 const aside=uFind(screen,'Selected group node');
 if(aside){const ts=aside.children.filter(n=>n.type==='TEXT');gStaticText(ts[1],data.name);const facts=uFind(aside,'Selected node protocol');if(facts){gStaticText(facts.findOne(n=>n.type==='TEXT'&&(n.getPluginData('rainlink-canonical-name')||n.name)==='Label'),data.p);gStaticText(facts.children.find(n=>n.type==='TEXT'),data.ping+' ms');}}
 screen.setPluginData('rainlink-chosen-target',gStaticKey(group,data));
}
function gStaticHeader(screen,group,data,online=false){
 const bar=uFind(screen,'Connection bar');if(!bar)return;for(const n of [...bar.children])n.remove();
 add(bar,add(row('Persistent group status',null,null,10),dot(online?'Primary':'Muted'),uText(online?'已连接':'未连接',13,online?'Primary':'Muted','Medium'),online?uSmall(group+' / '+data.name,'Secondary'):null),add(row('Persistent group speeds',null,null,16),online?uSmall(data.ping+' ms','Secondary'):null,uSmall(online?'↓ 12.8 MB/s':'↓ 0 MB/s','Secondary'),uSmall(online?'↑ 1.4 MB/s':'↑ 0 MB/s','Muted'),uButton('概览','D/'+(online?'Dashboard':'Disconnected'),'Ghost','grid')));
}
function gStaticHomeTarget(screen,group,data,online=false){
 const target=uFind(screen,'Overview target');if(target){gStaticText(target.children[0],group);gStaticText(target.children[1],data.name);}
 const mobile=uFind(screen,'Selected connection group');
 if(mobile){const name=uFind(mobile,'Selected group heading').children[0];gStaticText(name,group);const node=mobile.children.find(n=>n.type==='TEXT');gStaticText(node,data.name);const facts=uFind(mobile,'Selected group node');if(facts){gStaticText(facts.children[0],'延迟');gStaticText(facts.children[1],data.ping+' ms');}}
 gStaticHeader(screen,group,data,online);screen.setPluginData('rainlink-chosen-target',gStaticKey(group,data));screen.setPluginData('rainlink-overview-online',online?'true':'false');
 // Remove duplicate mode labels; the mode component is the one source of truth.
 const hero=uFind(screen,'Connection hero heading');if(hero){const badgeNode=hero.children.find(n=>n.type==='INSTANCE');if(badgeNode)badgeNode.visible=false;}
 const caption=uFind(screen,'VPN mode caption');if(caption){caption.children[0].visible=false;gStaticText(caption.children[1],online?'点按关闭 VPN':'点按开启 VPN');}
}
async function gStaticModeLibrary(){
 for(const mobile of [false,true]){
  const name='Overview / Proxy mode / '+(mobile?'Mobile':'Desktop'),rule=masters[name];
  let set=rule.parent.type==='COMPONENT_SET'?rule.parent:null;
  if(set){for(const n of [...set.children])if(n.id!==rule.id)n.remove();}
  const variants=[rule];
  for(const mode of ['全局','直连']){const c=rule.clone();dsPage.appendChild(c);variants.push(c);}
  if(!set)set=figma.combineAsVariants(variants,dsPage);else for(const c of variants)if(c.parent!==set)set.appendChild(c);
  set.name='Overview / 代理模式 / '+(mobile?'Mobile':'Desktop');set.setPluginData('rainlink-canonical-name',set.name);set.layoutMode='VERTICAL';set.primaryAxisSizingMode='AUTO';set.counterAxisSizingMode='AUTO';set.itemSpacing=24;set.paddingLeft=set.paddingRight=set.paddingTop=set.paddingBottom=24;
  for(let i=0;i<variants.length;i++){
   const c=variants[i];gUnbindInteractionState(c);c.name='模式='+G_MODES[i];c.setPluginData('rainlink-canonical-name',i===0?name:c.name);c.description='代理模式交互组件。规则、全局和直连，三种模式均在概览中切换。';
   for(const option of G_MODES){const item=uFind(c,'代理模式 · '+option);fill(item,option===G_MODES[i]?'PrimarySurface':'Raised');const t=item.findOne(n=>n.type==='TEXT');fill(t,option===G_MODES[i]?'Primary':'Secondary');}
   const desc=uFind(c,'模式说明');if(desc)gStaticText(desc,G_MODE_COPY[i]);
  }
  for(const c of variants)for(let i=0;i<G_MODES.length;i++){
   const option=uFind(c,'代理模式 · '+G_MODES[i]);
   if(c.id===variants[i].id){await option.setReactionsAsync([]);continue;}
   await option.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:variants[i].id,navigation:'CHANGE_TO',transition:{type:'SMART_ANIMATE',easing:{type:'EASE_OUT'},duration:.18}}]}]);
  }
  set.x=4870;set.y=mobile?420:0;
 }
}
async function gStaticWire(){
 figma.ui.postMessage({status:'构建免费方案可用的选择状态原型…'});
 // No paid prototype actions are used. Selection states are native Auto Layout frames.
 for(const p of [desktopPage,mobilePage])for(const s of p.children.filter(n=>n.type==='FRAME'&&n.getPluginData('rainlink')))gUnbindInteractionState(s);
 const originalLinks=[...pending,...uLinks].filter(l=>l.node&&!l.node.removed),staticRoutes=new Map();
 const put=(n,target,kind='navigate')=>{if(n)staticRoutes.set(n.id,{node:n,target,kind});};
 const rootOf=n=>{let r=n;while(r.parent&&r.parent.type!=='PAGE')r=r.parent;return r;};
 for(const l of originalLinks)if(['D/','M/'].some(p=>l.target.startsWith(p))){
  const root=rootOf(l.node),online=root.getPluginData('rainlink-overview-online')==='true';
  let target=l.target;if((target==='D/Dashboard'||target==='M/Home')&&!online)target=target[0]+('/Disconnected');
  put(l.node,target);
 }
 // Every node in the example lists gets an accurate selected state and overview target.
 const targets=new Map();
 for(const [group,nodes]of Object.values(gStaticNodes))for(const data of nodes)targets.set(gStaticKey(group,data),{group,data});
 targets.set('主订阅 · 开发代理链',{group:'主订阅',data:{name:'开发代理链 · 办公 HTTP → 东京',p:'2 跳 · TCP',ping:'46'},chain:true});
 targets.set('主订阅 · 反向开发代理链',{group:'主订阅',data:{name:'开发代理链 · 东京 → 办公 HTTP',p:'2 跳 · TCP',ping:'39'},chain:'reverse'});
 for(const [id,{group,data,chain}]of targets){
  const ready='待连接 · '+id,live='已连接 · '+id;
  gHome(ready,group,data,false,chain||false);gHome(live,group,data,true,chain||false);
  gStaticTargets.set(id,{ready,live,group,data});
  for(const [reg,p]of [[registry.desktop,'D/'],[registry.mobile,'M/']]){
   for(const [key,online]of [[ready,false],[live,true]]){
    const s=reg[key];gUnbindInteractionState(s);gStaticHomeTarget(s,group,data,online);
    const power=s.findOne(n=>n.getPluginData('rainlink-control-kind')==='vpn-power');put(power,p+(online?ready:live),'vpn-power');
    for(const n of s.findAll(n=>(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Navigate · ')||(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Tab · '))){const canonical=n.getPluginData('rainlink-canonical-name')||n.name,dest=canonical.split(' · ')[1];put(n,p+(dest==='Dashboard'||dest==='Home'?key:dest));}
    for(const n of s.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Button · '))){const canon=n.getPluginData('rainlink-canonical-name')||n.name;if(canon.includes('选择分组')||canon==='Button · 选择')put(n,p+(online?'Connected switch':'Quick switch'));}
   }
  }
 }
 for(const [reg,page,p]of [[registry.desktop,desktopPage,'D/'],[registry.mobile,mobilePage,'M/']]){
  const inventories=new Map();
  for(const [key,[group,nodes]]of Object.entries(gStaticNodes)){
   for(const data of nodes){const stateKey='选择节点 · '+key+' · '+data.name;
    const s=gStaticClone(reg[key],stateKey,reg,page,p);gUnbindInteractionState(s);gStaticNodeChosen(s,group,data);inventories.set(stateKey,{s,group,data});
   }
  }
  const allInventories=[...Object.entries(gStaticNodes).map(([key,[group,nodes]])=>({s:reg[key],group,data:nodes[0],base:key})),...Array.from(inventories.values()).map(x=>({...x,base:x.s.getPluginData('rainlink').split('/').slice(1).join('/').split(' · ')[1]}))];
  for(const {s,group,data,base}of allInventories){
   if(!base||!gStaticNodes[base])continue;
   const target=gStaticTargets.get(gStaticKey(group,data));
   for(const n of s.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Group node / '))){const t=uFind(n,'节点名称'),next='选择节点 · '+base+' · '+t.characters;put(n,p+next,'select-node');const move=uFind(n,'未分组节点移动');if(move&&move.visible&&t.characters==='办公 HTTP')put(move,p+'Move group');}
   for(const n of s.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Button · '))){const c=n.getPluginData('rainlink-canonical-name')||n.name;if(c==='Button · 去概览')put(n,p+target.ready);else if(c==='Button · 全部分组')put(n,p+'Profiles');else if(c==='Button · 代理链')put(n,p+'Chains');else if(c==='Button · 测速'||c==='Button · 测速完成')put(n,p+(base==='Nodes'?'Nodes tested':base));}
   for(const n of s.findAll(n=>(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Navigate · ')||(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Tab · '))){const dest=(n.getPluginData('rainlink-canonical-name')||n.name).split(' · ')[1];put(n,p+(dest==='Dashboard'||dest==='Home'?target.ready:dest));}
  }
  // Group card selection stays on the group list. Its node entry is a separate action.
  const groupPages=['Profiles','Source success','Import success','Manual success','Moved','Groups custom','Quick switch'];
  for(const key of groupPages){if(!reg[key])continue;const source=reg[key],states=[];
   const cards=source.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Group · '));
   for(const card of cards){const group=(card.getPluginData('rainlink-canonical-name')||card.name).slice(8),data=gGroupsData[group][0],stateKey='选择分组 · '+key+' · '+group,s=gStaticClone(source,stateKey,reg,page,p);gUnbindInteractionState(s);gStaticChosen(s,group,data);states.push({s,group,data,stateKey});}
   for(const {s,group,data}of [{s:source,group:'主订阅',data:G_MAIN[0]},...states]){
    const choice=gStaticTargets.get(gStaticKey(group,data));
    for(const card of s.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Group · '))){const name=(card.getPluginData('rainlink-canonical-name')||card.name).slice(8);put(card,p+'选择分组 · '+key+' · '+name,'select-group');const detail=uFind(card,'组节点入口');const target={'主订阅':key==='Moved'?'Moved nodes':'Nodes','备用订阅':'Backup group','未分组':key==='Manual success'?'Manual added nodes':['Moved','Groups custom'].includes(key)?'Ungrouped after move':'Ungrouped','开发环境':'Customgroup','旅行订阅':'Travel group'}[name];put(detail,p+target);}
    for(const n of s.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Button · '))){const c=n.getPluginData('rainlink-canonical-name')||n.name;if(['Button · 去概览','Button · 返回概览','Button · 关闭'].includes(c))put(n,p+choice.ready);}
    for(const n of s.findAll(n=>(n.getPluginData('rainlink-canonical-name')||n.name)==='Navigate · Dashboard'||(n.getPluginData('rainlink-canonical-name')||n.name)==='Tab · Home'))put(n,p+choice.ready);
   }
  }
  // Saving a chain selects its target and opens a disconnected overview.
  for(const [key,target]of [['Chain tested','主订阅 · 开发代理链'],['Chain reverse tested','主订阅 · 反向开发代理链'],['Chains','主订阅 · 开发代理链']])for(const n of reg[key].findAll(n=>n.getPluginData('rainlink-control-kind')==='select-chain'))put(n,p+gStaticTargets.get(target).ready,'select-chain');
  const onlineSwitch=gStaticClone(reg['Quick switch'],'Connected switch',reg,page,p);gUnbindInteractionState(onlineSwitch);gStaticHeader(onlineSwitch,'主订阅',G_MAIN[0],true);
  const localPending=gStaticClone(reg['Pending selection'],'待应用 · 未分组',reg,page,p);gUnbindInteractionState(localPending);
  for(const t of localPending.findAll(n=>n.type==='TEXT'))if(t.characters.includes('待应用：备用订阅'))gStaticText(t,'待应用：未分组 / 办公 HTTP · 关闭再开启 VPN 后生效');
  for(const card of onlineSwitch.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Group · '))){const group=(card.getPluginData('rainlink-canonical-name')||card.name).slice(8);put(card,p+(group==='主订阅'?(p==='D/'?'Dashboard':'Home'):group==='未分组'?'待应用 · 未分组':'Pending selection'),'select-group-pending');}
  for(const n of onlineSwitch.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Button · ')))if(['Button · 返回概览','Button · 关闭'].includes(n.getPluginData('rainlink-canonical-name')||n.name))put(n,p+(p==='D/'?'Dashboard':'Home'));
  const pendingScreen=reg['Pending selection'];for(const n of pendingScreen.findAll(n=>n.getPluginData('rainlink-control-kind')==='vpn-power'))put(n,p+gStaticTargets.get(gStaticKey('备用订阅',G_BACKUP[0])).ready,'vpn-power');
  for(const n of localPending.findAll(n=>n.getPluginData('rainlink-control-kind')==='vpn-power'))put(n,p+gStaticTargets.get(gStaticKey('未分组',G_LOOSE[0])).ready,'vpn-power');
  if(p==='M/')for(const [s,label]of [[pendingScreen,'备用订阅 / 伦敦 · 泰晤士'],[localPending,'未分组 / 办公 HTTP']])add(uFind(s,'Selected connection group'),uSmall('已选：'+label,'Warning',321));
  for(const [key,s]of Object.entries(reg)){
   if(s.getPluginData('rainlink-overview-online')!==''&&!key.startsWith('待连接 · ')&&!key.startsWith('已连接 · ')&&!key.startsWith('待应用 · ')&&key!=='Pending selection'){
    const online=s.getPluginData('rainlink-overview-online')==='true';for(const n of s.findAll(n=>n.getPluginData('rainlink-control-kind')==='vpn-power'))put(n,p+(online?'Disconnected':p==='D/'?'Dashboard':'Home'),'vpn-power');
   }
  }
 }
 // Navigation created by the new overview templates must also be included.
 for(const l of uLinks)if(l.node&&!l.node.removed&&!staticRoutes.has(l.node.id))put(l.node,l.target);
 for(const [reg,p]of [[registry.desktop,'D/'],[registry.mobile,'M/']])for(const [key,s]of Object.entries(reg)){
  for(const n of s.findAll(n=>'reactions'in n)){
   const canonical=n.getPluginData('rainlink-canonical-name')||n.name;
   if(staticRoutes.has(n.id))continue;
   if(canonical.startsWith('Navigate · ')||canonical.startsWith('Tab · ')){let dest=canonical.split(' · ')[1];if(dest==='Dashboard'||dest==='Home')dest=s.getPluginData('rainlink-overview-online')==='true'?(p==='D/'?'Dashboard':'Home'):'Disconnected';put(n,p+dest);}
   else if(canonical.startsWith('Button · ')){
    const label=canonical.slice(9),dest={'添加节点':'Import profile','返回分组':'Profiles','全部分组':'Profiles','返回节点':'Nodes','代理链':'Chains','编排代理链':'Chain editor','取消':'Profiles','查看':'Connections'}[label];if(dest)put(n,p+dest);
    else if(label===''&&n.parent&&((n.parent.getPluginData('rainlink-canonical-name')||n.parent.name)==='Page header'))put(n,p+(key.startsWith('选择节点 · ')?'Profiles':key.startsWith('选择分组 · Quick switch')?'Disconnected':key.startsWith('选择分组 · ')?'Import profile':'Settings'));
   }
  }
  const hero=uFind(s,'Connection hero heading');if(hero){const badgeNode=hero.children.find(n=>n.type==='INSTANCE');if(badgeNode)badgeNode.visible=false;}
  const caption=uFind(s,'VPN mode caption');if(caption){caption.children[0].visible=false;gStaticText(caption.children[1],s.getPluginData('rainlink-overview-online')==='true'?'点按关闭 VPN':'点按开启 VPN');}
  if(key==='Dashboard light'||key==='Home light')applyLight(s);
 }
 const valid=new Set([...Object.values(registry.desktop),...Object.values(registry.mobile)].map(n=>n.id));
 for(const page of [desktopPage,mobilePage])for(const n of page.findAll(n=>'reactions'in n&&n.reactions.length))await n.setReactionsAsync([]);
 let count=0;const edges=[];
 for(const {node,target,kind}of staticRoutes.values()){
  if(node.removed||node.opacity<.5||!valid.has(rootOf(node).id))continue;
  const [p,...bits]=target.split('/'),reg=p==='D'?registry.desktop:registry.mobile,dest=reg[bits.join('/')];if(!dest)throw new Error('Missing static state '+target);
  if(rootOf(node).parent!==dest.parent)continue;
  if(rootOf(node).id===dest.id)continue;
  await node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:dest.id,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false,resetInteractiveComponents:false}]}]);
  edges.push({from:node.id,to:dest.id,screen:rootOf(node).id,label:node.name,kind});
  if(++count%150===0)figma.ui.postMessage({status:'可用原型连接 '+count+' / '+staticRoutes.size});
 }
 await gStaticModeLibrary();
 await gFixOverviewNavigation();gFixOverviewContent();
 for(const [reg,step,columns]of [[registry.desktop,1540,3],[registry.mobile,473,5]]){let i=0;for(const s of Object.values(reg)){s.x=(i%columns)*step;s.y=150+Math.floor(i/columns)*(columns===3?1020:980);i++;}}
 desktopPage.flowStartingPoints=[{nodeId:registry.desktop.Disconnected.id,name:'桌面端 / 概览开启 VPN'},{nodeId:registry.desktop.Profiles.id,name:'桌面端 / 自动归组与选择'}];
 mobilePage.flowStartingPoints=[{nodeId:registry.mobile.Disconnected.id,name:'移动端 / 概览开启 VPN'},{nodeId:registry.mobile.Profiles.id,name:'移动端 / 自动归组与选择'}];
 const controls=edges.filter(e=>e.kind!=='navigate');
 figma.root.setPluginData('rainlink-overview-controls',JSON.stringify({version:'4.0',prototypeImplementation:'Native state frames and interactive component variants; Starter compatible',workspaceRemoved:true,selectionDoesNotConnect:true,powerOnlyOnOverview:true,proxyModeOnlyOnOverview:true,groupRemembersNode:true,pendingChoiceWhileConnected:true,chainSaveSelectsOnly:true,unsupportedActions:['SET_VARIABLE','CONDITIONAL'],stateEdgeCount:controls.length,stateEdgeSample:true,stateEdges:controls.slice(0,120).map(e=>({from:e.from,to:e.to,screen:e.screen,kind:e.kind})),targetStates:Array.from(gStaticTargets.entries())}));
 gSystem();return edges;
}
async function gWire(){return gStaticWire();}
async function gFastInitialize(){
 await figma.loadAllPagesAsync();await loadChineseFonts();for(const style of ['Regular','Medium','Semi Bold','Bold'])await figma.loadFontAsync({family:'Inter',style});await figma.loadFontAsync({family:'Roboto Mono',style:'Regular'});
 desktopPage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='desktop');mobilePage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='mobile');dsPage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='system');
 const base=JSON.parse(figma.root.getPluginData('rainlink-canonical-styles')||'{}');
 const collections=await figma.variables.getLocalVariableCollectionsAsync();for(const c of collections)if(base.collections&&base.collections[c.id])c.name=base.collections[c.id].name;
 collection=collections.find(c=>c.name==='RainLink / Colors / Dark');lightCollection=collections.find(c=>c.name==='RainLink / Colors / Light');darkMode=collection.defaultModeId;lightMode=darkMode;
 for(const v of await figma.variables.getLocalVariablesAsync()){if(base.variables&&base.variables[v.id])v.name=base.variables[v.id];if(v.variableCollectionId===collection.id)vars[v.name]=v;if(v.variableCollectionId===lightCollection.id)lightVars[v.name]=v;}
 for(const c of dsPage.findAll(n=>n.type==='COMPONENT')){const name=c.getPluginData('rainlink-canonical-name')||c.name;if(name.startsWith('Icon / '))icons[name.slice(7)]=c;else if(name.startsWith('Style=')){const parts=name.split(', ');masters['Button / '+parts[0].slice(6)+' / '+parts[1].slice(5)]=c;}else if(name.startsWith('Tone='))masters['Badge / '+name.slice(5)]=c;else masters[name]=c;}
 for(const [reg,page,prefix]of [[registry.desktop,desktopPage,'desktop/'],[registry.mobile,mobilePage,'mobile/']])for(const s of page.children.filter(n=>n.type==='FRAME'&&n.getPluginData('rainlink').startsWith(prefix)))reg[s.getPluginData('rainlink').slice(prefix.length)]=s;
}
async function gRepairMain(){
 figma.showUI('<body style="padding:24px;background:#10181e;color:#a8bac5;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#86e5c3">RainLink / 原型兼容</h2><p id="s">恢复原生组件…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:520,height:180});
 await gFastInitialize();await simplifyGroupsDocument();figma.ui.postMessage({status:'恢复中文并核验布局…'});const report=gV4Report(await localizeDocument());await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Profiles];figma.viewport.scrollAndZoomIntoView([registry.desktop.Profiles]);figma.notify('概览已统一 · '+report.counts.desktop+' 桌面 / '+report.counts.mobile+' 移动 · '+report.overflow.length+' 排版待检');figma.closePlugin();
}
async function gFinalizeStaticMain(){
 figma.showUI('<body style="padding:24px;background:#10181e;color:#a8bac5;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#86e5c3">RainLink / 核验原型</h2><p id="s">载入已有状态，不重建页面…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:520,height:180});
 await gFastInitialize();
 const cols=await figma.variables.getLocalVariableCollectionsAsync();gInteractionCollection=cols.find(c=>c.name==='RainLink / 交互状态');
 for(const v of await figma.variables.getLocalVariablesAsync())if(v.variableCollectionId===gInteractionCollection.id)gVars[v.name]=v;
 figma.ui.postMessage({status:'修复代理模式组件…'});await gStaticModeLibrary();
 for(const [reg,mobile]of [[registry.desktop,false],[registry.mobile,true]]){
  const rule=masters['Overview / Proxy mode / '+(mobile?'Mobile':'Desktop')],variants=rule.parent.children;
  for(const [key,mode]of [['Mode global',1],['Mode direct',2]]){const c=reg[key]&&reg[key].findOne(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name)==='Overview / Proxy mode / '+(mobile?'Mobile':'Desktop'));if(c)c.swapComponent(variants[mode]);}
  if(!mobile)for(const [key,group,data]of [['Backup connected','备用订阅',G_BACKUP[0]],['Manual connected','未分组',G_LOOSE[0]],['Local connected','未分组',G_LOOSE[1]],['Custom connected','开发环境',G_LOOSE[0]],['Travel connected','旅行订阅',G_MAIN[2]],['Chain connected','主订阅',{name:'开发代理链',ping:'46'}],['Chain reverse connected','主订阅',{name:'反向开发代理链',ping:'39'}]])if(reg[key])gStaticHeader(reg[key],group,data,true);
 }
 for(const [reg,step,columns]of [[registry.desktop,1540,3],[registry.mobile,473,5]]){let i=0;for(const s of Object.values(reg)){s.x=(i%columns)*step;s.y=150+Math.floor(i/columns)*(columns===3?1020:980);i++;}if(reg['Connected switch'])reg['Connected switch'].setPluginData('rainlink-overview-online','true');}
 desktopPage.flowStartingPoints=[{nodeId:registry.desktop.Disconnected.id,name:'桌面端 / 概览开启 VPN'},{nodeId:registry.desktop.Profiles.id,name:'桌面端 / 自动归组与选择'}];mobilePage.flowStartingPoints=[{nodeId:registry.mobile.Disconnected.id,name:'移动端 / 概览开启 VPN'},{nodeId:registry.mobile.Profiles.id,name:'移动端 / 自动归组与选择'}];
 const edges=[];
 for(const page of [desktopPage,mobilePage])for(const screen of page.children.filter(n=>n.type==='FRAME'&&n.getPluginData('rainlink')))for(const node of screen.findAll(n=>'reactions'in n&&n.reactions.length))for(const r of node.reactions)for(const a of r.actions||[])if(a.type==='NODE'&&a.navigation==='NAVIGATE')edges.push({from:node.id,to:a.destinationId,screen:screen.id,label:node.name,kind:node.getPluginData('rainlink-control-kind')||'navigate'});
 const controlEdges=edges.filter(e=>e.kind.startsWith('select-')||e.kind==='vpn-power');
 figma.root.setPluginData('rainlink-overview-controls',JSON.stringify({version:'4.0',prototypeImplementation:'Native state frames and interactive components; Starter compatible',workspaceRemoved:true,selectionDoesNotConnect:true,powerOnlyOnOverview:true,proxyModeOnlyOnOverview:true,groupRemembersNode:true,pendingChoiceWhileConnected:true,chainSaveSelectsOnly:true,unsupportedActions:['SET_VARIABLE','CONDITIONAL'],stateEdgeCount:controlEdges.length,stateEdgeSample:true,stateEdges:controlEdges.slice(0,120).map(e=>({from:e.from,to:e.to,screen:e.screen,kind:e.kind}))}));
 gSystem();
 await gFixOverviewNavigation();gFixOverviewContent();
 const old=JSON.parse(figma.root.getPluginData('rainlink-report')||'{}');delete old.groupEdges;delete old.overviewControls;Object.assign(old,{version:'4.0',desktop:Object.fromEntries(Object.entries(registry.desktop).map(([k,n])=>[k,n.id])),mobile:Object.fromEntries(Object.entries(registry.mobile).map(([k,n])=>[k,n.id])),prototypeNavigationCount:edges.length});figma.root.setPluginData('rainlink-report',JSON.stringify(old));
 figma.ui.postMessage({status:'恢复简体中文与排版核验…'});const report=gV4Report(await localizeDocument());
 // Keep Figma variant names valid after general layer localization.
 for(const set of dsPage.children.filter(n=>n.type==='COMPONENT_SET'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Overview / 代理模式 / ')))for(let i=0;i<set.children.length;i++)set.children[i].name='模式='+G_MODES[i];
 await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Profiles];figma.viewport.scrollAndZoomIntoView([registry.desktop.Profiles]);figma.notify('概览原型完成 · '+report.counts.desktop+' 桌面 / '+report.counts.mobile+' 移动 · '+report.overflow.length+' 排版待检');figma.closePlugin();
}

// Correct inherited sidebar interactions without rebuilding or relocalizing the document.
async function gFixOverviewNavigation(){
 let count=0;
 for(const [reg,mobile]of [[registry.desktop,false],[registry.mobile,true]])for(const [key,s]of Object.entries(reg)){
  const isOverview=!!s.findOne(n=>n.getPluginData('rainlink-control-kind')==='vpn-power');
  const chosen=s.getPluginData('rainlink-chosen-target'),online=s.getPluginData('rainlink-overview-online')==='true';
  let target=isOverview?s:reg[(online?'已连接 · ':'待连接 · ')+chosen];
  if(!target&&chosen.includes('反向开发代理链'))target=reg[(online?'已连接 · ':'待连接 · ')+'主订阅 · 反向开发代理链'];
  if(!target&&chosen.includes('开发代理链'))target=reg[(online?'已连接 · ':'待连接 · ')+'主订阅 · 开发代理链'];
  if(!target&&gStaticNodes[key])target=reg['待连接 · '+gStaticKey(gStaticNodes[key][0],gStaticNodes[key][1][0])];
  if(!target)target=reg[online?(mobile?'Home':'Dashboard'):'Disconnected'];
  const nav=mobile?uFind(s,'Mobile / Bottom navigation'):uFind(s,'Primary navigation');
  const item=nav&&nav.children.find(n=>n.findOne&&n.findOne(t=>t.type==='TEXT'&&[mobile?'首页':'概览',mobile?'Home':'Dashboard'].includes(t.characters)));
  if(!item)continue;
  if(target.id===s.id)await item.setReactionsAsync([]);
  else await item.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:target.id,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},resetInteractiveComponents:false}]}]);count++;
  if(count%20===0){figma.ui.postMessage({status:'修正概览导航 '+count+' / '+(Object.keys(registry.desktop).length+Object.keys(registry.mobile).length)});await new Promise(r=>setTimeout(r,10));}
 }
 return count;
}
function gFixOverviewContent(){
 const rules=registry.desktop.Rules;
 const modes=rules&&rules.findOne(n=>n.type==='FRAME'&&n.children&&n.children.length===3&&n.findAll(t=>t.type==='TEXT'&&['规则模式','全局模式','直连模式','Rule mode','Global mode','Direct mode'].includes(t.characters)).length===3);
 if(modes)modes.remove();
 const heading=rules&&uFind(rules,'Page header');
 const copy=heading&&heading.findAll(n=>n.type==='TEXT');
 if(copy&&copy[1])gStaticText(copy[1],'代理模式在概览设置，这里管理分流规则与优先级。');
 const network=uFind(registry.mobile.Settings,'Network preferences');
 if(network)for(const n of [...network.children])if(n.type==='FRAME'&&n.findOne(t=>t.type==='TEXT'&&['分流模式','路由模式','代理模式','Routing mode','Routing Mode'].includes(t.characters))){const i=network.children.indexOf(n),prior=network.children[i-1];n.remove();if(prior&&prior.height<=1)prior.remove();}
 const data=[...G_MAIN,...G_BACKUP,...G_LOOSE,{name:'备用 HTTP',ping:'16'}];
 for(const s of Object.values(registry.mobile)){
  const card=uFind(s,'Selected connection group'),facts=card&&uFind(card,'Selected group node');if(!facts)continue;
  const node=card.children.find(n=>n.type==='TEXT'),name=node&&node.characters||'';
  let ping=data.find(d=>name===d.name);ping=ping?ping.ping+' ms':name.includes('→')?(name.startsWith('东京')?'39 ms':'46 ms'):'—';
  gStaticText(facts.children[0],'延迟');gStaticText(facts.children[1],ping);facts.children[0].name='延迟';facts.children[1].name=ping;
 }
}
async function gTouchupMain(){
 figma.showUI('<body style="padding:24px;background:#10181e;color:#86e5c3;font:13px Microsoft YaHei,sans-serif"><p id="s">修正概览导航与旧入口…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:400,height:110});
 await figma.loadAllPagesAsync();await loadChineseFonts();for(const style of ['Regular','Medium','Semi Bold','Bold'])await figma.loadFontAsync({family:'Inter',style});await figma.loadFontAsync({family:'Roboto Mono',style:'Regular'});
 desktopPage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='desktop');mobilePage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='mobile');dsPage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='system');
 for(const [reg,page,prefix]of [[registry.desktop,desktopPage,'desktop/'],[registry.mobile,mobilePage,'mobile/']])for(const s of page.children.filter(n=>n.type==='FRAME'&&n.getPluginData('rainlink').startsWith(prefix)))reg[s.getPluginData('rainlink').slice(prefix.length)]=s;
 const count=await gFixOverviewNavigation();gFixOverviewContent();await gFinalizeTokenLabels();
 const report=JSON.parse(figma.root.getPluginData('rainlink-report'));
 report.interactionCorrection={overviewNavigationOverrides:count,activeOverviewHasNoExtraNavigation:true,oldModeEntriesRemoved:true,mobileLatencyLabelCorrected:true};
 figma.root.setPluginData('rainlink-report',JSON.stringify(report));const audit=uFind(dsPage,'Delivery / Native audit');audit.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);audit.visible=false;
 await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Profiles];figma.viewport.scrollAndZoomIntoView([registry.desktop.Profiles]);figma.notify('概览导航与旧模式入口已修正');figma.closePlugin();
}
async function gFinalizeTokenLabels(){
 await figma.loadAllPagesAsync();
 const report=JSON.parse(figma.root.getPluginData('rainlink-report'));
 for(const reg of [report.desktop,report.mobile])if(reg['待应用 · 未分组']){
  const screen=await figma.getNodeByIdAsync(reg['待应用 · 未分组']),power=screen.findOne(n=>n.getPluginData('rainlink-control-kind')==='vpn-power');
  await power.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:reg['待连接 · 未分组 · 办公 HTTP'],navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},resetInteractiveComponents:false}]}]);
 }
 const names={'RainLink / Colors / Dark':'RainLink / 颜色 / 深色','RainLink / Colors / Light':'RainLink / 颜色 / 浅色','RainLink / Spacing & radius':'RainLink / 间距与圆角'};
 const tokens={Background:'背景',Surface:'界面表层',Raised:'浮起表层',Hover:'悬停',Stroke:'边框',Text:'主要文字',Secondary:'次要文字',Muted:'弱化文字',Primary:'主色',PrimarySurface:'主色表层',OnPrimary:'主色上文字',Success:'成功',Warning:'警告',WarningSurface:'警告表层',Error:'错误',ErrorSurface:'错误表层',Info:'信息',InfoSurface:'信息表层',Chart2:'图表辅助色',Transparent:'透明',Space:'间距',Radius:'圆角'};
 for(const c of await figma.variables.getLocalVariableCollectionsAsync()){c.name=names[c.name]||c.name;for(const m of c.modes)if(m.name==='Mode 1')c.renameMode(m.modeId,'默认');}
 for(const v of await figma.variables.getLocalVariablesAsync())v.name=v.name.split('/').map(s=>tokens[s]||s).join('/');
}
async function gTokenLabelsMain(){await gFinalizeTokenLabels();figma.notify('设计变量默认中文已恢复');figma.closePlugin();}
