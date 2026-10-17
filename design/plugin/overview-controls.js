// RainLink 4.0. Selection, VPN state and routing mode are separate prototype states.
// All target selection actions change variables only. VPN actions exist on overview.
let gInteractionCollection;
const gVars = {}, gActions = new Map(), gGroupsData = {};
const G_MODES = ['规则', '全局', '直连'];
const G_MODE_COPY = ['按分流规则选择代理或直连', '全部流量使用当前选择', '全部流量直接访问网络'];

function gVar(name, type, value) {
  const x = gVars[name] || figma.variables.createVariable(name, gInteractionCollection, type);
  x.setValueForMode(gInteractionCollection.defaultModeId, value);
  x.description = 'RainLink 交互状态：'+name;
  gVars[name] = x;
  return x;
}
function gSet(name, value) {
  const variable = gVars[name];
  if (!variable) throw new Error('Missing interaction variable '+name);
  const data = value && value.type === 'VARIABLE_ALIAS'
    ? {type:'VARIABLE_ALIAS', resolvedType:variable.resolvedType, value}
    : {type:variable.resolvedType, resolvedType:variable.resolvedType, value};
  return {type:'SET_VARIABLE', variableId:variable.id, variableValue:data};
}
function gAlias(name) { return {type:'VARIABLE_ALIAS',id:gVars[name].id}; }
function gBound(node, name, field='characters') { node.setBoundVariable(field, gVars[name]);return node; }
function gBoundFill(node, name, target='fills') {
  node[target] = [figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:0,g:0,b:0}},'color',gVars[name])];
  return node;
}
function gAction(node, actions, kind) {
  node.setPluginData('rainlink-control-kind',kind);
  gActions.set(node.id,{node,actions,kind});
  return node;
}
function gGo(target) { return {rainlinkTarget:target}; }
function gColor(token) { return vars[token].valuesByMode[darkMode]; }

async function gV4Initialize() {
  gActions.clear();
  const cols=await figma.variables.getLocalVariableCollectionsAsync();
  gInteractionCollection=cols.find(c=>c.name==='RainLink / 交互状态') || figma.variables.createVariableCollection('RainLink / 交互状态');
  for(const v of await figma.variables.getLocalVariablesAsync())if(v.variableCollectionId===gInteractionCollection.id)gVars[v.name]=v;
  gVar('VPN/已开启','BOOLEAN',false);
  gVar('VPN/状态文案','STRING','未连接');
  gVar('VPN/状态颜色','COLOR',gColor('Muted'));
  gVar('VPN/下载','STRING','↓ 0 MB/s');gVar('VPN/上传','STRING','↑ 0 MB/s');
  gVar('选择/分组','STRING','主订阅');gVar('选择/节点','STRING',G_MAIN[0].name);
  gVar('选择/协议','STRING',G_MAIN[0].p);gVar('选择/延迟','STRING',G_MAIN[0].ping+' ms');
  gVar('选择/待应用','BOOLEAN',false);
  gVar('连接/分组','STRING','主订阅');gVar('连接/节点','STRING',G_MAIN[0].name);
  gVar('连接/协议','STRING',G_MAIN[0].p);gVar('连接/延迟','STRING',G_MAIN[0].ping+' ms');
  gVar('模式/名称','STRING','规则模式');gVar('模式/说明','STRING',G_MODE_COPY[0]);
  for(let i=0;i<G_MODES.length;i++)gVar('模式/'+G_MODES[i]+'/背景','COLOR',gColor(i===0?'PrimarySurface':'Raised'));
  const travel=[G_MAIN[2],G_MAIN[0],G_MAIN[1],G_MAIN[3]];
  const manual={name:'备用 HTTP',p:'HTTP',region:'自定义',code:'CN',ping:'16',server:'proxy.backup.example.com:8080'};
  Object.assign(gGroupsData,{'主订阅':[...G_MAIN,G_LOOSE[0]],'备用订阅':[...G_BACKUP,G_LOOSE[0]],'未分组':[...G_LOOSE,manual],'旅行订阅':travel,'开发环境':[G_LOOSE[0]]});
  for(const [group,nodes]of Object.entries(gGroupsData)){
    const selected=group==='主订阅';
    gVar('分组/'+group+'/选中','BOOLEAN',selected);
    gVar('分组/'+group+'/背景','COLOR',gColor(selected?'PrimarySurface':'Surface'));
    gVar('分组/'+group+'/节点','STRING',nodes[0].name);
    gVar('分组/'+group+'/协议','STRING',nodes[0].p);
    gVar('分组/'+group+'/延迟','STRING',nodes[0].ping+' ms');
    for(let i=0;i<nodes.length;i++){
      gVar('节点/'+group+'/'+nodes[i].name+'/选中','BOOLEAN',i===0);
      gVar('节点/'+group+'/'+nodes[i].name+'/背景','COLOR',gColor(i===0?'PrimarySurface':'Surface'));
    }
  }
}
function gSelection(group, data=null) {
  const actions=[];
  for(const name of Object.keys(gGroupsData)){
    actions.push(gSet('分组/'+name+'/选中',name===group));
    actions.push(gSet('分组/'+name+'/背景',gColor(name===group?'PrimarySurface':'Surface')));
  }
  if(data){
    for(const n of gGroupsData[group]){
      actions.push(gSet('节点/'+group+'/'+n.name+'/选中',n.name===data.name));
      actions.push(gSet('节点/'+group+'/'+n.name+'/背景',gColor(n.name===data.name?'PrimarySurface':'Surface')));
    }
    for(const [key,val]of [['节点',data.name],['协议',data.p],['延迟',data.ping+' ms']])actions.push(gSet('分组/'+group+'/'+key,val));
  }
  actions.push(gSet('选择/分组',group));
  for(const key of ['节点','协议','延迟'])actions.push(gSet('选择/'+key,gAlias('分组/'+group+'/'+key)));
  actions.push(gSet('选择/待应用',true));
  return actions;
}
function gPowerActions(online, prefix) {
  const actions=[gSet('VPN/已开启',!online),gSet('VPN/状态文案',online?'未连接':'已连接'),gSet('VPN/状态颜色',gColor(online?'Muted':'Primary')),gSet('VPN/下载',online?'↓ 0 MB/s':'↓ 12.8 MB/s'),gSet('VPN/上传',online?'↑ 0 MB/s':'↑ 1.4 MB/s'),gSet('选择/待应用',false)];
  if(!online)for(const key of ['分组','节点','协议','延迟'])actions.push(gSet('连接/'+key,gAlias('选择/'+key)));
  actions.push(gGo(prefix+(online?'Disconnected':prefix==='D/'?'Dashboard':'Home')));
  return actions;
}
function sidebar(active) {
  const n=frame('Sidebar',248,900,'VERTICAL','Surface',0,20);n.paddingTop=26;n.paddingBottom=24;stroke(n);
  const brand=add(row('Brand',208,44,12),instance('Brand / Mark'),tx('RainLink',22,'Text','Semi Bold'));
  const nav=v('Primary navigation',208,4);navNames.forEach((s,i)=>add(nav,navItem(s,s===active,i)));
  const footer=between(add(row('App status',208,null),small('RainLink 1.0.0'),badge('CORE READY','Success')));
  add(n,brand,space(32),nav,grow(space()),footer);return n;
}

function gLibrary() {
  gLibraryV3();
  const side=masters['Sidebar / Desktop'];
  for(const n of side.findAll(n=>['Workspace','Routing mode'].includes(n.getPluginData('rainlink-canonical-name')||n.name)||n.type==='TEXT'&&n.characters==='WORKSPACE'))n.remove();
  // Rebuild the compact header spacing, preserving the shared sidebar master identity.
  const nav=uFind(side,'Primary navigation');
  for(const n of [...side.children])if(n!==nav&&n.name!=='Brand'&&n.name!=='Workspace status'){
    if(n.type==='FRAME'&&n.name==='Flexible space')continue;
    if(n.width===1||n.name==='Spacer'||n.name==='Space')n.remove();
  }
  const footer=uFind(side,'Workspace status');
  if(footer)footer.name='App status';
  for(const mobile of [false,true]){
    const w=mobile?353:744,inner=w-32;
    gNative('Group / '+(mobile?'Mobile':'Desktop'),c=>{
      c.resize(w,132);c.layoutMode='VERTICAL';c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';
      c.paddingLeft=c.paddingRight=16;c.paddingTop=c.paddingBottom=16;c.itemSpacing=12;rad(c,14);fill(c,'Surface');stroke(c);
      const title=uText('主订阅',16,'Text','Medium');title.name='组名称';
      const meta=uSmall('8 个节点 · 订阅自动更新','Muted');meta.name='组信息';
      const check=icon('check',16,'Primary');check.name='分组选中';check.setPluginData('rainlink-canonical-name',check.name);
      add(c,between(add(row('Group heading',inner,null,10),add(row('Group identity',null,null,12),miniIcon('folder','Primary',36,'PrimarySurface'),add(v('Group copy',mobile?213:520,4),title,meta)),check)));
      const node=uText('东京 · 樱花',12,'Secondary','Medium');node.name='组当前节点';
      const ping=uSmall('24 ms','Primary');ping.name='组延迟';
      const detail=btn('节点','Ghost','M','chevron');detail.name='组节点入口';detail.setPluginData('rainlink-canonical-name',detail.name);
      add(c,between(add(row('Group current node',inner,36,8),add(row('Group current identity',null,null,8),node,ping),detail)));
    });
    gNative('Overview / Proxy mode / '+(mobile?'Mobile':'Desktop'),c=>{
      const mw=mobile?353:1120,iw=mw-32;c.resize(mw,mobile?114:82);c.layoutMode='VERTICAL';c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';
      c.paddingLeft=c.paddingRight=16;c.paddingTop=c.paddingBottom=14;c.itemSpacing=8;rad(c,14);fill(c,'Surface');stroke(c);
      const heading=between(add(row('Proxy mode heading',mobile?iw:700,null),uText('代理模式',14,'Text','Medium'),mobile?null:uSmall(G_MODE_COPY[0],'Secondary')));
      if(!mobile)heading.children[1].name='模式说明';
      const choices=add(row('Proxy mode options',mobile?iw:354,36,6));
      for(const mode of G_MODES){const b=center(rad(row('代理模式 · '+mode,mobile?103:114,36,0,6,mode==='规则'?'PrimarySurface':'Raised'),9));add(b,uText(mode,13,mode==='规则'?'Primary':'Secondary','Medium'));add(choices,b);}
      if(mobile)add(c,heading,choices);else add(c,between(add(row('Proxy mode desktop',iw,52,16),heading,choices)));
    });
  }
}
function gMode(mobile=false,staticMode=null) {
  const c=instance('Overview / Proxy mode / '+(mobile?'Mobile':'Desktop'));
  const desc=uFind(c,'模式说明');if(desc){if(staticMode)desc.characters=G_MODE_COPY[G_MODES.indexOf(staticMode)];else gBound(desc,'模式/说明');}
  for(let i=0;i<G_MODES.length;i++){
    const item=uFind(c,'代理模式 · '+G_MODES[i]);
    if(staticMode)fill(item,staticMode===G_MODES[i]?'PrimarySurface':'Raised');else gBoundFill(item,'模式/'+G_MODES[i]+'/背景');
    gAction(item,[gSet('模式/名称',G_MODES[i]+'模式'),gSet('模式/说明',G_MODE_COPY[i]),...G_MODES.map(m=>gSet('模式/'+m+'/背景',gColor(m===G_MODES[i]?'PrimarySurface':'Raised')))],'proxy-mode');
  }
  return c;
}
function gGroup(name,count,type,node,mobile=false,detail='Nodes',connected='Dashboard',meta=null) {
  const c=instance('Group / '+(mobile?'Mobile':'Desktop'));c.name='Group · '+name;c.setPluginData('rainlink-canonical-name',c.name);
  uOverride(c,'组名称',name);uOverride(c,'组信息',meta||count+' 个节点 · '+(type==='订阅'?'订阅自动更新':type==='自建'?'手动分组':'手动添加'));
  uOverride(c,'组当前节点',node.name);uOverride(c,'组延迟',node.ping+' ms');
  gBound(uFind(c,'组当前节点'),'分组/'+name+'/节点');gBound(uFind(c,'组延迟'),'分组/'+name+'/延迟');
  gBound(uFind(c,'分组选中'),'分组/'+name+'/选中','visible');gBoundFill(c,'分组/'+name+'/背景');
  gAction(c,gSelection(name),'select-group');uLink(uFind(c,'组节点入口'),(mobile?'M/':'D/')+detail);
  return c;
}
function gSelectedPanel(mobile=false,online=false,staticGroup=null,data=G_MAIN[0],chain=false) {
  const w=mobile?353:352,iw=w-32,c=borderCard('Selection summary',w,null,16,12);
  const group=uText(staticGroup||'主订阅',20,'Text','Medium',iw);
  const node=uText(chain?(chain==='reverse'?'东京 · 樱花 → 办公 HTTP':'办公 HTTP → 东京 · 樱花'):data.name,13,'Secondary','Medium',iw);
  const title=between(add(row('Selection heading',iw,null),uSmall('当前选择','Muted'),badge('已选中','Success')));
  if(!staticGroup){gBound(group,'选择/分组');gBound(node,'选择/节点');}
  add(c,title,group,node);
  if(online){const note=uSmall('待应用 · 关闭再开启 VPN','Warning',iw);gBound(note,'选择/待应用','visible');add(c,note);}
  add(c,uSmall('VPN 开关和代理模式均在概览。','Muted',iw),uButton('去概览',(mobile?'M/':'D/')+(mobile?'Home':'Dashboard'),'Secondary','grid',iw));
  return c;
}
function gGroups(key='Profiles',state='base') {
  for(const mobile of [false,true]){
    const p=mobile?'M/':'D/',w=mobile?353:1120,build=b=>{
      if(state!=='base')add(b,uSmall(state==='subscription'?'已导入旅行订阅，自动创建 4 节点分组。':state==='manual'?'备用 HTTP 已加入未分组。':state==='moved'?'办公 HTTP 已移入主订阅。':'开发环境已创建，办公 HTTP 已移入。','Primary',w));
      if(!mobile)add(b,between(add(row('Group toolbar',1120,40,16),input('搜索分组…',344,'search'),uSmall('点击选中分组，点「节点」更换组内节点。','Muted'))));
      const list=mobile?b:v('Group list',744,16),moved=state==='moved',loose=state==='manual'?4:moved||state==='custom'?2:3;
      add(list,gGroup('主订阅',moved?9:8,'订阅',G_MAIN[0],mobile,moved?'Moved nodes':'Nodes','Dashboard',moved?'8 个订阅节点 + 1 个手动节点':null),gGroup('备用订阅',3,'订阅',G_BACKUP[0],mobile,'Backup group','Backup connected'),gGroup('未分组',loose,'未分组',G_LOOSE[0],mobile,state==='manual'?'Manual added nodes':moved||state==='custom'?'Ungrouped after move':'Ungrouped'));
      if(state==='subscription')add(list,gGroup('旅行订阅',4,'订阅',G_MAIN[2],mobile,'Travel group'));
      if(state==='custom')add(list,gGroup('开发环境',1,'自建',G_LOOSE[0],mobile,'Customgroup'));
      if(!mobile)add(b,add(row('Group workspace',1120,null,24),list,gSelectedPanel()));
      else add(b,between(add(row('Group selection footer',353,40),uSmall('这里只选择，连接请前往概览。','Muted'),uButton('去概览','M/Home','Ghost','grid'))));
      add(b,uSmall('订阅 → 自动建组　·　单个节点 → 未分组','Muted',w));
    };
    if(mobile)gM(key,'分组','选择分组，记住该组当前节点',build,'Profiles','M/Import profile',true);
    else gD(key,'分组','选择连接目标。VPN 开关与代理模式在概览。',build,'Profiles',uButton('添加节点',p+'Import profile','Primary','plus'));
  }
}
function gNodePage(key,title,data,loose=false,moved=false,tested=false) {
  // A moved node is now remembered inside its new group; no move affordance remains.
  if(!gGroupsData[title].some(n=>n.name===data[data.length-1].name)){
    for(const n of data)if(!gGroupsData[title].some(x=>x.name===n.name)){
      gGroupsData[title].push(n);gVar('节点/'+title+'/'+n.name+'/选中','BOOLEAN',false);gVar('节点/'+title+'/'+n.name+'/背景','COLOR',gColor('Surface'));
    }
  }
  for(const mobile of [false,true]){
    const p=mobile?'M/':'D/',w=mobile?353:1120,build=b=>{
      add(b,between(add(row('Group node toolbar',w,40,8),uButton('全部分组',p+'Profiles','Ghost','folder'),uButton(tested?'测速完成':'测速',p+(key==='Nodes'?'Nodes tested':key),'Secondary','speed'))));
      const list=mobile?b:borderCard('Group node inventory',728,null,0,0);
      for(let i=0;i<data.length;i++){
        const n=gNode(data[i],mobile,i===0,loose);
        gBound(uFind(n,'节点选中'),'节点/'+title+'/'+data[i].name+'/选中','visible');gBoundFill(n,'节点/'+title+'/'+data[i].name+'/背景');
        gAction(n,gSelection(title,data[i]),'select-node');
        add(list,n);if(!mobile&&i<data.length-1)add(list,divider(728));
      }
      if(!mobile){
        const aside=borderCard('Selected group node',368,null,24,16);
        const current=uText(data[0].name,21,'Text','Medium',320);gBound(current,'分组/'+title+'/节点');
        const ping=uSmall(data[0].ping+' ms','Primary');gBound(ping,'分组/'+title+'/延迟');
        const tag=badge(data[0].p);gBound(tag.findOne(n=>n.type==='TEXT'),'分组/'+title+'/协议');
        add(aside,uSmall('该组当前节点','Secondary'),current,add(row('Selected node protocol',320,null,12),tag,ping),divider(320),uSmall('点击节点即可选中。连接统一在概览开启。','Muted',320),uButton('去概览',p+'Dashboard','Secondary','grid',320));
        if(loose)add(aside,uSmall('只有未分组节点可以移动。归组后隐藏移动入口。','Muted',320));
        else if(title==='主订阅')add(aside,uButton('代理链',p+'Chains','Ghost','link',320));
        if(moved)add(aside,uSmall('订阅更新保留手动加入的节点。','Muted',320));
        add(b,add(row('Group node workspace',1120,null,24),list,aside));
      }else{
        if(title==='主订阅')add(b,uButton('代理链',p+'Chains','Ghost','link',353));
        add(b,uSmall('选中后回到概览开启 VPN。','Muted',353));
      }
    };
    if(mobile)gM(key,title,data.length+' 个节点 · 点击选中',build,'Nodes','M/Profiles');
    else gD(key,title,data.length+' 个节点 · 点击选中，记住你的选择。',build,'Nodes',uButton('添加节点',p+'Import profile','Primary','plus'));
  }
}
function gHome(key,group='主订阅',data=G_MAIN[0],online=true,chain=false,staticMode=null) {
  const mk=key==='Dashboard'?'Home':key==='Dashboard light'?'Home light':key;
  const sample=!['Dashboard','Disconnected','Dashboard light','Mode global','Mode direct','Pending selection'].includes(key);
  const pending=key==='Pending selection',activeKey=online?'连接':'选择';
  const label=staticMode?staticMode+'模式':'规则模式';
  const db=b=>{
    const hero=borderCard('Connection group hero',1120,pending?222:196,28,16,online?'PrimarySurface':'Surface');
    const state=uText(online?'VPN 已开启':'VPN 已关闭',13,online?'Primary':'Muted','Medium');
    const mode=badge(label,'Success');if(!sample&&!staticMode)gBound(mode.findOne(n=>n.type==='TEXT'),'模式/名称');
    const power=btn(online?'关闭 VPN':'开启 VPN','Primary','M','power');gAction(power,gPowerActions(online,'D/'),'vpn-power');
    const name=uText(sample?group:'主订阅',28,'Text','Semi Bold',730);
    const node=uSmall(chain?(chain==='reverse'?'东京 · 樱花 → 办公 HTTP':'办公 HTTP → 东京 · 樱花'):data.name,'Secondary',730);
    if(!sample){gBound(name,activeKey+'/分组');gBound(node,activeKey+'/节点');}
    const ping=uSmall(online?data.ping+' ms':'未连接','Secondary');if(online&&!sample)gBound(ping,'连接/延迟');
    add(hero,between(add(row('Connection hero heading',1064,null),add(row('Connection state',null,null,8),dot(online?'Primary':'Muted'),state),mode)),between(add(row('Connection group summary',1064,null),add(v('Overview target',730,6),name,node),power)),between(add(row('Connection group bottom',1064,null),add(row('Current connection facts',null,null,12),uSmall(online?'当前连接':'当前选择','Muted'),ping),uButton('选择分组','D/Quick switch','Ghost','connections'))));
    if(pending)add(hero,uSmall('待应用：备用订阅 / 伦敦 · 泰晤士 · 关闭再开启 VPN 后生效','Warning',1064));
    add(b,hero,gMode(false,staticMode),add(row('Network stats',1120,86,16),uMetric('今日流量','8.42 GB','↓ 7.86 GB　↑ 560 MB',362),uMetric('下载速度',online?'12.8 MB/s':'0 MB/s','上传 '+(online?'1.4':'0')+' MB/s',362),uMetric('网络质量',online?'98 / 100':'—',online?'稳定 · 丢包 0%':'等待连接',364)));
    if(online){
      const change=between(add(row('Pending target summary',1120,36,12),uSmall('已选目标','Muted'),gBound(uText('主订阅',13,'Text','Medium'),'选择/分组'),gBound(uSmall(G_MAIN[0].name,'Secondary'),'选择/节点'),grow(space()),uSmall('待应用 · 下次开启 VPN 时生效','Warning')));
      gBound(change,'选择/待应用','visible');if(!pending)add(b,change);
    }
    add(b,add(row('Connection trends',1120,230,24),gTrend(data,chain),gHealth(group,data)));
  };
  const ds=gD(key,'概览','选择目标、VPN 开关和代理模式集中于此。',db,'Dashboard',uButton('选择分组','D/Quick switch','Secondary','connections'));
  ds.setPluginData('rainlink-overview-online',online?'true':'false');ds.setPluginData('rainlink-overview-sample',sample?'true':'false');
  const mb=b=>{
    const hero=center(borderCard('VPN control',353,pending?206:184,16,8,online?'PrimarySurface':'Surface'));
    const ring=center(rad(row('VPN power button',88,88,0,0,online?'Primary':'Raised'),44));stroke(ring,online?'Primary':'Stroke');add(ring,icon('power',32,online?'OnPrimary':'Primary'));gAction(ring,gPowerActions(online,'M/'),'vpn-power');
    const modeName=uSmall(label,'Secondary');if(!sample&&!staticMode)gBound(modeName,'模式/名称');
    const mode=add(row('VPN mode caption',null,null,6),modeName,uSmall('· '+(online?'点按关闭 VPN':'点按开启 VPN'),'Secondary'));
    add(hero,ring,uText(online?'VPN 已开启':'VPN 已关闭',21,'Text','Semi Bold'),mode);
    if(pending)add(hero,uSmall('关闭再开启后，应用新选择','Warning'));
    add(b,hero);
    const target=borderCard('Selected connection group',353,null,16,10),name=uText(sample?group:'主订阅',17,'Text','Medium'),node=uSmall(chain?(chain==='reverse'?'东京 → 办公 HTTP':'办公 HTTP → 东京'):data.name,'Secondary',321);
    if(!sample){gBound(name,activeKey+'/分组');gBound(node,activeKey+'/节点');}
    const ping=uSmall(online?data.ping+' ms':'当前选择','Primary');if(online&&!sample)gBound(ping,'连接/延迟');
    add(target,between(add(row('Selected group heading',321,null),name,uButton('选择','M/Quick switch','Ghost','connections'))),between(add(row('Selected group node',321,null),uSmall(online?'当前连接':'当前选择','Muted'),ping)),node);
    if(online){const note=uSmall('待应用 · 下次开启时使用新选择','Warning',321);gBound(note,'选择/待应用','visible');add(target,note);}
    add(b,target,gMode(true,staticMode),add(row('Mobile live speed',353,86,15),uMetric('下载',online?'12.8':'0','MB/s',169),uMetric('上传',online?'1.4':'0','MB/s',169)),between(add(row('Today traffic simple',353,44),uCopy('今日流量','↓ 7.86 GB　↑ 560 MB',230,12),uLink(uText('8.42 GB',18,'Text','Medium'),'M/Traffic'))));
  };
  const ms=gM(mk,'RainLink','概览 · 管理连接与代理模式',mb,'Home','M/Settings');
  ms.setPluginData('rainlink-overview-online',online?'true':'false');ms.setPluginData('rainlink-overview-sample',sample?'true':'false');
  const h=uFind(ms,'Page header'),back=h.children[0];h.appendChild(back);const ic=back.findOne(n=>n.type==='INSTANCE');if(ic)ic.swapComponent(icons.settings);
  if(key==='Dashboard light'){applyLight(ds);applyLight(ms);}
}
function gSwitch() {
  for(const mobile of [false,true]){
    const p=mobile?'M/':'D/',build=b=>{
      for(const args of [['主订阅',8,'订阅',G_MAIN[0],'Nodes'],['备用订阅',3,'订阅',G_BACKUP[0],'Backup group'],['未分组',3,'未分组',G_LOOSE[0],'Ungrouped']])add(b,gGroup(args[0],args[1],args[2],args[3],mobile,args[4]));
      add(b,uSmall('点击仅更换选择，不改变当前 VPN 连接。','Muted',mobile?353:744),uButton('返回概览',p+(mobile?'Home':'Dashboard'),'Secondary','grid',mobile?353:744));
    };
    if(mobile)gM('Quick switch','选择分组','使用该组上次选择的节点',build,'Home','M/Home');
    else gD('Quick switch','选择分组','选中后回到概览，按需开启 VPN。',build,'Dashboard',uButton('关闭','D/Dashboard','Ghost','close'));
  }
}
function gChainFlow() {
  gChainFlowV3();
  for(const [reg,p]of [[registry.desktop,'D/'],[registry.mobile,'M/']]){
    const main=reg.Chains;
    for(const t of main.findAll(n=>n.type==='TEXT'))if(/日常直接连接分组/.test(t.characters)){t.characters='需要多跳时编排代理链，选中后在概览开启 VPN。';t.setPluginData('rainlink-original-text',t.characters);}
    const choose=uSummary(p==='M/');const content=uFind(main,'Content');
    gAction(choose,[...gSelection('主订阅'),gSet('选择/节点','开发代理链 · 办公 HTTP → 东京'),gSet('选择/协议','2 跳 · TCP'),gSet('选择/延迟','46 ms')],'select-chain');
    // Existing summary opens editing; a distinct select action never starts the VPN.
    const pick=btn('选中代理链','Secondary','M','check');gAction(pick,[...gSelection('主订阅'),gSet('选择/节点','开发代理链 · 办公 HTTP → 东京'),gSet('选择/协议','2 跳 · TCP'),gSet('选择/延迟','46 ms')],'select-chain');add(content,pick);choose.remove();
    for(const [key,reverse]of [['Chain tested',false],['Chain reverse tested',true]]){
      const screen=reg[key];
      for(const t of screen.findAll(n=>n.type==='TEXT'))if(t.characters==='保存并连接'){t.characters='保存并选中';t.setPluginData('rainlink-original-text',t.characters);}
      const controls=screen.findAll(n=>(n.getPluginData('rainlink-canonical-name')||n.name)==='Button · 保存并连接');
      for(const b of controls){const power=b.findOne(n=>n.type==='INSTANCE');if(power)power.swapComponent(icons.check);gAction(b,[...gSelection('主订阅'),gSet('选择/节点',reverse?'开发代理链 · 东京 → 办公 HTTP':'开发代理链 · 办公 HTTP → 东京'),gSet('选择/协议','2 跳 · TCP'),gSet('选择/延迟',reverse?'39 ms':'46 ms'),gGo(p+(p==='M/'?'Home':'Dashboard'))],'select-chain');}
    }
  }
}
async function gPatchExisting() {
  await gPatchExistingV3();
  for(const [reg,p]of [[registry.desktop,'D/'],[registry.mobile,'M/']])for(const [key,s]of Object.entries(reg)){
    if(p==='D/'){
      const bar=uFind(s,'Connection bar');if(!bar)continue;
      for(const n of [...bar.children])n.remove();
      const online=s.getPluginData('rainlink-overview-online')==='true';
      const state=uText(online?'已连接':'未连接',13,online?'Primary':'Muted','Medium');
      const dotNode=dot(online?'Primary':'Muted');
      if(!online){gBound(state,'VPN/状态文案');gBoundFill(state,'VPN/状态颜色');gBoundFill(dotNode,'VPN/状态颜色');}
      const group=gBound(uSmall('主订阅','Secondary'),'连接/分组'),node=gBound(uSmall(G_MAIN[0].name,'Secondary'),'连接/节点');
      if(!online){gBound(group,'VPN/已开启','visible');gBound(node,'VPN/已开启','visible');}
      const left=add(row('Persistent group status',null,null,10),dotNode,state,group,node);
      const ping=gBound(uSmall('24 ms','Secondary'),'连接/延迟');
      const down=uSmall(online?'↓ 12.8 MB/s':'↓ 0 MB/s','Secondary'),up=uSmall(online?'↑ 1.4 MB/s':'↑ 0 MB/s','Muted');
      if(!online){gBound(down,'VPN/下载');gBound(up,'VPN/上传');}
      if(!online)gBound(ping,'VPN/已开启','visible');
      add(bar,left,add(row('Persistent group speeds',null,null,16),ping,down,up,uButton('概览','D/Dashboard','Ghost','grid')));
    }
  }
  const rules=registry.desktop.Rules;
  const modes=uFind(rules,'Routing modes');if(modes){const parent=modes.parent,idx=parent.children.indexOf(modes);modes.remove();const note=borderCard('Routing overview shortcut',1120,78,20,12);note.layoutMode='HORIZONTAL';note.primaryAxisAlignItems='SPACE_BETWEEN';add(note,uCopy('分流规则','代理模式在概览设置，这里管理规则与优先级。',760,16),uButton('前往概览','D/Dashboard','Secondary','grid'));parent.insertChild(idx,note);}
  const network=uFind(registry.mobile.Settings,'Network preferences');
  if(network){for(const n of [...network.children])if(n.type==='FRAME'&&n.findOne(t=>t.type==='TEXT'&&['Routing mode','路由模式','代理模式'].includes(t.characters)))n.remove();const cs=network.children;if(cs.length&&cs[cs.length-1].height<=1)cs[cs.length-1].remove();}
  // Node details has no power action. Selection has already happened on the list.
  const details=registry.mobile['Node details'];
  for(const b of details.findAll(n=>(n.getPluginData('rainlink-canonical-name')||n.name)==='Button · 连接此组')){textOverride(b,'Label','去概览');b.name='Button · 去概览';b.setPluginData('rainlink-canonical-name',b.name);const ic=b.findOne(n=>n.type==='INSTANCE');if(ic)ic.swapComponent(icons.grid);uLink(b,'M/Home');}
}
function gV4Examples() {
  gHome('Mode global','主订阅',G_MAIN[0],false,false,'全局');
  gHome('Mode direct','主订阅',G_MAIN[0],false,false,'直连');
  gHome('Pending selection','主订阅',G_MAIN[0],true);
}
function gSystem() {
  gSystemV3();
  const map=uFind(dsPage,'Prototype Flow / Interaction map');
  for(const n of [...map.children])n.remove();
  add(map,uTitle('原型流程 · 选择与连接',1404),uSmall('两端统一：分组和节点只选择，概览控制 VPN 与代理模式。','Secondary',1404));
  for(const [title,steps,desc]of [
    ['订阅导入',['添加节点','粘贴订阅','自动创建同名组','选中分组'],'添加不会连接。组内记住上次选择的节点。'],
    ['单个节点',['添加节点','填写 HTTP 等节点','自动进入未分组','选中或移动'],'只有未分组节点可以移动。订阅更新保留手动加入的节点。'],
    ['开启 VPN',['选择分组或节点','回到概览','设置代理模式','开启 VPN'],'规则 / 全局 / 直连模式均在概览。关闭后保留分组与节点选择。'],
    ['连接中改选',['保持当前连接','选中新目标','概览提示待应用','关闭再开启 VPN'],'选中不会重连，当前连接与下次使用的选择分别显示。'],
    ['可视化代理链',['选择已有节点','调整跳点顺序','测试并保存选中','概览开启 VPN'],'仅提供可视化编排，不需要代码。保存与选择不会启动连接。']
  ]){
    const c=borderCard(title,1404,null,24,16),r=row('Group flow steps',1356,56,20);add(c,uText(title,18,'Text','Medium'));
    for(let i=0;i<steps.length;i++){add(r,center(add(rad(row('Step '+i,295,56,8,12,i===0?'PrimarySurface':'Raised'),10),uText(String(i+1).padStart(2,'0'),11,'Primary','Medium'),uText(steps[i],13,'Text','Medium'))));if(i<steps.length-1)add(r,icon('arrow',16));}
    add(c,r,uSmall(desc,'Secondary',1356));add(map,c);
  }
  const gallery=dsPage.children.find(n=>n.getPluginData('rainlink-upgrade-gallery')==='true');
  for(const t of gallery.findAll(n=>n.type==='TEXT'))if(/主列表点击连接/.test(t.characters)){t.characters='组卡片点击选中，节点入口进入列表。组内点击节点记住选择；连接与代理模式由概览管理。';t.setPluginData('rainlink-original-text',t.characters);}
  add(gallery,uText('概览 · 代理模式组件',18,'Text','Medium'),instance('Overview / Proxy mode / Desktop'),instance('Overview / Proxy mode / Mobile'));
  const over=uFind(dsPage,'Delivery / Overview');
  for(const t of over.findAll(n=>n.type==='TEXT'))if(t.characters==='添加即归组，选择即可连接。')t.characters='添加即归组，选择与连接各司其职。';
  let y=gallery.y+gallery.height+100;
  for(const c of dsPage.children.filter(n=>n.type==='COMPONENT'&&(n.getPluginData('rainlink-group-component')===G_VERSION||n.getPluginData('rainlink-upgrade-component')==='2.0'))){c.x=3250;c.y=y;y+=c.height+50;}
}
function gNavAction(target) {
  const [p,...bits]=target.split('/'),key=bits.join('/'),reg=p==='D'?registry.desktop:registry.mobile,dest=reg[key];
  if(!dest)throw new Error('Missing overview destination '+target);
  const action=id=>({type:'NODE',destinationId:id,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false});
  if(key==='Dashboard'||key==='Home')return {type:'CONDITIONAL',conditionalBlocks:[{condition:{type:'VARIABLE_ALIAS',resolvedType:'BOOLEAN',value:gAlias('VPN/已开启')},actions:[action(dest.id)]},{actions:[action(reg.Disconnected.id)]}]};
  return action(dest.id);
}
async function gWire() {
  const valid=new Set([...Object.values(registry.desktop),...Object.values(registry.mobile)].map(n=>n.id)),edges=[];
  const rootOf=n=>{let root=n;while(root.parent&&root.parent.type!=='PAGE')root=root.parent;return root;};
  const links=new Map();
  for(const l of [...pending,...uLinks])if(l.node&&!l.node.removed&&l.node.opacity>=.5&&valid.has(rootOf(l.node).id))links.set(l.node.id,l);
  // Remove inherited interactions first. Custom variable actions are assigned last.
  for(const page of [desktopPage,mobilePage])for(const n of page.findAll(n=>'reactions'in n&&n.reactions.length))await n.setReactionsAsync([]);
  let count=0;
  for(const l of links.values()){
    const action=gNavAction(l.target);await l.node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[action]}]);
    edges.push({from:l.node.id,target:l.target,label:l.node.name,kind:'navigate'});
    if(++count%100===0)figma.ui.postMessage({status:'原型导航 '+count+' / '+links.size});
  }
  const stateEdges=[];
  for(const {node,actions,kind}of gActions.values()){
    if(node.removed||!valid.has(rootOf(node).id))continue;
    const resolved=actions.map(a=>a.rainlinkTarget?gNavAction(a.rainlinkTarget):a);
    await node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:resolved}]);
    stateEdges.push({node:node.id,screen:rootOf(node).id,kind,actions:resolved});
  }
  desktopPage.flowStartingPoints=[{nodeId:registry.desktop.Disconnected.id,name:'桌面端 / 概览开启 VPN'},{nodeId:registry.desktop.Profiles.id,name:'桌面端 / 自动归组与选择'}];
  mobilePage.flowStartingPoints=[{nodeId:registry.mobile.Disconnected.id,name:'移动端 / 概览开启 VPN'},{nodeId:registry.mobile.Profiles.id,name:'移动端 / 自动归组与选择'}];
  figma.root.setPluginData('rainlink-overview-controls',JSON.stringify({version:'4.0',workspaceRemoved:true,selectionDoesNotConnect:true,powerOnlyOnOverview:true,proxyModeOnlyOnOverview:true,groupRemembersNode:true,pendingChoiceWhileConnected:true,chainSaveSelectsOnly:true,interactionVariables:Object.keys(gVars).length,stateEdgeCount:stateEdges.length,stateEdgeSample:true,stateEdges:stateEdges.slice(0,60)}));
  return edges;
}
function gV4Report(report) {
  report.overviewControls=JSON.parse(figma.root.getPluginData('rainlink-overview-controls'));
  Object.assign(report.groupModel,{selectionDoesNotConnect:true,vpnControlPage:'概览',proxyModeControlPage:'概览',workspaceSelector:false,chainSaveSelectsOnly:true});
  const bound=desktopPage.findAll(n=>n.boundVariables&&Object.keys(n.boundVariables).length).length+mobilePage.findAll(n=>n.boundVariables&&Object.keys(n.boundVariables).length).length;
  report.overviewControls.boundNodes=bound;
  figma.root.setPluginData('rainlink-report',JSON.stringify(report));
  const audit=uFind(dsPage,'Delivery / Native audit');if(audit){audit.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);audit.visible=false;}
  return report;
}
