// RainLink 6: native overlays and subscription metadata; sample data only.
const R6_INFO={
 '主订阅':{used:'42.8',total:'200',remaining:'157.2',ratio:.214,expires:'2026-11-30',status:'正常',tone:'Primary',updated:'10:32',up:'2.6 GB',down:'40.2 GB'},
 '备用订阅':{used:'96.2',total:'100',remaining:'3.8',ratio:.962,expires:'2026-10-17',status:'3 天后到期',tone:'Warning',updated:'10:28',up:'6.4 GB',down:'89.8 GB'},
 '旅行订阅':{used:null,total:null,ratio:null,expires:null,status:'信息未提供',tone:'Muted',updated:'刚刚',up:null,down:null},
 '已过期订阅':{used:'68.4',total:'100',remaining:'31.6',ratio:.684,expires:'2026-10-10',status:'已过期',tone:'Error',updated:'10:32',up:'4.4 GB',down:'64 GB'},
 '流量已耗尽':{used:'100',total:'100',remaining:'0',ratio:1,expires:'2026-11-30',status:'流量已耗尽',tone:'Error',updated:'10:32',up:'8 GB',down:'92 GB'}
};
const r6Changes=new Set(),r6Routes=[],r6OverlayIds=new Set();
function rootOf(n){let root=n;while(root.parent&&root.parent.type!=='PAGE')root=root.parent;return root;}
function r6Name(n,name){n.name=name;n.setPluginData('rainlink-canonical-name',name);return n;}
function r6Copy(n,s){if(!n)return;n.setBoundVariable('characters',null);n.characters=s;n.setPluginData('rainlink-original-text',s);if(/[\u3400-\u9fff]/.test(s))n.fontName={family:zhFamily,style:zhStyles.Regular};}
function r6Text(s,size=14,color='Text',weight='Regular',w=null){return r6Name(uText(s,size,color,weight,w),s);}
function r6Button(s,tone='Secondary',ic=null,w=null){const n=instance('Button / '+tone+' / M'),label=uFind(n,'Label'),slot=uFind(n,'Icon slot');r6Copy(label,s);if(label)label.visible=!!s;if(slot){slot.visible=!!ic;if(ic)slot.swapComponent(icons[ic]);}n.primaryAxisSizingMode=w?'FIXED':'AUTO';n.resize(w||n.width,44);n.primaryAxisAlignItems='CENTER';rad(n,8);return r6Name(n,'按钮 · '+(s||'图标'));}
function r6Badge(s,tone='Neutral'){const n=instance('Badge / '+tone);r6Copy(uFind(n,'Label'),s);const d=uFind(n,'Status dot');if(d)d.visible=false;n.primaryAxisSizingMode='AUTO';return r6Name(n,'状态 · '+s);}
function r6Field(label,value,w){const f=v(label,w,8),inp=instance('Input / Default');inp.resize(w,44);r6Copy(uFind(inp,'Value'),value);const i=uFind(inp,'Icon slot');if(i)i.visible=false;rad(inp,8);add(f,r6Text(label,12,'Secondary'),r6Name(inp,'输入 · '+label));return f;}
function r6Route(n,dest,nav='OVERLAY'){r6Routes.push({n,dest,nav});return n;}
function r6Close(n){r6Routes.push({n,close:true});return n;}
function r6TabBar(w,manual){const f=rad(row('添加方式',w,40,4,4,'Raised'),8);for(const [i,s]of ['订阅','单个节点'].entries()){const tab=center(rad(row('方式 · '+s,(w-12)/2,32,0,0,i===(manual?1:0)?'Surface':null),6));add(tab,r6Text(s,13,i===(manual?1:0)?'Text':'Muted','Medium'));r6Route(tab,i?'Manual node':'Import profile','SWAP');add(f,tab);}return f;}
function r6Progress(w,ratio,tone='Primary'){const f=rad(row('订阅用量进度',w,4),2);fill(f,'Stroke');f.clipsContent=true;add(f,rad(row('订阅用量已用',Math.max(1,w*(ratio||0)),4,0,0,tone),2));return f;}
function r6ProgressMaster(mobile,ratio){const name='订阅进度 / '+(mobile?'移动端':'桌面端')+' / '+String(ratio);let c=masters[name];if(!c){c=component(name,n=>{n.layoutMode='HORIZONTAL';n.resize(mobile?183:590,4);n.primaryAxisSizingMode=n.counterAxisSizingMode='FIXED';fill(n,'Stroke');rad(n,2);n.clipsContent=true;add(n,rad(row('订阅用量已用',Math.max(1,(mobile?183:590)*ratio),4,0,0,ratio>=1?'Error':ratio>.9?'Warning':'Primary'),2));});r6Name(c,name);c.setPluginData('rainlink-subscription-component','6.0');}return c;}
function r6Meta(w,mobile){const f=row('订阅元信息',w,mobile?38:36,mobile?10:24),usage=v('订阅流量',mobile?183:590,6),expiry=v('订阅有效期',mobile?126:462,4);add(usage,r6Name(r6Text('已用 42.8 / 200 GB',12,'Secondary'),'订阅流量值'),r6Progress(mobile?183:590,.214));add(expiry,r6Name(r6Text('2026-11-30 到期',12,'Secondary'),'订阅到期值'),r6Name(r6Text('剩余 157.2 GB',11,'Muted'),'订阅状态值'));add(f,usage,expiry);f.visible=false;return f;}
function r6GroupLayout(n,mobile){
 const head=uFind(n,'Group heading'),bottom=uFind(n,'Group current node'),copy=uFind(n,'Group copy');n.layoutMode='VERTICAL';n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='FIXED';n.resize(mobile?353:1120,n.height);n.paddingLeft=n.paddingRight=16;n.paddingTop=n.paddingBottom=mobile?14:16;n.itemSpacing=mobile?10:12;n.counterAxisAlignItems='MIN';
 if(mobile){if(copy)copy.resize(182,copy.height);r5Fixed(head,319);r5Fixed(bottom,319,44);}else{const top=uFind(n,'订阅条目主行');r5Fixed(top,1086,44);if(top)top.itemSpacing=24;r5Fixed(head,544);r5Fixed(bottom,518,44);if(copy)copy.resize(414,copy.height);const facts=uFind(n,'Group current identity');if(facts)r5Fixed(facts,392);}
 for(const name of ['组名称','组信息']){const t=uFind(n,name);if(t){t.resize(mobile?182:414,t.height);t.textAutoResize='HEIGHT';}}
 const meta=uFind(n,'订阅元信息');if(meta)r5Fixed(meta,mobile?319:1086,mobile?38:36);
}
function r6ExtendGroupMasters(){for(const mobile of [false,true]){const c=masters['Group / '+(mobile?'Mobile':'Desktop')];if(!uFind(c,'订阅元信息')){const head=uFind(c,'Group heading'),bottom=uFind(c,'Group current node');if(!mobile){const top=row('订阅条目主行',1086,44,24);add(top,head,bottom);c.insertChild(0,top);}const more=r6Button('','Ghost','more',mobile?44:36);r6Name(more,'查看订阅信息');more.visible=false;add(head,more);add(c,r6Meta(mobile?319:1086,mobile));}const progress=uFind(c,'订阅用量进度');if(progress?.type!=='INSTANCE'){const p=progress.parent,index=p.children.indexOf(progress);progress.remove();p.insertChild(index,r6Name(r6ProgressMaster(mobile,.214).createInstance(),'订阅用量进度'));}r6GroupLayout(c,mobile);c.setPluginData('rainlink-subscription-component','6.0');}}
function r6GroupInfo(n,mobile,data){
 r6GroupLayout(n,mobile);const meta=uFind(n,'订阅元信息'),more=uFind(n,'查看订阅信息');if(meta)meta.visible=!!data;if(more)more.visible=!!data;if(!data)return;
 const amount=mobile?(data.used?'已用 '+data.used+' / '+data.total+' GB':'流量未提供'):(data.used?'已用 '+data.used+' GB / '+data.total+' GB':'服务未提供流量信息');r6Copy(uFind(n,'订阅流量值'),amount);r6Copy(uFind(n,'订阅到期值'),data.expires?data.expires+' 到期':'有效期未提供');r6Copy(uFind(n,'订阅状态值'),data.status==='正常'?'剩余 '+data.remaining+' GB':data.status==='信息未提供'?'以服务提供方为准':data.status);const status=uFind(n,'订阅状态值');if(status)fill(status,data.tone==='Primary'?'Muted':data.tone);
 const progress=uFind(n,'订阅用量进度');if(progress){progress.visible=data.ratio!==null;if(data.ratio!==null&&progress.type==='INSTANCE')progress.swapComponent(r6ProgressMaster(mobile,data.ratio));}n.setPluginData('rainlink-subscription-metadata',JSON.stringify(data));
}
function r6DialogComponent(mobile,mode='subscription',state='empty'){
 const name='弹窗 / '+(mobile?'移动端':'桌面端')+' / '+mode+' / '+state;let c=masters[name];if(c){c.primaryAxisSizingMode='AUTO';c.counterAxisSizingMode='FIXED';return c;}
 c=component(name,n=>{
  const w=mobile?393:520,pad=mobile?20:24,iw=w-pad*2;n.layoutMode='VERTICAL';n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='FIXED';n.resize(w,1);n.paddingLeft=n.paddingRight=pad;n.paddingTop=mobile?12:24;n.paddingBottom=mobile?34:24;n.itemSpacing=16;fill(n,'Surface');stroke(n);rad(n,mobile?24:16);n.clipsContent=true;
  if(mobile){const cap=center(row('弹窗拖拽柄容器',iw,8));add(cap,rad(row('弹窗拖拽柄',36,4,0,0,'Stroke'),2));add(n,cap);}
  const close=r6Close(r6Button('','Ghost','close',44));r6Name(close,'关闭弹窗');add(n,between(add(row('弹窗标题',iw,44,12),r6Text(mode==='qr'?'扫码导入':'添加',22,'Text','Medium'),close)));
  const manual=mode==='manual';if(mode!=='qr')add(n,r6TabBar(iw,manual));
  if(mode==='subscription'){
   const field=r6Field('订阅链接',state==='empty'?'粘贴订阅链接':'https://example.com/sub/travel',iw);r6Route(uFind(field,'输入 · 订阅链接'),'Import ready','SWAP');add(n,field);
   if(state==='empty')add(n,r6Route(r6Button('粘贴链接','Secondary','copy',iw),'Import ready','SWAP'));
   add(n,between(add(row('订阅自动更新',iw,44,12),add(v('自动更新说明',iw-68,4),r6Text('自动更新',14,'Text','Medium'),r6Text('每 6 小时',12,'Muted')),sw(true))),r6Text('名称随订阅自动识别，导入后自动成组。',12,'Muted','Regular',iw));
   if(state==='loading')add(n,add(row('订阅导入进度',iw,44,10),icon('refresh',18,'Primary'),r6Text('正在获取节点与订阅信息…',13,'Primary')));
   if(state==='error')add(n,r6Text('订阅获取失败，请检查链接后重试。',13,'Error','Regular',iw));
   if(mobile)add(n,r6Route(r6Button('扫码导入','Ghost','qr',iw),'QR import','SWAP'));
   const footer=add(row('弹窗操作',iw,44,12),r6Close(r6Button('取消','Secondary',null,100)),r6Button(state==='loading'?'正在导入…':'导入订阅','Primary',state==='loading'?'refresh':'download',iw-112)),submit=footer.children[1];r6Name(submit,'确认导入订阅');if(['empty','loading'].includes(state))submit.opacity=.4;else r6Route(submit,'Import loading','SWAP');add(n,footer);
  }else if(manual){
   const protocol=instance('Dropdown / Protocol');protocol.resize(iw,44);add(n,add(v('协议选择',iw,8),r6Text('协议',12,'Secondary'),protocol),r6Field('服务器','proxy.backup.example.com',iw),add(row('地址与名称',iw,null,12),r6Field('端口','8080',mobile?102:132),r6Field('名称（可选）','备用 HTTP',iw-(mobile?114:144))),r6Field('用户名（可选）','未设置',iw),r6Field('密码（可选）','未设置',iw),r6Text('添加后进入「未分组」，可再移动到已有分组。',12,'Muted','Regular',iw));add(n,add(row('弹窗操作',iw,44,12),r6Close(r6Button('取消','Secondary',null,100)),r6Route(r6Button('添加节点','Primary','plus',iw-112),'Manual success','NAVIGATE')));
  }else{const scan=center(borderCard('扫码区域',iw,230,20,16,'Raised'));rad(scan,12);add(scan,icon('qr',100,'Primary'),r6Text('将订阅二维码放入框内',14,'Secondary'));add(n,scan,r6Text('识别后自动带入订阅链接。',12,'Muted','Regular',iw),r6Route(r6Button('识别示例二维码','Primary','qr',iw),'Import ready','SWAP'),r6Route(r6Button('返回链接导入','Ghost',null,iw),'Import profile','SWAP'));}
 });c.primaryAxisSizingMode='AUTO';c.counterAxisSizingMode='FIXED';c.setPluginData('rainlink-subscription-component','6.0');r6Name(c,name);return c;
}
function r6InfoComponent(mobile,group){
 const name='弹窗 / '+(mobile?'移动端':'桌面端')+' / 订阅信息 / '+group;let c=masters[name];if(c){c.primaryAxisSizingMode='AUTO';c.counterAxisSizingMode='FIXED';return c;}const d=R6_INFO[group];c=component(name,n=>{
  const w=mobile?393:520,iw=w-(mobile?40:48);n.layoutMode='VERTICAL';n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='FIXED';n.resize(w,1);n.paddingLeft=n.paddingRight=mobile?20:24;n.paddingTop=24;n.paddingBottom=mobile?34:24;n.itemSpacing=18;fill(n,'Surface');stroke(n);rad(n,mobile?24:16);const close=r6Close(r6Button('','Ghost','close',44));r6Name(close,'关闭弹窗');add(n,between(add(row('订阅信息标题',iw,44,12),r6Text(group,22,'Text','Medium'),close)),r6Badge(d.status,d.tone==='Warning'?'Warning':d.tone==='Error'?'Error':'Neutral'));
  const usage=borderCard('订阅套餐流量',iw,null,16,12,'Raised');rad(usage,12);add(usage,r6Text('订阅流量',12,'Secondary'),r6Text(d.used?d.used+' GB / '+d.total+' GB':'服务未提供流量信息',d.used?24:16,'Text','Medium',iw-32));if(d.used)add(usage,r6Progress(iw-32,d.ratio,d.ratio>.9?'Warning':'Primary'),r6Text('剩余 '+d.remaining+' GB',13,'Secondary'),r6Text('下载 '+d.down+'　·　上传 '+d.up,12,'Muted','Regular',iw-32));add(n,usage);
  for(const [label,value,tone]of [['到期时间',d.expires||'未提供',d.tone==='Error'?'Error':'Secondary'],['最近更新',d.updated,'Secondary'],['自动更新','每 6 小时','Secondary']])add(n,between(add(row('订阅信息 · '+label,iw,32),r6Text(label,13,'Muted'),r6Text(value,13,tone))));if(!d.expires||!d.used)add(n,r6Text('流量与有效期以服务提供方返回的信息为准。',12,'Muted','Regular',iw));add(n,r6Close(r6Button('完成','Primary',null,iw)));
 });c.primaryAxisSizingMode='AUTO';c.counterAxisSizingMode='FIXED';c.setPluginData('rainlink-subscription-component','6.0');r6Name(c,name);return c;
}
function r6Overlay(mobile,key,master){
 const reg=mobile?registry.mobile:registry.desktop,page=mobile?mobilePage:desktopPage,w=mobile?393:1440,h=mobile?852:900;let s=reg[key];if(!s){s=frame('',w,h);page.appendChild(s);reg[key]=s;}for(const n of [...s.children])n.remove();r6Name(s,(mobile?'移动端':'桌面端')+' / 弹窗 / '+key);s.setPluginData('rainlink',(mobile?'mobile/':'desktop/')+key);s.setPluginData('rainlink-dialog','6.0');s.layoutMode='VERTICAL';s.primaryAxisSizingMode='FIXED';s.counterAxisSizingMode='FIXED';s.resize(w,h);s.paddingTop=s.paddingBottom=s.paddingLeft=s.paddingRight=0;s.itemSpacing=0;s.primaryAxisAlignItems=mobile?'MAX':'CENTER';s.counterAxisAlignItems='CENTER';fill(s,null);s.clipsContent=true;
 const scrim=figma.createRectangle();scrim.name='关闭弹窗遮罩';scrim.resize(w,h);scrim.fills=[{type:'SOLID',color:{r:0,g:0,b:0},opacity:.62}];add(s,scrim);scrim.layoutPositioning='ABSOLUTE';scrim.x=scrim.y=0;r6Close(scrim);const dialog=master.createInstance();r6Name(dialog,master.name);add(s,dialog);r6OverlayIds.add(s.id);r6Changes.add(s.id);return s;
}
async function r6ApplyRoutes(){let count=0;for(const x of r6Routes){const n=x.n;if(n.removed)continue;const root=rootOf(n),reg=root.parent===mobilePage?registry.mobile:registry.desktop;let actions;if(x.close)actions=[{type:'CLOSE'}];else{const dest=reg[x.dest];if(!dest)throw new Error('Missing overlay route '+x.dest);if(dest.id===root.id){await n.setReactionsAsync([]);continue;}actions=[{type:'NODE',destinationId:dest.id,navigation:x.nav,transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false,resetInteractiveComponents:false}];}try{await n.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions}]);}catch(e){throw new Error('弹窗路由 '+root.name+' / '+n.name+' ('+n.id+') → '+(x.dest||'关闭')+' / '+(x.nav||'CLOSE')+': '+String(e.message||e));}count++;}return count;}
function r6Preview(mobile,key,overlayKey){const reg=mobile?registry.mobile:registry.desktop,page=mobile?mobilePage:desktopPage;let s=reg[key];if(s)s.remove();s=reg.Profiles.clone();page.appendChild(s);reg[key]=s;r6Name(s,(mobile?'移动端':'桌面端')+' / '+key);s.setPluginData('rainlink',(mobile?'mobile/':'desktop/')+key);s.setPluginData('rainlink-dialog-preview','6.0');const over=reg[overlayKey].clone();add(s,over);over.layoutPositioning='ABSOLUTE';over.x=over.y=0;over.setPluginData('rainlink','');over.setPluginData('rainlink-dialog','');r6Changes.add(s.id);return s;}
function r6Gallery(){
 const name='订阅与弹窗 / 组件规范';let gallery=dsPage.children.find(n=>r5Name(n)===name);if(gallery)gallery.remove();gallery=borderCard(name,1500,null,32,24,'Background');dsPage.appendChild(gallery);r6Name(gallery,name);gallery.x=6500;gallery.y=1000;add(gallery,r6Text('添加弹窗与订阅信息 · 6.0',28,'Text','Medium'),r6Text('添加无需离开当前列表。订阅自动命名、自动成组；服务未提供的数据明确标注。',14,'Secondary','Regular',1436));
 for(const [label,group]of [['正常','主订阅'],['即将到期 / 流量不足','备用订阅'],['未返回信息','旅行订阅'],['已过期','已过期订阅'],['流量已耗尽','流量已耗尽']]){const n=masters['Group / Desktop'].createInstance();r6Copy(uFind(n,'组名称'),group);r6Name(n,'订阅示例 · '+group);r6GroupInfo(n,false,R6_INFO[group]);add(gallery,r6Text(label,14,'Secondary'),n);}
 add(gallery,r6Text('交互约定',20,'Text','Medium'),r6Text('打开弹窗 → 选择订阅或单个节点 → 导入 / 添加 → 自动归组。关闭、取消或点遮罩均返回原页面。',14,'Secondary','Regular',1436),r6Text('订阅名称由服务返回；缺失时使用域名或“订阅 1”，更新时跟随服务名称。手动节点不展示订阅额度。',13,'Muted','Regular',1436));const strip=row('弹窗组件示例',1436,null,24);add(strip,masters['弹窗 / 桌面端 / subscription / ready'].createInstance(),masters['弹窗 / 移动端 / subscription / empty'].createInstance());add(gallery,strip);return gallery;
}
async function r6Update(){
 await r5Initialize();figma.skipInvisibleInstanceChildren=false;Object.assign(C,R5_COLORS);
 const cols=await figma.variables.getLocalVariableCollectionsAsync();collection=cols.find(c=>/Colors \/ Dark|颜色 \/ 深色/.test(c.name));lightCollection=cols.find(c=>/Colors \/ Light|颜色 \/ 浅色/.test(c.name));darkMode=collection.defaultModeId;
 for(const variable of await figma.variables.getLocalVariablesAsync('COLOR')){const key=Object.keys(R5_TOKEN_NAMES).find(k=>variable.name===k||variable.name===R5_TOKEN_NAMES[k]);if(key)(variable.variableCollectionId===lightCollection.id?lightVars:vars)[key]=variable;}
 figma.ui.postMessage({status:'更新共享分组组件与订阅元信息…'});r6ExtendGroupMasters();
 for(const [reg,mobile]of [[registry.desktop,false],[registry.mobile,true]])for(const s of Object.values(reg)){
  for(const n of r5Walk(s).filter(n=>n.type==='INSTANCE'&&r5Name(n).startsWith('Group · '))){const group=r5Name(n).slice(8);r6GroupInfo(n,mobile,R6_INFO[group]);const more=uFind(n,'查看订阅信息');if(more&&more.visible)r6Route(more,'Subscription info · '+group);r6Changes.add(s.id);}
 }
 figma.ui.postMessage({status:'创建桌面弹窗与移动端底部弹窗…'});
 for(const mobile of [false,true]){
  for(const [key,mode,state]of [['Import profile','subscription','empty'],['Import ready','subscription','ready'],['Import loading','subscription','loading'],['Import error','subscription','error'],['Manual node','manual','ready'],...(mobile?[['QR import','qr','ready']]:[])])r6Overlay(mobile,key,r6DialogComponent(mobile,mode,state));
  for(const group of ['主订阅','备用订阅','旅行订阅'])r6Overlay(mobile,'Subscription info · '+group,r6InfoComponent(mobile,group));
 }
 // Wire canonical controls on each dialog instance, including maintenance reruns.
 for(const [reg,mobile]of [[registry.desktop,false],[registry.mobile,true]])for(const [key,s]of Object.entries(reg).filter(([k,n])=>r6OverlayIds.has(n.id)))for(const n of s.findAll(n=>'reactions'in n)){
  const label=r5Name(n);
  if(['关闭弹窗','按钮 · 取消','按钮 · 完成'].includes(label))r6Close(n);
  else if(label==='方式 · 订阅')r6Route(n,'Import profile','SWAP');
  else if(label==='方式 · 单个节点')r6Route(n,'Manual node','SWAP');
  else if(['输入 · 订阅链接','按钮 · 粘贴链接','按钮 · 识别示例二维码'].includes(label))r6Route(n,'Import ready','SWAP');
  else if(label==='按钮 · 扫码导入')r6Route(n,'QR import','SWAP');
  else if(label==='按钮 · 返回链接导入')r6Route(n,'Import profile','SWAP');
  else if(label==='确认导入订阅'&&['Import ready','Import error'].includes(key))r6Route(n,'Import loading','SWAP');
  else if(label==='按钮 · 添加节点'&&key==='Manual node')r6Route(n,'Manual success','NAVIGATE');
 }
 for(let i=r6Routes.length-1;i>=0;i--)if(rootOf(r6Routes[i].n).parent===dsPage)r6Routes.splice(i,1);
 let changedEntrances=0;const overlayKeyById=Object.fromEntries([...Object.entries(registry.desktop),...Object.entries(registry.mobile)].filter(([k,n])=>r6OverlayIds.has(n.id)).map(([k,n])=>[n.id,k]));
 for(const [reg,mobile]of [[registry.desktop,false],[registry.mobile,true]])for(const s of Object.values(reg).filter(n=>!r6OverlayIds.has(n.id))){
  for(const n of s.findAll(n=>'reactions'in n&&n.reactions.length)){
   const reactions=JSON.parse(JSON.stringify(n.reactions));let changed=false;for(const r of reactions)for(const a of r.actions||[])if(a.type==='NODE'&&r6OverlayIds.has(a.destinationId)&&['NAVIGATE','OVERLAY'].includes(a.navigation)){a.destinationId=reg[overlayKeyById[a.destinationId]].id;a.navigation='OVERLAY';changed=true;}
   if(changed){try{await n.setReactionsAsync(reactions);}catch(e){throw new Error('入口 '+s.name+' / '+n.name+' ('+n.id+'): '+String(e.message||e));}changedEntrances++;r6Changes.add(s.id);const label=uFind(n,'Label');if(label?.characters==='添加节点'){r6Copy(label,'添加');r6Name(n,'Button · 添加');}}
  }
 }
 figma.ui.postMessage({status:'更新概览公网 IP、国旗与检测状态…'});const egress=await r6EgressUpdate();
 figma.ui.postMessage({status:'接入原生打开、切换与关闭弹窗交互…'});const routeCount=await r6ApplyRoutes();
 for(const [reg,mobile]of [[registry.desktop,false],[registry.mobile,true]]){
  const s=reg['Import loading'];await s.setReactionsAsync([{trigger:{type:'AFTER_TIMEOUT',timeout:1.0},actions:[{type:'NODE',destinationId:(reg['Source success']||reg['Import success']).id,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false,resetInteractiveComponents:false}]}]);
  for(const [key,overlay]of [['添加订阅预览','Import ready'],['添加单个节点预览','Manual node'],['订阅详情预览','Subscription info · 主订阅']])r6Preview(mobile,key,overlay);
 }
 const gallery=r6Gallery();let y=1000;for(const c of dsPage.children.filter(n=>n.type==='COMPONENT'&&n.getPluginData('rainlink-subscription-component')==='6.0'&&!r5Name(n).startsWith('Group / '))){c.x=8160;c.y=y;y+=c.height+48;}
 desktopPage.flowStartingPoints=[{nodeId:registry.desktop.Disconnected.id,name:'桌面端 / 概览开启 VPN'},{nodeId:registry.desktop.Profiles.id,name:'桌面端 / 自动归组与选择'}];mobilePage.flowStartingPoints=[{nodeId:registry.mobile.Disconnected.id,name:'移动端 / 概览开启 VPN'},{nodeId:registry.mobile.Profiles.id,name:'移动端 / 自动归组与选择'}];
 for(const [reg,step,columns]of [[registry.desktop,1540,3],[registry.mobile,473,5]]){let i=0;for(const s of Object.values(reg)){s.x=(i%columns)*step;s.y=150+Math.floor(i/columns)*(columns===3?1020:980);i++;}}
 figma.ui.postMessage({status:'核验弹窗、元信息与 Auto Layout…'});const report=await r5AuditDocument();report.version='6.0';report.desktop=Object.fromEntries(Object.entries(registry.desktop).map(([k,n])=>[k,n.id]));report.mobile=Object.fromEntries(Object.entries(registry.mobile).map(([k,n])=>[k,n.id]));report.counts={...report.counts,desktop:Object.keys(registry.desktop).length,mobile:Object.keys(registry.mobile).length,components:dsPage.findAll(n=>n.type==='COMPONENT').length};
 report.subscriptionDialogs={version:'6.0',addIsOverlay:true,subscriptionNameFieldRemoved:true,nameSource:'订阅返回名称；缺失时域名或自动编号',nameFollowsSubscription:true,metadataFields:['已用流量','总额度','剩余流量','上传','下载','到期时间','更新时间'],missingDataExplicit:true,statuses:['正常','即将到期','流量不足','已过期','流量已耗尽','信息未提供'],manualNodesNoSubscriptionQuota:true,changedEntrances,routeCount,changedScreenIds:[...r6Changes],overlayIds:[...r6OverlayIds],systemGallery:gallery.id};report.egress=egress;
 delete report.nativeBackup;delete report.screenshotVerification;report.livePrototypeVerification={status:'pending refreshed scan'};figma.root.setPluginData('rainlink-report',JSON.stringify(report));figma.root.setPluginData('rainlink-subscription-version','6.0');const audit=uFind(dsPage,'Delivery / Native audit');audit.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);audit.visible=false;return report;
}
async function r6SubscriptionMain(){
 figma.showUI('<body style="padding:24px;background:#151617;color:#c0c2c8;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#8adcbf">RainLink / 添加与订阅信息</h2><p id="s">载入已有设计，不重建原型…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:520,height:170});
 await r5Yield();const report=await r6Update();await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Profiles,registry.desktop['添加订阅预览']];figma.viewport.scrollAndZoomIntoView(figma.currentPage.selection);figma.notify('弹窗与订阅信息已更新 · '+report.overflow.length+' 处排版待检');figma.closePlugin();
}
