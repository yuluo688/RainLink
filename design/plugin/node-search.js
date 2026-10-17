// RainLink 7.4: search the node inventory without adding application screens.
// Figma uses representative keyword variants; runtime text entry belongs to the app.
const R74_SEARCH='节点搜索工作区';
function r74Inventory(){
  const groups={'主订阅':G_MAIN,'备用订阅':G_BACKUP,'未分组':G_LOOSE,'旅行订阅':G_MAIN.slice(0,4)};
  return Object.entries(groups).flatMap(([group,nodes])=>nodes.map((data,index)=>({group,index,data,key:group+'-'+index})));
}
function r74Match(items,query){
  const terms=query.normalize('NFKC').trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
  return items.filter(({data})=>terms.every(term=>[data.name,data.p,data.region].join(' ').normalize('NFKC').toLocaleLowerCase().includes(term)));
}
function r74FieldMaster(mobile){
  const name='输入 / 节点搜索 / '+(mobile?'移动端':'桌面端');
  let c=masters[name];if(c)return c;
  c=masters['Input / Default'].clone();dsPage.appendChild(c);r6Name(c,name);masters[name]=c;
  c.primaryAxisSizingMode=c.counterAxisSizingMode='FIXED';c.resize(mobile?353:440,mobile?44:40);
  c.paddingLeft=12;c.paddingRight=mobile?0:4;c.itemSpacing=8;rad(c,8);
  const value=uFind(c,'Value');r6Copy(value,'搜索节点名称、协议或地区');value.layoutSizingHorizontal='FILL';value.fontSize=13;
  const clear=r6Name(r6Button('','Ghost','close',mobile?44:32),'清空节点搜索');
  if(mobile)r72IconButton(clear);else r73DesktopIconButton(clear);
  clear.visible=false;add(c,clear);c.setPluginData('rainlink-node-search-component','7.4');
  c.description='全分组搜索，匹配节点名称、协议或地区；不区分大小写。清空恢复分组浏览。移动端清空按钮为 44 px。';
  c.x=mobile?500:0;c.y=Math.max(...dsPage.children.filter(n=>n!==c&&n.visible).map(n=>n.y+n.height))+80;
  return c;
}
function r74Field(mobile,query){
  const n=r7Instance(r74FieldMaster(mobile),'节点搜索输入框'),value=uFind(n,'Value'),clear=uFind(n,'清空节点搜索');
  r6Copy(value,query||'搜索节点名称、协议或地区');fill(value,query?'Text':'Muted');clear.visible=!!query;
  if(query)stroke(n,'Primary');n.setPluginData('rainlink-search-query',query);
  return n;
}
function r74AddToolbar(c,source,mobile,query){
  const bar=source.clone(),field=r74Field(mobile,query);r6Name(bar,'节点操作');
  if(mobile){add(c,field,bar);}
  else{
    bar.primaryAxisAlignItems='MIN';bar.itemSpacing=12;bar.insertChild(1,field);
    const gap=r6Name(row('搜索工具栏留白',1,1),'搜索工具栏留白');bar.insertChild(2,gap);gap.layoutSizingHorizontal='FILL';
    add(c,bar);
  }
  return field;
}
function r74Empty(w,mobile,query){
  const n=r6Name(v('节点搜索无结果',w,12,0),'节点搜索无结果');n.resize(w,mobile?240:260);n.primaryAxisSizingMode='FIXED';
  n.primaryAxisAlignItems=n.counterAxisAlignItems='CENTER';
  add(n,miniIcon('search','Muted',40,'Raised'),r6Text('未找到匹配节点',16,'Text','Medium'),r6Text('没有与“'+query+'”匹配的节点',13,'Muted','Regular',mobile?300:420),r6Text('试试其他名称、协议或地区，或清空搜索。',12,'Muted','Regular',mobile?300:420),r6Name(r6Button('清空搜索','Secondary',null,mobile?136:120),'清空搜索结果'));
  for(const t of n.children.filter(n=>n.type==='TEXT'))t.textAlignHorizontal='CENTER';return n;
}
async function r74Build(mobile){
  // Newly-created result sections inherit the current page before they enter
  // the shared component. Resolve overlay routes on their platform page.
  await figma.setCurrentPageAsync(mobile?mobilePage:desktopPage);
  const platform=mobile?'移动端':'桌面端',screen=(mobile?registry.mobile:registry.desktop).Nodes,content=uFind(screen,'Content'),w=mobile?353:1120;
  const old=dsPage.children.find(n=>n.type==='COMPONENT_SET'&&r5Name(n)==='交互 / '+platform+' / 节点搜索');
  const installed=uFind(screen,R74_SEARCH);
  if(old&&installed)return {set:old.id,initial:(await installed.getMainComponentAsync()).id,variants:old.children.map(n=>({id:n.id,name:n.name,query:n.getPluginData('rainlink-search-query'),selected:n.getPluginData('rainlink-search-selection'),resultCount:r74Match(r74Inventory(),n.getPluginData('rainlink-search-query')).length})),field:r74FieldMaster(mobile).id,reused:true};
  if(old&&!installed)old.remove();
  const sourceBar=uFind(content,'节点操作'),sourceList=uFind(content,'节点分组与选择');
  if(!sourceBar||!sourceList)throw new Error(platform+'节点工具栏或列表缺失');
  const inventory=r74Inventory(),queries=['日本','HTTP','火星'],states={},entries=[{query:'',selected:'主订阅-0'}];
  for(const query of queries){
    entries.push({query,selected:'主订阅-0'});
    for(const item of r74Match(inventory,query))if(item.key!=='主订阅-0')entries.push({query,selected:item.key});
  }
  for(const {query,selected}of entries){
    const c=r7Body('查询='+(query||'全部')+', 选中='+selected,w);c.itemSpacing=mobile?10:16;
    c.setPluginData('rainlink-node-search-component','7.4');c.setPluginData('rainlink-search-query',query);c.setPluginData('rainlink-search-selection',selected);
    r74AddToolbar(c,sourceBar,mobile,query);
    if(!query)add(c,sourceList.clone());
    else{
      const matches=r74Match(inventory,query),list=r6Name(v('节点搜索结果',w,mobile?10:12),'节点搜索结果');
      add(list,r6Text('全部分组 · '+matches.length+' 个结果',12,'Muted'));
      if(!matches.length)add(list,r74Empty(w,mobile,query));
      else for(const group of [...new Set(matches.map(n=>n.group))]){
        const items=matches.filter(n=>n.group===group),section=r6Name(v('搜索分组 · '+group,w,mobile?8:0),'搜索分组 · '+group);
        const heading=row('搜索结果所属分组',w,32,8);heading.paddingLeft=mobile?0:16;
        add(heading,icon('folder',14,'Muted'),r6Text(group,12,'Secondary'),r6Text(String(items.length),11,'Muted'));add(section,heading);
        if(!mobile){const header=r5TableHeader();header.resize(w,36);add(section,header);}
        for(const item of items){
          const n=gNode(item.data,mobile,item.key===selected,group==='未分组');r6Name(n,'搜索节点 · '+item.key);
          const protocol=uFind(n,'节点协议');if(protocol)r6Copy(protocol.findOne(n=>n.type==='TEXT'),item.data.p);
          n.setPluginData('rainlink-search-item-key',item.key);n.setPluginData('rainlink-search-item-group',group);
          if(mobile)r72NodeLayout(n);else r73DesktopNodeLayout(n);
          add(section,n);
          const move=uFind(n,'未分组节点移动');if(group==='未分组'&&move)await move.setReactionsAsync(r7Click((mobile?registry.mobile:registry.desktop)['Move group'].id,'OVERLAY'));
        }
        add(list,section);
      }
      add(c,list);
    }
    states[query+'|'+selected]=c;
  }
  const set=r7VariantSet('交互 / '+platform+' / 节点搜索',Object.values(states),mobile?3:2);
  const initial=states['|主订阅-0'];
  for(const [key,c]of Object.entries(states)){
    const query=c.getPluginData('rainlink-search-query'),next=query===''?'日本':query==='日本'?'HTTP':query==='HTTP'?'火星':'日本';
    const field=uFind(c,'节点搜索输入框');await field.setReactionsAsync(r7Click(states[next+'|主订阅-0'].id));
    for(const name of ['清空节点搜索','清空搜索结果']){const clear=uFind(c,name);if(clear)await clear.setReactionsAsync(c.id===initial.id?[]:r7Click(initial.id));}
    for(const node of c.findAll(n=>n.type==='INSTANCE'&&!!n.getPluginData('rainlink-search-item-key'))){
      const itemKey=node.getPluginData('rainlink-search-item-key'),dest=states[query+'|'+itemKey];
      if(dest&&dest.id!==c.id)await node.setReactionsAsync(r7Click(dest.id));else await node.setReactionsAsync([]);
    }
  }
  const top=Math.max(...dsPage.children.filter(n=>n!==set&&n.visible).map(n=>n.y+n.height))+80;set.x=0;set.y=top;
  const at=content.children.indexOf(sourceBar);sourceBar.remove();sourceList.remove();
  const view=r7Instance(initial,R74_SEARCH);content.insertChild(at,view);
  screen.setPluginData('rainlink-node-search-version','7.4');
  return {set:set.id,initial:initial.id,variants:Object.values(states).map(c=>({id:c.id,name:c.name,query:c.getPluginData('rainlink-search-query'),selected:c.getPluginData('rainlink-search-selection'),resultCount:r74Match(inventory,c.getPluginData('rainlink-search-query')).length})),field:r74FieldMaster(mobile).id};
}
async function r74ApplySearch(report){
  // Remove only unfinished search builds left by an interrupted update.
  for(const c of [...dsPage.children])if(c.type==='COMPONENT'&&c.getPluginData('rainlink-node-search-component')==='7.4'&&c.name.startsWith('查询='))c.remove();
  for(const page of [desktopPage,mobilePage])for(const n of [...page.children])if(n.type==='FRAME'&&(r5Name(n)==='节点搜索结果'||r5Name(n).startsWith('搜索分组 · ')))n.remove();
  const desktop=await r74Build(false),mobile=await r74Build(true),items=r74Inventory();
  for(const result of [desktop,mobile]){
    const set=await figma.getNodeByIdAsync(result.set);
    for(const c of set.children)for(const n of c.findAll(n=>n.type==='INSTANCE'&&!!n.getPluginData('rainlink-search-item-key'))){
      const selected=n.getPluginData('rainlink-search-item-key')===c.getPluginData('rainlink-search-selection'),check=uFind(n,'节点选中');
      if(check)check.visible=selected;
    }
  }
  // Keep the active navigation item consistent with the node page title.
  for(const [reg,mobile]of [[registry.desktop,false],[registry.mobile,true]]){
    const nav=uFind(reg.Nodes,mobile?'Mobile / Bottom navigation':'Primary navigation');
    for(const tab of nav.children){
      const label=tab.findOne(n=>n.type==='TEXT'),active=label?.characters==='节点';
      if(!mobile)fill(tab,active?'PrimarySurface':null);
      if(label)fill(label,active?'Primary':mobile?'Muted':'Secondary');
      const mark=tab.findOne(n=>n.type==='INSTANCE');if(mark)tint(mark,active?'Primary':mobile?'Muted':'Secondary');
    }
  }
  const samples=Object.fromEntries(['日本','http','  HTTP  ','日本 VLESS','zzzz'].map(q=>[q,r74Match(items,q).map(n=>n.key)]));
  if(!samples['日本'].length||!samples.http.some(k=>k.startsWith('未分组-'))||samples.http.join()!==samples['  HTTP  '].join()||samples.zzzz.length)throw new Error('节点搜索匹配核验失败');
  for(const reg of [registry.desktop,registry.mobile]){
    const view=uFind(reg.Nodes,R74_SEARCH),field=uFind(view,'节点搜索输入框');
    if(!view||!field||field.height<(reg===registry.mobile?44:40))throw new Error('节点搜索输入框未安装');
  }
  const noteName='节点搜索 / 交互说明';let note=dsPage.children.find(n=>r5Name(n)===noteName);
  if(!note){note=borderCard(noteName,1120,null,24,12,'Surface');r6Name(note,noteName);dsPage.appendChild(note);add(note,r6Text('节点搜索 · 两端统一',22,'Text','Medium'),r6Text('覆盖所有分组，按节点名称、协议、地区做不区分大小写的包含匹配；空白查询恢复分组浏览。多个关键词取交集。',14,'Secondary','Regular',1072),r6Text('结果按所属分组呈现，选择不启动 VPN；未分组节点继续保留移动入口。清空恢复浏览，不改变应用中的选择。',14,'Secondary','Regular',1072),r6Text('原型演示：点击输入框依次查看“日本”“HTTP”和无结果；点击 × 或清空按钮回到列表。筛选及选中采用组件变体，不增加整页。',13,'Muted','Regular',1072),r6Text('实际产品：文本输入后即时筛选，Esc 清空，失焦保留查询；组名与已选目标保留在应用状态。Figma 使用示例关键词，不模拟任意文本输入。',13,'Muted','Regular',1072));note.x=0;note.y=Math.max(...dsPage.children.filter(n=>n!==note&&n.visible).map(n=>n.y+n.height))+80;}
  report.version='7.4';report.counts.components=dsPage.findAll(n=>n.type==='COMPONENT').length;
  report.counts.instances=[desktopPage,mobilePage,dsPage].reduce((sum,p)=>sum+p.findAll(n=>n.type==='INSTANCE').length,0);
  report.nodeSearch={version:'7.4',scope:'all groups',fields:['name','protocol','region'],caseInsensitive:true,trimWhitespace:true,multipleTerms:'AND',clearToBrowse:true,selectionStartsVpn:false,screensAdded:0,desktopInputHeight:40,mobileInputHeight:44,desktop,mobile,samples,prototypeInput:'Representative keywords; native Figma component variants',note:note.id};
  figma.root.setPluginData('rainlink-node-search-version','7.4');
  if(figma.root.getPluginData('rainlink-settings-version')==='7.5')await r75ApplySettings(report);
  return report.nodeSearch;
}
async function r74SearchMain(){
  figma.showUI('<body style="padding:24px;background:#151617;color:#c0c2c8;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#8adcbf">RainLink / 节点搜索</h2><p id="s">加入搜索、分组结果和清空状态…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:480,height:170});
  await r5Initialize();figma.skipInvisibleInstanceChildren=false;await r71Palette();
  const report=JSON.parse(figma.root.getPluginData('rainlink-report'));await r74ApplySearch(report);await r71VerifyControls(report);
  const audit=await r5AuditDocument();report.overflow=audit.overflow;report.untranslatedDisplayCopy=audit.untranslatedDisplayCopy;
  delete report.nativeBackup;delete report.screenshotVerification;
  const auditText=uFind(dsPage,'Delivery / Native audit');auditText.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);auditText.visible=false;
  figma.root.setPluginData('rainlink-report',JSON.stringify(report));
  await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Nodes];figma.viewport.scrollAndZoomIntoView(figma.currentPage.selection);
  figma.notify('两端节点搜索已加入 · 搜索与清空复用组件状态');figma.closePlugin();
}
