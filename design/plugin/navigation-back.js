// Shared back navigation for the compact product and its reusable detail states.
function r76BackMaster(){
  let c=dsPage.findOne(n=>n.type==='COMPONENT'&&n.getPluginData('rainlink-navigation-back-master')==='1');
  if(!c){
    c=figma.createComponent();r6Name(c,'导航 / 返回箭头');c.setPluginData('rainlink-navigation-back-master','1');
    const slot=icons['返回'].createInstance();r6Name(slot,'返回图标');c.appendChild(slot);slot.resize(24,24);
    const parent=icons['返回'].parent;parent.appendChild(c);c.x=80;c.y=104;
  }
  // Update the existing master in place so every detail state keeps its identity.
  c.layoutMode='HORIZONTAL';c.primaryAxisSizingMode=c.counterAxisSizingMode='FIXED';c.resize(44,44);c.primaryAxisAlignItems=c.counterAxisAlignItems='CENTER';c.fills=[];c.strokes=[];rad(c,10);c.clipsContent=false;
  let plate=c.children.find(n=>r5Name(n)==='返回按钮底板');
  if(!plate){plate=r6Name(frame('返回按钮底板',36,36,'HORIZONTAL'),'返回按钮底板');c.insertChild(0,plate);plate.layoutPositioning='ABSOLUTE';}
  plate.resize(36,36);plate.x=4;plate.y=4;fill(plate,'Raised');stroke(plate,'Stroke');rad(plate,10);
  c.description='标题左侧返回。36 px 圆角可视按钮，44 px 点击区域；与标题间距 4 px。';
  return c;
}
function r76BackIcon(n,name='返回箭头'){
  n.swapComponent(r76BackMaster());
  r6Name(n,name);n.setPluginData('rainlink-back-navigation','top-left');
  for(const t of n.findAll(x=>x.type==='TEXT')){r6Copy(t,'');t.visible=false;}
  const slot=n.children.find(x=>x.type==='INSTANCE');if(!slot)throw new Error(name+' 缺少图标槽');
  slot.visible=true;
  n.primaryAxisSizingMode=n.counterAxisSizingMode='FIXED';n.resize(44,44);
  n.paddingLeft=n.paddingRight=n.paddingTop=n.paddingBottom=0;n.primaryAxisAlignItems=n.counterAxisAlignItems='CENTER';rad(n,10);slot.layoutSizingHorizontal=slot.layoutSizingVertical='FIXED';slot.resize(24,24);return n;
}
function r76DetailHeader(title,desc,mobile,route){
  const w=mobile?353:912,header=r6Name(row('设置详情返回导航',w,52,4),'设置详情返回导航');
  add(header,r75Route(r76BackIcon(r75Button('','Ghost','返回',44),'返回'+(route==='首页'?'设置':route)+'箭头'),route),r75Copy(title,desc,w-48,mobile?20:22));return header;
}
function r76ReturnText(n){return n.type==='INSTANCE'&&n.children.some(t=>t.type==='TEXT'&&t.visible&&/^(返回|Back\b)/.test(t.characters));}
function r76Remove(n,removed){removed.push({id:n.id,name:r5Name(n)});n.remove();}
function r76Actions(n){return(n.reactions||[]).flatMap(r=>r.actions||[]);}
async function r76UpdateBackNavigation(report){
  if(!report.settingsUI)throw new Error('请先补全设置 UI');
  const records=[],removed=[];
  // Secondary settings return to their immediate parent, including every editor state.
  for(const [platform,mobile]of [['desktop',false],['mobile',true]]){
    const ui=report.settingsUI[platform];
    for(const [view,id]of Object.entries(ui.variants)){
      const legal=['隐私说明','开源许可'].includes(view),advanced=/配置/.test(view);
      if(!legal&&!advanced&&(!mobile||view==='首页'))continue;
      const c=await figma.getNodeByIdAsync(id),body=mobile?c:uFind(c,'设置详情'),route=legal?'关于':advanced?'核心引擎':'首页';
      let header=uFind(body,legal?'关于详情导航':'设置详情返回导航');
      if(!header){
        const texts=body.children.filter(n=>n.type==='TEXT'),title=texts[0],desc=texts[1];
        if(!title)throw new Error(platform+' '+view+' 标题缺失');
        header=r76DetailHeader(title.characters,desc?.characters||'',mobile,route);
        for(const n of [title,desc])if(n)n.remove();body.insertChild(0,header);
      }
      for(const n of [...body.children])if(r76ReturnText(n))r76Remove(n,removed);
      const back=header.children.find(n=>n.type==='INSTANCE');r76BackIcon(back,legal?'返回关于箭头':'返回'+(route==='首页'?'设置':route)+'箭头');
      header.itemSpacing=4;
      const copy=header.children.find(n=>n.type==='FRAME');copy.resize(header.width-48,copy.height);
      for(const t of copy.findAll(n=>n.type==='TEXT')){t.resize(header.width-48,t.height);t.textAutoResize='HEIGHT';}
      r75Route(back,route);await back.setReactionsAsync(r7Click(ui.variants[route]));
      records.push({scope:platform,view,id:back.id,header:header.id,container:body.id,destinationId:ui.variants[route],navigation:'CHANGE_TO'});
    }
  }
  // Product-page headers retain the existing content and use one 44 px back hit area.
  for(const [platform,key,parent]of [['desktop','Chain editor','Nodes'],['mobile','Quick switch','Home'],['mobile','DNS','BACK'],['mobile','Chain editor','Nodes']]){
    const mobile=platform==='mobile',reg=registry[platform],screen=reg[key],header=uFind(screen,'Page header');
    const title=header.children.find(n=>n.type==='FRAME'),back=header.children.find(n=>n.type==='INSTANCE');
    r76BackIcon(back,'返回'+(parent==='BACK'?'网络设置':parent==='Home'?'概览':'节点')+'箭头');header.insertChild(0,back);
    header.primaryAxisAlignItems='MIN';header.counterAxisAlignItems='CENTER';header.itemSpacing=4;
    const titleWidth=mobile?305:1072;title.resize(titleWidth,title.height);
    for(const t of title.findAll(n=>n.type==='TEXT')){t.resize(titleWidth,t.height);t.textAutoResize='HEIGHT';}
    if(parent==='BACK')await back.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'BACK'}]}]);
    else await back.setReactionsAsync(r7Click(reg[parent].id,'NAVIGATE'));
    const content=uFind(screen,'Content');for(const n of [...content.children])if(r76ReturnText(n))r76Remove(n,removed);
    records.push({scope:platform,view:key,id:back.id,header:header.id,container:screen.id,destinationId:parent==='BACK'?null:reg[parent].id,navigation:parent==='BACK'?'BACK':'NAVIGATE'});
  }
  // The chain editor already has a parent back arrow; group navigation remains in the sidebar.
  const chainSet=dsPage.findOne(n=>n.type==='COMPONENT_SET'&&r5Name(n)==='交互 / 桌面端 / 代理链编排');
  if(chainSet)for(const c of chainSet.children)for(const n of c.findAll(r76ReturnText))r76Remove(n,removed);
  // QR is a nested dialog step: back returns to URL import, close still dismisses the dialog.
  const qrComponents=dsPage.findAll(n=>n.type==='COMPONENT'&&(r5Name(n)==='弹窗 / 移动端 / qr / ready'||(r5Name(n)==='状态=扫码'&&r5Name(n.parent)==='交互 / 移动端 / 添加弹窗')));
  for(const c of qrComponents){
    const header=uFind(c,'弹窗标题'),title=header.children.find(n=>n.type==='TEXT'),close=header.children.find(n=>r5Name(n)==='关闭弹窗');
    let back=uFind(header,'返回链接导入箭头');if(!back){back=r76BackIcon(r6Button('','Ghost','返回',44),'返回链接导入箭头');header.insertChild(0,back);}
    r76BackIcon(back,'返回链接导入箭头');header.primaryAxisAlignItems='MIN';header.itemSpacing=4;title.resize(header.width-96,title.height);title.textAutoResize='HEIGHT';if(close)header.appendChild(close);
    for(const n of [...c.children])if(r76ReturnText(n))r76Remove(n,removed);
    const compact=c.parent.type==='COMPONENT_SET',destination=compact?c.parent.children.find(n=>r5Name(n)==='状态=订阅'):null;
    if(destination)await back.setReactionsAsync(r7Click(destination.id));
    records.push({scope:'mobile',view:compact?'扫码导入':'扫码导入组件母版',id:back.id,header:header.id,container:c.id,destinationId:destination?.id||null,navigation:compact?'CHANGE_TO':'BLUEPRINT'});
  }
  // Include unmodified pages and all component states in the residual-text audit.
  const textReturns=[];for(const page of [desktopPage,mobilePage,dsPage])for(const n of page.findAll(r76ReturnText))textReturns.push({id:n.id,name:r5Name(n)});
  report.backNavigation={version:'1.1',placement:'top-left',icon:'Icon / 返回',hitSize:44,visualSize:36,cornerRadius:10,titleGap:4,productScreens:23,pageCount:3,records,removedTextButtons:removed,residualTextReturns:textReturns};
  report.counts.components=dsPage.findAll(n=>n.type==='COMPONENT').length;
  report.counts.instances=[desktopPage,mobilePage,dsPage].reduce((sum,p)=>sum+p.findAll(n=>n.type==='INSTANCE').length,0);
  return report.backNavigation;
}
async function r76VerifyBackNavigation(report){
  const errors=[],check=(ok,msg)=>{if(!ok)errors.push(msg);},records=report.backNavigation.records;
  for(const record of records){
    const n=await figma.getNodeByIdAsync(record.id),header=await figma.getNodeByIdAsync(record.header),prefix=record.scope+' / '+record.view;
    check(n.parent===header&&header.children[0]===n,prefix+' 返回应在标题左侧');
    check(n.width===44&&n.height===44&&Math.abs(n.x-header.paddingLeft)<.1,prefix+' 返回位置或点击区域不统一');
    check(n.y>=-.1&&n.y+n.height<=header.height+.1,prefix+' 返回区域超出标题栏');
    const plate=n.children.find(t=>r5Name(t)==='返回按钮底板');
    check(plate&&plate.width===36&&plate.height===36&&plate.x===4&&plate.y===4&&plate.cornerRadius===10&&plate.fills.length>0,prefix+' 返回按钮底色或尺寸不统一');
    check(header.itemSpacing===4,prefix+' 返回与标题的间距未收紧');
    check(!n.findOne(t=>t.type==='TEXT'&&t.visible&&t.characters),prefix+' 仍显示返回文字');
    const slot=n.children.find(t=>t.type==='INSTANCE'&&t.visible),main=slot&&await slot.getMainComponentAsync();
    check(main&&r5Name(main)==='Icon / 返回'&&Math.abs(slot.width-24)<.1&&Math.abs(slot.height-24)<.1,prefix+' 箭头方向或尺寸不统一 ('+(main?r5Name(main):'missing')+' '+slot?.width+'×'+slot?.height+')');
    const actions=r76Actions(n);
    if(record.navigation==='BACK')check(actions.some(a=>a.type==='BACK'),prefix+' 返回未保留上层状态');
    else if(record.navigation!=='BLUEPRINT')check(actions.some(a=>a.destinationId===record.destinationId&&a.navigation===record.navigation),prefix+' 返回目标无效');
  }
  check(report.backNavigation.residualTextReturns.length===0,'文档内仍有文字返回按钮');
  check(figma.root.children.length===3,'文档页签数量改变');
  const screens=[desktopPage,mobilePage].flatMap(p=>p.findAll(n=>n.type==='FRAME'&&n.getPluginData('rainlink')));
  check(screens.length===23&&screens.every(n=>n.layoutMode!=='NONE'),'产品画面数量或 Auto Layout 改变');
  report.backNavigationVerification={verifiedAt:new Date().toISOString(),placement:'top-left',visualSize:36,titleGap:4,hitSize:44,arrows:records.length,interactiveArrows:records.filter(n=>n.navigation!=='BLUEPRINT').length,residualTextReturns:report.backNavigation.residualTextReturns,errors};
  if(errors.length)throw new Error('返回导航核验失败：'+errors.join('；'));
}
async function r76BackNavigationMain(){
  figma.showUI('<body style="padding:24px;background:#151617;color:#c0c2c8;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#8adcbf">RainLink / 返回导航</h2><p id="s">检查全部产品画面和组件状态…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:520,height:200});
  await r5Initialize();figma.skipInvisibleInstanceChildren=false;await r71Palette();const report=JSON.parse(figma.root.getPluginData('rainlink-report'));
  try{await r75ApplySettings(report);await r76UpdateBackNavigation(report);await r75VerifySettings(report);await r76VerifyBackNavigation(report);await r71VerifyControls(report);}
  catch(e){uFind(dsPage,'Delivery / Native audit').characters='RainLink 设计核验\n'+JSON.stringify({...report,backNavigationBuildError:String(e)+'\n'+String(e.stack||'')},null,2);throw e;}
  const audit=await r5AuditDocument();report.overflow=audit.overflow;report.untranslatedDisplayCopy=audit.untranslatedDisplayCopy;
  delete report.nativeBackup;delete report.screenshotVerification;delete report.backNavigationBuildError;
  const text=uFind(dsPage,'Delivery / Native audit');text.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);text.visible=false;figma.root.setPluginData('rainlink-report',JSON.stringify(report));
  await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop['Chain editor']];figma.viewport.scrollAndZoomIntoView(figma.currentPage.selection);figma.notify('两端返回已统一到左上角 · 保持 23 个产品画面');figma.closePlugin();
}
