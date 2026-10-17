// Public egress designs. RFC 5737 addresses and all geographic results are fixtures.
// The production UI reads both IP and ISO country from the same network probe.
// No request is sent to an IP / location service by this design plugin.
const R6_EGRESS = {
  direct: { ip: '198.51.100.86', country: '中国', code: 'CN' },
  proxy: { ip: '203.0.113.24', country: '日本', code: 'JP' }
};
const r6NetworkSets = {};
const R6_EGRESS_STATES = ['已获取', '检测中', '获取失败', '国家未获取'];

function r6FlagLibrary() {
  const star = (cx, cy, r, color) => {
    const points = Array.from({ length: 10 }, (_, i) => {
      const a = -Math.PI / 2 + i * Math.PI / 5, radius = i % 2 ? r * .382 : r;
      return (cx + Math.cos(a) * radius).toFixed(3) + ',' + (cy + Math.sin(a) * radius).toFixed(3);
    }).join(' ');
    return '<polygon points="' + points + '" fill="' + color + '"/>';
  };
  const artwork = {
    CN: '<path fill="#DE2910" d="M0 0h30v20H0z"/>' + star(5, 5, 3, '#FFDE00') +
      [[10,2],[12,4],[12,7],[10,9]].map(([x,y]) => star(x,y,1,'#FFDE00')).join(''),
    JP: '<path fill="#FFFFFF" d="M0 0h30v20H0z"/><circle cx="15" cy="10" r="6" fill="#BC002D"/>',
    SG: '<path fill="#EF3340" d="M0 0h30v10H0z"/><path fill="#FFFFFF" d="M0 10h30v10H0z"/><circle cx="7" cy="5" r="3.5" fill="#FFFFFF"/><circle cx="8.4" cy="5" r="3" fill="#EF3340"/>' + [[12,2.5],[14,4],[13.2,6.5],[10.8,6.5],[10,4]].map(([x,y])=>star(x,y,.85,'#FFFFFF')).join(''),
    US: '<path fill="#FFFFFF" d="M0 0h30v20H0z"/>' + Array.from({length:7},(_,i)=>'<path fill="#B22234" d="M0 '+(i*40/13)+'h30v'+(20/13)+'H0z"/>').join('') + '<path fill="#3C3B6E" d="M0 0h12v10.77H0z"/>' + Array.from({length:20},(_,i)=>star(1.3+(i%5)*2.35,1.3+Math.floor(i/5)*2.4,.56,'#FFFFFF')).join(''),
    GB: '<path fill="#012169" d="M0 0h30v20H0z"/><path d="m0 0 30 20M30 0 0 20" stroke="#FFFFFF" stroke-width="5"/><path d="m0 0 30 20M30 0 0 20" stroke="#C8102E" stroke-width="2"/><path d="M15 0v20M0 10h30" stroke="#FFFFFF" stroke-width="7"/><path d="M15 0v20M0 10h30" stroke="#C8102E" stroke-width="4"/>',
    DE: '<path fill="#000000" d="M0 0h30v6.667H0z"/><path fill="#DD0000" d="M0 6.667h30v6.666H0z"/><path fill="#FFCE00" d="M0 13.333h30V20H0z"/>',
    NL: '<path fill="#AE1C28" d="M0 0h30v6.667H0z"/><path fill="#FFFFFF" d="M0 6.667h30v6.666H0z"/><path fill="#21468B" d="M0 13.333h30V20H0z"/>'
  };
  for (const [code, svg] of Object.entries(artwork)) {
    const name = '国家图标 / ' + code;
    let c = masters[name];
    if (!c) c = component(name, n => {
      n.resize(24,16); n.primaryAxisSizingMode='FIXED'; n.counterAxisSizingMode='FIXED';
      n.layoutMode='HORIZONTAL'; n.clipsContent=true; rad(n,3);
      const vector = figma.createNodeFromSvg('<svg xmlns="http://www.w3.org/2000/svg" width="30" height="20" viewBox="0 0 30 20">' + svg + '</svg>');
      vector.resize(24,16); vector.name='国旗矢量'; add(n,vector);
    });
    r6Name(c,name); c.setPluginData('rainlink-egress-component','6.0');
    c.x=9850+Object.keys(artwork).indexOf(code)*84;c.y=7400;
    c.description='ISO 国家代码 '+code+'。与检测返回的国家名称一起显示；无国家信息时使用地球图标。';
  }
}

function r6NetworkKey(mobile, online, mode, status) {
  return (mobile?'移动端':'桌面端')+' / '+(online?'VPN 开启':'VPN 关闭')+' / '+mode+' / '+status;
}

function r6NetworkMode(mobile, mode) {
  const w=mobile?353:1120, c=borderCard('代理模式区',w,mobile?88:56,12,mobile?8:0);
  rad(c,12);
  if (!mobile) { c.layoutMode='HORIZONTAL'; c.primaryAxisAlignItems='SPACE_BETWEEN'; c.counterAxisAlignItems='CENTER'; }
  add(c,r6Text('代理模式',14,'Text','Medium'));
  const tabs=row('代理模式选项',mobile?329:324,36,4,0);
  for (const s of G_MODES) {
    const n=center(rad(row('出口模式 · '+s,mobile?107:105,36,0,0,s===mode?'PrimarySurface':'Raised'),8));
    r6Name(n,'出口模式 · '+s); add(n,r6Text(s,13,s===mode?'Primary':'Secondary','Medium')); add(tabs,n);
  }
  add(c,tabs);
  return c;
}

function r6EgressCard(mobile, online, mode, status) {
  const w=mobile?353:1120, iw=w-32, path=online&&mode!=='直连'?'proxy':'direct', data=R6_EGRESS[path];
  const valid=['已获取','国家未获取'].includes(status), countryOk=status==='已获取';
  const c=borderCard('当前出口信息',w,mobile?null:88,mobile?12:16,mobile?4:0); rad(c,12);
  const refresh=r6Button('', 'Ghost','refresh',44); r6Name(refresh,'刷新出口');
  const title=r6Text('当前出口',12,'Muted');
  const ip=r6Text(valid?data.ip:status==='检测中'?'正在检测…':'未获取',mobile?17:22,valid?'Text':status==='检测中'?'Secondary':'Muted','Medium',mobile?210:456);
  r6Name(ip,valid?'已获取公网 IP':status==='检测中'?'公网 IP 检测中':'公网 IP 获取失败');
  if(valid)ip.fontName={family:'Roboto Mono',style:'Regular'};
  const country=row('检测国家与图标',null,24,8);
  add(country,countryOk?masters['国家图标 / '+data.code].createInstance():icon('globe',20,'Muted'),r6Text(countryOk?data.country:status==='检测中'?'检测中':'未获取',14,countryOk?'Text':'Muted','Medium'));
  const caption=(path==='proxy'?'代理出口':'直连出口')+' · '+(status==='检测中'?'等待检测结果':status==='获取失败'?'检测失败，可重试':'10:32 更新');
  if(mobile){
    const mw=w-24;
    add(c,between(add(row('出口标题行',mw,24),title,country)),between(add(row('出口地址与刷新',mw,null),add(v('出口地址',250,2),ip,r6Text(caption,11,'Muted')),refresh)));
  }else{
    c.layoutMode='HORIZONTAL';c.primaryAxisAlignItems='SPACE_BETWEEN';c.counterAxisAlignItems='CENTER';
    add(c,add(v('出口地址',456,2),title,ip),add(v('出口国家',210,3),r6Text('国家 / 地区',12,'Muted'),country),add(v('出口检测时间',260,3),r6Text(caption,12,'Secondary'),r6Text('公网 IP 以当前出口检测为准',11,'Muted')),refresh);
  }
  c.setPluginData('rainlink-egress-status',status); c.setPluginData('rainlink-egress-path',path);
  return c;
}

async function r6NetworkLibrary() {
  r6FlagLibrary();
  for (const mobile of [false,true]) for(const online of [false,true]) {
    const name='概览 / 出口与模式 / '+(mobile?'移动端':'桌面端')+' / '+(online?'VPN 开启':'VPN 关闭');
    let set=dsPage.children.find(n=>n.type==='COMPONENT_SET'&&r5Name(n)===name);
    if(set){
      for(const c of set.children){
        const mode=c.getPluginData('rainlink-egress-mode'),status=c.getPluginData('rainlink-egress-status');
        for(const n of [...c.children])n.remove();
        c.itemSpacing=12;add(c,r6NetworkMode(mobile,mode),r6EgressCard(mobile,online,mode,status));
        r6NetworkSets[r6NetworkKey(mobile,online,mode,status)]=c;
      }
    } else {
      const children=[];
      for(const mode of G_MODES) for(const status of R6_EGRESS_STATES){
        const canonical=r6NetworkKey(mobile,online,mode,status);
        const c=component('模式='+mode+', 检测='+status,n=>{
          n.layoutMode='VERTICAL';n.resize(mobile?353:1120,1);n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='FIXED';n.itemSpacing=12;
          add(n,r6NetworkMode(mobile,mode),r6EgressCard(mobile,online,mode,status));
        });
        c.setPluginData('rainlink-egress-component','6.0');c.setPluginData('rainlink-egress-mode',mode);c.setPluginData('rainlink-egress-status',status);
        c.description='检测请求使用当前出站。地址与国家来自同一结果；规则模式只说明该检测请求的出口。此处为设计示例。';
        r6NetworkSets[canonical]=c;children.push(c);
      }
      set=figma.combineAsVariants(children,dsPage); r6Name(set,name);
      set.layoutMode='VERTICAL';set.primaryAxisSizingMode='AUTO';set.counterAxisSizingMode='AUTO';set.itemSpacing=24;set.paddingLeft=set.paddingRight=set.paddingTop=set.paddingBottom=24;
    }
    set.x=9850+(mobile?1220:0);set.y=online?3600:0;
    for(const mode of G_MODES)for(const status of R6_EGRESS_STATES){
      const c=r6NetworkSets[r6NetworkKey(mobile,online,mode,status)];
      const change=dest=>[{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:dest.id,navigation:'CHANGE_TO',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18}}]}];
      for(const option of G_MODES){
        const n=uFind(c,'出口模式 · '+option),next=r6NetworkSets[r6NetworkKey(mobile,online,option,'检测中')];
        await n.setReactionsAsync(option===mode?[]:change(next));
      }
      for(const n of c.findAll(n=>r5Name(n)==='刷新出口'))await n.setReactionsAsync(status==='检测中'?[]:change(r6NetworkSets[r6NetworkKey(mobile,online,mode,'检测中')]));
      await c.setReactionsAsync(status==='检测中'?[{trigger:{type:'AFTER_TIMEOUT',timeout:1.0},actions:[{type:'NODE',destinationId:r6NetworkSets[r6NetworkKey(mobile,online,mode,'已获取')].id,navigation:'CHANGE_TO',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18}}]}]:[]);
    }
  }
}

function r6NetworkInstance(mobile,online,mode='规则',status='已获取'){
  const n=r6NetworkSets[r6NetworkKey(mobile,online,mode,status)].createInstance();r6Name(n,'概览出口与模式');
  n.setPluginData('rainlink-egress-instance','6.0');return n;
}

function r6CompactMobileOverview(screen){
  const content=uFind(screen,'Content');if(content)content.itemSpacing=12;
  const hero=uFind(screen,'VPN control');
  if(hero&&!uFind(hero,'连接状态摘要')){
    const ring=uFind(hero,'VPN power button'),copy=v('连接状态摘要',217,6);
    for(const text of [...hero.children].filter(n=>n.type==='TEXT'||r5Name(n)==='VPN mode caption')){
      if(text.type==='TEXT'){text.resize(217,text.height);text.textAutoResize='HEIGHT';}
      add(copy,text);
    }
    add(hero,copy);hero.layoutMode='HORIZONTAL';hero.resize(353,120);hero.primaryAxisSizingMode='FIXED';hero.counterAxisSizingMode='AUTO';hero.primaryAxisAlignItems='MIN';hero.counterAxisAlignItems='CENTER';hero.paddingLeft=hero.paddingRight=hero.paddingTop=hero.paddingBottom=16;hero.itemSpacing=16;
    if(ring){ring.resize(88,88);hero.insertChild(0,ring);}
  }
  const target=uFind(screen,'Selected connection group');
  if(target&&!uFind(target,'概览节点与延迟')){
    const facts=uFind(target,'Selected group node'),node=target.children.find(n=>n.type==='TEXT'),ping=facts?.children[facts.children.length-1];
    if(node&&ping){const line=between(row('概览节点与延迟',321,null,8));node.resize(231,node.height);node.textAutoResize='HEIGHT';add(line,node,ping);facts.remove();target.insertChild(1,line);target.itemSpacing=8;target.primaryAxisSizingMode='AUTO';}
  }
  const speeds=uFind(screen,'Mobile live speed');
  if(speeds){
    speeds.resize(353,64);
    for(const card of speeds.children){
      if(card.type!=='FRAME')continue;card.paddingTop=card.paddingBottom=card.paddingLeft=card.paddingRight=8;card.itemSpacing=3;card.resize(card.width,64);
      for(const text of card.findAll(n=>n.type==='TEXT')){if(text.fontSize>=20){text.fontSize=20;text.lineHeight={unit:'PIXELS',value:29};}else if(text.characters==='MB/s'){text.fontSize=11;text.lineHeight={unit:'PIXELS',value:16};}}
      for(const child of card.children)if('resize'in child)child.resize(card.width-16,child.height);
    }
  }
}

function r6InsertEgress(screen,mobile,status='已获取'){
  const old=uFind(screen,'概览出口与模式')||screen.findOne(n=>n.type==='INSTANCE'&&r5Name(n).startsWith('Overview / Proxy mode / '));
  if(!old)return false;
  const parent=old.parent,index=parent.children.indexOf(old),online=screen.getPluginData('rainlink-overview-online')==='true';
  const mode=screen.getPluginData('rainlink-egress-mode')||(/Mode direct/.test(screen.getPluginData('rainlink'))?'直连':/Mode global/.test(screen.getPluginData('rainlink'))?'全局':'规则');
  old.remove();const n=r6NetworkInstance(mobile,online,mode,status);parent.insertChild(index,n);screen.setPluginData('rainlink-egress-mode',mode);
  if(mobile)r6CompactMobileOverview(screen);
  if(!mobile){
    parent.itemSpacing=12;
    const hero=uFind(screen,'Connection group hero');if(hero){hero.paddingTop=hero.paddingBottom=20;hero.itemSpacing=12;hero.primaryAxisSizingMode='AUTO';}
    const charts=uFind(screen,'Connection trends');if(charts){charts.resize(1120,210);for(const c of charts.children){if('resize'in c)c.resize(c.width,210);}}
  }
  if(/light/.test(screen.getPluginData('rainlink')))applyLight(n);
  screen.setPluginData('rainlink-egress-status',status);r6Changes.add(screen.id);return true;
}

async function r6EgressUpdate(){
  await r6NetworkLibrary();const counts={desktop:0,mobile:0},switches=[];
  for(const [reg,mobile]of [[registry.desktop,false],[registry.mobile,true]])for(const s of Object.values(reg)){
    if(s.getPluginData('rainlink-egress-transition')||s.getPluginData('rainlink-egress-example'))continue;
    if(r6InsertEgress(s,mobile))counts[mobile?'mobile':'desktop']++;
  }
  // Power transitions temporarily remove stale addresses. Native timer frames return
  // to the existing target screen and preserve the selected group and node.
  for(const [reg,mobile,page]of [[registry.desktop,false,desktopPage],[registry.mobile,true,mobilePage]]){
    const registryById=Object.fromEntries(Object.entries(reg).map(([key,n])=>[n.id,key]));
    const sourceScreens=Object.values(reg).filter(s=>!s.getPluginData('rainlink-egress-transition'));
    for(const screen of sourceScreens){
      for(const power of screen.findAll(n=>n.getPluginData('rainlink-control-kind')==='vpn-power')){
        const reactions=JSON.parse(JSON.stringify(power.reactions));let changed=false;
        for(const r of reactions)for(const a of r.actions||[])if(a.type==='NODE'&&a.navigation==='NAVIGATE'){
          let dest=reg[registryById[a.destinationId]];if(!dest)continue;
          if(dest.getPluginData('rainlink-egress-transition'))dest=reg[dest.getPluginData('rainlink-egress-target')];
          if(!dest||!uFind(dest,'概览出口与模式'))continue;
          const key='出口检测中 · '+registryById[dest.id];let loading=reg[key];
          if(!loading){loading=dest.clone();page.appendChild(loading);reg[key]=loading;}
          r6Name(loading,(mobile?'移动端':'桌面端')+' / '+key);loading.setPluginData('rainlink',(mobile?'mobile/':'desktop/')+key);
          loading.setPluginData('rainlink-egress-transition','6.0');loading.setPluginData('rainlink-egress-target',registryById[dest.id]);
          r6InsertEgress(loading,mobile,'检测中');
          await loading.setReactionsAsync([{trigger:{type:'AFTER_TIMEOUT',timeout:1.2},actions:[{type:'NODE',destinationId:dest.id,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18}}]}]);
          a.destinationId=loading.id;changed=true;switches.push({source:screen.id,power:power.id,loading:loading.id,destination:dest.id});
        }
        if(changed)await power.setReactionsAsync(reactions);
      }
    }
    for(const [key,status]of [['出口获取失败','获取失败'],['出口国家未获取','国家未获取']]){
      let s=reg[key];if(!s){s=reg[mobile?'Home':'Dashboard'].clone();page.appendChild(s);reg[key]=s;}
      r6Name(s,(mobile?'移动端':'桌面端')+' / 概览 / '+key);s.setPluginData('rainlink',(mobile?'mobile/':'desktop/')+key);s.setPluginData('rainlink-egress-example','6.0');r6InsertEgress(s,mobile,status);
    }
  }
  const name='公网出口 / 组件与检测规范';let gallery=dsPage.children.find(n=>r5Name(n)===name);if(gallery)gallery.remove();
  gallery=borderCard(name,1500,null,32,24,'Background');dsPage.appendChild(gallery);r6Name(gallery,name);gallery.x=6500;gallery.y=4200;
  add(gallery,r6Text('当前出口 · IP、国家与国旗',28,'Text','Medium'),r6Text('设计示例使用文档网段。产品按当前路径实测公网出口，IP 与国家来自同一检测结果。',14,'Secondary','Regular',1436));
  const flags=row('国家图标组件',1436,44,20);for(const code of ['CN','JP','SG','US','GB','DE','NL'])add(flags,masters['国家图标 / '+code].createInstance());add(flags,icon('globe',20,'Muted'));add(gallery,flags);
  for(const status of R6_EGRESS_STATES)add(gallery,r6Text(status,14,'Secondary'),r6NetworkInstance(false,true,'规则',status));
  add(gallery,r6Text('检测行为',20,'Text','Medium'),r6Text('VPN 关闭：直连检测。VPN 开启：经当前代理检测；直连模式仍检测直连出口。规则模式展示检测请求出口，不代表所有应用都使用该出口。',14,'Secondary','Regular',1436),r6Text('VPN、模式或实际出站变化立即清空旧结果并检测；仅改选待应用节点不刷新当前出口。手动刷新进入检测中，失败不保留旧 IP。',14,'Secondary','Regular',1436),r6Text('国家由结果的 ISO 国家代码生成国旗，不读取节点名或地区标签。只获取到 IP 时显示地址、地球图标与“未获取”；支持长 IPv6 地址换行。',14,'Secondary','Regular',1436));
  const mobiles=row('移动端出口状态',1436,null,24);for(const status of ['已获取','检测中','获取失败'])add(mobiles,r6NetworkInstance(true,true,'规则',status));add(gallery,mobiles);
  return {version:'6.0',counts,fields:['公网 IP','国旗','国家 / 地区','检测路径','更新时间','刷新'],countryIcon:'Reusable vector flag selected by detected ISO country; globe when missing',usesDetectedEgress:true,nodeRegionNotUsed:true,fixtureDataOnly:true,noLiveNetworkRequest:true,invalidateOn:['VPN toggle','proxy mode change','effective outbound change'],selectionOnlyKeepsCurrentEgress:true,statuses:R6_EGRESS_STATES,powerTransitions:switches,systemGallery:gallery.id};
}
