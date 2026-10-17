// RainLink 7.1: move network capture controls to the existing overview.
// Four local variants model two independent switches; no application screens are added.
const R71_CONTROLS = '首页网络接管';

async function r71ProbeMain() {
  figma.showUI('<body style="background:#151617;color:#c0c2c8;font:13px monospace;padding:16px"><pre id="s">检查本地缓存…</pre><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>', {width:700,height:400});
  const result = {currentPage:figma.currentPage.id, pages:figma.root.children.map(p=>({id:p.id,name:p.name})), storedReport:!!figma.root.getPluginData('rainlink-report')};
  const instance=figma.currentPage.findOne(n=>n.id==='31:181510');
  if(instance) {
    try {const c=await Promise.race([instance.getMainComponentAsync(),new Promise((_,reject)=>setTimeout(()=>reject(new Error('main component timeout')),5000))]);result.mainComponent=c&&{id:c.id,name:c.name,parent:c.parent.id,children:c.children.map(n=>({id:n.id,name:n.name}))};}catch(e){result.mainError=String(e);}
  }
  figma.ui.postMessage({status:JSON.stringify(result,null,2)});
}

async function r71DesktopOfflineMain() {
  figma.showUI('<body style="background:#151617;color:#c0c2c8;font:13px Microsoft YaHei,sans-serif;padding:24px"><h2>更新桌面概览</h2><p id="s">使用当前页缓存应用控件…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:480,height:180});
  const page=figma.currentPage,report=JSON.parse(figma.root.getPluginData('rainlink-report'));
  const dashboard=page.findOne(n=>n.id===report.desktop.Dashboard),settings=page.findOne(n=>n.id===report.desktop.Settings);
  if(!dashboard||!settings)throw new Error('请在现有桌面端页签运行');
  figma.skipInvisibleInstanceChildren=false;dsPage=page;Object.assign(C,R5_COLORS);
  zhFamily=report.chineseFont.family;zhStyles=report.chineseFont.styles;
  for(const style of new Set(Object.values(zhStyles)))await figma.loadFontAsync({family:zhFamily,style});
  for(const style of ['Regular','Medium','Semi Bold','Bold'])await figma.loadFontAsync({family:'Inter',style});
  const switches=page.findAll(n=>n.type==='INSTANCE'&&/^Switch \/ (On|Off)$/.test(r5Name(n)));
  for(const state of ['On','Off']){const original=switches.find(n=>r5Name(n)==='Switch / '+state);if(original)masters['Switch / '+state]={createInstance:()=>original.clone()};}
  const library=await r71ControlLibrary(false,false),content=uFind(dashboard,'Content'),body=uFind(dashboard,'连接开关与出口');
  let row=content.children.find(n=>r5Name(n)===R71_CONTROLS);
  if(!row){row=r7Instance(library.initial,R71_CONTROLS);content.insertChild(1,row);}
  r71CompactHome(body,false);
  content.itemSpacing=8;body.itemSpacing=8;
  const removed=r71RemoveSettingsControls(settings,false);
  let section=page.children.find(n=>n.type==='SECTION'&&n.getPluginData('rainlink-home-controls-cache')==='7.1');
  if(!section){section=figma.createSection();section.name='首页网络接管组件 / 离线缓存';section.setPluginData('rainlink-home-controls-cache','7.1');page.appendChild(section);}
  section.appendChild(library.set);library.set.x=24;library.set.y=24;section.resizeWithoutConstraints(library.set.width+48,library.set.height+48);section.visible=false;
  await r5Yield();
  const edge=Math.max(...content.children.filter(n=>n.visible).map(n=>n.y+n.height));
  if(edge>content.height-content.paddingBottom+1)throw new Error('概览需要进一步压缩：'+edge+' / '+content.height);
  report.pendingHomeControls={desktopApplied:true,mobileApplied:false,prototypePending:true,libraryId:library.set.id,sectionId:section.id,settingsRowsRemoved:removed,contentBottom:edge,contentHeight:content.height};
  delete report.nativeBackup;delete report.screenshotVerification;
  figma.root.setPluginData('rainlink-report',JSON.stringify(report));
  figma.currentPage.selection=[dashboard];figma.viewport.scrollAndZoomIntoView([dashboard]);
  figma.notify('桌面概览已更新；移动端等待页签恢复加载');figma.closePlugin();
}

async function r71Palette() {
  Object.assign(C, R5_COLORS);
  const collections = await figma.variables.getLocalVariableCollectionsAsync();
  collection = collections.find(c => /Colors \/ Dark|颜色 \/ 深色/.test(c.name));
  lightCollection = collections.find(c => /Colors \/ Light|颜色 \/ 浅色/.test(c.name));
  if (collection) darkMode = collection.defaultModeId;
  for (const variable of await figma.variables.getLocalVariablesAsync('COLOR')) {
    const key = Object.keys(R5_TOKEN_NAMES).find(k => variable.name === k || variable.name === R5_TOKEN_NAMES[k]);
    if (key && variable.variableCollectionId === collection?.id) vars[key] = variable;
    if (key && variable.variableCollectionId === lightCollection?.id) lightVars[key] = variable;
  }
}

async function r71ControlLibrary(mobile,wire=true) {
  const platform = mobile ? '移动端' : '桌面端';
  const name = '交互 / ' + platform + ' / 首页网络接管';
  let set = dsPage.findOne(n => n.type === 'COMPONENT_SET' && r5Name(n) === name);
  const variants = {};
  for (const proxy of [true, false]) for (const tun of [false, true]) {
    const key = (proxy ? '开启' : '关闭') + '/' + (tun ? '开启' : '关闭');
    const variantName = '系统代理=' + key.split('/')[0] + ', TUN模式=' + key.split('/')[1];
    let c = set?.children.find(n => n.name === variantName);
    if (!c) {
      c = component(variantName, n => {
        const w = mobile ? 353 : 1120, gap = mobile ? 8 : 16, pad = mobile ? 12 : 16;
        const cellWidth = (w - pad * 2 - 2 - gap * 2 - 1) / 2;
        n.layoutMode = 'HORIZONTAL';
        n.primaryAxisSizingMode = n.counterAxisSizingMode = 'FIXED';
        n.resize(w, mobile ? 52 : 56);
        n.paddingLeft = n.paddingRight = pad;
        n.paddingTop = n.paddingBottom = mobile ? 3 : 5;
        n.counterAxisAlignItems = 'CENTER'; n.itemSpacing = gap;
        fill(n, 'Surface'); stroke(n); rad(n, 12); n.strokesIncludedInLayout = true;
        const proxyCell = between(row('系统代理开关', cellWidth, 44));
        const tunCell = between(row('TUN 模式开关', cellWidth, 44));
        add(proxyCell, r6Text('系统代理', mobile ? 13 : 14, 'Text', 'Medium'), sw(proxy));
        add(tunCell, r6Text('TUN 模式', mobile ? 13 : 14, 'Text', 'Medium'), sw(tun));
        const separator = frame('开关分隔线', 1, 24, 'VERTICAL', 'Stroke');
        add(n, r6Name(proxyCell, '系统代理开关'), separator, r6Name(tunCell, 'TUN 模式开关'));
        n.setPluginData('rainlink-home-controls', '7.1');
        n.description = '概览中的两个独立开关。整行控件命中高度 44 px。系统代理与 TUN 可分别开启或关闭；VPN 总开关与代理模式保留在概览。';
      });
      if (set) set.appendChild(c);
    }
    variants[key] = c;
  }
  if (!set) {
    const bottom = Math.max(0, ...dsPage.children.filter(n => n.visible && !Object.values(variants).includes(n)).map(n => n.y + n.height));
    set = r7VariantSet(name, Object.values(variants), 2);
    set.x = mobile ? 4400 : 0;
    set.y = bottom + 80;
  }
  if(wire) for (const [key, c] of Object.entries(variants)) {
    const [proxy, tun] = key.split('/');
    await uFind(c, '系统代理开关').setReactionsAsync(r7Click(variants[(proxy === '开启' ? '关闭' : '开启') + '/' + tun].id));
    await uFind(c, 'TUN 模式开关').setReactionsAsync(r7Click(variants[proxy + '/' + (tun === '开启' ? '关闭' : '开启')].id));
  }
  return { set, initial: variants['开启/关闭'], variants };
}

function r71CompactHome(c, mobile) {
  c.itemSpacing = mobile ? 10 : 12;
  if (mobile) {
    const hero = uFind(c, 'VPN control'), ring = uFind(c, 'VPN power button');
    if (hero) { hero.resize(353, 106); hero.primaryAxisSizingMode = 'FIXED'; }
    if (ring) { ring.resize(72, 72); rad(ring, 36); }
    return;
  }
  const hero = uFind(c, 'Connection group hero');
  if (hero) { hero.paddingTop = hero.paddingBottom = 12; hero.itemSpacing = 8; hero.primaryAxisSizingMode = 'AUTO'; }
  const trends = uFind(c, 'Connection trends');
  if (!trends) return;
  trends.resize(1120, 196);
  for (const card of trends.children.filter(n => n.type === 'FRAME')) {
    card.resize(card.width, 196); card.paddingTop = card.paddingBottom = 14; card.itemSpacing = 8;
    for (const child of card.children) {
      if (r5Name(child).startsWith('Health ')) child.resize(child.width, 24);
      if (child.type === 'INSTANCE' && r5Name(child).startsWith('Button · ')) child.resize(child.width, 32);
    }
  }
}

function r71RemoveSettingsControls(screen, mobile) {
  const removed = [];
  const rows = screen.findAll(n => n.type === 'FRAME' && n.children.some(c => c.type === 'FRAME' && c.findOne(t => t.type === 'TEXT' && ['系统代理', 'System proxy', 'TUN 模式', 'TUN mode'].includes(t.characters))) && /^(Setting · |设置项 · )/.test(r5Name(n)));
  for (const row of rows) {
    const card = row.parent, id = row.id;
    row.remove(); removed.push(id);
    const entries = card.children.filter(n => n.type === 'FRAME' || n.type === 'INSTANCE');
    if (!entries.length) card.remove();
  }
  if (!mobile) {
    const col = uFind(screen, 'General settings'), layout = uFind(screen, 'Settings layout');
    if (col) col.primaryAxisSizingMode = 'AUTO';
    if (layout) { layout.counterAxisAlignItems = 'MIN'; layout.resize(1120, 652); }
  }
  return removed;
}

async function r71ApplyHomeControls(report) {
  await r71Palette();
  const countBefore = { desktop: Object.keys(registry.desktop).length, mobile: Object.keys(registry.mobile).length };
  const result = { version: '7.1', screensAdded: 0, libraries: {}, homes: {}, removedSettingsRows: [], switchesAreIndependent: true, mobileHitHeight: 44 };
  for (const mobile of [false, true]) {
    const platform = mobile ? 'mobile' : 'desktop', reg = mobile ? registry.mobile : registry.desktop;
    if(!mobile&&report.pendingHomeControls){const set=await figma.getNodeByIdAsync(report.pendingHomeControls.libraryId);if(set)dsPage.appendChild(set);const stray=uFind(reg.Dashboard,'Content')?.children.find(n=>r5Name(n)===R71_CONTROLS);if(stray)stray.remove();}
    const library = await r71ControlLibrary(mobile);
    result.libraries[platform] = library.set.id;
    result.homes[platform] = [];
    for (const [state, id] of Object.entries(report.compactCanvas.homeStates[platform].states)) {
      const c = await figma.getNodeByIdAsync(id);
      if (!c || c.type !== 'COMPONENT') throw new Error('缺少连接状态组件：' + platform + '/' + state);
      let controls = c.children.find(n => r5Name(n) === R71_CONTROLS);
      if (!controls) {
        controls = r7Instance(library.initial, R71_CONTROLS);
        const network = uFind(c, '概览出口与模式');
        c.insertChild(network ? c.children.indexOf(network) : 1, controls);
      }
      r71CompactHome(c, mobile);
      result.homes[platform].push({ state, id: c.id, controlsId: controls.id });
    }
    const screen = reg[mobile ? 'Home' : 'Dashboard'], content = uFind(screen, 'Content');
    if (mobile && content) { content.paddingTop = 12; content.paddingBottom = 16; }
    result.removedSettingsRows.push(...r71RemoveSettingsControls(reg.Settings, mobile));
  }
  await r5Yield();
  // Keep the two small control libraries together below the existing system.
  // A desktop library recovered from the temporary cache keeps its old x/y.
  const libraries = await Promise.all(Object.values(result.libraries).map(id => figma.getNodeByIdAsync(id)));
  const libraryTop = Math.max(0, ...dsPage.children.filter(n => n.visible && !libraries.includes(n)).map(n => n.y + n.height)) + 80;
  libraries.forEach((set, i) => { set.x = i ? 4400 : 0; set.y = libraryTop; });
  const fit = [];
  for (const [platform, homes] of Object.entries(result.homes)) for (const home of homes) {
    const c = await figma.getNodeByIdAsync(home.id), maxHeight = platform === 'mobile' ? 638 : 708;
    fit.push({ platform, state: home.state, height: c.height, maxHeight, fits: c.height <= maxHeight + 1 });
  }
  if (fit.some(x => !x.fits)) throw new Error('首页内容超出首屏：' + JSON.stringify(fit.filter(x => !x.fits)));
  if (countBefore.desktop !== Object.keys(registry.desktop).length || countBefore.mobile !== Object.keys(registry.mobile).length) throw new Error('此次更新不应增加页面');
  result.fit = fit;
  if(report.pendingHomeControls){const section=await figma.getNodeByIdAsync(report.pendingHomeControls.sectionId);if(section)section.remove();delete report.pendingHomeControls;}
  report.homeNetworkControls = result;
  report.version = '7.1';
  report.counts.components = dsPage.findAll(n => n.type === 'COMPONENT').length;
  figma.root.setPluginData('rainlink-home-controls-version', '7.1');
  return result;
}

async function r71VerifyControls(report) {
  const controls = { version: '7.1', variantsPerPlatform: 4, edgesPerPlatform: 8, independent: true, errors: [] };
  for (const [platform, id] of Object.entries(report.homeNetworkControls.libraries)) {
    const set = await figma.getNodeByIdAsync(id);
    if (!set || set.children.length !== 4) throw new Error('首页开关组件数量不正确：' + platform);
    for (const c of set.children) {
      const match = c.name.match(/^系统代理=(开启|关闭), TUN模式=(开启|关闭)$/);
      if (!match) throw new Error('首页开关变体命名不正确：' + c.name);
      for (const [name, index] of [['系统代理开关', 1], ['TUN 模式开关', 2]]) {
        const target = match.slice(1); target[index - 1] = target[index - 1] === '开启' ? '关闭' : '开启';
        const expected = set.children.find(n => n.name === '系统代理=' + target[0] + ', TUN模式=' + target[1]);
        const node = uFind(c, name), actions = node?.reactions?.[0]?.actions;
        if (!node || node.height < 44 || node.reactions.length !== 1 || node.reactions[0].trigger?.type !== 'ON_CLICK' || actions?.length !== 1 || actions[0].navigation !== 'CHANGE_TO' || actions[0].destinationId !== expected?.id) {
          controls.errors.push({ platform, variant: c.name, control: name });
        }
      }
    }
  }
  if (controls.errors.length) throw new Error('开关独立切换核验失败：' + JSON.stringify(controls.errors));
  const scan = { status: 'verified', kind: 'native interaction graph', version: report.version, verifiedAt: new Date().toISOString() };
  for (const [platform, page] of [['desktop', desktopPage], ['mobile', mobilePage], ['system', dsPage]]) {
    const nodes = [page, ...page.findAll(() => true)], destinations = new Set();
    let connectedNodes = 0, reactions = 0;
    function collect(value) {
      if (!value || typeof value !== 'object') return;
      if (typeof value.destinationId === 'string') destinations.add(value.destinationId);
      for (const child of Object.values(value)) {
        if (Array.isArray(child)) child.forEach(collect);
        else if (child && typeof child === 'object') collect(child);
      }
    }
    for (const node of nodes) {
      if (!('reactions' in node) || !node.reactions.length) continue;
      connectedNodes++; reactions += node.reactions.length; collect(node.reactions);
    }
    const unresolved = [];
    for (const id of destinations) if (!(await figma.getNodeByIdAsync(id))) unresolved.push(id);
    scan[platform] = { nodesScanned: nodes.length, connectedNodes, reactions, unresolved, unscannedScreens: [] };
    if (unresolved.length) throw new Error('原型存在失效目标：' + platform + '/' + unresolved.join(','));
  }
  report.homeNetworkControlsVerification = controls;
  report.livePrototypeVerification = scan;
  report.counts.prototypeInteractions = Object.fromEntries(['desktop', 'mobile', 'system'].map(platform => [platform, scan[platform].connectedNodes]));
}

async function r71HomeControlsMain() {
  figma.showUI('<body style="padding:24px;background:#151617;color:#c0c2c8;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#8adcbf">RainLink / 首页连接控制</h2><p id="s">将系统代理和 TUN 模式移到概览…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>', { width: 480, height: 170 });
  await r5Initialize(); figma.skipInvisibleInstanceChildren = false;
  if (figma.root.getPluginData('rainlink-compact-version') !== '7.0') throw new Error('请在现有精简版 RainLink 文件中运行此次更新');
  const report = JSON.parse(figma.root.getPluginData('rainlink-report'));
  await r71ApplyHomeControls(report);
  if (['7.2', '7.3'].includes(figma.root.getPluginData('rainlink-density-version'))) await r72ApplyDensity(report);
  const audit = await r5AuditDocument();
  report.overflow = audit.overflow; report.untranslatedDisplayCopy = audit.untranslatedDisplayCopy;
  report.counts.instances = [desktopPage, mobilePage, dsPage].reduce((sum, p) => sum + p.findAll(n => n.type === 'INSTANCE').length, 0);
  delete report.nativeBackup; delete report.screenshotVerification;
  await r71VerifyControls(report);
  const text = uFind(dsPage, 'Delivery / Native audit');
  text.characters = 'RainLink 设计核验\n' + JSON.stringify(report, null, 2); text.visible = false;
  figma.root.setPluginData('rainlink-report', JSON.stringify(report));
  await figma.setCurrentPageAsync(desktopPage); figma.currentPage.selection = [registry.desktop.Dashboard];
  figma.viewport.scrollAndZoomIntoView(figma.currentPage.selection);
  figma.notify('已移到概览：系统代理与 TUN 模式 · 保留原有 23 个画面'); figma.closePlugin();
}
