// 简体中文为默认语言；原位更新，保留页面、组件与原型的 ID。
const ZH_LOCALE='zh-CN';
let zhFamily='', zhStyles={};
function zhText(s){return ZH_COPY[s]!==undefined?ZH_COPY[s]:ZH_NAMES[s]!==undefined?ZH_NAMES[s]:s;}
function zhLayerName(s){
 if(ZH_COPY[s]!==undefined||ZH_NAMES[s]!==undefined)return zhText(s);
 const dynamic=s.match(/^(Column|Line|Log|Size|Space|Step) (.*)$/);
 if(dynamic){const prefix={Column:'列',Line:'行',Log:'日志',Size:'尺寸',Space:'间距',Step:'步骤'}[dynamic[1]];return prefix+' '+zhLayerName(dynamic[2]);}
 if(s.includes(' · '))return s.split(' · ').map(zhLayerName).join(' · ');
 if(s.includes(' / '))return s.split(' / ').map(zhLayerName).join(' / ');
 if(s.startsWith('Style='))return s.replace('Style=','样式=').replace('Size=','尺寸=').replace(/Primary|Secondary|Ghost|Danger/g,m=>ZH_NAMES[m]);
 if(s.startsWith('Tone='))return '状态='+zhLayerName(s.slice(5));
 if(s.startsWith('Selected · '))return '已选中 · '+zhLayerName(s.slice(11));
 const suffix=s.match(/^(.*) (title|field|heading)$/);
 if(suffix)return zhLayerName(suffix[1])+{title:'标题',field:'输入区',heading:'标题'}[suffix[2]];
 return s;
}
async function loadChineseFonts(){
 const fonts=await figma.listAvailableFontsAsync();
 for(const family of ['Noto Sans SC','Source Han Sans SC','Source Han Sans CN','Microsoft YaHei','PingFang SC']){
  const available=fonts.filter(f=>f.fontName.family===family).map(f=>f.fontName.style);
  if(!available.length)continue;
  const choose=(prefs)=>prefs.find(s=>available.includes(s))||available[0];
  const mapping={Regular:choose(['Regular','Normal']),Medium:choose(['Medium','Regular']), 'Semi Bold':choose(['SemiBold','Semi Bold','Bold','Medium','Regular']),Bold:choose(['Bold','SemiBold','Semibold','Regular'])};
  try{for(const style of [...new Set(Object.values(mapping))])await figma.loadFontAsync({family,style});zhFamily=family;zhStyles=mapping;return;}catch(e){console.warn('中文字体不可用',family,String(e));}
 }
 throw new Error('未找到可用中文字体，请保持原稿并安装思源黑体或微软雅黑。');
}
async function restoreLocaleBaseline(){
 await figma.loadAllPagesAsync();
 const fontMap=new Map();
 for(const page of figma.root.children)for(const n of page.findAll(n=>n.type==='TEXT')){const fonts=n.characters.length?n.getRangeAllFontNames(0,n.characters.length):(n.fontName===figma.mixed?[]:[n.fontName]);for(const font of fonts)fontMap.set(font.family+'|'+font.style,font);}
 await Promise.all([...fontMap.values()].map(font=>figma.loadFontAsync(font)));
 for(const page of figma.root.children){
  const pn=page.getPluginData('rainlink-canonical-name');if(pn)page.name=pn;
  for(const n of page.findAll(()=>true)){
   const name=n.getPluginData('rainlink-canonical-name');if(name)n.name=name;
   const original=n.getPluginData('rainlink-original-text');
   if(n.type==='TEXT'&&original)n.characters=original;
  }
 }
 const raw=figma.root.getPluginData('rainlink-canonical-styles');if(raw){const old=JSON.parse(raw);
  for(const c of await figma.variables.getLocalVariableCollectionsAsync()){if(old.collections[c.id]){c.name=old.collections[c.id].name;for(const m of c.modes)c.renameMode(m.modeId,old.collections[c.id].modes[m.modeId]||m.name);}}
  for(const v of await figma.variables.getLocalVariablesAsync())if(old.variables[v.id])v.name=old.variables[v.id];
  for(const s of [...await figma.getLocalTextStylesAsync(),...await figma.getLocalEffectStylesAsync()])if(old.styles[s.id])s.name=old.styles[s.id];
 }
}
async function addDefaultLanguagePreferences(){
 const pages=figma.root.children;
 desktopPage=pages.find(p=>p.getPluginData('rainlink-role')==='desktop');mobilePage=pages.find(p=>p.getPluginData('rainlink-role')==='mobile');dsPage=pages.find(p=>p.getPluginData('rainlink-role')==='system');
 const canonical=n=>n.getPluginData('rainlink-canonical-name')||n.name;
 const d=desktopPage.children.find(n=>canonical(n)==='Desktop / Settings');
 if(d&&!d.findOne(n=>n.getPluginData('rainlink-language-row')==='true')){
  const c=d.findOne(n=>n.type==='FRAME'&&canonical(n)==='General'&&n.parent&&canonical(n.parent)==='General settings');
  c.paddingTop=c.paddingBottom=18;
  for(const r of c.children.filter(n=>canonical(n).startsWith('Setting · ')))r.resize(r.width,52);
  const model=c.children.find(n=>canonical(n)==='Setting · Launch at login');const r=model.clone();r.name='Setting · Language';r.setPluginData('rainlink-language-row','true');
  const texts=r.findAll(n=>n.type==='TEXT');texts[0].characters='语言';texts[1].characters='默认使用简体中文显示界面。';
  const previous=r.children.find(n=>n.type==='INSTANCE');const value=tx('简体中文（默认）',13,'Primary','Medium');if(previous)previous.remove();r.appendChild(value);
  const div=c.children.find(n=>canonical(n)==='Divider').clone();c.appendChild(div);c.appendChild(r);
 }
 const m=mobilePage.children.find(n=>canonical(n)==='Mobile / Settings');
 if(m&&!m.findOne(n=>n.getPluginData('rainlink-language-row')==='true')){
  const pref=m.findOne(n=>n.type==='FRAME'&&canonical(n)==='Preferences');const model=pref.children.find(n=>canonical(n)==='Theme');const r=model.clone();r.name='Language';r.setPluginData('rainlink-language-row','true');await r.setReactionsAsync([]);
  const texts=r.findAll(n=>n.type==='TEXT');texts[0].characters='语言';texts[1].characters='简体中文（默认）';
  const div=pref.children.find(n=>canonical(n)==='Divider').clone();pref.appendChild(div);pref.appendChild(r);
 }
 if(m){const r=m.findOne(n=>n.getPluginData('rainlink-language-row')==='true');const globe=dsPage.findOne(n=>n.type==='COMPONENT'&&canonical(n)==='Icon / globe');const ic=r&&r.findOne(n=>n.type==='INSTANCE'&&canonical(n)==='Icon / moon');if(ic&&globe){ic.swapComponent(globe);ic.name='Icon / globe';ic.setPluginData('rainlink-canonical-name','Icon / globe');}}
}
async function localizeDocument(){
 await figma.loadAllPagesAsync();await loadChineseFonts();
 for(const style of ['Regular','Medium','Semi Bold','Bold'])await figma.loadFontAsync({family:'Inter',style});await figma.loadFontAsync({family:'Roboto Mono',style:'Regular'});
 await addDefaultLanguagePreferences();
 const pages=[dsPage,desktopPage,mobilePage], snapshots=[];
 for(const page of pages)for(const n of page.findAll(()=>true))if(!n.getPluginData('rainlink-canonical-name'))n.setPluginData('rainlink-canonical-name',n.name);
 for(const page of pages)for(const n of page.findAll(n=>n.type==='TEXT'&&n.name!=='Delivery / Native audit'&&n.getPluginData('rainlink-canonical-name')!=='Delivery / Native audit'))snapshots.push({node:n,text:n.characters,font:n.fontName});
 // 捕获实例文案后再修改母版，避免继承变动丢失覆盖值。
 let translated=0;const missing=[];
 for(const {node:n,text:s,font} of snapshots){
  const canonical=x=>x.getPluginData('rainlink-canonical-name')||x.name;
  const tableHeader=s==='MATCH'&&n.parent&&n.parent.parent&&canonical(n.parent.parent)==='Table header';
  const next=tableHeader?'匹配内容':zhText(s);n.setPluginData('rainlink-original-text',s);if(next!==s){n.characters=next;translated++;}
  if(/[\u3400-\u9fff]/.test(next)){
   const weight=font!==figma.mixed&&zhStyles[font.style]?font.style:'Regular';const current=n.fontName;if(current===figma.mixed||current.family!==zhFamily||current.style!==zhStyles[weight])n.fontName={family:zhFamily,style:zhStyles[weight]};
   n.letterSpacing={unit:'PIXELS',value:0};if(n.textAutoResize==='NONE')n.textAutoResize='HEIGHT';
   if(font!==figma.mixed&&font.family==='Roboto Mono'){
    const re=/[\x20-\x7e]+/g;let match;while((match=re.exec(next)))n.setRangeFontName(match.index,match.index+match[0].length,{family:'Roboto Mono',style:'Regular'});
   }
  }
  if(/[a-zA-Z]{3,}/.test(next)&&next===s&&!/[\u3400-\u9fff]/.test(next)&&!isTechnicalText(next))missing.push({id:n.id,text:next});
 }
 for(const page of pages){
  if(!page.getPluginData('rainlink-canonical-name'))page.setPluginData('rainlink-canonical-name',page.name);
  page.name=page===desktopPage?'01 · 桌面端':page===mobilePage?'02 · 移动端':'03 · 设计系统、组件与流程';page.setPluginData('rainlink-locale',ZH_LOCALE);
  for(const n of page.findAll(()=>true)){
   if(n.name==='Delivery / Native audit')continue;
   const original=n.getPluginData('rainlink-canonical-name')||n.name;if(!n.getPluginData('rainlink-canonical-name'))n.setPluginData('rainlink-canonical-name',original);
   n.name=n.type==='TEXT'?n.characters.slice(0,55):zhLayerName(original);
   if(n.type==='COMPONENT'||n.type==='COMPONENT_SET')n.description='RainLink '+zhLayerName(original)+'。可复用原生组件，默认使用简体中文，支持自动布局和深浅主题。修改母版会同步到实例。';
  }
  page.flowStartingPoints=page.flowStartingPoints.map(f=>({...f,name:zhFlowName(f.name)}));
 }
 const collectionNames={'RainLink / Colors / Dark':'RainLink / 颜色 / 深色','RainLink / Colors / Light':'RainLink / 颜色 / 浅色','RainLink / Spacing & radius':'RainLink / 间距与圆角'};
 const old={collections:{},variables:{},styles:{}};
 for(const c of await figma.variables.getLocalVariableCollectionsAsync()){old.collections[c.id]={name:c.name,modes:Object.fromEntries(c.modes.map(m=>[m.modeId,m.name]))};c.name=collectionNames[c.name]||c.name;for(const m of c.modes)c.renameMode(m.modeId,zhText(m.name)==='Mode 1'?'默认':zhText(m.name));}
 const tokenNames={Background:'背景',Surface:'界面表层',Raised:'浮起表层',Hover:'悬停',Stroke:'边框',Text:'主要文字',Secondary:'次要文字',Muted:'弱化文字',Primary:'主色',PrimarySurface:'主色表层',OnPrimary:'主色上文字',Success:'成功',Warning:'警告',WarningSurface:'警告表层',Error:'错误',ErrorSurface:'错误表层',Info:'信息',InfoSurface:'信息表层',Chart2:'图表辅助色',Transparent:'透明',Space:'间距',Radius:'圆角'};
 for(const v of await figma.variables.getLocalVariablesAsync()){old.variables[v.id]=v.name;v.name=v.name.split('/').map(s=>tokenNames[s]||s).join('/');v.description='RainLink '+v.name+'语义变量';}
 for(const s of await figma.getLocalTextStylesAsync()){old.styles[s.id]=s.name;s.name=s.name.split(' / ').map(zhLayerName).join(' / ');if(s.name.endsWith('Subtitle'))s.name=s.name.replace('Subtitle','副标题');s.fontName={family:zhFamily,style:zhStyles[s.fontName.style]||zhStyles.Regular};s.description='简体中文界面字体；品牌和技术标识保留原文。';}
 for(const s of await figma.getLocalEffectStylesAsync()){old.styles[s.id]=s.name;s.name=s.name.replace('Floating panel','浮层阴影');s.description='用于弹窗与浮层的柔和阴影。';}
 const prior=figma.root.getPluginData('rainlink-canonical-styles');const baseline=prior?JSON.parse(prior):{collections:{},variables:{},styles:{}};
 for(const key of ['collections','variables','styles'])for(const [id,value]of Object.entries(old[key]))if(!baseline[key][id])baseline[key][id]=value;
 figma.root.setPluginData('rainlink-canonical-styles',JSON.stringify(baseline));
 figma.root.setPluginData('rainlink-locale',ZH_LOCALE);figma.root.setPluginData('rainlink-default-locale',ZH_LOCALE);
 const overflow=[];for(const page of [desktopPage,mobilePage])for(const screen of page.children.filter(n=>n.type==='FRAME'&&n.getPluginData('rainlink'))){
  for(const n of screen.findAll(n=>['FRAME','INSTANCE'].includes(n.type)&&n.layoutMode&&n.layoutMode!=='NONE')){
   const canonical=n.getPluginData('rainlink-canonical-name')||n.name;if(canonical==='Scrollable content'||canonical.startsWith('Icon /'))continue;
   const cs=n.children.filter(c=>c.visible&&c.layoutPositioning!=='ABSOLUTE');if(!cs.length)continue;
   if(n.layoutMode==='VERTICAL'&&n.primaryAxisSizingMode==='FIXED'){const edge=Math.max(...cs.map(c=>c.y+c.height));if(edge>n.height+2)overflow.push({screen:screen.name,id:n.id,name:n.name,axis:'vertical',amount:Math.round(edge-n.height)});}
   if(n.layoutMode==='HORIZONTAL'&&n.primaryAxisSizingMode==='FIXED'){const edge=Math.max(...cs.map(c=>c.x+c.width));if(edge>n.width+2)overflow.push({screen:screen.name,id:n.id,name:n.name,axis:'horizontal',amount:Math.round(edge-n.width)});}
  }
 }
 const raw=figma.root.getPluginData('rainlink-report');const report=raw?JSON.parse(raw):{};
 report.locale=ZH_LOCALE;report.defaultLocale=ZH_LOCALE;report.chineseFont={family:zhFamily,styles:zhStyles};report.localizedTextNodes=translated;report.untranslatedDisplayCopy=missing;report.overflow=overflow;
 report.counts={desktop:desktopPage.children.filter(n=>n.type==='FRAME'&&n.getPluginData('rainlink')).length,mobile:mobilePage.children.filter(n=>n.type==='FRAME'&&n.getPluginData('rainlink')).length,components:dsPage.findAll(n=>n.type==='COMPONENT').length,instances:desktopPage.findAll(n=>n.type==='INSTANCE').length+mobilePage.findAll(n=>n.type==='INSTANCE').length,prototypeInteractions:{desktop:desktopPage.findAll(n=>'reactions'in n).reduce((s,n)=>s+n.reactions.length,0),mobile:mobilePage.findAll(n=>'reactions'in n).reduce((s,n)=>s+n.reactions.length,0)}};
 report.flows={desktop:desktopPage.flowStartingPoints,mobile:mobilePage.flowStartingPoints};figma.root.setPluginData('rainlink-report',JSON.stringify(report));
 const audit=dsPage.findOne(n=>(n.getPluginData('rainlink-canonical-name')||n.name)==='Delivery / Native audit');if(audit){audit.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);audit.visible=false;}
 console.log('RAINLINK_ZH_AUDIT',JSON.stringify(report));return report;
}
function isTechnicalText(s){return !s.trim()||/^(RainLink|RAINLINK|Safari|DNS|YAML|JSON|URL|TCP|UDP|office-user|Shadowsocks|VLESS|VMess|Trojan|Hysteria|TUIC|SOCKS5|HTTP|WebSocket|sing-box|DOMAIN|GEOIP|IP-CIDR|MATCH|Esc)/.test(s)||/^\s+/.test(s)||/:|#|\d|^[A-Z]{2}$|\.(com|net|org|rs|yaml|json)(:\d+)?$/.test(s)||['proxies:','rules:','dns:','ms','MB','MB/s','GB'].includes(s);}
function zhFlowName(s){return {'Desktop / Connect & switch':'桌面端 / 连接与切换','Desktop / Import & configure':'桌面端 / 导入与配置','Mobile / Connect & switch':'移动端 / 连接与切换','Mobile / Import a profile':'移动端 / 导入配置','Mobile / Recover a connection':'移动端 / 连接恢复'}[s]||zhLayerName(s);}
async function localizeMain(){
 figma.showUI('<body style="padding:24px;background:#10181e;color:#a8bac5;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#86e5c3">RainLink / 中文默认界面</h2><p>正在更新文案、字体、组件和默认语言…</p></body>',{width:440,height:160});
 const report=await localizeDocument();await figma.setCurrentPageAsync(desktopPage);const overview=desktopPage.children.find(n=>(n.getPluginData('rainlink-canonical-name')||n.name)==='Desktop / Dashboard');figma.currentPage.selection=[overview];figma.viewport.scrollAndZoomIntoView([overview]);
 figma.notify('中文已设为默认 · '+report.counts.desktop+' 个桌面端页面 · '+report.counts.mobile+' 个移动端页面 · '+report.overflow.length+' 项排版待检');figma.closePlugin();
}
