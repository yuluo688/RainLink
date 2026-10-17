// RainLink 7.3: compact desktop rows share the same group model as mobile.
// Existing component and action IDs are retained so native prototypes keep working.
function r72Fixed(n, w, h) {
  if (!n) return;
  n.resize(w, h === undefined ? n.height : h);
  if (n.layoutMode === 'HORIZONTAL') n.primaryAxisSizingMode = 'FIXED';
  if (n.layoutMode === 'VERTICAL') n.counterAxisSizingMode = 'FIXED';
}
function r72Text(n, width, size, line) {
  if (!n) return;
  n.fontSize = size; n.lineHeight = {unit:'PIXELS', value:line};
  n.resize(width, line); n.textAutoResize = 'HEIGHT';
}
function r72IconButton(n) {
  if (!n) return;
  n.primaryAxisSizingMode = n.counterAxisSizingMode = 'FIXED'; n.resize(44, 44);
  n.paddingLeft = n.paddingRight = n.paddingTop = n.paddingBottom = 0;
  n.primaryAxisAlignItems = n.counterAxisAlignItems = 'CENTER';
  const label = uFind(n, 'Label'), slot = uFind(n, 'Icon slot');
  if (label) label.visible = false;
  if (slot) slot.visible = true;
}
function r73UsageRatio(n, progress) {
  const saved = n.getPluginData('rainlink-subscription-metadata');
  const data = saved ? JSON.parse(saved) : R6_INFO[uFind(n, '组名称')?.characters];
  return data && typeof data.ratio === 'number' ? data.ratio : Math.min(1, (progress.children[0]?.width || 0) / progress.width);
}
function r72GroupStructure(c, mobile) {
  const facts = uFind(c, 'Group current identity');
  if (facts) facts.visible = false;
  if (!mobile) {
    const top = uFind(c, '订阅条目主行'), head = uFind(c, 'Group heading');
    const actions = uFind(c, 'Group current node'), entry = uFind(c, '组节点入口');
    const meta = uFind(c, '订阅元信息');
    if (meta.parent !== top) top.insertChild(1, meta);
    for (const name of ['分组选中', '查看订阅信息']) {
      const action = uFind(c, name);
      if (action && action.parent !== actions) actions.insertChild(actions.children.indexOf(entry), action);
    }
    return;
  }
  const head = uFind(c, 'Group heading'), entry = uFind(c, '组节点入口');
  let actions = uFind(c, '分组操作');
  if (!actions) {
    actions = r6Name(row('分组操作', null, 44, 0), '分组操作');
    const selected = uFind(c, '分组选中'), more = uFind(c, '查看订阅信息');
    for (const node of [selected, more, entry]) if (node) actions.appendChild(node);
    head.appendChild(actions);
  }
  const bottom = uFind(c, 'Group current node'); if (bottom) bottom.visible = false;
}
function r72GroupLayout(n, mobile) {
  const facts = uFind(n, 'Group current identity'); if (facts) facts.visible = false;
  if (!mobile) { r73DesktopGroupLayout(n); return; }
  n.layoutMode = 'VERTICAL'; n.primaryAxisSizingMode = 'AUTO'; n.counterAxisSizingMode = 'FIXED';
  n.resize(353, n.height); n.paddingLeft = n.paddingRight = 12; n.paddingTop = n.paddingBottom = 10;
  n.itemSpacing = 6; n.counterAxisAlignItems = 'MIN';
  const head = uFind(n, 'Group heading'), identity = uFind(n, 'Group identity'), copy = uFind(n, 'Group copy');
  r72Fixed(head, 327, 44); head.counterAxisSizingMode = 'FIXED'; head.primaryAxisAlignItems = 'SPACE_BETWEEN'; head.itemSpacing = 8;
  if (identity) { identity.primaryAxisSizingMode = identity.counterAxisSizingMode = 'AUTO'; identity.itemSpacing = 8; }
  if (copy) { r72Fixed(copy, 150); copy.primaryAxisSizingMode = 'AUTO'; copy.itemSpacing = 2; }
  const glyph = identity?.children.find(c => c !== copy); if (glyph && 'resize' in glyph) glyph.resize(28, 28);
  r72Text(uFind(n, '组名称'), 150, 15, 22); r72Text(uFind(n, '组信息'), 150, 11, 16);
  const bottom = uFind(n, 'Group current node'); if (bottom) bottom.visible = false;
  r72IconButton(uFind(n, '组节点入口')); r72IconButton(uFind(n, '查看订阅信息'));
  const actions = uFind(n, '分组操作'); if (actions) { actions.itemSpacing = 0; actions.primaryAxisSizingMode = 'AUTO'; actions.counterAxisSizingMode = 'FIXED'; actions.resize(actions.width, 44); }
  const meta = uFind(n, '订阅元信息'), usage = uFind(n, '订阅流量'), expiry = uFind(n, '订阅有效期');
  if (meta) { r72Fixed(meta, 327, 36); meta.itemSpacing = 10; }
  if (usage) { r72Fixed(usage, 185); usage.itemSpacing = 4; }
  if (expiry) { r72Fixed(expiry, 132); expiry.itemSpacing = 2; }
  r72Text(uFind(n, '订阅流量值'), 185, 11, 16);
  r72Text(uFind(n, '订阅到期值'), 132, 11, 16); r72Text(uFind(n, '订阅状态值'), 132, 11, 16);
  const progress = uFind(n, '订阅用量进度');
  if (progress) {
    const bar = progress.children[0], ratio = r73UsageRatio(n, progress);
    progress.resize(185, 3); if (bar) bar.resize(Math.max(1, 185 * ratio), 3);
  }
  n.setPluginData('rainlink-list-density', '7.2');
}
function r73DesktopIconButton(n) {
  if (!n) return;
  r72IconButton(n); n.resize(32, 32);
}
function r73DesktopGroupLayout(n) {
  n.layoutMode = 'VERTICAL'; n.primaryAxisSizingMode = n.counterAxisSizingMode = 'FIXED'; n.resize(1120, 72);
  n.paddingLeft = n.paddingRight = 16; n.paddingTop = n.paddingBottom = 12;
  n.itemSpacing = 0; n.counterAxisAlignItems = 'MIN';
  const top = uFind(n, '订阅条目主行'), head = uFind(n, 'Group heading');
  const identity = uFind(n, 'Group identity'), copy = uFind(n, 'Group copy');
  r72Fixed(top, 1086, 46); top.counterAxisSizingMode = 'FIXED'; top.itemSpacing = 24;
  top.primaryAxisAlignItems = 'MIN'; top.counterAxisAlignItems = 'CENTER';
  r72Fixed(head, 330, 40); head.counterAxisSizingMode = 'FIXED'; head.primaryAxisAlignItems = 'MIN';
  identity.primaryAxisSizingMode = identity.counterAxisSizingMode = 'AUTO'; identity.itemSpacing = 12;
  const glyph = identity.children.find(c => c !== copy); if (glyph) glyph.resize(32, 32);
  r72Fixed(copy, 286); copy.primaryAxisSizingMode = 'AUTO'; copy.itemSpacing = 2;
  r72Text(uFind(n, '组名称'), 286, 15, 22); r72Text(uFind(n, '组信息'), 286, 12, 16);
  const meta = uFind(n, '订阅元信息'), usage = uFind(n, '订阅流量'), expiry = uFind(n, '订阅有效期');
  r72Fixed(meta, 560, 38); meta.counterAxisSizingMode = 'FIXED'; meta.itemSpacing = 24;
  r72Fixed(usage, 300); usage.primaryAxisSizingMode = 'AUTO'; usage.itemSpacing = 6;
  r72Fixed(expiry, 236); expiry.primaryAxisSizingMode = 'AUTO'; expiry.itemSpacing = 2;
  r72Text(uFind(n, '订阅流量值'), 300, 12, 18);
  r72Text(uFind(n, '订阅到期值'), 236, 12, 18); r72Text(uFind(n, '订阅状态值'), 236, 11, 16);
  const progress = uFind(n, '订阅用量进度');
  if (progress) {
    const bar = progress.children[0], ratio = r73UsageRatio(n, progress);
    progress.resize(300, 3); if (bar) bar.resize(Math.max(1, 300 * ratio), 3);
  }
  const actions = uFind(n, 'Group current node');
  r72Fixed(actions, 148, 40); actions.layoutSizingHorizontal = 'FILL'; actions.counterAxisSizingMode = 'FIXED';
  actions.itemSpacing = 8; actions.primaryAxisAlignItems = 'MAX'; actions.counterAxisAlignItems = 'CENTER';
  r73DesktopIconButton(uFind(n, '查看订阅信息'));
  const entry = uFind(n, '组节点入口');
  entry.primaryAxisSizingMode = entry.counterAxisSizingMode = 'FIXED'; entry.resize(76, 32);
  entry.paddingLeft = entry.paddingRight = 12; entry.paddingTop = entry.paddingBottom = 0;
  entry.primaryAxisAlignItems = entry.counterAxisAlignItems = 'CENTER'; entry.itemSpacing = 6;
  n.setPluginData('rainlink-list-density', '7.3');
}
function r73DesktopNodeLayout(n) {
  n.layoutMode = 'VERTICAL'; n.primaryAxisSizingMode = n.counterAxisSizingMode = 'FIXED'; n.resize(1120, 56);
  n.paddingLeft = n.paddingRight = 16; n.paddingTop = n.paddingBottom = 8; n.itemSpacing = 0;
  const line = uFind(n, 'Node row'), identity = uFind(n, 'Node identity'), facts = uFind(n, 'Node facts');
  r72Fixed(line, 1086, 38); line.counterAxisSizingMode = 'FIXED'; line.itemSpacing = 16;
  r72Fixed(identity, 602, 38); identity.counterAxisSizingMode = 'FIXED'; identity.itemSpacing = 12;
  const country = uFind(n, '国家标记')?.parent, copy = identity.children.find(c => c !== country);
  if (country) country.resize(28, 28);
  if (copy) { r72Fixed(copy, 562); copy.primaryAxisSizingMode = 'AUTO'; copy.itemSpacing = 2; }
  r72Text(uFind(n, '节点名称'), 562, 14, 20); r72Text(uFind(n, '节点地区'), 562, 11, 16);
  r72Fixed(facts, 468, 38); facts.counterAxisSizingMode = 'FIXED'; facts.itemSpacing = 16;
  const tag = uFind(n, '节点协议'), check = uFind(n, '节点选中');
  for (const child of facts.children) if (child.type === 'INSTANCE' && child !== tag && child !== check) r73DesktopIconButton(child);
  r73DesktopIconButton(uFind(n, '未分组节点移动'));
  n.setPluginData('rainlink-list-density', '7.3');
}
function r72NodeStructure(c) {
  if (uFind(c, '紧凑节点内容')) return;
  const name = uFind(c, '节点名称'), country = uFind(c, '国家标记')?.parent;
  const meta = uFind(c, 'Node protocol region'), actions = uFind(c, 'Node actions'), ping = uFind(c, '节点延迟');
  if (!name || !country || !meta || !actions || !ping) throw new Error('节点组件结构不完整');
  const old = [...c.children], copy = r6Name(v('紧凑节点内容', 180, 4), '紧凑节点内容');
  copy.appendChild(name); copy.appendChild(meta); actions.insertChild(0, ping);
  c.appendChild(country); c.appendChild(copy); c.appendChild(actions);
  for (const node of old) if (node !== country && node !== copy && node !== actions) node.remove();
}
function r72NodeLayout(n) {
  n.layoutMode = 'HORIZONTAL'; n.primaryAxisSizingMode = n.counterAxisSizingMode = 'FIXED'; n.resize(353, 72);
  n.paddingLeft = 12; n.paddingRight = 8; n.paddingTop = n.paddingBottom = 8;
  n.itemSpacing = 10; n.counterAxisAlignItems = 'CENTER'; n.primaryAxisAlignItems = 'MIN';
  const country = uFind(n, '国家标记')?.parent, copy = uFind(n, '紧凑节点内容'), meta = uFind(n, 'Node protocol region'), actions = uFind(n, 'Node actions');
  if (country) country.resize(24, 24);
  if (copy) { copy.layoutSizingHorizontal = 'FILL'; copy.primaryAxisSizingMode = 'AUTO'; copy.itemSpacing = 4; }
  const name = uFind(n, '节点名称'); if (name) { name.fontSize = 14; name.lineHeight = {unit:'PIXELS',value:20}; name.textAutoResize = 'WIDTH_AND_HEIGHT'; }
  if (meta) { meta.primaryAxisSizingMode = meta.counterAxisSizingMode = 'AUTO'; meta.itemSpacing = 6; }
  if (actions) { actions.primaryAxisSizingMode = actions.counterAxisSizingMode = 'AUTO'; actions.itemSpacing = 2; }
  const ping = uFind(n, '节点延迟'); if (ping) { ping.fontSize = 11; ping.lineHeight = {unit:'PIXELS',value:16}; ping.textAutoResize = 'WIDTH_AND_HEIGHT'; }
  const move = uFind(n, '未分组节点移动'), check = uFind(n, '节点选中');
  for (const child of actions?.children || []) if (child !== ping && child !== check && child.type === 'INSTANCE') r72IconButton(child);
  r72IconButton(move);
  n.setPluginData('rainlink-list-density', '7.2');
}
async function r72ApplyDensity(report) {
  const groupD = masters['Group / Desktop'], groupM = masters['Group / Mobile'], nodeM = masters['Group node / Mobile'], nodeD = masters['Group node / Desktop'];
  if (!groupD || !groupM || !nodeM || !nodeD) throw new Error('缺少当前分组与节点共享组件');
  // A swapped progress instance inherits its inner bar from its own component.
  // Resize every ratio component so nested component overrides cannot retain the old 590 px geometry.
  for (const c of dsPage.children.filter(n => n.type === 'COMPONENT' && r5Name(n).startsWith('订阅进度 / '))) {
    const parts = r5Name(c).split('/').map(s => s.trim()), ratio = Number(parts[2]), width = parts[1] === '移动端' ? 185 : 300;
    c.primaryAxisSizingMode = c.counterAxisSizingMode = 'FIXED'; c.resize(width, 3);
    const bar = c.children[0]; bar.layoutSizingHorizontal = bar.layoutSizingVertical = 'FIXED'; bar.resize(Math.max(1, width * ratio), 3);
  }
  r72GroupStructure(groupD, false); r72GroupStructure(groupM, true); r72NodeStructure(nodeM);
  r72GroupLayout(groupD, false); r72GroupLayout(groupM, true); r72NodeLayout(nodeM); r73DesktopNodeLayout(nodeD);
  let groupCount = 0, nodeCount = 0, desktopNodeCount = 0;
  for (const page of [dsPage, desktopPage, mobilePage]) {
    const candidates = page.findAll(n => n.type === 'INSTANCE' && /^(Group · |Group \/ |订阅示例 · |Group node \/ (Mobile|Desktop)$|选择节点 · |搜索节点 · )/.test(r5Name(n)));
    for (const n of candidates) {
      const main = await n.getMainComponentAsync();
      if (main?.id === groupD.id || main?.id === groupM.id) { r72GroupLayout(n, main.id === groupM.id); groupCount++; }
      if (main?.id === nodeM.id) { r72NodeLayout(n); nodeCount++; }
      if (main?.id === nodeD.id) { r73DesktopNodeLayout(n); desktopNodeCount++; }
    }
  }
  for (const set of dsPage.children.filter(n => n.type === 'COMPONENT_SET' && /交互 \/ (移动端|桌面端) \/ (分组选择|节点选择)$/.test(r5Name(n)))) {
    for (const variant of set.children) {
      variant.itemSpacing = /桌面端 \/ 节点选择$/.test(r5Name(set)) ? 0 : 8;
      if (/桌面端 \/ 节点选择$/.test(r5Name(set))) {
        const header = uFind(variant, 'Node table headings'); if (header) header.resize(1120, 36);
      }
    }
  }
  for (const key of ['Profiles', 'Nodes', 'Quick switch']) {
    const content = uFind(registry.mobile[key], 'Content'); if (content) { content.itemSpacing = 10; content.paddingBottom = 16; }
  }
  await r5Yield();
  const groups = uFind(registry.mobile.Profiles, '分组选择列表'), nodes = uFind(registry.mobile.Nodes, '节点分组与选择');
  const cards = groups.children.filter(n => n.type === 'INSTANCE');
  if (cards.some(n => n.height > 109)) throw new Error('移动分组条目未压缩：' + cards.map(n=>n.height).join(','));
  const nodeRows = nodes.children.filter(n => r5Name(n).startsWith('选择节点 · '));
  if (nodeRows.some(n => Math.abs(n.height - 72) > 1)) throw new Error('移动节点条目高度不正确');
  for (const reg of [registry.desktop, registry.mobile]) {
    const groupList = uFind(reg.Profiles, '分组选择列表');
    if (groupList.findAll(n => n.type === 'TEXT' && r5Name(n) === '组当前节点' && n.visible && n.parent.visible).length) throw new Error('分组列表仍显示节点名称');
  }
  const desktopGroups = uFind(registry.desktop.Profiles, '分组选择列表'), desktopNodes = uFind(registry.desktop.Nodes, '节点分组与选择');
  const desktopCards = desktopGroups.children.filter(n => n.type === 'INSTANCE');
  const desktopRows = desktopNodes.children.filter(n => r5Name(n).startsWith('选择节点 · '));
  if (desktopCards.some(n => Math.abs(n.height - 72) > 1) || desktopRows.some(n => Math.abs(n.height - 56) > 1)) throw new Error('桌面列表密度未应用');
  report.version = '7.3';
  report.listDensity = { version:'7.3', screensAdded:0, groupNodeNamesVisible:false, desktopSubscriptionHeight:72, desktopManualGroupHeight:72, desktopNodeHeight:56, desktopGroupHeights:desktopCards.map(n=>n.height), desktopGroupListHeight:desktopGroups.height, desktopNodeListHeight:desktopNodes.height, desktopActionTarget:32, desktopNodeInstancesUpdated:desktopNodeCount, mobileSubscriptionHeight:108, mobileManualGroupHeight:66, mobileNodeHeight:72, listGap:8, actionTarget:44, groupInstancesUpdated:groupCount, nodeInstancesUpdated:nodeCount, mobileGroupHeights:cards.map(n=>n.height), groupListHeight:groups.height, nodeListHeight:nodes.height, masters:{desktopGroup:groupD.id,desktopNode:nodeD.id,mobileGroup:groupM.id,mobileNode:nodeM.id} };
  figma.root.setPluginData('rainlink-density-version', '7.3');
  if (figma.root.getPluginData('rainlink-node-search-version') === '7.4') await r74ApplySearch(report);
  return report.listDensity;
}
async function r72DensityMain() {
  figma.showUI('<body style="padding:24px;background:#151617;color:#c0c2c8;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#8adcbf">RainLink / 紧凑列表</h2><p id="s">压缩桌面分组与节点，保留移动端紧凑布局…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>', {width:480,height:170});
  await r5Initialize(); figma.skipInvisibleInstanceChildren = false; await r71Palette();
  const report = JSON.parse(figma.root.getPluginData('rainlink-report'));
  await r72ApplyDensity(report); await r71VerifyControls(report);
  const audit = await r5AuditDocument(); report.overflow = audit.overflow; report.untranslatedDisplayCopy = audit.untranslatedDisplayCopy;
  delete report.nativeBackup; delete report.screenshotVerification;
  const text = uFind(dsPage, 'Delivery / Native audit'); text.characters = 'RainLink 设计核验\n' + JSON.stringify(report, null, 2); text.visible = false;
  figma.root.setPluginData('rainlink-report', JSON.stringify(report));
  await figma.setCurrentPageAsync(desktopPage); figma.currentPage.selection = [registry.desktop.Profiles, registry.desktop.Nodes]; figma.viewport.scrollAndZoomIntoView(figma.currentPage.selection);
  figma.notify('桌面分组 72 px · 节点 56 px · 两端紧凑列表已同步'); figma.closePlugin();
}
