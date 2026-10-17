// RainLink 5: adapt awesome-design-md to native client UI, preserving screen IDs and reactions.
const R5_COLORS={
 Background:['#0F1011','#FAFAFA'],Surface:['#151617','#FFFFFF'],Raised:['#1B1C1E','#F4F4F5'],
 Hover:['#242528','#ECECEE'],Stroke:['#2B2D31','#E4E4E7'],Text:['#F4F4F6','#18191B'],
 Secondary:['#C0C2C8','#55585F'],Muted:['#969AA3','#696D75'],Primary:['#8ADCBF','#08795C'],
 PrimarySurface:['#1B2B25','#E7F5EE'],OnPrimary:['#10241C','#FFFFFF'],Success:['#8ADCBF','#08795C'],
 Warning:['#E8BC78','#955F0D'],WarningSurface:['#30281D','#FFF3DE'],Error:['#F28B96','#BD354A'],
 ErrorSurface:['#302125','#FFEAEF'],Info:['#A5BDF7','#316BC1'],InfoSurface:['#202737','#EBF1FD'],
 Chart2:['#9DAAF1','#6876C8'],Transparent:['#0F1011','#FAFAFA']
};
const R5_TOKEN_NAMES={Background:'背景',Surface:'界面表层',Raised:'浮起表层',Hover:'悬停',Stroke:'边框',Text:'主要文字',Secondary:'次要文字',Muted:'弱化文字',Primary:'主色',PrimarySurface:'主色表层',OnPrimary:'主色上文字',Success:'成功',Warning:'警告',WarningSurface:'警告表层',Error:'错误',ErrorSurface:'错误表层',Info:'信息',InfoSurface:'信息表层',Chart2:'图表辅助色',Transparent:'透明'};
const r5Name=n=>n.getPluginData('rainlink-canonical-name')||n.name;
function r5Walk(root,insideInstances=false){const out=[],walk=n=>{out.push(n);if('children'in n&&(insideInstances||n.type!=='INSTANCE'))for(const c of n.children)walk(c);};for(const n of root.children||[])walk(n);return out;}
const r5Yield=()=>new Promise(r=>setTimeout(r,20));
function r5Width(n,w,h=null){if(!n)return;n.resize(w,h===null?n.height:h);}
function r5Text(n,s){if(!n)return;n.characters=s;n.setPluginData('rainlink-original-text',s);}
function r5Fixed(n,w,h=null){if(!n)return;r5Width(n,w,h);if(n.layoutMode==='HORIZONTAL')n.primaryAxisSizingMode='FIXED';else if(n.layoutMode==='VERTICAL')n.counterAxisSizingMode='FIXED';}
async function r5Initialize(){
 figma.skipInvisibleInstanceChildren=true;
 figma.ui.postMessage({status:'载入三个文档页…'});await figma.loadAllPagesAsync();
 figma.ui.postMessage({status:'载入稿件使用的中文字体…'});const stored=JSON.parse(figma.root.getPluginData('rainlink-report'));zhFamily=stored.chineseFont.family;zhStyles=stored.chineseFont.styles;for(const style of new Set(Object.values(zhStyles)))await figma.loadFontAsync({family:zhFamily,style});
 figma.ui.postMessage({status:'载入数字与代码字体…'});for(const style of ['Regular','Medium','Semi Bold','Bold'])await figma.loadFontAsync({family:'Inter',style});await figma.loadFontAsync({family:'Roboto Mono',style:'Regular'});
 figma.ui.postMessage({status:'索引共享组件与状态画面…'});
 desktopPage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='desktop');mobilePage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='mobile');dsPage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='system');
 for(const [reg,page,prefix]of [[registry.desktop,desktopPage,'desktop/'],[registry.mobile,mobilePage,'mobile/']])for(const s of page.findAll(n=>n.type==='FRAME'&&n.getPluginData('rainlink').startsWith(prefix)))reg[s.getPluginData('rainlink').slice(prefix.length)]=s;
 for(const c of dsPage.findAll(n=>n.type==='COMPONENT')){
  const name=r5Name(c);if(name.startsWith('Icon / '))icons[name.slice(7)]=c;
  else if(name.startsWith('Style=')){const p=name.split(', ');masters['Button / '+p[0].slice(6)+' / '+p[1].slice(5)]=c;}
  else if(name.startsWith('Tone='))masters['Badge / '+name.slice(5)]=c;else masters[name]=c;
 }
}
async function r5Palette(){
 const prior={...C},hexMap={};for(const k of Object.keys(R5_COLORS))for(let i=0;i<2;i++)hexMap[prior[k][i].toUpperCase()]=R5_COLORS[k][i];
 const collections=await figma.variables.getLocalVariableCollectionsAsync();collection=collections.find(c=>/Colors \/ Dark|颜色 \/ 深色/.test(c.name));lightCollection=collections.find(c=>/Colors \/ Light|颜色 \/ 浅色/.test(c.name));darkMode=collection.defaultModeId;
 const keyOf=name=>Object.keys(R5_TOKEN_NAMES).find(k=>name===k||name===R5_TOKEN_NAMES[k]);
 const local=await figma.variables.getLocalVariablesAsync('COLOR');
 for(const variable of local){
  const key=keyOf(variable.name),index=variable.variableCollectionId===lightCollection.id?1:0;
  if(key&&(variable.variableCollectionId===collection.id||variable.variableCollectionId===lightCollection.id)){
   const col=collections.find(c=>c.id===variable.variableCollectionId);for(const mode of col.modes)variable.setValueForMode(mode.modeId,{...rgb(R5_COLORS[key][index]),a:1});(index?lightVars:vars)[key]=variable;
  }else for(const [mode,value]of Object.entries(variable.valuesByMode))if(value&&'r'in value){const next=hexMap['#'+[value.r,value.g,value.b].map(x=>Math.round(x*255).toString(16).padStart(2,'0')).join('').toUpperCase()];if(next)variable.setValueForMode(mode,{...rgb(next),a:value.a===undefined?1:value.a});}
 }
 Object.assign(C,R5_COLORS);
 const recolor=color=>{const hex='#'+[color.r,color.g,color.b].map(x=>Math.round(x*255).toString(16).padStart(2,'0')).join('').toUpperCase();const next=hexMap[hex];return next?{...color,...rgb(next)}:color;};
 function convert(p){if(p.type==='SOLID'&&!p.boundVariables?.color){const color=recolor(p.color);return color===p.color?p:{...p,color};}if(p.gradientStops){let changed=false;const stops=p.gradientStops.map(s=>{const color=recolor(s.color);if(color!==s.color)changed=true;return color===s.color?s:{...s,color};});return changed?{...p,gradientStops:stops}:p;}return p;}
 let count=0;
 const layers=[...r5Walk(dsPage),...r5Walk(desktopPage),...r5Walk(mobilePage)];
 // Light screens have explicit color overrides; all other instances inherit their shared masters.
 for(const screen of [registry.desktop['Dashboard light'],registry.mobile['Home light']])if(screen)for(const n of screen.findAll(n=>n.type==='INSTANCE'))layers.push(...r5Walk(n,true));
 for(const n of layers){
  for(const field of ['fills','strokes'])if(field in n&&Array.isArray(n[field])){const paints=n[field],next=paints.map(convert);if(next.some((p,i)=>p!==paints[i]))n[field]=next;}
  if('cornerRadius'in n&&n.cornerRadius!==figma.mixed){if(n.cornerRadius===14||n.cornerRadius===16)n.cornerRadius=12;else if(n.cornerRadius===10)n.cornerRadius=8;}
  if(n.type==='TEXT'&&/#[0-9A-Fa-f]{6}/.test(n.characters)){const next=n.characters.replace(/#[0-9A-Fa-f]{6}/g,h=>hexMap[h.toUpperCase()]||h);if(next!==n.characters)r5Text(n,next);}
  if(++count%750===0){figma.ui.postMessage({status:'更新共享表层与颜色 '+count+' 层…'});await r5Yield();}
 }
 return count;
}
function r5GroupLayout(c,mobile){
 const w=mobile?353:1120;c.layoutMode=mobile?'VERTICAL':'HORIZONTAL';c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.resize(w,mobile?128:96);c.paddingLeft=c.paddingRight=mobile?16:20;c.paddingTop=c.paddingBottom=mobile?12:20;c.itemSpacing=mobile?8:16;c.counterAxisAlignItems='CENTER';rad(c,12);
 const head=uFind(c,'Group heading'),copy=uFind(c,'Group copy'),bottom=uFind(c,'Group current node'),facts=uFind(c,'Group current identity');
 r5Fixed(head,mobile?319:544);r5Width(copy,mobile?213:458);r5Fixed(bottom,mobile?319:518,mobile?44:44);
 if(facts&&!mobile){facts.primaryAxisSizingMode='FIXED';r5Width(facts,392);facts.itemSpacing=16;}
 const node=uFind(c,'组当前节点'),ping=uFind(c,'组延迟');if(!mobile){r5Width(node,270,20);node.textAutoResize='HEIGHT';node.fontSize=14;node.lineHeight={unit:'PIXELS',value:20};r5Width(ping,90,20);ping.textAutoResize='HEIGHT';ping.fontName={family:'Roboto Mono',style:'Regular'};}
 const detail=uFind(c,'组节点入口');if(detail){r5Width(detail,detail.width,mobile?44:40);detail.cornerRadius=8;}
}
function r5NodeLayout(c,mobile){
 c.resize(mobile?353:1120,mobile?112:68);rad(c,mobile?12:0);c.paddingLeft=c.paddingRight=16;c.paddingTop=c.paddingBottom=mobile?14:12;c.itemSpacing=mobile?8:0;
 if(mobile){const star=uFind(c,'节点收藏');if(star)r5Width(star,44,44);return;}
 const line=uFind(c,'Node row'),identity=uFind(c,'Node identity'),facts=uFind(c,'Node facts');r5Fixed(line,1086,44);line.itemSpacing=16;
 r5Fixed(identity,602);if(identity?.children[1])r5Width(identity.children[1],558);
 r5Fixed(facts,468);facts.primaryAxisAlignItems='MIN';facts.itemSpacing=16;
 const tag=uFind(c,'节点协议'),ping=uFind(c,'节点延迟');if(tag){tag.primaryAxisSizingMode='FIXED';r5Width(tag,120);tag.primaryAxisAlignItems='CENTER';}
 if(ping){r5Width(ping,88,20);ping.textAutoResize='HEIGHT';ping.fontName={family:'Roboto Mono',style:'Regular'};ping.lineHeight={unit:'PIXELS',value:20};}
 for(const name of ['节点收藏','未分组节点移动']){const b=uFind(c,name);if(b)r5Width(b,b.width,36);}
}
function r5TableHeader(){
 const h=row('节点表格列头',1120,40,16,16,'Raised');h.setPluginData('rainlink-canonical-name','Node table headings');
 add(h,uSmall('节点与地区','Muted',602),uSmall('协议','Muted',120),uSmall('延迟','Muted',88),uSmall('操作','Muted',180));return h;
}
function r5DesktopList(screen){
 const groupArea=uFind(screen,'Group workspace'),nodeArea=uFind(screen,'Group node workspace');let removed=0;
 if(groupArea){
  const list=uFind(groupArea,'Group list');for(const n of [...groupArea.children])if(n!==list){n.remove();removed++;}
  r5Width(groupArea,1120);groupArea.counterAxisAlignItems='MIN';groupArea.itemSpacing=0;r5Width(list,1120);list.itemSpacing=12;
  const helper=uFind(screen,'Group toolbar')?.children.find(n=>n.type==='TEXT');if(helper)r5Text(helper,'点击分组选中；点「节点」查看组内列表。');
 }
 if(nodeArea){
  const list=uFind(nodeArea,'Group node inventory'),aside=uFind(nodeArea,'Selected group node'),toolbar=uFind(screen,'Group node toolbar');
  if(aside){
   const chain=aside.children.find(n=>n.type==='INSTANCE'&&n.findOne(t=>t.type==='TEXT'&&t.characters==='代理链'));
   if(chain&&toolbar&&!uFind(toolbar,'Node toolbar actions')){const speed=toolbar.children[toolbar.children.length-1],actions=row('节点工具栏操作',null,40,8);actions.setPluginData('rainlink-canonical-name','Node toolbar actions');r5Width(chain,110,40);chain.primaryAxisSizingMode='AUTO';chain.primaryAxisAlignItems='CENTER';add(actions,chain,speed);add(toolbar,actions);}
   aside.remove();removed++;
  }
  r5Width(nodeArea,1120);nodeArea.counterAxisAlignItems='MIN';r5Width(list,1120);rad(list,12);list.clipsContent=true;list.itemSpacing=0;
  if(!uFind(list,'Node table headings'))list.insertChild(0,r5TableHeader());
  for(const n of list.children)if(n.type==='RECTANGLE'&&n.height<=1)r5Width(n,1120);
 }
 const bar=uFind(screen,'Connection bar');if(bar)r5Width(bar,bar.width,56);
 const pageHead=uFind(screen,'Page header'),title=pageHead&&pageHead.findOne(n=>n.type==='TEXT'&&n.fontSize>=24);if(title){title.fontSize=26;title.lineHeight={unit:'PIXELS',value:36};}
 return {screen:screen.id,name:screen.name,groupList:!!groupArea,nodeList:!!nodeArea,removedPanels:removed};
}
function r5SystemNotes(){
 const gallery=dsPage.children.find(n=>n.getPluginData('rainlink-upgrade-gallery')==='true');
 if(gallery){for(const name of ['Group components','Grouped node components']){const strip=uFind(gallery,name);if(strip){strip.layoutMode='VERTICAL';strip.primaryAxisSizingMode='AUTO';strip.counterAxisSizingMode='FIXED';strip.counterAxisAlignItems='MIN';strip.resize(1404,strip.height);strip.itemSpacing=24;}}
  if(!uFind(gallery,'Design MD adoption')){const note=borderCard('Design MD adoption',1404,null,24,12);note.setPluginData('rainlink-canonical-name','Design MD adoption');add(note,uText('设计规范 · 工具界面',20,'Text','Medium'),uSmall('参考 awesome-design-md：Linear 的表层与细边框，Vercel 的列对齐，Raycast 的紧凑控件。','Secondary',1356),uSmall('保留 RainLink 薄荷绿。节点与分组单列展示；选中后在概览开启 VPN。','Muted',1356));add(gallery,note);}
 }
 const foundations=uFind(dsPage,'Design System / Foundations');if(foundations){const principles=foundations.findAll(n=>n.type==='TEXT');for(const t of principles){if(t.characters.includes('Lots of whitespace'))r5Text(t,'留白建立层级，列表内容优先。');}}
 let y=1000;
 for(const c of dsPage.children.filter(n=>n.type==='COMPONENT'&&n.getPluginData('rainlink-group-component'))){c.x=4870;c.y=y;y+=c.height+48;}
 const copyUpdates={'个人工作区':'旅行订阅','设计系统 · 1.0':'设计系统 · 5.0','页面标题 · 28 / 41':'页面标题 · 26 / 36','圆角 / 控件 8 · 列表行 12 · 卡片 16 · 浮层 24':'圆角 / 控件 8 · 卡片 12 · 浮层 24','配置名称':'分组名称','导入配置':'导入订阅'};
 for(const t of dsPage.findAll(n=>n.type==='TEXT'))if(copyUpdates[t.characters])r5Text(t,copyUpdates[t.characters]);
 for(const reg of [registry.desktop,registry.mobile])if(reg['Connected switch'])reg['Connected switch'].name=(reg===registry.desktop?'桌面端':'移动端')+' / 连接中切换分组';
}
async function r5PolishDocument(){
 const paletteLayers=await r5Palette();figma.ui.postMessage({status:'简化分组与节点列表…'});
 for(const mobile of [false,true]){r5GroupLayout(masters['Group / '+(mobile?'Mobile':'Desktop')],mobile);r5NodeLayout(masters['Group node / '+(mobile?'Mobile':'Desktop')],mobile);}
 const affected=[];
 for(const [reg,mobile]of [[registry.desktop,false],[registry.mobile,true]])for(const s of Object.values(reg)){
  for(const n of r5Walk(s).filter(n=>n.type==='INSTANCE')){const name=r5Name(n);if(name.startsWith('Group · ')||name==='Group / Desktop'||name==='Group / Mobile')r5GroupLayout(n,mobile);else if(name.startsWith('Group node / '))r5NodeLayout(n,mobile);}
  if(!mobile)affected.push(r5DesktopList(s));
  else for(const n of s.findAll(n=>n.type==='TEXT'))if(n.characters==='这里只选择，连接请前往概览。')r5Text(n,'选中后，在概览开启 VPN。');
  if(affected.length%12===0){figma.ui.postMessage({status:'整理状态画面 '+s.name+'…'});await r5Yield();}
 }
 for(const n of dsPage.findAll(n=>n.type==='INSTANCE')){const name=r5Name(n);if(name==='Group / Desktop')r5GroupLayout(n,false);if(name==='Group / Mobile')r5GroupLayout(n,true);if(name==='Group node / Desktop')r5NodeLayout(n,false);if(name==='Group node / Mobile')r5NodeLayout(n,true);}
 r5SystemNotes();figma.ui.postMessage({status:'核验所有状态画面、中文与 Auto Layout…'});
 const report=await r5AuditDocument();report.version='5.0';report.designMdPolish={reference:'https://github.com/VoltAgent/awesome-design-md',documents:['design-md/linear.app/DESIGN.md','design-md/vercel/DESIGN.md','design-md/raycast/DESIGN.md'],adaptation:'客户端界面；中性表层、细边框、紧凑控件、列对齐；保留品牌主色',paletteLayers,affectedDesktopLists:affected.filter(x=>x.groupList||x.nodeList),removedPanels:affected.reduce((s,x)=>s+x.removedPanels,0),allDesktopSelectionPanelsRemoved:!desktopPage.findOne(n=>['Selection summary','Selected group node'].includes(r5Name(n))),nodeToolbarChainEntry:true,tokens:R5_COLORS};
 report.livePrototypeVerification={status:'pending refreshed scan'};delete report.nativeBackup;delete report.screenshotVerification;
 figma.root.setPluginData('rainlink-design-md-version','5.0');figma.root.setPluginData('rainlink-report',JSON.stringify(report));const audit=uFind(dsPage,'Delivery / Native audit');audit.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);audit.visible=false;
 return report;
}
async function r5AuditDocument(){
 const report=JSON.parse(figma.root.getPluginData('rainlink-report')),overflow=[],missing=[];
 let inspected=0;
 for(const page of [dsPage,desktopPage,mobilePage]){
  for(const n of r5Walk(page))if(!n.getPluginData('rainlink-canonical-name')){n.setPluginData('rainlink-canonical-name',n.name);n.name=zhLayerName(n.name);}
  if(page===dsPage)continue;
  for(const screen of page.findAll(n=>n.type==='FRAME'&&n.getPluginData('rainlink'))){
   for(const n of screen.findAll(()=>true)){
    let hidden=false;for(let ancestor=n;ancestor&&ancestor!==screen.parent;ancestor=ancestor.parent)if('visible'in ancestor&&!ancestor.visible){hidden=true;break;}if(hidden)continue;
    if(n.type==='TEXT'&&n.visible&&/[a-zA-Z]{3,}/.test(n.characters)&&!/[\u3400-\u9fff]/.test(n.characters)&&!isTechnicalText(n.characters))missing.push({id:n.id,text:n.characters});
    if(!['FRAME','INSTANCE'].includes(n.type)||!n.layoutMode||n.layoutMode==='NONE')continue;
    const canonical=r5Name(n);if(canonical==='Scrollable content'||canonical.startsWith('Icon /'))continue;
    const cs=n.children.filter(c=>c.visible&&c.layoutPositioning!=='ABSOLUTE');if(!cs.length)continue;
    if(n.layoutMode==='VERTICAL'&&n.primaryAxisSizingMode==='FIXED'){const edge=Math.max(...cs.map(c=>c.y+c.height));if(edge>n.height+2)overflow.push({screen:screen.name,id:n.id,name:n.name,axis:'vertical',amount:Math.round(edge-n.height)});}
    if(n.layoutMode==='HORIZONTAL'&&n.primaryAxisSizingMode==='FIXED'){const edge=Math.max(...cs.map(c=>c.x+c.width));if(edge>n.width+2)overflow.push({screen:screen.name,id:n.id,name:n.name,axis:'horizontal',amount:Math.round(edge-n.width)});}
   }
   if(++inspected%16===0){figma.ui.postMessage({status:'核验布局 '+inspected+' / 326…'});await r5Yield();}
  }
 }
 report.overflow=overflow;report.untranslatedDisplayCopy=missing;return report;
}
async function r5PolishMain(){
 figma.showUI('<body style="padding:24px;background:#151617;color:#c0c2c8;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#8adcbf">RainLink / 设计优化</h2><p id="s">载入现有页面与共享组件…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:480,height:170});
 await r5Yield();await r5Initialize();const report=await r5PolishDocument();await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Nodes,registry.desktop.Profiles];figma.viewport.scrollAndZoomIntoView(figma.currentPage.selection);figma.notify('设计已优化 · 移除 '+report.designMdPolish.removedPanels+' 个重复信息卡 · '+report.overflow.length+' 处排版待检');figma.closePlugin();
}
