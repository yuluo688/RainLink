// An in-place finish command: keeps existing screen and component identities.
async function finalizeDocument(){
 const find=(root,name)=>root.findOne(n=>n.name===name&&n.type!=='TEXT');
 const resize=(node,w,h)=>{if(node){node.resize(w,h);if(node.layoutMode==='VERTICAL')node.primaryAxisSizingMode='FIXED';}};
 // Native text wraps to its real height, so descriptions participate in Auto Layout.
 for(const page of [desktopPage,mobilePage,dsPage]){
  for(const n of page.findAll(n=>n.type==='TEXT'&&n.name!=='Delivery / Native audit'&&n.textAutoResize==='NONE'&&n.characters.length>=80&&n.fontName!==figma.mixed&&n.fontName.family==='Inter'))n.textAutoResize='HEIGHT';
 }
 const traffic=registry.desktop.Traffic;
 const trend=find(traffic,'Traffic over time');trend.itemSpacing=18;resize(find(trend,'Chart · traffic'),1072,132);resize(trend,1120,316);
 const ranking=find(traffic,'Usage by application');ranking.itemSpacing=12;resize(ranking,1120,232);
 const settings=registry.desktop.Settings;
 const nav=find(settings,'Settings navigation');resize(nav.children.find(n=>n.name==='Network'),196,40);
 const network=settings.findOne(n=>n.type==='FRAME'&&n.name==='Network'&&n.parent.name==='General settings');resize(network,876,224);resize(find(settings,'Settings layout'),1120,694);
 const editor=find(registry.desktop['Profile editor'],'YAML editor');
 for(const line of editor.children.filter(n=>n.name.startsWith('Line '))){line.paddingTop=line.paddingBottom=0;resize(line,1120,23);}
 const mobileRank=find(registry.mobile.Traffic,'Usage ranking');
 for(const line of mobileRank.children.filter(n=>['Browser','Code','Terminal'].includes(n.name)))line.itemSpacing=8;
 const qrCopy=registry.mobile['QR import'].findOne(n=>n.type==='TEXT'&&n.characters.startsWith('RainLink requests camera'));
 if(qrCopy)qrCopy.textAutoResize='HEIGHT';
 const route=async(source,dest)=>{if(source&&dest&&source.id!==dest.id)await source.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:dest.id,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false}]}]);};
 for(const button of registry.desktop['Nodes tested'].findAll(n=>n.name==='Button · Connect'))await route(button,registry.desktop.Dashboard);
 for(const card of registry.mobile['Nodes tested'].findAll(n=>n.type==='INSTANCE'&&n.name.startsWith('Node · ')))await route(card,registry.mobile['Node details']);
 const recovery=registry.mobile['Connection error'];
 await route(find(recovery,'Connection ring'),registry.mobile['Quick switch']);
 await route(find(recovery,'Button · Switch'),registry.mobile['Quick switch']);
 await route(find(recovery,'Button · View'),registry.mobile.Traffic);
 for(const card of recovery.findAll(n=>n.type==='INSTANCE'&&n.name.startsWith('Node · ')))await route(card,registry.mobile['Node details']);
 for(const tab of recovery.findAll(n=>n.name.startsWith('Tab · ')))await route(tab,registry.mobile[tab.name.slice(6)]);
 // Set page flows after all screen identities and links are stable.
 desktopPage.flowStartingPoints=[{nodeId:registry.desktop.Disconnected.id,name:'Desktop / Connect & switch'},{nodeId:registry.desktop.Profiles.id,name:'Desktop / Import & configure'}];
 mobilePage.flowStartingPoints=[{nodeId:registry.mobile.Disconnected.id,name:'Mobile / Connect & switch'},{nodeId:registry.mobile.Profiles.id,name:'Mobile / Import a profile'},{nodeId:registry.mobile['Connection error'].id,name:'Mobile / Recover a connection'}];
 const buttonLabel=dsPage.findOne(n=>n.type==='TEXT'&&n.name==='Component 1');if(buttonLabel)buttonLabel.characters='Buttons / style and size variants';
 const badgeLabel=dsPage.findOne(n=>n.type==='TEXT'&&n.name==='Component 2');if(badgeLabel)badgeLabel.characters='Status badges / semantic tones';
 for(const label of dsPage.children.filter(n=>n.type==='TEXT'&&n.name.startsWith('Icon / '))){label.characters=label.name.slice(7);label.fontSize=10;label.textAutoResize='WIDTH_AND_HEIGHT';}
 const oldAudit=dsPage.findOne(n=>n.name==='Delivery / Native audit');if(oldAudit)oldAudit.visible=false;
 // A composed usage gallery complements the editable masters on the canvas.
 let gallery=dsPage.findOne(n=>n.name==='Components / Usage examples');
 if(!gallery){
  gallery=borderCard('Components / Usage examples',1500,null,48,28,'Background');dsPage.appendChild(gallery);gallery.x=1650;gallery.y=820;
  add(gallery,heading('Components'),tx('One language. Every interaction.',20,'Secondary','Medium'),small('Native instances below share the masters on this page. Edit a master to update every screen.','Muted',1404));
  const group=(label,...items)=>add(borderCard(label,1404,null,24,18),tx(label,16,'Text','Medium'),add(row('Examples',1356,null,16),...items));
  add(gallery,group('Buttons / primary, secondary, ghost, danger and disabled',btn('Connect','Primary','M','power'),btn('Test latency','Secondary','M','speed'),btn('Cancel','Ghost'),btn('Disconnect','Danger'),instance('Button / Disabled')));
  add(gallery,group('Inputs / default, focus and validation',instance('Input / Default'),instance('Input / Focus'),instance('Input / Error')));
  add(gallery,group('Status / text and color together',badge('Connected','Success',true),badge('Testing','Info',true),badge('Slow','Warning',true),badge('Timeout','Error',true),badge('Offline','Neutral',true)));
  add(gallery,group('Navigation / active states and tabs',instance('Navigation / Active'),instance('Navigation / Default'),tabs(['Today','This month'],0,320),instance('Mobile / Bottom navigation')));
  add(gallery,group('Nodes / selected state and quick switching',instance('Node Card / Selected'),instance('Node Card / Default'),instance('Dropdown / Node')));
  add(gallery,group('Charts / editable native vectors',chart(650,140,false),chart(650,140,true)));
  add(gallery,group('Surfaces / cards, modal and switches',instance('Card / Base'),instance('Modal / Import subscription'),add(v('Switch states',220,20),tx('Off / On',14,'Secondary','Medium'),add(row('Switches',220,null,20),sw(false),sw(true)))));
 }
 const overflow=[];
 for(const page of [desktopPage,mobilePage])for(const screen of page.children.filter(n=>n.type==='FRAME'&&n.getPluginData('rainlink'))){for(const n of screen.findAll(n=>n.type==='FRAME'&&n.layoutMode==='VERTICAL'&&n.primaryAxisSizingMode==='FIXED'&&n.name!=='Scrollable content'&&!n.name.startsWith('Icon'))){const cs=n.children.filter(c=>c.visible&&c.layoutPositioning!=='ABSOLUTE');if(cs.length){const bottom=Math.max(...cs.map(c=>c.y+c.height));if(bottom>n.height+2)overflow.push({screen:screen.name,id:n.id,name:n.name,overflow:Math.round(bottom-n.height)});}}}
 const interactions={desktop:0,mobile:0};for(const [key,page]of [['desktop',desktopPage],['mobile',mobilePage]])for(const n of page.findAll(n=>'reactions'in n))interactions[key]+=n.reactions.length;
 const report={file:'RainLink',version:'1.1',desktop:Object.fromEntries(Object.entries(registry.desktop).map(([k,n])=>[k,n.id])),mobile:Object.fromEntries(Object.entries(registry.mobile).map(([k,n])=>[k,n.id])),counts:{desktop:Object.keys(registry.desktop).length,mobile:Object.keys(registry.mobile).length,components:dsPage.findAll(n=>n.type==='COMPONENT').length,instances:desktopPage.findAll(n=>n.type==='INSTANCE').length+mobilePage.findAll(n=>n.type==='INSTANCE').length,prototypeInteractions:interactions},flows:{desktop:desktopPage.flowStartingPoints,mobile:mobilePage.flowStartingPoints},overflow,galleryId:gallery.id};
 figma.root.setPluginData('rainlink-report',JSON.stringify(report));
 if(oldAudit){oldAudit.characters='RainLink design audit\n'+JSON.stringify(report,null,2);oldAudit.textAutoResize='HEIGHT';}
 let overview=dsPage.findOne(n=>n.name==='Delivery / Overview');
 if(!overview){overview=borderCard('Delivery / Overview',1000,null,40,24,'Background');dsPage.appendChild(overview);overview.x=1650;overview.y=0;add(overview,add(row('Identity',920,null,16),instance('Brand / Mark'),heading('RainLink / Delivery')),tx('A complete workspace, from desktop to pocket.',20,'Secondary','Medium'),divider(920),tx('16 Desktop screens  /  15 Mobile screens',24,'Text','Semi Bold'),small('1440 × 900 desktop · 393 × 852 mobile · Shared native components and Auto Layout.','Secondary',920),small('Dark foundation and Light extension use independent semantic color collections, compatible with this Starter file.','Muted',920),divider(920),tx('Present the five named prototype flows',18,'Text','Medium'),small('Connect and switch nodes. Import a profile and refine routing. Recover gracefully from a connection error.','Secondary',920),small('Node, latency, traffic and camera states are illustrative prototype data.','Muted',920),divider(920),tx('File contents',18,'Text','Medium'),small('01 / Desktop\n02 / Mobile\n03 / Foundations, components and interaction map','Secondary',920));}
 console.log('RAINLINK_FINAL_AUDIT',JSON.stringify(report));return report;
}

async function finalizeMain(){
 figma.showUI('<body style="padding:24px;background:#10181e;color:#a8bac5;font:13px Arial"><h2 style="color:#86e5c3">RainLink / Final review</h2><p id="s">Finishing native layouts and prototype entries…</p></body>',{width:440,height:150});
 await figma.loadAllPagesAsync();await restoreLocaleBaseline();desktopPage=figma.root.children.find(p=>p.name==='01 · Desktop');mobilePage=figma.root.children.find(p=>p.name==='02 · Mobile');dsPage=figma.root.children.find(p=>p.name.startsWith('03 ·'));
 for(const style of ['Regular','Medium','Semi Bold','Bold'])await figma.loadFontAsync({family:'Inter',style});await figma.loadFontAsync({family:monoFamily,style:'Regular'});
 const collections=await figma.variables.getLocalVariableCollectionsAsync();collection=collections.find(c=>c.name==='RainLink / Colors / Dark');lightCollection=collections.find(c=>c.name==='RainLink / Colors / Light');darkMode=collection.defaultModeId;lightMode=darkMode;
 for(const variable of await figma.variables.getLocalVariablesAsync('COLOR')){if(variable.variableCollectionId===collection.id)vars[variable.name]=variable;if(variable.variableCollectionId===lightCollection.id)lightVars[variable.name]=variable;}
 for(const c of dsPage.findAll(n=>n.type==='COMPONENT')){if(c.name.startsWith('Icon / '))icons[c.name.slice(7)]=c;else if(c.name.startsWith('Style=')){const parts=c.name.split(', ');masters['Button / '+parts[0].slice(6)+' / '+parts[1].slice(5)]=c;}else if(c.name.startsWith('Tone='))masters['Badge / '+c.name.slice(5)]=c;else masters[c.name]=c;}
 for(const n of desktopPage.children.filter(n=>n.type==='FRAME'&&n.name.startsWith('Desktop / ')))registry.desktop[n.name.slice(10)]=n;
 for(const n of mobilePage.children.filter(n=>n.type==='FRAME'&&n.name.startsWith('Mobile / ')))registry.mobile[n.name.slice(9)]=n;
 await figma.setCurrentPageAsync(dsPage);const report=await finalizeDocument();await localizeDocument();
 await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Dashboard];figma.viewport.scrollAndZoomIntoView([registry.desktop.Dashboard]);
 figma.notify('RainLink complete · '+report.counts.desktop+' Desktop · '+report.counts.mobile+' Mobile · '+report.counts.components+' components · '+report.overflow.length+' layout issues');figma.closePlugin();
}
