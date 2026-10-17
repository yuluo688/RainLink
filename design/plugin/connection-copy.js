// Apply product terminology to the existing document without rebuilding screens.
const R79_COPY_PAIRS=[
  ['选择目标、VPN 开关和代理模式集中于此。','选择连接目标，管理连接状态与代理模式。'],
  ['新节点仅被保存。选择节点后，在概览开启 VPN。','节点已保存至未分组。选择节点后，在概览开始连接。'],
  ['保存只更改选择。VPN 开关与代理模式均在概览。','保存后仅更新选择，连接开关与代理模式均在概览。'],
  ['当前连接保持不变，返回概览开关 VPN 后应用。','当前连接保持不变，返回概览重新连接后应用。'],
  ['应用可能立即重连，VPN 状态保持开启。','应用可能立即重连，当前连接保持开启。'],
  ['系统代理不可用 · 通过 VPN 隧道接管','通过系统隧道接管网络'],
  ['连接需要系统 VPN 授权，RainLink 将在确认后请求系统许可。','连接需要系统授权，RainLink 将在确认后请求网络接管权限。'],
  ['系统 VPN · ','网络接管 · '],
  ['未获得 VPN 权限','未获得连接权限'],
  ['允许系统 VPN','允许网络连接'],
  ['允许 VPN','允许连接'],
  ['VPN 已开启','已连接'],
  ['VPN 已关闭','未连接'],
  ['点按开启 VPN','点按连接'],
  ['点按关闭 VPN','点按断开'],
  ['关闭再开启 VPN','断开后重新连接'],
  ['重新开启 VPN','重新连接'],
  ['开关 VPN 后应用','重新连接后应用'],
  ['关闭 VPN','断开连接'],
  ['开启 VPN','开始连接'],
  ['VPN 关闭','未连接'],
  ['VPN 开启','已连接'],
  ['VPN control','连接控制'],
  ['VPN power button','连接开关按钮'],
  ['VPN mode caption','连接模式说明'],
  ['VPN 连接控制','连接控制'],
  ['VPN 总开关','连接总开关'],
  ['VPN 开关','连接开关'],
  ['VPN 模式说明','连接模式说明'],
  ['系统 VPN 说明','系统隧道说明'],
  ['系统 VPN 授权','系统连接授权'],
  ['系统 VPN 接管','系统隧道接管'],
  ['VPN 隧道','系统隧道'],
  ['系统 VPN','系统隧道']
];
function r79ConnectionCopy(text){
  for(const [before,after]of R79_COPY_PAIRS)text=text.split(before).join(after);
  return text.replace(/\bVPN\b/gi,'连接');
}
async function r79RemoveVpnCopy(report){
  const audit=uFind(dsPage,'Delivery / Native audit'),nodes=[...desktopPage.findAll(()=>true),...mobilePage.findAll(()=>true),...dsPage.findAll(()=>true)],changes=[];
  const inherited=n=>{for(let p=n.parent;p&&p.type!=='PAGE';p=p.parent)if(p.type==='INSTANCE')return true;return false;};
  // Update source text before instance overrides to keep inherited text inherited.
  for(const pass of [false,true])for(const n of nodes){
    if(n===audit||n.type!=='TEXT'||!(/\bVPN\b/i.test(n.characters))||inherited(n)!==pass)continue;
    const before=n.characters,after=r79ConnectionCopy(before);if(before===after)continue;
    const oldFont=n.fontName;
    n.setBoundVariable('characters',null);
    if(oldFont===figma.mixed||oldFont.family!==zhFamily){const style=oldFont===figma.mixed?'Regular':/bold/i.test(oldFont.style)?'Bold':/medium/i.test(oldFont.style)?'Medium':'Regular';n.fontName={family:zhFamily,style:zhStyles[style]||zhStyles.Regular};}
    n.characters=after;n.setPluginData('rainlink-original-text',after);changes.push({id:n.id,before,after});
    if(changes.length%40===0)await r5Yield();
  }
  let renamed=0,descriptions=0;
  for(const n of nodes){
    if(n===audit)continue;
    if(/\bVPN\b/i.test(n.name)){if(!n.getPluginData('rainlink-canonical-name'))n.setPluginData('rainlink-canonical-name',n.name);n.name=r79ConnectionCopy(n.name);renamed++;}
    if('description'in n&&typeof n.description==='string'&&/\bVPN\b/i.test(n.description)){n.description=r79ConnectionCopy(n.description);descriptions++;}
  }
  const remainingText=nodes.filter(n=>n!==audit&&n.type==='TEXT'&&/\bVPN\b/i.test(n.characters)).map(n=>({id:n.id,text:n.characters})),remainingNames=nodes.filter(n=>n!==audit&&/\bVPN\b/i.test(n.name)).map(n=>({id:n.id,name:n.name}));
  const prior=report.reviewFix.connectionTerminology,allChanges=[...(prior?.changes||[]),...changes];
  report.reviewFix.connectionTerminology={revision:'1',verifiedAt:new Date().toISOString(),changedTextLayers:allChanges.length,renamedLayers:(prior?.renamedLayers||0)+renamed,changedDescriptions:(prior?.changedDescriptions||0)+descriptions,remainingText,remainingNames,changes:allChanges,technicalIdentifiersPreserved:true};
  if(remainingText.length||remainingNames.length)throw new Error('连接文案仍有旧术语：'+remainingText.length+' / '+remainingNames.length);
}
