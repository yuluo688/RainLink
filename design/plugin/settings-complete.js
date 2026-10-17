// RainLink 7.5 — complete settings inside the existing product frames.
// Native component variants demonstrate UI states; no OS/network action is run.
const R75_UI='设置工作区';
const R75_REVISION='4';
let r75Section,r75ShelfX=32,r75ShelfY=104,r75ShelfH=0;
const r75Libraries={};
function r75Mark(n){n.setPluginData('rainlink-settings-version','7.5');return n;}
function r75Place(n){
  if(r75ShelfX+n.width>5000&&r75ShelfX>32){r75ShelfY+=r75ShelfH+64;r75ShelfX=32;r75ShelfH=0;}
  r75Section.appendChild(n);n.x=r75ShelfX;n.y=r75ShelfY;r75ShelfX+=n.width+48;r75ShelfH=Math.max(r75ShelfH,n.height);return n;
}
function r75Set(name,variants,columns=3){
  const set=r7VariantSet(name,Object.values(variants),columns);r75Mark(set);for(const c of Object.values(variants))r75Mark(c);if(Object.keys(variants).some(k=>k.endsWith(' · 展开')))r75ChoiceGeometry(set);r75Place(set);return {set,variants};
}
function r75ChoiceGeometry(set){
  const cs=set.children,cols=Math.min(3,cs.length),w=Math.max(...cs.map(c=>c.width)),h=Math.max(...cs.map(c=>Math.max(c.height,...c.children.map(n=>n.y+n.height))));
  cs.forEach((c,i)=>{c.x=24+(i%cols)*(w+32);c.y=24+Math.floor(i/cols)*(h+40);});
  set.resize(48+cols*(w+32)-32,48+Math.ceil(cs.length/cols)*(h+40)-40);set.clipsContent=false;
}
async function r75RefreshChoiceLayouts(ui,section){
  for(const lib of Object.values(ui.controls))if(Object.keys(lib.states).some(k=>k.endsWith(' · 展开')))r75ChoiceGeometry(await figma.getNodeByIdAsync(lib.set));
  r75Section=section;r75ShelfX=32;r75ShelfY=104;r75ShelfH=0;
  for(const n of [...section.children])if(r5Name(n)!=='设置组件库说明')r75Place(n);
  section.resizeWithoutConstraints(5032,r75ShelfY+r75ShelfH+32);ui.choiceMenus='Full dropdown bounds reserved in component library';
}
function r75Text(s,size=13,color='Text',weight='Regular',w=null){return r6Text(s,size,color,weight,w);}
function r75Body(name,w){const c=r7Body(name,w);r75Mark(c);c.itemSpacing=12;return c;}
function r75Copy(title,desc,w,size=14){return add(r6Name(v('设置文案',w,3),'设置文案'),r6Name(r75Text(title,size,'Text','Medium',w),'设置项标题'),desc?r6Name(r75Text(desc,11,'Muted','Regular',w),'设置项说明'):null);}
function r75Card(title,mobile){const w=mobile?353:912,p=mobile?16:20,n=r6Name(borderCard(title,w,null,p,0,'Surface'),title);return {n,w:w-p*2-2};}
function r75Heading(body,title,desc,mobile){add(body,r75Text(title,mobile?20:22,'Text','Medium',mobile?353:912),desc?r75Text(desc,12,'Muted','Regular',mobile?353:912):null);}
function r75Button(label,tone='Secondary',ic=null,w=null){const b=r6Button(label,tone,ic,w);return r75Mark(b);}
function r75BackMaster(){
  const c=component('Icon / 返回',n=>{n.resize(24,24);n.layoutMode='HORIZONTAL';n.primaryAxisSizingMode=n.counterAxisSizingMode='FIXED';const svg=figma.createNodeFromSvg('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#c0c2c8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m15 5-7 7 7 7"/></svg>');add(n,svg);});
  r6Name(c,'Icon / 返回');r75Place(r75Mark(c));icons['返回']=c;
}
function r75Route(n,view){n.setPluginData('rainlink-settings-route',view);return n;}
function r75Item(title,desc,w,right=null,mobile=false){
  const n=r6Name(row('设置项 · '+title,w,mobile?56:60,12),'设置项 · '+title),copy=r75Copy(title,desc,Math.max(80,w-(right?right.width:0)-12),mobile?13:14);
  add(n,copy,right);return n;
}
function r75Rows(card,rows){rows.forEach((r,i)=>{if(i)add(card.n,divider(card.w));add(card.n,r);});return card.n;}
function r75Note(title,desc,w,tone='Info'){const p=14,n=r6Name(borderCard(title,w,null,p,6,tone==='Success'?'PrimarySurface':tone+'Surface'),title);stroke(n,tone,.5);add(n,r75Text(title,12,tone,'Medium',w-p*2-2),r75Text(desc,11,'Secondary','Regular',w-p*2-2));return n;}

async function r75ToggleLibrary(mobile){
  const platform=mobile?'移动端':'桌面端',w=mobile?319:420,variants={};
  for(const on of [true,false]){
    const c=r75Body('状态='+(on?'开启':'关闭'),w);c.resize(w,56);c.primaryAxisSizingMode='FIXED';c.layoutMode='HORIZONTAL';c.counterAxisAlignItems='CENTER';c.itemSpacing=12;
    const copy=r75Copy('设置项目','简短说明',w-56,mobile?13:14);add(c,copy);copy.layoutSizingHorizontal='FILL';
    const hit=center(r6Name(row('设置开关命中区',44,44),'设置开关命中区'));add(hit,sw(on));add(c,hit);variants[on?'on':'off']=c;
  }
  const lib=r75Set('设置 / '+platform+' / 开关行',variants,2);
  for(const [key,c]of Object.entries(variants))await uFind(c,'设置开关命中区').setReactionsAsync(r7Click(variants[key==='on'?'off':'on'].id));
  r75Libraries['toggle'+mobile]=lib;return lib;
}
function r75Toggle(title,desc,w,mobile,on=false){
  const n=r7Instance(r75Libraries['toggle'+mobile].variants[on?'on':'off'],'设置项 · '+title);n.resize(w,56);
  r6Copy(uFind(n,'设置项标题'),title);r6Copy(uFind(n,'设置项说明'),desc);return n;
}
async function r75ChoiceLibrary(key,values,mobile){
  const name='设置 / '+(mobile?'移动端':'桌面端')+' / '+key,w=mobile?148:192,h=mobile?44:36,variants={};
  for(const value of values)for(const open of [false,true]){
    const state=value+(open?' · 展开':''),c=r75Body('选项='+state,w);c.resize(w,h);c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.itemSpacing=0;
    const face=rad(r6Name(row('选择器按钮',w,h,8,10,'Raised'),'选择器按钮'),8);stroke(face);const t=r6Name(r75Text(value,12,'Secondary'),'选择器值');add(face,t);t.layoutSizingHorizontal='FILL';add(face,icon('down',14,'Muted'));add(c,face);
    if(open){
      const menu=borderCard('选择器菜单',w,null,4,2,'Raised');r6Name(menu,'选择器菜单');add(c,menu);menu.layoutPositioning='ABSOLUTE';menu.x=0;menu.y=h+4;
      for(const item of values){const optionRow=between(r6Name(row('选项 · '+item,w-10,mobile?44:36,6,8,item===value?'PrimarySurface':null),'选项 · '+item));add(optionRow,r75Text(item,12,item===value?'Primary':'Secondary'),item===value?icon('check',14,'Primary'):null);rad(optionRow,6);add(menu,optionRow);}
    }
    variants[state]=c;
  }
  const lib=r75Set(name,variants,Math.min(3,Object.keys(variants).length));
  for(const value of values){
    const closed=variants[value],opened=variants[value+' · 展开'];
    await uFind(closed,'选择器按钮').setReactionsAsync(r7Click(opened.id));
    await uFind(opened,'选择器按钮').setReactionsAsync(r7Click(closed.id));
    for(const item of values)await uFind(opened,'选项 · '+item).setReactionsAsync(r7Click(variants[item].id));
  }
  lib.defaultValue=values[0];
  r75Libraries[key+mobile]=lib;return lib;
}
function r75Choice(key,mobile,value=null){const lib=r75Libraries[key+mobile];return r7Instance(lib.variants[value||lib.defaultValue],'设置选择器 · '+key);}
async function r75ThemeLibrary(mobile){
  const w=mobile?319:870,variants={},options=['跟随系统','深色','浅色'];
  for(const selected of options){
    const c=r75Body('主题='+selected,w),tiles=row('主题选项',w,112,8);add(c,tiles);
    for(const option of options){
      const tw=(w-16)/3,card=borderCard('主题 · '+option,tw,112,8,8,selected===option?'PrimarySurface':'Raised');stroke(card,selected===option?'Primary':'Stroke');r6Name(card,'主题 · '+option);
      const dark=option!=='浅色',preview=rad(row('主题预览',tw-18,54,4,6,dark?'Background':'#FAFAFA'),5),side=rad(v('预览侧栏',Math.max(12,tw*.18),3,3,dark?'Raised':'#E4E4E7'),3),lines=v('预览内容',tw*.53,4);
      side.resize(Math.max(12,tw*.18),40);side.primaryAxisSizingMode='FIXED';
      add(lines,rad(row('预览标题',tw*.42,5,0,0,dark?'Secondary':'#55585F'),2),rad(row('预览条目',tw*.5,12,0,0,dark?'PrimarySurface':'#E7F5EE'),3),rad(row('预览辅助',tw*.4,5,0,0,dark?'Stroke':'#E4E4E7'),2));add(preview,side,lines);
      const bottom=between(row('主题标签',tw-18,24,4));add(bottom,r75Text(option,12,selected===option?'Primary':'Secondary'),selected===option?icon('check',14,'Primary'):null);add(card,preview,bottom);add(tiles,card);
    }
    add(c,r75Text('当前：'+selected+(selected==='跟随系统'?' · 随系统切换外观':''),11,'Muted'));variants[selected]=c;
  }
  const lib=r75Set('设置 / '+(mobile?'移动端':'桌面端')+' / 主题',variants,3);
  for(const [value,c]of Object.entries(variants))for(const option of options)if(option!==value)await uFind(c,'主题 · '+option).setReactionsAsync(r7Click(variants[option].id));
  r75Libraries['theme'+mobile]=lib;return lib;
}
async function r75DNSLibrary(mobile){
  const outer=mobile?353:912,pad=mobile?16:20,w=outer-pad*2-2,variants={},states=['加密 DNS','系统 DNS','自定义 DNS','测试中','测试通过','已保存','地址错误'];
  for(const state of states){
    const c=r75Body('状态='+state,outer);c.paddingLeft=c.paddingRight=pad;c.paddingTop=c.paddingBottom=pad;fill(c,'Surface');stroke(c);rad(c,12);c.itemSpacing=12;
    const mode=state==='系统 DNS'?state:state==='自定义 DNS'?state:'加密 DNS',tabs=row('DNS 模式选项',w,mobile?44:36,4);
    for(const name of ['加密 DNS','系统 DNS','自定义 DNS']){const t=center(rad(r6Name(row('DNS 模式 · '+name,(w-8)/3,mobile?44:36,0,0,name===mode?'PrimarySurface':'Raised'),'DNS 模式 · '+name),7));add(t,r75Text(name,12,name===mode?'Primary':'Secondary'));add(tabs,t);}add(c,tabs);
    if(state==='系统 DNS')add(c,r75Note('使用系统解析器','使用设备当前网络提供的 DNS，切换网络时自动更新。',w));
    else{
      const fields=mobile?v('DNS 解析器',w,12):row('DNS 解析器',w,null,16);
      const fw=mobile?w:(w-16)/2,first=r6Field('首选解析器',state==='地址错误'?'http://':state==='自定义 DNS'?'tls://1.1.1.1':'https://dns.google/dns-query',fw),second=r6Field('备用解析器','https://cloudflare-dns.com/dns-query',fw);
      for(const f of [first,second]){const input=uFind(f,'Input / Default');if(input){input.resize(fw,44);const text=uFind(input,'Value');if(text)text.fontSize=mobile?11:12;}}
      if(state==='地址错误'){const input=first.findOne(n=>n.type==='INSTANCE');stroke(input,'Error');add(first,r75Text('请输入完整的解析器地址',11,'Error','Regular',fw));}
      add(fields,first,second);add(c,fields,r75Text(state==='自定义 DNS'?'支持 HTTPS、TLS 或 IP 地址。':'通过 HTTPS 加密解析请求。',11,'Muted','Regular',w));
    }
    const actions=between(row('DNS 操作',w,44,8));add(actions,r6Name(r75Button(state==='测试中'?'测试中…':'测试解析','Secondary','globe',mobile?120:124),'测试 DNS'),r6Name(r75Button('保存设置','Primary',null,mobile?147:124),'保存 DNS'));add(c,actions);
    if(state==='地址错误')for(const action of actions.children)action.opacity=.4;
    if(['测试中','测试通过','已保存','地址错误'].includes(state))add(c,r75Note(state==='测试中'?'正在解析 example.com':state==='测试通过'?'解析成功 · 28 ms':state==='已保存'?'DNS 设置已保存':'解析器地址不完整',state==='测试中'?'请稍候…':state==='测试通过'?'首选解析器可用，备用解析器待命。':state==='已保存'?'新建连接将使用当前设置。':'补全地址后再保存。',w,state==='地址错误'?'Error':state==='测试中'?'Info':'Success'));
    variants[state]=c;
  }
  const lib=r75Set('设置 / '+(mobile?'移动端':'桌面端')+' / DNS 解析',variants,mobile?3:2);
  for(const [state,c]of Object.entries(variants)){
    for(const mode of ['加密 DNS','系统 DNS','自定义 DNS'])if(mode!==state)await uFind(c,'DNS 模式 · '+mode).setReactionsAsync(r7Click(variants[mode].id));
    if(!['测试中','地址错误'].includes(state))await uFind(c,'测试 DNS').setReactionsAsync(r7Click(variants['测试中'].id));
    if(!['已保存','地址错误'].includes(state))await uFind(c,'保存 DNS').setReactionsAsync(r7Click(variants['已保存'].id));
    if(state==='测试中')await c.setReactionsAsync(r7Timer(variants['测试通过'].id));
  }
  r75Libraries['dns'+mobile]=lib;return lib;
}
async function r75EngineLibrary(mobile){
  const outer=mobile?353:912,variants={};
  for(const state of ['运行中','确认重启','重启中','已重启']){
    const {n:c,w}=r75Card('核心状态',mobile),master=r75Body('状态='+state,outer);for(const child of [...c.children])child.remove();
    const title=between(row('引擎身份',w,48,12));add(title,add(row('引擎名称',null,48,12),miniIcon('terminal','Primary',40,'PrimarySurface'),r75Copy('sing-box','核心版本 1.12.0',mobile?144:360)),r6Badge(state==='重启中'?'重启中':'运行中',state==='重启中'?'Warning':'Success'));add(c,title,space(14));
    if(state==='确认重启')add(c,r75Note('重新启动核心引擎？','当前连接会短暂中断，完成后恢复。',w,'Warning'),space(12),add(row('重启确认操作',w,44,8),r6Name(r75Button('取消','Secondary',null,mobile?100:120),'取消重启'),r6Name(r75Button('确认重启','Primary','refresh',mobile?180:140),'确认重启')));
    else{
      const bar=between(row('引擎操作',w,44,8));add(bar,r75Text(state==='已重启'?'重启完成，配置已重新载入。':state==='重启中'?'正在重新载入配置…':'独立管理核心与日志。',11,state==='已重启'?'Primary':'Muted','Regular',mobile?170:520),r6Name(r75Button(state==='重启中'?'重启中…':'重启核心','Secondary','refresh',mobile?124:128),'重启核心'));add(c,bar);
    }
    add(master,c);variants[state]=master;
  }
  const lib=r75Set('设置 / '+(mobile?'移动端':'桌面端')+' / 核心状态',variants,2);
  for(const state of ['运行中','已重启'])await uFind(variants[state],'重启核心').setReactionsAsync(r7Click(variants['确认重启'].id));
  await uFind(variants['确认重启'],'取消重启').setReactionsAsync(r7Click(variants['运行中'].id));await uFind(variants['确认重启'],'确认重启').setReactionsAsync(r7Click(variants['重启中'].id));await variants['重启中'].setReactionsAsync(r7Timer(variants['已重启'].id));
  r75Libraries['engine'+mobile]=lib;return lib;
}
async function r75UpdateLibrary(mobile){
  const outer=mobile?353:912,variants={},states=mobile?['待检查','检查中','已是最新','发现更新','商店更新','检查失败']:['待检查','检查中','已是最新','发现更新','下载中','等待重启','确认更新','更新完成','检查失败'];
  for(const state of states){
    const card=r75Card('应用更新',mobile),c=r75Body('状态='+state,outer),available=['发现更新','下载中','等待重启'].includes(state);
    add(card.n,between(add(row('应用版本',card.w,52,12),add(row('版本标识',null,52,12),instance('Brand / Mark'),r75Copy('RainLink '+(['已是最新','更新完成'].includes(state)?'1.1.0':'1.0.0'),'当前版本 · 稳定版',mobile?174:450)),!mobile?r6Badge(available?'发现更新':state==='检查中'?'检查中':'当前版本',available?'Success':'Neutral'):null)),space(16));
    add(card.n,r75Text(state==='待检查'?'随时获取新功能与修复。':state==='检查中'?'正在检查更新…':state==='已是最新'?'当前已是最新版本':state==='检查失败'?'暂时无法检查更新':state==='等待重启'?'更新已准备就绪':state==='商店更新'?'在 App Store 中完成更新':state==='确认更新'?'重启 RainLink 并更新？':state==='更新完成'?'更新完成':'RainLink 1.1.0 可用',mobile?14:18,state==='检查失败'?'Error':'Text','Medium',card.w),space(8));
    if(available)add(card.n,r75Text('改进节点筛选、连接稳定性与使用体验。',12,'Muted','Regular',card.w),space(12));
    if(state==='检查失败')add(card.n,r75Text('检查网络连接后重试。',12,'Muted','Regular',card.w),space(12));
    if(state==='下载中'){const track=rad(row('下载进度',card.w,4,0,0,'Stroke'),2);add(track,rad(row('已下载',card.w*.64,4,0,0,'Primary'),2));add(card.n,track,space(12),r75Text('正在下载 · 64%',11,'Primary'),space(12));}
    if(state==='商店更新')add(card.n,r75Text('打开 App Store，进入账户页查看可用更新。',12,'Secondary','Regular',card.w),space(12));
    if(state==='确认更新')add(card.n,r75Note('当前连接会短暂中断','重启完成后恢复上次选择的连接。',card.w,'Warning'),space(12));
    const label=state==='检查中'?'检查中…':state==='发现更新'?(mobile?'前往 App Store':'下载更新'):state==='下载中'?'正在下载…':state==='等待重启'?'重启并更新':state==='确认更新'?'确认重启':state==='商店更新'?'知道了':state==='更新完成'?'完成':state==='检查失败'?'重试':'检查更新';
    const b=r6Name(r75Button(label,available?'Primary':'Secondary',state==='发现更新'?'download':'refresh',mobile?card.w:156),'更新操作');add(card.n,b);
    if(mobile&&state==='发现更新')add(card.n,space(8),r75Text('通过 App Store 完成更新。',11,'Muted','Regular',card.w));
    if(state==='等待重启')add(card.n,space(8),r75Text('重启会短暂中断当前连接。',11,'Muted','Regular',card.w));
    if(state==='确认更新')add(card.n,space(8),r6Name(r75Button('暂不重启','Ghost',null,mobile?card.w:156),'取消更新重启'));
    add(card.n,space(12),r75Text(state==='待检查'?'上次检查：尚未检查':'上次检查：刚刚',11,'Muted','Regular',card.w));
    add(c,card.n);variants[state]=c;
  }
  const lib=r75Set('设置 / '+(mobile?'移动端':'桌面端')+' / 应用更新',variants,2);
  for(const state of ['待检查','已是最新','检查失败'])await uFind(variants[state],'更新操作').setReactionsAsync(r7Click(variants['检查中'].id));
  await variants['检查中'].setReactionsAsync(r7Timer(variants['发现更新'].id));
  if(!mobile){await uFind(variants['发现更新'],'更新操作').setReactionsAsync(r7Click(variants['下载中'].id));await variants['下载中'].setReactionsAsync(r7Timer(variants['等待重启'].id));await uFind(variants['等待重启'],'更新操作').setReactionsAsync(r7Click(variants['确认更新'].id));await uFind(variants['确认更新'],'更新操作').setReactionsAsync(r7Click(variants['更新完成'].id));await uFind(variants['确认更新'],'取消更新重启').setReactionsAsync(r7Click(variants['等待重启'].id));await uFind(variants['更新完成'],'更新操作').setReactionsAsync(r7Click(variants['已是最新'].id));}
  else{await uFind(variants['发现更新'],'更新操作').setReactionsAsync(r7Click(variants['商店更新'].id));await uFind(variants['商店更新'],'更新操作').setReactionsAsync(r7Click(variants['待检查'].id));}
  r75Libraries['updates'+mobile]=lib;return lib;
}
function r75LinkRow(title,desc,view,w,mobile){const control=center(row('打开设置详情',mobile?28:36,44));add(control,icon('chevron',16,'Muted'));return r75Route(r75Item(title,desc,w,control,mobile),view);}
function r75PageIntro(c,title,desc,mobile){if(mobile)add(c,r76DetailHeader(title,desc,true,'首页'));else r75Heading(c,title,desc,false);}
function r75General(c,mobile){
  r75PageIntro(c,'通用','管理启动、窗口与通知偏好。',mobile);const a=r75Card('启动与行为',mobile);
  add(c,r75Rows(a,[r75Toggle('开机启动','系统启动后运行 RainLink',a.w,mobile,true),r75Toggle('启动时自动连接','恢复上次选择的分组与节点',a.w,mobile,false),r75Item('关闭窗口时','选择主窗口关闭后的行为',a.w,r75Choice('关闭行为',mobile),mobile)]));
  const b=r75Card('通知与语言',mobile);add(c,r75Rows(b,[r75Toggle('连接状态通知','连接变化与订阅到期时提醒',b.w,mobile,true),r75Toggle('显示托盘或菜单栏图标','从系统栏快速访问 RainLink',b.w,mobile,true),r75Item('界面语言','默认使用简体中文',b.w,r75Choice('语言',mobile),mobile)]));
}
function r75Appearance(c,mobile){
  r75PageIntro(c,'外观与语言','选择适合你的界面风格。',mobile);const a=r75Card('主题设置',mobile);add(a.n,r75Text('主题',13,'Secondary','Medium'),space(12),r7Instance(r75Libraries['theme'+mobile].variants['深色'],'主题选择'));add(c,a.n);
  const b=r75Card('显示偏好',mobile),rows=[r75Item('界面密度','调整列表和控件的留白',b.w,r75Choice('密度',mobile),mobile),r75Item('文字大小',null,b.w,r75Choice('文字',mobile),mobile),r75Toggle('减少动效','简化界面过渡动画',b.w,mobile,false)];
  if(mobile)rows.push(r75Item('界面语言',null,b.w,r75Choice('语言',mobile),mobile));add(c,r75Rows(b,rows));
}
function r75Network(c,mobile){
  r75PageIntro(c,'网络','管理解析方式与连接选项。',mobile);
  if(mobile){const a=r75Card('解析与连接',true);add(c,r75Rows(a,[r75LinkRow('DNS 解析','加密 DNS · 自动选择备用解析器','@DNS',a.w,true),r75Toggle('IPv6','允许通过 IPv6 建立连接',a.w,true,true),r75Toggle('DNS 缓存','复用近期解析结果',a.w,true,true)]));const b=r75Card('本地监听',true);add(c,r75Rows(b,[r75Item('混合端口','HTTP / SOCKS5',b.w,r75Choice('端口',true),true),r75Toggle('允许局域网连接','让同一网络设备使用本地代理',b.w,true,false)]));}
  else{add(c,r7Instance(r75Libraries['dnsfalse'].variants['加密 DNS'],'DNS 设置'));const a=r75Card('连接选项',false);add(c,r75Rows(a,[r75Toggle('IPv6','允许通过 IPv6 建立连接',a.w,false,true),r75Item('混合端口','HTTP / SOCKS5 本地监听',a.w,r75Choice('端口',false),false),r75Toggle('允许局域网连接','让同一网络设备使用本地代理',a.w,false,false)]));}
}
function r75Core(c,mobile){
  r75PageIntro(c,'核心引擎','查看引擎状态与高级选项。',mobile);add(c,r7Instance(r75Libraries['engine'+mobile].variants['运行中'],'核心重启交互'));
  const a=r75Card('引擎偏好',mobile);add(c,r75Rows(a,[r75Item('日志级别','调整事件记录的详细程度',a.w,r75Choice('日志',mobile),mobile),r75LinkRow('高级配置','查看与编辑 YAML / JSON','高级配置',a.w,mobile)]));
  add(c,r75Note('配置变更需要确认应用','保留当前可用配置，校验通过后再重新载入。',mobile?353:912));
}
function r75Updates(c,mobile){
  r75PageIntro(c,'更新','管理应用版本与更新渠道。',mobile);add(c,r7Instance(r75Libraries['updates'+mobile].variants['待检查'],'应用更新交互'));
  const a=r75Card('更新偏好',mobile);add(c,r75Rows(a,[r75Toggle('自动检查更新','发现新版本时通知',a.w,mobile,true),r75Item('更新渠道',mobile?'安装渠道管理更新':'选择接收版本的范围',a.w,mobile?r75Text('App Store',12,'Secondary'):r75Choice('渠道',false),mobile)]));
}
function r75About(c,mobile){
  r75PageIntro(c,'关于 RainLink','跨平台多协议网络客户端。',mobile);const a=r75Card('产品信息',mobile),brand=row('关于品牌',a.w,64,12);add(brand,instance('Brand / Mark'),r75Copy('RainLink','版本 1.0.0 · 稳定版',a.w-56,18));add(a.n,brand,space(12),divider(a.w),r75Item('核心版本',null,a.w,r75Text('sing-box 1.12.0',12,'Secondary'),mobile),divider(a.w),r75Item('界面语言',null,a.w,r75Text('简体中文',12,'Primary'),mobile));add(c,a.n);
  const b=r75Card('说明与许可',mobile);add(c,r75Rows(b,[r75LinkRow('隐私说明','了解本地数据与网络请求','隐私说明',b.w,mobile),r75LinkRow('第三方开源许可','查看使用的开源组件','开源许可',b.w,mobile)]));
}
function r75LegalHeader(mobile,privacy){
  const w=mobile?353:912,header=r6Name(row('关于详情导航',w,52,4),'关于详情导航');
  const back=r75Route(r76BackIcon(r75Button('','Ghost','返回',44),'返回关于箭头'),'关于');
  add(header,back,r75Copy(privacy?'隐私说明':'第三方开源许可',privacy?'清晰了解数据的使用方式。':'感谢开源社区。',w-48,mobile?20:22));return header;
}
function r75Legal(c,mobile,privacy){
  add(c,r75LegalHeader(mobile,privacy));const a=r75Card(privacy?'数据说明':'依赖与许可',mobile);
  const items=privacy?[['本地保存','节点、订阅地址与个人偏好保存在本机。'],['必要的网络请求','订阅更新、DNS 解析与公网出口检测会访问相应服务。'],['诊断日志','导出前可查看内容并移除敏感信息。']]:[['sing-box','网络核心 · GPL-3.0-or-later'],['第三方依赖','各组件保留原作者与许可信息。'],['许可声明','开源组件各自保留版权声明与许可条款。']];
  for(const [i,[title,desc]]of items.entries()){if(i)add(a.n,space(16),divider(a.w),space(16));add(a.n,r75Text(title,14,'Text','Medium',a.w),space(6),r75Text(desc,12,'Secondary','Regular',a.w));}add(c,a.n);
}
async function r75RefreshLegalBack(ui){
  for(const [platform,mobile]of [['desktop',false],['mobile',true]])for(const name of ['隐私说明','开源许可']){
    const c=await figma.getNodeByIdAsync(ui[platform].variants[name]),body=mobile?c:uFind(c,'设置详情');
    let header=uFind(body,'关于详情导航');
    if(!header){const card=body.children.find(n=>r5Name(n)===(name==='隐私说明'?'数据说明':'依赖与许可'));if(!card)throw new Error(platform+' '+name+' 详情卡缺失');for(const n of [...body.children])if(n!==card)n.remove();header=r75LegalHeader(mobile,name==='隐私说明');body.insertChild(0,header);}
    header.resize(mobile?353:912,52);header.itemSpacing=4;const back=r76BackIcon(uFind(header,'返回关于箭头'),'返回关于箭头');await back.setReactionsAsync(r7Click(ui[platform].variants['关于']));
  }
  ui.legalBackNavigation='top-left-arrow';
}
function r75Advanced(c,mobile,state='YAML'){
  add(c,r76DetailHeader('高级配置','校验后应用，出错时保留当前配置。',mobile,'核心引擎'));const a=r75Card('配置编辑器',mobile),format=state==='JSON'?'JSON':'YAML';
  const tabs=row('配置格式',a.w,44,8);for(const name of ['YAML','JSON']){const b=r75Route(r75Button(name,format===name?'Primary':'Secondary',null,84),'配置'+name);add(tabs,b);}add(a.n,tabs,space(12));
  const code=state==='错误'?'dns:\n  servers: [':format==='JSON'?'{\n  "log": { "level": "info" },\n  "dns": {\n    "servers": [\n      { "type": "https",\n        "server": "dns.google" }\n    ]\n  }\n}':'# RainLink 高级配置\nlog:\n  level: info\ndns:\n  servers:\n    - type: https\n      server: dns.google';
  const editor=borderCard('可编辑代码',a.w,mobile?224:256,14,0,'Background');stroke(editor,state==='错误'?'Error':'Stroke');const t=r75Text(code,mobile?11:13,'Secondary','Regular',a.w-30);t.fontName={family:'Roboto Mono',style:'Regular'};if(/[\u3400-\u9fff]/.test(code))t.fontName={family:zhFamily,style:zhStyles.Regular};add(editor,t);add(a.n,editor,space(12));
  if(['已校验','已应用','错误'].includes(state))add(a.n,r75Note(state==='错误'?'第 2 行：数组未闭合':state==='已应用'?'配置已应用':'配置校验通过',state==='错误'?'请补全右方括号后重试。当前配置继续生效。':state==='已应用'?'核心已重新载入当前配置。':'语法有效，可以应用到核心。',a.w,state==='错误'?'Error':'Success'),space(12));
  const actions=row('高级配置操作',a.w,44,8),validate=r75Route(r75Button('校验配置','Secondary','check',mobile?120:132),'配置校验'),apply=r75Button('应用配置','Primary',null,mobile?160:132);if(state==='已校验')r75Route(apply,'配置应用');else apply.opacity=.4;add(actions,validate,apply);add(a.n,actions);add(c,a.n);
}
function r75MobileHome(c){
  const a=r75Card('应用信息',true),id=row('应用标识',a.w,40,12);add(id,instance('Brand / Mark'),r75Copy('RainLink','1.0.0 · 稳定版',210,16));add(a.n,id);add(c,a.n);
  const b=r75Card('常用偏好',true);add(c,r75Rows(b,[r75Toggle('自动连接','启动时恢复上次选择',b.w,true,false),r75Toggle('连接与到期通知','连接变化与订阅到期时提醒',b.w,true,true)]));
  const d=r75Card('设置分类',true);add(c,r75Rows(d,[r75LinkRow('外观与语言','深色 · 简体中文','外观',d.w,true),r75LinkRow('网络与 DNS','加密解析 · IPv6','网络',d.w,true),r75LinkRow('核心与高级配置','sing-box · 运行中','核心引擎',d.w,true),r75LinkRow('更新','通过应用商店更新','更新',d.w,true),r75LinkRow('关于 RainLink','版本信息、隐私与开源许可','关于',d.w,true)]));
}
function r75DesktopNav(selected){
  const n=borderCard('设置分类导航',184,652,10,4,'Surface');r6Name(n,'设置分类导航');
  for(const [name,ic]of [['通用','settings'],['外观','sun'],['网络','globe'],['核心引擎','terminal'],['更新','refresh'],['关于','rain']]){
    const active=name===selected,b=r75Route(rad(row('设置分类 · '+name,162,44,10,12,active?'PrimarySurface':null),8),name);r6Name(b,'设置分类 · '+name);add(b,icon(ic,16,active?'Primary':'Muted'),r75Text(name,13,active?'Primary':'Secondary'));add(n,b);
  }
  const spacer=space();add(n,spacer);spacer.layoutGrow=1;add(n,r75Text('1.0.0 · 稳定版',11,'Muted'));return n;
}
async function r75Workspace(mobile){
  const platform=mobile?'移动端':'桌面端',views=mobile?['首页','外观','网络','核心引擎','更新','关于','高级配置','配置JSON','配置已校验','配置已应用','配置错误','隐私说明','开源许可']:['通用','外观','网络','核心引擎','更新','关于','高级配置','配置JSON','配置已校验','配置已应用','配置错误','隐私说明','开源许可'],variants={};
  for(const view of views){
    const c=r75Body('分类='+view,mobile?353:1120),body=mobile?c:v('设置详情',912,12);
    if(!mobile){c.layoutMode='HORIZONTAL';c.counterAxisAlignItems='MIN';c.itemSpacing=24;c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.resize(1120,652);add(c,r75DesktopNav(/配置/.test(view)?'核心引擎':['隐私说明','开源许可'].includes(view)?'关于':view),body);}
    if(view==='首页')r75MobileHome(body);else if(view==='通用')r75General(body,mobile);else if(view==='外观')r75Appearance(body,mobile);else if(view==='网络')r75Network(body,mobile);else if(view==='核心引擎')r75Core(body,mobile);else if(view==='更新')r75Updates(body,mobile);else if(view==='关于')r75About(body,mobile);else if(['隐私说明','开源许可'].includes(view))r75Legal(body,mobile,view==='隐私说明');else r75Advanced(body,mobile,view==='配置JSON'?'JSON':view==='配置已校验'?'已校验':view==='配置已应用'?'已应用':view==='配置错误'?'错误':'YAML');
    variants[view]=c;
  }
  const lib=r75Set('设置 / '+platform+' / 分类与详情',variants,mobile?4:2);
  const libraryPosition={x:lib.set.x,y:lib.set.y};
  // Navigation routes are authored on the destination's product page before
  // the component library is returned to the shared design-system section.
  if(mobile)mobilePage.appendChild(lib.set);
  for(const [view,c]of Object.entries(variants))for(const n of c.findAll(n=>!!n.getPluginData('rainlink-settings-route'))){
    const route=n.getPluginData('rainlink-settings-route');let dest=route==='配置YAML'?'高级配置':route==='配置JSON'?'配置JSON':route==='配置校验'?'配置已校验':route==='配置应用'?'配置已应用':route;
    if(route==='@DNS')await n.setReactionsAsync(r7Click(registry.mobile.DNS.id,'NAVIGATE'));
    else if(variants[dest]&&dest!==view)await n.setReactionsAsync(r7Click(variants[dest].id));
  }
  if(mobile){r75Section.appendChild(lib.set);lib.set.x=libraryPosition.x;lib.set.y=libraryPosition.y;}
  const screen=(mobile?registry.mobile:registry.desktop).Settings,content=uFind(screen,'Content');for(const n of [...content.children])if(r5Name(n)!=='Page header')n.remove();
  add(content,r7Instance(variants[mobile?'首页':'通用'],R75_UI));content.itemSpacing=mobile?12:16;content.paddingBottom=mobile?16:24;
  if(!mobile){const header=uFind(screen,'Page header');for(const n of [...header.children])if(n.type==='INSTANCE'&&n.findOne(t=>t.type==='TEXT'&&t.characters==='高级配置'))n.remove();}
  for(const t of screen.findAll(n=>n.type==='TEXT'))if(t.characters==='让 RainLink 符合你的习惯。')r6Copy(t,'偏好即时保存，网络与配置在确认后应用。');else if(t.characters==='小处贴心，日常顺手。')r6Copy(t,'管理偏好与网络选项');
  return {set:lib.set.id,initial:variants[mobile?'首页':'通用'].id,variants:Object.fromEntries(Object.entries(variants).map(([name,c])=>[name,c.id]))};
}
async function r75ApplySettings(report){
  const installed=uFind(registry.desktop.Settings,R75_UI),existing=dsPage.findOne(n=>n.type==='SECTION'&&n.getPluginData('rainlink-settings-version')==='7.5');
  if(installed&&uFind(registry.mobile.Settings,R75_UI)&&existing&&existing.getPluginData('rainlink-settings-revision')===R75_REVISION&&report.settingsUI?.revision===R75_REVISION){await r75RefreshChoiceLayouts(report.settingsUI,existing);await r75RefreshLegalBack(report.settingsUI);report.version='7.5';return report.settingsUI;}
  for(const reg of [registry.desktop,registry.mobile]){const view=uFind(reg.Settings,R75_UI);if(view)view.remove();}
  if(existing)existing.remove();
  for(const n of [...dsPage.children])if(n.getPluginData('rainlink-settings-version')==='7.5')n.remove();
  for(const page of [desktopPage,mobilePage])for(const n of [...page.children])if(n.type==='FRAME'&&['解析成功 · 28 ms','DNS 设置已保存','解析器地址不完整'].includes(r5Name(n)))n.remove();
  await figma.setCurrentPageAsync(dsPage);
  r75Section=figma.createSection();r75Section.name='设置 / 分类、控件与状态';r75Mark(r75Section);r75Section.setPluginData('rainlink-settings-revision',R75_REVISION);dsPage.appendChild(r75Section);r75Section.x=0;r75Section.y=Math.max(...dsPage.children.filter(n=>n!==r75Section&&n.visible).map(n=>n.y+n.height))+80;
  const title=add(v('设置组件库说明',4800,10),r75Text('设置 · 两端统一',26,'Text','Medium'),r75Text('分类、开关、主题、选择器、DNS、核心重启、更新与配置编辑，复用组件表达状态，不复制产品整页。',14,'Muted','Regular',4700));r75Section.appendChild(title);title.x=32;title.y=24;
  r75BackMaster();
  for(const mobile of [false,true]){
    await r75ToggleLibrary(mobile);
    for(const [key,options]of Object.entries({语言:['简体中文','繁體中文','English'],密度:['紧凑','标准'],文字:['标准','较大'],端口:['7890','8080','1080'],日志:['信息','警告','调试'],...(mobile?{}:{关闭行为:['最小化到托盘','退出应用'],渠道:['稳定版','预览版']})}))await r75ChoiceLibrary(key,options,mobile);
    await r75ThemeLibrary(mobile);await r75DNSLibrary(mobile);await r75EngineLibrary(mobile);await r75UpdateLibrary(mobile);
  }
  const desktop=await r75Workspace(false),mobile=await r75Workspace(true),dnsScreen=registry.mobile.DNS,dnsContent=uFind(dnsScreen,'Content');for(const n of [...dnsContent.children])n.remove();add(dnsContent,r7Instance(r75Libraries['dnstrue'].variants['加密 DNS'],'DNS 设置'),r75Toggle('DNS 缓存','复用近期解析结果',353,true,true),r75Button('返回网络设置','Secondary','返回',353));
  const back=dnsContent.children[dnsContent.children.length-1];
  const backReaction=[{trigger:{type:'ON_CLICK'},actions:[{type:'BACK'}]}];await back.setReactionsAsync(backReaction);
  const header=uFind(dnsScreen,'Page header'),close=header.children.find(n=>n.type==='INSTANCE');if(close)await close.setReactionsAsync(backReaction);
  const settingsHeader=uFind(registry.mobile.Settings,'Page header');for(const n of [...settingsHeader.children])if(n.type==='INSTANCE')n.remove();
  for(const screen of [registry.mobile.Settings,dnsScreen]){const nav=uFind(screen,'Mobile / Bottom navigation');for(const tab of nav.children){const label=tab.findOne(n=>n.type==='TEXT'),active=label?.characters==='设置';if(label)fill(label,active?'Primary':'Muted');const ic=tab.findOne(n=>n.type==='INSTANCE');if(ic)tint(ic,active?'Primary':'Muted');}}
  r75Section.resizeWithoutConstraints(5032,r75ShelfY+r75ShelfH+32);
  const controls=Object.fromEntries(Object.entries(r75Libraries).map(([key,{set,variants}])=>[key,{set:set.id,states:Object.fromEntries(Object.entries(variants).map(([name,c])=>[name,c.id]))}]));
  report.version='7.5';report.settingsUI={version:'7.5',revision:R75_REVISION,screensAdded:0,desktop,mobile,controls,section:r75Section.id,choiceMenus:'Full dropdown bounds reserved in component library',systemProxyAndTun:'overview only',defaultLanguage:'简体中文',desktopCategoryCount:6,mobileCategoryCount:5,prototypeBoundary:'Native component UI examples; no OS action, update download, arbitrary text editing or actual network request is performed.'};
  await r75RefreshLegalBack(report.settingsUI);report.counts.components=dsPage.findAll(n=>n.type==='COMPONENT').length;report.counts.instances=[desktopPage,mobilePage,dsPage].reduce((sum,p)=>sum+p.findAll(n=>n.type==='INSTANCE').length,0);figma.root.setPluginData('rainlink-settings-version','7.5');return report.settingsUI;
}
async function r75VerifySettings(report){
  const ui=report.settingsUI,errors=[],result={version:'7.5',revision:R75_REVISION,verifiedAt:new Date().toISOString(),errors,desktopViews:[],mobileViews:[],routeCount:0,choiceCount:0,toggleHitHeight:44};
  const check=(ok,detail)=>{if(!ok)errors.push(detail);};
  const actions=n=>(n?.reactions||[]).flatMap(r=>r.actions||[]),destination=(n,id)=>actions(n).some(a=>a.destinationId===id);
  check(figma.root.children.length===3,'文档页签应为 3 个');
  for(const [platform,page,reg,expected]of [['desktop',desktopPage,registry.desktop,12],['mobile',mobilePage,registry.mobile,11]]){
    const screens=page.findAll(n=>n.type==='FRAME'&&n.getPluginData('rainlink'));
    result[platform+'ScreenCount']=screens.length;check(screens.length===expected,platform+' 产品画面数量变化');
    check(screens.every(n=>n.layoutMode&&n.layoutMode!=='NONE'),platform+' 产品画面缺少 Auto Layout');
    const view=uFind(reg.Settings,R75_UI);check(!!view,platform+' 设置工作区缺失');
    check(!reg.Settings.findOne(n=>n.type==='TEXT'&&/系统代理|TUN\s*模式/i.test(n.characters)),platform+' 设置重复显示系统代理或 TUN');
    const lib=await figma.getNodeByIdAsync(ui[platform].set);check(lib.children.length===13,platform+' 设置详情不完整');
    for(const [name,id]of Object.entries(ui[platform].variants)){
      const c=await figma.getNodeByIdAsync(id),body=platform==='desktop'?uFind(c,'设置详情'):c;
      let expandedHeight=body.height;
      if(platform==='desktop')for(const child of body.children)if(child.type==='INSTANCE'){
        const main=await child.getMainComponentAsync(),parent=main?.parent;
        if(parent?.type==='COMPONENT_SET'&&parent.getPluginData('rainlink-settings-version')==='7.5')expandedHeight+=Math.max(...parent.children.map(n=>n.height))-child.height;
      }
      result[platform+'Views'].push({name,height:body.height,expandedHeight});
      if(platform==='desktop')check(expandedHeight<=652.1,'桌面 '+name+' 内容超过可用高度');
      if(platform==='mobile'&&name==='首页')check(body.height<=622,'移动设置首屏超高');
      if(['隐私说明','开源许可'].includes(name)){
        const header=uFind(body,'关于详情导航'),back=uFind(header,'返回关于箭头');
        check(body.children[0]===header&&header.children[0]===back,platform+' '+name+' 返回箭头应在内容区左上角');
        check(back?.width>=44&&back?.height>=44&&destination(back,ui[platform].variants['关于']),platform+' '+name+' 返回箭头命中区或目标无效');
        check(!c.findOne(n=>n.type==='TEXT'&&n.characters==='返回关于'),platform+' '+name+' 仍显示返回关于文字按钮');
        const slot=back?.children.find(n=>n.type==='INSTANCE'&&n.visible),master=slot&&await slot.getMainComponentAsync();check(master&&r5Name(master)==='Icon / 返回',platform+' '+name+' 返回箭头图标无效');
      }
      for(const n of c.findAll(n=>!!n.getPluginData('rainlink-settings-route'))){
        const route=n.getPluginData('rainlink-settings-route'),target=route==='配置YAML'?'高级配置':route==='配置JSON'?'配置JSON':route==='配置校验'?'配置已校验':route==='配置应用'?'配置已应用':route;
        if(route==='@DNS')check(destination(n,registry.mobile.DNS.id),'移动 DNS 入口无效');
        else if(target!==name)check(destination(n,ui[platform].variants[target]),platform+' '+name+' 到 '+target+' 的入口无效');
        result.routeCount++;
      }
    }
    const initial=await figma.getNodeByIdAsync(ui[platform].initial);
    if(platform==='desktop')check(uFind(initial,'设置分类导航').children.filter(n=>n.getPluginData('rainlink-settings-route')).length===6,'桌面设置分类应为 6 个');
    const network=await figma.getNodeByIdAsync(ui[platform].variants['网络']),port=uFind(network,'设置选择器 · 端口');
    check(uFind(port,'选择器值')?.characters==='7890',platform+' 默认混合端口不正确');
    for(const name of ['高级配置','配置JSON','配置错误','配置已应用']){
      const c=await figma.getNodeByIdAsync(ui[platform].variants[name]),apply=c.findOne(n=>n.type==='INSTANCE'&&n.findOne(t=>t.type==='TEXT'&&t.characters==='应用配置'));
      check(apply&&apply.opacity<.5&&actions(apply).length===0,platform+' 未校验配置不应直接应用');
    }
    const valid=await figma.getNodeByIdAsync(ui[platform].variants['配置已校验']),apply=valid.findOne(n=>n.type==='INSTANCE'&&n.findOne(t=>t.type==='TEXT'&&t.characters==='应用配置'));
    check(destination(apply,ui[platform].variants['配置已应用']),platform+' 已校验配置无法应用');
  }
  for(const [key,lib]of Object.entries(ui.controls)){
    if(key.startsWith('toggle'))for(const state of ['on','off']){
      const c=await figma.getNodeByIdAsync(lib.states[state]),hit=uFind(c,'设置开关命中区');
      check(hit?.height>=44&&hit?.width>=44&&destination(hit,lib.states[state==='on'?'off':'on']),key+' 开关命中区域或切换无效');
    }
    else if(Object.keys(lib.states).some(k=>k.endsWith(' · 展开'))){
      result.choiceCount++;
      for(const value of Object.keys(lib.states).filter(k=>!k.endsWith(' · 展开'))){
        const c=await figma.getNodeByIdAsync(lib.states[value]),open=await figma.getNodeByIdAsync(lib.states[value+' · 展开']);
        check(destination(uFind(c,'选择器按钮'),open.id)&&uFind(open,'选择器值').characters===value,key+' 选择器丢失当前值');
        const menu=uFind(open,'选择器菜单');check(open.y+menu.y+menu.height<=open.parent.height,key+' 展开菜单被组件集裁切');
        for(const option of Object.keys(lib.states).filter(k=>!k.endsWith(' · 展开')))check(destination(uFind(open,'选项 · '+option),lib.states[option]),key+' 选择器选项无效');
      }
    }
    else if(key.startsWith('dns')){
      const invalid=await figma.getNodeByIdAsync(lib.states['地址错误']);
      for(const name of ['保存 DNS','测试 DNS']){const n=uFind(invalid,name);check(n.opacity<.5&&!actions(n).length,key+' 地址错误时操作应禁用');}
    }
  }
  const dns=uFind(registry.mobile.DNS,'Content'),back=report.backNavigation?uFind(uFind(registry.mobile.DNS,'Page header'),'返回网络设置箭头'):dns.children[dns.children.length-1];
  check(actions(back).some(a=>a.type==='BACK'),'DNS 返回应保留设置分类');
  const backMaster=await back.children.find(n=>n.type==='INSTANCE'&&n.visible).getMainComponentAsync();
  check(r5Name(backMaster)==='Icon / 返回','DNS 返回箭头方向不正确');
  result.legalBackNavigation='top-left-arrow';result.legalBackViews=4;result.systemProxyAndTunAbsentFromSettings=true;result.productScreens=23;result.pageCount=3;report.settingsUIVerification=result;
}
async function r75SettingsMain(){
  figma.showUI('<body style="padding:24px;background:#151617;color:#c0c2c8;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#8adcbf">RainLink / 补全设置</h2><p id="s">补全两端分类、控件与交互…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:520,height:200});
  await r5Initialize();figma.skipInvisibleInstanceChildren=false;await r71Palette();const report=JSON.parse(figma.root.getPluginData('rainlink-report'));
  try{
    await r75ApplySettings(report);await r76UpdateBackNavigation(report);figma.ui.postMessage({status:'核验设置布局与全部原型目标…'});await r75VerifySettings(report);await r76VerifyBackNavigation(report);await r71VerifyControls(report);
  }catch(e){const t=uFind(dsPage,'Delivery / Native audit');t.characters='RainLink 设计核验\n'+JSON.stringify({...report,settingsUIBuildError:String(e)+'\n'+String(e.stack||'')},null,2);throw e;}
  const audit=await r5AuditDocument();report.overflow=audit.overflow;report.untranslatedDisplayCopy=audit.untranslatedDisplayCopy;delete report.nativeBackup;delete report.screenshotVerification;
  const text=uFind(dsPage,'Delivery / Native audit');text.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);text.visible=false;figma.root.setPluginData('rainlink-report',JSON.stringify(report));
  await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Settings];figma.viewport.scrollAndZoomIntoView(figma.currentPage.selection);figma.notify('两端设置已补全 · 保持 23 个产品画面');figma.closePlugin();
}
