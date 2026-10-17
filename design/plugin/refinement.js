// This source is incorporated into code.js by the update script before deployment.
async function refineMain(){
 figma.showUI('<body style="padding:24px;background:#10181e;color:#a8bac5;font:13px Arial"><h2 style="color:#86e5c3">RainLink / Quality pass</h2><p id="s">Inspecting the document…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script>',{width:420,height:160});
 await figma.loadAllPagesAsync();await restoreLocaleBaseline();
 desktopPage=figma.root.children.find(p=>p.name==='01 · Desktop');mobilePage=figma.root.children.find(p=>p.name==='02 · Mobile');dsPage=figma.root.children.find(p=>p.name.startsWith('03 ·'));
 for(const style of ['Regular','Medium','Semi Bold','Bold'])await figma.loadFontAsync({family:'Inter',style});try{await figma.loadFontAsync({family:monoFamily,style:'Regular'});}catch(e){monoFamily='Inter';}
 const collections=await figma.variables.getLocalVariableCollectionsAsync();collection=collections.find(c=>c.name==='RainLink / Colors / Dark');lightCollection=collections.find(c=>c.name==='RainLink / Colors / Light');darkMode=collection.defaultModeId;lightMode=darkMode;
 for(const variable of await figma.variables.getLocalVariablesAsync('COLOR')){if(variable.variableCollectionId===collection.id)vars[variable.name]=variable;if(variable.variableCollectionId===lightCollection.id)lightVars[variable.name]=variable;}
 for(const c of dsPage.findAll(n=>n.type==='COMPONENT')){if(c.name.startsWith('Icon / '))icons[c.name.slice(7)]=c;else if(c.name.startsWith('Style=')){const parts=c.name.split(', ');masters['Button / '+parts[0].slice(6)+' / '+parts[1].slice(5)]=c;}else if(c.name.startsWith('Tone='))masters['Badge / '+c.name.slice(5)]=c;else masters[c.name]=c;}
 for(const n of desktopPage.children.filter(n=>n.type==='FRAME'&&n.name.startsWith('Desktop / ')))registry.desktop[n.name.slice(10)]=n;
 for(const n of mobilePage.children.filter(n=>n.type==='FRAME'&&n.name.startsWith('Mobile / ')))registry.mobile[n.name.slice(9)]=n;
 // Figma imports an SVG wrapper with a default fill. Clear it while preserving vector strokes.
 await progress('Repairing SVG icon wrappers and responsive constraints…');
 for(const name of Object.keys(icons)){const c=icons[name];c.layoutMode='HORIZONTAL';c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';fill(c,null);for(const g of c.children){if(g.type==='FRAME'){g.fills=[];g.clipsContent=false;g.layoutPositioning='ABSOLUTE';g.x=0;g.y=0;g.constraints={horizontal:'SCALE',vertical:'SCALE'};}}}
 const allPages=[dsPage,desktopPage,mobilePage];const iconIds=new Set(Object.values(icons).map(c=>c.id));
 for(const p of allPages){for(const inst of p.findAll(n=>n.type==='INSTANCE')){const master=await inst.getMainComponentAsync();if(!master||!iconIds.has(master.id))continue;for(const g of inst.children){if(g.type==='FRAME'){g.fills=[];g.clipsContent=false;}}}}
 const find=(n,s)=>n.findOne(x=>x.name===s);const resize=(n,w,h)=>{if(n){n.resize(w,h);if(n.layoutMode==='VERTICAL')n.primaryAxisSizingMode='FIXED';}};const inset=(n,p,g)=>{if(n){n.paddingTop=n.paddingBottom=p;n.itemSpacing=g;}};
 await progress('Balancing card density, text and mobile first-screen content…');
 for(const screen of Object.values(registry.desktop)){
  for(const metric of screen.findAll(n=>n.name.startsWith('Metric · '))){inset(metric,16,6);const val=find(metric,'Value');if(val){const t=val.children.find(n=>n.type==='TEXT');if(t)t.lineHeight={unit:'PIXELS',value:34};}}
  for(const tile of screen.findAll(n=>n.name.startsWith('Profile · ')))inset(tile,18,8);
  const sub=find(screen,'Subscriptions');if(sub)sub.itemSpacing=0;
  const palette=find(screen,'Command palette');inset(palette,24,8);
  const imp=find(screen,'Import subscription form');inset(imp,24,8);
  const rule=find(screen,'Domain rule form');inset(rule,24,12);
  const network=screen.findOne(n=>n.type==='FRAME'&&n.name==='Network'&&n.parent.name==='General settings');if(network&&screen.name==='Desktop / Settings'){resize(network,876,224);resize(find(screen,'Settings layout'),1120,694);resize(find(screen,'Settings navigation').children.find(n=>n.name==='Network'),196,40);}
  const live=find(screen,'Live connections');if(live){for(const r of live.children.filter(n=>n.name==='Table row'))resize(r,1120,59);}
 }
 for(const key of ['Dashboard','Disconnected','Dashboard light']){
  const s=registry.desktop[key];for(const met of s.findAll(n=>n.name.startsWith('Metric · ')))inset(met,12,4);
  const q=find(s,'Network quality');if(q){const score=q.findOne(n=>n.type==='TEXT'&&n.characters==='98');if(score)score.lineHeight={unit:'PIXELS',value:60};}
  const trend=find(s,'Latency trend');inset(trend,16,8);
  const health=find(s,'Node health');inset(health,16,8);if(health)health.children.filter(n=>n.name.startsWith('Health · ')).forEach(n=>resize(n,348,26));
  const recent=find(s,'Recent activity');inset(recent,10,6);
 }
 for(const screen of Object.values(registry.mobile)){
  const hero=find(screen,'Connection control');if(hero){resize(hero,353,238);inset(hero,16,8);const ring=find(hero,'Connection ring');resize(ring,112,112);ring.children.filter(n=>n.type==='ELLIPSE').forEach(e=>e.resize(108,108));const power=find(ring,'Connect / power');resize(power,80,80);power.x=16;power.y=16;const ic=power.findOne(n=>n.type==='INSTANCE');if(ic)ic.resize(32,32);}
  const daily=find(screen,'Today’s traffic');if(daily){resize(daily,353,100);inset(daily,14,8);}
  const curve=find(screen,'Traffic chart');inset(curve,16,10);
  const total=find(screen,'Traffic total');if(total){const display=total.findOne(n=>n.type==='TEXT'&&n.characters==='8.42 GB');if(display)display.lineHeight={unit:'PIXELS',value:44};}
  const success=find(screen,'Success');inset(success,22,14);
  for(const tile of screen.findAll(n=>n.name.startsWith('Profile · ')))if(tile.height===200)inset(tile,18,8);
 }
 // Keep the power control centered after instance constraints propagate.
 for(const screen of Object.values(registry.mobile)){const hero=find(screen,'Connection control');if(hero){const ring=find(hero,'Connection ring');const power=find(ring,'Connect / power');power.x=16;power.y=16;}}
 // The sidebar is a shared native component, with each screen overriding its active item.
 await progress('Creating the shared Sidebar component and checking prototype destinations…');
 await figma.setCurrentPageAsync(dsPage);
 let sideMaster=dsPage.findOne(n=>n.type==='COMPONENT'&&n.name==='Sidebar / Desktop');
 if(!sideMaster){const source=find(registry.desktop.Dashboard,'Sidebar');sideMaster=figma.createComponent();sideMaster.name='Sidebar / Desktop';sideMaster.resize(248,900);sideMaster.layoutMode='VERTICAL';sideMaster.primaryAxisSizingMode='FIXED';sideMaster.counterAxisSizingMode='FIXED';sideMaster.paddingLeft=sideMaster.paddingRight=20;sideMaster.paddingTop=26;sideMaster.paddingBottom=24;sideMaster.itemSpacing=0;fill(sideMaster,'Surface');stroke(sideMaster);for(const child of source.children){const c=child.clone();add(sideMaster,c);for(const x of [c,...('findAll'in c?c.findAll(n=>'setReactionsAsync'in n):[])])if('setReactionsAsync'in x)await x.setReactionsAsync([]);}dsPage.appendChild(sideMaster);sideMaster.description='Shared desktop navigation. Override the active Navigation instance per screen.';sideMaster.x=1180;sideMaster.y=2820;}
 for(const [key,screen] of Object.entries(registry.desktop)){
  const old=screen.children.find(n=>n.name==='Sidebar'||n.name==='Sidebar / Desktop');if(!old)continue;
  const side=sideMaster.createInstance();side.name='Sidebar / Desktop';screen.insertChild(0,side);old.remove();
  const active=['Disconnected','Dashboard light','Quick switch'].includes(key)?'Dashboard':['Profile editor','Import profile'].includes(key)?'Profiles':key==='Appearance'?'Settings':key==='Rule editor'?'Rules':key==='Nodes tested'?'Nodes':key;
  for(const item of side.findAll(n=>n.type==='INSTANCE'&&n.name.startsWith('Navigate · '))){const name=item.name.slice(11);const idx=navNames.indexOf(name);if(idx<0)continue;item.swapComponent(masters['Navigation / '+(name===active?'Active':'Default')]);textOverride(item,'Nav label',name);textOverride(item,'Shortcut',String(idx+1));const ic=find(item,'Nav icon');if(ic){ic.swapComponent(icons[navIcons[idx]]);tint(ic,name===active?'Primary':'Secondary');ic.children.filter(n=>n.type==='FRAME').forEach(n=>n.fills=[]);}const destination=registry.desktop[name];if(destination&&destination.id!==screen.id)await item.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:destination.id,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false}]}]);}
  const mode=find(side,'Routing mode');if(mode&&key!=='Rules')await mode.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:registry.desktop.Rules.id,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false}]}]);
  if(key==='Dashboard light')applyLight(side);
 }
 const sets=dsPage.children.filter(n=>n.type==='COMPONENT_SET');if(sets[0])sets[0].name='Button / Variants';if(sets[1])sets[1].name='Status Badge / Variants';
 const foundation=dsPage.findOne(n=>n.name==='Design System / Foundations');foundation.itemSpacing=24;foundation.primaryAxisSizingMode='AUTO';const bars=find(foundation,'Spacing samples');if(bars)bars.resize(642,94);
 const oldFlow=dsPage.findOne(n=>n.name==='Prototype Flow / Interaction map');if(oldFlow)oldFlow.remove();libraryY=Math.max(...dsPage.children.filter(n=>n.type!=='TEXT').map(n=>n.y+n.height))+180;flowMap();
 const aliases={Button:'Button / Variants',Card:'Card / Base',Navigation:'Navigation / Active',Sidebar:'Sidebar / Desktop',Tabs:'Tab / Active',Input:'Input / Focus',Dropdown:'Dropdown / Node',NodeCard:'Node Card / Selected',StatusBadge:'Status Badge / Variants',Chart:'Chart / Traffic',Modal:'Modal / Import subscription',Switch:'Switch / On'};
 // Enrich component examples with disabled and error states.
 if(!dsPage.findOne(n=>n.type==='COMPONENT'&&n.name==='Button / Disabled')){const disabled=masters['Button / Secondary / M'].clone();disabled.name='Button / Disabled';disabled.opacity=.4;dsPage.appendChild(disabled);disabled.x=0;disabled.y=libraryY-100;const label=small('Disabled button','Muted');dsPage.appendChild(label);label.x=0;label.y=libraryY-126;}
 if(!dsPage.findOne(n=>n.type==='COMPONENT'&&n.name==='Input / Error')){const er=masters['Input / Default'].clone();er.name='Input / Error';stroke(er,'Error');textOverride(er,'Value','Enter a valid subscription URL','Error');dsPage.appendChild(er);er.x=220;er.y=libraryY-100;const label=small('Input validation error','Muted');dsPage.appendChild(label);label.x=220;label.y=libraryY-126;}
 // Delete orphan spacers created before their containing sidebar was assembled.
 for(const p of [desktopPage,mobilePage])for(const n of p.children.filter(n=>n.name==='Flexible space'))n.remove();
 await finalizeDocument();
 const overflow=[];for(const p of [desktopPage,mobilePage])for(const screen of p.children.filter(n=>n.type==='FRAME'&&n.getPluginData('rainlink'))){for(const n of screen.findAll(n=>n.type==='FRAME'&&n.layoutMode!=='NONE'&&!n.name.startsWith('Icon')&&n.name!=='Scrollable content')){if(n.primaryAxisSizingMode==='AUTO')continue;const children=n.children.filter(c=>c.visible&&c.layoutPositioning!=='ABSOLUTE');if(!children.length)continue;const bottom=Math.max(...children.map(c=>c.y+c.height));if(n.layoutMode==='VERTICAL'&&bottom>n.height+2)overflow.push({screen:screen.name,node:n.name,id:n.id,overflow:Math.round(bottom-n.height)});}}
 const protoCounts={desktop:0,mobile:0};for(const [key,p] of [['desktop',desktopPage],['mobile',mobilePage]])for(const n of p.findAll(n=>'reactions'in n)){protoCounts[key]+=n.reactions.length;}
 const report={file:'RainLink',desktop:Object.fromEntries(Object.entries(registry.desktop).map(([k,n])=>[k,n.id])),mobile:Object.fromEntries(Object.entries(registry.mobile).map(([k,n])=>[k,n.id])),counts:{desktop:Object.keys(registry.desktop).length,mobile:Object.keys(registry.mobile).length,components:dsPage.findAll(n=>n.type==='COMPONENT').length,instances:desktopPage.findAll(n=>n.type==='INSTANCE').length+mobilePage.findAll(n=>n.type==='INSTANCE').length,prototypeInteractions:protoCounts},componentCoverage:aliases,overflow};
 figma.root.setPluginData('rainlink-report',JSON.stringify(report));
 const audit=tx('RainLink design audit\n'+JSON.stringify(report,null,2),11,'Muted','Regular',1400,true);audit.name='Delivery / Native audit';dsPage.appendChild(audit);audit.x=1650;audit.y=0;
 await localizeDocument();
 await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Dashboard];figma.viewport.scrollAndZoomIntoView([registry.desktop.Dashboard]);
 figma.ui.postMessage({status:report.counts.desktop+' Desktop · '+report.counts.mobile+' Mobile · '+report.counts.components+' components. Overflow checks: '+overflow.length});console.log('RAINLINK_AUDIT',JSON.stringify(report));figma.notify('RainLink quality pass complete');figma.closePlugin();
}
