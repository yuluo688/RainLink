// RainLink 7.5 / review repair revision 1. UI examples only; keep 23 product frames.
const R77_REV='1';
let r77Section,r77X=24,r77Y=96,r77H=0;
const r77Edges=[],r77Libs={};
const R77_PROTOCOLS=['Shadowsocks','VLESS','VMess','Trojan','Hysteria','TUIC','SOCKS5','HTTP'];
async function r77Initialize(){
  figma.skipInvisibleInstanceChildren=true;for(const page of figma.root.children){figma.ui.postMessage({status:'载入页签 '+page.name+'…'});await page.loadAsync();}const report=JSON.parse(figma.root.getPluginData('rainlink-report'));zhFamily=report.chineseFont.family;zhStyles=report.chineseFont.styles;
  await Promise.all([...new Set(Object.values(zhStyles))].map(async style=>{figma.ui.postMessage({status:'载入中文字体 '+style+'…'});await figma.loadFontAsync({family:zhFamily,style});}));
  // Optional remote Latin weights can hang while offline. New and edited copy uses
  // the already-loaded Chinese family, which also contains Latin characters.
  uText=function(s,size=14,color='Text',weight='Regular',w=null){const n=figma.createText();n.fontName={family:zhFamily,style:zhStyles[weight]||zhStyles.Regular};n.fontSize=size;n.characters=s;n.lineHeight={unit:'PIXELS',value:Math.ceil(size*1.45)};fill(n,color);if(w){n.resize(w,Math.ceil(size*1.45));n.textAutoResize='HEIGHT';}else n.textAutoResize='WIDTH_AND_HEIGHT';return n;};
  r6Copy=function(n,s){if(!n)return;n.setBoundVariable('characters',null);n.fontName={family:zhFamily,style:zhStyles.Regular};n.characters=s;n.setPluginData('rainlink-original-text',s);};
  desktopPage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='desktop');mobilePage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='mobile');dsPage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='system');
  for(const [reg,page,prefix]of [[registry.desktop,desktopPage,'desktop/'],[registry.mobile,mobilePage,'mobile/']])for(const s of page.findAll(n=>n.type==='FRAME'&&n.getPluginData('rainlink').startsWith(prefix)))reg[s.getPluginData('rainlink').slice(prefix.length)]=s;
  for(const c of dsPage.findAll(n=>n.type==='COMPONENT')){const name=r5Name(c);if(name.startsWith('Icon / '))icons[name.slice(7)]=c;else if(name.startsWith('Style=')){const p=name.split(', ');masters['Button / '+p[0].slice(6)+' / '+p[1].slice(5)]=c;}else if(name.startsWith('Tone='))masters['Badge / '+name.slice(5)]=c;else masters[name]=c;}
}
function r77Mark(n){n.setPluginData('rainlink-review-fix',R77_REV);return n;}
function r77Place(n){
  if(r77X+n.width>6000&&r77X>24){r77Y+=r77H+64;r77X=24;r77H=0;}
  r77Section.appendChild(n);n.x=r77X;n.y=r77Y;r77X+=n.width+48;r77H=Math.max(r77H,n.height);return n;
}
function r77Body(name,w){return r77Mark(r7Body(name,w));}
function r77Set(name,states,mobile,build,cols=2){
  const edgeAt=r77Edges.length,variants={};for(const key of states){const c=build(key);r6Name(c,'状态='+key);variants[key]=r77Mark(c);}
  const set=r7VariantSet('修订 / '+(mobile?'移动端':'桌面端')+' / '+name,Object.values(variants),cols);r77Place(set);r77Mark(set);
  const lib={set,variants,initial:variants[states[0]]};for(const edge of r77Edges.slice(edgeAt))if(typeof edge.to==='string'&&variants[edge.to])edge.to=variants[edge.to];r77Libs[(mobile?'M/':'D/')+name]=lib;return lib;
}
function r77Go(n,to,nav='CHANGE_TO'){if(n&&to)r77Edges.push({n,to,nav});return n;}
function r77Close(n){r77Edges.push({n,close:true});return n;}
function r77Button(label,to=null,tone='Secondary',ic=null,w=null,nav='CHANGE_TO'){
  return r77Go(r6Button(label,tone,ic,w),to,nav);
}
function r77Text(s,size=14,tone='Text',w=null){return r6Text(s,size,tone,'Regular',w);}
function r77Note(title,copy,w,tone='Info'){
  const n=borderCard('反馈 · '+title,w,null,12,4,tone==='Success'?'PrimarySurface':tone+'Surface');rad(n,10);stroke(n,tone);
  add(n,r6Text(title,13,tone,'Medium',w-26),copy?r77Text(copy,12,'Secondary',w-26):null);return n;
}
function r77Back(title,w,to){
  const n=row('局部返回导航',w,44,4),back=r76BackIcon(r6Button('','Ghost',null,44),'返回上一级箭头');
  add(n,r77Go(back,to),r6Text(title,20,'Text','Medium',w-48));return n;
}
function r77Tabs(labels,active,w,mobile,prefix='切换'){
  const n=rad(row(prefix,w,44,4,0,'Raised'),8),each=(w-(labels.length-1)*4)/labels.length;
  for(const name of labels){const t=center(rad(row(prefix+' · '+name,each,44,0,0,active===name?'PrimarySurface':null),8));add(t,r77Text(name,13,active===name?'Primary':'Secondary'));add(n,t);}return n;
}
function r77Field(label,value,w){const n=r6Field(label,value,w);n.itemSpacing=4;const input=uFind(n,'输入 · '+label);input.paddingLeft=input.paddingRight=12;const t=uFind(input,'Value');if(t){t.layoutSizingHorizontal='FILL';t.fontSize=13;}return n;}
function r77Install(screen,c,name,keepHeader=true){
  const b=uFind(screen,'Content');for(const n of [...b.children])if(!keepHeader||r5Name(n)!=='Page header')n.remove();
  const instance=r7Instance(c,name);add(b,instance);return instance;
}
function r77Dialog(mobile,title,backTo=null){
  const w=mobile?393:520,p=mobile?20:24,iw=w-p*2,c=r77Body('弹窗',w);
  fill(c,'Surface');stroke(c);rad(c,mobile?24:16);c.paddingLeft=c.paddingRight=p;c.paddingTop=mobile?12:24;c.paddingBottom=mobile?34:24;c.itemSpacing=12;c.clipsContent=true;
  if(mobile){const cap=center(row('弹窗拖拽柄容器',iw,8));add(cap,rad(row('弹窗拖拽柄',36,4,0,0,'Stroke'),2));add(c,cap);}
  const head=row('弹窗标题',iw,44,4);if(backTo)add(head,r77Go(r76BackIcon(r6Button('','Ghost',null,44),'返回上一级箭头'),backTo));
  const text=r6Text(title,22,'Text','Medium',iw-(backTo?96:48));add(head,text);text.layoutSizingHorizontal='FILL';add(head,r77Close(r6Name(r6Button('','Ghost','close',44),'关闭弹窗')));add(c,head);
  return {c,w,iw};
}
function r77ClampScroll(n,maxHeight){n.primaryAxisSizingMode='FIXED';n.resize(n.width,Math.min(n.height,maxHeight));n.clipsContent=true;n.overflowDirection='VERTICAL';n.setPluginData('rainlink-keyboard-scroll','resize viewport with keyboard; fixed footer above keyboard');}
async function r77Add(mobile){
  const names=['订阅','订阅已填','地址错误','获取失败','导入中','重试中','订阅成功','节点成功','协议选择','校验错误','扫码','相机拒绝',...R77_PROTOCOLS.flatMap(p=>[p,p+' · 更多'])];
  const lib=r77Set('添加',names,mobile,key=>{
    const manual=R77_PROTOCOLS.some(p=>key.startsWith(p))||['协议选择','校验错误','节点成功'].includes(key),picker=key==='协议选择',qr=['扫码','相机拒绝'].includes(key);
    const {c,w,iw}=r77Dialog(mobile,picker?'选择协议':qr?'扫码导入':key.endsWith('成功')?'添加完成':'添加');
    if(key.endsWith('成功')){
      add(c,r6Badge('已完成','Success'),r6Text(key==='节点成功'?'节点已加入未分组':'订阅已自动成组',22,'Text','Medium',iw),r77Text(key==='节点成功'?'新节点仅被保存。选择节点后，在概览开启 VPN。':'已导入「旅行订阅」及 4 个节点，名称由订阅自动识别。',14,'Secondary',iw),r77Close(r6Button('完成','Primary',null,iw)));return c;
    }
    if(picker){
      const back=r77Back('单个节点',iw,'HTTP');add(c,back,r77Text('选择协议后填写连接参数',12,'Muted',iw));
      for(let i=0;i<R77_PROTOCOLS.length;i+=2){const line=row('协议选项',iw,44,8);for(const p of R77_PROTOCOLS.slice(i,i+2))add(line,r77Button(p,p,'Secondary',null,(iw-8)/2));add(c,line);}return c;
    }
    if(qr){
      if(key==='扫码'){
        const scan=center(borderCard('二维码识别区域',iw,220,16,12,'Raised'));add(scan,icon('qr',96,'Primary'),r77Text('扫描订阅或节点二维码',13,'Secondary'));add(c,scan,r77Button('识别示例二维码','订阅已填','Primary','qr',iw),r77Button('相机权限不可用','相机拒绝','Ghost',null,iw));
      }else add(c,r77Note('无法使用相机','请在系统设置中允许相机访问，或粘贴订阅链接。',iw,'Warning'),r77Button('使用链接导入','订阅','Primary',null,iw),r77Button('重新授权','扫码','Secondary',null,iw));
      c.insertChild(mobile?2:1,r77Back('链接导入',iw,'订阅'));return c;
    }
    const tabs=r77Tabs(['订阅','单个节点'],manual?'单个节点':'订阅',iw,mobile,'添加方式');add(c,tabs);r77Go(tabs.children[0],'订阅');r77Go(tabs.children[1],'HTTP');
    const scroll=v('表单滚动区',iw,12);add(c,scroll);
    if(!manual){
      const empty=key==='订阅',bad=key==='地址错误',loading=['导入中','重试中'].includes(key);
      const field=r77Field('订阅链接',empty?'粘贴 https:// 订阅地址':bad?'example.com/sub':'https://example.com/sub/travel',iw);add(scroll,field);r77Go(uFind(field,'输入 · 订阅链接'),empty?'订阅已填':bad?'订阅已填':'地址错误');
      if(empty)add(scroll,r77Button('粘贴链接','订阅已填','Secondary','copy',iw));
      const update=between(row('自动更新',iw,44,8));add(update,add(v('自动更新文案',iw-56,2),r77Text('自动更新',14),r77Text('每 6 小时',12,'Muted')),sw(true));add(scroll,update,r77Text('名称自动识别 · 导入后自动创建一个分组',12,'Muted',iw));
      if(bad)add(scroll,r77Note('链接格式不正确','请填写以 https:// 或 http:// 开头的完整地址。',iw,'Error'));
      if(key==='获取失败')add(scroll,r77Note('订阅获取失败','请求超时，已保留链接。检查网络后重试。',iw,'Error'));
      if(loading)add(scroll,r77Note('正在获取订阅','正在读取节点、流量与到期信息…',iw));
      if(mobile)add(scroll,r77Button('扫码导入','扫码','Ghost','qr',iw));
      const actions=row('弹窗操作',iw,44,12);add(actions,r77Close(r6Button('取消','Secondary',null,96)),r77Button(loading?'正在导入…':key==='获取失败'?'重试':'导入订阅',loading?null:empty?'地址错误':key==='获取失败'?'重试中':'导入中','Primary',loading?'refresh':'download',iw-108));add(c,actions);
    }else{
      const p=R77_PROTOCOLS.find(p=>key.startsWith(p))||'HTTP',more=key.endsWith('更多');
      const selector=between(rad(row('协议选择器',iw,44,8,12,'Raised'),8));stroke(selector);add(selector,r77Text(p,14),icon('down',16,'Muted'));add(scroll,r77Text('协议',12,'Secondary'),r77Go(selector,'协议选择'));
      add(scroll,r77Field('服务器',key==='校验错误'?'':'proxy.example.com',iw));
      const pair=row('端口与名称',iw,null,12);add(pair,r77Field('端口',p==='HTTP'?'8080':p==='SOCKS5'?'1080':'443',96),r77Field('名称（可选）','自动使用服务器地址',iw-108));add(scroll,pair);
      if(p==='Shadowsocks'){
        add(scroll,r77Field('加密方式','chacha20-ietf-poly1305',iw),r77Field('密码','••••••••••••',iw));
      }else if(['VLESS','VMess','TUIC'].includes(p)){
        add(scroll,r77Field('用户标识 UUID','a4f3c201-7a9e-4ac1-8a2e-1951b42e3856',iw));
        if(p==='TUIC')add(scroll,r77Field('密码','••••••••••••',iw));
      }else if(['Trojan','Hysteria'].includes(p))add(scroll,r77Field(p==='Hysteria'?'认证密码 · Hysteria 2':'密码','••••••••••••',iw));
      const toggle=r77Button(more?'收起更多参数':'更多参数',more?p:p+' · 更多','Ghost','down',iw);add(scroll,toggle);
      if(more){
        if(['HTTP','SOCKS5'].includes(p))add(scroll,r77Field('用户名（可选）','未设置',iw),r77Field('密码（可选）','未设置',iw));
        else{add(scroll,r77Field('TLS 服务器名称（SNI）','proxy.example.com',iw));if(['VLESS','VMess'].includes(p))add(scroll,r77Field('传输方式','TCP · TLS',iw));if(p==='Shadowsocks')add(scroll,r77Field('插件（可选）','无',iw));if(['TUIC','Hysteria'].includes(p))add(scroll,r77Field('ALPN','h3',iw));}
      }
      if(key==='校验错误')add(scroll,r77Note('请填写服务器','服务器地址不能为空，端口范围为 1–65535。',iw,'Error'));
      add(scroll,r77Text('保存至未分组，可从节点菜单移动到已有分组。',12,'Muted',iw));
      const actions=row('弹窗操作',iw,44,12);add(actions,r77Close(r6Button('取消','Secondary',null,96)),r77Button('添加节点','节点成功','Primary','plus',iw-108));add(c,actions);
      r77Go(uFind(scroll,'输入 · 服务器'),key==='校验错误'?'HTTP':'校验错误');
    }
    r77ClampScroll(scroll,mobile?388:460);return c;
  },3);
  for(const key of ['导入中','重试中'])await lib.variants[key].setReactionsAsync(r7Timer(lib.variants[key==='导入中'?'获取失败':'订阅成功'].id));
  const reg=mobile?registry.mobile:registry.desktop;r6Overlay(mobile,'Import profile',lib.initial);r77Close(uFind(reg['Import profile'],'关闭弹窗遮罩'));
  return lib;
}
function r77SubscriptionPanel(mobile,group,mode,backTo){
  const w=mobile?353:520,p=16,iw=w-p*2,d=R6_INFO[group],c=borderCard('当前订阅 · '+group,w,null,p,12,'Surface');rad(c,16);
  const title=row('订阅详情标题',iw,44,4),back=r76BackIcon(r6Button('','Ghost',null,44),'返回分组箭头');add(title,backTo?r77Go(back,backTo):r77Close(back),r6Text(group,20,'Text','Medium',iw-48));add(c,title);
  if(mode==='删除'){
    add(c,r77Note('删除此订阅？','将删除订阅节点和订阅信息。手动移入的节点会退回未分组。当前连接在下一次切换前保持。',iw,'Warning'),r77Button('确认删除','已删除|'+group,'Primary',null,iw),r77Button('取消','详情|'+group,'Secondary',null,iw));return c;
  }
  if(mode==='编辑'){
    add(c,r77Field('订阅链接','https://example.com/sub/'+(group==='主订阅'?'main':group==='备用订阅'?'backup':'travel'),iw),r77Text('名称从订阅自动识别，无需填写分组名称。',12,'Muted',iw),r77Button('保存链接','已更新|'+group,'Primary',null,iw));return c;
  }
  add(c,between(add(row('套餐状态',iw,24),r77Text('套餐流量',12,'Muted'),r6Badge(d.status,d.tone==='Primary'?'Success':d.tone==='Warning'?'Warning':'Neutral'))),r6Text(d.used?d.used+' / '+d.total+' GB':'服务未提供流量信息',d.used?26:17,'Text','Medium',iw));
  if(d.used)add(c,r6Progress(iw,d.ratio,d.ratio>.9?'Warning':'Primary'),r77Text('剩余 '+d.remaining+' GB · ↓ '+d.down+'  ↑ '+d.up,12,'Secondary',iw));
  for(const [label,value]of [['到期时间',d.expires||'未提供'],['最近更新',mode==='已更新'?'刚刚':d.updated],['自动更新','每 6 小时']])add(c,between(add(row('订阅详情 · '+label,iw,28),r77Text(label,13,'Muted'),r77Text(value,13,'Secondary'))));
  if(mode==='更新中')add(c,r77Note('正在更新','保留已有节点，正在获取最新订阅…',iw));
  if(mode==='失败')add(c,r77Note('更新失败','请求超时，已保留原有节点和套餐信息。',iw,'Error'));
  if(mode==='已更新')add(c,r77Note('更新完成','节点与套餐信息已刷新，手动加入的节点已保留。',iw,'Success'));
  if(!d.used)add(c,r77Text('流量与有效期以服务返回信息为准。',12,'Muted',iw));
  const actions=row('当前订阅管理',iw,44,8);for(const [label,to]of [[mode==='失败'?'重试':'更新',(mode==='失败'?'已更新':'更新中')+'|'+group],['编辑链接','编辑|'+group],['删除','删除|'+group]])add(actions,r77Button(label,to,'Secondary',null,(iw-16)/3));add(c,actions);return c;
}
async function r77Groups(mobile){
  const reg=mobile?registry.mobile:registry.desktop,w=mobile?353:1120,names=['主订阅','备用订阅','未分组','旅行订阅'];
  const old=dsPage.findOne(n=>n.type==='COMPONENT_SET'&&r5Name(n)==='交互 / '+(mobile?'移动端':'桌面端')+' / 分组选择');
  const states=[...names.map(n=>'选中|'+n),'空',...['主订阅','备用订阅','旅行订阅'].flatMap(n=>['详情','编辑','删除','更新中','失败','已更新','已删除'].map(m=>m+'|'+n))];
  const lib=r77Set('分组管理',states,mobile,key=>{
    const [mode,group]=key.split('|'),c=r77Body('分组管理',w);c.itemSpacing=8;
    if(mode==='空'){add(c,r77Note('还没有分组或节点','导入订阅会自动成组，单个节点会加入未分组。',w),r77Button('添加订阅或节点',reg['Import profile'],'Primary','plus',mobile?w:240,'OVERLAY'));return c;}
    const source=old.children.find(n=>n.name==='选中='+(mode==='选中'?group:'主订阅'))||old.children[0],list=source.createInstance();r6Name(list,'紧凑分组列表');add(c,list);
    for(const card of list.children){const n=r5Name(card).replace('Group · ','');if(!names.includes(n))continue;
      r77Go(card,'选中|'+n);const more=uFind(card,'查看订阅信息');if(more&&more.visible)r77Go(more,'详情|'+n);
      const entry=card.findOne(t=>t.type==='INSTANCE'&&t.findAll(n=>n.type==='TEXT').some(t=>t.characters==='节点'));if(entry)r77Go(entry,reg.Nodes,'NAVIGATE');
      for(const a of card.findAll(n=>n.type==='INSTANCE'&&r5Name(n).includes('chevron')))r77Go(a.parent===card?a:a.parent,reg.Nodes,'NAVIGATE');
      if(mode==='已删除'&&n===group)card.visible=false;
    }
    if(mode==='已删除')add(c,r77Note('已删除'+group,'手动加入的节点已退回未分组。',w,'Success'));
    add(c,r77Text('订阅自动成组 · 单个节点默认进入未分组',12,'Muted',w));
    if(!['选中','已删除'].includes(mode)){
      c.resize(w,mobile?592:600);c.primaryAxisSizingMode='FIXED';
      const mask=r77Go(frame('详情遮罩',w,c.height,'VERTICAL','#000000'),'选中|主订阅');mask.fills=[{type:'SOLID',color:{r:0,g:0,b:0},opacity:.58}];add(c,mask);mask.layoutPositioning='ABSOLUTE';mask.x=mask.y=0;
      const panel=r77SubscriptionPanel(mobile,group,mode,'选中|主订阅');add(c,panel);panel.layoutPositioning='ABSOLUTE';panel.x=mobile?0:(w-panel.width)/2;panel.y=mobile?Math.max(0,c.height-panel.height):16;
    }
    return c;
  },3);
  for(const group of ['主订阅','备用订阅','旅行订阅'])await lib.variants['更新中|'+group].setReactionsAsync(r7Timer(lib.variants['失败|'+group].id));
  r77Install(reg.Profiles,lib.initial,'分组管理工作区');
  if(mobile)r77Install(reg['Quick switch'],lib.initial,'分组管理工作区');
  // The existing standalone host remains the entry for the principal subscription only.
  const details=r77Set('订阅详情',['详情','编辑','删除','更新中','失败','已更新','已删除'].map(m=>m+'|主订阅'),mobile,key=>{
    const mode=key.split('|')[0],body=r77Body('当前订阅',mobile?353:520);
    if(mode==='已删除')add(body,r77Note('订阅已删除','手动加入的节点已退回未分组。',body.width,'Success'),r77Close(r6Button('完成','Primary',null,body.width)));
    else add(body,r77SubscriptionPanel(mobile,'主订阅',mode,null));return body;
  },2);
  await details.variants['更新中|主订阅'].setReactionsAsync(r7Timer(details.variants['失败|主订阅'].id));
  r6Overlay(mobile,'Subscription info · 主订阅',details.initial);r77Close(uFind(reg['Subscription info · 主订阅'],'关闭弹窗遮罩'));
  return lib;
}
function r77Hop(data,index,total,w,mobile,state){
  const c=borderCard('跳点 '+(index+1),w,null,mobile?12:16,8,'Surface');rad(c,12);const iw=w-(mobile?26:34);
  const line=between(row('跳点标题',iw,28,8));add(line,r6Text(index===total-1?'出口 · 第 '+(index+1)+' 跳':'入口 · 第 '+(index+1)+' 跳',12,'Muted','Medium'),r6Badge(data.p));add(c,line);
  const identity=between(row('跳点节点',iw,28));add(identity,r6Text(data.name,15,'Text','Medium',iw-70),r77Text(data.ping+' ms',13,'Primary'));add(c,identity);
  const tools=row('跳点操作',iw,44,4),change=r77Button('更换','更换|'+index,'Secondary',null,mobile?88:120);add(tools,change);
  for(const [label,to,ic]of [['上移',state==='倒序'?'默认':'倒序','upload'],['下移',state==='倒序'?'默认':'倒序','download'],['移除','单跳','close']]){
    const b=r77Button(mobile?'':label,to,'Ghost',ic,mobile?44:80);r6Name(b,'跳点'+index+' · '+label);
    if((label==='上移'&&index===0)||(label==='下移'&&index===total-1)){b.opacity=.3;b.setPluginData('rainlink-disabled','true');for(let i=r77Edges.length-1;i>=0;i--)if(r77Edges[i].n===b)r77Edges.splice(i,1);}
    add(tools,b);
  }add(c,tools);return c;
}
async function r77Chain(mobile){
  const reg=mobile?registry.mobile:registry.desktop,w=mobile?353:1120,states=['默认','倒序','单跳','已添加','更换|0','更换|1','更换|2','添加跳点','已更换','测试中','测试失败','测试通过','已选中'];
  const lib=r77Set('代理链',states,mobile,key=>{
    const c=r77Body('代理链',w);c.itemSpacing=mobile?12:16;
    if(key==='已选中'){
      const heading=between(row('节点结果标题',w,44,8));add(heading,r6Text('节点',mobile?26:28,'Text','Medium'),r77Button('全部节点',reg.Nodes,'Secondary','nodes',120,'NAVIGATE'));add(c,heading,r77Note('已选中开发代理链','当前连接保持不变，返回概览开关 VPN 后应用。',w,'Success'));
      const saved=borderCard('已选代理链',w,null,16,10,'PrimarySurface');stroke(saved,'Primary');const head=between(row('已选代理链标题',w-34,28));add(head,r6Text('开发代理链',18,'Text','Medium'),icon('check',20,'Primary'));add(saved,head,r77Text('办公 HTTP → 东京 · 樱花',14,'Secondary',w-34),r77Text('2 跳 · 测试通过 46 ms · 待概览应用',12,'Primary',w-34));add(c,saved,r77Button('前往概览',reg[mobile?'Home':'Dashboard'],'Primary','grid',mobile?w:240,'NAVIGATE'));return c;
    }
    const picker=key.startsWith('更换|')||key==='添加跳点';
    if(picker){
      add(c,r77Back(key==='添加跳点'?'添加跳点':'更换第 '+(+key.split('|')[1]+1)+' 跳',w,'默认'),r77Field('搜索节点','名称、协议或地区',w));
      for(const data of [G_MAIN[0],G_LOOSE[0],G_BACKUP[0]]){const card=borderCard('选择跳点 · '+data.name,w,null,12,4,'Surface');add(card,between(add(row('跳点选项',w-26,32),r6Text(data.name,15,'Text','Medium'),r77Text(data.ping+' ms',13,'Primary'))),r77Text(data.p+' · '+data.region,12,'Muted',w-26));add(c,r77Go(card,key==='添加跳点'?'已添加':'已更换'));}
      add(c,r77Text('HTTP 跳点仅转发 TCP；UDP 不兼容时会在测试中提示。',12,'Muted',w));return c;
    }
    add(c,r77Back('代理链编排',w,reg.Nodes));r77Edges[r77Edges.length-1].nav='NAVIGATE';
    const rowW=mobile?w:728,left=mobile?c:v('可视化代理链',rowW,12),right=mobile?c:borderCard('代理链操作',368,null,20,12,'Surface'),rev=key==='倒序';
    add(left,r77Field('链名称','开发代理链',rowW));
    const route=borderCard('链路路径',rowW,null,12,8,'Raised');add(route,r77Text('本机 → '+(rev?'东京 · 樱花 → 办公 HTTP':key==='单跳'?'办公 HTTP':key==='已添加'?'办公 HTTP → 东京 · 樱花 → 新加坡':'办公 HTTP → 东京 · 樱花')+' → 目标',13,'Secondary',rowW-26));add(left,route);
    const data=key==='单跳'?[G_LOOSE[0]]:key==='已添加'?[G_LOOSE[0],G_MAIN[0],G_MAIN[2]]:rev?[G_MAIN[0],G_LOOSE[0]]:key==='已更换'?[G_LOOSE[0],G_BACKUP[0]]:[G_LOOSE[0],G_MAIN[0]];
    data.forEach((d,i)=>add(left,r77Hop(d,i,data.length,rowW,mobile,key)));add(left,r77Button('添加跳点','添加跳点','Secondary','plus',rowW));
    if(!mobile)add(c,add(row('代理链布局',w,null,24),left,right));
    if(key==='测试失败')add(right,r77Note('第 2 跳握手超时','入口可达，请更换出口节点或重试。原有选择保持不变。',mobile?w:326,'Error'));
    else if(key==='测试通过')add(right,r77Note('测试通过 · 46 ms','两跳 TCP 握手成功 · 出口为日本东京',mobile?w:326,'Success'));
    else if(key==='单跳')add(right,r77Note('还需要一个出口','代理链至少包含两个节点。',mobile?w:326,'Warning'));
    else add(right,r77Text(key==='测试中'?'正在测试第 2 跳…':'按顺序转发，最后一跳作为出口。',13,'Muted',mobile?w:326));
    add(right,r77Button(key==='测试失败'?'重新测试':key==='测试中'?'测试中…':'测试链路',key==='测试中'||key==='单跳'?null:key==='测试失败'?'测试通过':'测试中','Secondary','speed',mobile?w:326));
    const save=r77Button('保存并选中',key==='测试通过'?'已选中':null,'Primary','check',mobile?w:326);if(key!=='测试通过')save.opacity=.4;add(right,save,r77Text('保存只更改选择。VPN 开关与代理模式均在概览。',12,'Muted',mobile?w:326));return c;
  },2);
  await lib.variants['测试中'].setReactionsAsync(r7Timer(lib.variants['测试失败'].id));
  // The header is part of this component, so the saved result can return visually to Nodes.
  const screen=reg['Chain editor'];if(mobile){const h=uFind(screen,'Page header');if(h)h.visible=false;}r77Install(screen,lib.initial,'代理链编排工作区',false);
  return lib;
}
function r77Toolbar(w,left,right){const n=between(row('操作栏',w,null,12));if(left)add(n,left);if(right)add(n,right);return n;}
function r77Metric(label,value,detail,w){const n=borderCard(label,w,null,16,6,'Surface');rad(n,12);add(n,r77Text(label,12,'Muted'),r6Text(value,28,'Text','Medium',w-34),r77Text(detail,12,'Secondary',w-34));return n;}
function r77Table(columns,rows,w,keyPrefix='条目'){
  const n=borderCard('数据列表',w,null,0,0,'Surface');rad(n,12);n.clipsContent=true;
  const make=(values,head=false,index=0)=>{const line=row(head?'表头':keyPrefix+' · '+index,w,head?40:56,16,0,head?'Raised':null);line.paddingLeft=line.paddingRight=16;
    columns.forEach((col,i)=>add(line,r77Text(values[i],head?12:13,head?'Muted':i===0?'Text':'Secondary',col[1])));return line;};
  add(n,make(columns.map(c=>c[0]),true));rows.forEach((r,i)=>{if(i)add(n,divider(w));add(n,make(r,false,i));});return n;
}
function r77ClearHeaderActions(screen){const head=uFind(screen,'Page header');if(head)for(const n of [...head.children])if(n.type==='INSTANCE')n.remove();}
async function r77Rules(){
  const w=1120,states=['全部','域名','IP','添加','编辑','编辑 IP','保存完成','确认删除','删除完成'];
  const rules=[['DOMAIN-SUFFIX','github.com','主订阅','代理'],['DOMAIN-SUFFIX','openai.com','主订阅','代理'],['IP-CIDR','192.168.0.0/16','直连','直连'],['IP-CIDR','10.0.0.0/8','直连','直连'],['MATCH','所有其他请求','主订阅','代理']];
  const lib=r77Set('分流规则',states,false,key=>{
    const c=r77Body('规则工作区',w);c.itemSpacing=16;
    if(['添加','编辑','编辑 IP'].includes(key)){
      const p=borderCard('规则编辑',728,null,24,16,'Surface'),iw=678;add(p,r77Back(key==='添加'?'添加规则':'编辑规则',iw,'全部'));
      const type=r77Tabs(['域名后缀','IP 网段'],key==='编辑 IP'?'IP 网段':'域名后缀',iw,false,'规则类型');r77Go(type.children[0],'编辑');r77Go(type.children[1],'编辑 IP');add(p,type,r77Field(key==='编辑 IP'?'IP 网段 · CIDR':'域名后缀',key==='编辑 IP'?'192.168.0.0/16':'github.com',iw),r77Field('出站策略','主订阅',iw),r77Text('按顺序匹配，首个命中的规则决定出站。',13,'Muted',iw));
      const actions=row('规则编辑操作',iw,44,12);add(actions,r77Button('取消','全部','Secondary',null,120),r77Button('保存规则','保存完成','Primary','check',180));add(p,actions);add(c,p);return c;
    }
    const tabs=r77Tabs(['全部','域名','IP'],['域名','IP'].includes(key)?key:'全部',336,false,'规则过滤');tabs.children.forEach((n,i)=>r77Go(n,['全部','域名','IP'][i]));add(c,r77Toolbar(w,tabs,r77Button('添加规则','添加','Primary','plus',144)));
    add(c,r77Text('当前为规则模式 · 匹配优先级从上到下 · 代理模式在概览切换',13,'Muted',w));
    if(key==='保存完成')add(c,r77Note('规则已保存','配置已校验并应用于后续新连接。',w,'Success'));
    if(key==='删除完成')add(c,r77Note('规则已删除','其余规则顺序保持不变。',w,'Success'));
    const data=rules.filter((r,i)=>(key!=='删除完成'||i!==0)&&(key==='域名'?r[0].startsWith('DOMAIN'):key==='IP'?r[0].startsWith('IP'):true));
    const list=r77Table([['类型',190],['匹配条件',430],['出站',210],['操作',170]],data.map(r=>[r[0],r[1],r[2],'编辑       删除']),w,'规则');
    for(const line of list.children.filter(n=>r5Name(n).startsWith('规则 · '))){const action=line.children[line.children.length-1];action.visible=false;const buttons=row('规则行操作',170,44,4);add(buttons,r77Button('编辑','编辑','Ghost',null,76),r77Button('删除','确认删除','Ghost',null,76));add(line,buttons);}add(c,list);
    if(key==='确认删除')add(c,r77Note('删除 github.com 的规则？','删除后，该域名将继续匹配后续规则。',w,'Warning'),add(row('确认删除规则',w,44,12),r77Button('取消','全部','Secondary',null,120),r77Button('确认删除','删除完成','Primary',null,144)));
    return c;
  },2);r77ClearHeaderActions(registry.desktop.Rules);r77Install(registry.desktop.Rules,lib.initial,'规则工作区');return lib;
}
function r77Chart(w,mobile,period,point=false,to=null){
  const p=mobile?16:20,iw=w-p*2-2,n=borderCard('流量趋势图',w,null,p,12,'Surface'),unit=period==='今日'?'MB/s':'GB',plotH=mobile?140:170;
  add(n,between(add(row('图表标题',iw,24),r6Text('流量趋势',14,'Text','Medium'),r77Text(unit,12,'Muted'))));
  const plot=frame('图表选点区',iw,plotH,'NONE');plot.clipsContent=true;add(n,r77Go(plot,to));
  for(let i=0;i<3;i++){const line=frame('网格线',iw-36,1,'NONE','Stroke');add(plot,line);line.x=36;line.y=16+i*(plotH-40)/2;const label=r77Text(String(period==='今日'?24-i*12:18-i*9),12,'Muted');add(plot,label);label.x=0;label.y=line.y-8;}
  const base=[.12,.18,.1,.39,.26,.31,.28,.62,.38,.46,.83,.57,.61,.43,.75,.5,.36,.28,.55,.44,.51,.79,.62,.84];
  for(const [k,tone,scale]of [[0,'Primary',1],[1,'Chart2',.33]]){const path=base.map((v,i)=>`${i?'L':'M'} ${36+i*(iw-40)/(base.length-1)} ${plotH-15-v*scale*(plotH-35)}`).join(' '),vector=figma.createVector();r6Name(vector,k?'上传曲线':'下载曲线');vector.vectorPaths=[{windingRule:'NONE',data:path}];vector.fills=[];stroke(vector,tone,2);add(plot,vector);}
  if(point){const tip=borderCard('选点数据',mobile?150:210,null,10,2,'Raised');stroke(tip,'Primary');add(tip,r77Text(period==='今日'?'12:00':'10 月 12 日',12),r77Text('↓ '+(period==='今日'?'18.2 MB/s':'12.4 GB'),12,'Primary'),r77Text('↑ '+(period==='今日'?'1.8 MB/s':'860 MB'),12,'Chart2'));add(plot,tip);tip.x=iw-tip.width-12;tip.y=8;}
  const axis=between(row('横轴',iw,20));for(const label of period==='今日'?['00:00','06:00','12:00','18:00']:period==='本周'?['周一','周三','周五','周日']:['1 日','10 日','20 日','30 日'])add(axis,r77Text(label,12,'Muted'));add(n,axis,add(row('图例',iw,20,16),r77Text('● 下载',12,'Primary'),r77Text('● 上传',12,'Chart2')));return n;
}
async function r77Traffic(mobile){
  const w=mobile?353:1120,states=['今日','本周','本月','今日 · 选点','本周 · 选点','本月 · 选点','导出完成'];
  const lib=r77Set('流量统计',states,mobile,key=>{
    const period=key.split(' · ')[0]==='导出完成'?'今日':key.split(' · ')[0],point=key.includes('选点'),c=r77Body('流量统计',w);c.itemSpacing=16;
    const tabs=r77Tabs(['今日','本周','本月'],period,mobile?w:360,mobile,'流量周期');tabs.children.forEach((n,i)=>r77Go(n,['今日','本周','本月'][i]));
    if(mobile)add(c,tabs);else add(c,r77Toolbar(w,tabs,r77Button('导出 CSV','导出完成','Secondary','download',148)));
    if(key==='导出完成')add(c,r77Note('流量统计已导出','当前周期的上传、下载和用量排行已包含在内。',w,'Success'));
    const total=period==='今日'?'8.42 GB':period==='本周'?'42.8 GB':'126.4 GB',down=period==='今日'?'7.86 GB':period==='本周'?'39.6 GB':'117.2 GB',up=period==='今日'?'560 MB':period==='本周'?'3.2 GB':'9.2 GB';
    if(mobile){const card=r77Metric('总流量 · '+period,total,'↓ '+down+'    ↑ '+up,w);fill(card,'PrimarySurface');add(c,card);}else add(c,add(row('周期总计',w,null,16),r77Metric('总流量',total,period,(w-32)/3),r77Metric('已下载',down,'当前周期 · 下载',(w-32)/3),r77Metric('已上传',up,'当前周期 · 上传',(w-32)/3)));
    add(c,r77Chart(w,mobile,period,point,point?period:period+' · 选点'));
    const ranking=borderCard('使用排行',w,null,16,8,'Surface');add(ranking,r6Text('使用排行',14,'Text','Medium'));
    for(const [i,label,value,ratio]of [[1,'浏览器',period==='今日'?'4.28 GB':'24.6 GB',.67],[2,'代码编辑器',period==='今日'?'2.46 GB':'12.2 GB',.44],[3,'终端',period==='今日'?'1.68 GB':'6.0 GB',.28]]){const line=between(row('流量排行 · '+label,w-34,36));add(line,r77Text(i+'  '+label,13),r77Text(value,12,'Secondary'));add(ranking,line,r6Progress(w-34,ratio));}add(c,ranking);
    if(mobile)add(c,r77Button('导出当前统计','导出完成','Ghost','download',w));return c;
  },2);const screen=(mobile?registry.mobile:registry.desktop).Traffic;r77ClearHeaderActions(screen);r77Install(screen,lib.initial,'流量统计工作区');return lib;
}
async function r77Connections(){
  const w=1120,states=['全部','代理','直连','已暂停','搜索','无结果','关闭单条','确认关闭全部','全部关闭','导出完成'];
  const rows=[['api.github.com:443','代码编辑器','DOMAIN-SUFFIX','代理','4.2 MB','04:32'],['registry.npmjs.org:443','终端','DOMAIN-SUFFIX','代理','168.2 MB','02:18'],['developer.apple.com:443','浏览器','DOMAIN-SUFFIX','代理','12.4 MB','01:54'],['192.168.1.1:80','浏览器','IP-CIDR','直连','284 KB','00:41'],['docs.rs:443','代码编辑器','MATCH','代理','3.8 MB','00:26'],['api.openai.com:443','终端','DOMAIN','代理','1.2 MB','00:14']];
  const lib=r77Set('实时连接',states,false,key=>{
    const c=r77Body('实时连接',w),zero=key==='全部关闭';c.itemSpacing=16;add(c,add(row('连接指标',w,null,16),r77Metric('活跃连接',zero?'0':key==='关闭单条'?'141':'142',key==='已暂停'?'列表已暂停刷新':'每秒刷新',(w-32)/3),r77Metric('代理 / 直连',zero?'0 / 0':key==='关闭单条'?'127 / 14':'128 / 14','当前活跃连接',(w-32)/3),r77Metric('累计传输','2.84 GB','本次会话',(w-32)/3)));
    const search=r77Go(r77Field('连接筛选',key==='搜索'?'github':key==='无结果'?'不存在的域名':'搜索域名、进程或规则',360),key==='搜索'?'无结果':key==='无结果'?'全部':'搜索');
    const filters=r77Tabs(['全部','代理','直连'],['代理','直连'].includes(key)?key:'全部',252,false,'连接类型');filters.children.forEach((n,i)=>r77Go(n,['全部','代理','直连'][i]));
    const controls=row('连接操作',null,44,8);add(controls,filters,r77Button(key==='已暂停'?'继续刷新':'暂停刷新',key==='已暂停'?'全部':'已暂停','Secondary',null,108),r77Button('关闭全部','确认关闭全部','Secondary','close',120),r77Button('导出','导出完成','Secondary','download',92));add(c,r77Toolbar(w,search,controls));
    if(key==='已暂停')add(c,r77Note('已暂停列表刷新','连接仍在运行，继续刷新可查看最新数据。',w));
    if(key==='关闭单条')add(c,r77Note('已关闭所选连接','应用下次请求时会按规则重新建立连接。',w,'Success'));
    if(key==='导出完成')add(c,r77Note('连接快照已导出','已包含目标、进程、规则、出站与流量。',w,'Success'));
    if(key==='确认关闭全部')add(c,r77Note('关闭全部 142 条连接？','应用可能立即重连，VPN 状态保持开启。',w,'Warning'),add(row('关闭全部确认',w,44,12),r77Button('取消','全部','Secondary',null,120),r77Button('确认关闭','全部关闭','Primary',null,144)));
    let data=zero||key==='无结果'?[]:rows.filter((r,i)=>(key!=='关闭单条'||i!==0)&&(key==='代理'?r[3]==='代理':key==='直连'?r[3]==='直连':key==='搜索'?r[0].includes('github'):true));
    if(!data.length)add(c,r77Note(zero?'暂无活跃连接':'没有匹配的连接',zero?'新的网络请求会自动出现在这里。':'调整关键词，或清空筛选。',w),r77Button('清空筛选','全部','Secondary',null,144));
    else{const table=r77Table([['目标地址',280],['进程',160],['匹配规则',190],['出站',90],['流量',100],['操作',150]],data.map(r=>[r[0],r[1],r[2],r[3],r[4],'关闭']),w,'连接');for(const line of table.children.filter(n=>r5Name(n).startsWith('连接 · '))){line.children[5].visible=false;add(line,r77Button('关闭','关闭单条','Ghost','close',100));}add(c,table);}return c;
  },2);r77ClearHeaderActions(registry.desktop.Connections);r77Install(registry.desktop.Connections,lib.initial,'实时连接工作区');return lib;
}
async function r77Logs(){
  const w=1120,states=['全部','信息','警告','错误','搜索','无结果','暂停','确认清空','已清空','已导出'];
  const logs=[['10:42:18.023','信息','隧道已建立 · 东京 · 樱花'],['10:42:18.108','信息','订阅已载入 · 126 条规则 · 8 个节点'],['10:42:18.246','信息','DNS 解析器就绪 · fake-ip 已开启'],['10:42:19.504','信息','TCP · 代码编辑器 → api.github.com:443 · VLESS · 24 ms'],['10:42:21.811','警告','备用 · 韩国首尔 · 探测超时，已保留当前节点'],['10:42:23.054','信息','健康检查完成 · 8 个节点中 7 个在线'],['10:42:24.026','错误','备用订阅更新失败 · 请求超时，保留上次可用配置'],['10:42:29.158','信息','活跃连接 142 · 当前下载 12.8 MB/s']];
  const lib=r77Set('运行日志',states,false,key=>{
    const c=r77Body('运行日志',w);c.itemSpacing=16;const search=r77Go(r77Field('搜索日志',key==='搜索'?'DNS':key==='无结果'?'不存在的事件':'搜索事件或关键词',360),key==='搜索'?'无结果':key==='无结果'?'全部':'搜索'),tabs=r77Tabs(['全部','信息','警告','错误'],['信息','警告','错误'].includes(key)?key:'全部',320,false,'日志级别');tabs.children.forEach((n,i)=>r77Go(n,['全部','信息','警告','错误'][i]));
    const controls=row('日志操作',null,44,8);add(controls,tabs,r77Button(key==='暂停'?'继续':'暂停',key==='暂停'?'全部':'暂停','Secondary',null,80),r77Button('清空','确认清空','Secondary',null,80),r77Button('导出','已导出','Secondary','download',100));add(c,r77Toolbar(w,search,controls));
    if(key==='确认清空')add(c,r77Note('清空当前日志？','此操作只清空本地记录，不影响连接。',w,'Warning'),add(row('日志清空确认',w,44,12),r77Button('取消','全部','Secondary',null,100),r77Button('确认清空','已清空','Primary',null,144)));
    if(key==='已导出')add(c,r77Note('日志已导出','已隐藏订阅令牌、密码与认证信息。',w,'Success'));
    if(key==='暂停')add(c,r77Note('已暂停自动滚动','新事件仍在后台记录。',w));
    const data=['已清空','无结果'].includes(key)?[]:logs.filter(r=>['信息','警告','错误'].includes(key)?r[1]===key:key==='搜索'?r[2].includes('DNS'):true);
    if(!data.length)add(c,r77Note(key==='已清空'?'日志已清空':'未找到匹配日志','新的事件会继续记录，可清空筛选查看全部。',w),r77Button('查看全部','全部','Secondary',null,144));
    else add(c,r77Table([['时间',170],['级别',100],['事件',770]],data,w,'日志'));
    add(c,r77Text('日志保留 7 天 · 自动隐藏认证信息',12,'Muted',w));return c;
  },2);r77ClearHeaderActions(registry.desktop.Logs);r77Install(registry.desktop.Logs,lib.initial,'运行日志工作区');return lib;
}
async function r77NodeActions(mobile){
  const states=['未收藏','已收藏','菜单','已收藏菜单','编辑','订阅说明','删除确认','已删除','已保存'];
  const lib=r77Set('节点操作',states,mobile,key=>{
    const c=r77Body('节点操作',mobile?88:80);c.layoutMode='HORIZONTAL';c.primaryAxisSizingMode=c.counterAxisSizingMode='FIXED';c.resize(mobile?88:80,44);c.itemSpacing=0;c.clipsContent=false;
    const fav=key.startsWith('已收藏'),star=r77Button('',fav?'未收藏':'已收藏','Ghost','star',44),more=r77Button('',fav?'已收藏菜单':'菜单','Ghost','more',mobile?44:36);r6Name(star,'节点收藏');r6Name(more,'节点更多');if(fav){tint(star,'Primary');fill(star,'PrimarySurface');}add(c,star,more);
    if(['未收藏','已收藏'].includes(key))return c;
    const menu=borderCard('节点操作菜单',mobile?280:320,null,12,8,'Raised');rad(menu,12);stroke(menu);add(c,menu);menu.layoutPositioning='ABSOLUTE';menu.x=c.width-menu.width;menu.y=48;const iw=menu.width-26;
    if(key.includes('菜单'))add(menu,r6Text('当前节点',15,'Text','Medium'),r77Button('编辑手动节点','编辑','Ghost',null,iw),r77Button('查看订阅节点','订阅说明','Ghost',null,iw),r77Button('删除节点','删除确认','Ghost',null,iw),r77Button('收起','未收藏','Ghost',null,iw));
    else if(key==='编辑')add(menu,r77Back('编辑节点',iw,'菜单'),r77Field('名称','办公 HTTP',iw),r77Field('服务器','proxy.backup.example.com',iw),r77Field('端口','8080',iw),r77Button('保存修改','已保存','Primary',null,iw));
    else if(key==='订阅说明')add(menu,r77Back('订阅节点',iw,'菜单'),r77Text('订阅节点的连接参数跟随订阅更新。名称别名、收藏与隐藏状态保存在本地。',12,'Secondary',iw),r77Button('更新所属订阅',(mobile?registry.mobile:registry.desktop)['Subscription info · 主订阅'],'Secondary','refresh',iw,'OVERLAY'));
    else if(key==='删除确认')add(menu,r77Back('删除此节点？',iw,'菜单'),r77Text('手动节点会被删除；订阅节点只在本地隐藏，下次更新仍保持隐藏。',12,'Secondary',iw),r77Button('确认删除','已删除','Primary',null,iw));
    else add(menu,r77Note(key==='已保存'?'节点已保存':'节点已删除',key==='已保存'?'已保留所属分组与收藏状态。':'当前出站在断开前保持。',iw,'Success'),r77Button('完成','未收藏','Primary',null,iw));
    return c;
  },3);
  const master=masters['Group node / '+(mobile?'Mobile':'Desktop')],parent=uFind(master,mobile?'Node actions':'Node facts');
  const star=parent.children.find(n=>r5Name(n)==='节点收藏与菜单')||parent.children.find(n=>n.type==='INSTANCE'&&/^Button · |^按钮 · /.test(r5Name(n)));const index=star?parent.children.indexOf(star):parent.children.length;if(star)star.remove();parent.insertChild(index,r7Instance(lib.initial,'节点收藏与菜单'));
  if(mobile){const region=uFind(master,'节点地区');if(region)region.visible=false;const copy=uFind(master,'紧凑节点内容');if(copy){const name=uFind(copy,'节点名称');name.textAutoResize='TRUNCATE';name.maxLines=1;name.layoutSizingHorizontal='FILL';} }
  // Source and result instances retain their per-node values; new operations inherit the master.
  return lib;
}
async function r77PlatformControls(){
  const lib=r77Set('平台网络能力',['iOS · 已授权','iOS · 未授权','Android · 已授权','Android · 未授权'],true,key=>{
    const c=r77Body('平台网络能力',353);c.resize(353,56);c.primaryAxisSizingMode='FIXED';fill(c,'Surface');stroke(c);rad(c,12);c.layoutMode='HORIZONTAL';c.counterAxisAlignItems='CENTER';c.paddingLeft=c.paddingRight=12;c.itemSpacing=8;
    const label=add(v('系统 VPN 说明',245,3),r6Text('系统 VPN · '+(key.startsWith('iOS')?'iOS':'Android'),13,'Text','Medium'),r77Text('系统代理不可用 · 通过 VPN 隧道接管',12,'Muted',245));add(c,label,r6Badge(key.endsWith('未授权')?'待授权':'已授权',key.endsWith('未授权')?'Warning':'Success'));return c;
  },2);lib.set.description='移动端保留首页接管信息。iOS 使用 NetworkExtension，Android 使用 VpnService；均不提供桌面式全局系统代理。VPN 总开关在概览，首次连接触发系统授权。';return lib;
}
async function r77Homes(report,platformLib){
  const result={};
  for(const mobile of [false,true]){
    const platform=mobile?'mobile':'desktop',ui=report.compactCanvas.homeStates[platform],set=await figma.getNodeByIdAsync(ui.set),states={};for(const [key,id]of Object.entries(ui.states))states[key]=await figma.getNodeByIdAsync(id);
    const extra=['连接详情','检测中','连接失败','连接超时','需要授权','授权拒绝','首次使用'];
    for(const key of extra){const old=set.children.find(n=>n.name==='连接='+key);if(old)old.remove();const c=states[key==='连接详情'?'开启':'关闭'].clone();set.appendChild(c);r6Name(c,'连接='+key);await r7Clear(c);states[key]=c;}
    for(const key of extra){const c=states[key];
      const feedback={连接详情:['连接正常','当前出站：东京 · 樱花 · VLESS · 24 ms','Info'],检测中:['正在检测链路','检查本地网络、节点握手和出口连通性…','Info'],连接失败:['无法建立连接','节点握手失败。已保留当前选择，可重试或更换节点。','Error'],连接超时:['连接超时','节点未在 10 秒内响应。请检查网络或更换节点。','Error'],需要授权:['允许系统 VPN',mobile?'连接需要系统 VPN 授权，RainLink 将在确认后请求系统许可。':'TUN 模式需要网络适配器权限，请允许系统授权。','Info'],授权拒绝:['未获得 VPN 权限','请重新授权后再连接，或在系统设置中允许 RainLink。','Warning'],首次使用:['添加第一个节点','订阅自动成组，单个节点进入未分组。','Info']}[key];
      const note=r77Note(...[feedback[0],feedback[1],mobile?353:1120,feedback[2]]);c.insertChild(1,note);
      const actions=row('连接反馈操作',mobile?353:1120,44,8);add(c,actions);
      const go=(label,to,tone='Secondary',ic=null)=>add(actions,r77Button(label,to,tone,ic,mobile?((353-8)/2):160));
      if(key==='连接详情'){go('检查链路',states['检测中']);go('关闭详情',states['开启']);}
      else if(key==='检测中')go('取消检测',states['开启']);
      else if(['连接失败','连接超时'].includes(key)){go('重试连接',states['连接中'],'Primary','refresh');go('更换节点',(mobile?registry.mobile:registry.desktop).Nodes,'Secondary','nodes');r77Edges[r77Edges.length-1].nav='NAVIGATE';}
      else if(key==='需要授权'){go('允许 VPN',states['连接中'],'Primary','shield');go('暂不允许','授权拒绝');}
      else if(key==='授权拒绝'){go('重新授权',states['需要授权'],'Primary');go('取消',states['关闭']);}
      else if(key==='首次使用'){go('添加',(mobile?registry.mobile:registry.desktop)['Import profile'],'Primary','plus');r77Edges[r77Edges.length-1].nav='OVERLAY';}
      if(!['连接详情','检测中','首次使用'].includes(key))for(const t of c.findAll(n=>n.type==='TEXT'))if(['VPN 已关闭','点按开启 VPN','等待连接'].includes(t.characters))r6Copy(t,t.characters==='VPN 已关闭'?feedback[0]:'检查网络后重试');
      const power=c.findOne(n=>n.getPluginData('rainlink-control-kind')==='vpn-power');if(power&&key!=='首次使用')r77Go(power,states[mobile&&['需要授权','授权拒绝'].includes(key)?'需要授权':'连接中']);
    }
    // Resolve references to variants created later in the same loop.
    for(const e of r77Edges)if(typeof e.to==='string'&&states[e.to])e.to=states[e.to];
    for(const [key,c]of Object.entries(states)){
      if(mobile){const old=uFind(c,'首页网络接管')||uFind(c,'首页平台网络接管');if(old){const p=old.parent,i=p.children.indexOf(old);old.remove();p.insertChild(i,r7Instance(platformLib.variants[key==='需要授权'||key==='授权拒绝'?'iOS · 未授权':'iOS · 已授权'],'首页平台网络接管'));}}
      const summary=uFind(c,mobile?'Connection summary':'Connection group hero');
      const hero=uFind(c,mobile?'VPN control':'Connection group hero'),copy=mobile?uFind(hero,'连接状态摘要'):null;
      if(copy&&['开启','关闭'].includes(key)){const caption=copy.children.find(n=>n.type==='TEXT'&&n.fontSize<18);if(caption)r6Copy(caption,'连接详情 ›');r77Go(copy,states['连接详情']);}
      if(!mobile&&['开启','关闭'].includes(key)){const old=uFind(c,'概览连接详情');if(old)old.remove();const line=row('概览连接详情',1120,32,8);add(line,r77Go(r6Text('连接详情 ›',13,'Muted','Regular',1120),states['连接详情']));add(c,line);}
      if(mobile&&key==='关闭'){const power=c.findOne(n=>n.getPluginData('rainlink-control-kind')==='vpn-power');r77Go(power,states['需要授权']);}
      if(!['开启','连接中','断开中'].includes(key))for(const t of c.findAll(n=>n.type==='TEXT'))if(t.characters==='12.8'||t.characters==='1.4')r6Copy(t,'0');
    }
    await states['检测中'].setReactionsAsync(r7Timer(states['连接超时'].id));
    // Failure is reached from a timed-out handshake; retry returns to the normal connection flow.
    const timeout=states['连接超时'],retry=uFind(timeout,'按钮 · 重试连接');if(retry)r77Go(retry,states['连接失败']);
    const maxW=Math.max(...set.children.map(n=>n.width)),maxH=Math.max(...set.children.map(n=>n.height));set.children.forEach((n,i)=>{n.x=24+(i%2)*(maxW+32);n.y=24+Math.floor(i/2)*(maxH+40);});set.resize(48+2*(maxW+32)-32,48+Math.ceil(set.children.length/2)*(maxH+40)-40);
    result[platform]={set:set.id,states:Object.fromEntries(Object.entries(states).map(([k,v])=>[k,v.id]))};
  }return result;
}
async function r77Consistency(report){
  for(const screen of Object.values(registry.desktop)){
    const bar=screen.findOne(n=>n.type==='FRAME'&&(r5Name(n)==='Top status bar'||n.name==='连接状态栏'));
    if(bar)for(const t of bar.findAll(n=>n.type==='TEXT')){const s=t.characters;if(s==='未连接')r6Copy(t,'已连接 · 东京 · 樱花');if(/↓\s*0\s*MB\/s/.test(s))r6Copy(t,'↓ 12.8 MB/s');if(/↑\s*0\s*MB\/s/.test(s))r6Copy(t,'↑ 1.4 MB/s');}
  }
  // The Nodes tab is a top-level destination, so it has no fixed Profiles back link.
  const header=uFind(registry.mobile.Nodes,'Page header');
  if(header){const left=header.children[0];if(left?.type==='INSTANCE')left.remove();header.itemSpacing=8;header.primaryAxisAlignItems='SPACE_BETWEEN';const title=header.children.find(n=>n.type==='FRAME');if(title){title.resize(293,title.height);for(const t of title.findAll(n=>n.type==='TEXT')){t.resize(293,t.height);t.textAutoResize='HEIGHT';}}}
  // Remove the second group-selection action in each desktop overview variant.
  const home=await figma.getNodeByIdAsync(report.compactCanvas.homeStates.desktop.set);
  for(const c of home.children){const actions=c.findAll(n=>n.type==='INSTANCE'&&n.findAll(t=>t.type==='TEXT').length===1&&n.findAll(t=>t.type==='TEXT')[0].characters==='选择分组');for(const n of actions.slice(1))n.visible=false;
    const trends=uFind(c,'Connection trends'),chart=trends?.children[0];if(chart&&!chart.findOne(n=>r5Name(n)==='延迟单位')){const text=r6Name(r77Text('延迟 · ms',12,'Muted'),'延迟单位');add(chart,text);text.layoutPositioning='ABSOLUTE';text.x=16;text.y=chart.height-24;}
    if(!uFind(c,'Recent connection record')&&!uFind(c,'最近连接记录')){const recent=between(row('最近连接记录',1120,44,12));add(recent,r77Text('最近连接',12,'Muted'),r77Text('api.github.com · 主订阅 · 24 ms',13,'Secondary'),r77Button('查看全部',registry.desktop.Connections,'Ghost','connections',120,'NAVIGATE'));add(c,recent);}
  }
  // Mobile update wording follows the installation source rather than assuming one store.
  const section=await figma.getNodeByIdAsync(report.settingsUI.section);
  for(const t of section.findAll(n=>n.type==='TEXT'&&/App Store/.test(n.characters))){r6Copy(t,t.characters.replace(/前往 App Store/g,'打开安装来源').replace(/App Store/g,'安装来源'));}
  return {defaultScenario:'VPN 开启 / 规则 / 主订阅 / 东京 · 樱花 / 24 ms / 下载 12.8 MB/s / 上传 1.4 MB/s',mobileTopLevelBackRemoved:true,proxyControls:'概览',selectionOnly:true};
}
async function r77ReadableAndHits(report){
  const changed=[];const mobileRoots=[mobilePage,...dsPage.findAll(n=>(n.type==='COMPONENT_SET'||n.type==='COMPONENT')&&/移动端|Mobile/.test(r5Name(n)))];
  const seen=new Set();for(const root of mobileRoots)for(const n of [root,...root.findAll(()=>true)]){
    if(seen.has(n.id))continue;seen.add(n.id);
    // Edit source nodes once. Traversing every nested instance creates thousands
    // of overrides and makes the Figma editor unresponsive.
    let inherited=false;for(let a=n.parent;a&&a!==root;a=a.parent)if(a.type==='INSTANCE'){inherited=true;break;}if(inherited)continue;
    if(n.type==='TEXT'&&typeof n.fontSize==='number'&&n.fontSize<12&&n.characters.trim()){
      n.fontName={family:zhFamily,style:zhStyles.Regular};n.fontSize=12;const line=n.lineHeight;if(line.unit==='PIXELS'&&line.value<16)n.lineHeight={unit:'PIXELS',value:16};changed.push(n.id);
    }
    if(!('reactions'in n)||!n.reactions.length||!('resize'in n)||n.type==='TEXT'||n.width>=44&&n.height>=44)continue;
    const name=r5Name(n);
    if(name.startsWith('出口模式 · ')){
      n.resize(n.width,44);const tabs=n.parent;if(tabs.height<44){const delta=44-tabs.height;tabs.resize(tabs.width,44);const card=tabs.parent;if(card.primaryAxisSizingMode==='FIXED')card.resize(card.width,card.height+delta);}
    }else if(name.startsWith('选择节点分组 · ')){
      n.resize(Math.max(44,n.width),44);n.parent.resize(n.parent.width,44);
    }else if(n.type==='INSTANCE'&&n.width<44){n.resize(44,Math.max(44,n.height));n.primaryAxisSizingMode=n.counterAxisSizingMode='FIXED';n.paddingLeft=n.paddingRight=0;}
    else if(n.type==='INSTANCE'||n.type==='FRAME'){n.resize(Math.max(n.width,44),Math.max(n.height,44));if(n.layoutMode==='HORIZONTAL')n.counterAxisSizingMode='FIXED';}
  }
  // Parent chip strips reserve the full hit height without increasing node-card heights.
  for(const set of dsPage.findAll(n=>n.type==='COMPONENT_SET'&&/移动端 \/ 节点选择$/.test(r5Name(n))))for(const c of set.children){const strip=uFind(c,'节点分组选项');if(strip)strip.resize(strip.width,44);}
  const mobileHeader=uFind(registry.mobile.Home,'Page header');if(mobileHeader)for(const b of mobileHeader.children.filter(n=>n.type==='INSTANCE'))b.resize(Math.max(44,b.width),44);
  return {minimumReadableSize:12,mobileHitMinimum:44,textLayersUpdated:changed.length,compactNodeHeight:72,transparentOrExistingContainers:true};
}
function r77Contract(){
  const c=borderCard('状态与平台交付约定',1120,null,24,16,'Surface');add(c,r6Text('状态、平台与布局约定',26,'Text','Medium'));
  const notes=[
    ['选择与连接','selectedTarget（所选分组、节点或链）与 activeOutbound（实际出站）分别保存。选择只更新 selectedTarget；已连接时显示“待应用”，原出站保持。在概览关闭再开启 VPN 才应用新选择；代理模式也只在概览设置。'],
    ['跨页与持久化','运行时由统一状态仓库驱动所有页面；每组记住上次选中的节点。Figma Starter 使用局部变体与一致的默认示例，不支持跨页面的实时全局状态。代理链保存结果在同一组件呈现返回节点后的选中反馈。'],
    ['自动归组','订阅由服务名称自动成组，缺失名称时用域名或自动编号；单个节点进入未分组。仅未分组节点可移动，移入订阅后更新保留手动节点。删除订阅会把手动节点退回未分组。'],
    ['节点管理','手动节点可编辑连接参数、收藏、删除。订阅节点只允许别名、收藏和本地隐藏，连接参数随订阅同步；隐藏不会在下次更新后恢复。删除正在使用的节点时，现有会话在断开前保持。'],
    ['桌面平台','Windows、macOS、Linux 在概览提供系统代理与 TUN 两个独立选项。TUN 按平台请求适配器或管理员权限；平台不可用时禁用并说明原因。权限失败不静默开启。'],
    ['移动平台','iOS 使用 NetworkExtension，Android 使用 VpnService。首次连接先请求系统 VPN 授权；拒绝后保留选择并提供重新授权。移动端没有桌面式系统代理开关，TUN 能力通过系统 VPN 接管，VPN 总开关保留在概览。'],
    ['安装来源','iOS 按 App Store / TestFlight 更新。Android 按 Google Play、应用商店或独立安装包更新，商店版打开原商店，独立安装提示下载后安装。不会在商店版中展示桌面式原位替换。'],
    ['异常与首次使用','无节点时显示首次使用状态与添加入口，禁用 VPN 按钮。订阅地址错误就地提示；超时保留链接并可重试。连接失败保留所选目标，正在建立连接时允许取消；授权拒绝不继续连接。'],
    ['弹窗与键盘','移动弹窗上限随可用高度变化。键盘出现时正文缩为可滚动区域，固定操作栏位于键盘上方；底部保留系统安全区。长名称单行省略，详情显示完整内容；IP 地址允许两行，不破坏国家图标与刷新命中区。'],
    ['响应式与大字','桌面 1100–1440：侧栏保持 216 px，内容列使用 Fill；低于 1100 收为图标侧栏。移动 360–430：左右边距 16–20 px，列表宽度 Fill，按钮命中不小于 44 px。大字模式辅助文字至少 14 px，卡片随内容增长。'],
    ['图表与导出','今日流量曲线单位 MB/s，周/月按日汇总为 GB。点击或悬停显示时间与上传/下载值。原型导出仅演示 UI 反馈，不创建真实 CSV 或日志；真实导出先隐藏认证信息。']
  ];for(const [label,text]of notes)add(c,r6Text(label,15,'Text','Medium'),r77Text(text,13,'Secondary',1070));r77Place(c);return c;
}
function r77Reflow(n,w){
  if(!('children'in n)||n.type==='VECTOR')return;
  const before=n.width;
  if(n.layoutMode&&n.layoutMode!=='NONE'){
    if(n.layoutMode==='HORIZONTAL')n.primaryAxisSizingMode='FIXED';else n.counterAxisSizingMode='FIXED';
  }
  if('resize'in n&&w>0&&Math.abs(before-w)>.1)n.resize(w,n.height);
  if(!n.layoutMode||n.layoutMode==='NONE'||/^Icon \/|图标 \/|国家图标/.test(n.name))return;
  if(/^按钮 ·|^刷新出口$/.test(n.name)){
    for(const t of n.children.filter(c=>c.type==='TEXT'))t.textAutoResize='WIDTH_AND_HEIGHT';
    return;
  }
  const cs=n.children.filter(c=>c.visible&&c.layoutPositioning!=='ABSOLUTE'),inner=n.width-(n.paddingLeft||0)-(n.paddingRight||0);
  if(n.layoutMode==='VERTICAL'){
    for(const c of cs){if(c.width>inner||Math.abs(c.width-before+(n.paddingLeft||0)+(n.paddingRight||0))<4){if(c.type==='TEXT'){c.resize(inner,c.height);c.textAutoResize='HEIGHT';}else r77Reflow(c,inner);}}
  }else{
    const total=cs.reduce((s,c)=>s+c.width,0)+(n.itemSpacing||0)*Math.max(0,cs.length-1),delta=Math.max(0,total-inner),flex=cs.filter(c=>c.width>100&&!/^按钮 ·|^刷新出口$/.test(c.name)),room=flex.reduce((s,c)=>s+Math.max(0,c.width-80),0);
    for(const c of flex){const next=Math.max(80,c.width-(room?delta*(c.width-80)/room:0));if(c.type==='TEXT'){c.resize(next,c.height);c.textAutoResize='HEIGHT';}else r77Reflow(c,next);}
  }
}
function r77AlignOverview(c){
  const metrics=uFind(c,'Network stats')||uFind(c,'Network metrics')||c.findOne(n=>n.name==='网络统计'),trends=uFind(c,'Connection trends');
  if(!metrics||!trends||metrics.children.length!==3||trends.children.length!==2)return;
  const quality=metrics.children[2],gap=metrics.itemSpacing,health=trends.children[1],chart=trends.children[0];
  // The lower row spans the same three-column grid as the metrics above it.
  // Read the actual third-column width so narrower previews stay aligned too.
  trends.itemSpacing=gap;
  r77Reflow(chart,metrics.width-quality.width-gap);
  r77Reflow(health,quality.width);
  trends.resize(metrics.width,trends.height);
}
function r77Preview(source,name,w,h,light=false,big=false,edge=false){
  const clone=source.clone();clone.setPluginData('rainlink','');const c=figma.createComponentFromNode(clone);r6Name(c,name);r77Mark(c);c.setPluginData('rainlink-review-preview','1');dsPage.appendChild(c);c.resize(w,h);
  // Boundary specimens are editable component snapshots. Detach nested source
  // instances before reflow: inherited fixed dimensions cannot be resized.
  const detach=n=>{for(const child of [...n.children||[]]){const item=child.type==='INSTANCE'?child.detachInstance():child;if('children'in item)detach(item);}};detach(c);
  for(const t of c.findAll(n=>n.type==='TEXT'))t.fontName={family:zhFamily,style:zhStyles.Regular};
  if(w<600){r77Reflow(c,w);}else{
    const side=c.children[0],main=c.children[1];if(side)r77Reflow(side,216);if(main){main.resize(w-216,h);r77Reflow(main,w-216);}
  }
  if(w<600){const nav=uFind(c,'Mobile / Bottom navigation');if(nav){nav.resize(w,80);nav.children.forEach(t=>{t.layoutSizingHorizontal='FILL';});}}
  if(big)for(const t of c.findAll(n=>n.type==='TEXT'&&typeof n.fontSize==='number'&&n.fontSize<14)){t.fontName={family:zhFamily,style:zhStyles.Regular};t.fontSize=14;t.lineHeight={unit:'PIXELS',value:20};}
  if(edge)for(const t of c.findAll(n=>n.type==='TEXT')){
    if(t.characters==='东京 · 樱花'){r6Copy(t,'日本东京 · 开发环境备用高速节点');t.textAutoResize='TRUNCATE';t.maxLines=1;}
    if(t.characters==='203.0.113.24'){r6Copy(t,'2001:db8:85a3::8a2e:370:7334');t.fontSize=13;t.resize(Math.min(224,t.width),38);t.textAutoResize='HEIGHT';}
  }
  if(w>=600)r77AlignOverview(c);
  if(light)applyLight(c);r77Place(c);return c;
}
function r77Extensions(report){
  for(const n of dsPage.findAll(n=>n.type==='COMPONENT'&&(n.getPluginData('rainlink-review-preview')==='1'||n.name==='验收 · 键盘与弹窗滚动')))n.remove();
  const previews={};
  previews.lightDesktop=r77Preview(registry.desktop.Dashboard,'验收 · 浅色概览 · 1100',1100,900,true).id;
  previews.smallMobile=r77Preview(registry.mobile.Home,'验收 · 小屏浅色 · 360',360,780,true).id;
  previews.largeText=r77Preview(registry.mobile.Home,'验收 · 大字与长名称 IPv6',393,852,false,true,true).id;
  const addLib=r77Libs['M/添加'],keyboard=r77Body('验收 · 键盘与弹窗滚动',393),dialog=addLib.variants['VLESS · 更多'].createInstance().detachInstance();keyboard.setPluginData('rainlink-review-preview','1');add(keyboard,dialog);const scroll=uFind(dialog,'表单滚动区');scroll.primaryAxisSizingMode='FIXED';scroll.resize(scroll.width,200);dialog.primaryAxisSizingMode='AUTO';
  const kb=borderCard('系统键盘占位',393,210,12,10,'Raised');for(const letters of [['Q','W','E','R','T','Y','U','I','O','P'],['A','S','D','F','G','H','J','K','L'],['⇧','Z','X','C','V','B','N','M','⌫']]){const line=center(row('键盘行',369,40,4));for(const s of letters)add(line,center(add(rad(row('键帽',30,40,0,0,'Surface'),5),r77Text(s,14))));add(kb,line);}add(keyboard,kb);r77Place(keyboard);previews.keyboard=keyboard.id;
  return {previews,productFramesAdded:0,sizes:{narrowDesktop:[1100,900],smallMobile:[360,780],largeText:[393,852]},keyboardViewport:200,theme:'real core components with light color bindings',boundary:'Representative reflow previews; runtime layout and OS keyboard behavior still require implementation testing.'};
}
async function r77Wire(){
  const latest=new Map();for(const edge of r77Edges)latest.set(edge.n.id,edge);
  let count=0;for(const edge of latest.values()){if(edge.n.removed)continue;if(typeof edge.to==='string')throw new Error('未解析修复状态 '+edge.to+' / '+r5Name(edge.n));
    let owner=edge.n;while(owner&&owner.type!=='COMPONENT')owner=owner.parent;
    if(edge.nav==='CHANGE_TO'&&owner===edge.to)continue;
    const actions=edge.close?[{type:'CLOSE'}]:[{type:'NODE',destinationId:edge.to.id,navigation:edge.nav,transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false,resetInteractiveComponents:false}];
    try{await edge.n.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions}]);}catch(e){throw new Error(r5Name(edge.n)+' ['+edge.n.id+'] → '+(edge.to?r5Name(edge.to):'关闭')+' ['+edge.nav+']: '+String(e));}count++;if(count%100===0)await r5Yield();
  }return count;
}
function r77LibraryGeometry(){
  const live=new Set(Object.values(r77Libs).map(v=>v.set.id));for(const n of [...r77Section.children])if(n.type==='COMPONENT_SET'&&!live.has(n.id))n.remove();
  for(const lib of Object.values(r77Libs)){
    const cs=lib.set.children,cols=Math.min(3,cs.length),left=Math.max(0,...cs.flatMap(c=>c.children.filter(n=>n.visible&&n.layoutPositioning==='ABSOLUTE').map(n=>-n.x))),w=Math.max(...cs.map(c=>Math.max(c.width,...c.children.filter(n=>n.visible).map(n=>n.x+n.width))))+left,h=Math.max(...cs.map(c=>Math.max(c.height,...c.children.filter(n=>n.visible).map(n=>n.y+n.height))));
    cs.forEach((c,i)=>{c.x=24+left+i%cols*(w+32);c.y=24+Math.floor(i/cols)*(h+40);});lib.set.resize(48+cols*(w+32)-32,48+Math.ceil(cs.length/cols)*(h+40)-40);
  }
  const nodes=[...r77Section.children];r77X=24;r77Y=96;r77H=0;nodes.forEach(r77Place);r77Section.resizeWithoutConstraints(6050,r77Y+r77H+32);
}
async function r77LocalLibraries(report){
  const result={};
  for(const mobile of [false,true]){
    const page=mobile?mobilePage:desktopPage,prefix=mobile?'M/':'D/',name='原型组件 · '+(mobile?'移动端':'桌面端')+' · 局部状态',existing=page.children.find(n=>n.type==='SECTION'&&r5Name(n)===name),section=existing||figma.createSection();
    page.appendChild(section);r6Name(section,name);section.x=10000;section.y=1000;section.fills=[paint('Background')];
    const sets=Object.entries(r77Libs).filter(([k])=>k.startsWith(prefix)).map(([,v])=>v.set);sets.push(await figma.getNodeByIdAsync(report.compactCanvas.homeStates[mobile?'mobile':'desktop'].set));
    let x=24,y=96,h=0;for(const set of sets){if(x+set.width>6000&&x>24){x=24;y+=h+64;h=0;}section.appendChild(set);set.x=x;set.y=y;x+=set.width+48;h=Math.max(h,set.height);}section.resizeWithoutConstraints(6050,y+h+32);result[mobile?'mobile':'desktop']=section.id;
  }return result;
}
async function r77Verify(report){
  const errors=[],check=(ok,msg)=>{if(!ok)errors.push(msg);},scan={};
  check(figma.root.children.length===3,'页签数量改变');check(Object.keys(registry.desktop).length===12&&Object.keys(registry.mobile).length===11,'产品画面数量改变');
  for(const reg of [registry.desktop,registry.mobile])check(Object.values(reg).every(n=>n.layoutMode!=='NONE'),'产品画面缺少 Auto Layout');
  for(const mobile of [false,true]){
    const p=mobile?'M/':'D/',lib=r77Libs[p+'添加'];for(const protocol of R77_PROTOCOLS){check(!!lib.variants[protocol],'缺少协议 '+p+protocol);const selector=uFind(lib.variants[protocol],'协议选择器');check(selector?.reactions.length>0,'协议选择不可用 '+p+protocol);}
    check(lib.variants['获取失败'].findOne(n=>n.type==='INSTANCE'&&r5Name(n)==='按钮 · 重试')?.reactions.length>0,'订阅重试未接入');
    const chain=r77Libs[p+'代理链'];check(uFind(chain.variants['测试通过'],'按钮 · 保存并选中')?.reactions.some(r=>r.actions.some(a=>a.destinationId===chain.variants['已选中'].id)),'代理链没有保存选中反馈');
    check(!registry[mobile?'mobile':'desktop']['Chain editor'].findOne(n=>n.type==='TEXT'&&/保存并连接/.test(n.characters)),'代理链仍自动连接');
  }
  for(const key of ['D/分流规则','D/实时连接','D/流量统计','D/运行日志','M/流量统计'])check(r77Libs[key].initial.findAll(n=>'reactions'in n&&n.reactions.length).length>0,'工具业务未接入 '+key);
  const overviewGrid=[];
  for(const id of [...Object.values(report.reviewFix.homes.desktop.states),report.reviewFix.extensions.previews.lightDesktop]){
    const c=await figma.getNodeByIdAsync(id),metrics=uFind(c,'Network stats')||uFind(c,'Network metrics')||c.findOne(n=>n.name==='网络统计'),trends=uFind(c,'Connection trends');
    if(!metrics||!trends||!metrics.visible||!trends.visible)continue;
    const quality=metrics.children[2],health=trends.children[1],delta=Math.abs(metrics.x+quality.x-trends.x-health.x),widthDelta=Math.abs(quality.width-health.width);
    overviewGrid.push({id,name:c.name,width:metrics.width,gap:trends.itemSpacing,qualityX:metrics.x+quality.x,healthX:trends.x+health.x,delta,widthDelta});
    check(delta<.1&&widthDelta<.1&&metrics.itemSpacing===trends.itemSpacing,'概览右侧卡片未对齐 '+c.name);
  }
  report.reviewFix.overviewGrid={verified:true,states:overviewGrid};
  const small=[];for(const screen of Object.values(registry.mobile))for(const n of screen.findAll(n=>'reactions'in n&&n.reactions.length)){
    let visible=true;for(let a=n;a&&a!==screen;a=a.parent)if(!a.visible)visible=false;if(visible&&(n.width<43.9||n.height<43.9))small.push({id:n.id,name:r5Name(n),width:n.width,height:n.height});
  }
  for(const [p,page]of [['desktop',desktopPage],['mobile',mobilePage],['system',dsPage]]){
    const nodes=[page,...page.findAll(()=>true)],destinations=new Set(),connections=[];for(const n of nodes)if('reactions'in n&&n.reactions.length){connections.push(n);for(const r of n.reactions)for(const a of r.actions||[])if(a.destinationId)destinations.add(a.destinationId);}
    const unresolved=[];for(const id of destinations)if(!(await figma.getNodeByIdAsync(id)))unresolved.push(id);check(!unresolved.length,'存在失效目标 '+p);scan[p]={nodesScanned:nodes.length,connectedNodes:connections.length,unresolved,unscannedScreens:[]};
  }
  report.reviewFixVerification={verifiedAt:new Date().toISOString(),errors,smallMobileTargets:small,prototype:scan,productScreens:23,pageCount:3,protocols:R77_PROTOCOLS};report.livePrototypeVerification={status:'verified',verifiedAt:new Date().toISOString(),...scan};
  if(errors.length)throw new Error(errors.join('；'));
}
function r77AuditDocument(){
  const overflow=[],untranslatedDisplayCopy=[];
  for(const screen of [...Object.values(registry.desktop),...Object.values(registry.mobile)])for(const n of screen.findAll(()=>true)){
    let hidden=false;for(let a=n;a&&a!==screen.parent;a=a.parent)if('visible'in a&&!a.visible){hidden=true;break;}if(hidden)continue;
    if(n.type==='TEXT'&&/[a-zA-Z]{3,}/.test(n.characters)&&!/[\u3400-\u9fff]/.test(n.characters)&&!isTechnicalText(n.characters))untranslatedDisplayCopy.push({id:n.id,text:n.characters});
    if(!['FRAME','INSTANCE'].includes(n.type)||!n.layoutMode||n.layoutMode==='NONE'||n.primaryAxisSizingMode!=='FIXED')continue;
    if(r5Name(n)==='Scrollable content'||/^Icon \/|国家图标/.test(r5Name(n))||n.clipsContent&&n.overflowDirection==='VERTICAL')continue;
    const children=n.children.filter(c=>c.visible&&c.layoutPositioning!=='ABSOLUTE');if(!children.length)continue;
    const vertical=n.layoutMode==='VERTICAL',edge=Math.max(...children.map(c=>vertical?c.y+c.height:c.x+c.width)),size=vertical?n.height:n.width;
    if(edge>size+2)overflow.push({screen:screen.name,id:n.id,name:n.name,axis:vertical?'vertical':'horizontal',amount:Math.round(edge-size)});
  }return {overflow,untranslatedDisplayCopy};
}
async function r77FinalPolish(report){
  const homeHeader=uFind(registry.desktop.Dashboard,'Page header');if(homeHeader)for(const n of homeHeader.children.filter(n=>n.type==='INSTANCE'))if(n.findAll(t=>t.type==='TEXT').some(t=>t.characters==='选择分组'))n.visible=false;
  for(const mobile of [false,true]){
    const home=report.reviewFix.homes[mobile?'mobile':'desktop'],set=await figma.getNodeByIdAsync(home.set);
    if(!mobile&&!home.states['延迟选点']){
      const selected=(await figma.getNodeByIdAsync(home.states['开启'])).clone();set.appendChild(selected);r6Name(selected,'连接=延迟选点');home.states['延迟选点']=selected.id;
      const chart=uFind(selected,'Connection trends')?.children[0];
      if(chart){
        const marker=row('延迟选点指示线',1,82,0,0,'Primary');add(chart,marker);marker.layoutPositioning='ABSOLUTE';marker.x=Math.round(chart.width*.62);marker.y=50;marker.opacity=.5;
        const tip=borderCard('延迟选点浮层',164,null,10,3,'Raised');add(tip,r77Text('10:20',12,'Muted'),r77Text('延迟 24 ms',14,'Primary'),r77Text('抖动 2 ms · 无丢包',12,'Secondary'));add(chart,tip);tip.layoutPositioning='ABSOLUTE';tip.x=Math.min(chart.width-180,Math.round(chart.width*.62)+12);tip.y=38;
        await chart.setReactionsAsync(r7Click(home.states['开启']));
      }
      const plain=await figma.getNodeByIdAsync(home.states['开启']),target=uFind(plain,'Connection trends')?.children[0];if(target)await target.setReactionsAsync(r7Click(selected.id));
      const maxW=Math.max(...set.children.map(n=>n.width)),maxH=Math.max(...set.children.map(n=>n.height));set.children.forEach((n,i)=>{n.x=24+i%2*(maxW+32);n.y=24+Math.floor(i/2)*(maxH+40);});set.resize(48+2*(maxW+32)-32,48+Math.ceil(set.children.length/2)*(maxH+40)-40);
    }
    for(const c of set.children){
      const old=uFind(c,'概览连接详情');if(old)old.remove();
      if(mobile){
        for(const b of c.findAll(n=>n.type==='INSTANCE'&&n.findAll(t=>t.type==='TEXT').some(t=>t.characters==='选择')))if(b.height<44)b.resize(b.width,44);
        if(c.id===home.states['开启']){const summary=uFind(c,'连接状态摘要');if(summary){const text=summary.findOne(n=>n.type==='TEXT'&&/点按关闭/.test(n.characters));if(text)r6Copy(text,'连接详情 ›');if(summary.height<44)summary.resize(summary.width,44);await summary.setReactionsAsync(r7Click(home.states['连接详情']));}}
      }else{
        r77AlignOverview(c);
        c.itemSpacing=6;
        const recent=uFind(c,'最近连接记录');if(recent){recent.resize(recent.width,36);for(const b of recent.children.filter(n=>n.type==='INSTANCE'))b.resize(b.width,36);}
        if(c.id===home.states['开启']){
          const footer=c.findOne(n=>n.type==='FRAME'&&n.children.some(t=>t.type==='TEXT'&&/^当前连接/.test(t.characters)));
          if(footer){const t=footer.children.find(t=>t.type==='TEXT'&&/^当前连接/.test(t.characters)),i=footer.children.indexOf(t);t.remove();const b=r6Button('连接详情 · 24 ms','Ghost',null,180);b.resize(180,36);footer.insertChild(i,b);await b.setReactionsAsync(r7Click(home.states['连接详情']));}
          for(const b of c.findAll(n=>n.name==='按钮 · 连接详情 · 24 ms'))for(const t of b.findAll(n=>n.type==='TEXT'))t.textAutoResize='WIDTH_AND_HEIGHT';
          for(const b of c.findAll(n=>n.name==='按钮 · 连接详情 · 24 ms'))for(const sibling of b.parent.children)if(sibling.type==='TEXT'&&sibling.characters==='24 ms')sibling.visible=false;
        }
      }
      if(c.id===home.states['首次使用']){
        for(const t of c.findAll(n=>n.type==='TEXT')){if(t.characters==='主订阅')r6Copy(t,'尚未选择节点');if(t.characters==='东京 · 樱花')r6Copy(t,'先添加订阅或单个节点');if(t.characters==='点按开启 VPN')r6Copy(t,'添加节点后即可连接');if(t.characters==='VPN 已关闭')r6Copy(t,'尚未就绪');}
        for(const name of mobile?['Connection summary','概览出口与模式','Mobile live speed','Today traffic']:['Network metrics','Connection trends','最近连接记录']){const n=uFind(c,name);if(n)n.visible=false;}
        const emptyOnly=new Set(mobile?['当前连接分组','今日流量','概览出口与模式','实时速度']:['网络统计','网络趋势','最近连接记录','首页网络接管','概览出口与模式']);
        for(const child of c.children)if(emptyOnly.has(child.name))child.visible=false;
        if(!mobile){const footer=c.findOne(n=>n.name==='连接卡片底栏');if(footer)footer.visible=false;}
        const power=c.findOne(n=>n.getPluginData('rainlink-control-kind')==='vpn-power');if(power){power.opacity=.35;await power.setReactionsAsync([]);}
        const platform=uFind(c,'首页平台网络接管');if(platform)for(const t of platform.findAll(n=>n.type==='TEXT'&&n.characters==='已授权'))r6Copy(t,'待授权');
      }
    }
  }
  const traffic=r77Libs['D/流量统计'];for(const c of Object.values(traffic.variants)){
    c.itemSpacing=12;
    for(const m of c.findAll(n=>n.type==='FRAME'&&['总流量','已下载','已上传'].includes(r5Name(n))))m.paddingTop=m.paddingBottom=12;
    const chart=uFind(c,'流量趋势图');if(chart)chart.paddingTop=chart.paddingBottom=16;
    const ranking=uFind(c,'使用排行');if(ranking&&ranking.type!=='TEXT'){ranking.itemSpacing=6;ranking.paddingTop=ranking.paddingBottom=14;}
  }
  const nav=uFind(registry.mobile.Profiles,'Mobile / Bottom navigation');if(nav)for(let i=0;i<nav.children.length;i++)tint(nav.children[i],i===2?'Primary':'Muted');
  for(const key of ['Rules','Connections','Traffic','Logs','Settings','Chain editor']){const content=uFind(registry.desktop[key],'Content');if(content){content.clipsContent=true;content.overflowDirection='VERTICAL';}}
  for(const id of Object.values(report.reviewFix.extensions.previews)){const c=await figma.getNodeByIdAsync(id);if(!c)continue;const head=uFind(c,'Page header');if(head)for(const b of head.children.filter(n=>n.type==='INSTANCE'))if(b.findAll(t=>t.type==='TEXT').some(t=>t.characters==='选择分组'))b.visible=false;for(const b of c.findAll(n=>n.name==='按钮 · 连接详情 · 24 ms'))for(const sibling of b.parent.children)if(sibling.type==='TEXT'&&sibling.characters==='24 ms')sibling.visible=false;}
  report.reviewFix.finalPolish='9';
}
async function r77ReviewFixMain(){
  figma.showUI('<body style="padding:24px;background:#151617;color:#c0c2c8;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#8adcbf">RainLink / 修复已知问题</h2><p id="s">载入现有设计…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:520,height:200});
  await r77Initialize();figma.skipInvisibleInstanceChildren=false;await r71Palette();const report=JSON.parse(figma.root.getPluginData('rainlink-report'));
  if(report.reviewFix?.revision===R77_REV&&report.reviewFix.finalPolish==='9'&&!report.reviewFixBuildError&&report.reviewFixVerification&&!report.reviewFixVerification.errors.length){figma.notify('本次修复已应用');figma.closePlugin();return;}
  // Persist each completed phase so retries do not recreate the whole library.
  let checkpoint;try{checkpoint=JSON.parse(figma.root.getPluginData('rainlink-review-checkpoint'));}catch(e){}
  if(checkpoint?.chunks){let value='';for(let i=0;i<checkpoint.chunks;i++)value+=figma.root.getPluginData('rainlink-review-checkpoint-'+i);checkpoint=JSON.parse(value);}
  if(checkpoint?.schema===2&&checkpoint.revision===R77_REV)r77Section=await figma.getNodeByIdAsync(checkpoint.section);
  if(r77Section){
    if(!['8','9'].includes(report.reviewFix?.finalPolish))delete checkpoint.completed['浅色与边界预览'];
    for(const [key,lib]of Object.entries(checkpoint.libraries)){
      const set=await figma.getNodeByIdAsync(lib.set),variants={};for(const [name,id]of Object.entries(lib.states))variants[name]=await figma.getNodeByIdAsync(id);
      r77Libs[key]={set,variants,initial:await figma.getNodeByIdAsync(lib.initial)};
    }
    for(const e of checkpoint.edges){const n=await figma.getNodeByIdAsync(e.node),to=e.destination?(e.named?e.destination:await figma.getNodeByIdAsync(e.destination)):undefined;if(n)r77Edges.push({n,to,nav:e.nav,close:e.close});}
  }else{
    for(const n of [...dsPage.children])if(r5Name(n)==='评估修复 · 组件与验收')n.remove();
    r77Section=figma.createSection();dsPage.appendChild(r77Section);r6Name(r77Section,'评估修复 · 组件与验收');r77Section.x=12000;r77Section.y=1000;r77Section.fills=[paint('Background')];
    checkpoint={schema:2,revision:R77_REV,section:r77Section.id,completed:{}};
  }
  const libraries=()=>Object.fromEntries(Object.entries(r77Libs).map(([k,v])=>[k,{set:v.set.id,initial:v.initial.id,states:Object.fromEntries(Object.entries(v.variants).map(([s,c])=>[s,c.id]))}]));
  const remember=()=>{checkpoint.libraries=libraries();checkpoint.edges=r77Edges.filter(e=>!e.n.removed).map(e=>({node:e.n.id,destination:typeof e.to==='string'?e.to:e.to?.id,named:typeof e.to==='string',nav:e.nav,close:e.close}));const value=JSON.stringify(checkpoint),chunks=Math.ceil(value.length/20000);for(let i=0;i<chunks;i++)figma.root.setPluginData('rainlink-review-checkpoint-'+i,value.slice(i*20000,(i+1)*20000));figma.root.setPluginData('rainlink-review-checkpoint',JSON.stringify({chunks}));};
  const step=async(name,fn)=>{if(Object.prototype.hasOwnProperty.call(checkpoint.completed,name))return checkpoint.completed[name];figma.ui.postMessage({status:name+'…'});await r5Yield();const value=await fn();checkpoint.completed[name]=value===undefined?true:value;remember();return value;};
  const save=()=>{figma.root.setPluginData('rainlink-report',JSON.stringify(report));const text=uFind(dsPage,'Delivery / Native audit');text.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);text.setPluginData('rainlink-original-text','');text.visible=false;};
  try{
    for(const mobile of [false,true]){const prefix=mobile?'移动端':'桌面端';await step(prefix+'多协议弹窗',async()=>{await r77Add(mobile);});await step(prefix+'订阅管理',async()=>{await r77Groups(mobile);});await step(prefix+'代理链',async()=>{await r77Chain(mobile);});await step(prefix+'节点操作',async()=>{await r77NodeActions(mobile);});}
    await step('分流规则',async()=>{await r77Rules();});await step('实时连接',async()=>{await r77Connections();});await step('桌面流量',async()=>{await r77Traffic(false);});await step('移动流量',async()=>{await r77Traffic(true);});await step('运行日志',async()=>{await r77Logs();});
    await step('移动平台能力',async()=>{await r77PlatformControls();});const homes=await step('连接异常与授权',()=>r77Homes(report,r77Libs['M/平台网络能力'])),consistency=await step('统一状态与导航',()=>r77Consistency(report));
    const accessibility=await step('字号与命中区域',()=>r77ReadableAndHits(report)),localLibraries=await step('页内原型组件',()=>r77LocalLibraries(report)),routeCount=await step('连接全部操作',()=>r77Wire()),extensions=await step('浅色与边界预览',()=>r77Extensions(report)),contractId=await step('交付约定',()=>r77Contract().id);r77LibraryGeometry();
    const connectionTerminology=report.reviewFix?.connectionTerminology;
    report.reviewFix={revision:R77_REV,screensAdded:0,section:r77Section.id,localLibraries,routeCount,homes,consistency,accessibility,extensions,contract:contractId,libraries:libraries(),connectionTerminology};
    await r77FinalPolish(report);await r79RemoveVpnCopy(report);remember();
    await r77Verify(report);const audit=r77AuditDocument();report.overflow=audit.overflow;report.untranslatedDisplayCopy=audit.untranslatedDisplayCopy;report.counts.components=[desktopPage,mobilePage,dsPage].reduce((s,p)=>s+p.findAll(n=>n.type==='COMPONENT').length,0);report.counts.instances=[desktopPage,mobilePage,dsPage].reduce((s,p)=>s+p.findAll(n=>n.type==='INSTANCE').length,0);delete report.nativeBackup;delete report.screenshotVerification;delete report.reviewFixBuildError;save();
  }catch(e){report.reviewFixBuildError=String(e)+'\n'+String(e.stack||'');save();throw e;}
  await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Dashboard];figma.viewport.scrollAndZoomIntoView(figma.currentPage.selection);figma.notify('已修复评估中的流程与交互问题 · 保持 23 个产品画面');figma.closePlugin();
}
