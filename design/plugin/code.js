// RainLink · native Figma design source. No network access, account data or live traffic.
// The example nodes, rates and domains below are illustrative product data.
const C = {
  Background:['#0B1015','#F3F6F7'], Surface:['#121A22','#FFFFFF'], Raised:['#19232D','#EDF2F4'],
  Hover:['#21313B','#E4ECEF'], Stroke:['#293742','#D9E3E7'], Text:['#EEF5F4','#152723'],
  Secondary:['#A8BAC5','#516771'], Muted:['#8196A3','#657C88'], Primary:['#86E5C3','#127D63'],
  PrimarySurface:['#19362E','#E0F5EC'], OnPrimary:['#0A2A20','#FFFFFF'], Success:['#86E5C3','#127D63'],
  Warning:['#E7BD7D','#97600E'], WarningSurface:['#362D20','#FFF2D8'], Error:['#F28F9D','#BA3651'],
  ErrorSurface:['#39232D','#FFE9EE'], Info:['#97BDFC','#326EBD'], InfoSurface:['#1F2E45','#E8F0FF'],
  Chart2:['#839EF3','#697DCC'], Transparent:['#0B1015','#F3F6F7']
};
const registry={desktop:{},mobile:{},components:{},links:[],counts:{},warnings:[]};
const masters={}, icons={}, vars={}, lightVars={}, textStyles={};
let dsPage, desktopPage, mobilePage, collection, lightCollection, darkMode, lightMode, monoFamily='Roboto Mono';
let libraryX=0, libraryY=0, pending=[], lastStatus='Initializing';
const rgb=h=>({r:parseInt(h.slice(1,3),16)/255,g:parseInt(h.slice(3,5),16)/255,b:parseInt(h.slice(5,7),16)/255});
function paint(token,alpha=1){let p={type:'SOLID',color:rgb(C[token]?C[token][0]:token),opacity:alpha}; return vars[token]?figma.variables.setBoundVariableForPaint(p,'color',vars[token]):p;}
function fill(n,token,alpha=1){n.fills=token?[paint(token,alpha)]:[];return n;}
function applyLight(node){
 const ids=Object.keys(vars).reduce((m,k)=>{m[vars[k].id]=k;return m;},{});
 function convert(p){const colorId=p.boundVariables&&p.boundVariables.color&&p.boundVariables.color.id;if(colorId&&ids[colorId])return figma.variables.setBoundVariableForPaint(p,'color',lightVars[ids[colorId]]);if(p.type==='SOLID'){for(const k of Object.keys(C)){const a=rgb(C[k][0]);if(Math.abs(p.color.r-a.r)<.002&&Math.abs(p.color.g-a.g)<.002&&Math.abs(p.color.b-a.b)<.002)return {...p,color:rgb(C[k][1])};}}if(p.gradientStops)return {...p,gradientStops:p.gradientStops.map(s=>{let col=s.color;for(const k of Object.keys(C)){const a=rgb(C[k][0]);if(Math.abs(col.r-a.r)<.002&&Math.abs(col.g-a.g)<.002&&Math.abs(col.b-a.b)<.002){col={...rgb(C[k][1]),a:col.a};break;}}return {...s,color:col};})};return p;}
 const all=[node,...('findAll'in node?node.findAll(()=>true):[])];for(const n of all){if('fills'in n&&Array.isArray(n.fills))n.fills=n.fills.map(convert);if('strokes'in n&&Array.isArray(n.strokes))n.strokes=n.strokes.map(convert);}
 node.setPluginData('rainlink-theme','Light');
}
function stroke(n,token='Stroke',weight=1){n.strokes=[paint(token)];n.strokeWeight=weight;n.strokeAlign='INSIDE';return n;}
function rad(n,r=12){n.cornerRadius=r;n.cornerSmoothing=.6;return n;}
function frame(name,w,h,dir='VERTICAL',bg=null,gap=0,pad=0){const n=figma.createFrame();n.name=name;fill(n,bg);n.resize(w||1,h||1);n.layoutMode=dir;n.primaryAxisSizingMode=h===null||w===null?'AUTO':'FIXED';n.counterAxisSizingMode='FIXED';n.primaryAxisAlignItems='MIN';n.counterAxisAlignItems='MIN';n.itemSpacing=gap;n.paddingLeft=n.paddingRight=n.paddingTop=n.paddingBottom=pad;n.clipsContent=false;return n;}
function v(name,w,gap=0,pad=0,bg=null){const n=frame(name,w,1,'VERTICAL',bg,gap,pad);n.primaryAxisSizingMode='AUTO';return n;}
function row(name,w,h,gap=0,pad=0,bg=null){const n=frame(name,w||1,h||1,'HORIZONTAL',bg,gap,pad);n.counterAxisAlignItems='CENTER';if(!w)n.primaryAxisSizingMode='AUTO';if(!h)n.counterAxisSizingMode='AUTO';return n;}
function add(p,...ns){ns.filter(Boolean).forEach(n=>p.appendChild(n));return p;}
function stretch(n){n.layoutAlign='STRETCH';return n;}
function grow(n){n.layoutGrow=1;return n;}
function between(n){n.primaryAxisAlignItems='SPACE_BETWEEN';return n;}
function center(n){n.primaryAxisAlignItems='CENTER';n.counterAxisAlignItems='CENTER';return n;}
function tx(s,size=14,color='Text',weight='Regular',w=null,mono=false){const n=figma.createText();n.name=s.length>55?s.slice(0,55):s;n.fontName={family:mono?monoFamily:'Inter',style:mono?'Regular':weight};n.fontSize=size;n.characters=s;fill(n,color);n.lineHeight={unit:'PIXELS',value:Math.round(size*1.45)};if(w){n.resize(w,Math.ceil(size*1.45));n.textAutoResize='HEIGHT';}else n.textAutoResize='WIDTH_AND_HEIGHT';return n;}
function small(s,c='Muted',w=null){return tx(s,12,c,'Regular',w);}
function heading(s,w=null){return tx(s,28,'Text','Semi Bold',w);}
function divider(w){const n=figma.createRectangle();n.name='Divider';n.resize(w,1);fill(n,'Stroke');return n;}
function space(h=1){const n=frame('Flexible space',1,h);n.fills=[];return n;}
function dot(color='Success',size=6){const n=figma.createEllipse();n.name='Status dot';n.resize(size,size);fill(n,color);return n;}
function borderCard(name,w,h=null,pad=24,gap=16,bg='Surface'){const n=v(name,w,gap,pad,bg);if(h){n.resize(w,h);n.primaryAxisSizingMode='FIXED';}rad(n,16);stroke(n);return n;}
function textColumn(title,sub,size=14,w=null){return add(v(title,w||240,4),tx(title,size,'Text','Medium',w),sub?small(sub,'Muted',w):null);}
const paths={
 grid:'<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
 nodes:'<circle cx="12" cy="5" r="2.3"/><circle cx="5" cy="18" r="2.3"/><circle cx="19" cy="18" r="2.3"/><path d="M10.9 7 6.1 16M13.1 7l4.8 9M7.4 18h9.2"/>',
 profile:'<path d="M7 3h8l4 4v14H5V3h2Z"/><path d="M14 3v5h5M8 12h8M8 16h6"/>',
 rules:'<path d="M4 6h16M4 12h16M4 18h16"/><circle cx="8" cy="6" r="2" fill="#fff"/><circle cx="16" cy="12" r="2" fill="#fff"/><circle cx="10" cy="18" r="2" fill="#fff"/>',
 connections:'<path d="M4 8h16m-4-4 4 4-4 4M20 16H4m4-4-4 4 4 4"/>',
 chart:'<path d="M4 3v17h17M7 14l4-4 4 2 6-8"/>',
 terminal:'<rect x="3" y="4" width="18" height="16" rx="3"/><path d="m7 8 4 4-4 4m7 0h4"/>',
 settings:'<path d="m10 3-.8 2.4-2.4 1L4.4 6 3 8.4l1.6 1.9v3.4L3 15.6 4.4 18l2.4-.4 2.4 1L10 21h4l.8-2.4 2.4-1 2.4.4 1.4-2.4-1.6-1.9v-3.4L21 8.4 19.6 6l-2.4.4-2.4-1L14 3Z"/><circle cx="12" cy="12" r="3"/>',
 search:'<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
 chevron:'<path d="m8 5 7 7-7 7"/>', down:'<path d="m5 9 7 7 7-7"/>', plus:'<path d="M12 4v16M4 12h16"/>',
 check:'<path d="m5 12 4 4L20 5"/>', close:'<path d="m6 6 12 12M6 18 18 6"/>', star:'<path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2-5.6-3-5.6 3 1.1-6.2L3 9.6l6.2-.9Z"/>',
 power:'<path d="M12 3v9M6.3 5.7a8.5 8.5 0 1 0 11.4 0"/>', download:'<path d="M12 3v12m-5-5 5 5 5-5M4 17v4h16v-4"/>', upload:'<path d="M12 16V4m-5 5 5-5 5 5M4 17v4h16v-4"/>',
 speed:'<path d="M4.7 17.8a9 9 0 1 1 14.6 0M12 12l5-5"/><circle cx="12" cy="12" r="1.5"/>', globe:'<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c5 5 5 13 0 18-5-5-5-13 0-18Z"/>',
 shield:'<path d="m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6l8-3Z"/><path d="m8 12 3 3 5-6"/>', bell:'<path d="M5 17h14l-2-3V9a5 5 0 0 0-10 0v5l-2 3ZM10 21h4"/>',
 sun:'<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5 19 19M5 19l1.5-1.5M17.5 6.5 19 5"/>', moon:'<path d="M20 14A9 9 0 0 1 10 4a9 9 0 1 0 10 10Z"/>',
 refresh:'<path d="M20 7v5h-5M4 17v-5h5M5.4 7a8 8 0 0 1 13.2-1M18.6 17a8 8 0 0 1-13.2 1"/>', qr:'<path d="M3 3h7v7H3ZM14 3h7v7h-7ZM3 14h7v7H3ZM14 14h3v3h4v4h-7v-3M20 14v2"/>',
 link:'<path d="m10 13 4-4M8 16l-1 1a4.2 4.2 0 0 1-6-6l5-5a4.2 4.2 0 0 1 6 0m0 12a4.2 4.2 0 0 0 6 0l5-5a4.2 4.2 0 0 0-6-6l-1 1"/>',
 copy:'<rect x="8" y="8" width="12" height="13" rx="2"/><path d="M16 8V3H3v13h5"/>', more:'<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
 clock:'<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>', folder:'<path d="M3 7V4h7l2 3h9v13H3V7Z"/>', arrow:'<path d="M4 12h16m-6-6 6 6-6 6"/>',
 laptop:'<rect x="5" y="3" width="14" height="12" rx="2"/><path d="M2 19h20l-3-4H5l-3 4Z"/>', wifi:'<path d="M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8 16a6 6 0 0 1 8 0"/><circle cx="12" cy="20" r="1"/>',
 rain:'<path d="M12 2.5S4.5 10.8 4.5 15a7.5 7.5 0 0 0 15 0C19.5 10.8 12 2.5 12 2.5Z"/><path d="m7.5 15 3-3 3 3 3-3"/><circle cx="7.5" cy="15" r="1" fill="#fff"/><circle cx="16.5" cy="12" r="1" fill="#fff"/>'
};
function tint(n,token){if('strokes'in n&&n.strokes.length)n.strokes=n.strokes.map(p=>p.type==='SOLID'?paint(token,p.opacity===undefined?1:p.opacity):p);if('fills'in n&&Array.isArray(n.fills)&&n.fills.length)n.fills=n.fills.map(p=>p.type==='SOLID'?paint(token,p.opacity===undefined?1:p.opacity):p);if('children'in n)n.children.forEach(c=>tint(c,token));}
function icon(name,size=18,color='Secondary'){const n=icons[name].createInstance();n.name='Icon / '+name;n.resize(size,size);if(color!=='Secondary')tint(n,color);return n;}
function component(name,build){const n=figma.createComponent();n.name=name;fill(n,null);n.layoutMode='VERTICAL';n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='AUTO';n.itemSpacing=0;dsPage.appendChild(n);build(n);masters[name]=n;registry.components[name]=n.id;return n;}
function instance(name){const n=masters[name].createInstance();n.name=name;n.setPluginData('rainlink-canonical-name',name);return n;}
function textOverride(n,name,s,color=null){const t=n.findOne(x=>x.type==='TEXT'&&(x.getPluginData('rainlink-canonical-name')||x.name)===name);if(t){t.characters=s;t.setPluginData('rainlink-original-text',s);if(color)fill(t,color);}return n;}
function btn(s,tone='Secondary',size='M',ic=null){const n=instance('Button / '+tone+' / '+size);textOverride(n,'Label',s);const sl=n.findOne(x=>(x.getPluginData('rainlink-canonical-name')||x.name)==='Icon slot');if(sl){sl.visible=!!ic;if(ic)sl.swapComponent(icons[ic]);}n.primaryAxisSizingMode='AUTO';const lab=n.findOne(x=>(x.getPluginData('rainlink-canonical-name')||x.name)==='Label');if(lab)lab.visible=!!s;n.name='Button · '+s;n.setPluginData('rainlink-canonical-name',n.name);return n;}
function badge(s,tone='Neutral',ic=false){const n=instance('Badge / '+tone);textOverride(n,'Label',s);const d=n.findOne(x=>x.name==='Status dot');if(d)d.visible=ic;n.primaryAxisSizingMode='AUTO';return n;}
function sw(on=true){return instance('Switch / '+(on?'On':'Off'));}
function input(placeholder,w=260,ic='search',focused=false){const n=instance('Input / '+(focused?'Focus':'Default'));n.resize(w,40);textOverride(n,'Value',placeholder);const sl=n.findOne(x=>(x.getPluginData('rainlink-canonical-name')||x.name)==='Icon slot');if(sl){sl.visible=!!ic;if(ic)sl.swapComponent(icons[ic]);}return n;}
function field(label,val,w=360,ic=null,helper=null){return add(v(label+' field',w,8),small(label,'Secondary'),input(val,w,ic),helper?small(helper,'Muted',w):null);}
function sectionHeader(title,meta,actions=null,w=1072){const n=between(row(title+' heading',w,null,12));add(n,textColumn(title,meta,18,w-230),actions);return n;}
function miniIcon(name,color='Secondary',size=36,bg='Raised'){const n=center(rad(row('Icon container',size,size,0,0,bg),10));add(n,icon(name,18,color));return n;}
function metric(title,value,unit,sub,ic,color='Primary',w=268){const n=borderCard('Metric · '+title,w,112,20,10);const top=between(row(title,w-40,null));add(top,small(title,'Secondary'),icon(ic,16,'Muted'));const val=add(row('Value',w-40,null,7),tx(value,28,'Text','Semi Bold'),tx(unit,13,'Muted'));add(n,top,val,small(sub,color));return n;}
function caption(s,w=1100){return tx(s,12,'Muted','Regular',w);}
function country(code,size=32){const n=center(rad(row('Region / '+code,size,size,0,0,'Raised'),9));add(n,tx(code,11,'Secondary','Semi Bold'));return n;}
const nodes=[
 {name:'Tokyo · Sakura',region:'Japan',code:'JP',city:'Tokyo',p:'VLESS',ping:'24',status:'Online',fav:true},
 {name:'Singapore · Marina',region:'Singapore',code:'SG',city:'Singapore',p:'Trojan',ping:'38',status:'Online',fav:true},
 {name:'Hong Kong · Victoria',region:'Hong Kong',code:'HK',city:'Hong Kong',p:'Hysteria',ping:'18',status:'Online',fav:true},
 {name:'Seoul · Han River',region:'South Korea',code:'KR',city:'Seoul',p:'TUIC',ping:'42',status:'Online',fav:false},
 {name:'Los Angeles · Pacific',region:'United States',code:'US',city:'Los Angeles',p:'Shadowsocks',ping:'142',status:'Online',fav:false},
 {name:'Frankfurt · Main',region:'Germany',code:'DE',city:'Frankfurt',p:'VMess',ping:'186',status:'Online',fav:false},
 {name:'London · Thames',region:'United Kingdom',code:'GB',city:'London',p:'SOCKS5',ping:'—',status:'Timeout',fav:false},
 {name:'Amsterdam · Canal',region:'Netherlands',code:'NL',city:'Amsterdam',p:'HTTP',ping:'164',status:'Online',fav:false}
];
function nodeCard(data=nodes[0],selected=false,w=353){const n=instance('Node Card / '+(selected?'Selected':'Default'));n.resize(w,88);textOverride(n,'Node name',data.name);textOverride(n,'Node region',data.city+' · '+data.region);textOverride(n,'Protocol',data.p);textOverride(n,'Latency',data.ping+' ms');textOverride(n,'Country',data.code);const st=n.findOne(x=>x.name==='Favorite');if(st){st.visible=data.fav;tint(st,'Warning');}n.name='Node · '+data.name;return n;}
function tabs(labels,active=0,w=320){const r=row('Tabs',w,38,4,4,'Raised');rad(r,10);labels.forEach((s,i)=>{const n=instance('Tab / '+(i===active?'Active':'Default'));textOverride(n,'Label',s);n.resize((w-8-4*(labels.length-1))/labels.length,30);add(r,n);});return r;}
function chart(w=680,h=160,two=false,type='latency'){const n=instance('Chart / '+(two?'Traffic':'Latency'));n.resize(w,h);n.name='Chart · '+type;return n;}
function chartSvg(w=700,h=150,two=false){let grid='';for(let i=0;i<4;i++){let y=12+i*(h-22)/3;grid+='<path d="M0 '+y+'H'+w+'" stroke="#293742" stroke-width="1" stroke-dasharray="3 5"/>';}
 const ys=two?[.80,.76,.79,.74,.52,.61,.56,.57,.50,.68,.72,.60,.31,.48,.41,.45,.12,.31,.29,.39,.20,.35,.51,.56,.42,.40,.26,.38,.46,.31,.40,.23]:[.68,.61,.65,.62,.64,.48,.53,.57,.49,.51,.55,.31,.43,.50,.48,.54,.58,.53,.48,.51,.40,.48,.36,.31,.40,.44,.32,.37,.47,.41,.37,.45];
 const points=ys.map((p,i)=>(i*w/(ys.length-1)).toFixed(1)+','+(8+p*(h-24)).toFixed(1));const line='M'+points.join(' L');let second='';if(two){const p=ys.map((p,i)=>(i*w/(ys.length-1)).toFixed(1)+','+(h-12-(1-p)*.33*h).toFixed(1));second='<path d="M'+p.join(' L')+'" fill="none" stroke="#839EF3" stroke-width="2"/>';}
 return '<svg width="'+w+'" height="'+h+'" viewBox="0 0 '+w+' '+h+'" xmlns="http://www.w3.org/2000/svg"><defs><linearGradient id="a" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#86E5C3" stop-opacity=".18"/><stop offset="1" stop-color="#86E5C3" stop-opacity="0"/></linearGradient></defs>'+grid+'<path d="'+line+' L'+w+','+h+' L0,'+h+' Z" fill="url(#a)"/><path d="'+line+'" stroke="#86E5C3" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>'+second+'</svg>';}
function attach(s,target,kind='NAVIGATE'){pending.push({node:s,target,kind});return s;}
function fullButton(s,tone,w,ic=null){const n=btn(s,tone,'L',ic);n.primaryAxisSizingMode='FIXED';n.resize(w,48);n.primaryAxisAlignItems='CENTER';return n;}
async function makeTokens(){collection=figma.variables.createVariableCollection('RainLink / Colors / Dark');darkMode=collection.modes[0].modeId;collection.renameMode(darkMode,'Dark');lightMode=darkMode;lightCollection=figma.variables.createVariableCollection('RainLink / Colors / Light');lightCollection.renameMode(lightCollection.defaultModeId,'Light');for(const k of Object.keys(C)){const variable=figma.variables.createVariable(k,collection,'COLOR');variable.setValueForMode(darkMode,{...rgb(C[k][0]),a:1});vars[k]=variable;const lv=figma.variables.createVariable(k,lightCollection,'COLOR');lv.setValueForMode(lightCollection.defaultModeId,{...rgb(C[k][1]),a:1});lightVars[k]=lv;}
 const values={Display:[40,'Semi Bold'],Heading:[28,'Semi Bold'],Title:[20,'Semi Bold'],Subtitle:[16,'Medium'],Body:[14,'Regular'],Label:[13,'Medium'],Caption:[12,'Regular']};
 for(const k of Object.keys(values)){const st=figma.createTextStyle();st.name='RainLink / '+k;st.fontName={family:'Inter',style:values[k][1]};st.fontSize=values[k][0];st.lineHeight={unit:'PIXELS',value:Math.round(values[k][0]*1.45)};textStyles[k]=st;}
 const sh=figma.createEffectStyle();sh.name='RainLink / Floating panel';sh.effects=[{type:'DROP_SHADOW',color:{r:0,g:0,b:0,a:.3},offset:{x:0,y:18},radius:48,spread:0,visible:true,blendMode:'NORMAL'}];
 const spacing=figma.variables.createVariableCollection('RainLink / Spacing & radius');for(const num of [4,8,12,16,20,24,32,40,48,64]){const variable=figma.variables.createVariable('Space/'+num,spacing,'FLOAT');variable.setValueForMode(spacing.defaultModeId,num);}for(const num of [8,10,12,16,24]){const variable=figma.variables.createVariable('Radius/'+num,spacing,'FLOAT');variable.setValueForMode(spacing.defaultModeId,num);}
}
async function makeComponents(){
 for(const name of Object.keys(paths)){const c=figma.createComponent();c.name='Icon / '+name;c.resize(24,24);fill(c,null);const svg=figma.createNodeFromSvg('<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#A8BAC5" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg">'+paths[name]+'</svg>');add(c,svg);tint(svg,name==='rain'?'Primary':'Secondary');dsPage.appendChild(c);icons[name]=c;}
 component('Brand / Mark',c=>{c.resize(40,40);c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.primaryAxisAlignItems='CENTER';c.counterAxisAlignItems='CENTER';rad(c,12);fill(c,'PrimarySurface');add(c,icon('rain',27,'Primary'));c.description='A rain droplet carrying a connected data path. Keep at least 8 px of clear space.';});
 const buttons=[];for(const tone of ['Primary','Secondary','Ghost','Danger'])for(const size of ['S','M','L']){const c=component('Button / '+tone+' / '+size,n=>{n.layoutMode='HORIZONTAL';n.itemSpacing=8;n.paddingLeft=n.paddingRight=size==='S'?10:16;n.resize(110,size==='L'?48:size==='S'?32:40);n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='FIXED';n.counterAxisAlignItems='CENTER';rad(n,10);fill(n,tone==='Primary'?'Primary':tone==='Secondary'?'Raised':tone==='Danger'?'ErrorSurface':null);if(tone==='Secondary')stroke(n);const it=icon('plus',16,tone==='Primary'?'OnPrimary':tone==='Danger'?'Error':'Secondary');it.name='Icon slot';it.visible=false;const lab=tx('Button',size==='S'?12:13,tone==='Primary'?'OnPrimary':tone==='Danger'?'Error':'Text','Medium');lab.name='Label';add(n,it,lab);n.description='44 px touch target on mobile; keyboard focus uses a 2 px primary outline.';});c.name='Style='+tone+', Size='+size;buttons.push(c);}
 registry.components['Button variants']=figma.combineAsVariants(buttons,dsPage).id;
 const badges=[];for(const tone of ['Neutral','Success','Warning','Error','Info']){const c=component('Badge / '+tone,n=>{n.layoutMode='HORIZONTAL';n.itemSpacing=6;n.paddingLeft=n.paddingRight=8;n.paddingTop=n.paddingBottom=4;n.counterAxisAlignItems='CENTER';rad(n,6);const color=tone==='Neutral'?'Secondary':tone;fill(n,tone==='Neutral'?'Raised':tone==='Success'?'PrimarySurface':tone+'Surface');const d=dot(color,5);const label=tx(tone,11,color,'Medium');label.name='Label';d.visible=false;add(n,d,label);});c.name='Tone='+tone;badges.push(c);}figma.combineAsVariants(badges,dsPage);
 for(const active of [false,true]){component('Switch / '+(active?'On':'Off'),n=>{n.resize(36,22);n.primaryAxisSizingMode='FIXED';n.counterAxisSizingMode='FIXED';n.layoutMode='HORIZONTAL';n.paddingLeft=n.paddingRight=3;n.primaryAxisAlignItems=active?'MAX':'MIN';n.counterAxisAlignItems='CENTER';rad(n,20);fill(n,active?'Primary':'Stroke');const k=figma.createEllipse();k.resize(16,16);fill(k,active?'OnPrimary':'Secondary');add(n,k);n.description=active?'Enabled':'Disabled';});}
 for(const focus of [false,true])component('Input / '+(focus?'Focus':'Default'),n=>{n.resize(260,40);n.layoutMode='HORIZONTAL';n.primaryAxisSizingMode='FIXED';n.counterAxisSizingMode='FIXED';n.counterAxisAlignItems='CENTER';n.itemSpacing=10;n.paddingLeft=n.paddingRight=12;fill(n,'Background');rad(n,10);stroke(n,focus?'Primary':'Stroke',focus?2:1);const ic=icon('search',16);ic.name='Icon slot';const t=tx('Search nodes…',13,'Muted');t.name='Value';t.layoutGrow=1;add(n,ic,t);});
 for(const active of [false,true])component('Tab / '+(active?'Active':'Default'),n=>{n.resize(110,30);n.layoutMode='HORIZONTAL';n.primaryAxisSizingMode='FIXED';n.counterAxisSizingMode='FIXED';n.primaryAxisAlignItems='CENTER';n.counterAxisAlignItems='CENTER';rad(n,7);fill(n,active?'Surface':null);const t=tx('Tab',12,active?'Text':'Muted','Medium');t.name='Label';add(n,t);});
 for(const active of [false,true])component('Navigation / '+(active?'Active':'Default'),n=>{n.resize(208,40);n.layoutMode='HORIZONTAL';n.primaryAxisSizingMode='FIXED';n.counterAxisSizingMode='FIXED';n.counterAxisAlignItems='CENTER';n.itemSpacing=12;n.paddingLeft=n.paddingRight=12;rad(n,9);fill(n,active?'PrimarySurface':null);const ic=icon('grid',18,active?'Primary':'Secondary');ic.name='Nav icon';const label=tx('Dashboard',13,active?'Primary':'Secondary',active?'Medium':'Regular');label.name='Nav label';label.layoutGrow=1;const key=tx('1',11,'Muted', 'Regular',null,true);key.name='Shortcut';add(n,ic,label,key);});
 for(const selected of [false,true])component('Node Card / '+(selected?'Selected':'Default'),n=>{n.resize(353,88);n.layoutMode='HORIZONTAL';n.primaryAxisSizingMode='FIXED';n.counterAxisSizingMode='FIXED';n.counterAxisAlignItems='CENTER';n.itemSpacing=12;n.paddingLeft=n.paddingRight=14;rad(n,13);fill(n,selected?'PrimarySurface':'Surface');stroke(n,selected?'Primary':'Stroke');const flag=country('JP',36);flag.findOne(x=>x.type==='TEXT').name='Country';const mid=v('Node details',210,5);mid.layoutGrow=1;const a=tx('Tokyo · Sakura',14,'Text','Medium');a.name='Node name';const b=small('Tokyo · Japan');b.name='Node region';const r=row('Node metadata',null,null,8);const pp=tx('VLESS',10,'Primary','Medium');pp.name='Protocol';const star=icon('star',12,'Warning');star.name='Favorite';add(r,pp,star);add(mid,a,b,r);const end=v('Latency and state',55,6);end.counterAxisAlignItems='MAX';const ping=tx('24 ms',12,'Primary','Medium');ping.name='Latency';add(end,ping,selected?icon('check',16,'Primary'):icon('chevron',14,'Muted'));add(n,flag,mid,end);});
 for(const two of [false,true])component('Chart / '+(two?'Traffic':'Latency'),n=>{n.resize(700,150);n.primaryAxisSizingMode='FIXED';n.counterAxisSizingMode='FIXED';const svg=figma.createNodeFromSvg(chartSvg(700,150,two));svg.name='Editable chart vectors';add(n,svg);svg.layoutPositioning='ABSOLUTE';svg.constraints={horizontal:'SCALE',vertical:'SCALE'};svg.x=0;svg.y=0;svg.findAll(x=>'constraints' in x).forEach(x=>x.constraints={horizontal:'SCALE',vertical:'SCALE'});});
 component('Dropdown / Node',n=>{n.resize(230,40);n.layoutMode='HORIZONTAL';n.primaryAxisSizingMode='FIXED';n.counterAxisSizingMode='FIXED';n.counterAxisAlignItems='CENTER';n.paddingLeft=n.paddingRight=12;n.itemSpacing=8;fill(n,'Raised');rad(n,10);stroke(n);add(n,country('JP',22),grow(tx('Tokyo · Sakura',12,'Text','Medium')),icon('down',14));});
 component('Card / Base',n=>{n.resize(320,150);n.primaryAxisSizingMode='FIXED';n.counterAxisSizingMode='FIXED';n.paddingLeft=n.paddingRight=n.paddingTop=n.paddingBottom=20;n.itemSpacing=12;rad(n,16);fill(n,'Surface');stroke(n);add(n,tx('Card title',16,'Text','Medium'),small('A focused container for related information.','Muted',280));});
 component('Status / Connected',n=>{n.layoutMode='HORIZONTAL';n.itemSpacing=8;n.counterAxisAlignItems='CENTER';add(n,dot(),tx('Connected',13,'Success','Medium'));});
 component('Mobile / Bottom navigation',n=>{n.resize(393,80);n.layoutMode='HORIZONTAL';n.primaryAxisSizingMode='FIXED';n.counterAxisSizingMode='FIXED';n.itemSpacing=0;n.paddingLeft=n.paddingRight=10;n.paddingTop=10;n.paddingBottom=20;fill(n,'Surface');stroke(n);for(const name of ['Home','Nodes','Profiles','Traffic','Settings']){const i=['grid','nodes','profile','chart','settings'][['Home','Nodes','Profiles','Traffic','Settings'].indexOf(name)];const tab=center(v('Tab · '+name,74,5));tab.resize(74,50);tab.primaryAxisSizingMode='FIXED';add(tab,icon(i,20,name==='Home'?'Primary':'Muted'),tx(name,10,name==='Home'?'Primary':'Muted','Medium'));add(n,tab);}});
 component('Modal / Import subscription',n=>{n.resize(460,410);n.primaryAxisSizingMode='FIXED';n.counterAxisSizingMode='FIXED';n.paddingTop=n.paddingBottom=n.paddingLeft=n.paddingRight=28;n.itemSpacing=20;rad(n,20);fill(n,'Surface');stroke(n);add(n,between(add(row('Title',404,null),tx('Import subscription',20,'Text','Semi Bold'),icon('close'))),small('Add your own subscription URL.','Muted',404),field('Subscription URL','https://example.com/subscription',404,'link'),field('Display name','Personal workspace',404),between(add(row('Automatic updates',404,null),tx('Auto-update every 6 hours',13),sw(true))),between(add(row('Actions',404,null),btn('Cancel','Ghost'),btn('Import profile','Primary','M','download'))));});
 // Arrange every master in a readable native component library.
 const title=heading('Components');dsPage.appendChild(title);title.x=0;title.y=1600;
 const sub=caption('Native components · semantic color bindings · editable vectors · shared across Desktop and Mobile',1200);dsPage.appendChild(sub);sub.x=0;sub.y=1650;
 let x=0,y=1720,rowH=0;const roots=dsPage.children.filter(n=>n.type==='COMPONENT'||n.type==='COMPONENT_SET');for(const n of roots){if(n.type==='COMPONENT_SET'){n.layoutMode='HORIZONTAL';n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='AUTO';n.itemSpacing=16;n.paddingLeft=n.paddingRight=n.paddingTop=n.paddingBottom=16;rad(n,16);stroke(n);n.children.forEach(c=>{c.x=0;c.y=0;});}if(x+n.width>1500){x=0;y+=rowH+90;rowH=0;}n.x=x;n.y=y;const label=small(n.name,'Muted',Math.min(n.width+30,400));dsPage.appendChild(label);label.x=x;label.y=y-26;x+=n.width+40;rowH=Math.max(rowH,n.height);}
 libraryY=y+rowH+180;
}
const navNames=['Dashboard','Nodes','Profiles','Rules','Connections','Traffic','Logs','Settings'];
const navIcons=['grid','nodes','profile','rules','connections','chart','terminal','settings'];
function navItem(name,active,index){const n=instance('Navigation / '+(active?'Active':'Default'));textOverride(n,'Nav label',name);textOverride(n,'Shortcut',String(index+1));const ic=n.findOne(x=>x.name==='Nav icon');if(ic){ic.swapComponent(icons[navIcons[index]]);if(active)tint(ic,'Primary');}n.name='Navigate · '+name;attach(n,'D/'+name);return n;}
function sidebar(active){const n=frame('Sidebar',248,900,'VERTICAL','Surface',0,20);n.paddingTop=26;n.paddingBottom=24;stroke(n);const brand=add(row('Brand',208,44,12),instance('Brand / Mark'),tx('RainLink',22,'Text','Semi Bold'));const workspace=between(add(row('Workspace',208,38,8,10,'Raised'),icon('folder',16),tx('Personal workspace',12,'Secondary','Medium'),icon('down',14)));rad(workspace,9);const spacer=space(20);const nav=v('Primary navigation',208,4);navNames.forEach((s,i)=>add(nav,navItem(s,s===active,i)));const bottom=v('Workspace status',208,16);const mode=borderCard('Routing mode',208,118,14,10,'Background');const activeMode=add(row('Mode title',180,null,8),icon('shield',16,'Primary'),tx('Rule mode',12,'Text','Medium'));add(mode,activeMode,small('Smart routing is active.','Muted',180),add(row('Mode options',180,28,6),badge('Rule','Success'),badge('Global'),badge('Direct')));attach(mode,'D/Rules');const footer=between(add(row('Footer',208,null),small('RainLink 1.0.0'),badge('CORE READY','Success')));add(bottom,mode,footer);add(n,brand,space(20),workspace,space(32),small('WORKSPACE'),space(12),nav,grow(space()),bottom);return n;}
function topbar(online=true){const r=between(row('Connection bar',1192,68,20,0,'Surface'));r.paddingLeft=r.paddingRight=36;stroke(r);const a=add(row('Connection status',null,null,10),dot(online?'Success':'Muted'),tx(online?'Connected':'Disconnected',13,online?'Success':'Muted','Medium'),small(online?'01:42:18':'Ready when you are'));
 const b=add(row('Live connection details',null,null,20),add(row('Latency',null,null,6),icon('speed',14),tx(online?'24 ms':'— ms',12,'Secondary', 'Regular',null,true)),add(row('Download',null,null,6),icon('download',14,'Primary'),tx(online?'12.8 MB/s':'0 MB/s',12,'Text', 'Regular',null,true)),add(row('Upload',null,null,6),icon('upload',14,'Info'),tx(online?'1.4 MB/s':'0 MB/s',12,'Text', 'Regular',null,true)),attach(instance('Dropdown / Node'),'D/Quick switch'),attach(btn('⌘ K','Ghost','S'),'D/Quick switch'));add(r,a,b);return r;}
function pageTitle(title,sub,actions=null){const n=between(row('Page header',1120,64,20));add(n,textColumn(title,sub,28,720),actions);return n;}
function desktop(name,sub,build,options={}){const n=frame('Desktop / '+name,1440,900,'HORIZONTAL','Background',0);n.clipsContent=true;n.setExplicitVariableModeForCollection(collection,options.light?lightMode:darkMode);desktopPage.appendChild(n);const active=options.active||name;const main=frame('Main',1192,900,'VERTICAL',null,0);const body=frame('Content',1192,832,'VERTICAL',null,16,36);body.paddingTop=24;body.paddingBottom=24;const actions=options.actions||add(row('Page actions',null,null,10),btn('Quick switch','Secondary','M','connections'));if(!options.actions)attach(actions.children[0],'D/Quick switch');add(body,pageTitle(name,sub,actions));add(main,topbar(options.online!==false),body);add(n,sidebar(active),main);build(body,n);registry.desktop[name]=n;return n;}
function listRow(cols,widths,w=1072,h=52,header=false){const n=row(header?'Table header':'Table row',w,h,0,0,header?'Raised':null);n.paddingLeft=n.paddingRight=16;cols.forEach((c,i)=>{let cell=row('Column '+i,widths[i],h,6);add(cell,typeof c==='string'?tx(c,header?11:13,header?'Muted':'Secondary',header?'Medium':'Regular'):c);add(n,cell);});return n;}
function tableCard(title,sub,w,heads,widths,rows){const c=borderCard(title,w,null,0,0);const h=between(add(row('Table title',w,70,0,24),textColumn(title,sub,16,w-260),btn('View all','Ghost','S')));add(c,h,listRow(heads,widths,w,36,true));rows.forEach((cells,i)=>{if(i)add(c,divider(w));add(c,listRow(cells,widths,w,50));});return c;}
function latencyCard(w=716,h=268){const c=borderCard('Latency trend',w,h,22,14);add(c,between(add(row('Chart header',w-44,null),textColumn('Latency trend','Tokyo · Sakura · Last 30 minutes',16,400),tabs(['30m','1h','24h'],0,174))),chart(w-44,132),between(add(row('Time axis',w-44,null),small('10:00'),small('10:10'),small('10:20'),small('10:30'))),between(add(row('Chart summary',w-44,null),add(row('Legend',null,null,7),dot('Primary',5),small('Latency','Secondary')),small('Avg 24 ms  ·  Jitter 2 ms','Secondary'))));return c;}
function healthCard(w=380,h=268){const c=borderCard('Node health',w,h,22,16);add(c,between(add(row('Title',w-44,null),tx('Node health',16,'Text','Medium'),badge('7 / 8 online','Success'))));nodes.slice(0,4).forEach(d=>add(c,between(add(row('Health · '+d.name,w-44,32,12),country(d.code,26),grow(tx(d.name.split(' · ')[0],12)),add(row('Ping',null,null,6),dot(),tx(d.ping+' ms',12,'Secondary', 'Regular',null,true))))));add(c,attach(btn('Manage nodes','Ghost','S','arrow'),'D/Nodes'));return c;}
function connectionHero(w=716,h=204,online=true){const c=borderCard('Connection overview',w,h,24,18,'PrimarySurface');stroke(c,'Primary',.5);const top=between(add(row('Connection title',w-48,null),add(row('State',null,null,8),dot(online?'Primary':'Muted'),tx(online?'YOUR NETWORK, IN FLOW':'READY TO CONNECT',11,online?'Primary':'Muted','Medium')),badge('RULE MODE','Success')));const mid=between(row('Connection summary',w-48,null,20));const left=v('Connection information',430,6);add(left,tx(online?'Connected. In control.':'Your next link awaits.',28,'Text','Semi Bold'),small(online?'Traffic flows through your selected node and routing rules.':'Connect to your own node with one click.','Secondary',430));const action=btn(online?'Disconnect':'Connect','Primary','M','power');attach(action,online?'D/Disconnected':'D/Dashboard');add(mid,left,action);const foot=between(add(row('Current node',w-48,null),add(row('Node',null,null,10),country('JP',28),tx('Tokyo · Sakura',13,'Text','Medium'),badge('VLESS','Neutral')),attach(btn('Switch node','Ghost','S','connections'),'D/Quick switch')));add(c,top,mid,foot);return c;}
function qualityCard(w=380,h=204){const c=borderCard('Network quality',w,h,24,14);add(c,between(add(row('Title',w-48,null),tx('Network quality',16,'Text','Medium'),icon('speed',18,'Primary'))));const score=add(row('Quality score',w-48,null,10),tx('98',48,'Text','Semi Bold'),tx('/ 100',16,'Muted'),badge('Excellent','Success'));const bars=row('Quality bars',w-48,8,4);for(let i=0;i<20;i++){const b=figma.createRectangle();b.resize((w-48-76)/20,6);rad(b,2);fill(b,i<19?'Primary':'Stroke');add(bars,b);}add(c,score,bars,small('Stable latency. Zero packet loss.','Secondary'));return c;}
function dashboard(online=true,light=false){return desktop(online?'Dashboard':'Disconnected',online?'A clear view of your network, in real time.':'Your workspace is ready. Select a node to get started.',b=>{add(b,add(row('Traffic metrics',1120,112,16),metric('Today’s traffic','8.42','GB','↑ 12% from yesterday','chart','Primary',268),metric('Download','12.8','MB/s','Peak 24.6 MB/s','download','Muted',268),metric('Upload','1.4','MB/s','Peak 3.2 MB/s','upload','Muted',268),metric('Active connections','142','','18 destinations','connections','Muted',268)),add(row('Connection & quality',1120,204,24),connectionHero(716,204,online),qualityCard()),add(row('Trends & health',1120,268,24),latencyCard(),healthCard()));const recent=borderCard('Recent activity',1120,98,18,10);add(recent,between(add(row('Activity title',1084,null),tx('Recent connections',14,'Text','Medium'),attach(btn('Open connections','Ghost','S'),'D/Connections'))),between(add(row('Recent destinations',1084,null),small('api.github.com','Secondary'),badge('PROXY','Success'),small('docs.rs','Secondary'),badge('PROXY','Success'),small('192.168.1.1','Secondary'),badge('DIRECT'),small('Updated just now'))));add(b,recent);},{active:'Dashboard',online,light});}
function desktopNodes(){const actions=add(row('Node actions',null,null,10),attach(btn('Test latency','Secondary','M','speed'),'D/Nodes tested'),attach(btn('Add node','Primary','M','plus'),'D/Import profile'));return desktop('Nodes','Your nodes. Your protocols. One workspace.',b=>{const toolbar=between(add(row('Node toolbar',1120,40),input('Search by name, region or protocol…',400),add(row('Filters',null,null,10),tabs(['All nodes','Favorites'],0,210),btn('All protocols','Secondary','M','down'))));add(b,toolbar);const all=borderCard('Node inventory',1120,null,0,0);const widths=[36,290,178,170,112,116,170];add(all,listRow(['','NODE','REGION','PROTOCOL','LATENCY','STATUS',''],widths,1120,40,true));nodes.forEach((d,i)=>{const r=listRow([icon('star',14,d.fav?'Warning':'Muted'),add(row('Node',null,null,10),country(d.code,32),tx(d.name,13,'Text','Medium')),d.region,badge(d.p),tx(d.ping+(d.ping==='—'?'':' ms'),13,d.status==='Online'?'Primary':'Error', 'Regular',null,true),badge(d.status,d.status==='Online'?'Success':'Error',true),i===0?badge('Selected','Success'):attach(btn('Connect','Ghost','S'),'D/Dashboard')],widths,1120,62);if(i===0){fill(r,'PrimarySurface');r.name='Selected · Tokyo Sakura';}if(i)add(all,divider(1120));add(all,r);});const footer=between(add(row('Inventory footer',1120,48,0,16),small('8 nodes · 7 online · Updated 2 minutes ago'),add(row('Subscriptions',null,null,8),dot(),small('Personal workspace synced','Secondary'))));add(all,divider(1120),footer);add(b,all,between(add(row('Protocols',1120,null),small('SUPPORTED PROTOCOLS'),add(row('Protocol tags',null,null,6),...['Shadowsocks','VLESS','VMess','Trojan','Hysteria','TUIC','SOCKS5','HTTP'].map(p=>badge(p))))));},{actions});}
function profileTile(title,file,meta,selected,w=356){const c=borderCard('Profile · '+title,w,200,22,14,selected?'PrimarySurface':'Surface');if(selected)stroke(c,'Primary');add(c,between(add(row('Title',w-44,null),miniIcon('profile',selected?'Primary':'Secondary',36,selected?'PrimarySurface':'Raised'),badge(selected?'Active':'Available',selected?'Success':'Neutral'))),tx(title,18,'Text','Medium'),small(file,'Secondary'),small(meta,'Muted',w-44),between(add(row('Actions',w-44,null),add(row('Update',null,null,6),icon('refresh',12),small('Updated 2m ago')),attach(btn('Edit','Ghost','S'),'D/Profile editor'))));return c;}
function desktopProfiles(){const actions=add(row('Profile actions',null,null,10),attach(btn('New profile','Secondary','M','plus'),'D/Profile editor'),attach(btn('Import subscription','Primary','M','download'),'D/Import profile'));return desktop('Profiles','A home for every network configuration.',b=>{add(b,add(row('Profiles',1120,200,26),profileTile('Personal workspace','personal.yaml','8 nodes · 126 rules · Auto-update on',true),profileTile('Development','dev-routing.json','4 nodes · 32 rules · Manual updates',false),profileTile('Travel essentials','travel.yaml','3 nodes · 48 rules · Auto-update on',false)));const sub=borderCard('Subscriptions',1120,264,24,20);add(sub,sectionHeader('Subscriptions','Keep your configurations in sync.',btn('Refresh all','Secondary','S','refresh'),1072),listRow(['SUBSCRIPTION','SOURCE','LAST UPDATED','NEXT UPDATE',''],[230,362,186,180,100],1072,34,true),listRow([textColumn('Personal workspace','8 nodes',13,210),tx('https://example.com/sub/••••',12,'Secondary', 'Regular',null,true),'2 minutes ago',badge('In 5h 58m','Success'),sw(true)],[230,362,186,180,100],1072,64),divider(1072),listRow([textColumn('Travel essentials','3 nodes',13,210),tx('https://example.net/travel/••••',12,'Secondary', 'Regular',null,true),'Today, 08:00',badge('In 2h','Neutral'),sw(true)],[230,362,186,180,100],1072,64));add(b,sub);const code=borderCard('Configuration tools',1120,152,24,12);add(code,between(add(row('Code title',1072,null),textColumn('Built for your workflow','Edit YAML or JSON directly, with clear validation.',16,650),attach(btn('Open configuration editor','Secondary','M','terminal'),'D/Profile editor'))),add(row('Code snippet',1072,42,0,14,'Background'),tx('mode: rule    •    ipv6: true    •    log-level: info    •    dns: enabled',12,'Secondary', 'Regular',null,true)));add(b,code);},{actions});}
function desktopRules(){return desktop('Rules','Route intentionally. Keep the rest simple.',b=>{const modes=row('Routing modes',1120,132,16);[['Rule mode','Match traffic against your ordered rules.','shield',true],['Global mode','Route all traffic through the current node.','globe',false],['Direct mode','Connect directly without a proxy.','arrow',false]].forEach(([t,s,ic,a])=>{const c=borderCard(t,362,132,20,10,a?'PrimarySurface':'Surface');if(a)stroke(c,'Primary');add(c,between(add(row('Mode',322,null),add(row('Title',null,null,9),icon(ic,18,a?'Primary':'Secondary'),tx(t,15,'Text','Medium')),a?icon('check',16,'Primary'):dot('Stroke',12))),small(s,'Muted',322),badge(a?'Active':'Available',a?'Success':'Neutral'));add(modes,c);});const rules=borderCard('Rule list',1120,null,0,0);const toolbar=between(add(row('Rule filters',1120,72,14,24),tabs(['All rules','Domain rules','IP rules'],0,340),attach(btn('Add rule','Primary','M','plus'),'D/Rule editor')));add(rules,toolbar,listRow(['PRIORITY','TYPE','MATCH','ACTION','HITS',''],[94,168,426,190,134,60],1120,38,true));const data=[['01','DOMAIN-SUFFIX','github.com','Proxy','12.8k'],['02','DOMAIN-SUFFIX','developer.apple.com','Proxy','4.2k'],['03','DOMAIN','api.openai.com','Proxy','8.7k'],['04','IP-CIDR','192.168.0.0/16','Direct','2.1k'],['05','GEOIP','PRIVATE','Direct','942'],['06','DOMAIN-SUFFIX','ads.example.com','Reject','318'],['07','MATCH','All remaining traffic','Proxy','32.4k']];data.forEach((d,i)=>{if(i)add(rules,divider(1120));add(rules,listRow([tx(d[0],12,'Muted', 'Regular',null,true),badge(d[1]),tx(d[2],13,'Text', 'Regular',null,true),badge(d[3],d[3]==='Reject'?'Error':d[3]==='Proxy'?'Success':'Neutral'),d[4],icon('more',16)],[94,168,426,190,134,60],1120,56));});add(rules,divider(1120),add(row('Rule order note',1120,46,8,16),icon('rules',14),small('Rules run from top to bottom. The first matching rule wins.')));add(b,modes,rules);},{actions:add(row('Actions',null,null,10),btn('Import rules','Secondary','M','download'),attach(btn('Add rule','Primary','M','plus'),'D/Rule editor'))});}
function desktopConnections(){return desktop('Connections','See exactly where your traffic goes.',b=>{add(b,add(row('Connection metrics',1120,112,16),metric('Active','142','','Across 18 destinations','connections','Muted'),metric('Proxied','128','','90% of active connections','shield'),metric('Direct','14','','Local and private networks','arrow','Muted'),metric('Transferred','2.84','GB','This session','chart','Muted')));const c=borderCard('Live connections',1120,null,0,0);add(c,between(add(row('Connection filters',1120,70,14,24),input('Filter by host, process or rule…',360),add(row('Live updates',null,null,12),badge('LIVE','Success',true),btn('Pause','Secondary','S'),btn('Close all','Danger','S')))),listRow(['DESTINATION','PROCESS','RULE','ROUTE','DOWNLOAD','DURATION'],[322,184,164,142,160,116],1120,38,true));[['api.github.com:443','Code','DOMAIN-SUFFIX','Proxy','42.8 MB','04:32'],['registry.npmjs.org:443','Terminal','DOMAIN-SUFFIX','Proxy','168.2 MB','02:18'],['developer.apple.com:443','Safari','DOMAIN-SUFFIX','Proxy','12.4 MB','01:54'],['192.168.1.1:80','Browser','IP-CIDR','Direct','284 KB','00:41'],['docs.rs:443','Code','MATCH','Proxy','3.8 MB','00:26'],['api.openai.com:443','Terminal','DOMAIN','Proxy','1.2 MB','00:14'],['fonts.googleapis.com:443','Browser','MATCH','Proxy','486 KB','00:08']].forEach((d,i)=>{if(i)add(c,divider(1120));add(c,listRow([tx(d[0],12,'Text', 'Regular',null,true),d[1],badge(d[2]),badge(d[3],d[3]==='Proxy'?'Success':'Neutral'),d[4],tx(d[5],12,'Muted', 'Regular',null,true)],[322,184,164,142,160,116],1120,60));});add(c,divider(1120),between(add(row('Footer',1120,48,0,16),small('Showing 7 of 142 connections'),small('Refreshes every second','Secondary'))));add(b,c);},{actions:btn('Export snapshot','Secondary','M','download')});}
function desktopTraffic(){return desktop('Traffic','Understand your usage, without the noise.',b=>{add(b,add(row('Totals',1120,112,16),metric('Total traffic','8.42','GB','Today · ↑ 12%','chart'),metric('Downloaded','7.86','GB','93% of total','download','Muted'),metric('Uploaded','560','MB','7% of total','upload','Muted'),metric('Monthly total','126.4','GB','October 2026','clock','Muted')));const c=borderCard('Traffic over time',1120,306,24,20);add(c,between(add(row('Chart title',1072,null),textColumn('Traffic over time','14 October 2026 · Local time',16,520),tabs(['Today','Week','Month'],0,230))),add(row('Legend',1072,null,18),add(row('Down',null,null,7),dot(),small('Download','Secondary')),add(row('Up',null,null,7),dot('Chart2'),small('Upload','Secondary')),grow(space()),small('Peak 24.6 MB/s')),chart(1072,160,true,'traffic'),between(add(row('Axis',1072,null),small('00:00'),small('06:00'),small('12:00'),small('18:00'),small('24:00'))));const rank=borderCard('Usage by application',1120,204,24,14);add(rank,sectionHeader('Usage by application','The processes behind your traffic.',null,1072));[['Browser','4.28 GB',.68,'globe'],['Code','2.46 GB',.4,'terminal'],['Terminal','1.68 GB',.25,'terminal']].forEach(d=>{const r=row(d[0],1072,32,14);const bar=rad(frame('Usage bar',680,6,'HORIZONTAL','Raised'),3);const p=figma.createRectangle();p.resize(680*d[2],6);rad(p,3);fill(p,'Primary');add(bar,p);add(r,icon(d[3],16),tx(d[0],13,'Secondary','Regular',160),bar,tx(d[1],12,'Text', 'Regular',null,true));add(rank,r);});add(b,c,rank);},{actions:btn('Export CSV','Secondary','M','download')});}
function desktopLogs(){return desktop('Logs','A calm console for the details that matter.',b=>{add(b,between(add(row('Log toolbar',1120,40),input('Search logs…',430),add(row('Filters',null,null,10),tabs(['All','Info','Warn','Error'],0,300),btn('Clear','Ghost','M'),btn('Export','Secondary','M','download')))));const c=borderCard('Event stream',1120,548,0,0,'Background');add(c,between(add(row('Stream header',1120,54,0,18,'Surface'),add(row('Title',null,null,10),icon('terminal',16),tx('Core event stream',13,'Text','Medium')),add(row('Live',null,null,8),badge('LIVE','Success',true),small('Info level')))));const data=[['10:42:18.023','INFO','Tunnel established · Tokyo · Sakura'],['10:42:18.108','INFO','Rule engine loaded: 126 rules, 3 rule providers'],['10:42:18.246','INFO','DNS resolver ready · fake-ip enabled'],['10:42:19.504','INFO','[TCP] Code → api.github.com:443 · VLESS · 24 ms'],['10:42:20.142','INFO','[TCP] Terminal → registry.npmjs.org:443 · Proxy'],['10:42:22.811','WARN','London · Thames: latency test timed out after 5000 ms'],['10:42:23.054','INFO','Health check complete: 7 of 8 nodes online'],['10:42:24.687','INFO','[TCP] Browser → 192.168.1.1:80 · DIRECT'],['10:42:26.029','INFO','Subscription refresh scheduled in 5h 58m'],['10:42:27.361','INFO','[UDP] Browser → dns.example.com:443 · Proxy'],['10:42:29.158','INFO','Active connections: 142 · Current throughput: 12.8 MB/s']];data.forEach((d,i)=>{const r=row('Log '+(i+1),1120,41,14,18,i%2?'Surface':null);r.paddingTop=r.paddingBottom=0;add(r,tx(d[0],12,'Muted','Regular',120,true),badge(d[1],d[1]==='WARN'?'Warning':'Info'),tx(d[2],12,d[1]==='WARN'?'Warning':'Secondary','Regular',820,true));add(c,r);});add(b,c,between(add(row('Log footer',1120,null),small('11 events shown · Log retention: 7 days'),add(row('Follow',null,null,8),small('Follow latest','Secondary'),sw(true)))));},{actions:btn('Pause stream','Secondary','M','clock')});}
function settingRow(title,sub,control,w=746){return between(add(row('Setting · '+title,w,66,16),textColumn(title,sub,13,w-180),control));}
function desktopSettings(){return desktop('Settings','Make RainLink feel like your own.',b=>{const r=row('Settings layout',1120,652,24);const menu=borderCard('Settings navigation',220,652,12,6);['General','Appearance','Network','Core Engine','Updates'].forEach((s,i)=>{const item=rad(row(s,196,40,10,12,i===0?'PrimarySurface':null),9);add(item,icon(['settings','sun','globe','terminal','refresh'][i],16,i===0?'Primary':'Muted'),tx(s,13,i===0?'Primary':'Secondary','Medium'));if(i===1)attach(item,'D/Appearance');add(menu,item);});add(menu,grow(space()),small('Version 1.0.0 · Stable','Muted',180));const col=v('General settings',876,18);const c=borderCard('General',876,332,24,4);add(c,tx('General',18,'Text','Medium'),small('Quiet defaults. Thoughtful controls.'),settingRow('Launch at login','Keep RainLink available when you start your device.',sw(true),828),divider(828),settingRow('Connect automatically','Restore the last selected node on launch.',sw(true),828),divider(828),settingRow('Show menu bar / tray icon','Connection controls, always within reach.',sw(true),828));const network=borderCard('Network',876,182,24,4);add(network,tx('Network',18,'Text','Medium'),settingRow('System proxy','Route compatible apps through RainLink.',sw(true),828),divider(828),settingRow('TUN mode','Route device traffic through the core engine.',sw(false),828));const core=borderCard('Core engine & updates',876,102,22,10);add(core,between(add(row('Core',832,null),add(row('Version',null,null,12),miniIcon('terminal','Primary',34),textColumn('sing-box 1.12.0','Core engine is up to date.',13,440)),badge('Latest','Success'),btn('Check updates','Secondary','S','refresh'))));add(col,c,network,core);add(r,menu,col);add(b,r);},{actions:btn('Reset defaults','Ghost','M')});}
function desktopEditor(){return desktop('Profile editor','Personal workspace / personal.yaml',b=>{const c=borderCard('YAML editor',1120,592,0,0,'Background');const bar=between(add(row('Editor tabs',1120,52,0,18,'Surface'),tabs(['personal.yaml','dev-routing.json'],0,340),add(row('Editor controls',null,null,12),badge('YAML','Neutral'),badge('Valid configuration','Success',true))));add(c,bar);const code=[['# RainLink · Personal workspace','Muted'],['mode: rule','Primary'],['log-level: info','Secondary'],['ipv6: true','Secondary'],['','Muted'],['dns:','Primary'],['  enable: true','Secondary'],['  enhanced-mode: fake-ip','Secondary'],['  nameserver: [https://dns.example.com/dns-query]','Secondary'],['','Muted'],['proxies:','Primary'],['  - name: "Tokyo · Sakura"','Text'],['    type: vless','Secondary'],['    server: tokyo.example.com','Secondary'],['    port: 443','Secondary'],['    tls: true','Primary'],['','Muted'],['rules:','Primary'],['  - DOMAIN-SUFFIX,github.com,PROXY','Secondary'],['  - IP-CIDR,192.168.0.0/16,DIRECT','Secondary'],['  - MATCH,PROXY','Secondary']];code.forEach((d,i)=>add(c,add(row('Line '+(i+1),1120,23,18,20),tx(String(i+1).padStart(2,'0'),12,'Muted','Regular',26,true),tx(d[0]||' ',12,d[1],'Regular',1000,true))));add(c,grow(space()),between(add(row('Editor status',1120,42,0,18,'Surface'),small('Ln 21, Col 15 · UTF-8 · 2 spaces'),small('Validated just now','Primary'))));add(b,c,between(add(row('Footer actions',1120,48),small('Changes apply after you save the profile.'),add(row('Actions',null,null,10),attach(btn('Cancel','Ghost'),'D/Profiles'),attach(btn('Save & apply','Primary','M','check'),'D/Profiles')))));},{active:'Profiles',actions:btn('Format document','Secondary','M','rules')});}
function desktopQuickSwitch(){const n=desktop('Quick switch','Find your next link in a keystroke.',b=>{const c=borderCard('Command palette',760,592,28,16);c.effects=[{type:'DROP_SHADOW',color:{r:0,g:0,b:0,a:.35},offset:{x:0,y:20},radius:48,spread:0,visible:true,blendMode:'NORMAL'}];add(c,between(add(row('Title',704,null),tx('Switch node',20,'Text','Semi Bold'),attach(btn('Esc','Ghost','S'),'D/Dashboard'))),input('Search nodes, regions or protocols…',704,'search',true),small('RECENT & FAVORITES'));nodes.slice(0,4).forEach((d,i)=>add(c,attach(nodeCard(d,i===0,704),'D/Dashboard')));add(c,divider(704),between(add(row('Shortcuts',704,null),small('↑ ↓  Navigate     ↵  Connect'),small('⌘ K to open from anywhere'))));const wrap=center(row('Palette alignment',1120,630));add(wrap,c);add(b,wrap);},{active:'Dashboard',actions:attach(btn('Back to dashboard','Ghost','M','arrow'),'D/Dashboard')});return n;}
function desktopImport(){return desktop('Import profile','Bring your own configuration into RainLink.',b=>{const r=row('Import layout',1120,560,24);const c=borderCard('Import subscription form',630,540,28,20);add(c,tx('Add a subscription',22,'Text','Semi Bold'),small('Paste a URL or import a local YAML / JSON file.','Muted',574),tabs(['Subscription URL','Local file','Paste config'],0,574),field('Subscription URL','https://example.com/subscription',574,'link','Your subscription stays in your workspace.'),field('Display name','Personal workspace',574,null),between(add(row('Auto-update',574,50),textColumn('Automatic updates','Refresh every 6 hours.',13,390),sw(true))),divider(574),between(add(row('Import actions',574,40),attach(btn('Cancel','Ghost'),'D/Profiles'),attach(btn('Import profile','Primary','M','download'),'D/Profiles'))));const info=borderCard('Import guidance',466,304,26,22);add(info,miniIcon('shield','Primary',44,'PrimarySurface'),tx('Designed around ownership.',20,'Text','Semi Bold'),small('RainLink connects to the nodes and configurations you provide. Choose trusted sources and keep your subscription link private.','Secondary',414),add(row('Formats',414,null,8),badge('YAML'),badge('JSON'),badge('Subscription URL')),small('Existing profiles are kept when you import.','Muted',414));add(r,c,info);add(b,r);},{active:'Profiles',actions:attach(btn('Back to profiles','Ghost','M','arrow'),'D/Profiles')});}
function desktopRuleEditor(){return desktop('Rule editor','Add a precise rule to your active profile.',b=>{const c=borderCard('Domain rule form',740,548,28,24);add(c,tx('New routing rule',22,'Text','Semi Bold'),tabs(['Domain rule','IP rule'],0,684),field('Match type','DOMAIN-SUFFIX',684,'down'),field('Value','example.com',684,null,'Matches example.com and its subdomains.'),field('Route action','Proxy · Tokyo · Sakura',684,'down'),between(add(row('Rule order',684,null),textColumn('Place before catch-all','This rule will run before the MATCH rule.',13,550),sw(true))),between(add(row('Actions',684,40),attach(btn('Cancel','Ghost'),'D/Rules'),attach(btn('Add rule','Primary','M','plus'),'D/Rules'))));add(b,c);},{active:'Rules',actions:attach(btn('Back to rules','Ghost','M','arrow'),'D/Rules')});}
function desktopAppearance(){return desktop('Appearance','A workspace that adapts to your day.',b=>{const r=row('Theme previews',1120,238,24);for(const light of [false,true]){const c=borderCard(light?'Light theme':'Dark theme',548,238,24,16);c.setExplicitVariableModeForCollection(collection,light?lightMode:darkMode);add(c,between(add(row('Theme title',500,null),add(row('Name',null,null,10),icon(light?'sun':'moon',18,'Primary'),tx(light?'Light':'Dark',16,'Text','Medium')),badge(light?'Preview':'Active',light?'Neutral':'Success'))));const mock=rad(frame('Theme preview',500,110,'HORIZONTAL','Background',12,12),12);stroke(mock);add(mock,rad(frame('Mini sidebar',66,86,'VERTICAL','Raised',8,8),8),add(v('Mini content',398,10),add(row('Preview stats',398,32,8),rad(frame('Metric',130,32,'HORIZONTAL','Surface'),6),rad(frame('Metric',130,32,'HORIZONTAL','Surface'),6)),chart(370,40)));add(c,mock,attach(btn(light?'View light dashboard':'Keep dark theme',light?'Secondary':'Primary','S'),light?'D/Dashboard light':'D/Dashboard'));if(light)applyLight(c);add(r,c);}const opts=borderCard('Appearance controls',1120,280,24,8);add(opts,settingRow('Follow system appearance','Match the theme selected in your operating system.',sw(false),1072),divider(1072),settingRow('Reduce motion','Use subtle fades in place of larger transitions.',sw(false),1072),divider(1072),settingRow('Compact density','Fit more information into lists and tables.',sw(false),1072));add(b,r,opts);},{active:'Settings',actions:attach(btn('Back to settings','Ghost','M','arrow'),'D/Settings')});}
function statusBar(){const r=between(row('Status bar / safe area',393,54,0,24));const time=tx('9:41',14,'Text','Semi Bold');const island=rad(frame('Dynamic Island',116,30,'HORIZONTAL','#000000'),20);add(r,time,island,add(row('System indicators',null,null,7),icon('wifi',16,'Text'),tx('▰',20,'Text')));return r;}
function mobileNav(active){const n=instance('Mobile / Bottom navigation');for(const name of ['Home','Nodes','Profiles','Traffic','Settings']){const tab=n.findOne(x=>x.name==='Tab · '+name);if(!tab)continue;const it=tab.findOne(x=>x.type==='INSTANCE');if(it)tint(it,name===active?'Primary':'Muted');const label=tab.findOne(x=>x.type==='TEXT');if(label)fill(label,name===active?'Primary':'Muted');attach(tab,'M/'+name);}return n;}
function mobile(name,title,sub,active,build,options={}){const n=frame('Mobile / '+name,393,852,'VERTICAL','Background',0);n.clipsContent=true;n.setExplicitVariableModeForCollection(collection,options.light?lightMode:darkMode);mobilePage.appendChild(n);const h=between(row('Page header',393,68,12,20));h.paddingTop=h.paddingBottom=8;const titleNode=textColumn(title,sub,24,278);add(h,titleNode,options.action||attach(btn('','Ghost','M','bell'),'M/Settings'));const viewport=frame('Scrollable content',393,650,'VERTICAL',null,0);viewport.layoutGrow=1;viewport.clipsContent=true;viewport.overflowDirection='VERTICAL';const content=v('Content',393,16,20);content.paddingTop=12;content.paddingBottom=24;add(viewport,content);add(n,statusBar(),h,viewport,mobileNav(active));build(content,n);if(options.light)applyLight(n);registry.mobile[name]=n;return n;}
function mobileHeading(s,action=null){return between(add(row(s+' title',353,null),tx(s,15,'Text','Medium'),action));}
function mobileHero(online=true,error=false){const c=center(borderCard('Connection control',353,262,20,8,online?'PrimarySurface':'Surface'));if(online)stroke(c,'Primary',.5);const ring=center(row('Connection ring',132,132));const e=figma.createEllipse();e.resize(128,128);fill(e,online?'PrimarySurface':'Raised');stroke(e,online?'Primary':error?'Error':'Stroke',1.5);add(ring,e);const button=center(rad(row('Connect / power',94,94,0,0,online?'Primary':'Raised'),48));stroke(button,online?'Primary':'Stroke');add(button,icon('power',36,online?'OnPrimary':error?'Error':'Primary'));add(ring,button);button.layoutPositioning='ABSOLUTE';button.x=19;button.y=19;attach(ring,error?'M/Home':online?'M/Disconnected':'M/Home');add(c,ring,tx(error?'Connection interrupted':online?'Connected':'Ready to connect',22,'Text','Semi Bold'),small(error?'Your last node did not respond.':online?'Rule mode · Connected for 1h 42m':'Tap to start your network.','Secondary'),add(row('Connection note',null,null,6),dot(error?'Error':online?'Success':'Muted'),small(error?'Try a different node':online?'Tap to disconnect':'Your configuration is ready',error?'Error':'Muted')));return c;}
function mobileMetric(title,value,unit,ic,color,w=169){const c=borderCard(title,w,94,16,8);add(c,add(row('Label',w-32,null,6),icon(ic,14,color),small(title,'Secondary')),add(row('Value',w-32,null,5),tx(value,24,'Text','Semi Bold'),tx(unit,11,'Muted')));return c;}
function mobileHome(online=true,light=false,error=false){return mobile(error?'Connection error':online?(light?'Home light':'Home'):'Disconnected','RainLink','Your network, in flow.','Home',b=>{add(b,mobileHero(online,error),mobileHeading('Current node',attach(btn('Switch','Ghost','S','connections'),'M/Quick switch')),attach(nodeCard(nodes[0],true),'M/Node details'),add(row('Network metrics',353,94,15),mobileMetric('Latency',online?'24':'—','ms','speed','Primary'),mobileMetric('Download',online?'12.8':'0','MB/s','download','Primary')));const daily=borderCard('Today’s traffic',353,108,16,10);add(daily,between(add(row('Daily header',321,null),tx('Today’s traffic',14,'Text','Medium'),attach(btn('View','Ghost','S','arrow'),'M/Traffic'))),between(add(row('Daily totals',321,null),tx('8.42 GB',24,'Text','Semi Bold'),small('↓ 7.86 GB    ↑ 560 MB','Secondary'))));add(b,daily);},{light});}
function mobileNodes(){return mobile('Nodes','Nodes','8 nodes · 7 online','Nodes',b=>{add(b,input('Search nodes or regions…',353),between(add(row('Filters',353,38),tabs(['All nodes','Favorites'],0,238),attach(btn('Test','Secondary','S','speed'),'M/Nodes tested'))),mobileHeading('Personal workspace',badge('SYNCED','Success')));nodes.forEach((d,i)=>add(b,attach(nodeCard(d,i===0),'M/Node details')));},{action:attach(btn('','Primary','M','plus'),'M/Import profile')});}
function mobileProfiles(){return mobile('Profiles','Profiles','Your configurations, together.','Profiles',b=>{const data=[['Personal workspace','8 nodes · 126 rules',true,'YAML'],['Development','4 nodes · 32 rules',false,'JSON'],['Travel essentials','3 nodes · 48 rules',false,'YAML']];data.forEach(d=>{const c=borderCard('Profile · '+d[0],353,150,18,12,d[2]?'PrimarySurface':'Surface');if(d[2])stroke(c,'Primary');add(c,between(add(row('Title',317,null),add(row('Name',null,null,10),miniIcon('profile',d[2]?'Primary':'Secondary',32),tx(d[0],15,'Text','Medium')),badge(d[3]))),small(d[1],'Secondary'),between(add(row('Update',317,null),add(row('Auto update',null,null,6),icon('refresh',12),small(d[2]?'Auto-update · 6h':'Updated today')),badge(d[2]?'Active':'Available',d[2]?'Success':'Neutral'))));add(b,c);});add(b,mobileHeading('Add a configuration'),add(row('Import shortcuts',353,90,15),attach(importShortcut('URL import','link',169),'M/Import profile'),attach(importShortcut('Scan QR code','qr',169),'M/QR import')),small('YAML, JSON and subscription URLs are supported.','Muted',353));},{action:attach(btn('','Primary','M','plus'),'M/Import profile')});}
function importShortcut(s,ic,w=169){const c=center(borderCard(s,w,90,16,10));add(c,icon(ic,22,'Primary'),tx(s,12,'Text','Medium'));return c;}
function mobileTraffic(){return mobile('Traffic','Traffic','A little perspective on your usage.','Traffic',b=>{add(b,tabs(['Today','This month'],0,353));const total=borderCard('Traffic total',353,136,20,8,'PrimarySurface');add(total,small('TOTAL TRAFFIC','Primary'),tx('8.42 GB',36,'Text','Semi Bold'),between(add(row('Breakdown',313,null),small('↓ 7.86 GB downloaded','Secondary'),small('↑ 560 MB uploaded','Secondary'))));const curve=borderCard('Traffic chart',353,234,18,14);add(curve,between(add(row('Chart title',317,null),tx('Traffic over time',14,'Text','Medium'),badge('LIVE','Success',true))),chart(317,112,true),between(add(row('Axis',317,null),small('00:00'),small('06:00'),small('12:00'),small('18:00'))),add(row('Legend',317,null,18),add(row('Down',null,null,6),dot(),small('Download','Secondary')),add(row('Up',null,null,6),dot('Chart2'),small('Upload','Secondary'))));const rank=borderCard('Usage ranking',353,null,18,14);add(rank,tx('Usage ranking',14,'Text','Medium'));[['Browser','4.28 GB','globe'],['Code','2.46 GB','terminal'],['Terminal','1.68 GB','terminal']].forEach((d,i)=>{add(rank,between(add(row(d[0],317,30,10),small(String(i+1)),icon(d[2],16),grow(tx(d[0],13)),tx(d[1],12,'Secondary','Regular',null,true))));if(i<2)add(rank,divider(317));});add(b,total,curve,rank);});}
function mobileSetting(title,ic,right,sub=null,target=null){const r=row(title,317,58,12);add(r,miniIcon(ic,'Secondary',30),grow(textColumn(title,sub,13,190)),typeof right==='string'?tx(right,12,'Muted'):right);if(target)attach(r,target);return r;}
function mobileSettings(){return mobile('Settings','Settings','Small details. A better daily flow.','Settings',b=>{const app=borderCard('About RainLink',353,92,18,10);add(app,add(row('Brand',317,null,14),instance('Brand / Mark'),grow(textColumn('RainLink','Version 1.0.0 · Stable',17,215)),badge('Latest','Success')));const pref=borderCard('Preferences',353,null,18,0);add(pref,small('PREFERENCES'),mobileSetting('Notifications','bell',sw(true)),divider(317),mobileSetting('Auto-connect','power',sw(true)),divider(317),mobileSetting('Theme','moon',icon('chevron',14),'Dark','M/Home light'));const network=borderCard('Network preferences',353,null,18,0);add(network,small('NETWORK'),mobileSetting('DNS','globe',icon('chevron',14),'Encrypted · Automatic','M/DNS'),divider(317),mobileSetting('Routing mode','shield',icon('chevron',14),'Rule mode','M/Node details'));const about=borderCard('Support',353,null,18,0);add(about,small('RAINLINK'),mobileSetting('About & licenses','rain',icon('chevron',14),'Open source, thoughtfully built.'),divider(317),mobileSetting('Check for updates','refresh',badge('Up to date','Success')));add(b,app,pref,network,about,center(add(row('Footer',353,30),small('Made for your network.'))));});}
function mobileImport(){return mobile('Import profile','Add a profile','Bring your own configuration.','Profiles',b=>{add(b,tabs(['URL','File','Paste'],0,353),field('Subscription URL','https://example.com/subscription',353,'link','Use a trusted source for your nodes.'),field('Display name','Personal workspace',353),borderCard('Update preference',353,null,18,12));const c=b.children[b.children.length-1];add(c,between(add(row('Auto-update',317,null),textColumn('Automatic updates','Refresh every 6 hours.',13,240),sw(true))));const note=borderCard('Privacy note',353,114,18,10,'PrimarySurface');add(note,add(row('Title',317,null,8),icon('shield',16,'Primary'),tx('Your link stays yours.',13,'Primary','Medium')),small('Subscriptions are stored on your device. RainLink does not provide or sell nodes.','Secondary',317));add(b,note,attach(fullButton('Import profile','Primary',353,'download'),'M/Import success'),attach(fullButton('Scan a QR code','Secondary',353,'qr'),'M/QR import'));},{action:attach(btn('','Ghost','M','close'),'M/Profiles')});}
function mobileSuccess(){return mobile('Import success','Profile added','Everything is ready for your next link.','Profiles',b=>{const c=center(borderCard('Success',353,256,24,18));add(c,miniIcon('check','Primary',72,'PrimarySurface'),tx('You’re all set.',24,'Text','Semi Bold'),small('Personal workspace was imported successfully.','Secondary',280),add(row('Imported contents',null,null,8),badge('8 nodes','Success'),badge('126 rules','Neutral')));add(b,c,attach(profileTile('Personal workspace','personal.yaml','Auto-update enabled · Every 6 hours',true,353),'M/Profiles'),attach(fullButton('Connect now','Primary',353,'power'),'M/Home'),attach(fullButton('Back to profiles','Secondary',353),'M/Profiles'));},{action:attach(btn('','Ghost','M','close'),'M/Profiles')});}
function mobileSwitch(){return mobile('Quick switch','Switch node','Choose a link for the moment.','Home',b=>{add(b,input('Search nodes…',353),mobileHeading('Recommended',badge('LOW LATENCY','Success')));nodes.slice(0,4).forEach((d,i)=>add(b,attach(nodeCard(d,i===0),'M/Home')));const info=borderCard('Smart choice',353,96,18,10,'PrimarySurface');add(info,add(row('Title',317,null,8),icon('speed',16,'Primary'),tx('Stay in flow.',14,'Text','Medium')),small('A quick latency test helps you choose the best node for your current network.','Secondary',317));add(b,info,attach(fullButton('Test all nodes','Secondary',353,'speed'),'M/Nodes tested'));},{action:attach(btn('','Ghost','M','close'),'M/Home')});}
function mobileDetails(){return mobile('Node details','Node details','Personal workspace','Nodes',b=>{const c=borderCard('Node overview',353,188,22,14,'PrimarySurface');add(c,between(add(row('Node',309,null),country('JP',44),icon('star',20,'Warning'))),tx('Tokyo · Sakura',24,'Text','Semi Bold'),add(row('Tags',309,null,8),badge('VLESS','Success'),badge('Japan · Tokyo'),badge('Online','Success',true)));const m=row('Node metrics',353,94,15);add(m,mobileMetric('Latency','24','ms','speed','Primary'),mobileMetric('Packet loss','0','%','shield','Primary'));const tech=borderCard('Connection details',353,null,18,8);[['Protocol','VLESS + TLS'],['Transport','WebSocket'],['Server','tokyo.example.com'],['Port','443'],['Last tested','Just now']].forEach((d,i)=>{add(tech,between(add(row(d[0],317,32),small(d[0],'Muted'),tx(d[1],12,'Secondary', 'Regular',null,d[0]==='Server'))));if(i<4)add(tech,divider(317));});add(b,c,m,tech,attach(fullButton('Use this node','Primary',353,'check'),'M/Home'),attach(fullButton('Test latency','Secondary',353,'speed'),'M/Nodes tested'));},{action:attach(btn('','Ghost','M','close'),'M/Nodes')});}
function mobileDNS(){return mobile('DNS','DNS','Resolve clearly. Connect confidently.','Settings',b=>{const modes=borderCard('DNS mode',353,null,18,16);add(modes,tx('Resolver mode',16,'Text','Medium'),between(add(row('Automatic',317,null),textColumn('Automatic','Use the active profile’s resolvers.',13,252),icon('check',18,'Primary'))),divider(317),between(add(row('Custom',317,null),textColumn('Custom resolver','Set your preferred DNS endpoints.',13,252),dot('Stroke',16))));add(b,modes,field('Primary resolver','https://dns.example.com/dns-query',353,'globe'),field('Fallback resolver','https://backup.example.com/dns-query',353,'globe'),borderCard('DNS behavior',353,null,18,4));const c=b.children[b.children.length-1];add(c,between(add(row('Fake IP',317,48),textColumn('Fake IP','Improve routing consistency.',13,260),sw(true))),divider(317),between(add(row('IPv6',317,48),textColumn('IPv6 resolution','Resolve IPv6 addresses.',13,260),sw(true))));add(b,attach(fullButton('Save settings','Primary',353,'check'),'M/Settings'));},{action:attach(btn('','Ghost','M','close'),'M/Settings')});}
function mobileQR(){return mobile('QR import','Scan a QR code','Import your own profile or node.','Profiles',b=>{const scanner=center(borderCard('Camera scanner',353,342,24,16,'Raised'));const view=center(rad(frame('Scan area',242,242,'VERTICAL','Background'),20));stroke(view,'Primary',2);add(view,icon('qr',88,'Muted'));const line=figma.createRectangle();line.resize(204,2);fill(line,'Primary');add(view,line);line.layoutPositioning='ABSOLUTE';line.x=19;line.y=120;add(scanner,view,small('Align the code inside the frame.','Secondary'));add(b,scanner,small('RainLink requests camera access only when you scan. You can also import a link or a local file.','Muted',353),attach(fullButton('Demo: scan a profile','Primary',353,'qr'),'M/Import success'),attach(fullButton('Import a URL instead','Secondary',353,'link'),'M/Import profile'));},{action:attach(btn('','Ghost','M','close'),'M/Profiles')});}
function arrangeScreens(){let i=0;for(const key of Object.keys(registry.desktop)){const n=registry.desktop[key];n.x=(i%3)*1540;n.y=150+Math.floor(i/3)*1020;n.setPluginData('rainlink','desktop/'+key);n.exportSettings=[{format:'PNG',constraint:{type:'SCALE',value:1}}];i++;}const title=add(v('Desktop collection intro',1300,12),add(row('Brand line',1300,null,16),instance('Brand / Mark'),tx('RainLink / Desktop',40,'Text','Semi Bold')),caption('1440 × 900 · Windows / macOS / Linux · Shared components and semantic color modes',1300));desktopPage.appendChild(title);title.x=0;title.y=-60;
 i=0;for(const key of Object.keys(registry.mobile)){const n=registry.mobile[key];n.x=(i%5)*473;n.y=150+Math.floor(i/5)*980;n.setPluginData('rainlink','mobile/'+key);n.exportSettings=[{format:'PNG',constraint:{type:'SCALE',value:2}}];i++;}const mt=add(v('Mobile collection intro',1200,12),add(row('Brand line',1200,null,16),instance('Brand / Mark'),tx('RainLink / Mobile',40,'Text','Semi Bold')),caption('393 × 852 · iPhone 15 Pro · iOS / Android · Scrollable content with fixed navigation',1200));mobilePage.appendChild(mt);mt.x=0;mt.y=-60;
}
function designSystem(){const root=borderCard('Design System / Foundations',1500,1450,48,32,'Background');dsPage.appendChild(root);root.x=0;root.y=0;root.setExplicitVariableModeForCollection(collection,darkMode);const brand=between(add(row('Design system header',1404,null),add(row('Identity',null,null,18),instance('Brand / Mark'),tx('RainLink',40,'Text','Semi Bold')),badge('DESIGN SYSTEM · 1.0','Success')));add(root,brand,tx('Clarity for every connection.',28,'Text','Medium'),tx('A quiet, precise interface for people who care about their network. Deep ink surfaces, soft mint signals and a shared language from desktop to pocket.',16,'Secondary','Regular',1000));const principle=row('Principles',1404,100,24);[['01 / Quiet','Color communicates state, not decoration.'],['02 / Precise','Readable metrics. Explicit routing.'],['03 / Connected','One component language on every screen.']].forEach(d=>add(principle,add(borderCard(d[0],452,100,20,8),tx(d[0],14,'Primary','Medium'),small(d[1],'Secondary',412))));add(root,principle,divider(1404),tx('Semantic color tokens',22,'Text','Semi Bold'));
 const modes=row('Dark and light palette',1404,null,24);for(const light of [false,true]){const panel=borderCard(light?'Light extension':'Dark foundation',690,null,22,18);panel.setExplicitVariableModeForCollection(collection,light?lightMode:darkMode);add(panel,tx(light?'Light extension':'Dark foundation',16,'Text','Medium'));const keys=['Background','Surface','Primary','Success','Warning','Error'];for(let i=0;i<keys.length;i+=3){const r=row('Swatches',646,118,14);keys.slice(i,i+3).forEach(k=>{const swatch=v(k,206,7);const block=rad(frame('Token / '+k,206,62,'HORIZONTAL',k),9);stroke(block);add(swatch,block,tx(k,12,'Text','Medium'),tx(C[k][light?1:0],11,'Muted','Regular',null,true));add(r,swatch);});add(panel,r);}if(light)applyLight(panel);add(modes,panel);}add(root,modes,divider(1404));const specs=row('Typography and rhythm',1404,320,24);const type=borderCard('Typography',690,320,24,12);add(type,tx('Typography / Inter',20,'Text','Semi Bold'));[['Display','40 / 58','RainLink',40],['Heading','28 / 41','Your network, in flow.',28],['Title','20 / 29','Tokyo · Sakura',20],['Body','14 / 20','A clear view of your network.',14],['Caption','12 / 17','Small details. Clear signals.',12]].forEach(d=>add(type,between(add(row(d[0],642,null),tx(d[2],d[3],'Text',d[3]>=20?'Semi Bold':'Regular'),small(d[0]+' · '+d[1])))));const rhythm=borderCard('Spacing and layout',690,320,24,16);add(rhythm,tx('Spacing / 4 px base',20,'Text','Semi Bold'),small('4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64','Secondary',642));const bars=row('Spacing samples',642,68,24);[8,16,24,32,48,64].forEach(s=>{const col=v('Space '+s,68,8);const b=rad(frame('Size '+s,68,s,'HORIZONTAL','PrimarySurface'),4);add(col,b,small(String(s),'Primary'));add(bars,col);});add(rhythm,bars,small('Radii / 8 controls · 12 rows · 16 cards · 24 overlays','Secondary',642),small('Desktop / 248 sidebar · 36 content margin · 24 columns','Muted',642),small('Mobile / 20 side margins · 44 minimum touch targets','Muted',642));add(specs,type,rhythm);add(root,specs,divider(1404));const behavior=row('Interaction and accessibility',1404,176,24);const motion=borderCard('Motion',690,176,24,12);add(motion,tx('Motion / gentle, deliberate',18,'Text','Medium'),small('Navigation 180 ms ease out · Node switch 220 ms · Sheet 240 ms','Secondary',642),small('Use Smart Animate for state changes and a short dissolve for page navigation. Reduced motion uses 100 ms fades.','Muted',642));const access=borderCard('Accessibility',690,176,24,12);add(access,tx('Clear beyond color',18,'Text','Medium'),small('Pair every status color with a label or icon.','Secondary',642),small('Visible focus rings · readable 12 px captions · 44 px mobile targets · preserved safe areas · keyboard command palette','Muted',642));add(behavior,motion,access);add(root,behavior,small('All values are native Figma variables or editable components. Illustrative network data; no real subscription or account details.','Muted',1404));return root;}
function flowMap(){const root=borderCard('Prototype Flow / Interaction map',1500,null,48,28,'Background');dsPage.appendChild(root);root.x=0;root.y=libraryY;add(root,heading('Prototype Flow'),tx('Two platforms. One familiar rhythm.',20,'Secondary','Medium'),caption('Clickable flows are connected on the Desktop and Mobile pages. Start with the named flows in Present mode.',1404));const flows=[['Desktop / Connect & switch',['Disconnected','Dashboard','Quick switch','Nodes','Dashboard'],'Connect → inspect the network → switch node → review inventory.'],['Desktop / Import & configure',['Profiles','Import profile','Profiles','Profile editor','Rules'],'Import a trusted URL → edit YAML / JSON → refine routing.'],['Mobile / Your daily flow',['Disconnected','Home','Quick switch','Node details','Home'],'Tap to connect → select a node → inspect protocol and latency.'],['Mobile / Bring your config',['Profiles','Import profile','Import success','Home','Traffic'],'Import by URL → receive clear confirmation → connect and inspect usage.']];
 flows.forEach((d,fi)=>{const c=borderCard(d[0],1404,192,24,20);add(c,between(add(row('Flow title',1356,null),tx(d[0],16,'Text','Medium'),badge('ON CLICK · 180 MS','Success'))));const r=row('Steps',1356,58,16);d[1].forEach((s,i)=>{const box=center(rad(row('Step '+s,225,56,8,12,i===0?'PrimarySurface':'Raised'),10));stroke(box,i===0?'Primary':'Stroke');add(box,tx(String(i+1).padStart(2,'0'),11,'Primary','Medium'),tx(s,12,'Text','Medium'));add(r,box);if(i<d[1].length-1)add(r,icon('arrow',18,'Muted'));});add(c,r,small(d[2],'Secondary'));add(root,c);});
 const states=row('State behavior',1404,188,24);[['Connection','Ready → Connected → Disconnected → Retry','Large mobile connection control and persistent desktop status share the same vocabulary.'],['Node testing','Online · Low latency · Timeout','The tested states surface feedback and preserve the selected node.'],['Import','Input → Validated → Added','A named success state makes the outcome clear before connecting.']].forEach(d=>add(states,add(borderCard(d[0],452,188,22,14),tx(d[0],18,'Text','Medium'),small(d[1],'Primary',408),small(d[2],'Muted',408))));add(root,states,small('Prototype data is illustrative. Camera scans and latency tests are represented by explicit demo states.','Muted',1404));return root;}
async function linkPrototype(){for(const p of pending){lastStatus='Linking '+p.node.name+' to '+p.target;const parts=p.target.split('/');const dest=parts[0]==='D'?registry.desktop[parts.slice(1).join('/')]:registry.mobile[parts.slice(1).join('/')];if(!dest){registry.warnings.push('Missing prototype destination: '+p.target);continue;}let source=p.node;while(source.parent&&source.parent.type!=='PAGE')source=source.parent;if(source.id===dest.id)continue;await p.node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:dest.id,navigation:p.kind,transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false}]}]);registry.links.push({from:p.node.id,to:dest.id,label:p.node.name});}
 for(const name of ['Nodes tested','Dashboard light']){const screen=registry.desktop[name];for(const node of screen.findAll(n=>n.name.startsWith('Navigate · '))){const dest=registry.desktop[node.name.replace('Navigate · ','')];if(dest)await node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:dest.id,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false}]}]);}for(const node of screen.findAll(n=>n.name==='Dropdown / Node'||n.name==='Button · Switch node'||n.name==='Button · Quick switch'))await node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:registry.desktop['Quick switch'].id,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false}]}]);}
 for(const node of registry.mobile['Nodes tested'].findAll(n=>n.name.startsWith('Tab · '))){const dest=registry.mobile[node.name.replace('Tab · ','')];if(dest)await node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:dest.id,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false}]}]);}
 desktopPage.flowStartingPoints=[{nodeId:registry.desktop.Disconnected.id,name:'Desktop / Connect & switch'},{nodeId:registry.desktop.Profiles.id,name:'Desktop / Import & configure'}];mobilePage.flowStartingPoints=[{nodeId:registry.mobile.Disconnected.id,name:'Mobile / Connect & switch'},{nodeId:registry.mobile.Profiles.id,name:'Mobile / Import a profile'}];
}
function inspectLayout(){const problems=[];for(const page of [desktopPage,mobilePage]){for(const screen of page.children.filter(n=>n.type==='FRAME'&&n.getPluginData('rainlink'))){if(screen.layoutMode==='NONE')problems.push(screen.name+': no Auto Layout');for(const n of screen.findAll(n=>n.type==='TEXT')){if(n.visible && n.characters && n.width<3)problems.push(n.name+': narrow text');}if(screen.width!== (page===desktopPage?1440:393)||screen.height!==(page===desktopPage?900:852))problems.push(screen.name+': wrong viewport');}}
 registry.counts={desktop:Object.keys(registry.desktop).length,mobile:Object.keys(registry.mobile).length,components:dsPage.findAll(n=>n.type==='COMPONENT').length,instances:desktopPage.findAll(n=>n.type==='INSTANCE').length+mobilePage.findAll(n=>n.type==='INSTANCE').length,colorTokens:Object.keys(vars).length,prototypeLinks:registry.links.length};registry.warnings.push(...problems);}
async function progress(s){lastStatus=s;figma.ui.postMessage({status:s});await new Promise(r=>setTimeout(r,20));}
async function main(){
 figma.showUI('<html><body style="margin:0;padding:26px;background:#10181e;color:#eff5f4;font:12px Inter,Arial,sans-serif"><strong style="font-size:20px;color:#86e5c3">RainLink Design Studio</strong><p id="s" style="color:#a8bac5;line-height:1.6">Building your workspace…</p><script>onmessage=e=>{document.getElementById("s").textContent=e.data.pluginMessage.status}</script></body></html>',{width:380,height:150});
 await figma.loadAllPagesAsync();
 // Only replace pages produced by this generator; preserve unrelated user work.
 const existing=figma.root.children.filter(p=>p.getPluginData('rainlink-page')==='v1');
 if(existing.length){for(const p of existing){p.children.slice().forEach(n=>n.remove());}}
 desktopPage=existing.find(p=>p.getPluginData('rainlink-role')==='desktop')||figma.root.children.find(p=>p.name==='Page 1'&&p.children.length===0)||figma.createPage();desktopPage.name='01 · Desktop';
 mobilePage=existing.find(p=>p.getPluginData('rainlink-role')==='mobile')||figma.createPage();mobilePage.name='02 · Mobile';
 dsPage=existing.find(p=>p.getPluginData('rainlink-role')==='system')||figma.createPage();dsPage.name='03 · System, Components & Flows';
 [[desktopPage,'desktop'],[mobilePage,'mobile'],[dsPage,'system']].forEach(([p,role])=>{p.setPluginData('rainlink-page','v1');p.setPluginData('rainlink-role',role);p.backgrounds=[{type:'SOLID',color:rgb('#080D12')}];});
 for(const st of await figma.getLocalTextStylesAsync())if(st.name.startsWith('RainLink /'))st.remove();for(const st of await figma.getLocalEffectStylesAsync())if(st.name.startsWith('RainLink /'))st.remove();for(const col of await figma.variables.getLocalVariableCollectionsAsync())if(col.name.startsWith('RainLink /'))col.remove();
 for(const style of ['Regular','Medium','Semi Bold','Bold'])await figma.loadFontAsync({family:'Inter',style});try{await figma.loadFontAsync({family:monoFamily,style:'Regular'});}catch(e){monoFamily='Inter';}
 await progress('Creating semantic tokens and reusable components…');await makeTokens();await figma.setCurrentPageAsync(dsPage);await makeComponents();designSystem();
 await progress('Building Desktop screens and configuration workflows…');await figma.setCurrentPageAsync(desktopPage);dashboard();desktopNodes();desktopProfiles();desktopRules();desktopConnections();desktopTraffic();desktopLogs();desktopSettings();dashboard(false);desktopQuickSwitch();desktopImport();desktopEditor();desktopAppearance();desktopRuleEditor();
 const tested=registry.desktop.Nodes.clone();desktopPage.appendChild(tested);tested.name='Desktop / Nodes tested';registry.desktop['Nodes tested']=tested;const note=small('Latency test complete · 7 online · London timed out · Selected node unchanged','Primary');const body=tested.findOne(n=>n.name==='Content');if(body)add(body,note);
 const light=registry.desktop.Dashboard.clone();desktopPage.appendChild(light);light.name='Desktop / Dashboard light';light.setExplicitVariableModeForCollection(collection,lightMode);registry.desktop['Dashboard light']=light;applyLight(light);
 // Tighten the dashboard to fit its 900 px viewport without hiding recent activity.
 for(const key of ['Dashboard','Disconnected','Dashboard light']){const d=registry.desktop[key];const b=d.findOne(n=>n.name==='Content');b.itemSpacing=16;b.paddingTop=22;b.paddingBottom=22;const ph=b.findOne(n=>n.name==='Page header');if(ph)ph.resize(1120,64);const met=b.findOne(n=>n.name==='Traffic metrics');met.resize(1120,100);met.children.forEach(n=>{n.resize(268,100);n.paddingTop=n.paddingBottom=16;n.itemSpacing=8;});const cr=b.findOne(n=>n.name==='Connection & quality');cr.resize(1120,188);cr.children.forEach(n=>{n.resize(n.width,188);n.paddingTop=n.paddingBottom=20;n.itemSpacing=12;});const tr=b.findOne(n=>n.name==='Trends & health');tr.resize(1120,240);tr.children.forEach(n=>{n.resize(n.width,240);n.paddingTop=n.paddingBottom=18;n.itemSpacing=10;});const la=d.findOne(n=>n.name==='Chart · latency');if(la)la.resize(672,104);const recent=b.findOne(n=>n.name==='Recent activity');recent.resize(1120,84);recent.paddingTop=recent.paddingBottom=12;}
 const disconnected=registry.desktop.Disconnected;for(const n of disconnected.findAll(n=>n.type==='TEXT')){if(n.characters==='12.8')n.characters='0';if(n.characters==='1.4')n.characters='0';if(n.characters==='142')n.characters='0';if(n.characters==='Network quality')n.characters='Last network quality';}
 await progress('Building Mobile screens, safe areas and interaction states…');await figma.setCurrentPageAsync(mobilePage);mobileHome();mobileNodes();mobileProfiles();mobileTraffic();mobileSettings();mobileHome(false);mobileSwitch();mobileImport();mobileSuccess();mobileDetails();mobileDNS();mobileQR();mobileHome(true,true);mobileHome(false,false,true);
 const mt=registry.mobile.Nodes.clone();mobilePage.appendChild(mt);mt.name='Mobile / Nodes tested';registry.mobile['Nodes tested']=mt;const mc=mt.findOne(n=>n.name==='Content');if(mc){const toast=badge('Tests complete · 7 online','Success',true);mc.insertChild(0,toast);}
 arrangeScreens();await progress('Connecting navigation, imports and node switching…');await linkPrototype();await figma.setCurrentPageAsync(dsPage);flowMap();inspectLayout();
 const report={version:'1.0',file:'RainLink',pages:[desktopPage.id,mobilePage.id,dsPage.id],desktop:Object.fromEntries(Object.entries(registry.desktop).map(([k,n])=>[k,n.id])),mobile:Object.fromEntries(Object.entries(registry.mobile).map(([k,n])=>[k,n.id])),counts:registry.counts,warnings:registry.warnings,flows:registry.links};figma.root.setPluginData('rainlink-report',JSON.stringify(report));
 await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Dashboard];figma.viewport.scrollAndZoomIntoView([registry.desktop.Dashboard]);await refineMain();return;
}
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
 await uInitialize();await simplifyGroupsDocument();
 await localizeDocument();
 await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Dashboard];figma.viewport.scrollAndZoomIntoView([registry.desktop.Dashboard]);
 figma.ui.postMessage({status:report.counts.desktop+' Desktop · '+report.counts.mobile+' Mobile · '+report.counts.components+' components. Overflow checks: '+overflow.length});console.log('RAINLINK_AUDIT',JSON.stringify(report));figma.notify('RainLink quality pass complete');figma.closePlugin();
}

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
 await figma.setCurrentPageAsync(dsPage);const report=await finalizeDocument();await uInitialize();await simplifyGroupsDocument();await localizeDocument();
 await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Dashboard];figma.viewport.scrollAndZoomIntoView([registry.desktop.Dashboard]);
 figma.notify('RainLink complete · '+report.counts.desktop+' Desktop · '+report.counts.mobile+' Mobile · '+report.counts.components+' components · '+report.overflow.length+' layout issues');figma.closePlugin();
}

const ZH_COPY={"  - name: \"Tokyo · Sakura\"": "  - name: \"东京 · 樱花\"", "[TCP] Browser → 192.168.1.1:80 · DIRECT": "[TCP] 浏览器 → 192.168.1.1:80 · DIRECT", "[TCP] Code → api.github.com:443 · VLESS · 24 ms": "[TCP] 代码编辑器 → api.github.com:443 · VLESS · 24 ms", "[TCP] Terminal → registry.npmjs.org:443 · Proxy": "[TCP] 终端 → registry.npmjs.org:443 · 代理", "[UDP] Browser → dns.example.com:443 · Proxy": "[UDP] 浏览器 → dns.example.com:443 · 代理", "# RainLink · Personal workspace": "# RainLink · 个人工作区", "↑ ↓  Navigate     ↵  Connect": "↑ ↓  选择节点     ↵  连接", "↑ 12% from yesterday": "↑ 较昨日增长 12%", "↑ 560 MB uploaded": "↑ 已上传 560 MB", "↓ 7.86 GB downloaded": "↓ 已下载 7.86 GB", "⌘ K to open from anywhere": "按 ⌘ K 随时打开", "01 / Desktop\n02 / Mobile\n03 / Foundations, components and interaction map": "01 / 桌面端\n02 / 移动端\n03 / 基础规范、组件与交互流程", "01 / Quiet": "01 / 克制", "02 / Precise": "02 / 精确", "03 / Connected": "03 / 连接", "11 events shown · Log retention: 7 days": "显示 11 条事件 · 日志保留 7 天", "126 rules": "126 条规则", "14 October 2026 · Local time": "2026 年 10 月 14 日 · 本地时间", "1440 × 900 · Windows / macOS / Linux · Shared components and semantic color modes": "1440 × 900 · Windows / macOS / Linux · 共享组件与语义颜色", "1440 × 900 desktop · 393 × 852 mobile · Shared native components and Auto Layout.": "桌面端 1440 × 900 · 移动端 393 × 852 · 共享原生组件与自动布局。", "16 Desktop screens  /  15 Mobile screens": "16 个桌面端页面  /  15 个移动端页面", "18 destinations": "18 个目标地址", "1h": "1 小时", "2 minutes ago": "2 分钟前", "24h": "24 小时", "3 nodes": "3 个节点", "3 nodes · 48 rules": "3 个节点 · 48 条规则", "3 nodes · 48 rules · Auto-update on": "3 个节点 · 48 条规则 · 自动更新已开启", "30m": "30 分钟", "393 × 852 · iPhone 15 Pro · iOS / Android · Scrollable content with fixed navigation": "393 × 852 · iPhone 15 Pro · iOS / Android · 内容可滚动，底部导航固定", "4 nodes · 32 rules": "4 个节点 · 32 条规则", "4 nodes · 32 rules · Manual updates": "4 个节点 · 32 条规则 · 手动更新", "7 / 8 online": "7 / 8 在线", "7% of total": "占总流量 7%", "8 nodes": "8 个节点", "8 nodes · 126 rules": "8 个节点 · 126 条规则", "8 nodes · 126 rules · Auto-update on": "8 个节点 · 126 条规则 · 自动更新已开启", "8 nodes · 7 online": "8 个节点 · 7 个在线", "8 nodes · 7 online · Updated 2 minutes ago": "8 个节点 · 7 个在线 · 2 分钟前更新", "90% of active connections": "占活跃连接的 90%", "93% of total": "占总流量 93%", "A calm console for the details that matter.": "安静清晰的控制台，呈现关键细节。", "A clear view of your network, in real time.": "实时掌握网络状态。", "A clear view of your network.": "清晰掌握网络状态。", "A complete workspace, from desktop to pocket.": "从桌面到掌心，完整的网络工作区。", "A focused container for related information.": "集中呈现相关信息的容器。", "A home for every network configuration.": "集中管理每一份网络配置。", "A little perspective on your usage.": "看清流量，掌握用量。", "A named success state makes the outcome clear before connecting.": "明确展示导入成功状态，再开始连接。", "A quick latency test helps you choose the best node for your current network.": "快速测速，为当前网络选择合适的节点。", "A quiet, precise interface for people who care about their network. Deep ink surfaces, soft mint signals and a shared language from desktop to pocket.": "为关注网络细节的用户打造。深墨色界面、柔和薄荷色提示，两端共享统一的设计语言。", "A workspace that adapts to your day.": "让工作区适应你的日常。", "About & licenses": "关于与开源许可", "Across 18 destinations": "覆盖 18 个目标地址", "ACTION": "操作", "Active": "已选中", "Active connections": "活跃连接", "Active connections: 142 · Current throughput: 12.8 MB/s": "活跃连接：142 · 当前速率：12.8 MB/s", "Add a configuration": "添加配置", "Add a precise rule to your active profile.": "向当前配置添加精确的分流规则。", "Add a profile": "添加配置", "Add a subscription": "添加订阅", "Add node": "添加节点", "Add rule": "添加规则", "Add your own subscription URL.": "添加你自己的订阅链接。", "Align the code inside the frame.": "将二维码对准取景框。", "All": "全部", "All nodes": "全部节点", "All protocols": "全部协议", "All remaining traffic": "其余所有流量", "All rules": "全部规则", "All values are native Figma variables or editable components. Illustrative network data; no real subscription or account details.": "所有数值均为原生 Figma 变量或可编辑组件。网络数据为示例，不包含真实订阅或账户信息。", "Amsterdam · Canal": "阿姆斯特丹 · 运河", "Amsterdam · Netherlands": "阿姆斯特丹 · 荷兰", "Appearance": "外观", "arrow": "箭头", "Auto-connect": "自动连接", "Auto-update · 6h": "自动更新 · 每 6 小时", "Auto-update enabled · Every 6 hours": "自动更新已开启 · 每 6 小时", "Auto-update every 6 hours": "每 6 小时自动更新", "Automatic": "自动", "Automatic updates": "自动更新", "Available": "可用", "Avg 24 ms  ·  Jitter 2 ms": "平均 24 ms  ·  抖动 2 ms", "Back to dashboard": "返回概览", "Back to profiles": "返回配置", "Back to rules": "返回规则", "Back to settings": "返回设置", "Background": "背景", "bell": "通知铃", "Body · 14 / 20": "正文 · 14 / 20", "Brand / Mark": "品牌 / 标志", "Bring your own configuration into RainLink.": "将自己的配置导入 RainLink。", "Bring your own configuration.": "导入自己的配置。", "Browser": "浏览器", "Built for your workflow": "适应你的工作方式", "Button": "按钮", "Buttons / primary, secondary, ghost, danger and disabled": "按钮 / 主要、次要、文字、危险与禁用", "Buttons / style and size variants": "按钮 / 样式与尺寸变体", "Cancel": "取消", "Caption · 12 / 17": "说明 · 12 / 17", "Card / Base": "卡片 / 基础", "Card title": "卡片标题", "Changes apply after you save the profile.": "保存配置后，修改才会生效。", "chart": "图表", "Chart / Latency": "图表 / 延迟", "Chart / Traffic": "图表 / 流量", "Charts / editable native vectors": "图表 / 可编辑原生矢量", "check": "确认", "Check for updates": "检查更新", "Check updates": "检查更新", "chevron": "展开箭头", "Choose a link for the moment.": "选择此刻合适的节点。", "Clarity for every connection.": "每一次连接，都清晰可见。", "Clear": "清空", "Clear beyond color": "状态表达，不只依赖颜色", "Clickable flows are connected on the Desktop and Mobile pages. Start with the named flows in Present mode.": "桌面端和移动端页面已连接交互。使用演示模式中的命名流程开始体验。", "clock": "时钟", "close": "关闭", "Close all": "关闭全部", "Code": "代码编辑器", "Color communicates state, not decoration.": "颜色传达状态，克制使用装饰。", "Compact density": "紧凑布局", "Components": "组件", "Connect": "连接", "Connect → inspect the network → switch node → review inventory.": "连接 → 查看网络状态 → 切换节点 → 查看节点列表。", "Connect and switch nodes. Import a profile and refine routing. Recover gracefully from a connection error.": "连接并切换节点；导入配置并调整分流；从连接错误中恢复。", "Connect automatically": "自动连接", "Connect directly without a proxy.": "直接连接，不经过代理。", "Connect now": "立即连接", "Connect to your own node with one click.": "一键连接自己的节点。", "Connected": "已连接", "Connected. In control.": "已连接，尽在掌握。", "Connection": "连接", "Connection controls, always within reach.": "连接控制，随手可达。", "Connection interrupted": "连接中断", "connections": "连接", "Connections": "连接", "copy": "复制", "Core Engine": "核心引擎", "Core engine is up to date.": "核心引擎已是最新版本。", "Core event stream": "核心事件日志", "CORE READY": "核心就绪", "Current node": "当前节点", "Custom resolver": "自定义解析器", "Dark": "深色", "Dark foundation": "深色基础", "Dark foundation and Light extension use independent semantic color collections, compatible with this Starter file.": "深色主题与浅色扩展采用独立语义颜色集合，适配当前免费方案的限制。", "Dashboard": "概览", "Demo: scan a profile": "演示：扫描配置", "DESIGN SYSTEM · 1.0": "设计系统 · 1.0", "Designed around ownership.": "配置由你掌控。", "Desktop / 248 sidebar · 36 content margin · 24 columns": "桌面端 / 侧栏 248 · 内容边距 36 · 列间距 24", "Desktop / Connect & switch": "桌面端 / 连接与切换", "Desktop / Import & configure": "桌面端 / 导入与配置", "DESTINATION": "目标地址", "Development": "开发环境", "Direct": "直连", "DIRECT": "直连", "Direct mode": "直连模式", "Disabled button": "禁用按钮", "Disconnect": "断开连接", "Disconnected": "未连接", "Display · 40 / 58": "展示标题 · 40 / 58", "Display name": "配置名称", "DNS resolver ready · fake-ip enabled": "DNS 解析器就绪 · fake-ip 已开启", "Domain rule": "域名规则", "Domain rules": "域名规则", "down": "向下", "download": "下载", "Download": "下载", "DOWNLOAD": "下载", "Downloaded": "已下载", "Dropdown / Node": "下拉选择 / 节点", "DURATION": "持续时间", "Edit": "编辑", "Edit YAML or JSON directly, with clear validation.": "直接编辑 YAML 或 JSON，校验结果清晰可见。", "Encrypted · Automatic": "加密 · 自动", "Enter a valid subscription URL": "请输入有效的订阅链接", "Error": "错误", "Everything is ready for your next link.": "准备就绪，随时开始连接。", "Excellent": "优秀", "Existing profiles are kept when you import.": "导入时会保留已有配置。", "Export": "导出", "Export CSV": "导出 CSV", "Export snapshot": "导出快照", "Fake IP": "虚拟 IP", "Fallback resolver": "备用解析器", "Favorites": "收藏", "File": "文件", "File contents": "文件内容", "Filter by host, process or rule…": "按主机、进程或规则筛选…", "Find your next link in a keystroke.": "一个快捷键，找到下一个节点。", "Fit more information into lists and tables.": "在列表和表格中显示更多信息。", "folder": "文件夹", "Follow latest": "跟随最新日志", "Follow system appearance": "跟随系统外观", "Format document": "格式化配置", "Frankfurt · Germany": "法兰克福 · 德国", "Frankfurt · Main": "法兰克福 · 美因", "General": "通用", "Germany": "德国", "Global": "全局", "Global mode": "全局模式", "globe": "地球", "grid": "网格", "Heading · 28 / 41": "页面标题 · 28 / 41", "Health check complete: 7 of 8 nodes online": "健康检查完成：8 个节点中 7 个在线", "HITS": "命中次数", "Home": "首页", "Hong Kong": "香港", "Hong Kong · Hong Kong": "香港 · 中国香港", "Hong Kong · Victoria": "香港 · 维多利亚", "Import": "导入", "Import a trusted URL → edit YAML / JSON → refine routing.": "导入可信链接 → 编辑 YAML / JSON → 调整分流。", "Import a URL instead": "改用链接导入", "Import by URL → receive clear confirmation → connect and inspect usage.": "链接导入 → 确认导入成功 → 连接并查看用量。", "Import profile": "添加节点", "Import rules": "导入规则", "Import subscription": "导入订阅", "Import success": "导入成功", "Import your own profile or node.": "导入自己的配置或节点。", "Improve routing consistency.": "保持解析与分流一致。", "In 2h": "2 小时后", "In 5h 58m": "5 小时 58 分钟后", "Info": "信息", "INFO": "信息", "Info level": "信息级别", "Input / Default": "输入框 / 默认", "Input / Focus": "输入框 / 聚焦", "Input → Validated → Added": "输入 → 校验 → 已添加", "Input validation error": "输入校验错误", "Inputs / default, focus and validation": "输入框 / 默认、聚焦与校验", "IP rule": "IP 规则", "IP rules": "IP 规则", "IPv6 resolution": "IPv6 解析", "Japan": "日本", "Japan · Tokyo": "日本 · 东京", "Just now": "刚刚", "Keep dark theme": "保持深色主题", "Keep RainLink available when you start your device.": "设备启动时，让 RainLink 随时可用。", "Keep your configurations in sync.": "同步管理你的配置。", "laptop": "笔记本", "Large mobile connection control and persistent desktop status share the same vocabulary.": "移动端的大型连接按钮与桌面端的常驻状态栏使用相同的状态文案。", "Last network quality": "上次网络质量", "Last tested": "上次测速", "LAST UPDATED": "上次更新", "Latency": "延迟", "LATENCY": "延迟", "Latency test complete · 7 online · London timed out · Selected node unchanged": "测速完成 · 7 个在线 · 伦敦节点超时 · 当前节点保持不变", "Latency trend": "延迟趋势", "Latest": "最新", "Launch at login": "开机启动", "Light": "浅色", "Light extension": "浅色扩展", "link": "链路", "LIVE": "实时", "Ln 21, Col 15 · UTF-8 · 2 spaces": "第 21 行，第 15 列 · UTF-8 · 2 空格缩进", "Local and private networks": "本地与私有网络", "Local file": "本地文件", "Logs": "日志", "London · Thames": "伦敦 · 泰晤士", "London · Thames: latency test timed out after 5000 ms": "伦敦 · 泰晤士：延迟测试在 5000 ms 后超时", "London · United Kingdom": "伦敦 · 英国", "Los Angeles · Pacific": "洛杉矶 · 太平洋", "Los Angeles · United States": "洛杉矶 · 美国", "LOW LATENCY": "低延迟", "Made for your network.": "为你的网络而设计。", "Make RainLink feel like your own.": "让 RainLink 符合你的习惯。", "Manage nodes": "管理节点", "Match the theme selected in your operating system.": "与操作系统选择的主题保持一致。", "Match traffic against your ordered rules.": "按顺序匹配分流规则。", "Match type": "匹配类型", "Matches example.com and its subdomains.": "匹配 example.com 及其子域名。", "Mobile / 20 side margins · 44 minimum touch targets": "移动端 / 两侧边距 20 · 最小触控区域 44", "Mobile / Bottom navigation": "移动端 / 底部导航", "Mobile / Bring your config": "移动端 / 导入你的配置", "Mobile / Your daily flow": "移动端 / 日常连接", "Modal / Import subscription": "弹窗 / 导入订阅", "Month": "月", "Monthly total": "本月总计", "moon": "月亮", "more": "更多", "Motion / gentle, deliberate": "动效 / 轻柔、明确", "Native components · semantic color bindings · editable vectors · shared across Desktop and Mobile": "原生组件 · 语义颜色绑定 · 可编辑矢量 · 桌面端与移动端共享", "Native instances below share the masters on this page. Edit a master to update every screen.": "以下实例共享本页的组件母版。编辑母版，即可更新各页面。", "Navigation / Active": "导航 / 选中", "Navigation / active states and tabs": "导航 / 选中状态与标签页", "Navigation / Default": "导航 / 默认", "Navigation 180 ms ease out · Node switch 220 ms · Sheet 240 ms": "页面导航 180 ms 缓出 · 节点切换 220 ms · 底部面板 240 ms", "Netherlands": "荷兰", "Network": "网络", "NETWORK": "网络", "Network quality": "网络质量", "Neutral": "中性", "New profile": "新建配置", "New routing rule": "新建分流规则", "NEXT UPDATE": "下次更新", "NODE": "节点", "Node Card / Default": "节点卡片 / 默认", "Node Card / Selected": "节点卡片 / 选中", "Node details": "节点详情", "Node health": "节点健康", "Node testing": "节点测速", "Node, latency, traffic and camera states are illustrative prototype data.": "节点、延迟、流量和相机状态均为原型示例数据。", "nodes": "节点", "Nodes": "节点", "Nodes / selected state and quick switching": "节点 / 选中状态与快速切换", "Notifications": "通知", "October 2026": "2026 年 10 月", "Off / On": "关闭 / 开启", "Offline": "离线", "ON CLICK · 180 MS": "点击 · 180 ms", "One component language on every screen.": "每个页面，共享一套组件语言。", "One language. Every interaction.": "统一设计，连贯体验。", "Online": "在线", "Online · Low latency · Timeout": "在线 · 低延迟 · 超时", "Open configuration editor": "打开配置编辑器", "Open connections": "查看连接", "Open source, thoughtfully built.": "用心打造，开源共享。", "Packet loss": "丢包率", "Pair every status color with a label or icon.": "每一种状态颜色，都配合文字或图标。", "Paste": "粘贴", "Paste a URL or import a local YAML / JSON file.": "粘贴链接，或导入本地 YAML / JSON 文件。", "Paste config": "粘贴配置", "Pause": "暂停", "Pause stream": "暂停日志", "Peak 24.6 MB/s": "峰值 24.6 MB/s", "Peak 3.2 MB/s": "峰值 3.2 MB/s", "Personal workspace": "个人工作区", "Personal workspace / personal.yaml": "个人工作区 / personal.yaml", "Personal workspace synced": "个人工作区已同步", "Personal workspace was imported successfully.": "个人工作区导入成功。", "Place before catch-all": "置于兜底规则之前", "plus": "添加", "Port": "端口", "power": "电源", "PREFERENCES": "偏好设置", "Present the five named prototype flows": "演示 5 条命名原型流程", "Preview": "预览", "Primary": "主色", "Primary resolver": "首选解析器", "PRIORITY": "优先级", "PRIVATE": "私有", "PROCESS": "进程", "profile": "配置", "Profile added": "配置已添加", "Profile editor": "高级内核配置", "Profiles": "分组", "Protocol": "协议", "PROTOCOL": "协议", "Prototype data is illustrative. Camera scans and latency tests are represented by explicit demo states.": "原型数据仅为示例。扫码和测速通过明确的演示状态呈现。", "Prototype Flow": "原型流程", "Proxied": "已代理", "Proxy": "代理", "PROXY": "代理", "Proxy · Tokyo · Sakura": "代理 · 东京 · 樱花", "qr": "二维码", "Quick switch": "选择分组", "Quiet defaults. Thoughtful controls.": "克制的默认设置，顺手的控制。", "Radii / 8 controls · 12 rows · 16 cards · 24 overlays": "圆角 / 控件 8 · 列表行 12 · 卡片 16 · 浮层 24", "rain": "雨滴", "RainLink / Delivery": "RainLink / 交付说明", "RainLink / Desktop": "RainLink / 桌面端", "RainLink / Mobile": "RainLink / 移动端", "RainLink connects to the nodes and configurations you provide. Choose trusted sources and keep your subscription link private.": "RainLink 连接你提供的节点与配置。请选择可信来源，并妥善保管订阅链接。", "RainLink requests camera access only when you scan. You can also import a link or a local file.": "仅在扫码时，RainLink 才会请求相机权限。你也可以导入链接或本地文件。", "Readable metrics. Explicit routing.": "指标清晰，分流明确。", "Ready → Connected → Disconnected → Retry": "就绪 → 已连接 → 未连接 → 重试", "Ready to connect": "准备连接", "READY TO CONNECT": "准备连接", "Ready when you are": "准备就绪，随时连接", "RECENT & FAVORITES": "最近使用与收藏", "Recent connections": "最近连接", "Recommended": "推荐", "Reduce motion": "减少动态效果", "refresh": "刷新", "Refresh all": "刷新全部", "Refresh every 6 hours.": "每 6 小时刷新一次。", "Refreshes every second": "每秒刷新", "REGION": "地区", "Reject": "拒绝", "Reset defaults": "恢复默认", "Resolve clearly. Connect confidently.": "解析清晰，连接安心。", "Resolve IPv6 addresses.": "解析 IPv6 地址。", "Resolver mode": "解析模式", "Restore the last selected node on launch.": "启动时恢复上次选择的节点。", "ROUTE": "路由", "Route action": "分流动作", "Route all traffic through the current node.": "所有流量通过当前节点。", "Route compatible apps through RainLink.": "让兼容的应用通过 RainLink 连接。", "Route device traffic through the core engine.": "通过核心引擎接管设备流量。", "Route intentionally. Keep the rest simple.": "分流按需设置，其余保持简单。", "Routing mode": "分流模式", "Rule": "规则", "RULE": "规则", "Rule editor": "规则编辑器", "Rule engine loaded: 126 rules, 3 rule providers": "规则引擎已加载：126 条规则，3 个规则集", "Rule mode": "规则模式", "RULE MODE": "规则模式", "Rule mode · Connected for 1h 42m": "规则模式 · 已连接 1 小时 42 分钟", "rules": "规则", "Rules": "规则", "Rules run from top to bottom. The first matching rule wins.": "规则从上到下执行，首条匹配规则生效。", "Save & apply": "保存并应用", "Save settings": "保存设置", "Scan a QR code": "扫描二维码", "Scan QR code": "扫描二维码", "search": "搜索", "Search by name, region or protocol…": "搜索名称、地区或协议…", "Search logs…": "搜索日志…", "Search nodes or regions…": "搜索节点或地区…", "Search nodes, regions or protocols…": "搜索节点、地区或协议…", "Search nodes…": "搜索节点…", "See exactly where your traffic goes.": "看清每一条连接的去向。", "Selected": "已选中", "Semantic color tokens": "语义颜色变量", "Seoul": "首尔", "Seoul · Han River": "首尔 · 汉江", "Seoul · South Korea": "首尔 · 韩国", "Server": "服务器", "Set your preferred DNS endpoints.": "设置首选 DNS 地址。", "settings": "设置", "Settings": "设置", "shield": "盾牌", "Show menu bar / tray icon": "显示菜单栏或托盘图标", "Showing 7 of 142 connections": "显示 142 条连接中的 7 条", "Singapore": "新加坡", "Singapore · Marina": "新加坡 · 滨海湾", "Singapore · Singapore": "新加坡 · 新加坡", "Slow": "延迟较高", "Small details. A better daily flow.": "小处贴心，日常顺手。", "Small details. Clear signals.": "细节克制，状态清晰。", "Smart routing is active.": "智能分流已启用。", "SOURCE": "来源", "South Korea": "韩国", "Spacing / 4 px base": "间距 / 4 px 基准", "speed": "测速", "Stable latency. Zero packet loss.": "延迟稳定，零丢包。", "star": "收藏星标", "STATUS": "状态", "Status / Connected": "状态 / 已连接", "Status / text and color together": "状态 / 文字与颜色", "Status badges / semantic tones": "状态标记 / 语义类型", "Stay in flow.": "连接顺畅，工作流畅。", "SUBSCRIPTION": "订阅", "Subscription refresh scheduled in 5h 58m": "订阅将在 5 小时 58 分钟后刷新", "Subscription URL": "订阅链接", "Subscriptions": "订阅", "Subscriptions are stored on your device. RainLink does not provide or sell nodes.": "订阅存储在你的设备上。RainLink 不提供或出售节点。", "Success": "成功", "sun": "太阳", "SUPPORTED PROTOCOLS": "支持的协议", "Surface": "界面表层", "Surfaces / cards, modal and switches": "容器 / 卡片、弹窗与开关", "Switch": "切换", "Switch / Off": "开关 / 关闭", "Switch / On": "开关 / 开启", "Switch node": "切换节点", "SYNCED": "已同步", "System proxy": "系统代理", "Tab": "标签页", "Tab / Active": "标签页 / 选中", "Tab / Default": "标签页 / 默认", "Tap to connect → select a node → inspect protocol and latency.": "点击连接 → 选择节点 → 查看协议和延迟。", "Tap to disconnect": "点击断开连接", "Tap to start your network.": "点击开始连接。", "terminal": "终端", "Terminal": "终端", "Test": "测速", "Test all nodes": "全部测速", "Test latency": "测试延迟", "Testing": "测速中", "Tests complete · 7 online": "测速完成 · 7 个在线", "The processes behind your traffic.": "查看流量背后的应用进程。", "The tested states surface feedback and preserve the selected node.": "测速结果提供明确反馈，并保留当前选中的节点。", "Theme": "主题", "This month": "本月", "This rule will run before the MATCH rule.": "该规则将在 MATCH 规则之前执行。", "This session": "本次会话", "Timeout": "超时", "Title · 20 / 29": "区块标题 · 20 / 29", "Today": "今日", "Today · ↑ 12%": "今日 · ↑ 12%", "Today, 08:00": "今天 08:00", "Today’s traffic": "今日流量", "Tokyo": "东京", "Tokyo · Japan": "东京 · 日本", "Tokyo · Sakura": "东京 · 樱花", "Tokyo · Sakura · Last 30 minutes": "东京 · 樱花 · 最近 30 分钟", "Total traffic": "总流量", "TOTAL TRAFFIC": "总流量", "Traffic": "流量", "Traffic flows through your selected node and routing rules.": "流量按照当前节点与分流规则转发。", "Traffic over time": "流量趋势", "Transferred": "传输量", "Transport": "传输方式", "Travel essentials": "旅行常用", "Try a different node": "尝试其他节点", "TUN mode": "TUN 模式", "Tunnel established · Tokyo · Sakura": "隧道已建立 · 东京 · 樱花", "Two platforms. One familiar rhythm.": "两端一致，操作熟悉。", "TYPE": "类型", "Typography / Inter": "字体 / 思源黑体与等宽字体", "Understand your usage, without the noise.": "看清使用情况，减少信息干扰。", "United Kingdom": "英国", "United States": "美国", "Up to date": "已是最新", "Updated 2m ago": "2 分钟前更新", "Updated just now": "刚刚更新", "Updated today": "今天更新", "Updates": "更新", "upload": "上传", "Upload": "上传", "Uploaded": "已上传", "URL import": "链接导入", "Usage by application": "应用流量", "Usage ranking": "使用排行", "Use a trusted source for your nodes.": "请使用可信的节点来源。", "Use Smart Animate for state changes and a short dissolve for page navigation. Reduced motion uses 100 ms fades.": "状态变化使用智能动画，页面导航使用短暂淡入淡出。开启减少动态效果后，采用 100 ms 渐变。", "Use subtle fades in place of larger transitions.": "用轻柔渐变替代大幅转场。", "Use the active profile’s resolvers.": "使用当前配置的解析器。", "Use this node": "使用此节点", "Valid configuration": "配置有效", "Validated just now": "刚刚校验", "Value": "值", "Version 1.0.0 · Stable": "版本 1.0.0 · 稳定版", "View": "查看", "View light dashboard": "查看浅色概览", "Visible focus rings · readable 12 px captions · 44 px mobile targets · preserved safe areas · keyboard command palette": "可见聚焦环 · 清晰的 12 px 说明文字 · 44 px 移动端触控区 · 保留安全区域 · 支持键盘命令面板", "Warn": "警告", "WARN": "警告", "Warning": "警告", "Week": "周", "wifi": "无线网络", "WORKSPACE": "工作区", "YAML, JSON and subscription URLs are supported.": "支持 YAML、JSON 和订阅链接。", "You’re all set.": "一切就绪。", "Your configuration is ready": "选择连接目标即可开始", "Your configurations, together.": "订阅与手动节点集中管理。", "Your last node did not respond.": "上次使用的节点未响应。", "Your link stays yours.": "你的连接，由你掌控。", "YOUR NETWORK, IN FLOW": "网络连接，顺畅如流", "Your network, in flow.": "网络连接，顺畅如流。", "Your next link awaits.": "下一次连接，即刻开启。", "Your nodes. Your protocols. One workspace.": "你的节点、你的协议，一个工作区。", "Your subscription stays in your workspace.": "订阅链接仅保存在你的工作区。", "Your workspace is ready. Select a node to get started.": "工作区已就绪，选择节点即可开始。", "Apply profile": "保存内核设置", "Chains": "代理链", "Manual node": "添加单个节点", "Manual error": "手动节点 · 输入校验", "Manual success": "单个节点已添加", "Subscription import": "导入订阅", "Source success": "订阅组已添加", "Chain editor": "代理链编排", "Chain empty": "代理链 · 待添加出口", "Chain picker": "选择代理链跳点", "Chain reordered": "代理链 · 调整顺序", "Chain tested": "代理链 · 测试通过", "Chain unavailable": "代理链 · 需要修复", "Chain connected": "代理链 · 已连接", "Groups custom": "分组 · 自建组", "Ungrouped": "未分组", "Ungrouped after move": "未分组 · 移动后", "Moved nodes": "主订阅 · 移动后", "Moved backup": "备用订阅 · 移动后", "Move group": "移动到分组", "Moved": "移动完成", "New group": "新建分组", "Customgroup": "开发环境", "Backup group": "备用订阅", "Backup connected": "备用订阅 · 已连接", "Manual connected": "HTTP · 已连接", "Local connected": "SOCKS5 · 已连接", "Custom connected": "开发环境 · 已连接", "Travel group": "旅行订阅", "Travel connected": "旅行订阅 · 已连接", "Manual added nodes": "未分组 · 添加后", "Group": "分组", "Group node": "组内节点", "back": "返回", "Group heading": "分组标题", "Group identity": "分组信息", "Group current node": "分组当前节点", "Group current identity": "当前节点信息", "Node identity": "节点信息", "Node name": "节点名称", "Node metadata": "节点详情", "Node protocol region": "协议与地区", "Node actions": "节点操作", "Node row": "节点行", "Node facts": "节点属性", "Group toolbar": "分组工具栏", "Group list": "分组列表", "Group current connection": "当前连接", "Current heading": "当前连接标题", "Current facts": "当前连接属性", "Group workspace": "分组工作区", "Group node toolbar": "组内节点工具栏", "Group node inventory": "组内节点列表", "Selected group node": "当前分组节点", "Selected node protocol": "当前节点协议", "Group node workspace": "组内节点工作区", "Simple add form": "添加表单", "Single node address": "节点地址", "Subscription update": "订阅更新", "Move node form": "移动节点表单", "Destination identity": "目标分组信息", "Connection group hero": "连接主卡片", "Connection hero heading": "连接状态标题", "Connection state": "连接状态", "Connection group summary": "当前分组概要", "Connection group bottom": "连接卡片底栏", "Current connection facts": "连接信息", "Network stats": "网络统计", "Connection trends": "网络趋势", "Recent connection record": "最近连接记录", "Selected connection group": "当前连接分组", "Selected group heading": "当前分组标题", "Mobile live speed": "移动端实时速度", "Today traffic simple": "今日流量", "Simple visual chain": "可视化链路", "Simple chain actions": "链路操作", "Visual chain workspace": "可视化链路工作区", "Persistent group status": "顶部连接状态", "Persistent group speeds": "顶部实时速度", "Group flow steps": "分组流程步骤", "Group components": "分组组件", "Grouped node components": "组内节点组件", "Visual chain components": "链路组件", "Groups": "分组", "Group latency trend": "分组延迟趋势", "Latency chart heading": "延迟图表标题", "Latency time axis": "延迟时间轴", "Group health": "分组健康状态", "Health heading": "健康状态标题", "Health node identity": "节点健康信息", "Fixed chain actions": "底部固定操作", "Chain reverse tested": "反向链路 · 测试通过", "Chain reverse connected": "反向链路 · 已连接", "Source": "来源", "Subscription": "订阅", "Manual row": "手动节点行", "Chain": "代理链", "Hop": "跳点", "Summary": "概览", "With source": "含分组标记", "Mode global": "概览 · 全局模式", "Mode direct": "概览 · 直连模式", "Pending selection": "概览 · 新选择待应用", "Overview": "概览", "Proxy mode": "代理模式", "Proxy mode heading": "代理模式标题", "Proxy mode options": "代理模式选项", "Proxy mode desktop": "桌面端代理模式", "Overview target": "概览连接目标", "VPN control": "VPN 连接控制", "VPN power button": "VPN 开关", "VPN mode caption": "VPN 模式说明", "Selection summary": "当前选择", "Selection heading": "选择状态标题", "Pending target summary": "待应用的选择", "Group copy": "分组文案", "Group selection footer": "分组选择底栏", "Routing overview shortcut": "代理模式概览入口", "App status": "应用状态", "桌面端 / 概览开启 VPN": "桌面端 / 概览开启 VPN", "移动端 / 概览开启 VPN": "移动端 / 概览开启 VPN"};
const ZH_NAMES={"Desktop": "桌面端", "Mobile": "移动端", "System, Components & Flows": "设计系统、组件与流程", "Design System": "设计系统", "Foundations": "基础规范", "Usage examples": "用法示例", "Interaction map": "交互流程图", "Overview": "概览", "Delivery": "交付", "Sidebar": "侧边栏", "Variants": "变体", "Badge": "状态标记", "Status Badge": "状态标记", "Button": "按钮", "Navigation": "导航", "Input": "输入框", "Dropdown": "下拉选择", "Node Card": "节点卡片", "Chart": "图表", "Modal": "弹窗", "Switch": "开关", "Tab": "标签页", "Icon": "图标", "Brand": "品牌", "Mark": "标志", "Active": "选中", "Default": "默认", "Focus": "聚焦", "On": "开启", "Off": "关闭", "Disabled": "禁用", "Secondary": "次要", "Primary": "主要", "Ghost": "文字", "Danger": "危险", "Error": "错误", "Info": "信息", "Warning": "警告", "Success": "成功", "Neutral": "中性", "Size": "尺寸", "Style": "样式", "Tone": "状态", "Main": "主内容", "Content": "内容", "Frame": "容器", "Rectangle": "矩形", "Ellipse": "椭圆", "Vector": "矢量", "Label": "标签", "Name": "名称", "Actions": "操作", "Activity title": "活动标题", "About RainLink": "关于 RainLink", "Accessibility": "可访问性", "Appearance controls": "外观控制", "Auto update": "自动更新", "Auto-update": "自动更新", "Axis": "坐标轴", "Body": "正文", "Brand line": "品牌标语", "Breakdown": "流量构成", "Camera scanner": "扫码取景", "Caption": "说明", "Chart header": "图表标题栏", "Chart summary": "图表摘要", "Chart title": "图表标题", "Code snippet": "配置代码", "Code title": "配置标题", "Command palette": "命令面板", "Configuration tools": "配置工具", "Connection & quality": "连接与质量", "Connection bar": "连接状态栏", "Connection control": "连接控制", "Connection details": "连接详情", "Connection filters": "连接筛选", "Connection information": "连接信息", "Connection metrics": "连接指标", "Connection note": "连接说明", "Connection overview": "连接概况", "Connection ring": "连接状态环", "Connection status": "连接状态", "Connection summary": "连接摘要", "Connection title": "连接标题", "Core": "核心", "Core engine & updates": "核心引擎与更新", "Current node title": "当前节点标题", "Custom": "自定义", "DNS behavior": "DNS 行为", "DNS mode": "DNS 模式", "Daily header": "今日流量标题", "Daily totals": "今日总计", "Dark and light palette": "深浅色板", "Dark theme": "深色主题", "Design system header": "设计系统标题", "Desktop collection intro": "桌面端页面说明", "Display": "展示标题", "Display name field": "配置名称输入区", "Divider": "分隔线", "Domain rule form": "域名规则表单", "Down": "下载", "Dynamic Island": "灵动岛", "Editable chart vectors": "可编辑图表矢量", "Editor controls": "编辑器操作", "Editor status": "编辑器状态", "Editor tabs": "编辑器标签页", "Event stream": "事件日志", "Examples": "示例", "Fallback resolver field": "备用解析器输入区", "Favorite": "收藏", "Filters": "筛选", "Flexible space": "弹性留白", "Flow title": "流程标题", "Follow": "跟随", "Footer": "页脚", "Footer actions": "底部操作", "Formats": "格式", "General settings": "通用设置", "Heading": "页面标题", "Icon container": "图标容器", "Icon slot": "图标槽", "Identity": "品牌标识", "Import actions": "导入操作", "Import guidance": "导入说明", "Import layout": "导入布局", "Import shortcuts": "导入快捷操作", "Import subscription form": "订阅导入表单", "Imported contents": "已导入内容", "Interaction and accessibility": "交互与可访问性", "Inventory footer": "节点列表页脚", "Latency and state": "延迟与状态", "Legend": "图例", "Light theme": "浅色主题", "Live": "实时", "Live connection details": "实时连接详情", "Live connections": "实时连接", "Live updates": "实时更新", "Log footer": "日志页脚", "Log toolbar": "日志工具栏", "Match type field": "匹配类型选择区", "Metric": "指标", "Mini content": "内容缩略", "Mini sidebar": "侧栏缩略", "Mobile collection intro": "移动端页面说明", "Connection error": "连接错误", "QR import": "扫码导入", "Nodes tested": "测速结果", "Dashboard light": "概览 · 浅色", "Home light": "首页 · 浅色", "Mode": "模式", "Mode options": "模式选项", "Mode title": "模式标题", "Motion": "动效", "Nav icon": "导航图标", "Nav label": "导航标签", "Navigate": "前往", "Network metrics": "网络指标", "Network preferences": "网络偏好", "Node": "节点", "Node actions": "节点操作", "Node inventory": "节点列表", "Node metadata": "节点详情", "Node metrics": "节点指标", "Node overview": "节点概况", "Node toolbar": "节点工具栏", "Node name": "节点名称", "Node region": "节点地区", "Page actions": "页面操作", "Page header": "页面标题栏", "Palette alignment": "面板定位", "Personal workspace title": "个人工作区标题", "Ping": "延迟", "Preferences": "偏好设置", "Preview stats": "数据预览", "Primary navigation": "主导航", "Primary resolver field": "首选解析器输入区", "Principles": "设计原则", "Privacy note": "隐私说明", "Profile actions": "配置操作", "Profile": "配置", "Protocol tags": "协议标签", "Protocols": "协议", "Quality bars": "质量指示条", "Quality score": "质量评分", "Recent activity": "近期活动", "Recent destinations": "最近目标地址", "Recommended title": "推荐标题", "Region": "地区", "Route action field": "分流动作选择区", "Routing modes": "分流模式", "Rule filters": "规则筛选", "Rule list": "规则列表", "Rule order": "规则顺序", "Rule order note": "规则顺序说明", "Scan area": "扫码区域", "Scrollable content": "可滚动内容", "Tokyo Sakura": "东京樱花", "Setting": "设置项", "Settings layout": "设置布局", "Settings navigation": "设置导航", "Shortcuts": "快捷键", "Shortcut": "快捷键", "Smart choice": "智能建议", "Space": "间距", "Spacing and layout": "间距与布局", "Spacing samples": "间距示例", "State": "状态", "State behavior": "状态行为", "Status bar": "状态栏", "safe area": "安全区域", "Status dot": "状态指示点", "Step": "步骤", "Steps": "步骤", "Stream header": "日志标题栏", "Subscription URL field": "订阅链接输入区", "Subscriptions heading": "订阅标题", "Support": "支持", "Swatches": "色板", "Switch states": "开关状态", "Switches": "开关", "System indicators": "系统状态", "Table header": "表头", "Table row": "表格行", "Tabs": "标签页", "Tags": "标签", "Theme preview": "主题预览", "Theme previews": "主题预览", "Theme title": "主题标题", "Time axis": "时间轴", "Title": "标题", "Token": "变量", "Totals": "总计", "Traffic chart": "流量图表", "Traffic metrics": "流量指标", "Traffic total": "流量总计", "Trends & health": "趋势与健康", "Typography": "字体", "Typography and rhythm": "字体与节奏", "Up": "上传", "Update": "更新", "Update preference": "更新偏好", "Usage bar": "用量条", "Usage by application heading": "应用流量标题", "Value field": "数值输入区", "Version": "版本", "Workspace": "工作区", "Workspace status": "工作区状态", "YAML editor": "YAML 编辑器", "Health": "健康", "Last network quality": "上次网络质量", "Language": "语言", "Simplified Chinese (default)": "简体中文（默认）", "Simplified Chinese is the default interface language.": "默认使用简体中文显示界面。", "Country": "国家地区", "Selected": "已选中", "Status": "状态", "Default language": "默认语言", "Semi Bold": "半粗体", "Medium": "中等字重", "Regular": "常规", "Bold": "粗体", "Sakura": "樱花", "Marina": "滨海湾", "Han River": "汉江", "Victoria": "维多利亚", "Profiles": "分组", "Import profile": "添加节点", "Source success": "订阅组已添加", "Manual success": "单个节点已添加", "Manual node": "添加单个节点", "Groups custom": "分组 · 自建组", "Ungrouped": "未分组", "Ungrouped after move": "未分组 · 移动后", "Moved nodes": "主订阅 · 移动后", "Moved backup": "备用订阅 · 移动后", "Move group": "移动到分组", "Moved": "移动完成", "New group": "新建分组", "Customgroup": "开发环境", "Backup group": "备用订阅", "Backup connected": "备用订阅 · 已连接", "Manual connected": "HTTP · 已连接", "Local connected": "SOCKS5 · 已连接", "Custom connected": "开发环境 · 已连接", "Travel group": "旅行订阅", "Travel connected": "旅行订阅 · 已连接", "Manual added nodes": "未分组 · 添加后", "Quick switch": "选择分组", "Group": "分组", "Group node": "组内节点", "Protocol": "协议", "back": "返回", "Group heading": "分组标题", "Group identity": "分组信息", "Group current node": "分组当前节点", "Group current identity": "当前节点信息", "Node identity": "节点信息", "Node protocol region": "协议与地区", "Node row": "节点行", "Node facts": "节点属性", "Group toolbar": "分组工具栏", "Group list": "分组列表", "Group current connection": "当前连接", "Current heading": "当前连接标题", "Current facts": "当前连接属性", "Group workspace": "分组工作区", "Group node toolbar": "组内节点工具栏", "Group node inventory": "组内节点列表", "Selected group node": "当前分组节点", "Selected node protocol": "当前节点协议", "Group node workspace": "组内节点工作区", "Simple add form": "添加表单", "Single node address": "节点地址", "Subscription update": "订阅更新", "Move node form": "移动节点表单", "Destination identity": "目标分组信息", "Connection group hero": "连接主卡片", "Connection hero heading": "连接状态标题", "Connection state": "连接状态", "Connection group summary": "当前分组概要", "Connection group bottom": "连接卡片底栏", "Current connection facts": "连接信息", "Network stats": "网络统计", "Connection trends": "网络趋势", "Recent connection record": "最近连接记录", "Selected connection group": "当前连接分组", "Selected group heading": "当前分组标题", "Mobile live speed": "移动端实时速度", "Today traffic simple": "今日流量", "Simple visual chain": "可视化链路", "Simple chain actions": "链路操作", "Visual chain workspace": "可视化链路工作区", "Persistent group status": "顶部连接状态", "Persistent group speeds": "顶部实时速度", "Group flow steps": "分组流程步骤", "Group components": "分组组件", "Grouped node components": "组内节点组件", "Visual chain components": "链路组件", "Groups": "分组", "Group latency trend": "分组延迟趋势", "Latency chart heading": "延迟图表标题", "Latency time axis": "延迟时间轴", "Group health": "分组健康状态", "Health heading": "健康状态标题", "Health node identity": "节点健康信息", "Fixed chain actions": "底部固定操作", "Chain reverse tested": "反向链路 · 测试通过", "Chain reverse connected": "反向链路 · 已连接", "Source": "来源", "Subscription": "订阅", "Manual row": "手动节点行", "Chain": "代理链", "Hop": "跳点", "Summary": "概览", "With source": "含分组标记", "Mode global": "概览 · 全局模式", "Mode direct": "概览 · 直连模式", "Pending selection": "概览 · 新选择待应用", "Proxy mode": "代理模式", "Proxy mode heading": "代理模式标题", "Proxy mode options": "代理模式选项", "Proxy mode desktop": "桌面端代理模式", "Overview target": "概览连接目标", "VPN control": "VPN 连接控制", "VPN power button": "VPN 开关", "VPN mode caption": "VPN 模式说明", "Selection summary": "当前选择", "Selection heading": "选择状态标题", "Pending target summary": "待应用的选择", "Group copy": "分组文案", "Group selection footer": "分组选择底栏", "Routing overview shortcut": "代理模式概览入口", "App status": "应用状态", "桌面端 / 概览开启 VPN": "桌面端 / 概览开启 VPN", "移动端 / 概览开启 VPN": "移动端 / 概览开启 VPN"};
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


const PRE_UPGRADE_TEXT={"I2:25009;2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:25009;2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:25009;2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:25009;2:24924;2:16729": {"text": "概览", "family": "Noto Sans SC", "style": "Medium"}, "I2:25009;2:24924;2:16730": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:25009;2:24925;2:16720": {"text": "节点", "family": "Noto Sans SC", "style": "Regular"}, "I2:25009;2:24925;2:16721": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:25009;2:24926;2:16720": {"text": "配置", "family": "Noto Sans SC", "style": "Regular"}, "I2:25009;2:24926;2:16721": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:25009;2:24927;2:16720": {"text": "规则", "family": "Noto Sans SC", "style": "Regular"}, "I2:25009;2:24927;2:16721": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:25009;2:24928;2:16720": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "I2:25009;2:24928;2:16721": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:25009;2:24929;2:16720": {"text": "流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:25009;2:24929;2:16721": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:25009;2:24930;2:16720": {"text": "日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:25009;2:24930;2:16721": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:25009;2:24931;2:16720": {"text": "设置", "family": "Noto Sans SC", "style": "Regular"}, "I2:25009;2:24931;2:16721": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "I2:25009;2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "I2:25009;2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:25009;2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:25009;2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:25009;2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "I2:25009;2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:25009;2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:17084": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "2:17085": {"text": "01:42:18", "family": "Inter", "style": "Regular"}, "2:17092": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:17097": {"text": "12.8 MB/s", "family": "Roboto Mono", "style": "Regular"}, "2:17102": {"text": "1.4 MB/s", "family": "Roboto Mono", "style": "Regular"}, "I2:17103;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:17103;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:17110;2:16650": {"text": "⌘ K", "family": "Noto Sans SC", "style": "Medium"}, "2:17079": {"text": "概览", "family": "Noto Sans SC", "style": "Medium"}, "2:17080": {"text": "实时掌握网络状态。", "family": "Noto Sans SC", "style": "Regular"}, "I2:17070;2:16640": {"text": "快速切换", "family": "Noto Sans SC", "style": "Medium"}, "2:17262": {"text": "今日流量", "family": "Noto Sans SC", "style": "Regular"}, "2:17267": {"text": "8.42", "family": "Inter", "style": "Semi Bold"}, "2:17268": {"text": "GB", "family": "Inter", "style": "Regular"}, "2:17269": {"text": "↑ 较昨日增长 12%", "family": "Noto Sans SC", "style": "Regular"}, "2:17272": {"text": "下载", "family": "Noto Sans SC", "style": "Regular"}, "2:17277": {"text": "12.8", "family": "Inter", "style": "Semi Bold"}, "2:17278": {"text": "MB/s", "family": "Inter", "style": "Regular"}, "2:17279": {"text": "峰值 24.6 MB/s", "family": "Noto Sans SC", "style": "Regular"}, "2:17282": {"text": "上传", "family": "Noto Sans SC", "style": "Regular"}, "2:17287": {"text": "1.4", "family": "Inter", "style": "Semi Bold"}, "2:17288": {"text": "MB/s", "family": "Inter", "style": "Regular"}, "2:17289": {"text": "峰值 3.2 MB/s", "family": "Noto Sans SC", "style": "Regular"}, "2:17292": {"text": "活跃连接", "family": "Noto Sans SC", "style": "Regular"}, "2:17297": {"text": "142", "family": "Inter", "style": "Semi Bold"}, "2:17298": {"text": "", "family": "Inter", "style": "Regular"}, "2:17299": {"text": "18 个目标地址", "family": "Noto Sans SC", "style": "Regular"}, "2:17305": {"text": "网络连接，顺畅如流", "family": "Noto Sans SC", "style": "Medium"}, "I2:17306;2:16682": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "2:17311": {"text": "已连接，尽在掌握。", "family": "Noto Sans SC", "style": "Bold"}, "2:17312": {"text": "流量按照当前节点与分流规则转发。", "family": "Noto Sans SC", "style": "Regular"}, "I2:17313;2:16625": {"text": "断开连接", "family": "Noto Sans SC", "style": "Medium"}, "2:17323": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "2:17324": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:17325;2:16679": {"text": "VLESS", "family": "Noto Sans SC", "style": "Medium"}, "I2:17328;2:16650": {"text": "切换节点", "family": "Noto Sans SC", "style": "Medium"}, "2:17337": {"text": "网络质量", "family": "Noto Sans SC", "style": "Medium"}, "2:17343": {"text": "98", "family": "Inter", "style": "Semi Bold"}, "2:17344": {"text": "/ 100", "family": "Inter", "style": "Regular"}, "I2:17345;2:16682": {"text": "优秀", "family": "Noto Sans SC", "style": "Medium"}, "2:17369": {"text": "延迟稳定，零丢包。", "family": "Noto Sans SC", "style": "Regular"}, "2:17374": {"text": "延迟趋势", "family": "Noto Sans SC", "style": "Medium"}, "2:17375": {"text": "东京 · 樱花 · 最近 30 分钟", "family": "Noto Sans SC", "style": "Regular"}, "I2:17377;2:16712": {"text": "30 分钟", "family": "Noto Sans SC", "style": "Medium"}, "I2:17379;2:16710": {"text": "1 小时", "family": "Noto Sans SC", "style": "Medium"}, "I2:17381;2:16710": {"text": "24 小时", "family": "Noto Sans SC", "style": "Medium"}, "2:17392": {"text": "10:00", "family": "Inter", "style": "Regular"}, "2:17393": {"text": "10:10", "family": "Inter", "style": "Regular"}, "2:17394": {"text": "10:20", "family": "Inter", "style": "Regular"}, "2:17395": {"text": "10:30", "family": "Inter", "style": "Regular"}, "2:17399": {"text": "延迟", "family": "Noto Sans SC", "style": "Regular"}, "2:17400": {"text": "平均 24 ms  ·  抖动 2 ms", "family": "Noto Sans SC", "style": "Regular"}, "2:17403": {"text": "节点健康", "family": "Noto Sans SC", "style": "Medium"}, "I2:17404;2:16682": {"text": "7 / 8 在线", "family": "Noto Sans SC", "style": "Medium"}, "2:17409": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "2:17410": {"text": "东京", "family": "Noto Sans SC", "style": "Regular"}, "2:17413": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:17416": {"text": "SG", "family": "Inter", "style": "Semi Bold"}, "2:17417": {"text": "新加坡", "family": "Noto Sans SC", "style": "Regular"}, "2:17420": {"text": "38 ms", "family": "Roboto Mono", "style": "Regular"}, "2:17423": {"text": "HK", "family": "Inter", "style": "Semi Bold"}, "2:17424": {"text": "香港", "family": "Noto Sans SC", "style": "Regular"}, "2:17427": {"text": "18 ms", "family": "Roboto Mono", "style": "Regular"}, "2:17430": {"text": "KR", "family": "Inter", "style": "Semi Bold"}, "2:17431": {"text": "首尔", "family": "Noto Sans SC", "style": "Regular"}, "2:17434": {"text": "42 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:17435;2:16650": {"text": "管理节点", "family": "Noto Sans SC", "style": "Medium"}, "2:17444": {"text": "最近连接", "family": "Noto Sans SC", "style": "Medium"}, "I2:17445;2:16650": {"text": "查看连接", "family": "Noto Sans SC", "style": "Medium"}, "2:17451": {"text": "api.github.com", "family": "Inter", "style": "Regular"}, "I2:17452;2:16682": {"text": "代理", "family": "Noto Sans SC", "style": "Medium"}, "2:17455": {"text": "docs.rs", "family": "Inter", "style": "Regular"}, "I2:17456;2:16682": {"text": "代理", "family": "Noto Sans SC", "style": "Medium"}, "2:17459": {"text": "192.168.1.1", "family": "Inter", "style": "Regular"}, "I2:17460;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "2:17463": {"text": "刚刚更新", "family": "Noto Sans SC", "style": "Regular"}, "I2:25125;2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:25125;2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:25125;2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:25125;2:24924;2:16720": {"text": "概览", "family": "Noto Sans SC", "style": "Regular"}, "I2:25125;2:24924;2:16721": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:25125;2:24925;2:16729": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:25125;2:24925;2:16730": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:25125;2:24926;2:16720": {"text": "配置", "family": "Noto Sans SC", "style": "Regular"}, "I2:25125;2:24926;2:16721": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:25125;2:24927;2:16720": {"text": "规则", "family": "Noto Sans SC", "style": "Regular"}, "I2:25125;2:24927;2:16721": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:25125;2:24928;2:16720": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "I2:25125;2:24928;2:16721": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:25125;2:24929;2:16720": {"text": "流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:25125;2:24929;2:16721": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:25125;2:24930;2:16720": {"text": "日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:25125;2:24930;2:16721": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:25125;2:24931;2:16720": {"text": "设置", "family": "Noto Sans SC", "style": "Regular"}, "I2:25125;2:24931;2:16721": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "I2:25125;2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "I2:25125;2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:25125;2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:25125;2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:25125;2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "I2:25125;2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:25125;2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:17488": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "2:17489": {"text": "01:42:18", "family": "Inter", "style": "Regular"}, "2:17496": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:17501": {"text": "12.8 MB/s", "family": "Roboto Mono", "style": "Regular"}, "2:17506": {"text": "1.4 MB/s", "family": "Roboto Mono", "style": "Regular"}, "I2:17507;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:17507;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:17514;2:16650": {"text": "⌘ K", "family": "Noto Sans SC", "style": "Medium"}, "2:17483": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "2:17484": {"text": "你的节点、你的协议，一个工作区。", "family": "Noto Sans SC", "style": "Regular"}, "I2:17465;2:16640": {"text": "测试延迟", "family": "Noto Sans SC", "style": "Medium"}, "I2:17473;2:16625": {"text": "添加节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:17664;2:16702": {"text": "搜索名称、地区或协议…", "family": "Noto Sans SC", "style": "Regular"}, "I2:17672;2:16712": {"text": "全部节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:17674;2:16710": {"text": "收藏", "family": "Noto Sans SC", "style": "Medium"}, "I2:17676;2:16640": {"text": "全部协议", "family": "Noto Sans SC", "style": "Medium"}, "2:17686": {"text": "", "family": "Inter", "style": "Medium"}, "2:17688": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "2:17690": {"text": "地区", "family": "Noto Sans SC", "style": "Medium"}, "2:17692": {"text": "协议", "family": "Noto Sans SC", "style": "Medium"}, "2:17694": {"text": "延迟", "family": "Noto Sans SC", "style": "Medium"}, "2:17696": {"text": "状态", "family": "Noto Sans SC", "style": "Medium"}, "2:17698": {"text": "", "family": "Inter", "style": "Medium"}, "2:17704": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "2:17705": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "2:17720": {"text": "日本", "family": "Noto Sans SC", "style": "Regular"}, "I2:17706;2:16679": {"text": "VLESS", "family": "Noto Sans SC", "style": "Medium"}, "2:17709": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:17710;2:16682": {"text": "在线", "family": "Noto Sans SC", "style": "Medium"}, "I2:17713;2:16682": {"text": "已选中", "family": "Noto Sans SC", "style": "Medium"}, "2:17730": {"text": "SG", "family": "Inter", "style": "Semi Bold"}, "2:17731": {"text": "新加坡 · 滨海湾", "family": "Noto Sans SC", "style": "Medium"}, "2:17748": {"text": "新加坡", "family": "Noto Sans SC", "style": "Regular"}, "I2:17732;2:16679": {"text": "Trojan", "family": "Noto Sans SC", "style": "Medium"}, "2:17735": {"text": "38 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:17736;2:16682": {"text": "在线", "family": "Noto Sans SC", "style": "Medium"}, "I2:17739;2:16650": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:17759": {"text": "HK", "family": "Inter", "style": "Semi Bold"}, "2:17760": {"text": "香港 · 维多利亚", "family": "Noto Sans SC", "style": "Medium"}, "2:17777": {"text": "香港", "family": "Noto Sans SC", "style": "Regular"}, "I2:17761;2:16679": {"text": "Hysteria", "family": "Noto Sans SC", "style": "Medium"}, "2:17764": {"text": "18 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:17765;2:16682": {"text": "在线", "family": "Noto Sans SC", "style": "Medium"}, "I2:17768;2:16650": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:17788": {"text": "KR", "family": "Inter", "style": "Semi Bold"}, "2:17789": {"text": "首尔 · 汉江", "family": "Noto Sans SC", "style": "Medium"}, "2:17806": {"text": "韩国", "family": "Noto Sans SC", "style": "Regular"}, "I2:17790;2:16679": {"text": "TUIC", "family": "Noto Sans SC", "style": "Medium"}, "2:17793": {"text": "42 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:17794;2:16682": {"text": "在线", "family": "Noto Sans SC", "style": "Medium"}, "I2:17797;2:16650": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:17817": {"text": "US", "family": "Inter", "style": "Semi Bold"}, "2:17818": {"text": "洛杉矶 · 太平洋", "family": "Noto Sans SC", "style": "Medium"}, "2:17835": {"text": "美国", "family": "Noto Sans SC", "style": "Regular"}, "I2:17819;2:16679": {"text": "Shadowsocks", "family": "Noto Sans SC", "style": "Medium"}, "2:17822": {"text": "142 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:17823;2:16682": {"text": "在线", "family": "Noto Sans SC", "style": "Medium"}, "I2:17826;2:16650": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:17846": {"text": "DE", "family": "Inter", "style": "Semi Bold"}, "2:17847": {"text": "法兰克福 · 美因", "family": "Noto Sans SC", "style": "Medium"}, "2:17864": {"text": "德国", "family": "Noto Sans SC", "style": "Regular"}, "I2:17848;2:16679": {"text": "VMess", "family": "Noto Sans SC", "style": "Medium"}, "2:17851": {"text": "186 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:17852;2:16682": {"text": "在线", "family": "Noto Sans SC", "style": "Medium"}, "I2:17855;2:16650": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:17875": {"text": "GB", "family": "Inter", "style": "Semi Bold"}, "2:17876": {"text": "伦敦 · 泰晤士", "family": "Noto Sans SC", "style": "Medium"}, "2:17893": {"text": "英国", "family": "Noto Sans SC", "style": "Regular"}, "I2:17877;2:16679": {"text": "SOCKS5", "family": "Noto Sans SC", "style": "Medium"}, "2:17880": {"text": "—", "family": "Roboto Mono", "style": "Regular"}, "I2:17881;2:16688": {"text": "超时", "family": "Noto Sans SC", "style": "Medium"}, "I2:17884;2:16650": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:17904": {"text": "NL", "family": "Inter", "style": "Semi Bold"}, "2:17905": {"text": "阿姆斯特丹 · 运河", "family": "Noto Sans SC", "style": "Medium"}, "2:17922": {"text": "荷兰", "family": "Noto Sans SC", "style": "Regular"}, "I2:17906;2:16679": {"text": "HTTP", "family": "Noto Sans SC", "style": "Medium"}, "2:17909": {"text": "164 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:17910;2:16682": {"text": "在线", "family": "Noto Sans SC", "style": "Medium"}, "I2:17913;2:16650": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:17929": {"text": "8 个节点 · 7 个在线 · 2 分钟前更新", "family": "Noto Sans SC", "style": "Regular"}, "2:17932": {"text": "个人工作区已同步", "family": "Noto Sans SC", "style": "Regular"}, "2:17935": {"text": "支持的协议", "family": "Noto Sans SC", "style": "Regular"}, "I2:17937;2:16679": {"text": "Shadowsocks", "family": "Noto Sans SC", "style": "Medium"}, "I2:17940;2:16679": {"text": "VLESS", "family": "Noto Sans SC", "style": "Medium"}, "I2:17943;2:16679": {"text": "VMess", "family": "Noto Sans SC", "style": "Medium"}, "I2:17946;2:16679": {"text": "Trojan", "family": "Noto Sans SC", "style": "Medium"}, "I2:17949;2:16679": {"text": "Hysteria", "family": "Noto Sans SC", "style": "Medium"}, "I2:17952;2:16679": {"text": "TUIC", "family": "Noto Sans SC", "style": "Medium"}, "I2:17955;2:16679": {"text": "SOCKS5", "family": "Noto Sans SC", "style": "Medium"}, "I2:17958;2:16679": {"text": "HTTP", "family": "Noto Sans SC", "style": "Medium"}, "I2:25257;2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:25257;2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:25257;2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:25257;2:24924;2:16720": {"text": "概览", "family": "Noto Sans SC", "style": "Regular"}, "I2:25257;2:24924;2:16721": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:25257;2:24925;2:16720": {"text": "节点", "family": "Noto Sans SC", "style": "Regular"}, "I2:25257;2:24925;2:16721": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:25257;2:24926;2:16729": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:25257;2:24926;2:16730": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:25257;2:24927;2:16720": {"text": "规则", "family": "Noto Sans SC", "style": "Regular"}, "I2:25257;2:24927;2:16721": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:25257;2:24928;2:16720": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "I2:25257;2:24928;2:16721": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:25257;2:24929;2:16720": {"text": "流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:25257;2:24929;2:16721": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:25257;2:24930;2:16720": {"text": "日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:25257;2:24930;2:16721": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:25257;2:24931;2:16720": {"text": "设置", "family": "Noto Sans SC", "style": "Regular"}, "I2:25257;2:24931;2:16721": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "I2:25257;2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "I2:25257;2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:25257;2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:25257;2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:25257;2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "I2:25257;2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:25257;2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:17984": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "2:17985": {"text": "01:42:18", "family": "Inter", "style": "Regular"}, "2:17992": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:17997": {"text": "12.8 MB/s", "family": "Roboto Mono", "style": "Regular"}, "2:18002": {"text": "1.4 MB/s", "family": "Roboto Mono", "style": "Regular"}, "I2:18003;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:18003;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:18010;2:16650": {"text": "⌘ K", "family": "Noto Sans SC", "style": "Medium"}, "2:17979": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "2:17980": {"text": "集中管理每一份网络配置。", "family": "Noto Sans SC", "style": "Regular"}, "I2:17962;2:16640": {"text": "新建配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:17967;2:16625": {"text": "导入订阅", "family": "Noto Sans SC", "style": "Medium"}, "I2:18167;2:16682": {"text": "已选中", "family": "Noto Sans SC", "style": "Medium"}, "2:18170": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "2:18171": {"text": "personal.yaml", "family": "Inter", "style": "Regular"}, "2:18172": {"text": "8 个节点 · 126 条规则 · 自动更新已开启", "family": "Noto Sans SC", "style": "Regular"}, "2:18178": {"text": "2 分钟前更新", "family": "Noto Sans SC", "style": "Regular"}, "I2:18179;2:16650": {"text": "编辑", "family": "Noto Sans SC", "style": "Medium"}, "I2:18191;2:16679": {"text": "可用", "family": "Noto Sans SC", "style": "Medium"}, "2:18194": {"text": "开发环境", "family": "Noto Sans SC", "style": "Medium"}, "2:18195": {"text": "dev-routing.json", "family": "Inter", "style": "Regular"}, "2:18196": {"text": "4 个节点 · 32 条规则 · 手动更新", "family": "Noto Sans SC", "style": "Regular"}, "2:18202": {"text": "2 分钟前更新", "family": "Noto Sans SC", "style": "Regular"}, "I2:18203;2:16650": {"text": "编辑", "family": "Noto Sans SC", "style": "Medium"}, "I2:18215;2:16679": {"text": "可用", "family": "Noto Sans SC", "style": "Medium"}, "2:18218": {"text": "旅行常用", "family": "Noto Sans SC", "style": "Medium"}, "2:18219": {"text": "travel.yaml", "family": "Inter", "style": "Regular"}, "2:18220": {"text": "3 个节点 · 48 条规则 · 自动更新已开启", "family": "Noto Sans SC", "style": "Regular"}, "2:18226": {"text": "2 分钟前更新", "family": "Noto Sans SC", "style": "Regular"}, "I2:18227;2:16650": {"text": "编辑", "family": "Noto Sans SC", "style": "Medium"}, "2:18242": {"text": "订阅", "family": "Noto Sans SC", "style": "Medium"}, "2:18243": {"text": "同步管理你的配置。", "family": "Noto Sans SC", "style": "Regular"}, "I2:18233;2:16635": {"text": "刷新全部", "family": "Noto Sans SC", "style": "Medium"}, "2:18246": {"text": "订阅", "family": "Noto Sans SC", "style": "Medium"}, "2:18248": {"text": "来源", "family": "Noto Sans SC", "style": "Medium"}, "2:18250": {"text": "上次更新", "family": "Noto Sans SC", "style": "Medium"}, "2:18252": {"text": "下次更新", "family": "Noto Sans SC", "style": "Medium"}, "2:18254": {"text": "", "family": "Inter", "style": "Medium"}, "2:18256": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "2:18257": {"text": "8 个节点", "family": "Noto Sans SC", "style": "Regular"}, "2:18258": {"text": "https://example.com/sub/••••", "family": "Roboto Mono", "style": "Regular"}, "2:18268": {"text": "2 分钟前", "family": "Noto Sans SC", "style": "Regular"}, "I2:18259;2:16682": {"text": "5 小时 58 分钟后", "family": "Noto Sans SC", "style": "Medium"}, "2:18273": {"text": "旅行常用", "family": "Noto Sans SC", "style": "Medium"}, "2:18274": {"text": "3 个节点", "family": "Noto Sans SC", "style": "Regular"}, "2:18275": {"text": "https://example.net/travel/••••", "family": "Roboto Mono", "style": "Regular"}, "2:18285": {"text": "今天 08:00", "family": "Noto Sans SC", "style": "Regular"}, "I2:18276;2:16679": {"text": "2 小时后", "family": "Noto Sans SC", "style": "Medium"}, "2:18291": {"text": "适应你的工作方式", "family": "Noto Sans SC", "style": "Medium"}, "2:18292": {"text": "直接编辑 YAML 或 JSON，校验结果清晰可见。", "family": "Noto Sans SC", "style": "Regular"}, "I2:18293;2:16640": {"text": "打开配置编辑器", "family": "Noto Sans SC", "style": "Medium"}, "2:18302": {"text": "mode: rule    •    ipv6: true    •    log-level: info    •    dns: enabled", "family": "Roboto Mono", "style": "Regular"}, "I2:25387;2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:25387;2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:25387;2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:25387;2:24924;2:16720": {"text": "概览", "family": "Noto Sans SC", "style": "Regular"}, "I2:25387;2:24924;2:16721": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:25387;2:24925;2:16720": {"text": "节点", "family": "Noto Sans SC", "style": "Regular"}, "I2:25387;2:24925;2:16721": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:25387;2:24926;2:16720": {"text": "配置", "family": "Noto Sans SC", "style": "Regular"}, "I2:25387;2:24926;2:16721": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:25387;2:24927;2:16729": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:25387;2:24927;2:16730": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:25387;2:24928;2:16720": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "I2:25387;2:24928;2:16721": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:25387;2:24929;2:16720": {"text": "流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:25387;2:24929;2:16721": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:25387;2:24930;2:16720": {"text": "日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:25387;2:24930;2:16721": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:25387;2:24931;2:16720": {"text": "设置", "family": "Noto Sans SC", "style": "Regular"}, "I2:25387;2:24931;2:16721": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "I2:25387;2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "I2:25387;2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:25387;2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:25387;2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:25387;2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "I2:25387;2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:25387;2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:18326": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "2:18327": {"text": "01:42:18", "family": "Inter", "style": "Regular"}, "2:18334": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:18339": {"text": "12.8 MB/s", "family": "Roboto Mono", "style": "Regular"}, "2:18344": {"text": "1.4 MB/s", "family": "Roboto Mono", "style": "Regular"}, "I2:18345;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:18345;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:18352;2:16650": {"text": "⌘ K", "family": "Noto Sans SC", "style": "Medium"}, "2:18321": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "2:18322": {"text": "分流按需设置，其余保持简单。", "family": "Noto Sans SC", "style": "Regular"}, "I2:18304;2:16640": {"text": "导入规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:18311;2:16625": {"text": "添加规则", "family": "Noto Sans SC", "style": "Medium"}, "2:18509": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "2:18513": {"text": "按顺序匹配分流规则。", "family": "Noto Sans SC", "style": "Regular"}, "I2:18514;2:16682": {"text": "已选中", "family": "Noto Sans SC", "style": "Medium"}, "2:18524": {"text": "全局模式", "family": "Noto Sans SC", "style": "Medium"}, "2:18526": {"text": "所有流量通过当前节点。", "family": "Noto Sans SC", "style": "Regular"}, "I2:18527;2:16679": {"text": "可用", "family": "Noto Sans SC", "style": "Medium"}, "2:18536": {"text": "直连模式", "family": "Noto Sans SC", "style": "Medium"}, "2:18538": {"text": "直接连接，不经过代理。", "family": "Noto Sans SC", "style": "Regular"}, "I2:18539;2:16679": {"text": "可用", "family": "Noto Sans SC", "style": "Medium"}, "I2:18545;2:16712": {"text": "全部规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:18547;2:16710": {"text": "域名规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:18549;2:16710": {"text": "IP 规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:18551;2:16625": {"text": "添加规则", "family": "Noto Sans SC", "style": "Medium"}, "2:18558": {"text": "优先级", "family": "Noto Sans SC", "style": "Medium"}, "2:18560": {"text": "类型", "family": "Noto Sans SC", "style": "Medium"}, "2:18562": {"text": "MATCH", "family": "Inter", "style": "Medium"}, "2:18564": {"text": "操作", "family": "Noto Sans SC", "style": "Medium"}, "2:18566": {"text": "命中次数", "family": "Noto Sans SC", "style": "Medium"}, "2:18568": {"text": "", "family": "Inter", "style": "Medium"}, "2:18569": {"text": "01", "family": "Roboto Mono", "style": "Regular"}, "I2:18570;2:16679": {"text": "DOMAIN-SUFFIX", "family": "Noto Sans SC", "style": "Medium"}, "2:18573": {"text": "github.com", "family": "Roboto Mono", "style": "Regular"}, "I2:18574;2:16682": {"text": "代理", "family": "Noto Sans SC", "style": "Medium"}, "2:18588": {"text": "12.8k", "family": "Inter", "style": "Regular"}, "2:18591": {"text": "02", "family": "Roboto Mono", "style": "Regular"}, "I2:18592;2:16679": {"text": "DOMAIN-SUFFIX", "family": "Noto Sans SC", "style": "Medium"}, "2:18595": {"text": "developer.apple.com", "family": "Roboto Mono", "style": "Regular"}, "I2:18596;2:16682": {"text": "代理", "family": "Noto Sans SC", "style": "Medium"}, "2:18610": {"text": "4.2k", "family": "Inter", "style": "Regular"}, "2:18613": {"text": "03", "family": "Roboto Mono", "style": "Regular"}, "I2:18614;2:16679": {"text": "DOMAIN", "family": "Noto Sans SC", "style": "Medium"}, "2:18617": {"text": "api.openai.com", "family": "Roboto Mono", "style": "Regular"}, "I2:18618;2:16682": {"text": "代理", "family": "Noto Sans SC", "style": "Medium"}, "2:18632": {"text": "8.7k", "family": "Inter", "style": "Regular"}, "2:18635": {"text": "04", "family": "Roboto Mono", "style": "Regular"}, "I2:18636;2:16679": {"text": "IP-CIDR", "family": "Noto Sans SC", "style": "Medium"}, "2:18639": {"text": "192.168.0.0/16", "family": "Roboto Mono", "style": "Regular"}, "I2:18640;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "2:18654": {"text": "2.1k", "family": "Inter", "style": "Regular"}, "2:18657": {"text": "05", "family": "Roboto Mono", "style": "Regular"}, "I2:18658;2:16679": {"text": "GEOIP", "family": "Noto Sans SC", "style": "Medium"}, "2:18661": {"text": "私有", "family": "Noto Sans SC", "style": "Regular"}, "I2:18662;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "2:18676": {"text": "942", "family": "Inter", "style": "Regular"}, "2:18679": {"text": "06", "family": "Roboto Mono", "style": "Regular"}, "I2:18680;2:16679": {"text": "DOMAIN-SUFFIX", "family": "Noto Sans SC", "style": "Medium"}, "2:18683": {"text": "ads.example.com", "family": "Roboto Mono", "style": "Regular"}, "I2:18684;2:16688": {"text": "拒绝", "family": "Noto Sans SC", "style": "Medium"}, "2:18698": {"text": "318", "family": "Inter", "style": "Regular"}, "2:18701": {"text": "07", "family": "Roboto Mono", "style": "Regular"}, "I2:18702;2:16679": {"text": "MATCH", "family": "Noto Sans SC", "style": "Medium"}, "2:18705": {"text": "其余所有流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:18706;2:16682": {"text": "代理", "family": "Noto Sans SC", "style": "Medium"}, "2:18720": {"text": "32.4k", "family": "Inter", "style": "Regular"}, "2:18730": {"text": "规则从上到下执行，首条匹配规则生效。", "family": "Noto Sans SC", "style": "Regular"}, "I2:25518;2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:25518;2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:25518;2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:25518;2:24924;2:16720": {"text": "概览", "family": "Noto Sans SC", "style": "Regular"}, "I2:25518;2:24924;2:16721": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:25518;2:24925;2:16720": {"text": "节点", "family": "Noto Sans SC", "style": "Regular"}, "I2:25518;2:24925;2:16721": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:25518;2:24926;2:16720": {"text": "配置", "family": "Noto Sans SC", "style": "Regular"}, "I2:25518;2:24926;2:16721": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:25518;2:24927;2:16720": {"text": "规则", "family": "Noto Sans SC", "style": "Regular"}, "I2:25518;2:24927;2:16721": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:25518;2:24928;2:16729": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "I2:25518;2:24928;2:16730": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:25518;2:24929;2:16720": {"text": "流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:25518;2:24929;2:16721": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:25518;2:24930;2:16720": {"text": "日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:25518;2:24930;2:16721": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:25518;2:24931;2:16720": {"text": "设置", "family": "Noto Sans SC", "style": "Regular"}, "I2:25518;2:24931;2:16721": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "I2:25518;2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "I2:25518;2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:25518;2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:25518;2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:25518;2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "I2:25518;2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:25518;2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:18748": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "2:18749": {"text": "01:42:18", "family": "Inter", "style": "Regular"}, "2:18756": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:18761": {"text": "12.8 MB/s", "family": "Roboto Mono", "style": "Regular"}, "2:18766": {"text": "1.4 MB/s", "family": "Roboto Mono", "style": "Regular"}, "I2:18767;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:18767;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:18774;2:16650": {"text": "⌘ K", "family": "Noto Sans SC", "style": "Medium"}, "2:18743": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:18744": {"text": "看清每一条连接的去向。", "family": "Noto Sans SC", "style": "Regular"}, "I2:18731;2:16640": {"text": "导出快照", "family": "Noto Sans SC", "style": "Medium"}, "2:18926": {"text": "已选中", "family": "Noto Sans SC", "style": "Regular"}, "2:18931": {"text": "142", "family": "Inter", "style": "Semi Bold"}, "2:18932": {"text": "", "family": "Inter", "style": "Regular"}, "2:18933": {"text": "覆盖 18 个目标地址", "family": "Noto Sans SC", "style": "Regular"}, "2:18936": {"text": "已代理", "family": "Noto Sans SC", "style": "Regular"}, "2:18942": {"text": "128", "family": "Inter", "style": "Semi Bold"}, "2:18943": {"text": "", "family": "Inter", "style": "Regular"}, "2:18944": {"text": "占活跃连接的 90%", "family": "Noto Sans SC", "style": "Regular"}, "2:18947": {"text": "直连", "family": "Noto Sans SC", "style": "Regular"}, "2:18952": {"text": "14", "family": "Inter", "style": "Semi Bold"}, "2:18953": {"text": "", "family": "Inter", "style": "Regular"}, "2:18954": {"text": "本地与私有网络", "family": "Noto Sans SC", "style": "Regular"}, "2:18957": {"text": "传输量", "family": "Noto Sans SC", "style": "Regular"}, "2:18962": {"text": "2.84", "family": "Inter", "style": "Semi Bold"}, "2:18963": {"text": "GB", "family": "Inter", "style": "Regular"}, "2:18964": {"text": "本次会话", "family": "Noto Sans SC", "style": "Regular"}, "I2:18967;2:16702": {"text": "按主机、进程或规则筛选…", "family": "Noto Sans SC", "style": "Regular"}, "I2:18974;2:16682": {"text": "实时", "family": "Noto Sans SC", "style": "Medium"}, "I2:18977;2:16635": {"text": "暂停", "family": "Noto Sans SC", "style": "Medium"}, "I2:18982;2:16665": {"text": "关闭全部", "family": "Noto Sans SC", "style": "Medium"}, "2:18989": {"text": "目标地址", "family": "Noto Sans SC", "style": "Medium"}, "2:18991": {"text": "进程", "family": "Noto Sans SC", "style": "Medium"}, "2:18993": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "2:18995": {"text": "路由", "family": "Noto Sans SC", "style": "Medium"}, "2:18997": {"text": "下载", "family": "Noto Sans SC", "style": "Medium"}, "2:18999": {"text": "持续时间", "family": "Noto Sans SC", "style": "Medium"}, "2:19000": {"text": "api.github.com:443", "family": "Roboto Mono", "style": "Regular"}, "2:19011": {"text": "代码编辑器", "family": "Noto Sans SC", "style": "Regular"}, "I2:19001;2:16679": {"text": "DOMAIN-SUFFIX", "family": "Noto Sans SC", "style": "Medium"}, "I2:19004;2:16682": {"text": "代理", "family": "Noto Sans SC", "style": "Medium"}, "2:19015": {"text": "42.8 MB", "family": "Inter", "style": "Regular"}, "2:19007": {"text": "04:32", "family": "Roboto Mono", "style": "Regular"}, "2:19018": {"text": "registry.npmjs.org:443", "family": "Roboto Mono", "style": "Regular"}, "2:19029": {"text": "终端", "family": "Noto Sans SC", "style": "Regular"}, "I2:19019;2:16679": {"text": "DOMAIN-SUFFIX", "family": "Noto Sans SC", "style": "Medium"}, "I2:19022;2:16682": {"text": "代理", "family": "Noto Sans SC", "style": "Medium"}, "2:19033": {"text": "168.2 MB", "family": "Inter", "style": "Regular"}, "2:19025": {"text": "02:18", "family": "Roboto Mono", "style": "Regular"}, "2:19036": {"text": "developer.apple.com:443", "family": "Roboto Mono", "style": "Regular"}, "2:19047": {"text": "Safari", "family": "Inter", "style": "Regular"}, "I2:19037;2:16679": {"text": "DOMAIN-SUFFIX", "family": "Noto Sans SC", "style": "Medium"}, "I2:19040;2:16682": {"text": "代理", "family": "Noto Sans SC", "style": "Medium"}, "2:19051": {"text": "12.4 MB", "family": "Inter", "style": "Regular"}, "2:19043": {"text": "01:54", "family": "Roboto Mono", "style": "Regular"}, "2:19054": {"text": "192.168.1.1:80", "family": "Roboto Mono", "style": "Regular"}, "2:19065": {"text": "浏览器", "family": "Noto Sans SC", "style": "Regular"}, "I2:19055;2:16679": {"text": "IP-CIDR", "family": "Noto Sans SC", "style": "Medium"}, "I2:19058;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "2:19069": {"text": "284 KB", "family": "Inter", "style": "Regular"}, "2:19061": {"text": "00:41", "family": "Roboto Mono", "style": "Regular"}, "2:19072": {"text": "docs.rs:443", "family": "Roboto Mono", "style": "Regular"}, "2:19083": {"text": "代码编辑器", "family": "Noto Sans SC", "style": "Regular"}, "I2:19073;2:16679": {"text": "MATCH", "family": "Noto Sans SC", "style": "Medium"}, "I2:19076;2:16682": {"text": "代理", "family": "Noto Sans SC", "style": "Medium"}, "2:19087": {"text": "3.8 MB", "family": "Inter", "style": "Regular"}, "2:19079": {"text": "00:26", "family": "Roboto Mono", "style": "Regular"}, "2:19090": {"text": "api.openai.com:443", "family": "Roboto Mono", "style": "Regular"}, "2:19101": {"text": "终端", "family": "Noto Sans SC", "style": "Regular"}, "I2:19091;2:16679": {"text": "DOMAIN", "family": "Noto Sans SC", "style": "Medium"}, "I2:19094;2:16682": {"text": "代理", "family": "Noto Sans SC", "style": "Medium"}, "2:19105": {"text": "1.2 MB", "family": "Inter", "style": "Regular"}, "2:19097": {"text": "00:14", "family": "Roboto Mono", "style": "Regular"}, "2:19108": {"text": "fonts.googleapis.com:443", "family": "Roboto Mono", "style": "Regular"}, "2:19119": {"text": "浏览器", "family": "Noto Sans SC", "style": "Regular"}, "I2:19109;2:16679": {"text": "MATCH", "family": "Noto Sans SC", "style": "Medium"}, "I2:19112;2:16682": {"text": "代理", "family": "Noto Sans SC", "style": "Medium"}, "2:19123": {"text": "486 KB", "family": "Inter", "style": "Regular"}, "2:19115": {"text": "00:08", "family": "Roboto Mono", "style": "Regular"}, "2:19127": {"text": "显示 142 条连接中的 7 条", "family": "Noto Sans SC", "style": "Regular"}, "2:19128": {"text": "每秒刷新", "family": "Noto Sans SC", "style": "Regular"}, "I2:25647;2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:25647;2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:25647;2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:25647;2:24924;2:16720": {"text": "概览", "family": "Noto Sans SC", "style": "Regular"}, "I2:25647;2:24924;2:16721": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:25647;2:24925;2:16720": {"text": "节点", "family": "Noto Sans SC", "style": "Regular"}, "I2:25647;2:24925;2:16721": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:25647;2:24926;2:16720": {"text": "配置", "family": "Noto Sans SC", "style": "Regular"}, "I2:25647;2:24926;2:16721": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:25647;2:24927;2:16720": {"text": "规则", "family": "Noto Sans SC", "style": "Regular"}, "I2:25647;2:24927;2:16721": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:25647;2:24928;2:16720": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "I2:25647;2:24928;2:16721": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:25647;2:24929;2:16729": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:25647;2:24929;2:16730": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:25647;2:24930;2:16720": {"text": "日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:25647;2:24930;2:16721": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:25647;2:24931;2:16720": {"text": "设置", "family": "Noto Sans SC", "style": "Regular"}, "I2:25647;2:24931;2:16721": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "I2:25647;2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "I2:25647;2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:25647;2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:25647;2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:25647;2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "I2:25647;2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:25647;2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:19146": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "2:19147": {"text": "01:42:18", "family": "Inter", "style": "Regular"}, "2:19154": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:19159": {"text": "12.8 MB/s", "family": "Roboto Mono", "style": "Regular"}, "2:19164": {"text": "1.4 MB/s", "family": "Roboto Mono", "style": "Regular"}, "I2:19165;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:19165;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:19172;2:16650": {"text": "⌘ K", "family": "Noto Sans SC", "style": "Medium"}, "2:19141": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "2:19142": {"text": "看清使用情况，减少信息干扰。", "family": "Noto Sans SC", "style": "Regular"}, "I2:19129;2:16640": {"text": "导出 CSV", "family": "Noto Sans SC", "style": "Medium"}, "2:19324": {"text": "总流量", "family": "Noto Sans SC", "style": "Regular"}, "2:19329": {"text": "8.42", "family": "Inter", "style": "Semi Bold"}, "2:19330": {"text": "GB", "family": "Inter", "style": "Regular"}, "2:19331": {"text": "今日 · ↑ 12%", "family": "Noto Sans SC", "style": "Regular"}, "2:19334": {"text": "已下载", "family": "Noto Sans SC", "style": "Regular"}, "2:19339": {"text": "7.86", "family": "Inter", "style": "Semi Bold"}, "2:19340": {"text": "GB", "family": "Inter", "style": "Regular"}, "2:19341": {"text": "占总流量 93%", "family": "Noto Sans SC", "style": "Regular"}, "2:19344": {"text": "已上传", "family": "Noto Sans SC", "style": "Regular"}, "2:19349": {"text": "560", "family": "Inter", "style": "Semi Bold"}, "2:19350": {"text": "MB", "family": "Inter", "style": "Regular"}, "2:19351": {"text": "占总流量 7%", "family": "Noto Sans SC", "style": "Regular"}, "2:19354": {"text": "本月总计", "family": "Noto Sans SC", "style": "Regular"}, "2:19360": {"text": "126.4", "family": "Inter", "style": "Semi Bold"}, "2:19361": {"text": "GB", "family": "Inter", "style": "Regular"}, "2:19362": {"text": "2026 年 10 月", "family": "Noto Sans SC", "style": "Regular"}, "2:19366": {"text": "流量趋势", "family": "Noto Sans SC", "style": "Medium"}, "2:19367": {"text": "2026 年 10 月 14 日 · 本地时间", "family": "Noto Sans SC", "style": "Regular"}, "I2:19369;2:16712": {"text": "今日", "family": "Noto Sans SC", "style": "Medium"}, "I2:19371;2:16710": {"text": "周", "family": "Noto Sans SC", "style": "Medium"}, "I2:19373;2:16710": {"text": "月", "family": "Noto Sans SC", "style": "Medium"}, "2:19378": {"text": "下载", "family": "Noto Sans SC", "style": "Regular"}, "2:19381": {"text": "上传", "family": "Noto Sans SC", "style": "Regular"}, "2:19383": {"text": "峰值 24.6 MB/s", "family": "Noto Sans SC", "style": "Regular"}, "2:19394": {"text": "00:00", "family": "Inter", "style": "Regular"}, "2:19395": {"text": "06:00", "family": "Inter", "style": "Regular"}, "2:19396": {"text": "12:00", "family": "Inter", "style": "Regular"}, "2:19397": {"text": "18:00", "family": "Inter", "style": "Regular"}, "2:19398": {"text": "24:00", "family": "Inter", "style": "Regular"}, "2:19402": {"text": "应用流量", "family": "Noto Sans SC", "style": "Medium"}, "2:19403": {"text": "查看流量背后的应用进程。", "family": "Noto Sans SC", "style": "Regular"}, "2:19411": {"text": "浏览器", "family": "Noto Sans SC", "style": "Regular"}, "2:19412": {"text": "4.28 GB", "family": "Roboto Mono", "style": "Regular"}, "2:19420": {"text": "代码编辑器", "family": "Noto Sans SC", "style": "Regular"}, "2:19421": {"text": "2.46 GB", "family": "Roboto Mono", "style": "Regular"}, "2:19429": {"text": "终端", "family": "Noto Sans SC", "style": "Regular"}, "2:19430": {"text": "1.68 GB", "family": "Roboto Mono", "style": "Regular"}, "I2:25776;2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:25776;2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:25776;2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:25776;2:24924;2:16720": {"text": "概览", "family": "Noto Sans SC", "style": "Regular"}, "I2:25776;2:24924;2:16721": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:25776;2:24925;2:16720": {"text": "节点", "family": "Noto Sans SC", "style": "Regular"}, "I2:25776;2:24925;2:16721": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:25776;2:24926;2:16720": {"text": "配置", "family": "Noto Sans SC", "style": "Regular"}, "I2:25776;2:24926;2:16721": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:25776;2:24927;2:16720": {"text": "规则", "family": "Noto Sans SC", "style": "Regular"}, "I2:25776;2:24927;2:16721": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:25776;2:24928;2:16720": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "I2:25776;2:24928;2:16721": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:25776;2:24929;2:16720": {"text": "流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:25776;2:24929;2:16721": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:25776;2:24930;2:16729": {"text": "日志", "family": "Noto Sans SC", "style": "Medium"}, "I2:25776;2:24930;2:16730": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:25776;2:24931;2:16720": {"text": "设置", "family": "Noto Sans SC", "style": "Regular"}, "I2:25776;2:24931;2:16721": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "I2:25776;2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "I2:25776;2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:25776;2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:25776;2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:25776;2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "I2:25776;2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:25776;2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:19449": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "2:19450": {"text": "01:42:18", "family": "Inter", "style": "Regular"}, "2:19457": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:19462": {"text": "12.8 MB/s", "family": "Roboto Mono", "style": "Regular"}, "2:19467": {"text": "1.4 MB/s", "family": "Roboto Mono", "style": "Regular"}, "I2:19468;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:19468;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:19475;2:16650": {"text": "⌘ K", "family": "Noto Sans SC", "style": "Medium"}, "2:19444": {"text": "日志", "family": "Noto Sans SC", "style": "Medium"}, "2:19445": {"text": "安静清晰的控制台，呈现关键细节。", "family": "Noto Sans SC", "style": "Regular"}, "I2:19431;2:16640": {"text": "暂停日志", "family": "Noto Sans SC", "style": "Medium"}, "I2:19625;2:16702": {"text": "搜索日志…", "family": "Noto Sans SC", "style": "Regular"}, "I2:19633;2:16712": {"text": "全部", "family": "Noto Sans SC", "style": "Medium"}, "I2:19635;2:16710": {"text": "信息", "family": "Noto Sans SC", "style": "Medium"}, "I2:19637;2:16710": {"text": "警告", "family": "Noto Sans SC", "style": "Medium"}, "I2:19639;2:16710": {"text": "错误", "family": "Noto Sans SC", "style": "Medium"}, "I2:19641;2:16655": {"text": "清空", "family": "Noto Sans SC", "style": "Medium"}, "I2:19646;2:16640": {"text": "导出", "family": "Noto Sans SC", "style": "Medium"}, "2:19660": {"text": "核心事件日志", "family": "Noto Sans SC", "style": "Medium"}, "I2:19662;2:16682": {"text": "实时", "family": "Noto Sans SC", "style": "Medium"}, "2:19665": {"text": "信息级别", "family": "Noto Sans SC", "style": "Regular"}, "2:19667": {"text": "10:42:18.023", "family": "Roboto Mono", "style": "Regular"}, "I2:19668;2:16691": {"text": "信息", "family": "Noto Sans SC", "style": "Medium"}, "2:19671": {"text": "隧道已建立 · 东京 · 樱花", "family": "mixed", "style": "mixed"}, "2:19673": {"text": "10:42:18.108", "family": "Roboto Mono", "style": "Regular"}, "I2:19674;2:16691": {"text": "信息", "family": "Noto Sans SC", "style": "Medium"}, "2:19677": {"text": "规则引擎已加载：126 条规则，3 个规则集", "family": "mixed", "style": "mixed"}, "2:19679": {"text": "10:42:18.246", "family": "Roboto Mono", "style": "Regular"}, "I2:19680;2:16691": {"text": "信息", "family": "Noto Sans SC", "style": "Medium"}, "2:19683": {"text": "DNS 解析器就绪 · fake-ip 已开启", "family": "mixed", "style": "mixed"}, "2:19685": {"text": "10:42:19.504", "family": "Roboto Mono", "style": "Regular"}, "I2:19686;2:16691": {"text": "信息", "family": "Noto Sans SC", "style": "Medium"}, "2:19689": {"text": "[TCP] 代码编辑器 → api.github.com:443 · VLESS · 24 ms", "family": "mixed", "style": "mixed"}, "2:19691": {"text": "10:42:20.142", "family": "Roboto Mono", "style": "Regular"}, "I2:19692;2:16691": {"text": "信息", "family": "Noto Sans SC", "style": "Medium"}, "2:19695": {"text": "[TCP] 终端 → registry.npmjs.org:443 · 代理", "family": "mixed", "style": "mixed"}, "2:19697": {"text": "10:42:22.811", "family": "Roboto Mono", "style": "Regular"}, "I2:19698;2:16685": {"text": "警告", "family": "Noto Sans SC", "style": "Medium"}, "2:19701": {"text": "伦敦 · 泰晤士：延迟测试在 5000 ms 后超时", "family": "mixed", "style": "mixed"}, "2:19703": {"text": "10:42:23.054", "family": "Roboto Mono", "style": "Regular"}, "I2:19704;2:16691": {"text": "信息", "family": "Noto Sans SC", "style": "Medium"}, "2:19707": {"text": "健康检查完成：8 个节点中 7 个在线", "family": "mixed", "style": "mixed"}, "2:19709": {"text": "10:42:24.687", "family": "Roboto Mono", "style": "Regular"}, "I2:19710;2:16691": {"text": "信息", "family": "Noto Sans SC", "style": "Medium"}, "2:19713": {"text": "[TCP] 浏览器 → 192.168.1.1:80 · DIRECT", "family": "mixed", "style": "mixed"}, "2:19715": {"text": "10:42:26.029", "family": "Roboto Mono", "style": "Regular"}, "I2:19716;2:16691": {"text": "信息", "family": "Noto Sans SC", "style": "Medium"}, "2:19719": {"text": "订阅将在 5 小时 58 分钟后刷新", "family": "mixed", "style": "mixed"}, "2:19721": {"text": "10:42:27.361", "family": "Roboto Mono", "style": "Regular"}, "I2:19722;2:16691": {"text": "信息", "family": "Noto Sans SC", "style": "Medium"}, "2:19725": {"text": "[UDP] 浏览器 → dns.example.com:443 · 代理", "family": "mixed", "style": "mixed"}, "2:19727": {"text": "10:42:29.158", "family": "Roboto Mono", "style": "Regular"}, "I2:19728;2:16691": {"text": "信息", "family": "Noto Sans SC", "style": "Medium"}, "2:19731": {"text": "活跃连接：142 · 当前速率：12.8 MB/s", "family": "mixed", "style": "mixed"}, "2:19733": {"text": "显示 11 条事件 · 日志保留 7 天", "family": "Noto Sans SC", "style": "Regular"}, "2:19735": {"text": "跟随最新日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:25906;2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:25906;2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:25906;2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:25906;2:24924;2:16720": {"text": "概览", "family": "Noto Sans SC", "style": "Regular"}, "I2:25906;2:24924;2:16721": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:25906;2:24925;2:16720": {"text": "节点", "family": "Noto Sans SC", "style": "Regular"}, "I2:25906;2:24925;2:16721": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:25906;2:24926;2:16720": {"text": "配置", "family": "Noto Sans SC", "style": "Regular"}, "I2:25906;2:24926;2:16721": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:25906;2:24927;2:16720": {"text": "规则", "family": "Noto Sans SC", "style": "Regular"}, "I2:25906;2:24927;2:16721": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:25906;2:24928;2:16720": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "I2:25906;2:24928;2:16721": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:25906;2:24929;2:16720": {"text": "流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:25906;2:24929;2:16721": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:25906;2:24930;2:16720": {"text": "日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:25906;2:24930;2:16721": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:25906;2:24931;2:16729": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "I2:25906;2:24931;2:16730": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "I2:25906;2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "I2:25906;2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:25906;2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:25906;2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:25906;2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "I2:25906;2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:25906;2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:19753": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "2:19754": {"text": "01:42:18", "family": "Inter", "style": "Regular"}, "2:19761": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:19766": {"text": "12.8 MB/s", "family": "Roboto Mono", "style": "Regular"}, "2:19771": {"text": "1.4 MB/s", "family": "Roboto Mono", "style": "Regular"}, "I2:19772;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:19772;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:19779;2:16650": {"text": "⌘ K", "family": "Noto Sans SC", "style": "Medium"}, "2:19748": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:19749": {"text": "让 RainLink 符合你的习惯。", "family": "Noto Sans SC", "style": "Regular"}, "I2:19738;2:16655": {"text": "恢复默认", "family": "Noto Sans SC", "style": "Medium"}, "2:19935": {"text": "通用", "family": "Noto Sans SC", "style": "Medium"}, "2:19941": {"text": "外观", "family": "Noto Sans SC", "style": "Medium"}, "2:19947": {"text": "网络", "family": "Noto Sans SC", "style": "Medium"}, "2:19953": {"text": "核心引擎", "family": "Noto Sans SC", "style": "Medium"}, "2:19958": {"text": "更新", "family": "Noto Sans SC", "style": "Medium"}, "2:19960": {"text": "版本 1.0.0 · 稳定版", "family": "Noto Sans SC", "style": "Regular"}, "2:19963": {"text": "通用", "family": "Noto Sans SC", "style": "Medium"}, "2:19964": {"text": "克制的默认设置，顺手的控制。", "family": "Noto Sans SC", "style": "Regular"}, "2:19969": {"text": "开机启动", "family": "Noto Sans SC", "style": "Medium"}, "2:19970": {"text": "设备启动时，让 RainLink 随时可用。", "family": "Noto Sans SC", "style": "Regular"}, "2:19976": {"text": "自动连接", "family": "Noto Sans SC", "style": "Medium"}, "2:19977": {"text": "启动时恢复上次选择的节点。", "family": "Noto Sans SC", "style": "Regular"}, "2:19983": {"text": "显示菜单栏或托盘图标", "family": "Noto Sans SC", "style": "Medium"}, "2:19984": {"text": "连接控制，随手可达。", "family": "Noto Sans SC", "style": "Regular"}, "8:27529": {"text": "语言", "family": "Noto Sans SC", "style": "Medium"}, "8:27530": {"text": "默认使用简体中文显示界面。", "family": "Noto Sans SC", "style": "Regular"}, "8:27533": {"text": "简体中文（默认）", "family": "Noto Sans SC", "style": "Medium"}, "2:19986": {"text": "网络", "family": "Noto Sans SC", "style": "Medium"}, "2:19991": {"text": "系统代理", "family": "Noto Sans SC", "style": "Medium"}, "2:19992": {"text": "让兼容的应用通过 RainLink 连接。", "family": "Noto Sans SC", "style": "Regular"}, "2:19998": {"text": "TUN 模式", "family": "Noto Sans SC", "style": "Medium"}, "2:19999": {"text": "通过核心引擎接管设备流量。", "family": "Noto Sans SC", "style": "Regular"}, "2:20009": {"text": "sing-box 1.12.0", "family": "Inter", "style": "Medium"}, "2:20010": {"text": "核心引擎已是最新版本。", "family": "Noto Sans SC", "style": "Regular"}, "I2:20011;2:16682": {"text": "最新", "family": "Noto Sans SC", "style": "Medium"}, "I2:20014;2:16635": {"text": "检查更新", "family": "Noto Sans SC", "style": "Medium"}, "I2:26036;2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:26036;2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:26036;2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:26036;2:24924;2:16729": {"text": "概览", "family": "Noto Sans SC", "style": "Medium"}, "I2:26036;2:24924;2:16730": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:26036;2:24925;2:16720": {"text": "节点", "family": "Noto Sans SC", "style": "Regular"}, "I2:26036;2:24925;2:16721": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:26036;2:24926;2:16720": {"text": "配置", "family": "Noto Sans SC", "style": "Regular"}, "I2:26036;2:24926;2:16721": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:26036;2:24927;2:16720": {"text": "规则", "family": "Noto Sans SC", "style": "Regular"}, "I2:26036;2:24927;2:16721": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:26036;2:24928;2:16720": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "I2:26036;2:24928;2:16721": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:26036;2:24929;2:16720": {"text": "流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:26036;2:24929;2:16721": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:26036;2:24930;2:16720": {"text": "日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:26036;2:24930;2:16721": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:26036;2:24931;2:16720": {"text": "设置", "family": "Noto Sans SC", "style": "Regular"}, "I2:26036;2:24931;2:16721": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "I2:26036;2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "I2:26036;2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:26036;2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:26036;2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:26036;2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "I2:26036;2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:26036;2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:20039": {"text": "未连接", "family": "Noto Sans SC", "style": "Medium"}, "2:20040": {"text": "准备就绪，随时连接", "family": "Noto Sans SC", "style": "Regular"}, "2:20047": {"text": "— ms", "family": "Roboto Mono", "style": "Regular"}, "2:20052": {"text": "0 MB/s", "family": "Roboto Mono", "style": "Regular"}, "2:20057": {"text": "0 MB/s", "family": "Roboto Mono", "style": "Regular"}, "I2:20058;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:20058;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:20065;2:16650": {"text": "⌘ K", "family": "Noto Sans SC", "style": "Medium"}, "2:20034": {"text": "未连接", "family": "Noto Sans SC", "style": "Medium"}, "2:20035": {"text": "工作区已就绪，选择节点即可开始。", "family": "Noto Sans SC", "style": "Regular"}, "I2:20025;2:16640": {"text": "快速切换", "family": "Noto Sans SC", "style": "Medium"}, "2:20217": {"text": "今日流量", "family": "Noto Sans SC", "style": "Regular"}, "2:20222": {"text": "8.42", "family": "Inter", "style": "Semi Bold"}, "2:20223": {"text": "GB", "family": "Inter", "style": "Regular"}, "2:20224": {"text": "↑ 较昨日增长 12%", "family": "Noto Sans SC", "style": "Regular"}, "2:20227": {"text": "下载", "family": "Noto Sans SC", "style": "Regular"}, "2:20232": {"text": "0", "family": "Inter", "style": "Semi Bold"}, "2:20233": {"text": "MB/s", "family": "Inter", "style": "Regular"}, "2:20234": {"text": "峰值 24.6 MB/s", "family": "Noto Sans SC", "style": "Regular"}, "2:20237": {"text": "上传", "family": "Noto Sans SC", "style": "Regular"}, "2:20242": {"text": "0", "family": "Inter", "style": "Semi Bold"}, "2:20243": {"text": "MB/s", "family": "Inter", "style": "Regular"}, "2:20244": {"text": "峰值 3.2 MB/s", "family": "Noto Sans SC", "style": "Regular"}, "2:20247": {"text": "活跃连接", "family": "Noto Sans SC", "style": "Regular"}, "2:20252": {"text": "0", "family": "Inter", "style": "Semi Bold"}, "2:20253": {"text": "", "family": "Inter", "style": "Regular"}, "2:20254": {"text": "18 个目标地址", "family": "Noto Sans SC", "style": "Regular"}, "2:20260": {"text": "准备连接", "family": "Noto Sans SC", "style": "Medium"}, "I2:20261;2:16682": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "2:20266": {"text": "下一次连接，即刻开启。", "family": "Noto Sans SC", "style": "Bold"}, "2:20267": {"text": "一键连接自己的节点。", "family": "Noto Sans SC", "style": "Regular"}, "I2:20268;2:16625": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:20278": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "2:20279": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:20280;2:16679": {"text": "VLESS", "family": "Noto Sans SC", "style": "Medium"}, "I2:20283;2:16650": {"text": "切换节点", "family": "Noto Sans SC", "style": "Medium"}, "2:20292": {"text": "上次网络质量", "family": "Noto Sans SC", "style": "Medium"}, "2:20298": {"text": "98", "family": "Inter", "style": "Semi Bold"}, "2:20299": {"text": "/ 100", "family": "Inter", "style": "Regular"}, "I2:20300;2:16682": {"text": "优秀", "family": "Noto Sans SC", "style": "Medium"}, "2:20324": {"text": "延迟稳定，零丢包。", "family": "Noto Sans SC", "style": "Regular"}, "2:20329": {"text": "延迟趋势", "family": "Noto Sans SC", "style": "Medium"}, "2:20330": {"text": "东京 · 樱花 · 最近 30 分钟", "family": "Noto Sans SC", "style": "Regular"}, "I2:20332;2:16712": {"text": "30 分钟", "family": "Noto Sans SC", "style": "Medium"}, "I2:20334;2:16710": {"text": "1 小时", "family": "Noto Sans SC", "style": "Medium"}, "I2:20336;2:16710": {"text": "24 小时", "family": "Noto Sans SC", "style": "Medium"}, "2:20347": {"text": "10:00", "family": "Inter", "style": "Regular"}, "2:20348": {"text": "10:10", "family": "Inter", "style": "Regular"}, "2:20349": {"text": "10:20", "family": "Inter", "style": "Regular"}, "2:20350": {"text": "10:30", "family": "Inter", "style": "Regular"}, "2:20354": {"text": "延迟", "family": "Noto Sans SC", "style": "Regular"}, "2:20355": {"text": "平均 24 ms  ·  抖动 2 ms", "family": "Noto Sans SC", "style": "Regular"}, "2:20358": {"text": "节点健康", "family": "Noto Sans SC", "style": "Medium"}, "I2:20359;2:16682": {"text": "7 / 8 在线", "family": "Noto Sans SC", "style": "Medium"}, "2:20364": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "2:20365": {"text": "东京", "family": "Noto Sans SC", "style": "Regular"}, "2:20368": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:20371": {"text": "SG", "family": "Inter", "style": "Semi Bold"}, "2:20372": {"text": "新加坡", "family": "Noto Sans SC", "style": "Regular"}, "2:20375": {"text": "38 ms", "family": "Roboto Mono", "style": "Regular"}, "2:20378": {"text": "HK", "family": "Inter", "style": "Semi Bold"}, "2:20379": {"text": "香港", "family": "Noto Sans SC", "style": "Regular"}, "2:20382": {"text": "18 ms", "family": "Roboto Mono", "style": "Regular"}, "2:20385": {"text": "KR", "family": "Inter", "style": "Semi Bold"}, "2:20386": {"text": "首尔", "family": "Noto Sans SC", "style": "Regular"}, "2:20389": {"text": "42 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:20390;2:16650": {"text": "管理节点", "family": "Noto Sans SC", "style": "Medium"}, "2:20399": {"text": "最近连接", "family": "Noto Sans SC", "style": "Medium"}, "I2:20400;2:16650": {"text": "查看连接", "family": "Noto Sans SC", "style": "Medium"}, "2:20406": {"text": "api.github.com", "family": "Inter", "style": "Regular"}, "I2:20407;2:16682": {"text": "代理", "family": "Noto Sans SC", "style": "Medium"}, "2:20410": {"text": "docs.rs", "family": "Inter", "style": "Regular"}, "I2:20411;2:16682": {"text": "代理", "family": "Noto Sans SC", "style": "Medium"}, "2:20414": {"text": "192.168.1.1", "family": "Inter", "style": "Regular"}, "I2:20415;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "2:20418": {"text": "刚刚更新", "family": "Noto Sans SC", "style": "Regular"}, "I2:26153;2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:26153;2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:26153;2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:26153;2:24924;2:16729": {"text": "概览", "family": "Noto Sans SC", "style": "Medium"}, "I2:26153;2:24924;2:16730": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:26153;2:24925;2:16720": {"text": "节点", "family": "Noto Sans SC", "style": "Regular"}, "I2:26153;2:24925;2:16721": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:26153;2:24926;2:16720": {"text": "配置", "family": "Noto Sans SC", "style": "Regular"}, "I2:26153;2:24926;2:16721": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:26153;2:24927;2:16720": {"text": "规则", "family": "Noto Sans SC", "style": "Regular"}, "I2:26153;2:24927;2:16721": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:26153;2:24928;2:16720": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "I2:26153;2:24928;2:16721": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:26153;2:24929;2:16720": {"text": "流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:26153;2:24929;2:16721": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:26153;2:24930;2:16720": {"text": "日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:26153;2:24930;2:16721": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:26153;2:24931;2:16720": {"text": "设置", "family": "Noto Sans SC", "style": "Regular"}, "I2:26153;2:24931;2:16721": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "I2:26153;2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "I2:26153;2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:26153;2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:26153;2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:26153;2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "I2:26153;2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:26153;2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:20436": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "2:20437": {"text": "01:42:18", "family": "Inter", "style": "Regular"}, "2:20444": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:20449": {"text": "12.8 MB/s", "family": "Roboto Mono", "style": "Regular"}, "2:20454": {"text": "1.4 MB/s", "family": "Roboto Mono", "style": "Regular"}, "I2:20455;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:20455;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:20462;2:16650": {"text": "⌘ K", "family": "Noto Sans SC", "style": "Medium"}, "2:20431": {"text": "快速切换", "family": "Noto Sans SC", "style": "Medium"}, "2:20432": {"text": "一个快捷键，找到下一个节点。", "family": "Noto Sans SC", "style": "Regular"}, "I2:20419;2:16655": {"text": "返回概览", "family": "Noto Sans SC", "style": "Medium"}, "2:20613": {"text": "切换节点", "family": "Noto Sans SC", "style": "Bold"}, "I2:20614;2:16650": {"text": "Esc", "family": "Noto Sans SC", "style": "Medium"}, "I2:20619;2:16708": {"text": "搜索节点、地区或协议…", "family": "Noto Sans SC", "style": "Regular"}, "2:20625": {"text": "最近使用与收藏", "family": "Noto Sans SC", "style": "Regular"}, "I2:20626;2:16749": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:20626;2:16751": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:20626;2:16752": {"text": "东京 · 日本", "family": "Noto Sans SC", "style": "Regular"}, "I2:20626;2:16754": {"text": "VLESS", "family": "Inter", "style": "Medium"}, "I2:20626;2:16759": {"text": "24 ms", "family": "Inter", "style": "Medium"}, "I2:20642;2:16733": {"text": "SG", "family": "Inter", "style": "Semi Bold"}, "I2:20642;2:16735": {"text": "新加坡 · 滨海湾", "family": "Noto Sans SC", "style": "Medium"}, "I2:20642;2:16736": {"text": "新加坡 · 新加坡", "family": "Noto Sans SC", "style": "Regular"}, "I2:20642;2:16738": {"text": "Trojan", "family": "Inter", "style": "Medium"}, "I2:20642;2:16743": {"text": "38 ms", "family": "Inter", "style": "Medium"}, "I2:20658;2:16733": {"text": "HK", "family": "Inter", "style": "Semi Bold"}, "I2:20658;2:16735": {"text": "香港 · 维多利亚", "family": "Noto Sans SC", "style": "Medium"}, "I2:20658;2:16736": {"text": "香港 · 中国香港", "family": "Noto Sans SC", "style": "Regular"}, "I2:20658;2:16738": {"text": "Hysteria", "family": "Inter", "style": "Medium"}, "I2:20658;2:16743": {"text": "18 ms", "family": "Inter", "style": "Medium"}, "I2:20674;2:16733": {"text": "KR", "family": "Inter", "style": "Semi Bold"}, "I2:20674;2:16735": {"text": "首尔 · 汉江", "family": "Noto Sans SC", "style": "Medium"}, "I2:20674;2:16736": {"text": "首尔 · 韩国", "family": "Noto Sans SC", "style": "Regular"}, "I2:20674;2:16738": {"text": "TUIC", "family": "Inter", "style": "Medium"}, "I2:20674;2:16743": {"text": "42 ms", "family": "Inter", "style": "Medium"}, "2:20692": {"text": "↑ ↓  选择节点     ↵  连接", "family": "Noto Sans SC", "style": "Regular"}, "2:20693": {"text": "按 ⌘ K 随时打开", "family": "Noto Sans SC", "style": "Regular"}, "I2:26270;2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:26270;2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:26270;2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:26270;2:24924;2:16720": {"text": "概览", "family": "Noto Sans SC", "style": "Regular"}, "I2:26270;2:24924;2:16721": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:26270;2:24925;2:16720": {"text": "节点", "family": "Noto Sans SC", "style": "Regular"}, "I2:26270;2:24925;2:16721": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:26270;2:24926;2:16729": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:26270;2:24926;2:16730": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:26270;2:24927;2:16720": {"text": "规则", "family": "Noto Sans SC", "style": "Regular"}, "I2:26270;2:24927;2:16721": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:26270;2:24928;2:16720": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "I2:26270;2:24928;2:16721": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:26270;2:24929;2:16720": {"text": "流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:26270;2:24929;2:16721": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:26270;2:24930;2:16720": {"text": "日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:26270;2:24930;2:16721": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:26270;2:24931;2:16720": {"text": "设置", "family": "Noto Sans SC", "style": "Regular"}, "I2:26270;2:24931;2:16721": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "I2:26270;2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "I2:26270;2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:26270;2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:26270;2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:26270;2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "I2:26270;2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:26270;2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:20712": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "2:20713": {"text": "01:42:18", "family": "Inter", "style": "Regular"}, "2:20720": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:20725": {"text": "12.8 MB/s", "family": "Roboto Mono", "style": "Regular"}, "2:20730": {"text": "1.4 MB/s", "family": "Roboto Mono", "style": "Regular"}, "I2:20731;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:20731;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:20738;2:16650": {"text": "⌘ K", "family": "Noto Sans SC", "style": "Medium"}, "2:20707": {"text": "导入配置", "family": "Noto Sans SC", "style": "Medium"}, "2:20708": {"text": "将自己的配置导入 RainLink。", "family": "Noto Sans SC", "style": "Regular"}, "I2:20695;2:16655": {"text": "返回配置", "family": "Noto Sans SC", "style": "Medium"}, "2:20889": {"text": "添加订阅", "family": "Noto Sans SC", "style": "Bold"}, "2:20890": {"text": "粘贴链接，或导入本地 YAML / JSON 文件。", "family": "Noto Sans SC", "style": "Regular"}, "I2:20892;2:16712": {"text": "订阅链接", "family": "Noto Sans SC", "style": "Medium"}, "I2:20894;2:16710": {"text": "本地文件", "family": "Noto Sans SC", "style": "Medium"}, "I2:20896;2:16710": {"text": "粘贴配置", "family": "Noto Sans SC", "style": "Medium"}, "2:20899": {"text": "订阅链接", "family": "Noto Sans SC", "style": "Regular"}, "I2:20900;2:16702": {"text": "https://example.com/subscription", "family": "Noto Sans SC", "style": "Regular"}, "2:20906": {"text": "订阅链接仅保存在你的工作区。", "family": "Noto Sans SC", "style": "Regular"}, "2:20910": {"text": "配置名称", "family": "Noto Sans SC", "style": "Regular"}, "I2:20911;2:16702": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Regular"}, "2:20919": {"text": "自动更新", "family": "Noto Sans SC", "style": "Medium"}, "2:20920": {"text": "每 6 小时刷新一次。", "family": "Noto Sans SC", "style": "Regular"}, "I2:20925;2:16655": {"text": "取消", "family": "Noto Sans SC", "style": "Medium"}, "I2:20930;2:16625": {"text": "导入配置", "family": "Noto Sans SC", "style": "Medium"}, "2:20943": {"text": "配置由你掌控。", "family": "Noto Sans SC", "style": "Bold"}, "2:20944": {"text": "RainLink 连接你提供的节点与配置。请选择可信来源，并妥善保管订阅链接。", "family": "Noto Sans SC", "style": "Regular"}, "I2:20946;2:16679": {"text": "YAML", "family": "Noto Sans SC", "style": "Medium"}, "I2:20949;2:16679": {"text": "JSON", "family": "Noto Sans SC", "style": "Medium"}, "I2:20952;2:16679": {"text": "订阅链接", "family": "Noto Sans SC", "style": "Medium"}, "2:20955": {"text": "导入时会保留已有配置。", "family": "Noto Sans SC", "style": "Regular"}, "I2:26401;2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:26401;2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:26401;2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:26401;2:24924;2:16720": {"text": "概览", "family": "Noto Sans SC", "style": "Regular"}, "I2:26401;2:24924;2:16721": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:26401;2:24925;2:16720": {"text": "节点", "family": "Noto Sans SC", "style": "Regular"}, "I2:26401;2:24925;2:16721": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:26401;2:24926;2:16729": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:26401;2:24926;2:16730": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:26401;2:24927;2:16720": {"text": "规则", "family": "Noto Sans SC", "style": "Regular"}, "I2:26401;2:24927;2:16721": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:26401;2:24928;2:16720": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "I2:26401;2:24928;2:16721": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:26401;2:24929;2:16720": {"text": "流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:26401;2:24929;2:16721": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:26401;2:24930;2:16720": {"text": "日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:26401;2:24930;2:16721": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:26401;2:24931;2:16720": {"text": "设置", "family": "Noto Sans SC", "style": "Regular"}, "I2:26401;2:24931;2:16721": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "I2:26401;2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "I2:26401;2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:26401;2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:26401;2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:26401;2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "I2:26401;2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:26401;2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:20976": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "2:20977": {"text": "01:42:18", "family": "Inter", "style": "Regular"}, "2:20984": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:20989": {"text": "12.8 MB/s", "family": "Roboto Mono", "style": "Regular"}, "2:20994": {"text": "1.4 MB/s", "family": "Roboto Mono", "style": "Regular"}, "I2:20995;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:20995;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:21002;2:16650": {"text": "⌘ K", "family": "Noto Sans SC", "style": "Medium"}, "2:20971": {"text": "配置编辑器", "family": "Noto Sans SC", "style": "Medium"}, "2:20972": {"text": "个人工作区 / personal.yaml", "family": "Noto Sans SC", "style": "Regular"}, "I2:20956;2:16640": {"text": "格式化配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:21154;2:16712": {"text": "personal.yaml", "family": "Noto Sans SC", "style": "Medium"}, "I2:21156;2:16710": {"text": "dev-routing.json", "family": "Noto Sans SC", "style": "Medium"}, "I2:21159;2:16679": {"text": "YAML", "family": "Noto Sans SC", "style": "Medium"}, "I2:21162;2:16682": {"text": "配置有效", "family": "Noto Sans SC", "style": "Medium"}, "2:21166": {"text": "01", "family": "Roboto Mono", "style": "Regular"}, "2:21167": {"text": "# RainLink · 个人工作区", "family": "mixed", "style": "mixed"}, "2:21169": {"text": "02", "family": "Roboto Mono", "style": "Regular"}, "2:21170": {"text": "mode: rule", "family": "Roboto Mono", "style": "Regular"}, "2:21172": {"text": "03", "family": "Roboto Mono", "style": "Regular"}, "2:21173": {"text": "log-level: info", "family": "Roboto Mono", "style": "Regular"}, "2:21175": {"text": "04", "family": "Roboto Mono", "style": "Regular"}, "2:21176": {"text": "ipv6: true", "family": "Roboto Mono", "style": "Regular"}, "2:21178": {"text": "05", "family": "Roboto Mono", "style": "Regular"}, "2:21179": {"text": " ", "family": "Roboto Mono", "style": "Regular"}, "2:21181": {"text": "06", "family": "Roboto Mono", "style": "Regular"}, "2:21182": {"text": "dns:", "family": "Roboto Mono", "style": "Regular"}, "2:21184": {"text": "07", "family": "Roboto Mono", "style": "Regular"}, "2:21185": {"text": "  enable: true", "family": "Roboto Mono", "style": "Regular"}, "2:21187": {"text": "08", "family": "Roboto Mono", "style": "Regular"}, "2:21188": {"text": "  enhanced-mode: fake-ip", "family": "Roboto Mono", "style": "Regular"}, "2:21190": {"text": "09", "family": "Roboto Mono", "style": "Regular"}, "2:21191": {"text": "  nameserver: [https://dns.example.com/dns-query]", "family": "Roboto Mono", "style": "Regular"}, "2:21193": {"text": "10", "family": "Roboto Mono", "style": "Regular"}, "2:21194": {"text": " ", "family": "Roboto Mono", "style": "Regular"}, "2:21196": {"text": "11", "family": "Roboto Mono", "style": "Regular"}, "2:21197": {"text": "proxies:", "family": "Roboto Mono", "style": "Regular"}, "2:21199": {"text": "12", "family": "Roboto Mono", "style": "Regular"}, "2:21200": {"text": "  - name: \"东京 · 樱花\"", "family": "mixed", "style": "mixed"}, "2:21202": {"text": "13", "family": "Roboto Mono", "style": "Regular"}, "2:21203": {"text": "    type: vless", "family": "Roboto Mono", "style": "Regular"}, "2:21205": {"text": "14", "family": "Roboto Mono", "style": "Regular"}, "2:21206": {"text": "    server: tokyo.example.com", "family": "Roboto Mono", "style": "Regular"}, "2:21208": {"text": "15", "family": "Roboto Mono", "style": "Regular"}, "2:21209": {"text": "    port: 443", "family": "Roboto Mono", "style": "Regular"}, "2:21211": {"text": "16", "family": "Roboto Mono", "style": "Regular"}, "2:21212": {"text": "    tls: true", "family": "Roboto Mono", "style": "Regular"}, "2:21214": {"text": "17", "family": "Roboto Mono", "style": "Regular"}, "2:21215": {"text": " ", "family": "Roboto Mono", "style": "Regular"}, "2:21217": {"text": "18", "family": "Roboto Mono", "style": "Regular"}, "2:21218": {"text": "rules:", "family": "Roboto Mono", "style": "Regular"}, "2:21220": {"text": "19", "family": "Roboto Mono", "style": "Regular"}, "2:21221": {"text": "  - DOMAIN-SUFFIX,github.com,PROXY", "family": "Roboto Mono", "style": "Regular"}, "2:21223": {"text": "20", "family": "Roboto Mono", "style": "Regular"}, "2:21224": {"text": "  - IP-CIDR,192.168.0.0/16,DIRECT", "family": "Roboto Mono", "style": "Regular"}, "2:21226": {"text": "21", "family": "Roboto Mono", "style": "Regular"}, "2:21227": {"text": "  - MATCH,PROXY", "family": "Roboto Mono", "style": "Regular"}, "2:21230": {"text": "第 21 行，第 15 列 · UTF-8 · 2 空格缩进", "family": "Noto Sans SC", "style": "Regular"}, "2:21231": {"text": "刚刚校验", "family": "Noto Sans SC", "style": "Regular"}, "2:21233": {"text": "保存配置后，修改才会生效。", "family": "Noto Sans SC", "style": "Regular"}, "I2:21235;2:16655": {"text": "取消", "family": "Noto Sans SC", "style": "Medium"}, "I2:21240;2:16625": {"text": "保存并应用", "family": "Noto Sans SC", "style": "Medium"}, "I2:26532;2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:26532;2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:26532;2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:26532;2:24924;2:16720": {"text": "概览", "family": "Noto Sans SC", "style": "Regular"}, "I2:26532;2:24924;2:16721": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:26532;2:24925;2:16720": {"text": "节点", "family": "Noto Sans SC", "style": "Regular"}, "I2:26532;2:24925;2:16721": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:26532;2:24926;2:16720": {"text": "配置", "family": "Noto Sans SC", "style": "Regular"}, "I2:26532;2:24926;2:16721": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:26532;2:24927;2:16720": {"text": "规则", "family": "Noto Sans SC", "style": "Regular"}, "I2:26532;2:24927;2:16721": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:26532;2:24928;2:16720": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "I2:26532;2:24928;2:16721": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:26532;2:24929;2:16720": {"text": "流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:26532;2:24929;2:16721": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:26532;2:24930;2:16720": {"text": "日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:26532;2:24930;2:16721": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:26532;2:24931;2:16729": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "I2:26532;2:24931;2:16730": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "I2:26532;2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "I2:26532;2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:26532;2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:26532;2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:26532;2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "I2:26532;2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:26532;2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:21264": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "2:21265": {"text": "01:42:18", "family": "Inter", "style": "Regular"}, "2:21272": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:21277": {"text": "12.8 MB/s", "family": "Roboto Mono", "style": "Regular"}, "2:21282": {"text": "1.4 MB/s", "family": "Roboto Mono", "style": "Regular"}, "I2:21283;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:21283;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:21290;2:16650": {"text": "⌘ K", "family": "Noto Sans SC", "style": "Medium"}, "2:21259": {"text": "外观", "family": "Noto Sans SC", "style": "Medium"}, "2:21260": {"text": "让工作区适应你的日常。", "family": "Noto Sans SC", "style": "Regular"}, "I2:21247;2:16655": {"text": "返回设置", "family": "Noto Sans SC", "style": "Medium"}, "2:21446": {"text": "深色", "family": "Noto Sans SC", "style": "Medium"}, "I2:21447;2:16682": {"text": "已选中", "family": "Noto Sans SC", "style": "Medium"}, "I2:21464;2:16620": {"text": "保持深色主题", "family": "Noto Sans SC", "style": "Medium"}, "2:21476": {"text": "浅色", "family": "Noto Sans SC", "style": "Medium"}, "I2:21477;2:16679": {"text": "预览", "family": "Noto Sans SC", "style": "Medium"}, "I2:21494;2:16635": {"text": "查看浅色概览", "family": "Noto Sans SC", "style": "Medium"}, "2:21504": {"text": "跟随系统外观", "family": "Noto Sans SC", "style": "Medium"}, "2:21505": {"text": "与操作系统选择的主题保持一致。", "family": "Noto Sans SC", "style": "Regular"}, "2:21511": {"text": "减少动态效果", "family": "Noto Sans SC", "style": "Medium"}, "2:21512": {"text": "用轻柔渐变替代大幅转场。", "family": "Noto Sans SC", "style": "Regular"}, "2:21518": {"text": "紧凑布局", "family": "Noto Sans SC", "style": "Medium"}, "2:21519": {"text": "在列表和表格中显示更多信息。", "family": "Noto Sans SC", "style": "Regular"}, "I2:26663;2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:26663;2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:26663;2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:26663;2:24924;2:16720": {"text": "概览", "family": "Noto Sans SC", "style": "Regular"}, "I2:26663;2:24924;2:16721": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:26663;2:24925;2:16720": {"text": "节点", "family": "Noto Sans SC", "style": "Regular"}, "I2:26663;2:24925;2:16721": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:26663;2:24926;2:16720": {"text": "配置", "family": "Noto Sans SC", "style": "Regular"}, "I2:26663;2:24926;2:16721": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:26663;2:24927;2:16729": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:26663;2:24927;2:16730": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:26663;2:24928;2:16720": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "I2:26663;2:24928;2:16721": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:26663;2:24929;2:16720": {"text": "流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:26663;2:24929;2:16721": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:26663;2:24930;2:16720": {"text": "日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:26663;2:24930;2:16721": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:26663;2:24931;2:16720": {"text": "设置", "family": "Noto Sans SC", "style": "Regular"}, "I2:26663;2:24931;2:16721": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "I2:26663;2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "I2:26663;2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:26663;2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:26663;2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:26663;2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "I2:26663;2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:26663;2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:21537": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "2:21538": {"text": "01:42:18", "family": "Inter", "style": "Regular"}, "2:21545": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:21550": {"text": "12.8 MB/s", "family": "Roboto Mono", "style": "Regular"}, "2:21555": {"text": "1.4 MB/s", "family": "Roboto Mono", "style": "Regular"}, "I2:21556;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:21556;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:21563;2:16650": {"text": "⌘ K", "family": "Noto Sans SC", "style": "Medium"}, "2:21532": {"text": "规则编辑器", "family": "Noto Sans SC", "style": "Medium"}, "2:21533": {"text": "向当前配置添加精确的分流规则。", "family": "Noto Sans SC", "style": "Regular"}, "I2:21520;2:16655": {"text": "返回规则", "family": "Noto Sans SC", "style": "Medium"}, "2:21713": {"text": "新建分流规则", "family": "Noto Sans SC", "style": "Bold"}, "I2:21715;2:16712": {"text": "域名规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:21717;2:16710": {"text": "IP 规则", "family": "Noto Sans SC", "style": "Medium"}, "2:21720": {"text": "匹配类型", "family": "Noto Sans SC", "style": "Regular"}, "I2:21721;2:16702": {"text": "DOMAIN-SUFFIX", "family": "Noto Sans SC", "style": "Regular"}, "2:21730": {"text": "值", "family": "Noto Sans SC", "style": "Regular"}, "I2:21731;2:16702": {"text": "example.com", "family": "Noto Sans SC", "style": "Regular"}, "2:21737": {"text": "匹配 example.com 及其子域名。", "family": "Noto Sans SC", "style": "Regular"}, "2:21739": {"text": "分流动作", "family": "Noto Sans SC", "style": "Regular"}, "I2:21740;2:16702": {"text": "代理 · 东京 · 樱花", "family": "Noto Sans SC", "style": "Regular"}, "2:21750": {"text": "置于兜底规则之前", "family": "Noto Sans SC", "style": "Medium"}, "2:21751": {"text": "该规则将在 MATCH 规则之前执行。", "family": "Noto Sans SC", "style": "Regular"}, "I2:21755;2:16655": {"text": "取消", "family": "Noto Sans SC", "style": "Medium"}, "I2:21760;2:16625": {"text": "添加规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:26796;2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:26796;2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:26796;2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:26796;2:24924;2:16720": {"text": "概览", "family": "Noto Sans SC", "style": "Regular"}, "I2:26796;2:24924;2:16721": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:26796;2:24925;2:16729": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:26796;2:24925;2:16730": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:26796;2:24926;2:16720": {"text": "配置", "family": "Noto Sans SC", "style": "Regular"}, "I2:26796;2:24926;2:16721": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:26796;2:24927;2:16720": {"text": "规则", "family": "Noto Sans SC", "style": "Regular"}, "I2:26796;2:24927;2:16721": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:26796;2:24928;2:16720": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "I2:26796;2:24928;2:16721": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:26796;2:24929;2:16720": {"text": "流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:26796;2:24929;2:16721": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:26796;2:24930;2:16720": {"text": "日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:26796;2:24930;2:16721": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:26796;2:24931;2:16720": {"text": "设置", "family": "Noto Sans SC", "style": "Regular"}, "I2:26796;2:24931;2:16721": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "I2:26796;2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "I2:26796;2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:26796;2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:26796;2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:26796;2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "I2:26796;2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:26796;2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:21805": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "2:21806": {"text": "01:42:18", "family": "Inter", "style": "Regular"}, "2:21810": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:21813": {"text": "12.8 MB/s", "family": "Roboto Mono", "style": "Regular"}, "2:21816": {"text": "1.4 MB/s", "family": "Roboto Mono", "style": "Regular"}, "I2:21817;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:21817;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:21818;2:16650": {"text": "⌘ K", "family": "Noto Sans SC", "style": "Medium"}, "2:21822": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "2:21823": {"text": "你的节点、你的协议，一个工作区。", "family": "Noto Sans SC", "style": "Regular"}, "I2:21825;2:16640": {"text": "测试延迟", "family": "Noto Sans SC", "style": "Medium"}, "I2:21826;2:16625": {"text": "添加节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:21828;2:16702": {"text": "搜索名称、地区或协议…", "family": "Noto Sans SC", "style": "Regular"}, "I2:21831;2:16712": {"text": "全部节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:21832;2:16710": {"text": "收藏", "family": "Noto Sans SC", "style": "Medium"}, "I2:21833;2:16640": {"text": "全部协议", "family": "Noto Sans SC", "style": "Medium"}, "2:21837": {"text": "", "family": "Inter", "style": "Medium"}, "2:21839": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "2:21841": {"text": "地区", "family": "Noto Sans SC", "style": "Medium"}, "2:21843": {"text": "协议", "family": "Noto Sans SC", "style": "Medium"}, "2:21845": {"text": "延迟", "family": "Noto Sans SC", "style": "Medium"}, "2:21847": {"text": "状态", "family": "Noto Sans SC", "style": "Medium"}, "2:21849": {"text": "", "family": "Inter", "style": "Medium"}, "2:21856": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "2:21857": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "2:21859": {"text": "日本", "family": "Noto Sans SC", "style": "Regular"}, "I2:21861;2:16679": {"text": "VLESS", "family": "Noto Sans SC", "style": "Medium"}, "2:21863": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:21865;2:16682": {"text": "在线", "family": "Noto Sans SC", "style": "Medium"}, "I2:21867;2:16682": {"text": "已选中", "family": "Noto Sans SC", "style": "Medium"}, "2:21875": {"text": "SG", "family": "Inter", "style": "Semi Bold"}, "2:21876": {"text": "新加坡 · 滨海湾", "family": "Noto Sans SC", "style": "Medium"}, "2:21878": {"text": "新加坡", "family": "Noto Sans SC", "style": "Regular"}, "I2:21880;2:16679": {"text": "Trojan", "family": "Noto Sans SC", "style": "Medium"}, "2:21882": {"text": "38 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:21884;2:16682": {"text": "在线", "family": "Noto Sans SC", "style": "Medium"}, "I2:21886;2:16650": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:21894": {"text": "HK", "family": "Inter", "style": "Semi Bold"}, "2:21895": {"text": "香港 · 维多利亚", "family": "Noto Sans SC", "style": "Medium"}, "2:21897": {"text": "香港", "family": "Noto Sans SC", "style": "Regular"}, "I2:21899;2:16679": {"text": "Hysteria", "family": "Noto Sans SC", "style": "Medium"}, "2:21901": {"text": "18 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:21903;2:16682": {"text": "在线", "family": "Noto Sans SC", "style": "Medium"}, "I2:21905;2:16650": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:21913": {"text": "KR", "family": "Inter", "style": "Semi Bold"}, "2:21914": {"text": "首尔 · 汉江", "family": "Noto Sans SC", "style": "Medium"}, "2:21916": {"text": "韩国", "family": "Noto Sans SC", "style": "Regular"}, "I2:21918;2:16679": {"text": "TUIC", "family": "Noto Sans SC", "style": "Medium"}, "2:21920": {"text": "42 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:21922;2:16682": {"text": "在线", "family": "Noto Sans SC", "style": "Medium"}, "I2:21924;2:16650": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:21932": {"text": "US", "family": "Inter", "style": "Semi Bold"}, "2:21933": {"text": "洛杉矶 · 太平洋", "family": "Noto Sans SC", "style": "Medium"}, "2:21935": {"text": "美国", "family": "Noto Sans SC", "style": "Regular"}, "I2:21937;2:16679": {"text": "Shadowsocks", "family": "Noto Sans SC", "style": "Medium"}, "2:21939": {"text": "142 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:21941;2:16682": {"text": "在线", "family": "Noto Sans SC", "style": "Medium"}, "I2:21943;2:16650": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:21951": {"text": "DE", "family": "Inter", "style": "Semi Bold"}, "2:21952": {"text": "法兰克福 · 美因", "family": "Noto Sans SC", "style": "Medium"}, "2:21954": {"text": "德国", "family": "Noto Sans SC", "style": "Regular"}, "I2:21956;2:16679": {"text": "VMess", "family": "Noto Sans SC", "style": "Medium"}, "2:21958": {"text": "186 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:21960;2:16682": {"text": "在线", "family": "Noto Sans SC", "style": "Medium"}, "I2:21962;2:16650": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:21970": {"text": "GB", "family": "Inter", "style": "Semi Bold"}, "2:21971": {"text": "伦敦 · 泰晤士", "family": "Noto Sans SC", "style": "Medium"}, "2:21973": {"text": "英国", "family": "Noto Sans SC", "style": "Regular"}, "I2:21975;2:16679": {"text": "SOCKS5", "family": "Noto Sans SC", "style": "Medium"}, "2:21977": {"text": "—", "family": "Roboto Mono", "style": "Regular"}, "I2:21979;2:16688": {"text": "超时", "family": "Noto Sans SC", "style": "Medium"}, "I2:21981;2:16650": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:21989": {"text": "NL", "family": "Inter", "style": "Semi Bold"}, "2:21990": {"text": "阿姆斯特丹 · 运河", "family": "Noto Sans SC", "style": "Medium"}, "2:21992": {"text": "荷兰", "family": "Noto Sans SC", "style": "Regular"}, "I2:21994;2:16679": {"text": "HTTP", "family": "Noto Sans SC", "style": "Medium"}, "2:21996": {"text": "164 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:21998;2:16682": {"text": "在线", "family": "Noto Sans SC", "style": "Medium"}, "I2:22000;2:16650": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:22003": {"text": "8 个节点 · 7 个在线 · 2 分钟前更新", "family": "Noto Sans SC", "style": "Regular"}, "2:22006": {"text": "个人工作区已同步", "family": "Noto Sans SC", "style": "Regular"}, "2:22008": {"text": "支持的协议", "family": "Noto Sans SC", "style": "Regular"}, "I2:22010;2:16679": {"text": "Shadowsocks", "family": "Noto Sans SC", "style": "Medium"}, "I2:22011;2:16679": {"text": "VLESS", "family": "Noto Sans SC", "style": "Medium"}, "I2:22012;2:16679": {"text": "VMess", "family": "Noto Sans SC", "style": "Medium"}, "I2:22013;2:16679": {"text": "Trojan", "family": "Noto Sans SC", "style": "Medium"}, "I2:22014;2:16679": {"text": "Hysteria", "family": "Noto Sans SC", "style": "Medium"}, "I2:22015;2:16679": {"text": "TUIC", "family": "Noto Sans SC", "style": "Medium"}, "I2:22016;2:16679": {"text": "SOCKS5", "family": "Noto Sans SC", "style": "Medium"}, "I2:22017;2:16679": {"text": "HTTP", "family": "Noto Sans SC", "style": "Medium"}, "2:22018": {"text": "测速完成 · 7 个在线 · 伦敦节点超时 · 当前节点保持不变", "family": "Noto Sans SC", "style": "Regular"}, "I2:26929;2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:26929;2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:26929;2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:26929;2:24924;2:16729": {"text": "概览", "family": "Noto Sans SC", "style": "Medium"}, "I2:26929;2:24924;2:16730": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:26929;2:24925;2:16720": {"text": "节点", "family": "Noto Sans SC", "style": "Regular"}, "I2:26929;2:24925;2:16721": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:26929;2:24926;2:16720": {"text": "配置", "family": "Noto Sans SC", "style": "Regular"}, "I2:26929;2:24926;2:16721": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:26929;2:24927;2:16720": {"text": "规则", "family": "Noto Sans SC", "style": "Regular"}, "I2:26929;2:24927;2:16721": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:26929;2:24928;2:16720": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "I2:26929;2:24928;2:16721": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:26929;2:24929;2:16720": {"text": "流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:26929;2:24929;2:16721": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:26929;2:24930;2:16720": {"text": "日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:26929;2:24930;2:16721": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:26929;2:24931;2:16720": {"text": "设置", "family": "Noto Sans SC", "style": "Regular"}, "I2:26929;2:24931;2:16721": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "I2:26929;2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "I2:26929;2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:26929;2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:26929;2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:26929;2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "I2:26929;2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:26929;2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:22149": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "2:22150": {"text": "01:42:18", "family": "Inter", "style": "Regular"}, "2:22154": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:22157": {"text": "12.8 MB/s", "family": "Roboto Mono", "style": "Regular"}, "2:22160": {"text": "1.4 MB/s", "family": "Roboto Mono", "style": "Regular"}, "I2:22161;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:22161;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:22162;2:16650": {"text": "⌘ K", "family": "Noto Sans SC", "style": "Medium"}, "2:22166": {"text": "概览", "family": "Noto Sans SC", "style": "Medium"}, "2:22167": {"text": "实时掌握网络状态。", "family": "Noto Sans SC", "style": "Regular"}, "I2:22169;2:16640": {"text": "快速切换", "family": "Noto Sans SC", "style": "Medium"}, "2:22173": {"text": "今日流量", "family": "Noto Sans SC", "style": "Regular"}, "2:22176": {"text": "8.42", "family": "Inter", "style": "Semi Bold"}, "2:22177": {"text": "GB", "family": "Inter", "style": "Regular"}, "2:22178": {"text": "↑ 较昨日增长 12%", "family": "Noto Sans SC", "style": "Regular"}, "2:22181": {"text": "下载", "family": "Noto Sans SC", "style": "Regular"}, "2:22184": {"text": "12.8", "family": "Inter", "style": "Semi Bold"}, "2:22185": {"text": "MB/s", "family": "Inter", "style": "Regular"}, "2:22186": {"text": "峰值 24.6 MB/s", "family": "Noto Sans SC", "style": "Regular"}, "2:22189": {"text": "上传", "family": "Noto Sans SC", "style": "Regular"}, "2:22192": {"text": "1.4", "family": "Inter", "style": "Semi Bold"}, "2:22193": {"text": "MB/s", "family": "Inter", "style": "Regular"}, "2:22194": {"text": "峰值 3.2 MB/s", "family": "Noto Sans SC", "style": "Regular"}, "2:22197": {"text": "活跃连接", "family": "Noto Sans SC", "style": "Regular"}, "2:22200": {"text": "142", "family": "Inter", "style": "Semi Bold"}, "2:22201": {"text": "", "family": "Inter", "style": "Regular"}, "2:22202": {"text": "18 个目标地址", "family": "Noto Sans SC", "style": "Regular"}, "2:22208": {"text": "网络连接，顺畅如流", "family": "Noto Sans SC", "style": "Medium"}, "I2:22209;2:16682": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "2:22212": {"text": "已连接，尽在掌握。", "family": "Noto Sans SC", "style": "Bold"}, "2:22213": {"text": "流量按照当前节点与分流规则转发。", "family": "Noto Sans SC", "style": "Regular"}, "I2:22214;2:16625": {"text": "断开连接", "family": "Noto Sans SC", "style": "Medium"}, "2:22218": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "2:22219": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:22220;2:16679": {"text": "VLESS", "family": "Noto Sans SC", "style": "Medium"}, "I2:22221;2:16650": {"text": "切换节点", "family": "Noto Sans SC", "style": "Medium"}, "2:22224": {"text": "网络质量", "family": "Noto Sans SC", "style": "Medium"}, "2:22227": {"text": "98", "family": "Inter", "style": "Semi Bold"}, "2:22228": {"text": "/ 100", "family": "Inter", "style": "Regular"}, "I2:22229;2:16682": {"text": "优秀", "family": "Noto Sans SC", "style": "Medium"}, "2:22251": {"text": "延迟稳定，零丢包。", "family": "Noto Sans SC", "style": "Regular"}, "2:22256": {"text": "延迟趋势", "family": "Noto Sans SC", "style": "Medium"}, "2:22257": {"text": "东京 · 樱花 · 最近 30 分钟", "family": "Noto Sans SC", "style": "Regular"}, "I2:22259;2:16712": {"text": "30 分钟", "family": "Noto Sans SC", "style": "Medium"}, "I2:22260;2:16710": {"text": "1 小时", "family": "Noto Sans SC", "style": "Medium"}, "I2:22261;2:16710": {"text": "24 小时", "family": "Noto Sans SC", "style": "Medium"}, "2:22264": {"text": "10:00", "family": "Inter", "style": "Regular"}, "2:22265": {"text": "10:10", "family": "Inter", "style": "Regular"}, "2:22266": {"text": "10:20", "family": "Inter", "style": "Regular"}, "2:22267": {"text": "10:30", "family": "Inter", "style": "Regular"}, "2:22271": {"text": "延迟", "family": "Noto Sans SC", "style": "Regular"}, "2:22272": {"text": "平均 24 ms  ·  抖动 2 ms", "family": "Noto Sans SC", "style": "Regular"}, "2:22275": {"text": "节点健康", "family": "Noto Sans SC", "style": "Medium"}, "I2:22276;2:16682": {"text": "7 / 8 在线", "family": "Noto Sans SC", "style": "Medium"}, "2:22279": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "2:22280": {"text": "东京", "family": "Noto Sans SC", "style": "Regular"}, "2:22283": {"text": "24 ms", "family": "Roboto Mono", "style": "Regular"}, "2:22286": {"text": "SG", "family": "Inter", "style": "Semi Bold"}, "2:22287": {"text": "新加坡", "family": "Noto Sans SC", "style": "Regular"}, "2:22290": {"text": "38 ms", "family": "Roboto Mono", "style": "Regular"}, "2:22293": {"text": "HK", "family": "Inter", "style": "Semi Bold"}, "2:22294": {"text": "香港", "family": "Noto Sans SC", "style": "Regular"}, "2:22297": {"text": "18 ms", "family": "Roboto Mono", "style": "Regular"}, "2:22300": {"text": "KR", "family": "Inter", "style": "Semi Bold"}, "2:22301": {"text": "首尔", "family": "Noto Sans SC", "style": "Regular"}, "2:22304": {"text": "42 ms", "family": "Roboto Mono", "style": "Regular"}, "I2:22305;2:16650": {"text": "管理节点", "family": "Noto Sans SC", "style": "Medium"}, "2:22308": {"text": "最近连接", "family": "Noto Sans SC", "style": "Medium"}, "I2:22309;2:16650": {"text": "查看连接", "family": "Noto Sans SC", "style": "Medium"}, "2:22311": {"text": "api.github.com", "family": "Inter", "style": "Regular"}, "I2:22312;2:16682": {"text": "代理", "family": "Noto Sans SC", "style": "Medium"}, "2:22313": {"text": "docs.rs", "family": "Inter", "style": "Regular"}, "I2:22314;2:16682": {"text": "代理", "family": "Noto Sans SC", "style": "Medium"}, "2:22315": {"text": "192.168.1.1", "family": "Inter", "style": "Regular"}, "I2:22316;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "2:22317": {"text": "刚刚更新", "family": "Noto Sans SC", "style": "Regular"}, "2:24415": {"text": "RainLink / 桌面端", "family": "Noto Sans SC", "style": "Bold"}, "2:24416": {"text": "1440 × 900 · Windows / macOS / Linux · 共享组件与语义颜色", "family": "Noto Sans SC", "style": "Regular"}, "2:22552": {"text": "9:41", "family": "Inter", "style": "Semi Bold"}, "2:22559": {"text": "▰", "family": "Inter", "style": "Regular"}, "2:22540": {"text": "RainLink", "family": "Inter", "style": "Medium"}, "2:22541": {"text": "网络连接，顺畅如流。", "family": "Noto Sans SC", "style": "Regular"}, "2:22601": {"text": "已连接", "family": "Noto Sans SC", "style": "Bold"}, "2:22602": {"text": "规则模式 · 已连接 1 小时 42 分钟", "family": "Noto Sans SC", "style": "Regular"}, "2:22605": {"text": "点击断开连接", "family": "Noto Sans SC", "style": "Regular"}, "2:22614": {"text": "当前节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:22606;2:16650": {"text": "切换", "family": "Noto Sans SC", "style": "Medium"}, "I2:22615;2:16749": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:22615;2:16751": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:22615;2:16752": {"text": "东京 · 日本", "family": "Noto Sans SC", "style": "Regular"}, "I2:22615;2:16754": {"text": "VLESS", "family": "Inter", "style": "Medium"}, "I2:22615;2:16759": {"text": "24 ms", "family": "Inter", "style": "Medium"}, "2:22638": {"text": "延迟", "family": "Noto Sans SC", "style": "Regular"}, "2:22640": {"text": "24", "family": "Inter", "style": "Semi Bold"}, "2:22641": {"text": "ms", "family": "Inter", "style": "Regular"}, "2:22647": {"text": "下载", "family": "Noto Sans SC", "style": "Regular"}, "2:22649": {"text": "12.8", "family": "Inter", "style": "Semi Bold"}, "2:22650": {"text": "MB/s", "family": "Inter", "style": "Regular"}, "2:22653": {"text": "今日流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:22654;2:16650": {"text": "查看", "family": "Noto Sans SC", "style": "Medium"}, "2:22662": {"text": "8.42 GB", "family": "Inter", "style": "Semi Bold"}, "2:22663": {"text": "↓ 7.86 GB    ↑ 560 MB", "family": "Inter", "style": "Regular"}, "I2:22560;2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "I2:22560;2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:22560;2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:22560;2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:22560;2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:22677": {"text": "9:41", "family": "Inter", "style": "Semi Bold"}, "2:22684": {"text": "▰", "family": "Inter", "style": "Regular"}, "2:22672": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "2:22673": {"text": "8 个节点 · 7 个在线", "family": "Noto Sans SC", "style": "Regular"}, "I2:22719;2:16702": {"text": "搜索节点或地区…", "family": "Noto Sans SC", "style": "Regular"}, "I2:22727;2:16712": {"text": "全部节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:22729;2:16710": {"text": "收藏", "family": "Noto Sans SC", "style": "Medium"}, "I2:22731;2:16635": {"text": "测速", "family": "Noto Sans SC", "style": "Medium"}, "2:22743": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:22739;2:16682": {"text": "已同步", "family": "Noto Sans SC", "style": "Medium"}, "I2:22744;2:16749": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:22744;2:16751": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:22744;2:16752": {"text": "东京 · 日本", "family": "Noto Sans SC", "style": "Regular"}, "I2:22744;2:16754": {"text": "VLESS", "family": "Inter", "style": "Medium"}, "I2:22744;2:16759": {"text": "24 ms", "family": "Inter", "style": "Medium"}, "I2:22760;2:16733": {"text": "SG", "family": "Inter", "style": "Semi Bold"}, "I2:22760;2:16735": {"text": "新加坡 · 滨海湾", "family": "Noto Sans SC", "style": "Medium"}, "I2:22760;2:16736": {"text": "新加坡 · 新加坡", "family": "Noto Sans SC", "style": "Regular"}, "I2:22760;2:16738": {"text": "Trojan", "family": "Inter", "style": "Medium"}, "I2:22760;2:16743": {"text": "38 ms", "family": "Inter", "style": "Medium"}, "I2:22776;2:16733": {"text": "HK", "family": "Inter", "style": "Semi Bold"}, "I2:22776;2:16735": {"text": "香港 · 维多利亚", "family": "Noto Sans SC", "style": "Medium"}, "I2:22776;2:16736": {"text": "香港 · 中国香港", "family": "Noto Sans SC", "style": "Regular"}, "I2:22776;2:16738": {"text": "Hysteria", "family": "Inter", "style": "Medium"}, "I2:22776;2:16743": {"text": "18 ms", "family": "Inter", "style": "Medium"}, "I2:22792;2:16733": {"text": "KR", "family": "Inter", "style": "Semi Bold"}, "I2:22792;2:16735": {"text": "首尔 · 汉江", "family": "Noto Sans SC", "style": "Medium"}, "I2:22792;2:16736": {"text": "首尔 · 韩国", "family": "Noto Sans SC", "style": "Regular"}, "I2:22792;2:16738": {"text": "TUIC", "family": "Inter", "style": "Medium"}, "I2:22792;2:16743": {"text": "42 ms", "family": "Inter", "style": "Medium"}, "I2:22808;2:16733": {"text": "US", "family": "Inter", "style": "Semi Bold"}, "I2:22808;2:16735": {"text": "洛杉矶 · 太平洋", "family": "Noto Sans SC", "style": "Medium"}, "I2:22808;2:16736": {"text": "洛杉矶 · 美国", "family": "Noto Sans SC", "style": "Regular"}, "I2:22808;2:16738": {"text": "Shadowsocks", "family": "Inter", "style": "Medium"}, "I2:22808;2:16743": {"text": "142 ms", "family": "Inter", "style": "Medium"}, "I2:22824;2:16733": {"text": "DE", "family": "Inter", "style": "Semi Bold"}, "I2:22824;2:16735": {"text": "法兰克福 · 美因", "family": "Noto Sans SC", "style": "Medium"}, "I2:22824;2:16736": {"text": "法兰克福 · 德国", "family": "Noto Sans SC", "style": "Regular"}, "I2:22824;2:16738": {"text": "VMess", "family": "Inter", "style": "Medium"}, "I2:22824;2:16743": {"text": "186 ms", "family": "Inter", "style": "Medium"}, "I2:22840;2:16733": {"text": "GB", "family": "Inter", "style": "Semi Bold"}, "I2:22840;2:16735": {"text": "伦敦 · 泰晤士", "family": "Noto Sans SC", "style": "Medium"}, "I2:22840;2:16736": {"text": "伦敦 · 英国", "family": "Noto Sans SC", "style": "Regular"}, "I2:22840;2:16738": {"text": "SOCKS5", "family": "Inter", "style": "Medium"}, "I2:22840;2:16743": {"text": "— ms", "family": "Inter", "style": "Medium"}, "I2:22856;2:16733": {"text": "NL", "family": "Inter", "style": "Semi Bold"}, "I2:22856;2:16735": {"text": "阿姆斯特丹 · 运河", "family": "Noto Sans SC", "style": "Medium"}, "I2:22856;2:16736": {"text": "阿姆斯特丹 · 荷兰", "family": "Noto Sans SC", "style": "Regular"}, "I2:22856;2:16738": {"text": "HTTP", "family": "Inter", "style": "Medium"}, "I2:22856;2:16743": {"text": "164 ms", "family": "Inter", "style": "Medium"}, "I2:22685;2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "I2:22685;2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:22685;2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:22685;2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:22685;2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:22885": {"text": "9:41", "family": "Inter", "style": "Semi Bold"}, "2:22892": {"text": "▰", "family": "Inter", "style": "Regular"}, "2:22880": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "2:22881": {"text": "集中管理你的配置。", "family": "Noto Sans SC", "style": "Regular"}, "2:22935": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:22936;2:16679": {"text": "YAML", "family": "Noto Sans SC", "style": "Medium"}, "2:22939": {"text": "8 个节点 · 126 条规则", "family": "Noto Sans SC", "style": "Regular"}, "2:22945": {"text": "自动更新 · 每 6 小时", "family": "Noto Sans SC", "style": "Regular"}, "I2:22946;2:16682": {"text": "已选中", "family": "Noto Sans SC", "style": "Medium"}, "2:22957": {"text": "开发环境", "family": "Noto Sans SC", "style": "Medium"}, "I2:22958;2:16679": {"text": "JSON", "family": "Noto Sans SC", "style": "Medium"}, "2:22961": {"text": "4 个节点 · 32 条规则", "family": "Noto Sans SC", "style": "Regular"}, "2:22967": {"text": "今天更新", "family": "Noto Sans SC", "style": "Regular"}, "I2:22968;2:16679": {"text": "可用", "family": "Noto Sans SC", "style": "Medium"}, "2:22979": {"text": "旅行常用", "family": "Noto Sans SC", "style": "Medium"}, "I2:22980;2:16679": {"text": "YAML", "family": "Noto Sans SC", "style": "Medium"}, "2:22983": {"text": "3 个节点 · 48 条规则", "family": "Noto Sans SC", "style": "Regular"}, "2:22989": {"text": "今天更新", "family": "Noto Sans SC", "style": "Regular"}, "I2:22990;2:16679": {"text": "可用", "family": "Noto Sans SC", "style": "Medium"}, "2:22994": {"text": "添加配置", "family": "Noto Sans SC", "style": "Medium"}, "2:23000": {"text": "链接导入", "family": "Noto Sans SC", "style": "Medium"}, "2:23005": {"text": "扫描二维码", "family": "Noto Sans SC", "style": "Medium"}, "2:23006": {"text": "支持 YAML、JSON 和订阅链接。", "family": "Noto Sans SC", "style": "Regular"}, "I2:22893;2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "I2:22893;2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:22893;2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:22893;2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:22893;2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:23022": {"text": "9:41", "family": "Inter", "style": "Semi Bold"}, "2:23029": {"text": "▰", "family": "Inter", "style": "Regular"}, "2:23010": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "2:23011": {"text": "看清流量，掌握用量。", "family": "Noto Sans SC", "style": "Regular"}, "I2:23065;2:16712": {"text": "今日", "family": "Noto Sans SC", "style": "Medium"}, "I2:23067;2:16710": {"text": "本月", "family": "Noto Sans SC", "style": "Medium"}, "2:23070": {"text": "总流量", "family": "Noto Sans SC", "style": "Regular"}, "2:23071": {"text": "8.42 GB", "family": "Inter", "style": "Semi Bold"}, "2:23073": {"text": "↓ 已下载 7.86 GB", "family": "Noto Sans SC", "style": "Regular"}, "2:23074": {"text": "↑ 已上传 560 MB", "family": "Noto Sans SC", "style": "Regular"}, "2:23077": {"text": "流量趋势", "family": "Noto Sans SC", "style": "Medium"}, "I2:23078;2:16682": {"text": "实时", "family": "Noto Sans SC", "style": "Medium"}, "2:23091": {"text": "00:00", "family": "Inter", "style": "Regular"}, "2:23092": {"text": "06:00", "family": "Inter", "style": "Regular"}, "2:23093": {"text": "12:00", "family": "Inter", "style": "Regular"}, "2:23094": {"text": "18:00", "family": "Inter", "style": "Regular"}, "2:23098": {"text": "下载", "family": "Noto Sans SC", "style": "Regular"}, "2:23101": {"text": "上传", "family": "Noto Sans SC", "style": "Regular"}, "2:23103": {"text": "使用排行", "family": "Noto Sans SC", "style": "Medium"}, "2:23105": {"text": "1", "family": "Inter", "style": "Regular"}, "2:23110": {"text": "浏览器", "family": "Noto Sans SC", "style": "Regular"}, "2:23111": {"text": "4.28 GB", "family": "Roboto Mono", "style": "Regular"}, "2:23114": {"text": "2", "family": "Inter", "style": "Regular"}, "2:23119": {"text": "代码编辑器", "family": "Noto Sans SC", "style": "Regular"}, "2:23120": {"text": "2.46 GB", "family": "Roboto Mono", "style": "Regular"}, "2:23123": {"text": "3", "family": "Inter", "style": "Regular"}, "2:23128": {"text": "终端", "family": "Noto Sans SC", "style": "Regular"}, "2:23129": {"text": "1.68 GB", "family": "Roboto Mono", "style": "Regular"}, "I2:23030;2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "I2:23030;2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:23030;2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:23030;2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:23030;2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:23145": {"text": "9:41", "family": "Inter", "style": "Semi Bold"}, "2:23152": {"text": "▰", "family": "Inter", "style": "Regular"}, "2:23133": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:23134": {"text": "小处贴心，日常顺手。", "family": "Noto Sans SC", "style": "Regular"}, "2:23197": {"text": "RainLink", "family": "Inter", "style": "Medium"}, "2:23198": {"text": "版本 1.0.0 · 稳定版", "family": "Noto Sans SC", "style": "Regular"}, "I2:23199;2:16682": {"text": "最新", "family": "Noto Sans SC", "style": "Medium"}, "2:23203": {"text": "偏好设置", "family": "Noto Sans SC", "style": "Regular"}, "2:23212": {"text": "通知", "family": "Noto Sans SC", "style": "Medium"}, "2:23222": {"text": "自动连接", "family": "Noto Sans SC", "style": "Medium"}, "2:23233": {"text": "主题", "family": "Noto Sans SC", "style": "Medium"}, "2:23234": {"text": "深色", "family": "Noto Sans SC", "style": "Regular"}, "8:27539": {"text": "语言", "family": "Noto Sans SC", "style": "Medium"}, "8:27540": {"text": "简体中文（默认）", "family": "Noto Sans SC", "style": "Regular"}, "2:23236": {"text": "网络", "family": "Noto Sans SC", "style": "Regular"}, "2:23247": {"text": "DNS", "family": "Inter", "style": "Medium"}, "2:23248": {"text": "加密 · 自动", "family": "Noto Sans SC", "style": "Regular"}, "2:23260": {"text": "分流模式", "family": "Noto Sans SC", "style": "Medium"}, "2:23261": {"text": "规则模式", "family": "Noto Sans SC", "style": "Regular"}, "2:23263": {"text": "RAINLINK", "family": "Inter", "style": "Regular"}, "2:23276": {"text": "关于与开源许可", "family": "Noto Sans SC", "style": "Medium"}, "2:23277": {"text": "用心打造，开源共享。", "family": "Noto Sans SC", "style": "Regular"}, "2:23288": {"text": "检查更新", "family": "Noto Sans SC", "style": "Medium"}, "I2:23279;2:16682": {"text": "已是最新", "family": "Noto Sans SC", "style": "Medium"}, "2:23290": {"text": "为你的网络而设计。", "family": "Noto Sans SC", "style": "Regular"}, "I2:23153;2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "I2:23153;2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:23153;2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:23153;2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:23153;2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:23306": {"text": "9:41", "family": "Inter", "style": "Semi Bold"}, "2:23313": {"text": "▰", "family": "Inter", "style": "Regular"}, "2:23294": {"text": "RainLink", "family": "Inter", "style": "Medium"}, "2:23295": {"text": "网络连接，顺畅如流。", "family": "Noto Sans SC", "style": "Regular"}, "2:23355": {"text": "准备连接", "family": "Noto Sans SC", "style": "Bold"}, "2:23356": {"text": "点击开始连接。", "family": "Noto Sans SC", "style": "Regular"}, "2:23359": {"text": "配置已就绪", "family": "Noto Sans SC", "style": "Regular"}, "2:23368": {"text": "当前节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:23360;2:16650": {"text": "切换", "family": "Noto Sans SC", "style": "Medium"}, "I2:23369;2:16749": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:23369;2:16751": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:23369;2:16752": {"text": "东京 · 日本", "family": "Noto Sans SC", "style": "Regular"}, "I2:23369;2:16754": {"text": "VLESS", "family": "Inter", "style": "Medium"}, "I2:23369;2:16759": {"text": "24 ms", "family": "Inter", "style": "Medium"}, "2:23392": {"text": "延迟", "family": "Noto Sans SC", "style": "Regular"}, "2:23394": {"text": "—", "family": "Inter", "style": "Semi Bold"}, "2:23395": {"text": "ms", "family": "Inter", "style": "Regular"}, "2:23401": {"text": "下载", "family": "Noto Sans SC", "style": "Regular"}, "2:23403": {"text": "0", "family": "Inter", "style": "Semi Bold"}, "2:23404": {"text": "MB/s", "family": "Inter", "style": "Regular"}, "2:23407": {"text": "今日流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:23408;2:16650": {"text": "查看", "family": "Noto Sans SC", "style": "Medium"}, "2:23416": {"text": "8.42 GB", "family": "Inter", "style": "Semi Bold"}, "2:23417": {"text": "↓ 7.86 GB    ↑ 560 MB", "family": "Inter", "style": "Regular"}, "I2:23314;2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "I2:23314;2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:23314;2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:23314;2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:23314;2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:23433": {"text": "9:41", "family": "Inter", "style": "Semi Bold"}, "2:23440": {"text": "▰", "family": "Inter", "style": "Regular"}, "2:23428": {"text": "切换节点", "family": "Noto Sans SC", "style": "Medium"}, "2:23429": {"text": "选择此刻合适的节点。", "family": "Noto Sans SC", "style": "Regular"}, "I2:23475;2:16702": {"text": "搜索节点…", "family": "Noto Sans SC", "style": "Regular"}, "2:23485": {"text": "推荐", "family": "Noto Sans SC", "style": "Medium"}, "I2:23481;2:16682": {"text": "低延迟", "family": "Noto Sans SC", "style": "Medium"}, "I2:23486;2:16749": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:23486;2:16751": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:23486;2:16752": {"text": "东京 · 日本", "family": "Noto Sans SC", "style": "Regular"}, "I2:23486;2:16754": {"text": "VLESS", "family": "Inter", "style": "Medium"}, "I2:23486;2:16759": {"text": "24 ms", "family": "Inter", "style": "Medium"}, "I2:23502;2:16733": {"text": "SG", "family": "Inter", "style": "Semi Bold"}, "I2:23502;2:16735": {"text": "新加坡 · 滨海湾", "family": "Noto Sans SC", "style": "Medium"}, "I2:23502;2:16736": {"text": "新加坡 · 新加坡", "family": "Noto Sans SC", "style": "Regular"}, "I2:23502;2:16738": {"text": "Trojan", "family": "Inter", "style": "Medium"}, "I2:23502;2:16743": {"text": "38 ms", "family": "Inter", "style": "Medium"}, "I2:23518;2:16733": {"text": "HK", "family": "Inter", "style": "Semi Bold"}, "I2:23518;2:16735": {"text": "香港 · 维多利亚", "family": "Noto Sans SC", "style": "Medium"}, "I2:23518;2:16736": {"text": "香港 · 中国香港", "family": "Noto Sans SC", "style": "Regular"}, "I2:23518;2:16738": {"text": "Hysteria", "family": "Inter", "style": "Medium"}, "I2:23518;2:16743": {"text": "18 ms", "family": "Inter", "style": "Medium"}, "I2:23534;2:16733": {"text": "KR", "family": "Inter", "style": "Semi Bold"}, "I2:23534;2:16735": {"text": "首尔 · 汉江", "family": "Noto Sans SC", "style": "Medium"}, "I2:23534;2:16736": {"text": "首尔 · 韩国", "family": "Noto Sans SC", "style": "Regular"}, "I2:23534;2:16738": {"text": "TUIC", "family": "Inter", "style": "Medium"}, "I2:23534;2:16743": {"text": "42 ms", "family": "Inter", "style": "Medium"}, "2:23556": {"text": "连接顺畅，工作流畅。", "family": "Noto Sans SC", "style": "Medium"}, "2:23557": {"text": "快速测速，为当前网络选择合适的节点。", "family": "Noto Sans SC", "style": "Regular"}, "I2:23558;2:16645": {"text": "全部测速", "family": "Noto Sans SC", "style": "Medium"}, "I2:23441;2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "I2:23441;2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:23441;2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:23441;2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:23441;2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:23581": {"text": "9:41", "family": "Inter", "style": "Semi Bold"}, "2:23588": {"text": "▰", "family": "Inter", "style": "Regular"}, "2:23576": {"text": "添加配置", "family": "Noto Sans SC", "style": "Medium"}, "2:23577": {"text": "导入自己的配置。", "family": "Noto Sans SC", "style": "Regular"}, "I2:23624;2:16712": {"text": "URL", "family": "Noto Sans SC", "style": "Medium"}, "I2:23626;2:16710": {"text": "文件", "family": "Noto Sans SC", "style": "Medium"}, "I2:23628;2:16710": {"text": "粘贴", "family": "Noto Sans SC", "style": "Medium"}, "2:23631": {"text": "订阅链接", "family": "Noto Sans SC", "style": "Regular"}, "I2:23632;2:16702": {"text": "https://example.com/subscription", "family": "Noto Sans SC", "style": "Regular"}, "2:23638": {"text": "请使用可信的节点来源。", "family": "Noto Sans SC", "style": "Regular"}, "2:23642": {"text": "配置名称", "family": "Noto Sans SC", "style": "Regular"}, "I2:23643;2:16702": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Regular"}, "2:23652": {"text": "自动更新", "family": "Noto Sans SC", "style": "Medium"}, "2:23653": {"text": "每 6 小时刷新一次。", "family": "Noto Sans SC", "style": "Regular"}, "2:23662": {"text": "你的连接，由你掌控。", "family": "Noto Sans SC", "style": "Medium"}, "2:23663": {"text": "订阅存储在你的设备上。RainLink 不提供或出售节点。", "family": "Noto Sans SC", "style": "Regular"}, "I2:23664;2:16630": {"text": "导入配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:23671;2:16645": {"text": "扫描二维码", "family": "Noto Sans SC", "style": "Medium"}, "I2:23589;2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "I2:23589;2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:23589;2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:23589;2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:23589;2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:23693": {"text": "9:41", "family": "Inter", "style": "Semi Bold"}, "2:23700": {"text": "▰", "family": "Inter", "style": "Regular"}, "2:23688": {"text": "配置已添加", "family": "Noto Sans SC", "style": "Medium"}, "2:23689": {"text": "准备就绪，随时开始连接。", "family": "Noto Sans SC", "style": "Regular"}, "2:23740": {"text": "一切就绪。", "family": "Noto Sans SC", "style": "Bold"}, "2:23741": {"text": "个人工作区导入成功。", "family": "Noto Sans SC", "style": "Regular"}, "I2:23743;2:16682": {"text": "8 个节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:23746;2:16679": {"text": "126 条规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:23756;2:16682": {"text": "已选中", "family": "Noto Sans SC", "style": "Medium"}, "2:23759": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "2:23760": {"text": "personal.yaml", "family": "Inter", "style": "Regular"}, "2:23761": {"text": "自动更新已开启 · 每 6 小时", "family": "Noto Sans SC", "style": "Regular"}, "2:23767": {"text": "2 分钟前更新", "family": "Noto Sans SC", "style": "Regular"}, "I2:23768;2:16650": {"text": "编辑", "family": "Noto Sans SC", "style": "Medium"}, "I2:23773;2:16630": {"text": "立即连接", "family": "Noto Sans SC", "style": "Medium"}, "I2:23780;2:16645": {"text": "返回配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:23701;2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "I2:23701;2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:23701;2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:23701;2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:23701;2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:23800": {"text": "9:41", "family": "Inter", "style": "Semi Bold"}, "2:23807": {"text": "▰", "family": "Inter", "style": "Regular"}, "2:23795": {"text": "节点详情", "family": "Noto Sans SC", "style": "Medium"}, "2:23796": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Regular"}, "2:23845": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "2:23849": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Bold"}, "I2:23851;2:16682": {"text": "VLESS", "family": "Noto Sans SC", "style": "Medium"}, "I2:23854;2:16679": {"text": "日本 · 东京", "family": "Noto Sans SC", "style": "Medium"}, "I2:23857;2:16682": {"text": "在线", "family": "Noto Sans SC", "style": "Medium"}, "2:23867": {"text": "延迟", "family": "Noto Sans SC", "style": "Regular"}, "2:23869": {"text": "24", "family": "Inter", "style": "Semi Bold"}, "2:23870": {"text": "ms", "family": "Inter", "style": "Regular"}, "2:23877": {"text": "丢包率", "family": "Noto Sans SC", "style": "Regular"}, "2:23879": {"text": "0", "family": "Inter", "style": "Semi Bold"}, "2:23880": {"text": "%", "family": "Inter", "style": "Regular"}, "2:23883": {"text": "协议", "family": "Noto Sans SC", "style": "Regular"}, "2:23884": {"text": "VLESS + TLS", "family": "Inter", "style": "Regular"}, "2:23887": {"text": "传输方式", "family": "Noto Sans SC", "style": "Regular"}, "2:23888": {"text": "WebSocket", "family": "Inter", "style": "Regular"}, "2:23891": {"text": "服务器", "family": "Noto Sans SC", "style": "Regular"}, "2:23892": {"text": "tokyo.example.com", "family": "Roboto Mono", "style": "Regular"}, "2:23895": {"text": "端口", "family": "Noto Sans SC", "style": "Regular"}, "2:23896": {"text": "443", "family": "Inter", "style": "Regular"}, "2:23899": {"text": "上次测速", "family": "Noto Sans SC", "style": "Regular"}, "2:23900": {"text": "刚刚", "family": "Noto Sans SC", "style": "Regular"}, "I2:23901;2:16630": {"text": "使用此节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:23908;2:16645": {"text": "测试延迟", "family": "Noto Sans SC", "style": "Medium"}, "I2:23808;2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "I2:23808;2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:23808;2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:23808;2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:23808;2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:23931": {"text": "9:41", "family": "Inter", "style": "Semi Bold"}, "2:23938": {"text": "▰", "family": "Inter", "style": "Regular"}, "2:23926": {"text": "DNS", "family": "Inter", "style": "Medium"}, "2:23927": {"text": "解析清晰，连接安心。", "family": "Noto Sans SC", "style": "Regular"}, "2:23974": {"text": "解析模式", "family": "Noto Sans SC", "style": "Medium"}, "2:23977": {"text": "自动", "family": "Noto Sans SC", "style": "Medium"}, "2:23978": {"text": "使用当前配置的解析器。", "family": "Noto Sans SC", "style": "Regular"}, "2:23985": {"text": "自定义解析器", "family": "Noto Sans SC", "style": "Medium"}, "2:23986": {"text": "设置首选 DNS 地址。", "family": "Noto Sans SC", "style": "Regular"}, "2:23989": {"text": "首选解析器", "family": "Noto Sans SC", "style": "Regular"}, "I2:23990;2:16702": {"text": "https://dns.example.com/dns-query", "family": "Noto Sans SC", "style": "Regular"}, "2:24000": {"text": "备用解析器", "family": "Noto Sans SC", "style": "Regular"}, "I2:24001;2:16702": {"text": "https://backup.example.com/dns-query", "family": "Noto Sans SC", "style": "Regular"}, "2:24013": {"text": "虚拟 IP", "family": "Noto Sans SC", "style": "Medium"}, "2:24014": {"text": "保持解析与分流一致。", "family": "Noto Sans SC", "style": "Regular"}, "2:24020": {"text": "IPv6 解析", "family": "Noto Sans SC", "style": "Medium"}, "2:24021": {"text": "解析 IPv6 地址。", "family": "Noto Sans SC", "style": "Regular"}, "I2:24024;2:16630": {"text": "保存设置", "family": "Noto Sans SC", "style": "Medium"}, "I2:23939;2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "I2:23939;2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:23939;2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:23939;2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:23939;2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:24046": {"text": "9:41", "family": "Inter", "style": "Semi Bold"}, "2:24053": {"text": "▰", "family": "Inter", "style": "Regular"}, "2:24041": {"text": "扫描二维码", "family": "Noto Sans SC", "style": "Medium"}, "2:24042": {"text": "导入自己的配置或节点。", "family": "Noto Sans SC", "style": "Regular"}, "2:24094": {"text": "将二维码对准取景框。", "family": "Noto Sans SC", "style": "Regular"}, "2:24095": {"text": "仅在扫码时，RainLink 才会请求相机权限。你也可以导入链接或本地文件。", "family": "Noto Sans SC", "style": "Regular"}, "I2:24096;2:16630": {"text": "演示：扫描配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:24103;2:16645": {"text": "改用链接导入", "family": "Noto Sans SC", "style": "Medium"}, "I2:24054;2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "I2:24054;2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:24054;2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:24054;2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:24054;2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:24125": {"text": "9:41", "family": "Inter", "style": "Semi Bold"}, "2:24132": {"text": "▰", "family": "Inter", "style": "Regular"}, "2:24113": {"text": "RainLink", "family": "Inter", "style": "Medium"}, "2:24114": {"text": "网络连接，顺畅如流。", "family": "Noto Sans SC", "style": "Regular"}, "2:24174": {"text": "已连接", "family": "Noto Sans SC", "style": "Bold"}, "2:24175": {"text": "规则模式 · 已连接 1 小时 42 分钟", "family": "Noto Sans SC", "style": "Regular"}, "2:24178": {"text": "点击断开连接", "family": "Noto Sans SC", "style": "Regular"}, "2:24187": {"text": "当前节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:24179;2:16650": {"text": "切换", "family": "Noto Sans SC", "style": "Medium"}, "I2:24188;2:16749": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:24188;2:16751": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:24188;2:16752": {"text": "东京 · 日本", "family": "Noto Sans SC", "style": "Regular"}, "I2:24188;2:16754": {"text": "VLESS", "family": "Inter", "style": "Medium"}, "I2:24188;2:16759": {"text": "24 ms", "family": "Inter", "style": "Medium"}, "2:24211": {"text": "延迟", "family": "Noto Sans SC", "style": "Regular"}, "2:24213": {"text": "24", "family": "Inter", "style": "Semi Bold"}, "2:24214": {"text": "ms", "family": "Inter", "style": "Regular"}, "2:24220": {"text": "下载", "family": "Noto Sans SC", "style": "Regular"}, "2:24222": {"text": "12.8", "family": "Inter", "style": "Semi Bold"}, "2:24223": {"text": "MB/s", "family": "Inter", "style": "Regular"}, "2:24226": {"text": "今日流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:24227;2:16650": {"text": "查看", "family": "Noto Sans SC", "style": "Medium"}, "2:24235": {"text": "8.42 GB", "family": "Inter", "style": "Semi Bold"}, "2:24236": {"text": "↓ 7.86 GB    ↑ 560 MB", "family": "Inter", "style": "Regular"}, "I2:24133;2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "I2:24133;2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:24133;2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:24133;2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:24133;2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:24252": {"text": "9:41", "family": "Inter", "style": "Semi Bold"}, "2:24259": {"text": "▰", "family": "Inter", "style": "Regular"}, "2:24240": {"text": "RainLink", "family": "Inter", "style": "Medium"}, "2:24241": {"text": "网络连接，顺畅如流。", "family": "Noto Sans SC", "style": "Regular"}, "2:24301": {"text": "连接中断", "family": "Noto Sans SC", "style": "Bold"}, "2:24302": {"text": "上次使用的节点未响应。", "family": "Noto Sans SC", "style": "Regular"}, "2:24305": {"text": "尝试其他节点", "family": "Noto Sans SC", "style": "Regular"}, "2:24314": {"text": "当前节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:24306;2:16650": {"text": "切换", "family": "Noto Sans SC", "style": "Medium"}, "I2:24315;2:16749": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:24315;2:16751": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:24315;2:16752": {"text": "东京 · 日本", "family": "Noto Sans SC", "style": "Regular"}, "I2:24315;2:16754": {"text": "VLESS", "family": "Inter", "style": "Medium"}, "I2:24315;2:16759": {"text": "24 ms", "family": "Inter", "style": "Medium"}, "2:24338": {"text": "延迟", "family": "Noto Sans SC", "style": "Regular"}, "2:24340": {"text": "—", "family": "Inter", "style": "Semi Bold"}, "2:24341": {"text": "ms", "family": "Inter", "style": "Regular"}, "2:24347": {"text": "下载", "family": "Noto Sans SC", "style": "Regular"}, "2:24349": {"text": "0", "family": "Inter", "style": "Semi Bold"}, "2:24350": {"text": "MB/s", "family": "Inter", "style": "Regular"}, "2:24353": {"text": "今日流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:24354;2:16650": {"text": "查看", "family": "Noto Sans SC", "style": "Medium"}, "2:24362": {"text": "8.42 GB", "family": "Inter", "style": "Semi Bold"}, "2:24363": {"text": "↓ 7.86 GB    ↑ 560 MB", "family": "Inter", "style": "Regular"}, "I2:24260;2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "I2:24260;2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:24260;2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:24260;2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:24260;2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:24366": {"text": "9:41", "family": "Inter", "style": "Semi Bold"}, "2:24370": {"text": "▰", "family": "Inter", "style": "Regular"}, "2:24373": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "2:24374": {"text": "8 个节点 · 7 个在线", "family": "Noto Sans SC", "style": "Regular"}, "I2:24403;2:16682": {"text": "测速完成 · 7 个在线", "family": "Noto Sans SC", "style": "Medium"}, "I2:24378;2:16702": {"text": "搜索节点或地区…", "family": "Noto Sans SC", "style": "Regular"}, "I2:24381;2:16712": {"text": "全部节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:24382;2:16710": {"text": "收藏", "family": "Noto Sans SC", "style": "Medium"}, "I2:24383;2:16635": {"text": "测速", "family": "Noto Sans SC", "style": "Medium"}, "2:24385": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "I2:24386;2:16682": {"text": "已同步", "family": "Noto Sans SC", "style": "Medium"}, "I2:24387;2:16749": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:24387;2:16751": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:24387;2:16752": {"text": "东京 · 日本", "family": "Noto Sans SC", "style": "Regular"}, "I2:24387;2:16754": {"text": "VLESS", "family": "Inter", "style": "Medium"}, "I2:24387;2:16759": {"text": "24 ms", "family": "Inter", "style": "Medium"}, "I2:24388;2:16733": {"text": "SG", "family": "Inter", "style": "Semi Bold"}, "I2:24388;2:16735": {"text": "新加坡 · 滨海湾", "family": "Noto Sans SC", "style": "Medium"}, "I2:24388;2:16736": {"text": "新加坡 · 新加坡", "family": "Noto Sans SC", "style": "Regular"}, "I2:24388;2:16738": {"text": "Trojan", "family": "Inter", "style": "Medium"}, "I2:24388;2:16743": {"text": "38 ms", "family": "Inter", "style": "Medium"}, "I2:24389;2:16733": {"text": "HK", "family": "Inter", "style": "Semi Bold"}, "I2:24389;2:16735": {"text": "香港 · 维多利亚", "family": "Noto Sans SC", "style": "Medium"}, "I2:24389;2:16736": {"text": "香港 · 中国香港", "family": "Noto Sans SC", "style": "Regular"}, "I2:24389;2:16738": {"text": "Hysteria", "family": "Inter", "style": "Medium"}, "I2:24389;2:16743": {"text": "18 ms", "family": "Inter", "style": "Medium"}, "I2:24390;2:16733": {"text": "KR", "family": "Inter", "style": "Semi Bold"}, "I2:24390;2:16735": {"text": "首尔 · 汉江", "family": "Noto Sans SC", "style": "Medium"}, "I2:24390;2:16736": {"text": "首尔 · 韩国", "family": "Noto Sans SC", "style": "Regular"}, "I2:24390;2:16738": {"text": "TUIC", "family": "Inter", "style": "Medium"}, "I2:24390;2:16743": {"text": "42 ms", "family": "Inter", "style": "Medium"}, "I2:24391;2:16733": {"text": "US", "family": "Inter", "style": "Semi Bold"}, "I2:24391;2:16735": {"text": "洛杉矶 · 太平洋", "family": "Noto Sans SC", "style": "Medium"}, "I2:24391;2:16736": {"text": "洛杉矶 · 美国", "family": "Noto Sans SC", "style": "Regular"}, "I2:24391;2:16738": {"text": "Shadowsocks", "family": "Inter", "style": "Medium"}, "I2:24391;2:16743": {"text": "142 ms", "family": "Inter", "style": "Medium"}, "I2:24392;2:16733": {"text": "DE", "family": "Inter", "style": "Semi Bold"}, "I2:24392;2:16735": {"text": "法兰克福 · 美因", "family": "Noto Sans SC", "style": "Medium"}, "I2:24392;2:16736": {"text": "法兰克福 · 德国", "family": "Noto Sans SC", "style": "Regular"}, "I2:24392;2:16738": {"text": "VMess", "family": "Inter", "style": "Medium"}, "I2:24392;2:16743": {"text": "186 ms", "family": "Inter", "style": "Medium"}, "I2:24393;2:16733": {"text": "GB", "family": "Inter", "style": "Semi Bold"}, "I2:24393;2:16735": {"text": "伦敦 · 泰晤士", "family": "Noto Sans SC", "style": "Medium"}, "I2:24393;2:16736": {"text": "伦敦 · 英国", "family": "Noto Sans SC", "style": "Regular"}, "I2:24393;2:16738": {"text": "SOCKS5", "family": "Inter", "style": "Medium"}, "I2:24393;2:16743": {"text": "— ms", "family": "Inter", "style": "Medium"}, "I2:24394;2:16733": {"text": "NL", "family": "Inter", "style": "Semi Bold"}, "I2:24394;2:16735": {"text": "阿姆斯特丹 · 运河", "family": "Noto Sans SC", "style": "Medium"}, "I2:24394;2:16736": {"text": "阿姆斯特丹 · 荷兰", "family": "Noto Sans SC", "style": "Regular"}, "I2:24394;2:16738": {"text": "HTTP", "family": "Inter", "style": "Medium"}, "I2:24394;2:16743": {"text": "164 ms", "family": "Inter", "style": "Medium"}, "I2:24395;2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "I2:24395;2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:24395;2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:24395;2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:24395;2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:24426": {"text": "RainLink / 移动端", "family": "Noto Sans SC", "style": "Bold"}, "2:24427": {"text": "393 × 852 · iPhone 15 Pro · iOS / Android · 内容可滚动，底部导航固定", "family": "Noto Sans SC", "style": "Regular"}, "2:16620": {"text": "按钮", "family": "Noto Sans SC", "style": "Medium"}, "2:16625": {"text": "按钮", "family": "Noto Sans SC", "style": "Medium"}, "2:16630": {"text": "按钮", "family": "Noto Sans SC", "style": "Medium"}, "2:16635": {"text": "按钮", "family": "Noto Sans SC", "style": "Medium"}, "2:16640": {"text": "按钮", "family": "Noto Sans SC", "style": "Medium"}, "2:16645": {"text": "按钮", "family": "Noto Sans SC", "style": "Medium"}, "2:16650": {"text": "按钮", "family": "Noto Sans SC", "style": "Medium"}, "2:16655": {"text": "按钮", "family": "Noto Sans SC", "style": "Medium"}, "2:16660": {"text": "按钮", "family": "Noto Sans SC", "style": "Medium"}, "2:16665": {"text": "按钮", "family": "Noto Sans SC", "style": "Medium"}, "2:16670": {"text": "按钮", "family": "Noto Sans SC", "style": "Medium"}, "2:16675": {"text": "按钮", "family": "Noto Sans SC", "style": "Medium"}, "2:16679": {"text": "中性", "family": "Noto Sans SC", "style": "Medium"}, "2:16682": {"text": "成功", "family": "Noto Sans SC", "style": "Medium"}, "2:16685": {"text": "警告", "family": "Noto Sans SC", "style": "Medium"}, "2:16688": {"text": "错误", "family": "Noto Sans SC", "style": "Medium"}, "2:16691": {"text": "信息", "family": "Noto Sans SC", "style": "Medium"}, "2:16702": {"text": "搜索节点…", "family": "Noto Sans SC", "style": "Regular"}, "2:16708": {"text": "搜索节点…", "family": "Noto Sans SC", "style": "Regular"}, "2:16710": {"text": "标签页", "family": "Noto Sans SC", "style": "Medium"}, "2:16712": {"text": "标签页", "family": "Noto Sans SC", "style": "Medium"}, "2:16720": {"text": "概览", "family": "Noto Sans SC", "style": "Regular"}, "2:16721": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "2:16729": {"text": "概览", "family": "Noto Sans SC", "style": "Medium"}, "2:16730": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "2:16733": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "2:16735": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "2:16736": {"text": "东京 · 日本", "family": "Noto Sans SC", "style": "Regular"}, "2:16738": {"text": "VLESS", "family": "Inter", "style": "Medium"}, "2:16743": {"text": "24 ms", "family": "Inter", "style": "Medium"}, "2:16749": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "2:16751": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "2:16752": {"text": "东京 · 日本", "family": "Noto Sans SC", "style": "Regular"}, "2:16754": {"text": "VLESS", "family": "Inter", "style": "Medium"}, "2:16759": {"text": "24 ms", "family": "Inter", "style": "Medium"}, "2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "2:16788": {"text": "卡片标题", "family": "Noto Sans SC", "style": "Medium"}, "2:16789": {"text": "集中呈现相关信息的容器。", "family": "Noto Sans SC", "style": "Regular"}, "2:16792": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:16829": {"text": "导入订阅", "family": "Noto Sans SC", "style": "Bold"}, "2:16833": {"text": "添加你自己的订阅链接。", "family": "Noto Sans SC", "style": "Regular"}, "2:16835": {"text": "订阅链接", "family": "Noto Sans SC", "style": "Regular"}, "I2:16836;2:16702": {"text": "https://example.com/subscription", "family": "Noto Sans SC", "style": "Regular"}, "2:16845": {"text": "配置名称", "family": "Noto Sans SC", "style": "Regular"}, "I2:16846;2:16702": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Regular"}, "2:16853": {"text": "每 6 小时自动更新", "family": "Noto Sans SC", "style": "Regular"}, "I2:16857;2:16655": {"text": "取消", "family": "Noto Sans SC", "style": "Medium"}, "I2:16862;2:16625": {"text": "导入配置", "family": "Noto Sans SC", "style": "Medium"}, "2:16869": {"text": "组件", "family": "Noto Sans SC", "style": "Bold"}, "2:16870": {"text": "原生组件 · 语义颜色绑定 · 可编辑矢量 · 桌面端与移动端共享", "family": "Noto Sans SC", "style": "Regular"}, "2:16871": {"text": "网格", "family": "Noto Sans SC", "style": "Regular"}, "2:16872": {"text": "节点", "family": "Noto Sans SC", "style": "Regular"}, "2:16873": {"text": "配置", "family": "Noto Sans SC", "style": "Regular"}, "2:16874": {"text": "规则", "family": "Noto Sans SC", "style": "Regular"}, "2:16875": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "2:16876": {"text": "图表", "family": "Noto Sans SC", "style": "Regular"}, "2:16877": {"text": "终端", "family": "Noto Sans SC", "style": "Regular"}, "2:16878": {"text": "设置", "family": "Noto Sans SC", "style": "Regular"}, "2:16879": {"text": "搜索", "family": "Noto Sans SC", "style": "Regular"}, "2:16880": {"text": "展开箭头", "family": "Noto Sans SC", "style": "Regular"}, "2:16881": {"text": "向下", "family": "Noto Sans SC", "style": "Regular"}, "2:16882": {"text": "添加", "family": "Noto Sans SC", "style": "Regular"}, "2:16883": {"text": "确认", "family": "Noto Sans SC", "style": "Regular"}, "2:16884": {"text": "关闭", "family": "Noto Sans SC", "style": "Regular"}, "2:16885": {"text": "收藏星标", "family": "Noto Sans SC", "style": "Regular"}, "2:16886": {"text": "电源", "family": "Noto Sans SC", "style": "Regular"}, "2:16887": {"text": "下载", "family": "Noto Sans SC", "style": "Regular"}, "2:16888": {"text": "上传", "family": "Noto Sans SC", "style": "Regular"}, "2:16889": {"text": "测速", "family": "Noto Sans SC", "style": "Regular"}, "2:16890": {"text": "地球", "family": "Noto Sans SC", "style": "Regular"}, "2:16891": {"text": "盾牌", "family": "Noto Sans SC", "style": "Regular"}, "2:16892": {"text": "通知铃", "family": "Noto Sans SC", "style": "Regular"}, "2:16893": {"text": "太阳", "family": "Noto Sans SC", "style": "Regular"}, "2:16894": {"text": "月亮", "family": "Noto Sans SC", "style": "Regular"}, "2:16895": {"text": "刷新", "family": "Noto Sans SC", "style": "Regular"}, "2:16896": {"text": "二维码", "family": "Noto Sans SC", "style": "Regular"}, "2:16897": {"text": "链路", "family": "Noto Sans SC", "style": "Regular"}, "2:16898": {"text": "复制", "family": "Noto Sans SC", "style": "Regular"}, "2:16899": {"text": "更多", "family": "Noto Sans SC", "style": "Regular"}, "2:16900": {"text": "时钟", "family": "Noto Sans SC", "style": "Regular"}, "2:16901": {"text": "文件夹", "family": "Noto Sans SC", "style": "Regular"}, "2:16902": {"text": "箭头", "family": "Noto Sans SC", "style": "Regular"}, "2:16903": {"text": "笔记本", "family": "Noto Sans SC", "style": "Regular"}, "2:16904": {"text": "无线网络", "family": "Noto Sans SC", "style": "Regular"}, "2:16905": {"text": "雨滴", "family": "Noto Sans SC", "style": "Regular"}, "2:16906": {"text": "品牌 / 标志", "family": "Noto Sans SC", "style": "Regular"}, "2:16907": {"text": "按钮 / 样式与尺寸变体", "family": "Noto Sans SC", "style": "Regular"}, "2:16908": {"text": "状态标记 / 语义类型", "family": "Noto Sans SC", "style": "Regular"}, "2:16909": {"text": "开关 / 关闭", "family": "Noto Sans SC", "style": "Regular"}, "2:16910": {"text": "开关 / 开启", "family": "Noto Sans SC", "style": "Regular"}, "2:16911": {"text": "输入框 / 默认", "family": "Noto Sans SC", "style": "Regular"}, "2:16912": {"text": "输入框 / 聚焦", "family": "Noto Sans SC", "style": "Regular"}, "2:16913": {"text": "标签页 / 默认", "family": "Noto Sans SC", "style": "Regular"}, "2:16914": {"text": "标签页 / 选中", "family": "Noto Sans SC", "style": "Regular"}, "2:16915": {"text": "导航 / 默认", "family": "Noto Sans SC", "style": "Regular"}, "2:16916": {"text": "导航 / 选中", "family": "Noto Sans SC", "style": "Regular"}, "2:16917": {"text": "节点卡片 / 默认", "family": "Noto Sans SC", "style": "Regular"}, "2:16918": {"text": "节点卡片 / 选中", "family": "Noto Sans SC", "style": "Regular"}, "2:16919": {"text": "图表 / 延迟", "family": "Noto Sans SC", "style": "Regular"}, "2:16920": {"text": "图表 / 流量", "family": "Noto Sans SC", "style": "Regular"}, "2:16921": {"text": "下拉选择 / 节点", "family": "Noto Sans SC", "style": "Regular"}, "2:16922": {"text": "卡片 / 基础", "family": "Noto Sans SC", "style": "Regular"}, "2:16923": {"text": "状态 / 已连接", "family": "Noto Sans SC", "style": "Regular"}, "2:16924": {"text": "移动端 / 底部导航", "family": "Noto Sans SC", "style": "Regular"}, "2:16925": {"text": "弹窗 / 导入订阅", "family": "Noto Sans SC", "style": "Regular"}, "2:16936": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "I2:16937;2:16682": {"text": "设计系统 · 1.0", "family": "Noto Sans SC", "style": "Medium"}, "2:16940": {"text": "每一次连接，都清晰可见。", "family": "Noto Sans SC", "style": "Medium"}, "2:16941": {"text": "为关注网络细节的用户打造。深墨色界面、柔和薄荷色提示，两端共享统一的设计语言。", "family": "Noto Sans SC", "style": "Regular"}, "2:16944": {"text": "01 / 克制", "family": "Noto Sans SC", "style": "Medium"}, "2:16945": {"text": "颜色传达状态，克制使用装饰。", "family": "Noto Sans SC", "style": "Regular"}, "2:16947": {"text": "02 / 精确", "family": "Noto Sans SC", "style": "Medium"}, "2:16948": {"text": "指标清晰，分流明确。", "family": "Noto Sans SC", "style": "Regular"}, "2:16950": {"text": "03 / 连接", "family": "Noto Sans SC", "style": "Medium"}, "2:16951": {"text": "每个页面，共享一套组件语言。", "family": "Noto Sans SC", "style": "Regular"}, "2:16953": {"text": "语义颜色变量", "family": "Noto Sans SC", "style": "Bold"}, "2:16956": {"text": "深色基础", "family": "Noto Sans SC", "style": "Medium"}, "2:16960": {"text": "背景", "family": "Noto Sans SC", "style": "Medium"}, "2:16961": {"text": "#0B1015", "family": "Roboto Mono", "style": "Regular"}, "2:16964": {"text": "界面表层", "family": "Noto Sans SC", "style": "Medium"}, "2:16965": {"text": "#121A22", "family": "Roboto Mono", "style": "Regular"}, "2:16968": {"text": "主色", "family": "Noto Sans SC", "style": "Medium"}, "2:16969": {"text": "#86E5C3", "family": "Roboto Mono", "style": "Regular"}, "2:16973": {"text": "成功", "family": "Noto Sans SC", "style": "Medium"}, "2:16974": {"text": "#86E5C3", "family": "Roboto Mono", "style": "Regular"}, "2:16977": {"text": "警告", "family": "Noto Sans SC", "style": "Medium"}, "2:16978": {"text": "#E7BD7D", "family": "Roboto Mono", "style": "Regular"}, "2:16981": {"text": "错误", "family": "Noto Sans SC", "style": "Medium"}, "2:16982": {"text": "#F28F9D", "family": "Roboto Mono", "style": "Regular"}, "2:16984": {"text": "浅色扩展", "family": "Noto Sans SC", "style": "Medium"}, "2:16988": {"text": "背景", "family": "Noto Sans SC", "style": "Medium"}, "2:16989": {"text": "#F3F6F7", "family": "Roboto Mono", "style": "Regular"}, "2:16992": {"text": "界面表层", "family": "Noto Sans SC", "style": "Medium"}, "2:16993": {"text": "#FFFFFF", "family": "Roboto Mono", "style": "Regular"}, "2:16996": {"text": "主色", "family": "Noto Sans SC", "style": "Medium"}, "2:16997": {"text": "#127D63", "family": "Roboto Mono", "style": "Regular"}, "2:17001": {"text": "成功", "family": "Noto Sans SC", "style": "Medium"}, "2:17002": {"text": "#127D63", "family": "Roboto Mono", "style": "Regular"}, "2:17005": {"text": "警告", "family": "Noto Sans SC", "style": "Medium"}, "2:17006": {"text": "#97600E", "family": "Roboto Mono", "style": "Regular"}, "2:17009": {"text": "错误", "family": "Noto Sans SC", "style": "Medium"}, "2:17010": {"text": "#BA3651", "family": "Roboto Mono", "style": "Regular"}, "2:17014": {"text": "字体 / 思源黑体与等宽字体", "family": "Noto Sans SC", "style": "Bold"}, "2:17016": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "2:17017": {"text": "展示标题 · 40 / 58", "family": "Noto Sans SC", "style": "Regular"}, "2:17019": {"text": "网络连接，顺畅如流。", "family": "Noto Sans SC", "style": "Bold"}, "2:17020": {"text": "页面标题 · 28 / 41", "family": "Noto Sans SC", "style": "Regular"}, "2:17022": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Bold"}, "2:17023": {"text": "区块标题 · 20 / 29", "family": "Noto Sans SC", "style": "Regular"}, "2:17025": {"text": "清晰掌握网络状态。", "family": "Noto Sans SC", "style": "Regular"}, "2:17026": {"text": "正文 · 14 / 20", "family": "Noto Sans SC", "style": "Regular"}, "2:17028": {"text": "细节克制，状态清晰。", "family": "Noto Sans SC", "style": "Regular"}, "2:17029": {"text": "说明 · 12 / 17", "family": "Noto Sans SC", "style": "Regular"}, "2:17031": {"text": "间距 / 4 px 基准", "family": "Noto Sans SC", "style": "Bold"}, "2:17032": {"text": "4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64", "family": "Inter", "style": "Regular"}, "2:17036": {"text": "8", "family": "Inter", "style": "Regular"}, "2:17039": {"text": "16", "family": "Inter", "style": "Regular"}, "2:17042": {"text": "24", "family": "Inter", "style": "Regular"}, "2:17045": {"text": "32", "family": "Inter", "style": "Regular"}, "2:17048": {"text": "48", "family": "Inter", "style": "Regular"}, "2:17051": {"text": "64", "family": "Inter", "style": "Regular"}, "2:17052": {"text": "圆角 / 控件 8 · 列表行 12 · 卡片 16 · 浮层 24", "family": "Noto Sans SC", "style": "Regular"}, "2:17053": {"text": "桌面端 / 侧栏 248 · 内容边距 36 · 列间距 24", "family": "Noto Sans SC", "style": "Regular"}, "2:17054": {"text": "移动端 / 两侧边距 20 · 最小触控区域 44", "family": "Noto Sans SC", "style": "Regular"}, "2:17058": {"text": "动效 / 轻柔、明确", "family": "Noto Sans SC", "style": "Medium"}, "2:17059": {"text": "页面导航 180 ms 缓出 · 节点切换 220 ms · 底部面板 240 ms", "family": "Noto Sans SC", "style": "Regular"}, "2:17060": {"text": "状态变化使用智能动画，页面导航使用短暂淡入淡出。开启减少动态效果后，采用 100 ms 渐变。", "family": "Noto Sans SC", "style": "Regular"}, "2:17062": {"text": "状态表达，不只依赖颜色", "family": "Noto Sans SC", "style": "Medium"}, "2:17063": {"text": "每一种状态颜色，都配合文字或图标。", "family": "Noto Sans SC", "style": "Regular"}, "2:17064": {"text": "可见聚焦环 · 清晰的 12 px 说明文字 · 44 px 移动端触控区 · 保留安全区域 · 支持键盘命令面板", "family": "Noto Sans SC", "style": "Regular"}, "2:17065": {"text": "所有数值均为原生 Figma 变量或可编辑组件。网络数据为示例，不包含真实订阅或账户信息。", "family": "Noto Sans SC", "style": "Regular"}, "2:24904": {"text": "RainLink", "family": "Inter", "style": "Semi Bold"}, "2:24914": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Medium"}, "2:24921": {"text": "工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:24924;2:16729": {"text": "概览", "family": "Noto Sans SC", "style": "Medium"}, "I2:24924;2:16730": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:24925;2:16720": {"text": "节点", "family": "Noto Sans SC", "style": "Regular"}, "I2:24925;2:16721": {"text": "2", "family": "Roboto Mono", "style": "Regular"}, "I2:24926;2:16720": {"text": "配置", "family": "Noto Sans SC", "style": "Regular"}, "I2:24926;2:16721": {"text": "3", "family": "Roboto Mono", "style": "Regular"}, "I2:24927;2:16720": {"text": "规则", "family": "Noto Sans SC", "style": "Regular"}, "I2:24927;2:16721": {"text": "4", "family": "Roboto Mono", "style": "Regular"}, "I2:24928;2:16720": {"text": "连接", "family": "Noto Sans SC", "style": "Regular"}, "I2:24928;2:16721": {"text": "5", "family": "Roboto Mono", "style": "Regular"}, "I2:24929;2:16720": {"text": "流量", "family": "Noto Sans SC", "style": "Regular"}, "I2:24929;2:16721": {"text": "6", "family": "Roboto Mono", "style": "Regular"}, "I2:24930;2:16720": {"text": "日志", "family": "Noto Sans SC", "style": "Regular"}, "I2:24930;2:16721": {"text": "7", "family": "Roboto Mono", "style": "Regular"}, "I2:24931;2:16720": {"text": "设置", "family": "Noto Sans SC", "style": "Regular"}, "I2:24931;2:16721": {"text": "8", "family": "Roboto Mono", "style": "Regular"}, "2:24989": {"text": "规则模式", "family": "Noto Sans SC", "style": "Medium"}, "2:24990": {"text": "智能分流已启用。", "family": "Noto Sans SC", "style": "Regular"}, "I2:24992;2:16682": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "I2:24993;2:16679": {"text": "全局", "family": "Noto Sans SC", "style": "Medium"}, "I2:24994;2:16679": {"text": "直连", "family": "Noto Sans SC", "style": "Medium"}, "2:24996": {"text": "RainLink 1.0.0", "family": "Inter", "style": "Regular"}, "I2:24997;2:16682": {"text": "核心就绪", "family": "Noto Sans SC", "style": "Medium"}, "2:27047": {"text": "原型流程", "family": "Noto Sans SC", "style": "Bold"}, "2:27048": {"text": "两端一致，操作熟悉。", "family": "Noto Sans SC", "style": "Medium"}, "2:27049": {"text": "桌面端和移动端页面已连接交互。使用演示模式中的命名流程开始体验。", "family": "Noto Sans SC", "style": "Regular"}, "2:27052": {"text": "桌面端 / 连接与切换", "family": "Noto Sans SC", "style": "Medium"}, "I2:27053;2:16682": {"text": "点击 · 180 ms", "family": "Noto Sans SC", "style": "Medium"}, "2:27058": {"text": "01", "family": "Inter", "style": "Medium"}, "2:27059": {"text": "未连接", "family": "Noto Sans SC", "style": "Medium"}, "2:27064": {"text": "02", "family": "Inter", "style": "Medium"}, "2:27065": {"text": "概览", "family": "Noto Sans SC", "style": "Medium"}, "2:27070": {"text": "03", "family": "Inter", "style": "Medium"}, "2:27071": {"text": "快速切换", "family": "Noto Sans SC", "style": "Medium"}, "2:27076": {"text": "04", "family": "Inter", "style": "Medium"}, "2:27077": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "2:27082": {"text": "05", "family": "Inter", "style": "Medium"}, "2:27083": {"text": "概览", "family": "Noto Sans SC", "style": "Medium"}, "2:27084": {"text": "连接 → 查看网络状态 → 切换节点 → 查看节点列表。", "family": "Noto Sans SC", "style": "Regular"}, "2:27087": {"text": "桌面端 / 导入与配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:27088;2:16682": {"text": "点击 · 180 ms", "family": "Noto Sans SC", "style": "Medium"}, "2:27093": {"text": "01", "family": "Inter", "style": "Medium"}, "2:27094": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "2:27099": {"text": "02", "family": "Inter", "style": "Medium"}, "2:27100": {"text": "导入配置", "family": "Noto Sans SC", "style": "Medium"}, "2:27105": {"text": "03", "family": "Inter", "style": "Medium"}, "2:27106": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "2:27111": {"text": "04", "family": "Inter", "style": "Medium"}, "2:27112": {"text": "配置编辑器", "family": "Noto Sans SC", "style": "Medium"}, "2:27117": {"text": "05", "family": "Inter", "style": "Medium"}, "2:27118": {"text": "规则", "family": "Noto Sans SC", "style": "Medium"}, "2:27119": {"text": "导入可信链接 → 编辑 YAML / JSON → 调整分流。", "family": "Noto Sans SC", "style": "Regular"}, "2:27122": {"text": "移动端 / 日常连接", "family": "Noto Sans SC", "style": "Medium"}, "I2:27123;2:16682": {"text": "点击 · 180 ms", "family": "Noto Sans SC", "style": "Medium"}, "2:27128": {"text": "01", "family": "Inter", "style": "Medium"}, "2:27129": {"text": "未连接", "family": "Noto Sans SC", "style": "Medium"}, "2:27134": {"text": "02", "family": "Inter", "style": "Medium"}, "2:27135": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "2:27140": {"text": "03", "family": "Inter", "style": "Medium"}, "2:27141": {"text": "快速切换", "family": "Noto Sans SC", "style": "Medium"}, "2:27146": {"text": "04", "family": "Inter", "style": "Medium"}, "2:27147": {"text": "节点详情", "family": "Noto Sans SC", "style": "Medium"}, "2:27152": {"text": "05", "family": "Inter", "style": "Medium"}, "2:27153": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "2:27154": {"text": "点击连接 → 选择节点 → 查看协议和延迟。", "family": "Noto Sans SC", "style": "Regular"}, "2:27157": {"text": "移动端 / 导入你的配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:27158;2:16682": {"text": "点击 · 180 ms", "family": "Noto Sans SC", "style": "Medium"}, "2:27163": {"text": "01", "family": "Inter", "style": "Medium"}, "2:27164": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "2:27169": {"text": "02", "family": "Inter", "style": "Medium"}, "2:27170": {"text": "导入配置", "family": "Noto Sans SC", "style": "Medium"}, "2:27175": {"text": "03", "family": "Inter", "style": "Medium"}, "2:27176": {"text": "导入成功", "family": "Noto Sans SC", "style": "Medium"}, "2:27181": {"text": "04", "family": "Inter", "style": "Medium"}, "2:27182": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "2:27187": {"text": "05", "family": "Inter", "style": "Medium"}, "2:27188": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "2:27189": {"text": "链接导入 → 确认导入成功 → 连接并查看用量。", "family": "Noto Sans SC", "style": "Regular"}, "2:27192": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "2:27193": {"text": "就绪 → 已连接 → 未连接 → 重试", "family": "Noto Sans SC", "style": "Regular"}, "2:27194": {"text": "移动端的大型连接按钮与桌面端的常驻状态栏使用相同的状态文案。", "family": "Noto Sans SC", "style": "Regular"}, "2:27196": {"text": "节点测速", "family": "Noto Sans SC", "style": "Medium"}, "2:27197": {"text": "在线 · 低延迟 · 超时", "family": "Noto Sans SC", "style": "Regular"}, "2:27198": {"text": "测速结果提供明确反馈，并保留当前选中的节点。", "family": "Noto Sans SC", "style": "Regular"}, "2:27200": {"text": "导入", "family": "Noto Sans SC", "style": "Medium"}, "2:27201": {"text": "输入 → 校验 → 已添加", "family": "Noto Sans SC", "style": "Regular"}, "2:27202": {"text": "明确展示导入成功状态，再开始连接。", "family": "Noto Sans SC", "style": "Regular"}, "2:27203": {"text": "原型数据仅为示例。扫码和测速通过明确的演示状态呈现。", "family": "Noto Sans SC", "style": "Regular"}, "2:27206": {"text": "按钮", "family": "Noto Sans SC", "style": "Medium"}, "2:27207": {"text": "禁用按钮", "family": "Noto Sans SC", "style": "Regular"}, "2:27212": {"text": "请输入有效的订阅链接", "family": "Noto Sans SC", "style": "Regular"}, "2:27216": {"text": "输入校验错误", "family": "Noto Sans SC", "style": "Regular"}, "2:27234": {"text": "组件", "family": "Noto Sans SC", "style": "Bold"}, "2:27235": {"text": "统一设计，连贯体验。", "family": "Noto Sans SC", "style": "Medium"}, "2:27236": {"text": "以下实例共享本页的组件母版。编辑母版，即可更新各页面。", "family": "Noto Sans SC", "style": "Regular"}, "2:27268": {"text": "按钮 / 主要、次要、文字、危险与禁用", "family": "Noto Sans SC", "style": "Medium"}, "I2:27237;2:16625": {"text": "连接", "family": "Noto Sans SC", "style": "Medium"}, "I2:27244;2:16640": {"text": "测试延迟", "family": "Noto Sans SC", "style": "Medium"}, "I2:27252;2:16655": {"text": "取消", "family": "Noto Sans SC", "style": "Medium"}, "I2:27257;2:16670": {"text": "断开连接", "family": "Noto Sans SC", "style": "Medium"}, "I2:27262;2:27206": {"text": "按钮", "family": "Noto Sans SC", "style": "Medium"}, "2:27289": {"text": "输入框 / 默认、聚焦与校验", "family": "Noto Sans SC", "style": "Medium"}, "I2:27270;2:16702": {"text": "搜索节点…", "family": "Noto Sans SC", "style": "Regular"}, "I2:27276;2:16708": {"text": "搜索节点…", "family": "Noto Sans SC", "style": "Regular"}, "I2:27282;2:27212": {"text": "请输入有效的订阅链接", "family": "Noto Sans SC", "style": "Regular"}, "2:27307": {"text": "状态 / 文字与颜色", "family": "Noto Sans SC", "style": "Medium"}, "I2:27291;2:16682": {"text": "已连接", "family": "Noto Sans SC", "style": "Medium"}, "I2:27294;2:16691": {"text": "测速中", "family": "Noto Sans SC", "style": "Medium"}, "I2:27297;2:16685": {"text": "延迟较高", "family": "Noto Sans SC", "style": "Medium"}, "I2:27300;2:16688": {"text": "超时", "family": "Noto Sans SC", "style": "Medium"}, "I2:27303;2:16679": {"text": "离线", "family": "Noto Sans SC", "style": "Medium"}, "2:27367": {"text": "导航 / 选中状态与标签页", "family": "Noto Sans SC", "style": "Medium"}, "I2:27309;2:16729": {"text": "概览", "family": "Noto Sans SC", "style": "Medium"}, "I2:27309;2:16730": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:27318;2:16720": {"text": "概览", "family": "Noto Sans SC", "style": "Regular"}, "I2:27318;2:16721": {"text": "1", "family": "Roboto Mono", "style": "Regular"}, "I2:27328;2:16712": {"text": "今日", "family": "Noto Sans SC", "style": "Medium"}, "I2:27330;2:16710": {"text": "本月", "family": "Noto Sans SC", "style": "Medium"}, "I2:27332;2:16801": {"text": "首页", "family": "Noto Sans SC", "style": "Medium"}, "I2:27332;2:16809": {"text": "节点", "family": "Noto Sans SC", "style": "Medium"}, "I2:27332;2:16815": {"text": "配置", "family": "Noto Sans SC", "style": "Medium"}, "I2:27332;2:16820": {"text": "流量", "family": "Noto Sans SC", "style": "Medium"}, "I2:27332;2:16826": {"text": "设置", "family": "Noto Sans SC", "style": "Medium"}, "2:27409": {"text": "节点 / 选中状态与快速切换", "family": "Noto Sans SC", "style": "Medium"}, "I2:27369;2:16749": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:27369;2:16751": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:27369;2:16752": {"text": "东京 · 日本", "family": "Noto Sans SC", "style": "Regular"}, "I2:27369;2:16754": {"text": "VLESS", "family": "Inter", "style": "Medium"}, "I2:27369;2:16759": {"text": "24 ms", "family": "Inter", "style": "Medium"}, "I2:27385;2:16733": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:27385;2:16735": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "I2:27385;2:16736": {"text": "东京 · 日本", "family": "Noto Sans SC", "style": "Regular"}, "I2:27385;2:16738": {"text": "VLESS", "family": "Inter", "style": "Medium"}, "I2:27385;2:16743": {"text": "24 ms", "family": "Inter", "style": "Medium"}, "I2:27401;2:16782": {"text": "JP", "family": "Inter", "style": "Semi Bold"}, "I2:27401;2:16783": {"text": "东京 · 樱花", "family": "Noto Sans SC", "style": "Medium"}, "2:27429": {"text": "图表 / 可编辑原生矢量", "family": "Noto Sans SC", "style": "Medium"}, "2:27479": {"text": "容器 / 卡片、弹窗与开关", "family": "Noto Sans SC", "style": "Medium"}, "I2:27431;2:16788": {"text": "卡片标题", "family": "Noto Sans SC", "style": "Medium"}, "I2:27431;2:16789": {"text": "集中呈现相关信息的容器。", "family": "Noto Sans SC", "style": "Regular"}, "I2:27434;2:16829": {"text": "导入订阅", "family": "Noto Sans SC", "style": "Bold"}, "I2:27434;2:16833": {"text": "添加你自己的订阅链接。", "family": "Noto Sans SC", "style": "Regular"}, "I2:27434;2:16835": {"text": "订阅链接", "family": "Noto Sans SC", "style": "Regular"}, "I2:27434;2:16836;2:16702": {"text": "https://example.com/subscription", "family": "Noto Sans SC", "style": "Regular"}, "I2:27434;2:16845": {"text": "配置名称", "family": "Noto Sans SC", "style": "Regular"}, "I2:27434;2:16846;2:16702": {"text": "个人工作区", "family": "Noto Sans SC", "style": "Regular"}, "I2:27434;2:16853": {"text": "每 6 小时自动更新", "family": "Noto Sans SC", "style": "Regular"}, "I2:27434;2:16857;2:16655": {"text": "取消", "family": "Noto Sans SC", "style": "Medium"}, "I2:27434;2:16862;2:16625": {"text": "导入配置", "family": "Noto Sans SC", "style": "Medium"}, "2:27472": {"text": "关闭 / 开启", "family": "Noto Sans SC", "style": "Medium"}, "2:27490": {"text": "RainLink / 交付说明", "family": "Noto Sans SC", "style": "Bold"}, "2:27491": {"text": "从桌面到掌心，完整的网络工作区。", "family": "Noto Sans SC", "style": "Medium"}, "2:27493": {"text": "16 个桌面端页面  /  15 个移动端页面", "family": "Noto Sans SC", "style": "Bold"}, "2:27494": {"text": "桌面端 1440 × 900 · 移动端 393 × 852 · 共享原生组件与自动布局。", "family": "Noto Sans SC", "style": "Regular"}, "2:27495": {"text": "深色主题与浅色扩展采用独立语义颜色集合，适配当前免费方案的限制。", "family": "Noto Sans SC", "style": "Regular"}, "2:27497": {"text": "演示 5 条命名原型流程", "family": "Noto Sans SC", "style": "Medium"}, "2:27498": {"text": "连接并切换节点；导入配置并调整分流；从连接错误中恢复。", "family": "Noto Sans SC", "style": "Regular"}, "2:27499": {"text": "节点、延迟、流量和相机状态均为原型示例数据。", "family": "Noto Sans SC", "style": "Regular"}, "2:27501": {"text": "文件内容", "family": "Noto Sans SC", "style": "Medium"}, "2:27502": {"text": "01 / 桌面端\n02 / 移动端\n03 / 基础规范、组件与交互流程", "family": "Noto Sans SC", "style": "Regular"}};
// RainLink 2.0: subscriptions + independent manual nodes + visual proxy chains.
// Native, in-place screen updates preserve public screen IDs. All data is illustrative.
const U_VERSION='2.0';
const U_NODE_DATA=[
 {name:'办公 HTTP',p:'HTTP',region:'办公室',code:'CN',source:'手动添加',server:'proxy.office.example.com:8080',ping:'12',role:'入口'},
 {name:'东京 · 樱花',p:'VLESS',region:'日本 · 东京',code:'JP',source:'主订阅',server:'tokyo.example.com:443',ping:'24',role:'出口'},
 {name:'本地 SOCKS',p:'SOCKS5',region:'本机',code:'LO',source:'手动添加',server:'127.0.0.1:1080',ping:'1',role:'入口'},
 {name:'新加坡 · 滨海湾',p:'Trojan',region:'新加坡',code:'SG',source:'主订阅',server:'sg.example.com:443',ping:'38',role:'出口'},
 {name:'香港 · 维多利亚',p:'Hysteria',region:'中国香港',code:'HK',source:'主订阅',server:'hk.example.com:443',ping:'18',role:'出口'},
 {name:'伦敦 · 泰晤士',p:'VLESS',region:'英国 · 伦敦',code:'GB',source:'备用订阅',server:'uk.example.com:443',ping:'168',role:'出口'},
 {name:'实验室 HTTP',p:'HTTP',region:'实验室',code:'CN',source:'手动添加',server:'lab.example.com:3128',ping:'8',role:'入口'}
];
let uLinks=[];
const uFind=(n,name)=>n&&n.findOne(x=>(x.getPluginData('rainlink-canonical-name')||x.name)===name);
function uText(s,size=14,color='Text',weight='Regular',w=null){const n=tx(s,size,color,weight,w);if(/[\u3400-\u9fff]/.test(s)){n.fontName={family:zhFamily,style:zhStyles[weight]||zhStyles.Regular};n.letterSpacing={unit:'PIXELS',value:0};}return n;}
function uSmall(s,color='Muted',w=null){return uText(s,12,color,'Regular',w);}
function uTitle(s,w=600){return uText(s,28,'Text','Semi Bold',w);}
function uCopy(title,sub,w,size=16){return add(v(title,w,5),uText(title,size,'Text','Medium',w),sub?uSmall(sub,'Muted',w):null);}
function uLink(node,target,animate=false){uLinks.push({node,target,animate});return node;}
function uButton(s,target,tone='Secondary',ic=null,w=null){return uLink(w?fullButton(s,tone,w,ic):btn(s,tone,'M',ic),target);}
function uField(label,value,w,helper=null,error=false){const f=v(label+' field',w,8);let i=input(value,w,null);if(error){i.swapComponent(masters['Input / Error']);i.resize(w,40);textOverride(i,'Value',value,'Error');}const glyph=i.children.find(n=>n.type==='INSTANCE');if(glyph)glyph.visible=false;add(f,uSmall(label,'Secondary'),i,helper?uSmall(helper,error?'Error':'Muted',w):null);return f;}
function uHead(title,sub,actions=null){return between(add(row('Page header',1120,64,18),uCopy(title,sub,700,28),actions));}
function uNote(title,body,w=353,tone='Info'){const c=borderCard(title,w,null,16,8,tone+'Surface');stroke(c,tone,.5);add(c,add(row('Notice title',w-32,null,8),icon(tone==='Warning'?'shield':tone==='Error'?'close':'check',16,tone),uText(title,13,tone,'Medium',w-56)),uSmall(body,'Secondary',w-32));return c;}
function uSection(title,meta,w,action=null){return between(add(row(title+' heading',w,null,12),uCopy(title,meta,w-180,16),action));}
function uMetric(title,value,sub,w){const c=borderCard(title,w,86,14,6);add(c,between(add(row('Metric label',w-28,null),uSmall(title,'Secondary'),uText(value,24,'Text','Semi Bold'))),uSmall(sub,'Muted',w-28));return c;}
function uOverride(n,name,s){const t=uFind(n,name);if(t&&t.type==='TEXT'){t.characters=s;t.setPluginData('rainlink-canonical-name',name);t.setPluginData('rainlink-original-text',s);if(/[\u3400-\u9fff]/.test(s))t.fontName={family:zhFamily,style:zhStyles.Medium};}return n;}
function uNative(name,builder){if(masters[name])return masters[name];const c=component(name,builder);c.setPluginData('rainlink-upgrade-component','2.0');return c;}
function uComponentLibrary(){
 uNative('Source / Subscription',c=>{c.resize(664,100);c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.paddingLeft=c.paddingRight=16;c.paddingTop=c.paddingBottom=14;c.itemSpacing=8;rad(c,12);fill(c,'Raised');stroke(c);const name=uText('主订阅',14,'Text','Medium');name.name='来源名称';const desc=uSmall('8 个节点 · 2 分钟前更新','Secondary');desc.name='来源状态';const interval=uSmall('每 6 小时自动更新');interval.name='更新频率';add(c,between(add(row('Source title',632,null),add(row('Identity',null,null,10),miniIcon('refresh','Primary',30,'PrimarySurface'),name),badge('已启用','Success',true))),between(add(row('Source metadata',632,null),desc,interval)),null);});
 uNative('Source / Manual row',c=>{c.resize(664,42);c.layoutMode='HORIZONTAL';c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.counterAxisAlignItems='CENTER';c.itemSpacing=12;const name=uText('办公 HTTP',13,'Text','Medium',160);name.name='节点名称';const endpoint=uSmall('proxy.office.example.com:8080','Muted',284);endpoint.name='服务器';add(c,miniIcon('laptop','Secondary',28),name,badge('HTTP'),endpoint,icon('chevron',14));});
 for(const mobile of [false,true]){
  const w=mobile?353:728,inner=w-36;
  uNative('Chain / Hop / '+(mobile?'Mobile':'Desktop'),c=>{c.resize(w,mobile?164:160);c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.paddingLeft=c.paddingRight=18;c.paddingTop=c.paddingBottom=16;c.itemSpacing=10;rad(c,14);fill(c,'Surface');stroke(c);const name=uText('办公 HTTP',15,'Text','Medium');name.name='跳点名称';const order=uText('01',13,'Primary','Medium');order.name='跳点序号';const r=between(add(row('Hop heading',inner,null),add(row('Hop identity',null,null,10),miniIcon('link','Primary',30,'PrimarySurface'),order,name),badge('入口','Success')));const meta=uSmall('HTTP · 手动添加 · 12 ms','Secondary',inner);meta.name='跳点来源';const address=uSmall('proxy.office.example.com:8080','Muted',inner);address.name='跳点地址';add(c,r,meta,mobile?null:address,between(add(row('Hop controls',inner,null),btn('更换节点','Ghost','S','nodes'),add(row('Reorder',null,null,4),btn('上移','Ghost','S','upload'),btn('下移','Ghost','S','download'),btn('移除','Ghost','S','close')))));});
  uNative('Chain / Summary / '+(mobile?'Mobile':'Desktop'),c=>{c.resize(w,160);c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.paddingLeft=c.paddingRight=18;c.paddingTop=c.paddingBottom=16;c.itemSpacing=12;rad(c,14);fill(c,'PrimarySurface');stroke(c,'Primary',.6);const name=uText('开发代理链',16,'Text','Medium');name.name='代理链名称';add(c,between(add(row('Chain title',inner,null),add(row('Chain identity',null,null,10),miniIcon('link','Primary',32),name),badge('2 跳','Success'))),uText('办公 HTTP  →  东京 · 樱花',13,'Primary','Medium',inner),between(add(row('Chain facts',inner,null),uSmall('TCP · 整链 46 ms','Secondary'),uSmall('手动节点 + 主订阅','Secondary'))),uSmall('最后一跳是出口，决定对外网络位置。','Muted',inner));});
 }
 uNative('Node / With source',c=>{c.resize(353,96);c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.paddingLeft=c.paddingRight=16;c.paddingTop=c.paddingBottom=14;c.itemSpacing=10;rad(c,12);fill(c,'Surface');stroke(c);const name=uText('东京 · 樱花',14,'Text','Medium');name.name='节点名称';const region=uSmall('日本 · 东京','Secondary');region.name='节点地区';const source=uSmall('来源：主订阅');source.name='节点来源';const protocol=badge('VLESS');protocol.name='协议标记';const latency=uText('24 ms',12,'Success','Medium');latency.name='节点延迟';add(c,between(add(row('Node title',321,null),add(row('Identity',null,null,10),country('JP',28),name),latency)),between(add(row('Node source',321,null),add(row('Metadata',null,null,8),protocol,region),source)));});
 const sourceNode=masters['Node / With source'];const protocol=sourceNode.children[1].children[0].children[0];protocol.name='协议标记';protocol.setPluginData('rainlink-canonical-name','协议标记');const countryText=sourceNode.children[0].children[0].children[0].findOne(n=>n.type==='TEXT');countryText.name='Country';countryText.setPluginData('rainlink-canonical-name','Country');
 uNative('Chain / Drag handle',c=>{c.resize(12,22);c.layoutMode='HORIZONTAL';c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.itemSpacing=3;c.counterAxisAlignItems='CENTER';for(let i=0;i<2;i++)add(c,add(v('Grip dots',3,3),dot('Muted',3),dot('Muted',3),dot('Muted',3)));});
 for(const mobile of [false,true]){const hop=masters['Chain / Hop / '+(mobile?'Mobile':'Desktop')],identity=hop.children[0].children[0];if(!identity.children.some(n=>n.getPluginData('rainlink-grip')==='true')){const grip=instance('Chain / Drag handle');grip.setPluginData('rainlink-grip','true');identity.insertChild(0,grip);}if(mobile)hop.resize(353,144);}
 // Separate gallery shows reusable source and chain components in context.
 let g=dsPage.children.find(n=>n.getPluginData('rainlink-upgrade-gallery')==='true');
 if(!g){g=borderCard('Sources and chains / Components',1500,null,48,24,'Background');g.setPluginData('rainlink-upgrade-gallery','true');dsPage.appendChild(g);g.x=3250;g.y=0;}
 for(const n of [...g.children])n.remove();
 add(g,uTitle('节点来源与代理链 · 组件',1404),uSmall('统一节点库、来源标记、有序跳点与状态反馈；所有示例均为原生组件实例。','Secondary',1404),instance('Source / Subscription'),add(row('Reusable chain layouts',1404,null,24),instance('Chain / Hop / Desktop'),instance('Chain / Hop / Mobile')),add(row('Chain summary layouts',1404,null,24),instance('Chain / Summary / Desktop'),instance('Chain / Summary / Mobile')),add(row('Node and validation',1404,null,24),instance('Node / With source'),uNote('端口无效','请输入 1–65535 之间的端口。',353,'Error'),uNote('仅支持 TCP','HTTP CONNECT 入口不支持 UDP，整条代理链按 TCP 使用。',353,'Warning')),uText('交互约定',18,'Text','Medium'),uSmall('排序：拖动把手或使用上移 / 下移；键盘提供同等操作。测试通过后显式保存，保存后仍需在连接目标或分流规则中选择。','Secondary',1404),uSmall('订阅更新按来源和稳定节点标识维护引用。节点移除或协议不兼容时，标记代理链不可用，并提示用户修复。','Secondary',1404));
 let x=3250,y=g.height+100;
 for(const c of dsPage.findAll(n=>n.type==='COMPONENT'&&n.getPluginData('rainlink-upgrade-component')==='2.0')){c.x=x;c.y=y;y+=c.height+50;}
}
function uSourceCard(name='主订阅',count=8,interval=6,w=664){const c=instance('Source / Subscription');c.resize(w,100);uOverride(c,'来源名称',name);uOverride(c,'来源状态',count+' 个节点 · '+(name==='主订阅'?'2 分钟前':'18 分钟前')+'更新');uOverride(c,'更新频率','每 '+interval+' 小时自动更新');for(const r of c.children.filter(n=>n.type==='FRAME'))r.resize(w-32,r.height);return c;}
function uNode(data,w=353,selected=false){const c=instance('Node / With source');c.resize(w,96);uOverride(c,'节点名称',data.name);uOverride(c,'节点地区',data.region);uOverride(c,'节点来源','来源：'+data.source);uOverride(c,'节点延迟',data.ping+' ms');const p=uFind(c,'协议标记');if(p)textOverride(p,'Label',data.p);uOverride(c,'Country',data.code);for(const r of c.children.filter(n=>n.type==='FRAME'))r.resize(w-32,r.height);if(selected){fill(c,'PrimarySurface');stroke(c,'Primary');}return c;}
function uSummary(mobile=false,w=null){const c=instance('Chain / Summary / '+(mobile?'Mobile':'Desktop'));if(w){c.resize(w,c.height);for(const r of c.children.filter(n=>n.type==='FRAME'))r.resize(w-36,r.height);for(const t of c.children.filter(n=>n.type==='TEXT')){t.resize(w-36,t.height);t.textAutoResize='HEIGHT';}}return c;}
function uSide(active){const s=instance('Sidebar / Desktop');s.name='Sidebar / Desktop';for(const it of s.findAll(n=>n.type==='INSTANCE'&&n.name.startsWith('Navigate · '))){const key=it.name.slice(11),idx=navNames.indexOf(key);if(idx<0)continue;it.swapComponent(masters['Navigation / '+(key===active?'Active':'Default')]);textOverride(it,'Nav label',key);textOverride(it,'Shortcut',String(idx+1));const ic=uFind(it,'Nav icon');if(ic){ic.swapComponent(icons[navIcons[idx]]);tint(ic,key===active?'Primary':'Secondary');}uLink(it,'D/'+key);}uLink(uFind(s,'Routing mode'),'D/Rules');return s;}
function uD(key,title,sub,build,active='Profiles',actions=null){let s=registry.desktop[key];if(!s){s=frame('Desktop / '+key,1440,900,'HORIZONTAL','Background');desktopPage.appendChild(s);registry.desktop[key]=s;}for(const c of [...s.children])c.remove();s.name='Desktop / '+key;s.setPluginData('rainlink-canonical-name',s.name);s.setPluginData('rainlink','desktop/'+key);s.setPluginData('rainlink-upgrade','2.0');s.resize(1440,900);s.clipsContent=true;const main=frame('Main',1192,900,'VERTICAL');const body=frame('Content',1192,832,'VERTICAL',null,16,36);body.paddingTop=body.paddingBottom=24;add(body,uHead(title,sub,actions||uButton('添加来源','D/Import profile','Primary','plus')));add(main,topbar(),body);add(s,uSide(active),main);build(body,s);return s;}
function uM(key,title,sub,build,active='Profiles',back='M/Profiles'){let s=registry.mobile[key];if(!s){s=frame('Mobile / '+key,393,852,'VERTICAL','Background');mobilePage.appendChild(s);registry.mobile[key]=s;}for(const c of [...s.children])c.remove();s.name='Mobile / '+key;s.setPluginData('rainlink-canonical-name',s.name);s.setPluginData('rainlink','mobile/'+key);s.setPluginData('rainlink-upgrade','2.0');s.resize(393,852);s.clipsContent=true;const header=between(add(row('Page header',393,68,12,20),uCopy(title,sub,278,24),uButton('',back,'Ghost','close')));header.paddingTop=header.paddingBottom=8;const view=frame('Scrollable content',393,650,'VERTICAL');view.layoutGrow=1;view.clipsContent=true;view.overflowDirection='VERTICAL';const b=v('Content',393,14,20);b.paddingTop=12;b.paddingBottom=24;add(view,b);add(s,statusBar(),header,view,mobileNav(active));build(b,s);return s;}
function uSourceOverview(){
 uD('Profiles','节点来源','订阅与手动节点同时启用，汇入同一个节点库。',b=>{
  add(b,add(row('Source metrics',1120,86,16),uMetric('可用节点','14','来自所有启用的来源',362),uMetric('订阅来源','2','分别更新，独立管理',363),uMetric('手动节点','3','独立保存，订阅更新不覆盖',363)));
  const cols=row('Mixed source workspace',1120,null,24),left=v('Source inventory',704,16),right=v('Source guidance',392,16);
  const subscriptions=borderCard('Subscription sources',704,null,20,12);add(subscriptions,uSection('订阅来源','持续同步各自的节点',664,uButton('更新全部','D/Source success','Ghost','refresh')),uLink(uSourceCard(),'D/Nodes'),uLink(uSourceCard('备用订阅',3,2),'D/Nodes'));
  const manual=borderCard('Manual nodes',704,null,20,8);add(manual,uSection('手动节点','单个节点直接加入节点库',664,uButton('添加节点','D/Manual node','Ghost','plus')));for(const d of [U_NODE_DATA[0],U_NODE_DATA[2],U_NODE_DATA[6]]){const n=instance('Source / Manual row');uOverride(n,'节点名称',d.name);uOverride(n,'服务器',d.server);textOverride(n.findOne(n=>n.name==='Badge / Neutral'),'Label',d.p);uLink(n,'D/Manual node');add(manual,n);}
  const model=borderCard('How sources work',392,null,22,16);add(model,uText('把来源和连接分开管理',17,'Text','Medium',348));for(const [no,title,desc]of [['01','添加节点来源','订阅同步一批节点；手动保存单个节点。'],['02','统一查看与测速','在「节点」中按来源筛选、收藏和选择。'],['03','直接连接或编排代理链','多个节点按顺序转发，最后一跳是出口。']])add(model,add(row('Source principle',348,null,12),miniIcon(no==='03'?'link':no==='02'?'nodes':'refresh','Primary',34),uCopy(title,desc,302,13)));add(model,uButton('查看全部节点','D/Nodes','Secondary','nodes',348));
  const chain=borderCard('Chain shortcut',392,null,22,12,'PrimarySurface');add(chain,between(add(row('Chain shortcut title',348,null),uText('可视化代理链',16,'Text','Medium'),badge('2 条','Success'))),uSmall('办公 HTTP → 东京 · 樱花\n跨来源选择节点，按顺序组成一条链。','Secondary',348),uButton('管理代理链','D/Chains','Primary','link',348));add(left,subscriptions,manual);add(right,model,chain);add(cols,left,right);add(b,cols,uSmall('订阅更新仅同步本来源。手动节点和其他订阅保持独立。','Muted',1120));
 });
 uM('Profiles','节点来源','2 个订阅 + 3 个手动节点',b=>{
  add(b,between(add(row('Source actions',353,null),badge('共 14 个节点','Success'),uButton('添加来源','M/Import profile','Primary','plus'))));
  add(b,uLink(uSummary(true),'M/Chains'),uSection('订阅来源','自动同步，分别更新',353,uButton('更新','M/Import success','Ghost','refresh')));
  for(const args of [['主订阅',8,6],['备用订阅',3,2]])add(b,uLink(uSourceCard(...args,353),'M/Nodes'));
  add(b,uSection('手动节点','独立保存，不被订阅覆盖',353,uButton('添加','M/Manual node','Ghost','plus')));for(const d of [U_NODE_DATA[0],U_NODE_DATA[2],U_NODE_DATA[6]])add(b,uLink(uNode(d),'M/Node details'));
  add(b,uNote('来源可以同时启用','新增订阅会追加节点；手动节点继续保留。',353,'Info'));
 });
}
function uAddSource(){
 const choices=[['订阅链接','持续更新一批节点','粘贴订阅 URL，设置独立更新周期。','refresh','Subscription import'],['手动节点','输入单个 HTTP、SOCKS5 等节点','选择协议，填写服务器与认证信息。','laptop','Manual node'],['可视化代理链','把已有节点按顺序串联','从节点库挑选入口和出口，测试后保存。','link','Chain editor']];
 uD('Import profile','添加来源或代理链','先添加节点，再选择直接使用还是按顺序编排。',b=>{const r=row('Add choices',1120,null,20);for(const [title,sub,desc,ic,target]of choices){const c=borderCard(title,360,288,24,16);add(c,miniIcon(ic,'Primary',48,'PrimarySurface'),uText(title,21,'Text','Medium'),uSmall(sub,'Primary',312),uSmall(desc,'Secondary',312),grow(space()),uButton(title==='可视化代理链'?'开始编排':'继续','D/'+target,'Primary','arrow',312));add(r,c);}add(b,r,uNote('多个来源可以共存','添加订阅不会替换手动节点。代理链引用已有节点，可作为连接目标或分流规则的出站。',1120,'Info'),uButton('高级内核配置（YAML / JSON）','D/Profile editor','Ghost','terminal'));},'Profiles',uButton('返回节点来源','D/Profiles','Ghost','arrow'));
 uM('Import profile','添加来源','选择你要添加的内容',b=>{for(const [title,sub,desc,ic,target]of choices){const c=borderCard(title,353,null,18,12);add(c,add(row('Choice title',317,null,12),miniIcon(ic,'Primary',36,'PrimarySurface'),uCopy(title,sub,268,16)),uSmall(desc,'Secondary',317),uButton(title==='可视化代理链'?'开始编排':'继续','M/'+target,'Primary','arrow',317));add(b,c);}add(b,uButton('扫码导入','M/QR import','Secondary','qr',353),uSmall('扫码后识别订阅链接或单个节点，并显示对应的确认表单。','Muted',353));});
}
function uSubscriptionForm(){
 uD('Subscription import','导入订阅','新增一个节点来源，保留当前订阅和手动节点。',b=>{const r=row('Subscription workspace',1120,null,24),form=borderCard('Subscription form',728,null,26,18),side=borderCard('Import preview',368,null,24,16);add(form,uText('订阅信息',20,'Text','Medium'),uField('来源名称','主订阅',676),uField('订阅链接','https://example.com/subscription',676,'使用自己的订阅链接；可在保存前预览节点。'),between(add(row('Auto update',676,48),uCopy('自动更新','每 6 小时；仅更新此来源的节点。',500,14),sw(true))),uNote('追加来源','现有备用订阅和 3 个手动节点都会保留。',676,'Info'),between(add(row('Form actions',676,48),uButton('取消','D/Profiles','Ghost'),uButton('预览并导入','D/Source success','Primary','download'))));add(side,miniIcon('refresh','Primary',48,'PrimarySurface'),uText('订阅会带来什么？',18,'Text','Medium',320),uSmall('批量添加节点并持续同步。节点名称、协议、地区和来源会出现在统一节点库中。','Secondary',320),divider(320),uText('高级导入',14,'Text','Medium'),uSmall('YAML / JSON 配置可在高级内核配置中导入与校验。来源管理仍独立保存。','Muted',320),uButton('打开高级配置','D/Profile editor','Secondary','terminal',320));add(r,form,side);add(b,r);},'Profiles',uButton('返回','D/Import profile','Ghost','arrow'));
 uM('Subscription import','导入订阅','追加来源，保留已有节点',b=>{add(b,uField('来源名称','主订阅',353),uField('订阅链接','https://example.com/subscription',353,'粘贴订阅 URL。'),borderCard('Auto update',353,null,18,12));const c=b.children[b.children.length-1];add(c,between(add(row('Update toggle',317,null),uCopy('自动更新','每 6 小时，仅同步这个来源。',264,14),sw(true))));add(b,uNote('保留现有来源','备用订阅与 3 个手动节点不受影响。',353,'Info'),uButton('预览并导入','M/Import success','Primary','download',353),uButton('扫码填入链接','M/QR import','Secondary','qr',353));},'Profiles','M/Import profile');
}
function uManualForm(error=false){
 const key=error?'Manual error':'Manual node';
 uD(key,'添加手动节点','单个节点独立保存，可直接使用，也可加入代理链。',b=>{const r=row('Manual node workspace',1120,null,24),form=borderCard('Manual node form',728,null,26,16),side=borderCard('Manual guidance',368,null,24,18);add(form,add(row('Protocol selection',676,null,12),badge('HTTP','Success'),badge('SOCKS5'),badge('VLESS'),badge('更多协议')),uField('节点名称','办公 HTTP',676),add(row('Endpoint inputs',676,null,16),uField('服务器','proxy.office.example.com',492),uField('端口',error?'70000':'8080',168,error?'请输入 1–65535。':null,error)),between(add(row('Authentication',676,36),uText('用户名 / 密码认证（可选）',13),sw(true))),add(row('Credentials',676,null,16),uField('用户名','office-user',330),uField('密码','••••••••',330)),error?uNote('端口无效','修正端口后才能保存。节点尚未加入节点库。',676,'Error'):uNote('独立于订阅','保存后来源为「手动添加」，订阅更新不会覆盖此节点。',676,'Info'),between(add(row('Manual save actions',676,48),uButton(error?'修正为 8080':'查看输入校验',error?'D/Manual node':'D/Manual error','Ghost'),error?instance('Button / Disabled'):uButton('保存节点','D/Manual success','Primary','check'))));if(error)textOverride(form.children[form.children.length-1].children[1],'Label','保存节点');add(side,miniIcon('laptop','Primary',48,'PrimarySurface'),uText('一条节点，多个用法',18,'Text','Medium',320),uSmall('节点保存到统一节点库。可以直接连接，也可以作为代理链中的任意一跳。','Secondary',320),divider(320),uText('HTTP 的链路能力',14,'Warning','Medium'),uSmall('HTTP CONNECT 用于转发 TCP。本示例作为入口时，整链不支持 UDP。','Secondary',320),divider(320),uSmall('支持 Shadowsocks、VLESS、VMess、Trojan、Hysteria、TUIC、SOCKS5、HTTP。按协议显示专属字段。','Muted',320));add(r,form,side);add(b,r);},'Profiles',uButton('返回节点来源','D/Profiles','Ghost','arrow'));
 uM(key,'手动添加节点','独立保存到统一节点库',b=>{add(b,uSmall('协议','Secondary'),tabs(['HTTP','SOCKS5','更多'],0,353),uField('节点名称','办公 HTTP',353),add(row('Endpoint inputs',353,null,12),uField('服务器','proxy.office.example.com',239),uField('端口',error?'70000':'8080',102,error?'1–65535':null,error)),between(add(row('Authentication',353,36),uText('用户名 / 密码认证',13),sw(true))),uField('用户名','office-user',353),uField('密码','••••••••',353),uNote(error?'端口无效':'手动节点独立保存',error?'修正端口后才能保存。':'订阅更新不会覆盖它，可作为代理链入口。',353,error?'Error':'Info'),error?uButton('修正为 8080','M/Manual node','Primary','check',353):uButton('保存节点','M/Manual success','Primary','check',353),error?null:uButton('查看输入校验','M/Manual error','Ghost',null,353));},'Profiles','M/Import profile');
}
function uSuccess(manual=false){
 const dkey=manual?'Manual success':'Source success',mkey=manual?'Manual success':'Import success',title=manual?'手动节点已保存':'订阅导入成功',desc=manual?'办公 HTTP 已加入统一节点库。':'主订阅已同步 8 个节点。';
 uD(dkey,title,desc,b=>{const c=borderCard('Source receipt',1120,null,28,18,'PrimarySurface');add(c,add(row('Success identity',1064,null,16),miniIcon('check','Primary',56),uCopy(title,desc,880,24)),add(row('Source receipt facts',1064,null,12),badge('2 个订阅'),badge('3 个手动节点'),badge('共 14 个节点','Success')),divider(1064),uText(manual?'来源：手动添加 · HTTP · proxy.office.example.com:8080':'来源：主订阅 · 每 6 小时自动更新',14,'Secondary','Regular',1064),uSmall('其他来源完整保留。节点可直接连接，也可加入代理链。','Secondary',1064));add(b,c,add(row('Next actions',1120,48,12),uButton('查看节点','D/Nodes','Primary','nodes'),uButton('创建代理链','D/Chain editor','Secondary','link'),uButton('返回节点来源','D/Profiles','Ghost')));},'Profiles',uButton('完成','D/Profiles','Ghost','check'));
 uM(mkey,title,manual?'来源：手动添加':'来源：主订阅',b=>{const c=center(borderCard('Success receipt',353,null,24,16,'PrimarySurface'));add(c,miniIcon('check','Primary',64),uText(title,22,'Text','Semi Bold'),uSmall(desc,'Secondary',305),badge('共 14 个节点','Success'));add(b,c,uNote('现有来源完整保留','2 个订阅与 3 个手动节点可以同时使用。',353,'Info'),uButton('查看节点','M/Nodes','Primary','nodes',353),uButton('创建代理链','M/Chain editor','Secondary','link',353),uButton('返回节点来源','M/Profiles','Ghost',null,353));});
}
function uChainList(){
 uD('Chains','代理链','把不同来源的节点按顺序串联；末尾节点是对外出口。',b=>{const r=row('Chain collection',1120,null,24),left=v('Saved chains',728,16),right=borderCard('Chain usage guide',368,null,24,16);const summary=uSummary();uLink(summary,'D/Chain editor');add(left,summary,add(row('Saved chain actions',728,40,12),uButton('编辑编排','D/Chain editor','Secondary','link'),uButton('测试整链','D/Chain tested','Secondary','speed'),uButton('设为连接目标','D/Chain connected','Primary','power')));const failed=borderCard('Unavailable chain',728,null,20,14);add(failed,between(add(row('Failed chain title',688,null),uCopy('备用代理链','本地 SOCKS → 伦敦 · 泰晤士',490,17),badge('需要修复','Error',true))),uSmall('出口节点已从备用订阅移除，无法继续连接。','Secondary',688),uButton('检查缺失节点','D/Chain unavailable','Secondary','shield'));add(left,failed);add(right,miniIcon('link','Primary',48,'PrimarySurface'),uText('有序转发，出口明确',18,'Text','Medium',320),uSmall('本机 → 第一跳 → 第二跳 → 目标网站\n节点来源可以混用；跳点顺序决定连接路径。','Secondary',320),divider(320),uSmall('保存后，在快速切换或分流规则里选择这条代理链。测试数据为设计示例。','Muted',320),uButton('前往快速切换','D/Quick switch','Secondary','connections',320),uButton('用于分流规则','D/Rule editor','Secondary','rules',320));add(r,left,right);add(b,r,uNote('兼容性按整条链计算','HTTP 入口仅支持 TCP。节点缺失或不兼容时，提示修复，不自动替换入口或出口。',1120,'Warning'));},'Chains',uButton('新建代理链','D/Chain editor','Primary','plus'));
 uM('Chains','代理链','跨来源选择，按顺序转发',b=>{add(b,uButton('新建代理链','M/Chain editor','Primary','plus',353),uLink(uSummary(true),'M/Chain editor'),add(row('Chain actions',353,48,12),uButton('编排','M/Chain editor','Secondary','link'),uButton('连接','M/Chain connected','Primary','power')));const failed=borderCard('Unavailable chain',353,null,18,12);add(failed,between(add(row('Unavailable title',317,null),uText('备用代理链',15,'Text','Medium'),badge('需要修复','Error'))),uSmall('本地 SOCKS → 伦敦 · 泰晤士\n出口节点已被订阅移除。','Secondary',317),uButton('检查缺失节点','M/Chain unavailable','Secondary','shield',317));add(b,failed,uNote('怎样使用代理链','测试并保存后，在首页快速切换中选择这条链。',353,'Info'));});
}
function uHop(data,index,mobile,swapped=false,empty=false){const c=instance('Chain / Hop / '+(mobile?'Mobile':'Desktop'));c.name='Chain hop / '+data.name;uOverride(c,'跳点名称',data.name);uOverride(c,'跳点序号',String(index+1).padStart(2,'0'));uOverride(c,'跳点来源',data.p+' · '+data.source+' · '+data.ping+' ms');uOverride(c,'跳点地址',data.server);const badges=c.findAll(n=>n.type==='INSTANCE'&&n.name==='Badge / Success');if(badges[0])textOverride(badges[0],'Label',index===0?'入口':'出口');const prefix=mobile?'M/':'D/';for(const button of c.findAll(n=>n.type==='INSTANCE'&&n.name.startsWith('Button · '))){const name=button.name.slice(9);if(name==='更换节点')uLink(button,prefix+'Chain picker');if(name==='上移'||name==='下移'){if(!empty)uLink(button,prefix+(swapped?'Chain editor':'Chain reordered'),true);if((index===0&&name==='上移')||(index===1&&name==='下移')){button.opacity=.35;}}if(name==='移除')uLink(button,prefix+'Chain empty',true);}return c;}
function uRouteDiagram(w,mobile=false,swapped=false,empty=false){const r=mobile?v('Ordered route',w,8):row('Ordered route',w,72,12);const steps=empty?['本机','办公 HTTP','待添加出口','目标网站']:['本机',swapped?'东京 · 樱花':'办公 HTTP',swapped?'办公 HTTP':'东京 · 樱花','目标网站'];if(mobile){add(r,uText(steps.join('  →  '),12,'Primary','Medium',w));return r;}steps.forEach((label,i)=>{const box=center(rad(row('Route point '+i,i===1||i===2?168:128,56,6,8,i===1||i===2?'PrimarySurface':'Raised'),10));add(box,uText(label,13,i===1||i===2?'Primary':'Secondary','Medium'));add(r,box);if(i<steps.length-1)add(r,icon('arrow',18,'Muted'));});return r;}
function uChainEditor(state='default'){
 const swapped=state==='reordered',empty=state==='empty',tested=state==='tested',key=swapped?'Chain reordered':empty?'Chain empty':tested?'Chain tested':'Chain editor',title=tested?'代理链测试通过':'编排代理链';
 const build=(b,mobile)=>{const w=mobile?353:728,prefix=mobile?'M/':'D/',order=swapped?[U_NODE_DATA[1],U_NODE_DATA[0]]:[U_NODE_DATA[0],U_NODE_DATA[1]];const left=mobile?b:v('Chain visual editor',728,14);
  if(tested)add(left,uNote('整链可连接','握手成功 · 整链延迟 46 ms · 出口：东京 · 樱花。',w,'Info'));
  add(left,uField('代理链名称','开发代理链',w),uRouteDiagram(w,mobile,swapped,empty),uHop(order[0],0,mobile,swapped,empty));if(!empty)add(left,uHop(order[1],1,mobile,swapped));
  const addHop=fullButton(empty?'添加出口节点':'添加一跳','Secondary',w,'plus');stroke(addHop,'Primary',.6);uLink(addHop,prefix+'Chain picker');add(left,addHop);
  if(mobile){add(left,uNote(empty?'至少需要 2 跳':swapped?'出口已改变':'整链能力：仅 TCP',empty?'选择出口节点后，再测试和保存。':swapped?'当前末尾是办公 HTTP，对外出口变为办公室网络。':'HTTP CONNECT 入口不支持 UDP；出口为东京 · 樱花。',w,'Warning'),uSmall('点击上移 / 下移调整顺序。更换和移除不会修改原始节点。','Muted',w),empty?null:uButton(tested?'保存代理链':'测试整链',tested?'M/Chains':'M/Chain tested','Primary',tested?'check':'speed',353));}
  else{const side=borderCard('Chain inspector',368,null,24,18);add(side,uText('链路检查',18,'Text','Medium'),badge(empty?'待完成':tested?'测试通过':'未保存',tested?'Success':'Neutral',true),uSmall('节点来源可以混用','Primary',320),uText('入口：'+order[0].name+'\n出口：'+(empty?'尚未选择':order[1].name),14,'Secondary','Regular',320),divider(320),uNote(empty?'至少需要两跳':'整链能力：仅 TCP',empty?'添加出口节点后，才能测试和保存。':'HTTP CONNECT 不转发 UDP。应用 UDP 规则时，这条链不可选。',320,'Warning'),uSmall('拖动把手或点击上移 / 下移排序；末尾节点决定出口。','Muted',320),empty?null:uButton(tested?'保存代理链':'测试整链',tested?'D/Chains':'D/Chain tested','Primary',tested?'check':'speed',320),uButton('取消','D/Chains','Ghost',null,320));add(b,add(row('Visual chain workspace',1120,null,24),left,side));}
 };
 uD(key,title,'本机 → 入口 → 出口 → 目标网站；从左到右按顺序转发。',b=>build(b,false),'Chains',uButton('返回代理链','D/Chains','Ghost','arrow'));
 uM(key,title,tested?'整链延迟 46 ms · 仅 TCP':'顺序决定路径，最后一跳是出口',b=>build(b,true),'Profiles','M/Chains');
}
function uChainPicker(){
 uD('Chain picker','选择跳点','从统一节点库选择，可跨订阅和手动来源。',b=>{add(b,between(add(row('Picker filters',1120,40),input('搜索节点名称、协议或来源',480,'search'),tabs(['全部来源','订阅节点','手动节点'],0,500))));const r=row('Picker inventory',1120,null,24),left=v('Available chain nodes',728,12);for(const data of [U_NODE_DATA[1],U_NODE_DATA[3],U_NODE_DATA[2]]){const c=borderCard(data.name,728,null,18,12);add(c,between(add(row('Candidate',692,null),add(row('Candidate label',null,null,10),country(data.code,30),uCopy(data.name,data.p+' · '+data.region+' · 来源：'+data.source,410,15)),uButton('选为出口','D/Chain editor','Primary','check'))),uSmall(data.server+' · '+data.ping+' ms','Muted',692));add(left,c);}const side=borderCard('Selection context',368,null,24,18);add(side,uText('正在选择第 2 跳',18,'Text','Medium'),uSmall('当前入口：办公 HTTP\n所选节点将成为出口。','Secondary',320),divider(320),uNote('UDP 节点不可选','香港 · 维多利亚 / Hysteria 需要 UDP，无法通过此 HTTP CONNECT 入口。',320,'Warning'),uSmall('已在链中的节点不可重复加入，避免形成循环。','Muted',320),uButton('返回编排','D/Chain editor','Secondary','arrow',320));add(r,left,side);add(b,r);},'Chains',uButton('取消','D/Chain editor','Ghost','close'));
 uM('Chain picker','选择出口节点','当前入口：办公 HTTP',b=>{add(b,input('搜索名称或来源',353),tabs(['全部','订阅','手动'],0,353));for(const data of [U_NODE_DATA[1],U_NODE_DATA[3],U_NODE_DATA[2]])add(b,uLink(uNode(data),'M/Chain editor'));const disabled=uNode(U_NODE_DATA[4]);disabled.opacity=.45;add(b,disabled,uNote('此节点不可选','Hysteria 需要 UDP，当前 HTTP CONNECT 入口无法转发。',353,'Warning'),uSmall('已在链中的节点不可重复添加。','Muted',353));},'Profiles','M/Chain editor');
}
function uChainUnavailable(){
 const content=(b,mobile)=>{const w=mobile?353:1120,prefix=mobile?'M/':'D/';add(b,uNote('出口节点已失效','伦敦 · 泰晤士已从备用订阅移除。此链暂停使用，原始跳点顺序继续保留。',w,'Error'));const c=borderCard('Missing node',w,null,24,16);add(c,uText('备用代理链',20,'Text','Medium'),uText('本机  →  本地 SOCKS  →  缺失出口  →  目标网站',mobile?12:16,'Warning','Medium',w-48),uSmall('入口可用 · 出口不可用 · 连接已停止','Secondary',w-48),uButton('选择替代出口',prefix+'Chain picker','Primary','nodes',mobile?w-48:null));add(b,c,uNote('修复后再连接','更换出口后需重新测试并保存。RainLink 不会静默改用其他节点或直连。',w,'Warning'),uButton('返回代理链',prefix+'Chains','Secondary','arrow',mobile?353:null));};
 uD('Chain unavailable','代理链需要修复','来源变化时保留编排，并明确指出失效的跳点。',b=>content(b,false),'Chains',uButton('返回','D/Chains','Ghost','arrow'));
 uM('Chain unavailable','代理链不可用','需要重新选择出口',b=>content(b,true),'Profiles','M/Chains');
}
function uNodesAndSwitch(){
 const table=(b,tested=false)=>{add(b,between(add(row('Node source filters',1120,40),input('搜索名称、协议或地区',360),tabs(['全部 14','订阅 11','手动 3'],0,400))),add(row('Protocol tags',1120,null,8),...['Shadowsocks','VLESS','VMess','Trojan','Hysteria','TUIC','SOCKS5','HTTP'].map(x=>badge(x))),tested?uNote('测速已完成','14 个节点已测试；当前连接目标保持不变。',1120,'Info'):null);const c=borderCard('Unified node inventory',1120,null,20,0);add(c,add(row('Node table header',1080,32,12),...['节点 / 地区','协议','来源','延迟','操作'].map((s,i)=>uSmall(s,'Muted',[380,100,180,116,256][i]))));for(const d of U_NODE_DATA){add(c,divider(1080),add(row('Node table row',1080,48,12),add(row('Node identity',380,48,12),country(d.code,28),uCopy(d.name,d.region,332,13)),add(row('Node protocol',100,48),badge(d.p)),uText(d.source,12,d.source==='手动添加'?'Info':'Secondary','Regular',180),uText(d.ping+' ms',12,'Success','Medium',116),add(row('Node operations',256,48,8),uButton('连接','D/Dashboard','Ghost','power'),uButton('加入代理链','D/Chain editor','Ghost','link'))));}add(b,c,uSmall('节点名称、协议相同也不会跨来源覆盖。收藏与代理链引用随节点稳定标识保留。','Muted',1120));};
 for(const tested of [false,true])uD(tested?'Nodes tested':'Nodes',tested?'节点测速结果':'节点','统一节点库 · 14 个节点 · 2 个订阅来源 + 3 个手动节点',b=>table(b,tested),'Nodes',add(row('Node page actions',null,40,10),uButton('全部测速','D/Nodes tested','Secondary','speed'),uButton('添加节点','D/Import profile','Primary','plus')));
 for(const tested of [false,true])uM(tested?'Nodes tested':'Nodes','节点',tested?'测速已完成 · 14 个节点':'14 个节点 · 来源可以混用',b=>{add(b,input('搜索节点、地区或来源',353),tabs(['全部 14','订阅 11','手动 3'],0,353),between(add(row('Node list actions',353,40),uButton('测速','M/Nodes tested','Secondary','speed'),uButton('添加节点','M/Import profile','Primary','plus'))));for(const d of [U_NODE_DATA[1],U_NODE_DATA[0],U_NODE_DATA[2],U_NODE_DATA[3],U_NODE_DATA[5]])add(b,uLink(uNode(d,d===U_NODE_DATA[1]?353:353,d===U_NODE_DATA[1]),'M/Node details'));},'Nodes','M/Home');
 uD('Quick switch','切换连接目标','可以选择单个节点，也可以选择一条已保存的代理链。',b=>{const r=row('Connection target workspace',1120,null,24),left=v('Target choices',728,14),side=borderCard('Current target context',368,null,24,16);add(left,input('搜索节点或代理链',728),uText('代理链',16,'Text','Medium'),uLink(uSummary(),'D/Chain connected'),uText('单个节点',16,'Text','Medium'));for(const d of [U_NODE_DATA[1],U_NODE_DATA[0]]){const c=borderCard(d.name,728,null,18,8);add(c,between(add(row('Single target',692,null),uCopy(d.name,d.p+' · 来源：'+d.source+' · '+d.ping+' ms',450,15),uButton('连接','D/Dashboard','Primary','power'))));add(left,c);}add(side,uText('当前使用单个节点',18,'Text','Medium'),uSmall('东京 · 樱花 / VLESS\n来源：主订阅','Secondary',320),divider(320),uSmall('选择代理链后，所有经过该连接目标的 TCP 流量按跳点顺序转发。','Muted',320),uButton('管理代理链','D/Chains','Secondary','link',320));add(r,left,side);add(b,r);},'Dashboard',uButton('返回概览','D/Dashboard','Ghost','close'));
 uM('Quick switch','切换连接目标','单个节点或已保存的代理链',b=>{add(b,input('搜索节点或代理链',353),uSection('代理链','按顺序转发',353,uButton('管理','M/Chains','Ghost','link')),uLink(uSummary(true),'M/Chain connected'),uText('单个节点',16,'Text','Medium'));for(const d of [U_NODE_DATA[1],U_NODE_DATA[0],U_NODE_DATA[2]])add(b,uLink(uNode(d),'M/Home'));},'Home','M/Home');
}
function uChainConnected(){
 uD('Chain connected','连接已建立','当前连接目标：开发代理链 · 2 跳 · 仅 TCP',b=>{const c=borderCard('Connected chain',1120,null,28,20,'PrimarySurface');add(c,between(add(row('Connected chain title',1064,null),add(row('Connected status',null,null,12),dot('Success',8),uText('开发代理链',24,'Text','Semi Bold')),badge('已连接','Success',true))),uRouteDiagram(1064),uText('对外出口：日本 · 东京 / 东京 · 樱花',16,'Primary','Medium'),uSmall('办公 HTTP（手动） → 东京 · 樱花（主订阅）','Secondary',1064));add(b,c,add(row('Chain connection metrics',1120,112,16),metric('整链延迟','46','ms','端到端连接测量','speed','Primary',362),metric('下载速度','9.6','MB/s','经代理链转发','download','Primary',363),metric('今日流量','8.42','GB','所有连接目标汇总','chart','Primary',363)),uNote('TCP 流量通过此链','UDP 规则不能选择本代理链。可在分流规则中显式选择其他兼容出站。',1120,'Warning'),add(row('Chain connection actions',1120,48,12),uButton('切换目标','D/Quick switch','Secondary','connections'),uButton('查看编排','D/Chain editor','Secondary','link'),uButton('断开连接','D/Disconnected','Danger','power')));const bar=uFind(registry.desktop['Chain connected'],'Connection bar');const dropdown=bar.findOne(n=>n.type==='INSTANCE'&&n.name==='Dropdown / Node');if(dropdown){const text=dropdown.findOne(n=>n.type==='TEXT'&&n.characters==='Tokyo · Sakura');if(text)text.characters='开发代理链 · 2 跳';}const time=bar.findOne(n=>n.type==='TEXT'&&n.characters==='24 ms');if(time)time.characters='46 ms';},'Dashboard',uButton('管理代理链','D/Chains','Ghost','link'));
 uM('Chain connected','RainLink','当前通过 2 跳代理链连接',b=>{const c=center(borderCard('Chain connection status',353,null,22,12,'PrimarySurface'));add(c,miniIcon('power','Primary',76),uText('已连接',24,'Text','Semi Bold'),badge('开发代理链 · 2 跳','Success',true),uSmall('整链延迟 46 ms · 仅 TCP','Secondary'));uLink(c,'M/Disconnected');add(b,c,uLink(uSummary(true),'M/Chain editor'),uNote('出口：日本 · 东京','办公 HTTP → 东京 · 樱花。末尾节点决定对外出口位置。',353,'Info'),add(row('Connected chain metrics',353,94,15),mobileMetric('整链延迟','46','ms','speed','Primary'),mobileMetric('下载','9.6','MB/s','download','Primary')),uButton('切换目标','M/Quick switch','Primary','connections',353));},'Home','M/Home');
}
function uRules(){
 uD('Rules','分流规则','规则的出站可选单个节点或代理链，按优先级依次匹配。',b=>{add(b,tabs(['规则模式','全局模式','直连模式'],0,500),uNote('当前规则使用代理链','example.com 的 TCP 连接通过「开发代理链」；UDP 使用单独的兼容出站。',1120,'Info'));const c=borderCard('Rule outbound inventory',1120,null,24,10);add(c,add(row('Rule header',1072,32,16),...['匹配类型','匹配内容','出站目标','传输'].map((x,i)=>uSmall(x,'Muted',[160,340,360,164][i]))));for(const d of [['DOMAIN-SUFFIX','example.com','开发代理链 · 2 跳','TCP'],['DOMAIN-SUFFIX','github.com','东京 · 樱花','TCP / UDP'],['IP-CIDR','192.168.0.0/16','直连','TCP / UDP'],['MATCH','其他连接','东京 · 樱花','TCP / UDP']]){add(c,divider(1072),add(row('Rule outbound row',1072,58,16),...d.map((x,i)=>uText(x,13,i===2&&d[2].includes('代理链')?'Primary':'Secondary','Regular',[160,340,360,164][i]))));}add(b,c,uButton('编辑代理链出站','D/Rule editor','Secondary','rules'));},'Rules',uButton('添加规则','D/Rule editor','Primary','plus'));
 uD('Rule editor','添加分流规则','匹配条件与出站目标分开设置。',b=>{const r=row('Rule form workspace',1120,null,24),c=borderCard('Domain rule form',728,null,26,18),side=borderCard('Rule destination context',368,null,24,16);add(c,tabs(['域名规则','IP 规则'],0,676),uField('匹配方式','DOMAIN-SUFFIX',676),uField('匹配内容','example.com',676,'匹配该域名及其子域名。'),uField('传输协议','TCP',676),uLink(uField('出站目标','代理链 / 开发代理链 · 2 跳',676),'D/Quick switch'),uSmall('按从上到下的顺序匹配，放在兜底规则之前。','Muted',676),uButton('保存规则','D/Rules','Primary','check'));add(side,uText('使用已保存的代理链',18,'Text','Medium',320),uSmall('办公 HTTP（入口）\n↓\n东京 · 樱花（出口）','Primary',320),uNote('仅适用于 TCP','选择 UDP 时，本链置为不可选，并解释原因。',320,'Warning'),uButton('查看代理链','D/Chain editor','Secondary','link',320));add(r,c,side);add(b,r);},'Rules',uButton('返回规则','D/Rules','Ghost','arrow'));
}
async function uInitialize(){
 await figma.loadAllPagesAsync();await restoreLocaleBaseline();await loadChineseFonts();for(const style of ['Regular','Medium','Semi Bold','Bold'])await figma.loadFontAsync({family:'Inter',style});await figma.loadFontAsync({family:monoFamily,style:'Regular'});
 desktopPage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='desktop');mobilePage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='mobile');dsPage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='system');
 // Recover old instance text overrides once; earlier localization inherited master metadata.
 const oldTextNodes=new Map(figma.root.children.flatMap(p=>p.findAll(n=>n.type==='TEXT')).map(n=>[n.id,n]));
 for(const [id,copy] of Object.entries(PRE_UPGRADE_TEXT)){const n=oldTextNodes.get(id);if(!n)continue;const family=copy.family==='mixed'?'Noto Sans SC':copy.family,style=copy.style==='mixed'?'Regular':copy.style;if(family&&style)n.fontName={family,style};n.characters=copy.text;n.setPluginData('rainlink-original-text',copy.text);}
 const collections=await figma.variables.getLocalVariableCollectionsAsync();collection=collections.find(c=>c.name==='RainLink / Colors / Dark');lightCollection=collections.find(c=>c.name==='RainLink / Colors / Light');darkMode=collection.defaultModeId;lightMode=darkMode;for(const x of await figma.variables.getLocalVariablesAsync('COLOR')){if(x.variableCollectionId===collection.id)vars[x.name]=x;if(x.variableCollectionId===lightCollection.id)lightVars[x.name]=x;}
 for(const c of dsPage.findAll(n=>n.type==='COMPONENT')){if(c.name.startsWith('Icon / '))icons[c.name.slice(7)]=c;else if(c.name.startsWith('Style=')){const parts=c.name.split(', ');masters['Button / '+parts[0].slice(6)+' / '+parts[1].slice(5)]=c;}else if(c.name.startsWith('Tone='))masters['Badge / '+c.name.slice(5)]=c;else masters[c.name]=c;}
 for(const [r,p,prefix]of [[registry.desktop,desktopPage,'desktop/'],[registry.mobile,mobilePage,'mobile/']])for(const n of p.children.filter(n=>n.type==='FRAME'&&n.getPluginData('rainlink').startsWith(prefix)))r[n.getPluginData('rainlink').slice(prefix.length)]=n;
}
async function upgradeDocument(){
 await loadChineseFonts();uLinks=[];pending=[];
 if(!navNames.includes('Chains')){navNames.splice(3,0,'Chains');navIcons.splice(3,0,'link');}
 const side=masters['Sidebar / Desktop'],nav=uFind(side,'Primary navigation');if(nav.children.length===8){const item=navItem('Chains',false,3);nav.insertChild(3,item);await item.setReactionsAsync([]);}
 while(nav.children.length>9)nav.children[3].remove();
 for(let i=0;i<nav.children.length;i++){const item=nav.children[i];item.name='Navigate · '+navNames[i];item.setPluginData('rainlink-canonical-name',item.name);textOverride(item,'Nav label',navNames[i]);textOverride(item,'Shortcut',String(i+1));const ic=uFind(item,'Nav icon');if(ic)ic.swapComponent(icons[navIcons[i]]);}
 pending=[];
 uPrepareWidgetSlots();uComponentLibrary();uSourceOverview();uAddSource();uSubscriptionForm();uManualForm();uManualForm(true);uSuccess();uSuccess(true);uChainList();for(const state of ['default','empty','reordered','tested'])uChainEditor(state);uChainPicker();uChainUnavailable();uNodesAndSwitch();uRules();uChainConnected();uPolishChains();
 // Update shared navigation on every existing screen, including light and recovery states.
 for(const [key,screen]of Object.entries(registry.desktop)){
  const side=uFind(screen,'Sidebar / Desktop');if(side){const menu=uFind(side,'Primary navigation');const active=['Dashboard','Disconnected','Dashboard light','Quick switch','Chain connected'].includes(key)?'Dashboard':['Nodes','Nodes tested'].includes(key)?'Nodes':['Rules','Rule editor'].includes(key)?'Rules':key==='Appearance'?'Settings':key.startsWith('Chain')||key==='Chains'?'Chains':navNames.includes(key)?key:'Profiles';for(let idx=0;idx<menu.children.length;idx++){const it=menu.children[idx],target=navNames[idx];it.swapComponent(masters['Navigation / '+(target===active?'Active':'Default')]);it.name='Navigate · '+target;it.setPluginData('rainlink-canonical-name',it.name);textOverride(it,'Nav label',target);textOverride(it,'Shortcut',String(idx+1));const ic=uFind(it,'Nav icon');if(ic){ic.swapComponent(icons[navIcons[idx]]);tint(ic,target===active?'Primary':'Secondary');}uLink(it,'D/'+target);}}
 }
 for(const n of [masters['Mobile / Bottom navigation'],...mobilePage.findAll(n=>n.type==='INSTANCE'&&n.name==='Mobile / Bottom navigation')]){const tab=uFind(n,'Tab · Profiles');const label=tab&&tab.findOne(n=>n.type==='TEXT');if(label){label.characters='来源';label.setPluginData('rainlink-original-text','来源');}}
 // Keep advanced YAML / JSON editing accessible under Settings.
 const settings=registry.desktop.Settings,engine=uFind(settings,'Core engine & updates');if(engine){const b=engine.findAll(n=>n.type==='INSTANCE'&&n.name.startsWith('Button · '))[0];if(b)uLink(b,'D/Profile editor');}
 const edit=registry.desktop['Profile editor'];if(edit){const h=uFind(edit,'Page header');if(h){const texts=h.findAll(n=>n.type==='TEXT');if(texts[0]){texts[0].characters='高级内核配置';texts[0].setPluginData('rainlink-original-text','高级内核配置');}if(texts[1]){texts[1].characters='YAML / JSON 高级设置，节点来源独立保存。';texts[1].setPluginData('rainlink-original-text',texts[1].characters);}}}
 // QR import returns to a review form; it never adds data silently.
 const qr=registry.mobile['QR import'];for(const bt of qr.findAll(n=>n.type==='INSTANCE'&&n.name.startsWith('Button · '))){if(bt.name.includes('Demo: scan')){textOverride(bt,'Label','识别订阅 · 预览');bt.findAll(n=>n.type==='TEXT').forEach(t=>t.setPluginData('rainlink-original-text',t.characters));uLink(bt,'M/Subscription import');}if(bt.name.includes('Import a URL'))uLink(bt,'M/Subscription import');}const qcopy=qr.findOne(n=>n.type==='TEXT'&&n.characters.startsWith('RainLink requests camera'));if(qcopy){qcopy.characters='扫描后识别类型：订阅链接先预览来源；单个节点先确认协议、服务器和认证信息。';qcopy.setPluginData('rainlink-original-text',qcopy.characters);}
 // Existing DNS preferences now belong to the app, not to one active source.
 const dns=registry.mobile.DNS;for(const t of dns.findAll(n=>n.type==='TEXT'&&n.characters==='Use the active profile’s resolvers.')){t.characters='使用应用的网络解析设置。';t.setPluginData('rainlink-original-text',t.characters);}
 for(const [r,step,columns,startY]of [[registry.desktop,1540,3,150],[registry.mobile,473,5,150]]){let i=0;for(const n of Object.values(r)){n.x=(i%columns)*step;n.y=startY+Math.floor(i/columns)*(columns===3?1020:980);i++;}}
 await linkPrototype();
 const edges=[];for(const l of uLinks){if(!l.node||l.node.removed)continue;const [prefix,...rest]=l.target.split('/'),dest=(prefix==='D'?registry.desktop:registry.mobile)[rest.join('/')];if(!dest)throw new Error('Missing upgrade destination: '+l.target);let source=l.node;while(source.parent&&source.parent.type!=='PAGE')source=source.parent;if(source.id===dest.id)continue;await l.node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:dest.id,navigation:'NAVIGATE',transition:{type:l.animate?'SMART_ANIMATE':'DISSOLVE',easing:{type:'EASE_OUT'},duration:l.animate?.22:.18},preserveScrollPosition:false}]}]);edges.push({from:l.node.id,to:dest.id,label:l.node.name});}
 desktopPage.flowStartingPoints=[{nodeId:registry.desktop.Disconnected.id,name:'桌面端 / 连接与切换'},{nodeId:registry.desktop.Profiles.id,name:'桌面端 / 混合节点来源'},{nodeId:registry.desktop.Chains.id,name:'桌面端 / 可视化代理链'}];mobilePage.flowStartingPoints=[{nodeId:registry.mobile.Disconnected.id,name:'移动端 / 连接与切换'},{nodeId:registry.mobile.Profiles.id,name:'移动端 / 混合节点来源'},{nodeId:registry.mobile.Chains.id,name:'移动端 / 可视化代理链'},{nodeId:registry.mobile['Connection error'].id,name:'移动端 / 连接恢复'}];
 uFlowMap();
 const overview=uFind(dsPage,'Delivery / Overview');if(overview){for(const t of overview.findAll(n=>n.type==='TEXT')){if(/16 Desktop|16 个桌面/.test(t.characters)){t.characters=Object.keys(registry.desktop).length+' 个桌面端 / '+Object.keys(registry.mobile).length+' 个移动端页面';t.setPluginData('rainlink-original-text',t.characters);}if(t.characters.startsWith('Present the five')){t.characters='7 个原型入口：连接、混合来源、可视化代理链与错误恢复';t.setPluginData('rainlink-original-text',t.characters);}if(t.characters.startsWith('Connect and switch nodes.')){t.characters='追加订阅 → 独立保存手动节点 → 可视化编排 → 测试并保存 → 选择连接目标或分流出站。';t.setPluginData('rainlink-original-text',t.characters);}}}
 figma.root.setPluginData('rainlink-source-chain-version',U_VERSION);
 const raw=figma.root.getPluginData('rainlink-report'),report=raw?JSON.parse(raw):{};Object.assign(report,{version:U_VERSION,desktop:Object.fromEntries(Object.entries(registry.desktop).map(([k,n])=>[k,n.id])),mobile:Object.fromEntries(Object.entries(registry.mobile).map(([k,n])=>[k,n.id])),sourceModel:{subscriptions:2,subscriptionNodes:11,manualNodes:3,totalNodes:14,concurrentSources:true,visualChains:true,chainCodeEditor:false},upgradeEdges:edges,sourceChainGallery:dsPage.children.find(n=>n.getPluginData('rainlink-upgrade-gallery')==='true').id});figma.root.setPluginData('rainlink-report',JSON.stringify(report));return report;
}
function uFlowMap(){let root=uFind(dsPage,'Prototype Flow / Interaction map');if(!root)return;for(const c of [...root.children])c.remove();root.primaryAxisSizingMode='AUTO';add(root,uTitle('原型流程 · 混合来源与可视化代理链',1404),uSmall('桌面端与移动端遵循同一模型。来源可以共存；链引用节点；保存后显式选择出站。','Secondary',1404));for(const [title,steps,desc]of [['添加订阅',['节点来源','添加来源','导入订阅','预览并导入','统一节点库'],'订阅只更新本来源，其他订阅和手动节点完整保留。'],['添加单个节点',['节点来源','手动节点','协议与认证','输入校验','保存节点'],'HTTP / SOCKS5 等单个节点独立保存，也可加入代理链。'],['编排与连接',['代理链','选择跳点','调整顺序','测试并保存','选择连接目标'],'本机 → 入口 → 出口 → 目标；末尾跳点决定对外出口。'],['修复失效引用',['订阅变化','出口缺失','暂停使用','选择替代节点','重新测试'],'节点缺失时标记不可用，修复后显式保存，不静默换节点。']]){const c=borderCard(title,1404,null,24,16);add(c,uText(title,18,'Text','Medium'),add(row('Flow steps',1356,56,16),...steps.flatMap((s,i)=>{const n=center(rad(row('Step '+i,225,56,8,12,i===0?'PrimarySurface':'Raised'),10));add(n,uText(String(i+1).padStart(2,'0'),11,'Primary','Medium'),uText(s,13,'Text','Medium'));return i===4?[n]:[n,icon('arrow',18)];})),uSmall(desc,'Secondary',1356));add(root,c);}add(root,uNote('能力检查贯穿编排和出站选择','HTTP CONNECT 入口仅支持 TCP；需要 UDP 的节点不可加入此链。整链延迟使用端到端测量，不相加单节点 Ping。',1404,'Warning'));}
async function sourceChainMain(){
 figma.showUI('<body style="padding:24px;background:#10181e;color:#a8bac5;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#86e5c3">RainLink / 节点来源与可视化代理链</h2><p id="s">正在原位更新桌面端、移动端、共享组件与原型…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:480,height:170});
 await uInitialize();await upgradeDocument();const report=await localizeDocument();await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Profiles];figma.viewport.scrollAndZoomIntoView([registry.desktop.Profiles]);figma.notify('来源与代理链已更新 · '+report.counts.desktop+' 桌面 / '+report.counts.mobile+' 移动 · '+report.overflow.length+' 排版待检');figma.closePlugin();
}

// Final layout and interaction refinements for RainLink visual chains.
function uPrepareWidgetSlots(){
 for(const [key,c]of Object.entries(masters)){if(key.startsWith('Button / ')||key.startsWith('Input / ')){const ic=c.children.find(n=>n.type==='INSTANCE');if(ic){ic.name='Icon slot';ic.setPluginData('rainlink-canonical-name','Icon slot');}}if(key.startsWith('Navigation / ')){const ic=c.children.find(n=>n.type==='INSTANCE');if(ic){ic.name='Nav icon';ic.setPluginData('rainlink-canonical-name','Nav icon');}}}
}
function uStickyAction(screen,label,target,disabled=false){const footer=row('Fixed chain actions',393,72,0,20,'Background');footer.paddingTop=footer.paddingBottom=12;let b;if(disabled){b=instance('Button / Disabled');textOverride(b,'Label',label);b.primaryAxisSizingMode='FIXED';b.resize(353,48);b.primaryAxisAlignItems='CENTER';}else b=uButton(label,target,'Primary',label.includes('连接')?'power':label.includes('添加')?'plus':label.includes('导入')?'download':label.includes('新建')?'folder':label.includes('保存')?'check':'speed',353);add(footer,b);screen.insertChild(3,footer);}
function uThreeRoute(w,mobile=false){const values=['本机','办公 HTTP','东京 · 樱花','新加坡 · 滨海湾','目标网站'];if(mobile)return uText(values.join(' → '),12,'Primary','Medium',w);const r=row('Three-hop route',w,56,8);for(let i=0;i<values.length;i++){const box=center(rad(row('Three-hop point '+i,[76,130,144,170,104][i],48,0,8,i>0&&i<4?'PrimarySurface':'Raised'),10));add(box,uText(values[i],12,i>0&&i<4?'Primary':'Secondary','Medium'));add(r,box);if(i<4)add(r,icon('arrow',14));}return r;}
function uThreeSummary(mobile=false,w=353){const c=borderCard('Three-hop summary',w,null,20,14,'PrimarySurface');add(c,between(add(row('Three-hop summary heading',w-40,null),uText('开发代理链',18,'Text','Medium'),badge('3 跳','Success'))),uThreeRoute(w-40,mobile),uSmall('HTTP → VLESS → Trojan · 整链仅 TCP','Secondary',w-40),uSmall('出口：新加坡 · 滨海湾 · 来源：主订阅','Primary',w-40));return c;}
function uPolishChains(){
 // Root pages use an add action; close buttons are reserved for subordinate screens.
 for(const [key,target]of [['Profiles','Import profile'],['Nodes','Import profile'],['Nodes tested','Import profile'],['Chains','Chain editor']]){const h=uFind(registry.mobile[key],'Page header');const old=h.children[h.children.length-1];old.remove();add(h,uButton('','M/'+target,'Ghost','plus'));}
 // Error examples are reached by editing the port, not by a debugging button in the product UI.
 for(const [reg,prefix]of [[registry.desktop,'D/'],[registry.mobile,'M/']]){const normal=reg['Manual node'];const debug=normal.findOne(n=>n.type==='INSTANCE'&&n.name==='Button · 查看输入校验');if(debug){const t=debug.findOne(n=>n.type==='TEXT');if(t){t.characters='取消';t.setPluginData('rainlink-original-text','取消');}uLink(debug,prefix+'Profiles');}const port=uFind(normal,'端口 field');if(port)uLink(port,prefix+'Manual error');}
 // Mobile subscriptions use their own native component, avoiding inherited desktop widths.
 uNative('Source / Subscription / Mobile',c=>{c.resize(353,108);c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.paddingLeft=c.paddingRight=16;c.paddingTop=c.paddingBottom=14;c.itemSpacing=10;rad(c,12);fill(c,'Raised');stroke(c);const name=uText('主订阅',14,'Text','Medium');name.name='来源名称';const count=uSmall('8 个节点 · 2 分钟前更新','Secondary');count.name='来源状态';const interval=uSmall('每 6 小时更新');interval.name='更新频率';add(c,between(add(row('Source mobile heading',321,null),add(row('Source mobile name',null,null,10),miniIcon('refresh','Primary',28,'PrimarySurface'),name),sw(true))),between(add(row('Source mobile metadata',321,null),count,interval)));});
 const sourceBody=uFind(registry.mobile.Profiles,'Content');let subindex=0;for(const c of [...sourceBody.children])if(c.type==='INSTANCE'&&c.getPluginData('rainlink-canonical-name')==='Source / Subscription'){const newCard=instance('Source / Subscription / Mobile');if(subindex===1){uOverride(newCard,'来源名称','备用订阅');uOverride(newCard,'来源状态','3 个节点 · 18 分钟前更新');uOverride(newCard,'更新频率','每 2 小时更新');}sourceBody.insertChild(sourceBody.children.indexOf(c),newCard);uLink(newCard,'M/Nodes');c.remove();subindex++;}
 // Primary actions stay reachable without scrolling on a mobile chain editor.
 for(const key of ['Chain editor','Chain empty','Chain reordered','Chain tested']){const s=registry.mobile[key],b=uFind(s,'Content');const action=b.children.find(n=>n.type==='INSTANCE'&&['Button · 测试整链','Button · 保存代理链'].includes(n.name));if(action)action.remove();uStickyAction(s,key==='Chain tested'?'保存代理链':'测试整链',key==='Chain tested'?'M/Chains':'M/Chain tested',key==='Chain empty');}
 // Only valid reorder directions are interactive; first/last disabled controls have no action.
 uLinks=uLinks.filter(l=>{if(!l.node||l.node.removed)return false;const p=l.node.parent;return !(l.animate&&l.node.opacity<.5&&p&&p.name==='Reorder');});
 for(const p of [desktopPage,mobilePage])for(const metric of p.findAll(n=>n.name.startsWith('Metric · ')&&n.parent&&n.parent.name==='Chain connection metrics')){metric.paddingTop=metric.paddingBottom=16;metric.itemSpacing=6;}
 for(const platform of ['D','M']){
  const mobile=platform==='M',prefix=platform+'/',reg=mobile?registry.mobile:registry.desktop;
  const editor=reg['Chain editor'];const more=editor.findOne(n=>n.type==='INSTANCE'&&n.name==='Button · 添加一跳');if(more)uLink(more,prefix+'Chain add picker');
  const pickerBuild=b=>{const w=mobile?353:728,c=borderCard('Append third hop',w,null,20,16);add(c,uText('添加第 3 跳 · 新出口',18,'Text','Medium',w-40),uSmall('已选路径：办公 HTTP → 东京 · 樱花','Secondary',w-40),uLink(uNode(U_NODE_DATA[3],mobile?313:688),prefix+'Chain extended'),uSmall('加入后保留前两跳，新加坡 · 滨海湾将成为出口。','Muted',w-40),uButton('添加到链末尾',prefix+'Chain extended','Primary','plus',w-40));add(b,mobile?uNote('前两跳保持不变','同一节点不可重复加入。整条链按 TCP 转发。',353,'Info'):null,c);};
  if(mobile)uM('Chain add picker','添加一跳','追加到末尾，保留已有路径',pickerBuild,'Profiles','M/Chain editor');else uD('Chain add picker','添加第三跳','追加节点到链末尾，原有入口和中间跳点保持不变。',pickerBuild,'Chains',uButton('取消','D/Chain editor','Ghost','close'));
  // In the replacement picker, Singapore is explicitly appended; a loopback is not a remote exit.
  if(mobile){const picker=reg['Chain picker'];for(const card of picker.findAll(n=>n.type==='INSTANCE'&&n.getPluginData('rainlink-canonical-name')==='Node / With source')){const n=uFind(card,'节点名称');if(n&&n.characters==='新加坡 · 滨海湾')uLink(card,prefix+'Chain extended');if(n&&n.characters==='本地 SOCKS'){card.opacity=.4;uLinks=uLinks.filter(l=>l.node.id!==card.id);}}}
  else{const picker=reg['Chain picker'];for(const card of picker.findAll(n=>n.type==='FRAME'&&['新加坡 · 滨海湾','本地 SOCKS'].includes(n.name))){const bt=card.findOne(n=>n.type==='INSTANCE'&&n.name.startsWith('Button · '));if(bt&&card.name==='新加坡 · 滨海湾'){const t=bt.findOne(n=>n.type==='TEXT');t.characters='追加为新出口';t.setPluginData('rainlink-original-text',t.characters);uLink(bt,prefix+'Chain extended');}if(bt&&card.name==='本地 SOCKS'){bt.opacity=.4;uLinks=uLinks.filter(l=>l.node.id!==bt.id);}}}
  const extendedBuild=b=>{const w=mobile?353:728,left=mobile?b:v('Three-hop editor',728,12);add(left,uField('代理链名称','开发代理链',w),uThreeRoute(w,mobile));[U_NODE_DATA[0],U_NODE_DATA[1],U_NODE_DATA[3]].forEach((data,i)=>{const hop=uHop(data,i,mobile);if(!mobile){const address=uFind(hop,'跳点地址');if(address)address.visible=false;hop.resize(728,144);}const status=hop.findOne(n=>n.type==='INSTANCE'&&(n.name==='Badge / Success'||n.getPluginData('rainlink-canonical-name')==='Badge / Success'));if(status)textOverride(status,'Label',i===0?'入口':i===2?'出口':'中间跳点');add(left,hop);});if(!mobile){const side=borderCard('Three-hop inspector',368,null,24,18);add(side,uText('出口已更新',18,'Text','Medium'),uSmall('新加坡 · 滨海湾 / Trojan\n办公 HTTP 与东京 · 樱花继续保留。','Secondary',320),uNote('整链仅支持 TCP','来源可以混用；末尾节点决定对外出口。',320,'Warning'),uButton('测试整链','D/Chain extended tested','Primary','speed',320));add(b,add(row('Three-hop workspace',1120,null,24),left,side));}else add(b,uNote('出口：新加坡 · 滨海湾','3 跳 · HTTP → VLESS → Trojan · 仅 TCP',353,'Warning'));};
  if(mobile){const s=uM('Chain extended','编排代理链','已添加第 3 跳，出口为新加坡',extendedBuild,'Profiles','M/Chain editor');uStickyAction(s,'测试整链','M/Chain extended tested');}else uD('Chain extended','三跳代理链','入口和中间节点保持不变，新加入的最后一跳是出口。',extendedBuild,'Chains',uButton('返回两跳编排','D/Chain editor','Ghost','arrow'));
  const testedBuild=b=>{const w=mobile?353:1120;add(b,uNote('三跳链路测试通过','端到端握手成功 · 整链延迟 68 ms · 出口位于新加坡。',w,'Info'),uThreeSummary(mobile,w),uSmall('测试通过后可显式保存；点击「保存并连接」会同时选择此连接目标。','Secondary',w));if(!mobile)add(b,add(row('Three-hop tested actions',1120,48,12),uButton('保存并连接','D/Chain extended connected','Primary','power'),uButton('返回编排','D/Chain extended','Secondary','link')));};
  if(mobile){const s=uM('Chain extended tested','测试通过','整链 68 ms · 出口：新加坡',testedBuild,'Profiles','M/Chain extended');uStickyAction(s,'保存并连接','M/Chain extended connected');}else uD('Chain extended tested','三跳链路测试通过','保存并连接，或返回继续调整顺序。',testedBuild,'Chains',uButton('返回编排','D/Chain extended','Ghost','arrow'));
  const connectedBuild=b=>{const w=mobile?353:1120;add(b,uNote('已通过三跳链路连接','开发代理链已保存并设为连接目标。',w,'Info'),uThreeSummary(mobile,w),uText('68 ms',mobile?32:48,'Primary','Semi Bold',w),uSmall('整链延迟 · 端到端测量，未累加单节点 Ping。','Muted',w),uButton('查看编排',prefix+'Chain extended','Secondary','link',mobile?353:null),uButton('断开连接',prefix+'Disconnected','Danger','power',mobile?353:null));};
  if(mobile)uM('Chain extended connected','RainLink','已连接 · 3 跳 · 出口：新加坡',connectedBuild,'Home','M/Quick switch');else{const s=uD('Chain extended connected','三跳链路已连接','当前目标：开发代理链 · 出口：新加坡 · 滨海湾',connectedBuild,'Dashboard',uButton('切换目标','D/Quick switch','Secondary','connections'));const bar=uFind(s,'Connection bar');const dropdown=bar.findOne(n=>n.type==='INSTANCE'&&(n.name==='Dropdown / Node'||n.getPluginData('rainlink-canonical-name')==='Dropdown / Node'));if(dropdown){const t=dropdown.findOne(n=>n.type==='TEXT'&&n.characters.includes('Sakura'));if(t){t.characters='开发代理链 · 3 跳';t.setPluginData('rainlink-original-text',t.characters);}}const ping=bar.findOne(n=>n.type==='TEXT'&&n.characters==='24 ms');if(ping)ping.characters='68 ms';}
 }
 // A routing-target picker selects an outbound without connecting immediately.
 const routeField=uFind(registry.desktop['Rule editor'],'出站目标 field');if(routeField)uLink(routeField,'D/Rule target');
 uD('Rule target','选择规则出站','本次只设置分流规则的目标，当前连接保持不变。',b=>{add(b,uText('代理链 · TCP',18,'Text','Medium'),uLink(uSummary(false,1120),'D/Rule editor'),uText('单个节点',18,'Text','Medium'),uLink(uNode(U_NODE_DATA[1],728),'D/Rule editor'),uNote('传输协议需兼容','开发代理链含 HTTP CONNECT 入口，UDP 规则不能选择此链。',1120,'Warning'));},'Rules',uButton('返回规则编辑','D/Rule editor','Ghost','arrow'));
 // Explicit HTTP detail screen avoids presenting a manual HTTP card as VLESS.
 const office=U_NODE_DATA[0];uM('Manual details','手动节点详情','来源：手动添加',b=>{add(b,uNode(office,353,true),uField('服务器','proxy.office.example.com',353),uField('端口','8080',353),uNote('独立保存的 HTTP 节点','订阅更新不会覆盖。可直接连接，也可作为 TCP 代理链入口。',353,'Info'),uButton('加入代理链','M/Chain editor','Primary','link',353),uButton('编辑节点','M/Manual node','Secondary','settings',353));},'Nodes','M/Nodes');
 for(const key of ['Profiles','Nodes','Nodes tested'])for(const card of registry.mobile[key].findAll(n=>n.type==='INSTANCE'&&(n.name==='Node / With source'||n.getPluginData('rainlink-canonical-name')==='Node / With source'))){const name=uFind(card,'节点名称');if(name&&name.characters==='办公 HTTP')uLink(card,'M/Manual details');}
}

// RainLink 3.0: choose a group, then connect. Native, editable Auto Layout.
// Subscriptions own an automatic group. Single nodes start in Ungrouped.
const G_VERSION='4.0';
const G_MAIN=[
 U_NODE_DATA[1],U_NODE_DATA[4],U_NODE_DATA[3],
 {name:'大阪 · 晴空',p:'VMess',region:'日本 · 大阪',code:'JP',ping:'31',server:'osaka.example.com:443'},
 {name:'首尔 · 汉江',p:'TUIC',region:'韩国 · 首尔',code:'KR',ping:'42',server:'seoul.example.com:443'},
 {name:'洛杉矶 · 日落',p:'Shadowsocks',region:'美国 · 洛杉矶',code:'US',ping:'126',server:'la.example.com:8388'},
 {name:'台北 · 山岚',p:'SOCKS5',region:'中国台湾 · 台北',code:'TW',ping:'35',server:'taipei.example.com:1080'},
 {name:'悉尼 · 海风',p:'HTTP',region:'澳大利亚 · 悉尼',code:'AU',ping:'156',server:'sydney.example.com:8080'}
];
const G_BACKUP=[U_NODE_DATA[5],{name:'纽约 · 曼哈顿',p:'Trojan',region:'美国 · 纽约',code:'US',ping:'182',server:'ny.example.com:443'},{name:'法兰克福 · 莱茵',p:'VMess',region:'德国 · 法兰克福',code:'DE',ping:'146',server:'de.example.com:443'}];
const G_LOOSE=[U_NODE_DATA[0],U_NODE_DATA[2],U_NODE_DATA[6]];
const G_LABELS={Profiles:'分组','Import profile':'添加节点','Manual node':'添加单个节点','Source success':'订阅组已添加','Manual success':'单个节点已添加',Nodes:'主订阅 · 节点','Nodes tested':'主订阅 · 测速结果','Quick switch':'切换分组',Ungrouped:'未分组','Move group':'移动到分组',Moved:'已移入主订阅','New group':'新建分组',Customgroup:'开发环境', 'Backup group':'备用订阅 · 节点','Backup connected':'已连接备用订阅','Manual connected':'已连接未分组节点',Chains:'主订阅 · 代理链','Chain editor':'可视化编排','Chain reordered':'调整链路顺序','Chain empty':'添加出口节点','Chain picker':'选择链路节点','Chain tested':'链路测试通过','Chain connected':'已连接代理链','Node details':'节点详情'};
let gRebuilt=new Set();
function gMark(s){s.setPluginData('rainlink-group-version',G_VERSION);gRebuilt.add(s.id);return s;}
function gD(key,title,sub,build,active='Profiles',actions=null){return gMark(uD(key,title,sub,build,active,actions||uButton('返回分组','D/Profiles','Ghost','arrow')));}
function gM(key,title,sub,build,active='Profiles',back='M/Profiles',root=false){const s=gMark(uM(key,title,sub,build,active,back));const h=uFind(s,'Page header');if(root){h.children[h.children.length-1].remove();add(h,uButton('',back,'Ghost','plus'));}else{const b=h.children[h.children.length-1],ic=b.findOne(n=>n.type==='INSTANCE');if(ic&&icons.back)ic.swapComponent(icons.back);h.insertChild(0,b);}return s;}
function gNative(name,build){let c=masters[name];if(c){for(const n of [...c.children])n.remove();build(c);}else c=component(name,build);c.setPluginData('rainlink-group-component',G_VERSION);return c;}
function gLibraryV3(){
 navIcons[2]='folder';for(const d of G_LOOSE)d.source='未分组';
 gNative('Dropdown / Protocol',c=>{c.resize(353,40);c.layoutMode='HORIZONTAL';c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.counterAxisAlignItems='CENTER';c.primaryAxisAlignItems='SPACE_BETWEEN';c.paddingLeft=c.paddingRight=12;fill(c,'Raised');rad(c,10);stroke(c);const t=grow(uText('HTTP',13,'Text','Medium'));t.name='协议值';add(c,t,icon('down',14));});
 if(!icons.back)icons.back=gNative('Icon / back',c=>{c.resize(20,20);c.layoutMode='HORIZONTAL';c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';const n=figma.createNodeFromSvg('<svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M12 4L6 10L12 16" stroke="#A8BAC5" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>');add(c,n);});
 for(const mobile of [false,true]){
  const w=mobile?353:744,inner=w-32;
  gNative('Group / '+(mobile?'Mobile':'Desktop'),c=>{c.resize(w,136);c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.paddingLeft=c.paddingRight=16;c.paddingTop=c.paddingBottom=16;c.itemSpacing=12;rad(c,14);fill(c,'Surface');stroke(c);
   const node=uText('东京 · 樱花',13,'Secondary','Medium');node.name='组当前节点';const ping=uSmall('24 ms','Primary');ping.name='组延迟';
   const head=between(add(row('Group heading',inner,null,8),add(row('Group identity',null,null,12),miniIcon('folder','Primary',36,'PrimarySurface'),uCopy('主订阅','8 个节点 · 订阅自动更新',mobile?182:400,16)),badge('订阅','Neutral')));
   head.children[0].children[1].children[0].name='组名称';head.children[0].children[1].children[1].name='组信息';
   const action=btn('连接','Secondary',mobile?'M':'M','power');action.name='组连接';action.setPluginData('rainlink-canonical-name','组连接');
   add(c,head,between(add(row('Group current node',inner,null,10),add(row('Group current identity',null,null,8),dot('Primary',5),node,ping),action)));
  });
  gNative('Group node / '+(mobile?'Mobile':'Desktop'),c=>{const nw=mobile?353:728,iw=nw-32;c.resize(nw,mobile?108:62);c.layoutMode='VERTICAL';c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.paddingLeft=c.paddingRight=16;c.paddingTop=c.paddingBottom=mobile?14:10;c.itemSpacing=8;rad(c,mobile?12:8);fill(c,'Surface');stroke(c,mobile?'Stroke':'Surface');
   const name=uText('东京 · 樱花',14,'Text','Medium');name.name='节点名称';const region=uSmall('日本 · 东京','Muted');region.name='节点地区';const ping=uText('24 ms',12,'Primary','Medium');ping.name='节点延迟';const protocol=badge('VLESS');protocol.name='节点协议';protocol.setPluginData('rainlink-canonical-name','节点协议');const check=icon('check',16,'Primary');check.name='节点选中';check.setPluginData('rainlink-canonical-name','节点选中');const star=btn('','Ghost','M','star');star.name='节点收藏';
   if(mobile){add(c,between(add(row('Node identity',iw,null,8),add(row('Node name',null,null,10),country('JP',28),name),ping)),between(add(row('Node metadata',iw,null,8),add(row('Node protocol region',null,null,8),protocol,region),add(row('Node actions',null,null,4),check,star))));}
   else add(c,between(add(row('Node row',iw,40,8),add(row('Node identity',null,null,12),country('JP',32),uCopy('东京 · 樱花','日本 · 东京',260,14)),add(row('Node facts',null,null,16),protocol,ping,star,check))));
   if(!mobile){name.remove();region.remove();const cp=c.children[0].children[0].children[1];cp.children[0].name='节点名称';cp.children[1].name='节点地区';}const ct=c.findOne(n=>n.type==='TEXT'&&n.characters==='JP');ct.name='国家标记';ct.setPluginData('rainlink-canonical-name','国家标记');const move=btn('移动','Ghost','M','folder');move.name='未分组节点移动';move.setPluginData('rainlink-canonical-name',move.name);move.visible=false;add(mobile?c.children[1].children[1]:c.children[0].children[1],move);
  });
 }
 // Keep existing reusable sidebar identity while removing the extra Chains destination.
 const side=masters['Sidebar / Desktop'];const temp=sidebar('Profiles');for(const n of [...side.children])n.remove();for(const n of [...temp.children])side.appendChild(n);temp.remove();
 side.resize(248,900);side.primaryAxisSizingMode='FIXED';side.counterAxisSizingMode='FIXED';
 for(const n of side.findAll(n=>n.name==='Navigate · Profiles')){textOverride(n,'Nav label','分组');const ic=uFind(n,'Nav icon');if(ic)ic.swapComponent(icons.folder);}
 const mobileMaster=masters['Mobile / Bottom navigation'];const pt=mobileMaster.findOne(n=>(n.getPluginData('rainlink-canonical-name')||n.name)==='Tab · Profiles');if(pt){const t=pt.findOne(n=>n.type==='TEXT');t.characters='分组';t.setPluginData('rainlink-original-text','分组');const ic=pt.findOne(n=>n.type==='INSTANCE');if(ic)ic.swapComponent(icons.folder);}
}
function gGroup(name,count,type,node,mobile=false,detail='Nodes',connected='Dashboard',meta=null){if(mobile&&type==='未分组')meta=count+' 个节点 · 手动添加';const c=instance('Group / '+(mobile?'Mobile':'Desktop'));c.name='Group · '+name;c.setPluginData('rainlink-canonical-name',c.name);uOverride(c,'组名称',name);uOverride(c,'组信息',meta||count+' 个节点 · '+(type==='订阅'?'订阅自动更新':'手动添加'));uOverride(c,'组当前节点',node.name);uOverride(c,'组延迟',node.ping+' ms');const tag=c.findOne(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name)==='Badge / Neutral');if(tag)textOverride(tag,'Label',type);const prefix=mobile?'M/':'D/';uLink(c,prefix+detail);const b=uFind(c,'组连接');if(b){textOverride(b,'Label','连接');uLink(b,prefix+connected);}return c;}
function gNode(data,mobile=false,selected=false,loose=false){const c=instance('Group node / '+(mobile?'Mobile':'Desktop'));uOverride(c,'节点名称',data.name);uOverride(c,'节点地区',data.region);uOverride(c,'节点延迟',data.ping+' ms');uOverride(c,'国家标记',data.code);const prot=uFind(c,'节点协议');textOverride(prot,'Label',data.p);const selectedIcon=uFind(c,'节点选中');selectedIcon.visible=selected;
 if(selected){fill(c,'PrimarySurface');stroke(c,'Primary');}if(loose){selectedIcon.visible=false;const move=uFind(c,'未分组节点移动');move.visible=true;if(data.name==='办公 HTTP')uLink(move,(mobile?'M/':'D/')+'Move group');}return c;}
function gGroups(key='Profiles',state='base'){
 for(const mobile of [false,true]){const prefix=mobile?'M/':'D/',build=b=>{const w=mobile?353:1120;
   if(state!=='base')add(b,uSmall(state==='subscription'?'已导入「旅行订阅」，自动创建 4 节点分组。':state==='manual'?'「备用 HTTP」已加入未分组。':state==='moved'?'「办公 HTTP」已移入主订阅，未分组剩余 2 个节点。':'「开发环境」已创建，办公 HTTP 已移入。','Primary',w));
   if(mobile){add(b,add(row('Group toolbar',353,28),uSmall((['subscription','custom'].includes(state)?'4':'3')+' 个分组 · '+(state==='subscription'?18:state==='manual'?15:14)+' 个节点','Secondary')));}
   else add(b,between(add(row('Group toolbar',1120,40),input('搜索分组…',344,'search'),uSmall('按分组连接，节点自动归组。','Muted'))));
   const left=mobile?b:v('Group list',744,16),moved=state==='moved',loose=state==='manual'?4:moved||state==='custom'?2:3;
   add(left,gGroup('主订阅',moved?9:8,'订阅',G_MAIN[0],mobile,moved?'Moved nodes':'Nodes','Dashboard',moved?'8 个订阅节点 + 1 个手动节点':null),gGroup('备用订阅',3,'订阅',G_BACKUP[0],mobile,'Backup group','Backup connected'),gGroup('未分组',loose,'未分组',G_LOOSE[moved||state==='custom'?1:0],mobile,state==='manual'?'Manual added nodes':moved||state==='custom'?'Ungrouped after move':'Ungrouped',moved||state==='custom'?'Local connected':'Manual connected',''+loose+' 个节点 · 单个节点默认放在这里'));
   if(state==='subscription')add(left,gGroup('旅行订阅',4,'订阅',G_MAIN[2],mobile,'Travel group','Travel connected','4 个节点 · 刚刚导入'));
   if(state==='custom')add(left,gGroup('开发环境',1,'自建',G_LOOSE[0],mobile,'Customgroup','Custom connected','1 个节点 · 手动分组'));
   if(!mobile){const side=borderCard('Group current connection',352,null,24,18,'Raised');add(side,between(add(row('Current heading',304,null),uSmall('当前连接','Secondary'),badge('已连接','Success',true))),uText('主订阅',22,'Text','Medium'),uText('东京 · 樱花',15,'Secondary','Medium'),add(row('Current facts',304,null,8),badge('VLESS'),uSmall('24 ms','Primary')),divider(304),uSmall('切换分组时，使用该组上次选择的节点。','Muted',304),uButton('查看概览','D/Dashboard','Secondary','grid',304));add(b,add(row('Group workspace',1120,null,24),left,side));}
   add(b,uSmall('订阅 → 自动建组　·　单个节点 → 未分组','Muted',w));
  };if(mobile)gM(key,'分组',state==='base'?'选一组，直接连接':'自动归组完成',build,'Profiles','M/Import profile',true);else gD(key,'分组',state==='base'?'选一组，使用该组当前节点连接。':'节点已自动整理到对应分组。',build,'Profiles',uButton('添加节点','D/Import profile','Primary','plus'));
 }
}
function gNodePage(key,title,data,loose=false,moved=false,tested=false){
 for(const mobile of [false,true]){const prefix=mobile?'M/':'D/',connected=title==='备用订阅'?'Backup connected':title==='未分组'?(data[0].name==='本地 SOCKS'?'Local connected':'Manual connected'):title==='旅行订阅'?'Travel connected':title==='开发环境'?'Custom connected':'Dashboard';const build=b=>{
   const w=mobile?353:1120;add(b,between(add(row('Group node toolbar',w,40,8),uButton('全部分组',prefix+(key==='Moved nodes'?'Moved':key==='Customgroup'?'Groups custom':key==='Manual added nodes'?'Manual success':title==='旅行订阅'?(mobile?'Import success':'Source success'):'Profiles'),'Ghost','folder'),uButton(tested?'测速完成':'测速',prefix+(key==='Nodes'?'Nodes tested':key),'Secondary','speed'))));
   const list=mobile?b:borderCard('Group node inventory',728,null,0,0);
   for(let i=0;i<data.length;i++){add(list,gNode(data[i],mobile,i===0,loose));if(!mobile&&i<data.length-1)add(list,divider(728));}
   if(!mobile){const aside=borderCard('Selected group node',368,null,24,16);add(aside,uSmall('该组当前节点','Secondary'),uText(data[0].name,21,'Text','Medium',320),add(row('Selected node protocol',320,null,12),badge(data[0].p),uSmall(data[0].ping+' ms','Primary')),uSmall(data[0].region,'Muted',320),divider(320),uButton('连接此组',prefix+connected,'Primary','power',320));if(loose)add(aside,uSmall('只有未分组节点可以移动。移入分组后，移动入口消失。','Muted',320));else if(title==='主订阅')add(aside,uButton('代理链',prefix+'Chains','Ghost','link',320));if(moved)add(aside,uSmall((title==='主订阅'?'8':'3')+' 个订阅节点 + 1 个手动节点。\n订阅更新会保留手动加入的节点。','Muted',320));add(b,add(row('Group node workspace',1120,null,24),list,aside));}
   else{if(!loose&&title==='主订阅')add(b,uButton('代理链',prefix+'Chains','Ghost','link',353));if(moved)add(b,uSmall((title==='主订阅'?'8':'3')+' 个订阅节点 + 1 个手动节点。订阅更新保留手动节点。','Muted',353));}
   if(loose)add(b,uSmall('仅未分组节点提供移动操作。','Muted',w));
  };if(mobile){const s=gM(key,title,data.length+' 个节点'+(loose?' · 可移动到分组':''),build,'Nodes','M/Profiles');uStickyAction(s,'连接此组',prefix+connected);}else gD(key,title,data.length+' 个节点 · '+(loose?'单个节点默认进入这里。':moved?'订阅与手动节点都已归入本组。':'选择节点后，可直接连接此组。'),build,'Nodes',uButton('添加节点',prefix+'Import profile','Primary','plus'));
 }
}
function gAddForms(manual=false){
 for(const mobile of [false,true]){const prefix=mobile?'M/':'D/',key=manual?'Manual node':'Import profile',w=mobile?353:600,build=b=>{
   const f=mobile?b:borderCard('Simple add form',648,null,24,20),fw=mobile?353:600;const t=tabs(['订阅','单个节点'],manual?1:0,fw);for(let i=0;i<t.children.length;i++)uLink(t.children[i],prefix+(i?'Manual node':'Import profile'));add(f,t);
   if(manual){const protocol=instance('Dropdown / Protocol');protocol.resize(fw,40);add(f,add(v('协议 field',fw,8),uSmall('协议','Secondary'),protocol),uField('服务器','proxy.backup.example.com',fw),add(row('Single node address',fw,null,12),uField('端口','8080',mobile?110:180),uField('名称（可选）','备用 HTTP',mobile?231:408)),uField('用户名（可选）','未设置',fw),uField('密码（可选）','未设置',fw),uSmall('保存后自动进入「未分组」。','Muted',fw));}
   else add(f,uField('订阅链接','https://example.com/sub/travel',fw),uField('分组名称','旅行订阅',fw,'自动识别，可修改'),between(add(row('Subscription update',fw,52),uCopy('自动更新','每 6 小时',fw-80,14),sw(true))),uSmall('导入后自动创建同名分组。','Muted',fw),mobile?uButton('扫码导入',prefix+'QR import','Ghost','qr'):null);
   if(!mobile){add(f,uButton(manual?'添加节点':'导入订阅',prefix+(manual?'Manual success':'Source success'),'Primary',manual?'plus':'download',fw));add(b,f);}
  };if(mobile){const s=gM(key,'添加节点','自动归组，无需先创建分组',build,'Profiles','M/Profiles');uStickyAction(s,manual?'添加节点':'导入订阅',prefix+(manual?'Manual success':'Import success'));}else gD(key,'添加节点','订阅自动成为一组，单个节点进入未分组。',build,'Profiles',uButton('取消',prefix+'Profiles','Ghost','close'));
 }
}
function gMoveScreens(){
 for(const mobile of [false,true]){const prefix=mobile?'M/':'D/',w=mobile?353:648,build=b=>{const c=mobile?b:borderCard('Move node form',696,null,24,20);add(c,uSmall('移动「办公 HTTP」','Secondary',w));for(const [name,count,target]of [['主订阅','8 个节点','Moved'],['备用订阅','3 个节点','Moved backup']]){const r=between(add(row('Move destination '+name,w,72,12,16,'Surface'),add(row('Destination identity',null,null,12),miniIcon('folder','Primary',32,'PrimarySurface'),uCopy(name,count,mobile?170:430,16)),icon('chevron',16)));rad(r,12);stroke(r);uLink(r,prefix+target,true);add(c,r);}add(c,uButton('新建分组',prefix+'New group','Ghost','plus',w),uSmall('选择分组即完成移动。归组后不再显示移动入口。','Muted',w));if(!mobile)add(b,c);};if(mobile)gM('Move group','移动到分组','来自未分组',build,'Nodes','M/Ungrouped');else gD('Move group','移动到分组','仅未分组节点可以移动，选择目标后立即归组。',build,'Nodes',uButton('取消','D/Ungrouped','Ghost','close'));
   const create=b=>{add(b,uField('分组名称','开发环境',mobile?353:600),uSmall('创建后将「办公 HTTP」移入此组。','Muted',mobile?353:600));if(!mobile)add(b,uButton('新建并移入','D/Customgroup','Primary','folder',600));};if(mobile){const s=gM('New group','新建分组','收纳未分组节点',create,'Nodes','M/Move group');uStickyAction(s,'新建并移入','M/Customgroup');}else gD('New group','新建分组','创建自定义分组并移入当前节点。',create,'Nodes',uButton('取消','D/Move group','Ghost','close'));
 }
}
function gTrend(data,chain=false){const c=borderCard('Group latency trend',716,230,22,12);add(c,between(add(row('Latency chart heading',672,null),uText('延迟趋势',16,'Text','Medium'),uSmall(chain?'开发代理链 · 最近 30 分钟':data.name+' · 最近 30 分钟','Muted'))),chart(672,80),between(add(row('Latency time axis',672,null),uSmall('10:00'),uSmall('10:10'),uSmall('10:20'),uSmall('10:30'))),uSmall('平均 '+(chain==='reverse'?'39':chain?'46':data.ping)+' ms　·　抖动 2 ms','Secondary'));return c;}
function gHealth(group,data){const c=borderCard('Group health',380,230,20,10);const list=group==='备用订阅'?G_BACKUP:group==='未分组'?G_LOOSE:group==='开发环境'?[G_LOOSE[0]]:G_MAIN;add(c,between(add(row('Health heading',340,null),uText('节点健康',16,'Text','Medium'),badge(list.length+'/'+list.length+' 在线','Success'))));for(const n of list.slice(0,3))add(c,between(add(row('Health '+n.name,340,28,8),add(row('Health node identity',null,null,8),dot('Primary',5),uSmall(n.name,'Secondary')),uSmall(n.ping+' ms','Primary'))));add(c,uButton('管理分组','D/Profiles','Ghost','folder'));return c;}
function gHome(key,group='主订阅',data=G_MAIN[0],online=true,chain=false){
 const mobileKey=key==='Dashboard'?'Home':key==='Dashboard light'?'Home light':key;
 const light=key==='Dashboard light',connectedKey=chain?(chain==='reverse'?'Chain reverse connected':'Chain connected'):group==='备用订阅'?'Backup connected':group==='开发环境'?'Custom connected':group==='未分组'?(data.name==='本地 SOCKS'?'Local connected':'Manual connected'):group==='旅行订阅'?'Travel connected':'Dashboard';
 const db=b=>{const hero=borderCard('Connection group hero',1120,212,28,20,online?'PrimarySurface':'Surface');add(hero,between(add(row('Connection hero heading',1064,null),add(row('Connection state',null,null,8),dot(online?'Primary':'Muted'),uText(online?'已连接':'未连接',13,online?'Primary':'Muted','Medium')),badge('规则模式','Success'))),between(add(row('Connection group summary',1064,null),uCopy(group,chain?(chain==='reverse'?'东京 · 樱花 → 办公 HTTP':'办公 HTTP → 东京 · 樱花'):data.name,760,30),uButton(online?'断开连接':'连接此组',online?'D/Disconnected':'D/'+connectedKey,'Primary','power'))),between(add(row('Connection group bottom',1064,null),add(row('Current connection facts',null,null,12),badge(chain?'2 跳 · TCP':data.p),uSmall(online?(chain==='reverse'?'39':chain?'46':data.ping)+' ms':'— ms','Secondary')),uButton('切换分组','D/Quick switch','Ghost','connections'))));add(b,hero,add(row('Network stats',1120,86,16),uMetric('今日流量','8.42 GB','↓ 7.86 GB　↑ 560 MB',362),uMetric('下载速度',online?'12.8 MB/s':'0 MB/s','上传 '+(online?'1.4':'0')+' MB/s',362),uMetric('网络质量',online?'98 / 100':'—',''+(online?'稳定 · 丢包 0%':'等待连接'),364)),add(row('Connection trends',1120,230,24),gTrend(data,chain),gHealth(group,data)),between(add(row('Recent connection record',1120,28),uSmall('最近连接','Muted'),uSmall('api.github.com','Secondary'),badge('代理','Success'),uSmall('192.168.1.1','Secondary'),badge('直连'),uLink(btn('查看','Ghost','S'),'D/Connections'))));};
 const ds=gD(key,online?'概览':'准备连接',online?'当前分组和节点，一眼可见。':'选择一个分组，开始连接。',db,'Dashboard',uButton('切换分组','D/Quick switch','Secondary','connections'));if(light)applyLight(ds);
 const mb=(b,s)=>{const hero=mobileHero(online);const ring=uFind(hero,'Connection ring');ring.resize(96,96);ring.children[0].resize(94,94);const power=ring.children[1];power.resize(76,76);power.x=10;power.y=10;hero.paddingTop=hero.paddingBottom=16;for(const n of hero.findAll(n=>n.type==='TEXT')){if(n.characters==='Connected')n.characters='已连接';if(n.characters==='Ready to connect')n.characters='准备连接';}uLink(uFind(hero,'Connection ring'),online?'M/Disconnected':'M/'+(connectedKey==='Dashboard'?'Home':connectedKey));hero.resize(353,220);hero.itemSpacing=5;add(b,hero);const c=borderCard('Selected connection group',353,null,16,12);c.itemSpacing=8;add(c,between(add(row('Selected group heading',321,null),uText(group,18,'Text','Medium'),uButton('切换','M/Quick switch','Ghost','connections'))),between(add(row('Selected group node',321,null),uText(chain?(chain==='reverse'?'东京 · 樱花 → 办公 HTTP':'办公 HTTP → 东京 · 樱花'):data.name,12,'Secondary','Medium'),uSmall(online?(chain==='reverse'?'39':chain?'46':data.ping)+' ms':'未连接','Primary'))));add(b,c,add(row('Mobile live speed',353,86,15),uMetric('下载',online?'12.8':'0','MB/s',169),uMetric('上传',online?'1.4':'0','MB/s',169)),between(add(row('Today traffic simple',353,44),uCopy('今日流量','↓ 7.86 GB　↑ 560 MB',235,12),uLink(uText('8.42 GB',18,'Text','Medium'),'M/Traffic'))));};const ms=gM(mobileKey,'RainLink',online?'已连接 · '+group:'点一下，连接当前分组',mb,'Home','M/Settings');const mh=uFind(ms,'Page header');const mbt=mh.children[0];mh.appendChild(mbt);const mic=mbt.findOne(n=>n.type==='INSTANCE');if(mic){mic.swapComponent(icons.settings);}if(light)applyLight(ms);
}
function gSwitch(){
 for(const mobile of [false,true]){const prefix=mobile?'M/':'D/',build=b=>{for(const args of [['主订阅',8,'订阅',G_MAIN[0],'Nodes','Dashboard'],['备用订阅',3,'订阅',G_BACKUP[0],'Backup group','Backup connected'],['未分组',3,'未分组',G_LOOSE[0],'Ungrouped','Manual connected']])add(b,gGroup(args[0],args[1],args[2],args[3],mobile,args[4],args[5]));add(b,uSmall('点「连接」切换分组；点卡片可进入组内选节点。','Muted',mobile?353:744));};if(mobile)gM('Quick switch','切换分组','使用各组上次选择的节点',build,'Home','M/Home');else gD('Quick switch','切换分组','点连接即可切换，进入分组可更换当前节点。',build,'Dashboard',uButton('关闭','D/Dashboard','Ghost','close'));
 }
}
function gChainFlowV3(){
 for(const mobile of [false,true]){const prefix=mobile?'M/':'D/',w=mobile?353:728;
  const list=b=>{add(b,uSmall('主订阅内的可选连接方式','Muted',mobile?353:1120),uLink(uSummary(mobile,w),prefix+'Chain editor'),uButton('编排代理链',prefix+'Chain editor','Secondary','link',w));};if(mobile)gM('Chains','代理链','主订阅',list,'Nodes','M/Nodes');else gD('Chains','主订阅 · 代理链','需要多跳时再进入，日常直接连接分组。',list,'Nodes',uButton('返回节点','D/Nodes','Ghost','arrow'));
  for(const state of ['default','reordered','empty','tested','reverse-tested']){const key={default:'Chain editor',reordered:'Chain reordered',empty:'Chain empty',tested:'Chain tested','reverse-tested':'Chain reverse tested'}[state],swap=['reordered','reverse-tested'].includes(state),empty=state==='empty',tested=['tested','reverse-tested'].includes(state),build=b=>{const f=mobile?b:v('Simple visual chain',728,12);add(f,uField('链名称','开发代理链',w),uRouteDiagram(w,mobile,swap,empty));const vals=swap?[G_MAIN[0],G_LOOSE[0]]:[G_LOOSE[0],G_MAIN[0]];for(let i=0;i<(empty?1:2);i++){const hop=uHop(vals[i],i,mobile,swap,empty);if(!mobile){hop.resize(728,142);hop.itemSpacing=8;}add(f,hop);}if(empty)add(f,uButton('选择出口节点',prefix+'Chain picker','Secondary','plus',w));else add(f,uSmall(tested?(swap?'测试通过 · 整链 39 ms · 出口：办公 HTTP':'测试通过 · 整链 46 ms · 出口：日本东京'):'按顺序转发，最后一跳是出口。',''+(tested?'Primary':'Muted'),w));if(!mobile){const side=borderCard('Simple chain actions',368,null,24,16);add(side,uText(tested?'测试通过':'链路状态',18,'Text','Medium'),uSmall(tested?(swap?'端到端握手成功 · 39 ms':'端到端握手成功 · 46 ms'):'HTTP 入口，仅支持 TCP。','Secondary',320),uButton(tested?'保存并连接':'测试链路',prefix+(tested?(swap?'Chain reverse connected':'Chain connected'):(swap?'Chain reverse tested':'Chain tested')),'Primary',tested?'power':'speed',320),uButton('返回分组',prefix+'Profiles','Ghost','folder',320));if(empty)side.children[2].opacity=.35;add(b,add(row('Visual chain workspace',1120,null,24),f,side));}};if(mobile){const s=gM(key,'可视化编排','主订阅 · 开发代理链',build,'Nodes','M/Chains');uStickyAction(s,tested?'保存并连接':'测试链路',prefix+(tested?(swap?'Chain reverse connected':'Chain connected'):(swap?'Chain reverse tested':'Chain tested')),empty);}else gD(key,'可视化编排','从已有节点选择跳点，调整顺序后测试。',build,'Nodes',uButton('返回节点','D/Nodes','Ghost','arrow'));
  }
  const picker=b=>{add(b,uSmall('入口：办公 HTTP · 未分组','Secondary',w),uLink(gNode(G_MAIN[0],mobile,true),prefix+'Chain editor'),uSmall('选择东京节点作为出口，补全这条两跳链。','Muted',w));};if(mobile)gM('Chain picker','选择出口','主订阅',picker,'Nodes','M/Chain editor');else gD('Chain picker','选择出口节点','从现有分组中选择链路出口。',picker,'Nodes',uButton('取消','D/Chain editor','Ghost','close'));
 }
 gHome('Chain connected','主订阅',G_MAIN[0],true,true);gHome('Chain reverse connected','主订阅',G_LOOSE[0],true,'reverse');
}
async function gPatchExistingV3(){
 // All remaining major screens share the same group-first navigation and top status.
 for(const [reg,prefix]of [[registry.desktop,'D/'],[registry.mobile,'M/']])for(const [key,s]of Object.entries(reg)){
  const mobile=prefix==='M/';if(!gRebuilt.has(s.id)&&!mobile){const old=s.children.find(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name)==='Sidebar / Desktop');if(old){const ix=s.children.indexOf(old);old.remove();s.insertChild(ix,uSide(key==='Appearance'?'Settings':['Rule editor'].includes(key)?'Rules':navNames.includes(key)?key:'Profiles'));}}
  for(const n of s.findAll(n=>'reactions'in n)){const canonical=n.getPluginData('rainlink-canonical-name')||n.name;if(canonical.startsWith('Navigate · ')){const dest=canonical.slice(11);uLink(n,prefix+dest);}if(canonical.startsWith('Tab · ')){const dest=canonical.slice(6);uLink(n,prefix+dest);if(dest==='Profiles'){const t=n.findOne(c=>c.type==='TEXT');if(t){t.characters='分组';t.setPluginData('rainlink-original-text','分组');}}}}
  if(!mobile){const bar=uFind(s,'Connection bar');if(bar){const old=bar;const main=old.parent;const ix=main.children.indexOf(old);old.remove();const status=between(row('Connection bar',1192,68,16,0,'Surface'));status.paddingLeft=status.paddingRight=36;stroke(status);const online=key!=='Disconnected',group=key==='Backup connected'?'备用订阅':key==='Custom connected'?'开发环境':['Manual connected','Local connected'].includes(key)?'未分组':key==='Travel connected'?'旅行订阅':'主订阅',data=key==='Backup connected'?G_BACKUP[0]:key==='Manual connected'||key==='Custom connected'?G_LOOSE[0]:key==='Local connected'?G_LOOSE[1]:key==='Travel connected'?G_MAIN[2]:G_MAIN[0];add(status,add(row('Persistent group status',null,null,10),dot(online?'Primary':'Muted'),uText(online?'已连接':'未连接',13,online?'Primary':'Muted','Medium'),uSmall(group+' / '+(['Chain connected','Chain reverse connected'].includes(key)?'开发代理链':data.name),'Secondary')),add(row('Persistent group speeds',null,null,16),uSmall(online?(key==='Chain reverse connected'?'39':key==='Chain connected'?'46':data.ping)+' ms':'— ms','Secondary'),uSmall('↓ '+(online?'12.8':'0')+' MB/s','Secondary'),uSmall('↑ '+(online?'1.4':'0')+' MB/s','Muted'),uButton('切换分组','D/Quick switch','Ghost','connections')));main.insertChild(ix,status);}}
 }
 const qr=registry.mobile['QR import'];if(qr){for(const t of qr.findAll(n=>n.type==='TEXT'))if(t.characters.startsWith('RainLink requests camera')||t.characters.startsWith('扫描后')){t.characters='识别为订阅时自动创建分组；识别为单个节点时进入未分组。';t.setPluginData('rainlink-original-text',t.characters);}for(const n of qr.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Button · ')))uLink(n,'M/Import profile');}
 // Advanced configuration remains reachable in settings, outside the add-node task.
 const settings=registry.desktop.Settings;const settingsHeader=uFind(settings,'Page header');if(settingsHeader){const a=uButton('高级配置','D/Profile editor','Ghost','terminal');const old=settingsHeader.children[settingsHeader.children.length-1];old.remove();add(settingsHeader,a);}
 for(const reg of [registry.desktop,registry.mobile])for(const [key,s]of Object.entries(reg))if(!gRebuilt.has(s.id))for(const t of s.findAll(n=>n.type==='TEXT'))if(/节点来源|当前配置|活动配置|active profile|来源独立/.test(t.characters)){t.characters=t.characters.replace(/节点来源/g,'分组').replace(/当前配置|活动配置/g,'当前分组').replace(/active profile/g,'current group').replace(/节点来源独立保存/g,'节点按分组保存');t.setPluginData('rainlink-original-text',t.characters);}
}
function gSystemV3(){
 const map=uFind(dsPage,'Prototype Flow / Interaction map');for(const n of [...map.children])n.remove();map.primaryAxisSizingMode='AUTO';add(map,uTitle('原型流程 · 自动分组',1404),uSmall('两端统一：添加时自动归组，按分组直接连接。','Secondary',1404));
 for(const [title,steps,desc]of [['订阅',['添加节点','粘贴订阅','自动创建同名组','连接此组'],'更新只同步该订阅；手动加入本组的节点独立保留。'],['单个节点',['添加节点','填写 HTTP 等节点','自动进入未分组','直接连接或移动'],'添加时不要求用户选择分组。'],['移动分组',['未分组','节点上的移动','选择现有组或新建组','移动完成'],'只有未分组节点能移动；已归组及订阅节点都不显示移动操作。'],['连接与代理链',['选择分组','连接上次选中的节点','需要多跳时进入代理链','可视化编排并连接'],'代理链是组内可选入口；无需代码编辑。']]){const c=borderCard(title,1404,null,24,16);add(c,uText(title,18,'Text','Medium'));const r=row('Group flow steps',1356,56,20);for(let i=0;i<steps.length;i++){add(r,center(add(rad(row('Step '+i,295,56,8,12,i===0?'PrimarySurface':'Raised'),10),uText(String(i+1).padStart(2,'0'),11,'Primary','Medium'),uText(steps[i],13,'Text','Medium'))));if(i<steps.length-1)add(r,icon('arrow',16));}add(c,r,uSmall(desc,'Secondary',1356));add(map,c);}
 let gallery=dsPage.children.find(n=>n.getPluginData('rainlink-upgrade-gallery')==='true');if(!gallery){gallery=borderCard('Groups / Components',1500,null,48,24,'Background');gallery.setPluginData('rainlink-upgrade-gallery','true');dsPage.appendChild(gallery);gallery.x=3250;gallery.y=0;}for(const n of [...gallery.children])n.remove();gallery.name='Groups / Components';gallery.setPluginData('rainlink-canonical-name',gallery.name);add(gallery,uTitle('分组与节点 · 可复用组件',1404),uSmall('每个订阅自动成组；单个节点先进入未分组。','Secondary',1404),add(row('Group components',1404,null,24),instance('Group / Desktop'),instance('Group / Mobile')),add(row('Grouped node components',1404,null,24),gNode(G_MAIN[0]),gNode(G_LOOSE[0],true,false,true)),add(row('Visual chain components',1404,null,24),instance('Chain / Hop / Desktop'),instance('Chain / Hop / Mobile')),uText('分组规则',18,'Text','Medium'),uSmall('组内记住当前节点。主列表点击连接使用该节点；点击组卡片进入节点列表。未分组始终保留。','Secondary',1404),uSmall('订阅组允许接收未分组节点，显示「订阅 + 手动」数量；订阅更新只管理订阅节点。代理链引用节点，不移动节点。','Secondary',1404));
 const over=uFind(dsPage,'Delivery / Overview');for(const n of [...over.children])n.remove();over.primaryAxisSizingMode='AUTO';add(over,uTitle('RainLink / 交付',920),uText('添加即归组，选择即可连接。',24,'Secondary','Medium',920),divider(920),uText(Object.keys(registry.desktop).length+' 个桌面端 / '+Object.keys(registry.mobile).length+' 个移动端画面',22,'Text','Medium',920),uSmall('1440 × 900 桌面端 · 393 × 852 移动端 · 共享原生组件与 Auto Layout。','Secondary',920),uSmall('默认简体中文 · 深色主题 · 浅色扩展 · 可视化代理链。','Muted',920),divider(920),uSmall('4 个原型入口：桌面 / 移动的连接，以及自动分组与移动。代理链从组内节点页进入。','Secondary',920),uSmall('网络、延迟、订阅及扫码均为设计示例。','Muted',920));
 let yy=gallery.y+gallery.height+100;for(const c of dsPage.children.filter(n=>n.type==='COMPONENT'&&(n.getPluginData('rainlink-group-component')===G_VERSION||n.getPluginData('rainlink-upgrade-component')==='2.0'))){c.x=3250;c.y=yy;yy+=c.height+50;}
}
async function gWire(){
 const valid=new Set([...Object.values(registry.desktop),...Object.values(registry.mobile)].map(n=>n.id));const eligible=(n,target)=>{if(!n||n.removed||n.opacity<.5)return false;let root=n;while(root.parent&&root.parent.type!=='PAGE')root=root.parent;const prefix=target.split('/')[0];return valid.has(root.id)&&root.parent===(prefix==='D'?desktopPage:mobilePage);};uLinks=[...pending,...uLinks].filter(l=>eligible(l.node,l.target));figma.ui.postMessage({status:'正在连接分组原型…'});
 // Repair inherited connections to superseded source/chain examples before exporting.
 for(const page of [desktopPage,mobilePage])for(const n of page.findAll(n=>'reactions'in n&&n.reactions.length)){const next=n.reactions.filter(r=>!(r.actions||[]).some(a=>a.type==='NODE'&&a.destinationId&&!valid.has(a.destinationId)));if(next.length!==n.reactions.length)await n.setReactionsAsync(next);}
 const seen=new Map();for(const l of uLinks)if(l.node&&!l.node.removed)seen.set(l.node.id,l);const edges=[];let count=0;for(const l of seen.values()){const [p,...bits]=l.target.split('/'),dest=(p==='D'?registry.desktop:registry.mobile)[bits.join('/')];if(!dest)throw new Error('Missing group destination '+l.target);let root=l.node;while(root.parent&&root.parent.type!=='PAGE')root=root.parent;if(root.id===dest.id)continue;await l.node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:dest.id,navigation:'NAVIGATE',transition:{type:l.animate?'SMART_ANIMATE':'DISSOLVE',easing:{type:'EASE_OUT'},duration:l.animate?.22:.18},preserveScrollPosition:false}]}]);edges.push({from:l.node.id,to:dest.id,label:l.node.name});if(++count%50===0)figma.ui.postMessage({status:'原型连接 '+count+' / '+seen.size});}
 desktopPage.flowStartingPoints=[{nodeId:registry.desktop.Disconnected.id,name:'桌面端 / 选择分组并连接'},{nodeId:registry.desktop.Profiles.id,name:'桌面端 / 自动归组与移动'}];mobilePage.flowStartingPoints=[{nodeId:registry.mobile.Disconnected.id,name:'移动端 / 选择分组并连接'},{nodeId:registry.mobile.Profiles.id,name:'移动端 / 自动归组与移动'}];return edges;
}
async function simplifyGroupsDocument(){
 await gV4Initialize();
 uLinks=[];pending=[];if(!masters['Chain / Hop / Desktop'])uComponentLibrary();uPrepareWidgetSlots();gLibrary();
 // Delete superseded, generated examples through the plugin API, preserving public group IDs.
 for(const reg of [registry.desktop,registry.mobile])for(const key of ['Subscription import','Manual error','Chain unavailable','Chain add picker','Chain extended','Chain extended tested','Chain extended connected','Rule target','Manual details'])if(reg[key]){reg[key].remove();delete reg[key];}
 gGroups();gGroups('Source success','subscription');gGroups('Manual success','manual');gGroups('Moved','moved');gGroups('Groups custom','custom');
 gNodePage('Nodes','主订阅',G_MAIN);gNodePage('Nodes tested','主订阅',G_MAIN,false,false,true);gNodePage('Ungrouped','未分组',G_LOOSE,true);gNodePage('Ungrouped after move','未分组',G_LOOSE.slice(1),true);gNodePage('Backup group','备用订阅',G_BACKUP);gNodePage('Moved nodes','主订阅',[...G_MAIN,G_LOOSE[0]],false,true);gNodePage('Customgroup','开发环境',[G_LOOSE[0]]);gNodePage('Travel group','旅行订阅',[G_MAIN[2],G_MAIN[0],G_MAIN[1],G_MAIN[3]]);gNodePage('Manual added nodes','未分组',[...G_LOOSE,{name:'备用 HTTP',p:'HTTP',region:'自定义',code:'CN',ping:'16',server:'proxy.backup.example.com:8080'}],true);
 gAddForms(false);gAddForms(true);gMoveScreens();gHome('Dashboard');gHome('Disconnected','主订阅',G_MAIN[0],false);gHome('Dashboard light');gHome('Backup connected','备用订阅',G_BACKUP[0]);gHome('Manual connected','未分组',G_LOOSE[0]);gHome('Local connected','未分组',G_LOOSE[1]);gHome('Custom connected','开发环境',G_LOOSE[0]);gHome('Travel connected','旅行订阅',G_MAIN[2]);gSwitch();gChainFlow();
 // An explicit second move result keeps both destination choices truthful.
 gNodePage('Moved backup','备用订阅',[...G_BACKUP,G_LOOSE[0]],false,true);
 // Existing mobile import success ID and details ID remain valid and fit the new model.
 const mm=registry.mobile['Source success'];const existing=registry.mobile['Import success'];for(const n of [...existing.children])n.remove();for(const n of [...mm.children])existing.appendChild(n);mm.remove();delete registry.mobile['Source success'];existing.name='Mobile / Import success';existing.setPluginData('rainlink-canonical-name',existing.name);gRebuilt.add(existing.id);
 gM('Node details','节点详情','主订阅 · 当前节点',b=>{add(b,gNode(G_MAIN[0],true,true),uField('服务器',G_MAIN[0].server,353),uSmall('已归入主订阅，不提供移动操作。','Muted',353),uButton('连接此组','M/Home','Primary','power',353),uButton('代理链','M/Chains','Ghost','link',353));},'Nodes','M/Nodes');
 // Fix mobile destinations that use Desktop's Dashboard key.
 for(const l of uLinks)if(l.target==='M/Dashboard')l.target='M/Home';else if(l.target==='M/Source success')l.target='M/Import success';
 gV4Examples();await gPatchExisting();for(const r of [registry.desktop,registry.mobile])if(r['Dashboard light']||r['Home light'])applyLight(r['Dashboard light']||r['Home light']);
 // Convert inherited source wording and ensure settings remain accessible from every screen.
 for(const l of uLinks)if(l.target==='M/Dashboard')l.target='M/Home';else if(l.target==='M/Source success')l.target='M/Import success';
 for(const [reg,step,columns]of [[registry.desktop,1540,3],[registry.mobile,473,5]]){let i=0;for(const s of Object.values(reg)){s.x=(i%columns)*step;s.y=150+Math.floor(i/columns)*(columns===3?1020:980);i++;}}
 gSystem();const edges=await gWire();const old=JSON.parse(figma.root.getPluginData('rainlink-report')||'{}');delete old.sourceModel;delete old.upgradeEdges;Object.assign(old,{version:G_VERSION,desktop:Object.fromEntries(Object.entries(registry.desktop).map(([k,n])=>[k,n.id])),mobile:Object.fromEntries(Object.entries(registry.mobile).map(([k,n])=>[k,n.id])),groupModel:{subscriptionCreatesGroup:true,singleNodeDefaultGroup:'未分组',moveOnlyUngrouped:true,manualNodesInSubscriptionRetainedOnUpdate:true,connectUsesLastSelectedNode:true,visualChainSecondaryEntry:true,chainCodeEditor:false,baseGroupCounts:{主订阅:8,备用订阅:3,未分组:3},moveExample:{node:'办公 HTTP',from:'未分组',to:'主订阅',afterCounts:{主订阅:9,备用订阅:3,未分组:2}}},groupEdgeCount:edges.length,groupEdgeSample:true,groupEdges:edges.slice(0,80).map(e=>({from:e.from,to:e.to,screen:e.screen,kind:e.kind})),screenLabels:G_LABELS});figma.root.setPluginData('rainlink-report',JSON.stringify(old));figma.root.setPluginData('rainlink-group-version',G_VERSION);return old;
}
async function groupSimplificationMain(){
 figma.showUI('<body style="padding:24px;background:#10181e;color:#a8bac5;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#86e5c3">RainLink / 概览控制</h2><p id="s">正在更新选择、VPN 开关及代理模式…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:480,height:170});
 figma.ui.postMessage({status:'载入已有原生组件与字体…'});await uInitialize();figma.ui.postMessage({status:'重绘概览、分组与节点选择…'});await simplifyGroupsDocument();figma.ui.postMessage({status:'更新中文并核验布局…'});const report=gV4Report(await localizeDocument());await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Profiles];figma.viewport.scrollAndZoomIntoView([registry.desktop.Profiles]);figma.notify('概览控制已更新 · '+report.counts.desktop+' 桌面 / '+report.counts.mobile+' 移动 · '+report.overflow.length+' 排版待检');figma.closePlugin();
}

// RainLink 4.0. Selection, VPN state and routing mode are separate prototype states.
// All target selection actions change variables only. VPN actions exist on overview.
let gInteractionCollection;
const gVars = {}, gActions = new Map(), gGroupsData = {};
const G_MODES = ['规则', '全局', '直连'];
const G_MODE_COPY = ['按分流规则选择代理或直连', '全部流量使用当前选择', '全部流量直接访问网络'];

function gVar(name, type, value) {
  const x = gVars[name] || figma.variables.createVariable(name, gInteractionCollection, type);
  x.setValueForMode(gInteractionCollection.defaultModeId, value);
  x.description = 'RainLink 交互状态：'+name;
  gVars[name] = x;
  return x;
}
function gSet(name, value) {
  const variable = gVars[name];
  if (!variable) throw new Error('Missing interaction variable '+name);
  const data = value && value.type === 'VARIABLE_ALIAS'
    ? {type:'VARIABLE_ALIAS', resolvedType:variable.resolvedType, value}
    : {type:variable.resolvedType, resolvedType:variable.resolvedType, value};
  return {type:'SET_VARIABLE', variableId:variable.id, variableValue:data};
}
function gAlias(name) { return {type:'VARIABLE_ALIAS',id:gVars[name].id}; }
function gBound(node, name, field='characters') { node.setBoundVariable(field, gVars[name]);return node; }
function gBoundFill(node, name, target='fills') {
  node[target] = [figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:0,g:0,b:0}},'color',gVars[name])];
  return node;
}
function gAction(node, actions, kind) {
  node.setPluginData('rainlink-control-kind',kind);
  gActions.set(node.id,{node,actions,kind});
  return node;
}
function gGo(target) { return {rainlinkTarget:target}; }
function gColor(token) { return vars[token].valuesByMode[darkMode]; }

async function gV4Initialize() {
  gActions.clear();
  const cols=await figma.variables.getLocalVariableCollectionsAsync();
  gInteractionCollection=cols.find(c=>c.name==='RainLink / 交互状态') || figma.variables.createVariableCollection('RainLink / 交互状态');
  for(const v of await figma.variables.getLocalVariablesAsync())if(v.variableCollectionId===gInteractionCollection.id)gVars[v.name]=v;
  gVar('VPN/已开启','BOOLEAN',false);
  gVar('VPN/状态文案','STRING','未连接');
  gVar('VPN/状态颜色','COLOR',gColor('Muted'));
  gVar('VPN/下载','STRING','↓ 0 MB/s');gVar('VPN/上传','STRING','↑ 0 MB/s');
  gVar('选择/分组','STRING','主订阅');gVar('选择/节点','STRING',G_MAIN[0].name);
  gVar('选择/协议','STRING',G_MAIN[0].p);gVar('选择/延迟','STRING',G_MAIN[0].ping+' ms');
  gVar('选择/待应用','BOOLEAN',false);
  gVar('连接/分组','STRING','主订阅');gVar('连接/节点','STRING',G_MAIN[0].name);
  gVar('连接/协议','STRING',G_MAIN[0].p);gVar('连接/延迟','STRING',G_MAIN[0].ping+' ms');
  gVar('模式/名称','STRING','规则模式');gVar('模式/说明','STRING',G_MODE_COPY[0]);
  for(let i=0;i<G_MODES.length;i++)gVar('模式/'+G_MODES[i]+'/背景','COLOR',gColor(i===0?'PrimarySurface':'Raised'));
  const travel=[G_MAIN[2],G_MAIN[0],G_MAIN[1],G_MAIN[3]];
  const manual={name:'备用 HTTP',p:'HTTP',region:'自定义',code:'CN',ping:'16',server:'proxy.backup.example.com:8080'};
  Object.assign(gGroupsData,{'主订阅':[...G_MAIN,G_LOOSE[0]],'备用订阅':[...G_BACKUP,G_LOOSE[0]],'未分组':[...G_LOOSE,manual],'旅行订阅':travel,'开发环境':[G_LOOSE[0]]});
  for(const [group,nodes]of Object.entries(gGroupsData)){
    const selected=group==='主订阅';
    gVar('分组/'+group+'/选中','BOOLEAN',selected);
    gVar('分组/'+group+'/背景','COLOR',gColor(selected?'PrimarySurface':'Surface'));
    gVar('分组/'+group+'/节点','STRING',nodes[0].name);
    gVar('分组/'+group+'/协议','STRING',nodes[0].p);
    gVar('分组/'+group+'/延迟','STRING',nodes[0].ping+' ms');
    for(let i=0;i<nodes.length;i++){
      gVar('节点/'+group+'/'+nodes[i].name+'/选中','BOOLEAN',i===0);
      gVar('节点/'+group+'/'+nodes[i].name+'/背景','COLOR',gColor(i===0?'PrimarySurface':'Surface'));
    }
  }
}
function gSelection(group, data=null) {
  const actions=[];
  for(const name of Object.keys(gGroupsData)){
    actions.push(gSet('分组/'+name+'/选中',name===group));
    actions.push(gSet('分组/'+name+'/背景',gColor(name===group?'PrimarySurface':'Surface')));
  }
  if(data){
    for(const n of gGroupsData[group]){
      actions.push(gSet('节点/'+group+'/'+n.name+'/选中',n.name===data.name));
      actions.push(gSet('节点/'+group+'/'+n.name+'/背景',gColor(n.name===data.name?'PrimarySurface':'Surface')));
    }
    for(const [key,val]of [['节点',data.name],['协议',data.p],['延迟',data.ping+' ms']])actions.push(gSet('分组/'+group+'/'+key,val));
  }
  actions.push(gSet('选择/分组',group));
  for(const key of ['节点','协议','延迟'])actions.push(gSet('选择/'+key,gAlias('分组/'+group+'/'+key)));
  actions.push(gSet('选择/待应用',true));
  return actions;
}
function gPowerActions(online, prefix) {
  const actions=[gSet('VPN/已开启',!online),gSet('VPN/状态文案',online?'未连接':'已连接'),gSet('VPN/状态颜色',gColor(online?'Muted':'Primary')),gSet('VPN/下载',online?'↓ 0 MB/s':'↓ 12.8 MB/s'),gSet('VPN/上传',online?'↑ 0 MB/s':'↑ 1.4 MB/s'),gSet('选择/待应用',false)];
  if(!online)for(const key of ['分组','节点','协议','延迟'])actions.push(gSet('连接/'+key,gAlias('选择/'+key)));
  actions.push(gGo(prefix+(online?'Disconnected':prefix==='D/'?'Dashboard':'Home')));
  return actions;
}
function sidebar(active) {
  const n=frame('Sidebar',248,900,'VERTICAL','Surface',0,20);n.paddingTop=26;n.paddingBottom=24;stroke(n);
  const brand=add(row('Brand',208,44,12),instance('Brand / Mark'),tx('RainLink',22,'Text','Semi Bold'));
  const nav=v('Primary navigation',208,4);navNames.forEach((s,i)=>add(nav,navItem(s,s===active,i)));
  const footer=between(add(row('App status',208,null),small('RainLink 1.0.0'),badge('CORE READY','Success')));
  add(n,brand,space(32),nav,grow(space()),footer);return n;
}

function gLibrary() {
  gLibraryV3();
  const side=masters['Sidebar / Desktop'];
  for(const n of side.findAll(n=>['Workspace','Routing mode'].includes(n.getPluginData('rainlink-canonical-name')||n.name)||n.type==='TEXT'&&n.characters==='WORKSPACE'))n.remove();
  // Rebuild the compact header spacing, preserving the shared sidebar master identity.
  const nav=uFind(side,'Primary navigation');
  for(const n of [...side.children])if(n!==nav&&n.name!=='Brand'&&n.name!=='Workspace status'){
    if(n.type==='FRAME'&&n.name==='Flexible space')continue;
    if(n.width===1||n.name==='Spacer'||n.name==='Space')n.remove();
  }
  const footer=uFind(side,'Workspace status');
  if(footer)footer.name='App status';
  for(const mobile of [false,true]){
    const w=mobile?353:744,inner=w-32;
    gNative('Group / '+(mobile?'Mobile':'Desktop'),c=>{
      c.resize(w,132);c.layoutMode='VERTICAL';c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';
      c.paddingLeft=c.paddingRight=16;c.paddingTop=c.paddingBottom=16;c.itemSpacing=12;rad(c,14);fill(c,'Surface');stroke(c);
      const title=uText('主订阅',16,'Text','Medium');title.name='组名称';
      const meta=uSmall('8 个节点 · 订阅自动更新','Muted');meta.name='组信息';
      const check=icon('check',16,'Primary');check.name='分组选中';check.setPluginData('rainlink-canonical-name',check.name);
      add(c,between(add(row('Group heading',inner,null,10),add(row('Group identity',null,null,12),miniIcon('folder','Primary',36,'PrimarySurface'),add(v('Group copy',mobile?213:520,4),title,meta)),check)));
      const node=uText('东京 · 樱花',12,'Secondary','Medium');node.name='组当前节点';
      const ping=uSmall('24 ms','Primary');ping.name='组延迟';
      const detail=btn('节点','Ghost','M','chevron');detail.name='组节点入口';detail.setPluginData('rainlink-canonical-name',detail.name);
      add(c,between(add(row('Group current node',inner,36,8),add(row('Group current identity',null,null,8),node,ping),detail)));
    });
    gNative('Overview / Proxy mode / '+(mobile?'Mobile':'Desktop'),c=>{
      const mw=mobile?353:1120,iw=mw-32;c.resize(mw,mobile?114:82);c.layoutMode='VERTICAL';c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';
      c.paddingLeft=c.paddingRight=16;c.paddingTop=c.paddingBottom=14;c.itemSpacing=8;rad(c,14);fill(c,'Surface');stroke(c);
      const heading=between(add(row('Proxy mode heading',mobile?iw:700,null),uText('代理模式',14,'Text','Medium'),mobile?null:uSmall(G_MODE_COPY[0],'Secondary')));
      if(!mobile)heading.children[1].name='模式说明';
      const choices=add(row('Proxy mode options',mobile?iw:354,36,6));
      for(const mode of G_MODES){const b=center(rad(row('代理模式 · '+mode,mobile?103:114,36,0,6,mode==='规则'?'PrimarySurface':'Raised'),9));add(b,uText(mode,13,mode==='规则'?'Primary':'Secondary','Medium'));add(choices,b);}
      if(mobile)add(c,heading,choices);else add(c,between(add(row('Proxy mode desktop',iw,52,16),heading,choices)));
    });
  }
}
function gMode(mobile=false,staticMode=null) {
  const c=instance('Overview / Proxy mode / '+(mobile?'Mobile':'Desktop'));
  const desc=uFind(c,'模式说明');if(desc){if(staticMode)desc.characters=G_MODE_COPY[G_MODES.indexOf(staticMode)];else gBound(desc,'模式/说明');}
  for(let i=0;i<G_MODES.length;i++){
    const item=uFind(c,'代理模式 · '+G_MODES[i]);
    if(staticMode)fill(item,staticMode===G_MODES[i]?'PrimarySurface':'Raised');else gBoundFill(item,'模式/'+G_MODES[i]+'/背景');
    gAction(item,[gSet('模式/名称',G_MODES[i]+'模式'),gSet('模式/说明',G_MODE_COPY[i]),...G_MODES.map(m=>gSet('模式/'+m+'/背景',gColor(m===G_MODES[i]?'PrimarySurface':'Raised')))],'proxy-mode');
  }
  return c;
}
function gGroup(name,count,type,node,mobile=false,detail='Nodes',connected='Dashboard',meta=null) {
  const c=instance('Group / '+(mobile?'Mobile':'Desktop'));c.name='Group · '+name;c.setPluginData('rainlink-canonical-name',c.name);
  uOverride(c,'组名称',name);uOverride(c,'组信息',meta||count+' 个节点 · '+(type==='订阅'?'订阅自动更新':type==='自建'?'手动分组':'手动添加'));
  uOverride(c,'组当前节点',node.name);uOverride(c,'组延迟',node.ping+' ms');
  gBound(uFind(c,'组当前节点'),'分组/'+name+'/节点');gBound(uFind(c,'组延迟'),'分组/'+name+'/延迟');
  gBound(uFind(c,'分组选中'),'分组/'+name+'/选中','visible');gBoundFill(c,'分组/'+name+'/背景');
  gAction(c,gSelection(name),'select-group');uLink(uFind(c,'组节点入口'),(mobile?'M/':'D/')+detail);
  return c;
}
function gSelectedPanel(mobile=false,online=false,staticGroup=null,data=G_MAIN[0],chain=false) {
  const w=mobile?353:352,iw=w-32,c=borderCard('Selection summary',w,null,16,12);
  const group=uText(staticGroup||'主订阅',20,'Text','Medium',iw);
  const node=uText(chain?(chain==='reverse'?'东京 · 樱花 → 办公 HTTP':'办公 HTTP → 东京 · 樱花'):data.name,13,'Secondary','Medium',iw);
  const title=between(add(row('Selection heading',iw,null),uSmall('当前选择','Muted'),badge('已选中','Success')));
  if(!staticGroup){gBound(group,'选择/分组');gBound(node,'选择/节点');}
  add(c,title,group,node);
  if(online){const note=uSmall('待应用 · 关闭再开启 VPN','Warning',iw);gBound(note,'选择/待应用','visible');add(c,note);}
  add(c,uSmall('VPN 开关和代理模式均在概览。','Muted',iw),uButton('去概览',(mobile?'M/':'D/')+(mobile?'Home':'Dashboard'),'Secondary','grid',iw));
  return c;
}
function gGroups(key='Profiles',state='base') {
  for(const mobile of [false,true]){
    const p=mobile?'M/':'D/',w=mobile?353:1120,build=b=>{
      if(state!=='base')add(b,uSmall(state==='subscription'?'已导入旅行订阅，自动创建 4 节点分组。':state==='manual'?'备用 HTTP 已加入未分组。':state==='moved'?'办公 HTTP 已移入主订阅。':'开发环境已创建，办公 HTTP 已移入。','Primary',w));
      if(!mobile)add(b,between(add(row('Group toolbar',1120,40,16),input('搜索分组…',344,'search'),uSmall('点击选中分组，点「节点」更换组内节点。','Muted'))));
      const list=mobile?b:v('Group list',744,16),moved=state==='moved',loose=state==='manual'?4:moved||state==='custom'?2:3;
      add(list,gGroup('主订阅',moved?9:8,'订阅',G_MAIN[0],mobile,moved?'Moved nodes':'Nodes','Dashboard',moved?'8 个订阅节点 + 1 个手动节点':null),gGroup('备用订阅',3,'订阅',G_BACKUP[0],mobile,'Backup group','Backup connected'),gGroup('未分组',loose,'未分组',G_LOOSE[0],mobile,state==='manual'?'Manual added nodes':moved||state==='custom'?'Ungrouped after move':'Ungrouped'));
      if(state==='subscription')add(list,gGroup('旅行订阅',4,'订阅',G_MAIN[2],mobile,'Travel group'));
      if(state==='custom')add(list,gGroup('开发环境',1,'自建',G_LOOSE[0],mobile,'Customgroup'));
      if(!mobile)add(b,add(row('Group workspace',1120,null,24),list,gSelectedPanel()));
      else add(b,between(add(row('Group selection footer',353,40),uSmall('这里只选择，连接请前往概览。','Muted'),uButton('去概览','M/Home','Ghost','grid'))));
      add(b,uSmall('订阅 → 自动建组　·　单个节点 → 未分组','Muted',w));
    };
    if(mobile)gM(key,'分组','选择分组，记住该组当前节点',build,'Profiles','M/Import profile',true);
    else gD(key,'分组','选择连接目标。VPN 开关与代理模式在概览。',build,'Profiles',uButton('添加节点',p+'Import profile','Primary','plus'));
  }
}
function gNodePage(key,title,data,loose=false,moved=false,tested=false) {
  // A moved node is now remembered inside its new group; no move affordance remains.
  if(!gGroupsData[title].some(n=>n.name===data[data.length-1].name)){
    for(const n of data)if(!gGroupsData[title].some(x=>x.name===n.name)){
      gGroupsData[title].push(n);gVar('节点/'+title+'/'+n.name+'/选中','BOOLEAN',false);gVar('节点/'+title+'/'+n.name+'/背景','COLOR',gColor('Surface'));
    }
  }
  for(const mobile of [false,true]){
    const p=mobile?'M/':'D/',w=mobile?353:1120,build=b=>{
      add(b,between(add(row('Group node toolbar',w,40,8),uButton('全部分组',p+'Profiles','Ghost','folder'),uButton(tested?'测速完成':'测速',p+(key==='Nodes'?'Nodes tested':key),'Secondary','speed'))));
      const list=mobile?b:borderCard('Group node inventory',728,null,0,0);
      for(let i=0;i<data.length;i++){
        const n=gNode(data[i],mobile,i===0,loose);
        gBound(uFind(n,'节点选中'),'节点/'+title+'/'+data[i].name+'/选中','visible');gBoundFill(n,'节点/'+title+'/'+data[i].name+'/背景');
        gAction(n,gSelection(title,data[i]),'select-node');
        add(list,n);if(!mobile&&i<data.length-1)add(list,divider(728));
      }
      if(!mobile){
        const aside=borderCard('Selected group node',368,null,24,16);
        const current=uText(data[0].name,21,'Text','Medium',320);gBound(current,'分组/'+title+'/节点');
        const ping=uSmall(data[0].ping+' ms','Primary');gBound(ping,'分组/'+title+'/延迟');
        const tag=badge(data[0].p);gBound(tag.findOne(n=>n.type==='TEXT'),'分组/'+title+'/协议');
        add(aside,uSmall('该组当前节点','Secondary'),current,add(row('Selected node protocol',320,null,12),tag,ping),divider(320),uSmall('点击节点即可选中。连接统一在概览开启。','Muted',320),uButton('去概览',p+'Dashboard','Secondary','grid',320));
        if(loose)add(aside,uSmall('只有未分组节点可以移动。归组后隐藏移动入口。','Muted',320));
        else if(title==='主订阅')add(aside,uButton('代理链',p+'Chains','Ghost','link',320));
        if(moved)add(aside,uSmall('订阅更新保留手动加入的节点。','Muted',320));
        add(b,add(row('Group node workspace',1120,null,24),list,aside));
      }else{
        if(title==='主订阅')add(b,uButton('代理链',p+'Chains','Ghost','link',353));
        add(b,uSmall('选中后回到概览开启 VPN。','Muted',353));
      }
    };
    if(mobile)gM(key,title,data.length+' 个节点 · 点击选中',build,'Nodes','M/Profiles');
    else gD(key,title,data.length+' 个节点 · 点击选中，记住你的选择。',build,'Nodes',uButton('添加节点',p+'Import profile','Primary','plus'));
  }
}
function gHome(key,group='主订阅',data=G_MAIN[0],online=true,chain=false,staticMode=null) {
  const mk=key==='Dashboard'?'Home':key==='Dashboard light'?'Home light':key;
  const sample=!['Dashboard','Disconnected','Dashboard light','Mode global','Mode direct','Pending selection'].includes(key);
  const pending=key==='Pending selection',activeKey=online?'连接':'选择';
  const label=staticMode?staticMode+'模式':'规则模式';
  const db=b=>{
    const hero=borderCard('Connection group hero',1120,pending?222:196,28,16,online?'PrimarySurface':'Surface');
    const state=uText(online?'VPN 已开启':'VPN 已关闭',13,online?'Primary':'Muted','Medium');
    const mode=badge(label,'Success');if(!sample&&!staticMode)gBound(mode.findOne(n=>n.type==='TEXT'),'模式/名称');
    const power=btn(online?'关闭 VPN':'开启 VPN','Primary','M','power');gAction(power,gPowerActions(online,'D/'),'vpn-power');
    const name=uText(sample?group:'主订阅',28,'Text','Semi Bold',730);
    const node=uSmall(chain?(chain==='reverse'?'东京 · 樱花 → 办公 HTTP':'办公 HTTP → 东京 · 樱花'):data.name,'Secondary',730);
    if(!sample){gBound(name,activeKey+'/分组');gBound(node,activeKey+'/节点');}
    const ping=uSmall(online?data.ping+' ms':'未连接','Secondary');if(online&&!sample)gBound(ping,'连接/延迟');
    add(hero,between(add(row('Connection hero heading',1064,null),add(row('Connection state',null,null,8),dot(online?'Primary':'Muted'),state),mode)),between(add(row('Connection group summary',1064,null),add(v('Overview target',730,6),name,node),power)),between(add(row('Connection group bottom',1064,null),add(row('Current connection facts',null,null,12),uSmall(online?'当前连接':'当前选择','Muted'),ping),uButton('选择分组','D/Quick switch','Ghost','connections'))));
    if(pending)add(hero,uSmall('待应用：备用订阅 / 伦敦 · 泰晤士 · 关闭再开启 VPN 后生效','Warning',1064));
    add(b,hero,gMode(false,staticMode),add(row('Network stats',1120,86,16),uMetric('今日流量','8.42 GB','↓ 7.86 GB　↑ 560 MB',362),uMetric('下载速度',online?'12.8 MB/s':'0 MB/s','上传 '+(online?'1.4':'0')+' MB/s',362),uMetric('网络质量',online?'98 / 100':'—',online?'稳定 · 丢包 0%':'等待连接',364)));
    if(online){
      const change=between(add(row('Pending target summary',1120,36,12),uSmall('已选目标','Muted'),gBound(uText('主订阅',13,'Text','Medium'),'选择/分组'),gBound(uSmall(G_MAIN[0].name,'Secondary'),'选择/节点'),grow(space()),uSmall('待应用 · 下次开启 VPN 时生效','Warning')));
      gBound(change,'选择/待应用','visible');if(!pending)add(b,change);
    }
    add(b,add(row('Connection trends',1120,230,24),gTrend(data,chain),gHealth(group,data)));
  };
  const ds=gD(key,'概览','选择目标、VPN 开关和代理模式集中于此。',db,'Dashboard',uButton('选择分组','D/Quick switch','Secondary','connections'));
  ds.setPluginData('rainlink-overview-online',online?'true':'false');ds.setPluginData('rainlink-overview-sample',sample?'true':'false');
  const mb=b=>{
    const hero=center(borderCard('VPN control',353,pending?206:184,16,8,online?'PrimarySurface':'Surface'));
    const ring=center(rad(row('VPN power button',88,88,0,0,online?'Primary':'Raised'),44));stroke(ring,online?'Primary':'Stroke');add(ring,icon('power',32,online?'OnPrimary':'Primary'));gAction(ring,gPowerActions(online,'M/'),'vpn-power');
    const modeName=uSmall(label,'Secondary');if(!sample&&!staticMode)gBound(modeName,'模式/名称');
    const mode=add(row('VPN mode caption',null,null,6),modeName,uSmall('· '+(online?'点按关闭 VPN':'点按开启 VPN'),'Secondary'));
    add(hero,ring,uText(online?'VPN 已开启':'VPN 已关闭',21,'Text','Semi Bold'),mode);
    if(pending)add(hero,uSmall('关闭再开启后，应用新选择','Warning'));
    add(b,hero);
    const target=borderCard('Selected connection group',353,null,16,10),name=uText(sample?group:'主订阅',17,'Text','Medium'),node=uSmall(chain?(chain==='reverse'?'东京 → 办公 HTTP':'办公 HTTP → 东京'):data.name,'Secondary',321);
    if(!sample){gBound(name,activeKey+'/分组');gBound(node,activeKey+'/节点');}
    const ping=uSmall(online?data.ping+' ms':'当前选择','Primary');if(online&&!sample)gBound(ping,'连接/延迟');
    add(target,between(add(row('Selected group heading',321,null),name,uButton('选择','M/Quick switch','Ghost','connections'))),between(add(row('Selected group node',321,null),uSmall(online?'当前连接':'当前选择','Muted'),ping)),node);
    if(online){const note=uSmall('待应用 · 下次开启时使用新选择','Warning',321);gBound(note,'选择/待应用','visible');add(target,note);}
    add(b,target,gMode(true,staticMode),add(row('Mobile live speed',353,86,15),uMetric('下载',online?'12.8':'0','MB/s',169),uMetric('上传',online?'1.4':'0','MB/s',169)),between(add(row('Today traffic simple',353,44),uCopy('今日流量','↓ 7.86 GB　↑ 560 MB',230,12),uLink(uText('8.42 GB',18,'Text','Medium'),'M/Traffic'))));
  };
  const ms=gM(mk,'RainLink','概览 · 管理连接与代理模式',mb,'Home','M/Settings');
  ms.setPluginData('rainlink-overview-online',online?'true':'false');ms.setPluginData('rainlink-overview-sample',sample?'true':'false');
  const h=uFind(ms,'Page header'),back=h.children[0];h.appendChild(back);const ic=back.findOne(n=>n.type==='INSTANCE');if(ic)ic.swapComponent(icons.settings);
  if(key==='Dashboard light'){applyLight(ds);applyLight(ms);}
}
function gSwitch() {
  for(const mobile of [false,true]){
    const p=mobile?'M/':'D/',build=b=>{
      for(const args of [['主订阅',8,'订阅',G_MAIN[0],'Nodes'],['备用订阅',3,'订阅',G_BACKUP[0],'Backup group'],['未分组',3,'未分组',G_LOOSE[0],'Ungrouped']])add(b,gGroup(args[0],args[1],args[2],args[3],mobile,args[4]));
      add(b,uSmall('点击仅更换选择，不改变当前 VPN 连接。','Muted',mobile?353:744),uButton('返回概览',p+(mobile?'Home':'Dashboard'),'Secondary','grid',mobile?353:744));
    };
    if(mobile)gM('Quick switch','选择分组','使用该组上次选择的节点',build,'Home','M/Home');
    else gD('Quick switch','选择分组','选中后回到概览，按需开启 VPN。',build,'Dashboard',uButton('关闭','D/Dashboard','Ghost','close'));
  }
}
function gChainFlow() {
  gChainFlowV3();
  for(const [reg,p]of [[registry.desktop,'D/'],[registry.mobile,'M/']]){
    const main=reg.Chains;
    for(const t of main.findAll(n=>n.type==='TEXT'))if(/日常直接连接分组/.test(t.characters)){t.characters='需要多跳时编排代理链，选中后在概览开启 VPN。';t.setPluginData('rainlink-original-text',t.characters);}
    const choose=uSummary(p==='M/');const content=uFind(main,'Content');
    gAction(choose,[...gSelection('主订阅'),gSet('选择/节点','开发代理链 · 办公 HTTP → 东京'),gSet('选择/协议','2 跳 · TCP'),gSet('选择/延迟','46 ms')],'select-chain');
    // Existing summary opens editing; a distinct select action never starts the VPN.
    const pick=btn('选中代理链','Secondary','M','check');gAction(pick,[...gSelection('主订阅'),gSet('选择/节点','开发代理链 · 办公 HTTP → 东京'),gSet('选择/协议','2 跳 · TCP'),gSet('选择/延迟','46 ms')],'select-chain');add(content,pick);choose.remove();
    for(const [key,reverse]of [['Chain tested',false],['Chain reverse tested',true]]){
      const screen=reg[key];
      for(const t of screen.findAll(n=>n.type==='TEXT'))if(t.characters==='保存并连接'){t.characters='保存并选中';t.setPluginData('rainlink-original-text',t.characters);}
      const controls=screen.findAll(n=>(n.getPluginData('rainlink-canonical-name')||n.name)==='Button · 保存并连接');
      for(const b of controls){const power=b.findOne(n=>n.type==='INSTANCE');if(power)power.swapComponent(icons.check);gAction(b,[...gSelection('主订阅'),gSet('选择/节点',reverse?'开发代理链 · 东京 → 办公 HTTP':'开发代理链 · 办公 HTTP → 东京'),gSet('选择/协议','2 跳 · TCP'),gSet('选择/延迟',reverse?'39 ms':'46 ms'),gGo(p+(p==='M/'?'Home':'Dashboard'))],'select-chain');}
    }
  }
}
async function gPatchExisting() {
  await gPatchExistingV3();
  for(const [reg,p]of [[registry.desktop,'D/'],[registry.mobile,'M/']])for(const [key,s]of Object.entries(reg)){
    if(p==='D/'){
      const bar=uFind(s,'Connection bar');if(!bar)continue;
      for(const n of [...bar.children])n.remove();
      const online=s.getPluginData('rainlink-overview-online')==='true';
      const state=uText(online?'已连接':'未连接',13,online?'Primary':'Muted','Medium');
      const dotNode=dot(online?'Primary':'Muted');
      if(!online){gBound(state,'VPN/状态文案');gBoundFill(state,'VPN/状态颜色');gBoundFill(dotNode,'VPN/状态颜色');}
      const group=gBound(uSmall('主订阅','Secondary'),'连接/分组'),node=gBound(uSmall(G_MAIN[0].name,'Secondary'),'连接/节点');
      if(!online){gBound(group,'VPN/已开启','visible');gBound(node,'VPN/已开启','visible');}
      const left=add(row('Persistent group status',null,null,10),dotNode,state,group,node);
      const ping=gBound(uSmall('24 ms','Secondary'),'连接/延迟');
      const down=uSmall(online?'↓ 12.8 MB/s':'↓ 0 MB/s','Secondary'),up=uSmall(online?'↑ 1.4 MB/s':'↑ 0 MB/s','Muted');
      if(!online){gBound(down,'VPN/下载');gBound(up,'VPN/上传');}
      if(!online)gBound(ping,'VPN/已开启','visible');
      add(bar,left,add(row('Persistent group speeds',null,null,16),ping,down,up,uButton('概览','D/Dashboard','Ghost','grid')));
    }
  }
  const rules=registry.desktop.Rules;
  const modes=uFind(rules,'Routing modes');if(modes){const parent=modes.parent,idx=parent.children.indexOf(modes);modes.remove();const note=borderCard('Routing overview shortcut',1120,78,20,12);note.layoutMode='HORIZONTAL';note.primaryAxisAlignItems='SPACE_BETWEEN';add(note,uCopy('分流规则','代理模式在概览设置，这里管理规则与优先级。',760,16),uButton('前往概览','D/Dashboard','Secondary','grid'));parent.insertChild(idx,note);}
  const network=uFind(registry.mobile.Settings,'Network preferences');
  if(network){for(const n of [...network.children])if(n.type==='FRAME'&&n.findOne(t=>t.type==='TEXT'&&['Routing mode','路由模式','代理模式'].includes(t.characters)))n.remove();const cs=network.children;if(cs.length&&cs[cs.length-1].height<=1)cs[cs.length-1].remove();}
  // Node details has no power action. Selection has already happened on the list.
  const details=registry.mobile['Node details'];
  for(const b of details.findAll(n=>(n.getPluginData('rainlink-canonical-name')||n.name)==='Button · 连接此组')){textOverride(b,'Label','去概览');b.name='Button · 去概览';b.setPluginData('rainlink-canonical-name',b.name);const ic=b.findOne(n=>n.type==='INSTANCE');if(ic)ic.swapComponent(icons.grid);uLink(b,'M/Home');}
}
function gV4Examples() {
  gHome('Mode global','主订阅',G_MAIN[0],false,false,'全局');
  gHome('Mode direct','主订阅',G_MAIN[0],false,false,'直连');
  gHome('Pending selection','主订阅',G_MAIN[0],true);
}
function gSystem() {
  gSystemV3();
  const map=uFind(dsPage,'Prototype Flow / Interaction map');
  for(const n of [...map.children])n.remove();
  add(map,uTitle('原型流程 · 选择与连接',1404),uSmall('两端统一：分组和节点只选择，概览控制 VPN 与代理模式。','Secondary',1404));
  for(const [title,steps,desc]of [
    ['订阅导入',['添加节点','粘贴订阅','自动创建同名组','选中分组'],'添加不会连接。组内记住上次选择的节点。'],
    ['单个节点',['添加节点','填写 HTTP 等节点','自动进入未分组','选中或移动'],'只有未分组节点可以移动。订阅更新保留手动加入的节点。'],
    ['开启 VPN',['选择分组或节点','回到概览','设置代理模式','开启 VPN'],'规则 / 全局 / 直连模式均在概览。关闭后保留分组与节点选择。'],
    ['连接中改选',['保持当前连接','选中新目标','概览提示待应用','关闭再开启 VPN'],'选中不会重连，当前连接与下次使用的选择分别显示。'],
    ['可视化代理链',['选择已有节点','调整跳点顺序','测试并保存选中','概览开启 VPN'],'仅提供可视化编排，不需要代码。保存与选择不会启动连接。']
  ]){
    const c=borderCard(title,1404,null,24,16),r=row('Group flow steps',1356,56,20);add(c,uText(title,18,'Text','Medium'));
    for(let i=0;i<steps.length;i++){add(r,center(add(rad(row('Step '+i,295,56,8,12,i===0?'PrimarySurface':'Raised'),10),uText(String(i+1).padStart(2,'0'),11,'Primary','Medium'),uText(steps[i],13,'Text','Medium'))));if(i<steps.length-1)add(r,icon('arrow',16));}
    add(c,r,uSmall(desc,'Secondary',1356));add(map,c);
  }
  const gallery=dsPage.children.find(n=>n.getPluginData('rainlink-upgrade-gallery')==='true');
  for(const t of gallery.findAll(n=>n.type==='TEXT'))if(/主列表点击连接/.test(t.characters)){t.characters='组卡片点击选中，节点入口进入列表。组内点击节点记住选择；连接与代理模式由概览管理。';t.setPluginData('rainlink-original-text',t.characters);}
  add(gallery,uText('概览 · 代理模式组件',18,'Text','Medium'),instance('Overview / Proxy mode / Desktop'),instance('Overview / Proxy mode / Mobile'));
  const over=uFind(dsPage,'Delivery / Overview');
  for(const t of over.findAll(n=>n.type==='TEXT'))if(t.characters==='添加即归组，选择即可连接。')t.characters='添加即归组，选择与连接各司其职。';
  let y=gallery.y+gallery.height+100;
  for(const c of dsPage.children.filter(n=>n.type==='COMPONENT'&&(n.getPluginData('rainlink-group-component')===G_VERSION||n.getPluginData('rainlink-upgrade-component')==='2.0'))){c.x=3250;c.y=y;y+=c.height+50;}
}
function gNavAction(target) {
  const [p,...bits]=target.split('/'),key=bits.join('/'),reg=p==='D'?registry.desktop:registry.mobile,dest=reg[key];
  if(!dest)throw new Error('Missing overview destination '+target);
  const action=id=>({type:'NODE',destinationId:id,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false});
  if(key==='Dashboard'||key==='Home')return {type:'CONDITIONAL',conditionalBlocks:[{condition:{type:'VARIABLE_ALIAS',resolvedType:'BOOLEAN',value:gAlias('VPN/已开启')},actions:[action(dest.id)]},{actions:[action(reg.Disconnected.id)]}]};
  return action(dest.id);
}
async function gWire() {
  const valid=new Set([...Object.values(registry.desktop),...Object.values(registry.mobile)].map(n=>n.id)),edges=[];
  const rootOf=n=>{let root=n;while(root.parent&&root.parent.type!=='PAGE')root=root.parent;return root;};
  const links=new Map();
  for(const l of [...pending,...uLinks])if(l.node&&!l.node.removed&&l.node.opacity>=.5&&valid.has(rootOf(l.node).id))links.set(l.node.id,l);
  // Remove inherited interactions first. Custom variable actions are assigned last.
  for(const page of [desktopPage,mobilePage])for(const n of page.findAll(n=>'reactions'in n&&n.reactions.length))await n.setReactionsAsync([]);
  let count=0;
  for(const l of links.values()){
    const action=gNavAction(l.target);await l.node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[action]}]);
    edges.push({from:l.node.id,target:l.target,label:l.node.name,kind:'navigate'});
    if(++count%100===0)figma.ui.postMessage({status:'原型导航 '+count+' / '+links.size});
  }
  const stateEdges=[];
  for(const {node,actions,kind}of gActions.values()){
    if(node.removed||!valid.has(rootOf(node).id))continue;
    const resolved=actions.map(a=>a.rainlinkTarget?gNavAction(a.rainlinkTarget):a);
    await node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:resolved}]);
    stateEdges.push({node:node.id,screen:rootOf(node).id,kind,actions:resolved});
  }
  desktopPage.flowStartingPoints=[{nodeId:registry.desktop.Disconnected.id,name:'桌面端 / 概览开启 VPN'},{nodeId:registry.desktop.Profiles.id,name:'桌面端 / 自动归组与选择'}];
  mobilePage.flowStartingPoints=[{nodeId:registry.mobile.Disconnected.id,name:'移动端 / 概览开启 VPN'},{nodeId:registry.mobile.Profiles.id,name:'移动端 / 自动归组与选择'}];
  figma.root.setPluginData('rainlink-overview-controls',JSON.stringify({version:'4.0',workspaceRemoved:true,selectionDoesNotConnect:true,powerOnlyOnOverview:true,proxyModeOnlyOnOverview:true,groupRemembersNode:true,pendingChoiceWhileConnected:true,chainSaveSelectsOnly:true,interactionVariables:Object.keys(gVars).length,stateEdgeCount:stateEdges.length,stateEdgeSample:true,stateEdges:stateEdges.slice(0,60)}));
  return edges;
}
function gV4Report(report) {
  report.overviewControls=JSON.parse(figma.root.getPluginData('rainlink-overview-controls'));
  Object.assign(report.groupModel,{selectionDoesNotConnect:true,vpnControlPage:'概览',proxyModeControlPage:'概览',workspaceSelector:false,chainSaveSelectsOnly:true});
  const bound=desktopPage.findAll(n=>n.boundVariables&&Object.keys(n.boundVariables).length).length+mobilePage.findAll(n=>n.boundVariables&&Object.keys(n.boundVariables).length).length;
  report.overviewControls.boundNodes=bound;
  figma.root.setPluginData('rainlink-report',JSON.stringify(report));
  const audit=uFind(dsPage,'Delivery / Native audit');if(audit){audit.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);audit.visible=false;}
  return report;
}

async function gPrototypePlanProbe(){
 await figma.loadAllPagesAsync();
 const page=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='desktop');
 const group=page.findOne(n=>n.getPluginData('rainlink-control-kind')==='select-group');
 const variable=(await figma.variables.getLocalVariablesAsync('STRING')).find(v=>v.name==='选择/分组');
 let result='SET_VARIABLE: supported';
 try{await group.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'SET_VARIABLE',variableId:variable.id,variableValue:{type:'STRING',value:'备用订阅'}}]}]);}
 catch(e){result='SET_VARIABLE: '+String(e.message||e);}
 figma.showUI('<body style="background:#10181e;color:#86e5c3;padding:20px;font:13px sans-serif">'+result+'</body>',{width:520,height:160});
}
const gStaticTargets=new Map();
const gStaticNodes={
 'Nodes':['主订阅',G_MAIN], 'Nodes tested':['主订阅',G_MAIN],
 'Backup group':['备用订阅',G_BACKUP], 'Ungrouped':['未分组',G_LOOSE],
 'Ungrouped after move':['未分组',G_LOOSE.slice(1)],
 'Moved nodes':['主订阅',[...G_MAIN,G_LOOSE[0]]], 'Moved backup':['备用订阅',[...G_BACKUP,G_LOOSE[0]]],
 'Customgroup':['开发环境',[G_LOOSE[0]]], 'Travel group':['旅行订阅',[G_MAIN[2],G_MAIN[0],G_MAIN[1],G_MAIN[3]]],
 'Manual added nodes':['未分组',[...G_LOOSE,{name:'备用 HTTP',p:'HTTP',region:'自定义',code:'CN',ping:'16',server:'proxy.backup.example.com:8080'}]]
};
function gStaticText(n,s){if(!n)return;n.setBoundVariable('characters',null);n.characters=s;n.setPluginData('rainlink-original-text',s);}
function gStaticKey(group,node){return group+' · '+node.name;}
function gStaticClone(source,key,reg,page,prefix){
 let n=reg[key];if(n)n.remove();n=source.clone();page.appendChild(n);n.name=(prefix==='D/'?'Desktop / ':'Mobile / ')+key;n.setPluginData('rainlink-canonical-name',n.name);n.setPluginData('rainlink',prefix==='D/'?'desktop/'+key:'mobile/'+key);n.setPluginData('rainlink-group-version','4.0');reg[key]=n;return n;
}
function gUnbindInteractionState(root){
 const ids=new Set(Object.values(gVars).map(v=>v.id));
 for(const n of [root,...root.findAll(()=>true)]){
  const bound=n.boundVariables||{};
  for(const field of ['characters','visible','opacity'])if(bound[field]&&ids.has(bound[field].id))n.setBoundVariable(field,null);
  for(const field of ['fills','strokes'])if(field in n&&Array.isArray(n[field]))n[field]=n[field].map(p=>{
   const a=p.boundVariables&&p.boundVariables.color;
   if(!a||!ids.has(a.id))return p;
   const v=Object.values(gVars).find(v=>v.id===a.id),value=v.valuesByMode[gInteractionCollection.defaultModeId];
   return {type:'SOLID',color:{r:value.r,g:value.g,b:value.b},opacity:p.opacity===undefined?1:p.opacity};
  });
 }
}
function gStaticChosen(screen,group,data){
 for(const c of screen.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Group · '))){
  const chosen=(c.getPluginData('rainlink-canonical-name')||c.name)==='Group · '+group;
  const check=uFind(c,'分组选中');if(check)check.visible=chosen;fill(c,chosen?'PrimarySurface':'Surface');
 }
 const summary=uFind(screen,'Selection summary');
 if(summary){const ts=summary.children.filter(n=>n.type==='TEXT');gStaticText(ts[0],group);gStaticText(ts[1],data.name);}
 screen.setPluginData('rainlink-chosen-target',gStaticKey(group,data));
}
function gStaticNodeChosen(screen,group,data){
 for(const c of screen.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Group node / '))){
  const t=uFind(c,'节点名称'),selected=t&&t.characters===data.name,check=uFind(c,'节点选中');
  if(check)check.visible=selected;fill(c,selected?'PrimarySurface':'Surface');stroke(c,selected?'Primary':'Stroke');
 }
 const aside=uFind(screen,'Selected group node');
 if(aside){const ts=aside.children.filter(n=>n.type==='TEXT');gStaticText(ts[1],data.name);const facts=uFind(aside,'Selected node protocol');if(facts){gStaticText(facts.findOne(n=>n.type==='TEXT'&&(n.getPluginData('rainlink-canonical-name')||n.name)==='Label'),data.p);gStaticText(facts.children.find(n=>n.type==='TEXT'),data.ping+' ms');}}
 screen.setPluginData('rainlink-chosen-target',gStaticKey(group,data));
}
function gStaticHeader(screen,group,data,online=false){
 const bar=uFind(screen,'Connection bar');if(!bar)return;for(const n of [...bar.children])n.remove();
 add(bar,add(row('Persistent group status',null,null,10),dot(online?'Primary':'Muted'),uText(online?'已连接':'未连接',13,online?'Primary':'Muted','Medium'),online?uSmall(group+' / '+data.name,'Secondary'):null),add(row('Persistent group speeds',null,null,16),online?uSmall(data.ping+' ms','Secondary'):null,uSmall(online?'↓ 12.8 MB/s':'↓ 0 MB/s','Secondary'),uSmall(online?'↑ 1.4 MB/s':'↑ 0 MB/s','Muted'),uButton('概览','D/'+(online?'Dashboard':'Disconnected'),'Ghost','grid')));
}
function gStaticHomeTarget(screen,group,data,online=false){
 const target=uFind(screen,'Overview target');if(target){gStaticText(target.children[0],group);gStaticText(target.children[1],data.name);}
 const mobile=uFind(screen,'Selected connection group');
 if(mobile){const name=uFind(mobile,'Selected group heading').children[0];gStaticText(name,group);const node=mobile.children.find(n=>n.type==='TEXT');gStaticText(node,data.name);const facts=uFind(mobile,'Selected group node');if(facts){gStaticText(facts.children[0],'延迟');gStaticText(facts.children[1],data.ping+' ms');}}
 gStaticHeader(screen,group,data,online);screen.setPluginData('rainlink-chosen-target',gStaticKey(group,data));screen.setPluginData('rainlink-overview-online',online?'true':'false');
 // Remove duplicate mode labels; the mode component is the one source of truth.
 const hero=uFind(screen,'Connection hero heading');if(hero){const badgeNode=hero.children.find(n=>n.type==='INSTANCE');if(badgeNode)badgeNode.visible=false;}
 const caption=uFind(screen,'VPN mode caption');if(caption){caption.children[0].visible=false;gStaticText(caption.children[1],online?'点按关闭 VPN':'点按开启 VPN');}
}
async function gStaticModeLibrary(){
 for(const mobile of [false,true]){
  const name='Overview / Proxy mode / '+(mobile?'Mobile':'Desktop'),rule=masters[name];
  let set=rule.parent.type==='COMPONENT_SET'?rule.parent:null;
  if(set){for(const n of [...set.children])if(n.id!==rule.id)n.remove();}
  const variants=[rule];
  for(const mode of ['全局','直连']){const c=rule.clone();dsPage.appendChild(c);variants.push(c);}
  if(!set)set=figma.combineAsVariants(variants,dsPage);else for(const c of variants)if(c.parent!==set)set.appendChild(c);
  set.name='Overview / 代理模式 / '+(mobile?'Mobile':'Desktop');set.setPluginData('rainlink-canonical-name',set.name);set.layoutMode='VERTICAL';set.primaryAxisSizingMode='AUTO';set.counterAxisSizingMode='AUTO';set.itemSpacing=24;set.paddingLeft=set.paddingRight=set.paddingTop=set.paddingBottom=24;
  for(let i=0;i<variants.length;i++){
   const c=variants[i];gUnbindInteractionState(c);c.name='模式='+G_MODES[i];c.setPluginData('rainlink-canonical-name',i===0?name:c.name);c.description='代理模式交互组件。规则、全局和直连，三种模式均在概览中切换。';
   for(const option of G_MODES){const item=uFind(c,'代理模式 · '+option);fill(item,option===G_MODES[i]?'PrimarySurface':'Raised');const t=item.findOne(n=>n.type==='TEXT');fill(t,option===G_MODES[i]?'Primary':'Secondary');}
   const desc=uFind(c,'模式说明');if(desc)gStaticText(desc,G_MODE_COPY[i]);
  }
  for(const c of variants)for(let i=0;i<G_MODES.length;i++){
   const option=uFind(c,'代理模式 · '+G_MODES[i]);
   if(c.id===variants[i].id){await option.setReactionsAsync([]);continue;}
   await option.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:variants[i].id,navigation:'CHANGE_TO',transition:{type:'SMART_ANIMATE',easing:{type:'EASE_OUT'},duration:.18}}]}]);
  }
  set.x=4870;set.y=mobile?420:0;
 }
}
async function gStaticWire(){
 figma.ui.postMessage({status:'构建免费方案可用的选择状态原型…'});
 // No paid prototype actions are used. Selection states are native Auto Layout frames.
 for(const p of [desktopPage,mobilePage])for(const s of p.children.filter(n=>n.type==='FRAME'&&n.getPluginData('rainlink')))gUnbindInteractionState(s);
 const originalLinks=[...pending,...uLinks].filter(l=>l.node&&!l.node.removed),staticRoutes=new Map();
 const put=(n,target,kind='navigate')=>{if(n)staticRoutes.set(n.id,{node:n,target,kind});};
 const rootOf=n=>{let r=n;while(r.parent&&r.parent.type!=='PAGE')r=r.parent;return r;};
 for(const l of originalLinks)if(['D/','M/'].some(p=>l.target.startsWith(p))){
  const root=rootOf(l.node),online=root.getPluginData('rainlink-overview-online')==='true';
  let target=l.target;if((target==='D/Dashboard'||target==='M/Home')&&!online)target=target[0]+('/Disconnected');
  put(l.node,target);
 }
 // Every node in the example lists gets an accurate selected state and overview target.
 const targets=new Map();
 for(const [group,nodes]of Object.values(gStaticNodes))for(const data of nodes)targets.set(gStaticKey(group,data),{group,data});
 targets.set('主订阅 · 开发代理链',{group:'主订阅',data:{name:'开发代理链 · 办公 HTTP → 东京',p:'2 跳 · TCP',ping:'46'},chain:true});
 targets.set('主订阅 · 反向开发代理链',{group:'主订阅',data:{name:'开发代理链 · 东京 → 办公 HTTP',p:'2 跳 · TCP',ping:'39'},chain:'reverse'});
 for(const [id,{group,data,chain}]of targets){
  const ready='待连接 · '+id,live='已连接 · '+id;
  gHome(ready,group,data,false,chain||false);gHome(live,group,data,true,chain||false);
  gStaticTargets.set(id,{ready,live,group,data});
  for(const [reg,p]of [[registry.desktop,'D/'],[registry.mobile,'M/']]){
   for(const [key,online]of [[ready,false],[live,true]]){
    const s=reg[key];gUnbindInteractionState(s);gStaticHomeTarget(s,group,data,online);
    const power=s.findOne(n=>n.getPluginData('rainlink-control-kind')==='vpn-power');put(power,p+(online?ready:live),'vpn-power');
    for(const n of s.findAll(n=>(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Navigate · ')||(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Tab · '))){const canonical=n.getPluginData('rainlink-canonical-name')||n.name,dest=canonical.split(' · ')[1];put(n,p+(dest==='Dashboard'||dest==='Home'?key:dest));}
    for(const n of s.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Button · '))){const canon=n.getPluginData('rainlink-canonical-name')||n.name;if(canon.includes('选择分组')||canon==='Button · 选择')put(n,p+(online?'Connected switch':'Quick switch'));}
   }
  }
 }
 for(const [reg,page,p]of [[registry.desktop,desktopPage,'D/'],[registry.mobile,mobilePage,'M/']]){
  const inventories=new Map();
  for(const [key,[group,nodes]]of Object.entries(gStaticNodes)){
   for(const data of nodes){const stateKey='选择节点 · '+key+' · '+data.name;
    const s=gStaticClone(reg[key],stateKey,reg,page,p);gUnbindInteractionState(s);gStaticNodeChosen(s,group,data);inventories.set(stateKey,{s,group,data});
   }
  }
  const allInventories=[...Object.entries(gStaticNodes).map(([key,[group,nodes]])=>({s:reg[key],group,data:nodes[0],base:key})),...Array.from(inventories.values()).map(x=>({...x,base:x.s.getPluginData('rainlink').split('/').slice(1).join('/').split(' · ')[1]}))];
  for(const {s,group,data,base}of allInventories){
   if(!base||!gStaticNodes[base])continue;
   const target=gStaticTargets.get(gStaticKey(group,data));
   for(const n of s.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Group node / '))){const t=uFind(n,'节点名称'),next='选择节点 · '+base+' · '+t.characters;put(n,p+next,'select-node');const move=uFind(n,'未分组节点移动');if(move&&move.visible&&t.characters==='办公 HTTP')put(move,p+'Move group');}
   for(const n of s.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Button · '))){const c=n.getPluginData('rainlink-canonical-name')||n.name;if(c==='Button · 去概览')put(n,p+target.ready);else if(c==='Button · 全部分组')put(n,p+'Profiles');else if(c==='Button · 代理链')put(n,p+'Chains');else if(c==='Button · 测速'||c==='Button · 测速完成')put(n,p+(base==='Nodes'?'Nodes tested':base));}
   for(const n of s.findAll(n=>(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Navigate · ')||(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Tab · '))){const dest=(n.getPluginData('rainlink-canonical-name')||n.name).split(' · ')[1];put(n,p+(dest==='Dashboard'||dest==='Home'?target.ready:dest));}
  }
  // Group card selection stays on the group list. Its node entry is a separate action.
  const groupPages=['Profiles','Source success','Import success','Manual success','Moved','Groups custom','Quick switch'];
  for(const key of groupPages){if(!reg[key])continue;const source=reg[key],states=[];
   const cards=source.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Group · '));
   for(const card of cards){const group=(card.getPluginData('rainlink-canonical-name')||card.name).slice(8),data=gGroupsData[group][0],stateKey='选择分组 · '+key+' · '+group,s=gStaticClone(source,stateKey,reg,page,p);gUnbindInteractionState(s);gStaticChosen(s,group,data);states.push({s,group,data,stateKey});}
   for(const {s,group,data}of [{s:source,group:'主订阅',data:G_MAIN[0]},...states]){
    const choice=gStaticTargets.get(gStaticKey(group,data));
    for(const card of s.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Group · '))){const name=(card.getPluginData('rainlink-canonical-name')||card.name).slice(8);put(card,p+'选择分组 · '+key+' · '+name,'select-group');const detail=uFind(card,'组节点入口');const target={'主订阅':key==='Moved'?'Moved nodes':'Nodes','备用订阅':'Backup group','未分组':key==='Manual success'?'Manual added nodes':['Moved','Groups custom'].includes(key)?'Ungrouped after move':'Ungrouped','开发环境':'Customgroup','旅行订阅':'Travel group'}[name];put(detail,p+target);}
    for(const n of s.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Button · '))){const c=n.getPluginData('rainlink-canonical-name')||n.name;if(['Button · 去概览','Button · 返回概览','Button · 关闭'].includes(c))put(n,p+choice.ready);}
    for(const n of s.findAll(n=>(n.getPluginData('rainlink-canonical-name')||n.name)==='Navigate · Dashboard'||(n.getPluginData('rainlink-canonical-name')||n.name)==='Tab · Home'))put(n,p+choice.ready);
   }
  }
  // Saving a chain selects its target and opens a disconnected overview.
  for(const [key,target]of [['Chain tested','主订阅 · 开发代理链'],['Chain reverse tested','主订阅 · 反向开发代理链'],['Chains','主订阅 · 开发代理链']])for(const n of reg[key].findAll(n=>n.getPluginData('rainlink-control-kind')==='select-chain'))put(n,p+gStaticTargets.get(target).ready,'select-chain');
  const onlineSwitch=gStaticClone(reg['Quick switch'],'Connected switch',reg,page,p);gUnbindInteractionState(onlineSwitch);gStaticHeader(onlineSwitch,'主订阅',G_MAIN[0],true);
  const localPending=gStaticClone(reg['Pending selection'],'待应用 · 未分组',reg,page,p);gUnbindInteractionState(localPending);
  for(const t of localPending.findAll(n=>n.type==='TEXT'))if(t.characters.includes('待应用：备用订阅'))gStaticText(t,'待应用：未分组 / 办公 HTTP · 关闭再开启 VPN 后生效');
  for(const card of onlineSwitch.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Group · '))){const group=(card.getPluginData('rainlink-canonical-name')||card.name).slice(8);put(card,p+(group==='主订阅'?(p==='D/'?'Dashboard':'Home'):group==='未分组'?'待应用 · 未分组':'Pending selection'),'select-group-pending');}
  for(const n of onlineSwitch.findAll(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Button · ')))if(['Button · 返回概览','Button · 关闭'].includes(n.getPluginData('rainlink-canonical-name')||n.name))put(n,p+(p==='D/'?'Dashboard':'Home'));
  const pendingScreen=reg['Pending selection'];for(const n of pendingScreen.findAll(n=>n.getPluginData('rainlink-control-kind')==='vpn-power'))put(n,p+gStaticTargets.get(gStaticKey('备用订阅',G_BACKUP[0])).ready,'vpn-power');
  for(const n of localPending.findAll(n=>n.getPluginData('rainlink-control-kind')==='vpn-power'))put(n,p+gStaticTargets.get(gStaticKey('未分组',G_LOOSE[0])).ready,'vpn-power');
  if(p==='M/')for(const [s,label]of [[pendingScreen,'备用订阅 / 伦敦 · 泰晤士'],[localPending,'未分组 / 办公 HTTP']])add(uFind(s,'Selected connection group'),uSmall('已选：'+label,'Warning',321));
  for(const [key,s]of Object.entries(reg)){
   if(s.getPluginData('rainlink-overview-online')!==''&&!key.startsWith('待连接 · ')&&!key.startsWith('已连接 · ')&&!key.startsWith('待应用 · ')&&key!=='Pending selection'){
    const online=s.getPluginData('rainlink-overview-online')==='true';for(const n of s.findAll(n=>n.getPluginData('rainlink-control-kind')==='vpn-power'))put(n,p+(online?'Disconnected':p==='D/'?'Dashboard':'Home'),'vpn-power');
   }
  }
 }
 // Navigation created by the new overview templates must also be included.
 for(const l of uLinks)if(l.node&&!l.node.removed&&!staticRoutes.has(l.node.id))put(l.node,l.target);
 for(const [reg,p]of [[registry.desktop,'D/'],[registry.mobile,'M/']])for(const [key,s]of Object.entries(reg)){
  for(const n of s.findAll(n=>'reactions'in n)){
   const canonical=n.getPluginData('rainlink-canonical-name')||n.name;
   if(staticRoutes.has(n.id))continue;
   if(canonical.startsWith('Navigate · ')||canonical.startsWith('Tab · ')){let dest=canonical.split(' · ')[1];if(dest==='Dashboard'||dest==='Home')dest=s.getPluginData('rainlink-overview-online')==='true'?(p==='D/'?'Dashboard':'Home'):'Disconnected';put(n,p+dest);}
   else if(canonical.startsWith('Button · ')){
    const label=canonical.slice(9),dest={'添加节点':'Import profile','返回分组':'Profiles','全部分组':'Profiles','返回节点':'Nodes','代理链':'Chains','编排代理链':'Chain editor','取消':'Profiles','查看':'Connections'}[label];if(dest)put(n,p+dest);
    else if(label===''&&n.parent&&((n.parent.getPluginData('rainlink-canonical-name')||n.parent.name)==='Page header'))put(n,p+(key.startsWith('选择节点 · ')?'Profiles':key.startsWith('选择分组 · Quick switch')?'Disconnected':key.startsWith('选择分组 · ')?'Import profile':'Settings'));
   }
  }
  const hero=uFind(s,'Connection hero heading');if(hero){const badgeNode=hero.children.find(n=>n.type==='INSTANCE');if(badgeNode)badgeNode.visible=false;}
  const caption=uFind(s,'VPN mode caption');if(caption){caption.children[0].visible=false;gStaticText(caption.children[1],s.getPluginData('rainlink-overview-online')==='true'?'点按关闭 VPN':'点按开启 VPN');}
  if(key==='Dashboard light'||key==='Home light')applyLight(s);
 }
 const valid=new Set([...Object.values(registry.desktop),...Object.values(registry.mobile)].map(n=>n.id));
 for(const page of [desktopPage,mobilePage])for(const n of page.findAll(n=>'reactions'in n&&n.reactions.length))await n.setReactionsAsync([]);
 let count=0;const edges=[];
 for(const {node,target,kind}of staticRoutes.values()){
  if(node.removed||node.opacity<.5||!valid.has(rootOf(node).id))continue;
  const [p,...bits]=target.split('/'),reg=p==='D'?registry.desktop:registry.mobile,dest=reg[bits.join('/')];if(!dest)throw new Error('Missing static state '+target);
  if(rootOf(node).parent!==dest.parent)continue;
  if(rootOf(node).id===dest.id)continue;
  await node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:dest.id,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false,resetInteractiveComponents:false}]}]);
  edges.push({from:node.id,to:dest.id,screen:rootOf(node).id,label:node.name,kind});
  if(++count%150===0)figma.ui.postMessage({status:'可用原型连接 '+count+' / '+staticRoutes.size});
 }
 await gStaticModeLibrary();
 await gFixOverviewNavigation();gFixOverviewContent();
 for(const [reg,step,columns]of [[registry.desktop,1540,3],[registry.mobile,473,5]]){let i=0;for(const s of Object.values(reg)){s.x=(i%columns)*step;s.y=150+Math.floor(i/columns)*(columns===3?1020:980);i++;}}
 desktopPage.flowStartingPoints=[{nodeId:registry.desktop.Disconnected.id,name:'桌面端 / 概览开启 VPN'},{nodeId:registry.desktop.Profiles.id,name:'桌面端 / 自动归组与选择'}];
 mobilePage.flowStartingPoints=[{nodeId:registry.mobile.Disconnected.id,name:'移动端 / 概览开启 VPN'},{nodeId:registry.mobile.Profiles.id,name:'移动端 / 自动归组与选择'}];
 const controls=edges.filter(e=>e.kind!=='navigate');
 figma.root.setPluginData('rainlink-overview-controls',JSON.stringify({version:'4.0',prototypeImplementation:'Native state frames and interactive component variants; Starter compatible',workspaceRemoved:true,selectionDoesNotConnect:true,powerOnlyOnOverview:true,proxyModeOnlyOnOverview:true,groupRemembersNode:true,pendingChoiceWhileConnected:true,chainSaveSelectsOnly:true,unsupportedActions:['SET_VARIABLE','CONDITIONAL'],stateEdgeCount:controls.length,stateEdgeSample:true,stateEdges:controls.slice(0,120).map(e=>({from:e.from,to:e.to,screen:e.screen,kind:e.kind})),targetStates:Array.from(gStaticTargets.entries())}));
 gSystem();return edges;
}
async function gWire(){return gStaticWire();}
async function gFastInitialize(){
 await figma.loadAllPagesAsync();await loadChineseFonts();for(const style of ['Regular','Medium','Semi Bold','Bold'])await figma.loadFontAsync({family:'Inter',style});await figma.loadFontAsync({family:'Roboto Mono',style:'Regular'});
 desktopPage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='desktop');mobilePage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='mobile');dsPage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='system');
 const base=JSON.parse(figma.root.getPluginData('rainlink-canonical-styles')||'{}');
 const collections=await figma.variables.getLocalVariableCollectionsAsync();for(const c of collections)if(base.collections&&base.collections[c.id])c.name=base.collections[c.id].name;
 collection=collections.find(c=>c.name==='RainLink / Colors / Dark');lightCollection=collections.find(c=>c.name==='RainLink / Colors / Light');darkMode=collection.defaultModeId;lightMode=darkMode;
 for(const v of await figma.variables.getLocalVariablesAsync()){if(base.variables&&base.variables[v.id])v.name=base.variables[v.id];if(v.variableCollectionId===collection.id)vars[v.name]=v;if(v.variableCollectionId===lightCollection.id)lightVars[v.name]=v;}
 for(const c of dsPage.findAll(n=>n.type==='COMPONENT')){const name=c.getPluginData('rainlink-canonical-name')||c.name;if(name.startsWith('Icon / '))icons[name.slice(7)]=c;else if(name.startsWith('Style=')){const parts=name.split(', ');masters['Button / '+parts[0].slice(6)+' / '+parts[1].slice(5)]=c;}else if(name.startsWith('Tone='))masters['Badge / '+name.slice(5)]=c;else masters[name]=c;}
 for(const [reg,page,prefix]of [[registry.desktop,desktopPage,'desktop/'],[registry.mobile,mobilePage,'mobile/']])for(const s of page.children.filter(n=>n.type==='FRAME'&&n.getPluginData('rainlink').startsWith(prefix)))reg[s.getPluginData('rainlink').slice(prefix.length)]=s;
}
async function gRepairMain(){
 figma.showUI('<body style="padding:24px;background:#10181e;color:#a8bac5;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#86e5c3">RainLink / 原型兼容</h2><p id="s">恢复原生组件…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:520,height:180});
 await gFastInitialize();await simplifyGroupsDocument();figma.ui.postMessage({status:'恢复中文并核验布局…'});const report=gV4Report(await localizeDocument());await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Profiles];figma.viewport.scrollAndZoomIntoView([registry.desktop.Profiles]);figma.notify('概览已统一 · '+report.counts.desktop+' 桌面 / '+report.counts.mobile+' 移动 · '+report.overflow.length+' 排版待检');figma.closePlugin();
}
async function gFinalizeStaticMain(){
 figma.showUI('<body style="padding:24px;background:#10181e;color:#a8bac5;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#86e5c3">RainLink / 核验原型</h2><p id="s">载入已有状态，不重建页面…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:520,height:180});
 await gFastInitialize();
 const cols=await figma.variables.getLocalVariableCollectionsAsync();gInteractionCollection=cols.find(c=>c.name==='RainLink / 交互状态');
 for(const v of await figma.variables.getLocalVariablesAsync())if(v.variableCollectionId===gInteractionCollection.id)gVars[v.name]=v;
 figma.ui.postMessage({status:'修复代理模式组件…'});await gStaticModeLibrary();
 for(const [reg,mobile]of [[registry.desktop,false],[registry.mobile,true]]){
  const rule=masters['Overview / Proxy mode / '+(mobile?'Mobile':'Desktop')],variants=rule.parent.children;
  for(const [key,mode]of [['Mode global',1],['Mode direct',2]]){const c=reg[key]&&reg[key].findOne(n=>n.type==='INSTANCE'&&(n.getPluginData('rainlink-canonical-name')||n.name)==='Overview / Proxy mode / '+(mobile?'Mobile':'Desktop'));if(c)c.swapComponent(variants[mode]);}
  if(!mobile)for(const [key,group,data]of [['Backup connected','备用订阅',G_BACKUP[0]],['Manual connected','未分组',G_LOOSE[0]],['Local connected','未分组',G_LOOSE[1]],['Custom connected','开发环境',G_LOOSE[0]],['Travel connected','旅行订阅',G_MAIN[2]],['Chain connected','主订阅',{name:'开发代理链',ping:'46'}],['Chain reverse connected','主订阅',{name:'反向开发代理链',ping:'39'}]])if(reg[key])gStaticHeader(reg[key],group,data,true);
 }
 for(const [reg,step,columns]of [[registry.desktop,1540,3],[registry.mobile,473,5]]){let i=0;for(const s of Object.values(reg)){s.x=(i%columns)*step;s.y=150+Math.floor(i/columns)*(columns===3?1020:980);i++;}if(reg['Connected switch'])reg['Connected switch'].setPluginData('rainlink-overview-online','true');}
 desktopPage.flowStartingPoints=[{nodeId:registry.desktop.Disconnected.id,name:'桌面端 / 概览开启 VPN'},{nodeId:registry.desktop.Profiles.id,name:'桌面端 / 自动归组与选择'}];mobilePage.flowStartingPoints=[{nodeId:registry.mobile.Disconnected.id,name:'移动端 / 概览开启 VPN'},{nodeId:registry.mobile.Profiles.id,name:'移动端 / 自动归组与选择'}];
 const edges=[];
 for(const page of [desktopPage,mobilePage])for(const screen of page.children.filter(n=>n.type==='FRAME'&&n.getPluginData('rainlink')))for(const node of screen.findAll(n=>'reactions'in n&&n.reactions.length))for(const r of node.reactions)for(const a of r.actions||[])if(a.type==='NODE'&&a.navigation==='NAVIGATE')edges.push({from:node.id,to:a.destinationId,screen:screen.id,label:node.name,kind:node.getPluginData('rainlink-control-kind')||'navigate'});
 const controlEdges=edges.filter(e=>e.kind.startsWith('select-')||e.kind==='vpn-power');
 figma.root.setPluginData('rainlink-overview-controls',JSON.stringify({version:'4.0',prototypeImplementation:'Native state frames and interactive components; Starter compatible',workspaceRemoved:true,selectionDoesNotConnect:true,powerOnlyOnOverview:true,proxyModeOnlyOnOverview:true,groupRemembersNode:true,pendingChoiceWhileConnected:true,chainSaveSelectsOnly:true,unsupportedActions:['SET_VARIABLE','CONDITIONAL'],stateEdgeCount:controlEdges.length,stateEdgeSample:true,stateEdges:controlEdges.slice(0,120).map(e=>({from:e.from,to:e.to,screen:e.screen,kind:e.kind}))}));
 gSystem();
 await gFixOverviewNavigation();gFixOverviewContent();
 const old=JSON.parse(figma.root.getPluginData('rainlink-report')||'{}');delete old.groupEdges;delete old.overviewControls;Object.assign(old,{version:'4.0',desktop:Object.fromEntries(Object.entries(registry.desktop).map(([k,n])=>[k,n.id])),mobile:Object.fromEntries(Object.entries(registry.mobile).map(([k,n])=>[k,n.id])),prototypeNavigationCount:edges.length});figma.root.setPluginData('rainlink-report',JSON.stringify(old));
 figma.ui.postMessage({status:'恢复简体中文与排版核验…'});const report=gV4Report(await localizeDocument());
 // Keep Figma variant names valid after general layer localization.
 for(const set of dsPage.children.filter(n=>n.type==='COMPONENT_SET'&&(n.getPluginData('rainlink-canonical-name')||n.name).startsWith('Overview / 代理模式 / ')))for(let i=0;i<set.children.length;i++)set.children[i].name='模式='+G_MODES[i];
 await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Profiles];figma.viewport.scrollAndZoomIntoView([registry.desktop.Profiles]);figma.notify('概览原型完成 · '+report.counts.desktop+' 桌面 / '+report.counts.mobile+' 移动 · '+report.overflow.length+' 排版待检');figma.closePlugin();
}

// Correct inherited sidebar interactions without rebuilding or relocalizing the document.
async function gFixOverviewNavigation(){
 let count=0;
 for(const [reg,mobile]of [[registry.desktop,false],[registry.mobile,true]])for(const [key,s]of Object.entries(reg)){
  const isOverview=!!s.findOne(n=>n.getPluginData('rainlink-control-kind')==='vpn-power');
  const chosen=s.getPluginData('rainlink-chosen-target'),online=s.getPluginData('rainlink-overview-online')==='true';
  let target=isOverview?s:reg[(online?'已连接 · ':'待连接 · ')+chosen];
  if(!target&&chosen.includes('反向开发代理链'))target=reg[(online?'已连接 · ':'待连接 · ')+'主订阅 · 反向开发代理链'];
  if(!target&&chosen.includes('开发代理链'))target=reg[(online?'已连接 · ':'待连接 · ')+'主订阅 · 开发代理链'];
  if(!target&&gStaticNodes[key])target=reg['待连接 · '+gStaticKey(gStaticNodes[key][0],gStaticNodes[key][1][0])];
  if(!target)target=reg[online?(mobile?'Home':'Dashboard'):'Disconnected'];
  const nav=mobile?uFind(s,'Mobile / Bottom navigation'):uFind(s,'Primary navigation');
  const item=nav&&nav.children.find(n=>n.findOne&&n.findOne(t=>t.type==='TEXT'&&[mobile?'首页':'概览',mobile?'Home':'Dashboard'].includes(t.characters)));
  if(!item)continue;
  if(target.id===s.id)await item.setReactionsAsync([]);
  else await item.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:target.id,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},resetInteractiveComponents:false}]}]);count++;
  if(count%20===0){figma.ui.postMessage({status:'修正概览导航 '+count+' / '+(Object.keys(registry.desktop).length+Object.keys(registry.mobile).length)});await new Promise(r=>setTimeout(r,10));}
 }
 return count;
}
function gFixOverviewContent(){
 const rules=registry.desktop.Rules;
 const modes=rules&&rules.findOne(n=>n.type==='FRAME'&&n.children&&n.children.length===3&&n.findAll(t=>t.type==='TEXT'&&['规则模式','全局模式','直连模式','Rule mode','Global mode','Direct mode'].includes(t.characters)).length===3);
 if(modes)modes.remove();
 const heading=rules&&uFind(rules,'Page header');
 const copy=heading&&heading.findAll(n=>n.type==='TEXT');
 if(copy&&copy[1])gStaticText(copy[1],'代理模式在概览设置，这里管理分流规则与优先级。');
 const network=uFind(registry.mobile.Settings,'Network preferences');
 if(network)for(const n of [...network.children])if(n.type==='FRAME'&&n.findOne(t=>t.type==='TEXT'&&['分流模式','路由模式','代理模式','Routing mode','Routing Mode'].includes(t.characters))){const i=network.children.indexOf(n),prior=network.children[i-1];n.remove();if(prior&&prior.height<=1)prior.remove();}
 const data=[...G_MAIN,...G_BACKUP,...G_LOOSE,{name:'备用 HTTP',ping:'16'}];
 for(const s of Object.values(registry.mobile)){
  const card=uFind(s,'Selected connection group'),facts=card&&uFind(card,'Selected group node');if(!facts)continue;
  const node=card.children.find(n=>n.type==='TEXT'),name=node&&node.characters||'';
  let ping=data.find(d=>name===d.name);ping=ping?ping.ping+' ms':name.includes('→')?(name.startsWith('东京')?'39 ms':'46 ms'):'—';
  gStaticText(facts.children[0],'延迟');gStaticText(facts.children[1],ping);facts.children[0].name='延迟';facts.children[1].name=ping;
 }
}
async function gTouchupMain(){
 figma.showUI('<body style="padding:24px;background:#10181e;color:#86e5c3;font:13px Microsoft YaHei,sans-serif"><p id="s">修正概览导航与旧入口…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:400,height:110});
 await figma.loadAllPagesAsync();await loadChineseFonts();for(const style of ['Regular','Medium','Semi Bold','Bold'])await figma.loadFontAsync({family:'Inter',style});await figma.loadFontAsync({family:'Roboto Mono',style:'Regular'});
 desktopPage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='desktop');mobilePage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='mobile');dsPage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='system');
 for(const [reg,page,prefix]of [[registry.desktop,desktopPage,'desktop/'],[registry.mobile,mobilePage,'mobile/']])for(const s of page.children.filter(n=>n.type==='FRAME'&&n.getPluginData('rainlink').startsWith(prefix)))reg[s.getPluginData('rainlink').slice(prefix.length)]=s;
 const count=await gFixOverviewNavigation();gFixOverviewContent();await gFinalizeTokenLabels();
 const report=JSON.parse(figma.root.getPluginData('rainlink-report'));
 report.interactionCorrection={overviewNavigationOverrides:count,activeOverviewHasNoExtraNavigation:true,oldModeEntriesRemoved:true,mobileLatencyLabelCorrected:true};
 figma.root.setPluginData('rainlink-report',JSON.stringify(report));const audit=uFind(dsPage,'Delivery / Native audit');audit.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);audit.visible=false;
 await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Profiles];figma.viewport.scrollAndZoomIntoView([registry.desktop.Profiles]);figma.notify('概览导航与旧模式入口已修正');figma.closePlugin();
}
async function gFinalizeTokenLabels(){
 await figma.loadAllPagesAsync();
 const report=JSON.parse(figma.root.getPluginData('rainlink-report'));
 for(const reg of [report.desktop,report.mobile])if(reg['待应用 · 未分组']){
  const screen=await figma.getNodeByIdAsync(reg['待应用 · 未分组']),power=screen.findOne(n=>n.getPluginData('rainlink-control-kind')==='vpn-power');
  await power.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:reg['待连接 · 未分组 · 办公 HTTP'],navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},resetInteractiveComponents:false}]}]);
 }
 const names={'RainLink / Colors / Dark':'RainLink / 颜色 / 深色','RainLink / Colors / Light':'RainLink / 颜色 / 浅色','RainLink / Spacing & radius':'RainLink / 间距与圆角'};
 const tokens={Background:'背景',Surface:'界面表层',Raised:'浮起表层',Hover:'悬停',Stroke:'边框',Text:'主要文字',Secondary:'次要文字',Muted:'弱化文字',Primary:'主色',PrimarySurface:'主色表层',OnPrimary:'主色上文字',Success:'成功',Warning:'警告',WarningSurface:'警告表层',Error:'错误',ErrorSurface:'错误表层',Info:'信息',InfoSurface:'信息表层',Chart2:'图表辅助色',Transparent:'透明',Space:'间距',Radius:'圆角'};
 for(const c of await figma.variables.getLocalVariableCollectionsAsync()){c.name=names[c.name]||c.name;for(const m of c.modes)if(m.name==='Mode 1')c.renameMode(m.modeId,'默认');}
 for(const v of await figma.variables.getLocalVariablesAsync())v.name=v.name.split('/').map(s=>tokens[s]||s).join('/');
}
async function gTokenLabelsMain(){await gFinalizeTokenLabels();figma.notify('设计变量默认中文已恢复');figma.closePlugin();}

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

// RainLink 6: native overlays and subscription metadata; sample data only.
const R6_INFO={
 '主订阅':{used:'42.8',total:'200',remaining:'157.2',ratio:.214,expires:'2026-11-30',status:'正常',tone:'Primary',updated:'10:32',up:'2.6 GB',down:'40.2 GB'},
 '备用订阅':{used:'96.2',total:'100',remaining:'3.8',ratio:.962,expires:'2026-10-17',status:'3 天后到期',tone:'Warning',updated:'10:28',up:'6.4 GB',down:'89.8 GB'},
 '旅行订阅':{used:null,total:null,ratio:null,expires:null,status:'信息未提供',tone:'Muted',updated:'刚刚',up:null,down:null},
 '已过期订阅':{used:'68.4',total:'100',remaining:'31.6',ratio:.684,expires:'2026-10-10',status:'已过期',tone:'Error',updated:'10:32',up:'4.4 GB',down:'64 GB'},
 '流量已耗尽':{used:'100',total:'100',remaining:'0',ratio:1,expires:'2026-11-30',status:'流量已耗尽',tone:'Error',updated:'10:32',up:'8 GB',down:'92 GB'}
};
const r6Changes=new Set(),r6Routes=[],r6OverlayIds=new Set();
function rootOf(n){let root=n;while(root.parent&&root.parent.type!=='PAGE')root=root.parent;return root;}
function r6Name(n,name){n.name=name;n.setPluginData('rainlink-canonical-name',name);return n;}
function r6Copy(n,s){if(!n)return;n.setBoundVariable('characters',null);n.characters=s;n.setPluginData('rainlink-original-text',s);if(/[\u3400-\u9fff]/.test(s))n.fontName={family:zhFamily,style:zhStyles.Regular};}
function r6Text(s,size=14,color='Text',weight='Regular',w=null){return r6Name(uText(s,size,color,weight,w),s);}
function r6Button(s,tone='Secondary',ic=null,w=null){const n=instance('Button / '+tone+' / M'),label=uFind(n,'Label'),slot=uFind(n,'Icon slot');r6Copy(label,s);if(label)label.visible=!!s;if(slot){slot.visible=!!ic;if(ic)slot.swapComponent(icons[ic]);}n.primaryAxisSizingMode=w?'FIXED':'AUTO';n.resize(w||n.width,44);n.primaryAxisAlignItems='CENTER';rad(n,8);return r6Name(n,'按钮 · '+(s||'图标'));}
function r6Badge(s,tone='Neutral'){const n=instance('Badge / '+tone);r6Copy(uFind(n,'Label'),s);const d=uFind(n,'Status dot');if(d)d.visible=false;n.primaryAxisSizingMode='AUTO';return r6Name(n,'状态 · '+s);}
function r6Field(label,value,w){const f=v(label,w,8),inp=instance('Input / Default');inp.resize(w,44);r6Copy(uFind(inp,'Value'),value);const i=uFind(inp,'Icon slot');if(i)i.visible=false;rad(inp,8);add(f,r6Text(label,12,'Secondary'),r6Name(inp,'输入 · '+label));return f;}
function r6Route(n,dest,nav='OVERLAY'){r6Routes.push({n,dest,nav});return n;}
function r6Close(n){r6Routes.push({n,close:true});return n;}
function r6TabBar(w,manual){const f=rad(row('添加方式',w,40,4,4,'Raised'),8);for(const [i,s]of ['订阅','单个节点'].entries()){const tab=center(rad(row('方式 · '+s,(w-12)/2,32,0,0,i===(manual?1:0)?'Surface':null),6));add(tab,r6Text(s,13,i===(manual?1:0)?'Text':'Muted','Medium'));r6Route(tab,i?'Manual node':'Import profile','SWAP');add(f,tab);}return f;}
function r6Progress(w,ratio,tone='Primary'){const f=rad(row('订阅用量进度',w,4),2);fill(f,'Stroke');f.clipsContent=true;add(f,rad(row('订阅用量已用',Math.max(1,w*(ratio||0)),4,0,0,tone),2));return f;}
function r6ProgressMaster(mobile,ratio){const name='订阅进度 / '+(mobile?'移动端':'桌面端')+' / '+String(ratio);let c=masters[name];if(!c){c=component(name,n=>{n.layoutMode='HORIZONTAL';n.resize(mobile?183:590,4);n.primaryAxisSizingMode=n.counterAxisSizingMode='FIXED';fill(n,'Stroke');rad(n,2);n.clipsContent=true;add(n,rad(row('订阅用量已用',Math.max(1,(mobile?183:590)*ratio),4,0,0,ratio>=1?'Error':ratio>.9?'Warning':'Primary'),2));});r6Name(c,name);c.setPluginData('rainlink-subscription-component','6.0');}return c;}
function r6Meta(w,mobile){const f=row('订阅元信息',w,mobile?38:36,mobile?10:24),usage=v('订阅流量',mobile?183:590,6),expiry=v('订阅有效期',mobile?126:462,4);add(usage,r6Name(r6Text('已用 42.8 / 200 GB',12,'Secondary'),'订阅流量值'),r6Progress(mobile?183:590,.214));add(expiry,r6Name(r6Text('2026-11-30 到期',12,'Secondary'),'订阅到期值'),r6Name(r6Text('剩余 157.2 GB',11,'Muted'),'订阅状态值'));add(f,usage,expiry);f.visible=false;return f;}
function r6GroupLayout(n,mobile){
 const head=uFind(n,'Group heading'),bottom=uFind(n,'Group current node'),copy=uFind(n,'Group copy');n.layoutMode='VERTICAL';n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='FIXED';n.resize(mobile?353:1120,n.height);n.paddingLeft=n.paddingRight=16;n.paddingTop=n.paddingBottom=mobile?14:16;n.itemSpacing=mobile?10:12;n.counterAxisAlignItems='MIN';
 if(mobile){if(copy)copy.resize(182,copy.height);r5Fixed(head,319);r5Fixed(bottom,319,44);}else{const top=uFind(n,'订阅条目主行');r5Fixed(top,1086,44);if(top)top.itemSpacing=24;r5Fixed(head,544);r5Fixed(bottom,518,44);if(copy)copy.resize(414,copy.height);const facts=uFind(n,'Group current identity');if(facts)r5Fixed(facts,392);}
 for(const name of ['组名称','组信息']){const t=uFind(n,name);if(t){t.resize(mobile?182:414,t.height);t.textAutoResize='HEIGHT';}}
 const meta=uFind(n,'订阅元信息');if(meta)r5Fixed(meta,mobile?319:1086,mobile?38:36);
}
function r6ExtendGroupMasters(){for(const mobile of [false,true]){const c=masters['Group / '+(mobile?'Mobile':'Desktop')];if(!uFind(c,'订阅元信息')){const head=uFind(c,'Group heading'),bottom=uFind(c,'Group current node');if(!mobile){const top=row('订阅条目主行',1086,44,24);add(top,head,bottom);c.insertChild(0,top);}const more=r6Button('','Ghost','more',mobile?44:36);r6Name(more,'查看订阅信息');more.visible=false;add(head,more);add(c,r6Meta(mobile?319:1086,mobile));}const progress=uFind(c,'订阅用量进度');if(progress?.type!=='INSTANCE'){const p=progress.parent,index=p.children.indexOf(progress);progress.remove();p.insertChild(index,r6Name(r6ProgressMaster(mobile,.214).createInstance(),'订阅用量进度'));}r6GroupLayout(c,mobile);c.setPluginData('rainlink-subscription-component','6.0');}}
function r6GroupInfo(n,mobile,data){
 r6GroupLayout(n,mobile);const meta=uFind(n,'订阅元信息'),more=uFind(n,'查看订阅信息');if(meta)meta.visible=!!data;if(more)more.visible=!!data;if(!data)return;
 const amount=mobile?(data.used?'已用 '+data.used+' / '+data.total+' GB':'流量未提供'):(data.used?'已用 '+data.used+' GB / '+data.total+' GB':'服务未提供流量信息');r6Copy(uFind(n,'订阅流量值'),amount);r6Copy(uFind(n,'订阅到期值'),data.expires?data.expires+' 到期':'有效期未提供');r6Copy(uFind(n,'订阅状态值'),data.status==='正常'?'剩余 '+data.remaining+' GB':data.status==='信息未提供'?'以服务提供方为准':data.status);const status=uFind(n,'订阅状态值');if(status)fill(status,data.tone==='Primary'?'Muted':data.tone);
 const progress=uFind(n,'订阅用量进度');if(progress){progress.visible=data.ratio!==null;if(data.ratio!==null&&progress.type==='INSTANCE')progress.swapComponent(r6ProgressMaster(mobile,data.ratio));}n.setPluginData('rainlink-subscription-metadata',JSON.stringify(data));
}
function r6DialogComponent(mobile,mode='subscription',state='empty'){
 const name='弹窗 / '+(mobile?'移动端':'桌面端')+' / '+mode+' / '+state;let c=masters[name];if(c){c.primaryAxisSizingMode='AUTO';c.counterAxisSizingMode='FIXED';return c;}
 c=component(name,n=>{
  const w=mobile?393:520,pad=mobile?20:24,iw=w-pad*2;n.layoutMode='VERTICAL';n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='FIXED';n.resize(w,1);n.paddingLeft=n.paddingRight=pad;n.paddingTop=mobile?12:24;n.paddingBottom=mobile?34:24;n.itemSpacing=16;fill(n,'Surface');stroke(n);rad(n,mobile?24:16);n.clipsContent=true;
  if(mobile){const cap=center(row('弹窗拖拽柄容器',iw,8));add(cap,rad(row('弹窗拖拽柄',36,4,0,0,'Stroke'),2));add(n,cap);}
  const close=r6Close(r6Button('','Ghost','close',44));r6Name(close,'关闭弹窗');add(n,between(add(row('弹窗标题',iw,44,12),r6Text(mode==='qr'?'扫码导入':'添加',22,'Text','Medium'),close)));
  const manual=mode==='manual';if(mode!=='qr')add(n,r6TabBar(iw,manual));
  if(mode==='subscription'){
   const field=r6Field('订阅链接',state==='empty'?'粘贴订阅链接':'https://example.com/sub/travel',iw);r6Route(uFind(field,'输入 · 订阅链接'),'Import ready','SWAP');add(n,field);
   if(state==='empty')add(n,r6Route(r6Button('粘贴链接','Secondary','copy',iw),'Import ready','SWAP'));
   add(n,between(add(row('订阅自动更新',iw,44,12),add(v('自动更新说明',iw-68,4),r6Text('自动更新',14,'Text','Medium'),r6Text('每 6 小时',12,'Muted')),sw(true))),r6Text('名称随订阅自动识别，导入后自动成组。',12,'Muted','Regular',iw));
   if(state==='loading')add(n,add(row('订阅导入进度',iw,44,10),icon('refresh',18,'Primary'),r6Text('正在获取节点与订阅信息…',13,'Primary')));
   if(state==='error')add(n,r6Text('订阅获取失败，请检查链接后重试。',13,'Error','Regular',iw));
   if(mobile)add(n,r6Route(r6Button('扫码导入','Ghost','qr',iw),'QR import','SWAP'));
   const footer=add(row('弹窗操作',iw,44,12),r6Close(r6Button('取消','Secondary',null,100)),r6Button(state==='loading'?'正在导入…':'导入订阅','Primary',state==='loading'?'refresh':'download',iw-112)),submit=footer.children[1];r6Name(submit,'确认导入订阅');if(['empty','loading'].includes(state))submit.opacity=.4;else r6Route(submit,'Import loading','SWAP');add(n,footer);
  }else if(manual){
   const protocol=instance('Dropdown / Protocol');protocol.resize(iw,44);add(n,add(v('协议选择',iw,8),r6Text('协议',12,'Secondary'),protocol),r6Field('服务器','proxy.backup.example.com',iw),add(row('地址与名称',iw,null,12),r6Field('端口','8080',mobile?102:132),r6Field('名称（可选）','备用 HTTP',iw-(mobile?114:144))),r6Field('用户名（可选）','未设置',iw),r6Field('密码（可选）','未设置',iw),r6Text('添加后进入「未分组」，可再移动到已有分组。',12,'Muted','Regular',iw));add(n,add(row('弹窗操作',iw,44,12),r6Close(r6Button('取消','Secondary',null,100)),r6Route(r6Button('添加节点','Primary','plus',iw-112),'Manual success','NAVIGATE')));
  }else{const scan=center(borderCard('扫码区域',iw,230,20,16,'Raised'));rad(scan,12);add(scan,icon('qr',100,'Primary'),r6Text('将订阅二维码放入框内',14,'Secondary'));add(n,scan,r6Text('识别后自动带入订阅链接。',12,'Muted','Regular',iw),r6Route(r6Button('识别示例二维码','Primary','qr',iw),'Import ready','SWAP'),r6Route(r6Button('返回链接导入','Ghost',null,iw),'Import profile','SWAP'));}
 });c.primaryAxisSizingMode='AUTO';c.counterAxisSizingMode='FIXED';c.setPluginData('rainlink-subscription-component','6.0');r6Name(c,name);return c;
}
function r6InfoComponent(mobile,group){
 const name='弹窗 / '+(mobile?'移动端':'桌面端')+' / 订阅信息 / '+group;let c=masters[name];if(c){c.primaryAxisSizingMode='AUTO';c.counterAxisSizingMode='FIXED';return c;}const d=R6_INFO[group];c=component(name,n=>{
  const w=mobile?393:520,iw=w-(mobile?40:48);n.layoutMode='VERTICAL';n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='FIXED';n.resize(w,1);n.paddingLeft=n.paddingRight=mobile?20:24;n.paddingTop=24;n.paddingBottom=mobile?34:24;n.itemSpacing=18;fill(n,'Surface');stroke(n);rad(n,mobile?24:16);const close=r6Close(r6Button('','Ghost','close',44));r6Name(close,'关闭弹窗');add(n,between(add(row('订阅信息标题',iw,44,12),r6Text(group,22,'Text','Medium'),close)),r6Badge(d.status,d.tone==='Warning'?'Warning':d.tone==='Error'?'Error':'Neutral'));
  const usage=borderCard('订阅套餐流量',iw,null,16,12,'Raised');rad(usage,12);add(usage,r6Text('订阅流量',12,'Secondary'),r6Text(d.used?d.used+' GB / '+d.total+' GB':'服务未提供流量信息',d.used?24:16,'Text','Medium',iw-32));if(d.used)add(usage,r6Progress(iw-32,d.ratio,d.ratio>.9?'Warning':'Primary'),r6Text('剩余 '+d.remaining+' GB',13,'Secondary'),r6Text('下载 '+d.down+'　·　上传 '+d.up,12,'Muted','Regular',iw-32));add(n,usage);
  for(const [label,value,tone]of [['到期时间',d.expires||'未提供',d.tone==='Error'?'Error':'Secondary'],['最近更新',d.updated,'Secondary'],['自动更新','每 6 小时','Secondary']])add(n,between(add(row('订阅信息 · '+label,iw,32),r6Text(label,13,'Muted'),r6Text(value,13,tone))));if(!d.expires||!d.used)add(n,r6Text('流量与有效期以服务提供方返回的信息为准。',12,'Muted','Regular',iw));add(n,r6Close(r6Button('完成','Primary',null,iw)));
 });c.primaryAxisSizingMode='AUTO';c.counterAxisSizingMode='FIXED';c.setPluginData('rainlink-subscription-component','6.0');r6Name(c,name);return c;
}
function r6Overlay(mobile,key,master){
 const reg=mobile?registry.mobile:registry.desktop,page=mobile?mobilePage:desktopPage,w=mobile?393:1440,h=mobile?852:900;let s=reg[key];if(!s){s=frame('',w,h);page.appendChild(s);reg[key]=s;}for(const n of [...s.children])n.remove();r6Name(s,(mobile?'移动端':'桌面端')+' / 弹窗 / '+key);s.setPluginData('rainlink',(mobile?'mobile/':'desktop/')+key);s.setPluginData('rainlink-dialog','6.0');s.layoutMode='VERTICAL';s.primaryAxisSizingMode='FIXED';s.counterAxisSizingMode='FIXED';s.resize(w,h);s.paddingTop=s.paddingBottom=s.paddingLeft=s.paddingRight=0;s.itemSpacing=0;s.primaryAxisAlignItems=mobile?'MAX':'CENTER';s.counterAxisAlignItems='CENTER';fill(s,null);s.clipsContent=true;
 const scrim=figma.createRectangle();scrim.name='关闭弹窗遮罩';scrim.resize(w,h);scrim.fills=[{type:'SOLID',color:{r:0,g:0,b:0},opacity:.62}];add(s,scrim);scrim.layoutPositioning='ABSOLUTE';scrim.x=scrim.y=0;r6Close(scrim);const dialog=master.createInstance();r6Name(dialog,master.name);add(s,dialog);r6OverlayIds.add(s.id);r6Changes.add(s.id);return s;
}
async function r6ApplyRoutes(){let count=0;for(const x of r6Routes){const n=x.n;if(n.removed)continue;const root=rootOf(n),reg=root.parent===mobilePage?registry.mobile:registry.desktop;let actions;if(x.close)actions=[{type:'CLOSE'}];else{const dest=reg[x.dest];if(!dest)throw new Error('Missing overlay route '+x.dest);if(dest.id===root.id){await n.setReactionsAsync([]);continue;}actions=[{type:'NODE',destinationId:dest.id,navigation:x.nav,transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false,resetInteractiveComponents:false}];}try{await n.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions}]);}catch(e){throw new Error('弹窗路由 '+root.name+' / '+n.name+' ('+n.id+') → '+(x.dest||'关闭')+' / '+(x.nav||'CLOSE')+': '+String(e.message||e));}count++;}return count;}
function r6Preview(mobile,key,overlayKey){const reg=mobile?registry.mobile:registry.desktop,page=mobile?mobilePage:desktopPage;let s=reg[key];if(s)s.remove();s=reg.Profiles.clone();page.appendChild(s);reg[key]=s;r6Name(s,(mobile?'移动端':'桌面端')+' / '+key);s.setPluginData('rainlink',(mobile?'mobile/':'desktop/')+key);s.setPluginData('rainlink-dialog-preview','6.0');const over=reg[overlayKey].clone();add(s,over);over.layoutPositioning='ABSOLUTE';over.x=over.y=0;over.setPluginData('rainlink','');over.setPluginData('rainlink-dialog','');r6Changes.add(s.id);return s;}
function r6Gallery(){
 const name='订阅与弹窗 / 组件规范';let gallery=dsPage.children.find(n=>r5Name(n)===name);if(gallery)gallery.remove();gallery=borderCard(name,1500,null,32,24,'Background');dsPage.appendChild(gallery);r6Name(gallery,name);gallery.x=6500;gallery.y=1000;add(gallery,r6Text('添加弹窗与订阅信息 · 6.0',28,'Text','Medium'),r6Text('添加无需离开当前列表。订阅自动命名、自动成组；服务未提供的数据明确标注。',14,'Secondary','Regular',1436));
 for(const [label,group]of [['正常','主订阅'],['即将到期 / 流量不足','备用订阅'],['未返回信息','旅行订阅'],['已过期','已过期订阅'],['流量已耗尽','流量已耗尽']]){const n=masters['Group / Desktop'].createInstance();r6Copy(uFind(n,'组名称'),group);r6Name(n,'订阅示例 · '+group);r6GroupInfo(n,false,R6_INFO[group]);add(gallery,r6Text(label,14,'Secondary'),n);}
 add(gallery,r6Text('交互约定',20,'Text','Medium'),r6Text('打开弹窗 → 选择订阅或单个节点 → 导入 / 添加 → 自动归组。关闭、取消或点遮罩均返回原页面。',14,'Secondary','Regular',1436),r6Text('订阅名称由服务返回；缺失时使用域名或“订阅 1”，更新时跟随服务名称。手动节点不展示订阅额度。',13,'Muted','Regular',1436));const strip=row('弹窗组件示例',1436,null,24);add(strip,masters['弹窗 / 桌面端 / subscription / ready'].createInstance(),masters['弹窗 / 移动端 / subscription / empty'].createInstance());add(gallery,strip);return gallery;
}
async function r6Update(){
 await r5Initialize();figma.skipInvisibleInstanceChildren=false;Object.assign(C,R5_COLORS);
 const cols=await figma.variables.getLocalVariableCollectionsAsync();collection=cols.find(c=>/Colors \/ Dark|颜色 \/ 深色/.test(c.name));lightCollection=cols.find(c=>/Colors \/ Light|颜色 \/ 浅色/.test(c.name));darkMode=collection.defaultModeId;
 for(const variable of await figma.variables.getLocalVariablesAsync('COLOR')){const key=Object.keys(R5_TOKEN_NAMES).find(k=>variable.name===k||variable.name===R5_TOKEN_NAMES[k]);if(key)(variable.variableCollectionId===lightCollection.id?lightVars:vars)[key]=variable;}
 figma.ui.postMessage({status:'更新共享分组组件与订阅元信息…'});r6ExtendGroupMasters();
 for(const [reg,mobile]of [[registry.desktop,false],[registry.mobile,true]])for(const s of Object.values(reg)){
  for(const n of r5Walk(s).filter(n=>n.type==='INSTANCE'&&r5Name(n).startsWith('Group · '))){const group=r5Name(n).slice(8);r6GroupInfo(n,mobile,R6_INFO[group]);const more=uFind(n,'查看订阅信息');if(more&&more.visible)r6Route(more,'Subscription info · '+group);r6Changes.add(s.id);}
 }
 figma.ui.postMessage({status:'创建桌面弹窗与移动端底部弹窗…'});
 for(const mobile of [false,true]){
  for(const [key,mode,state]of [['Import profile','subscription','empty'],['Import ready','subscription','ready'],['Import loading','subscription','loading'],['Import error','subscription','error'],['Manual node','manual','ready'],...(mobile?[['QR import','qr','ready']]:[])])r6Overlay(mobile,key,r6DialogComponent(mobile,mode,state));
  for(const group of ['主订阅','备用订阅','旅行订阅'])r6Overlay(mobile,'Subscription info · '+group,r6InfoComponent(mobile,group));
 }
 // Wire canonical controls on each dialog instance, including maintenance reruns.
 for(const [reg,mobile]of [[registry.desktop,false],[registry.mobile,true]])for(const [key,s]of Object.entries(reg).filter(([k,n])=>r6OverlayIds.has(n.id)))for(const n of s.findAll(n=>'reactions'in n)){
  const label=r5Name(n);
  if(['关闭弹窗','按钮 · 取消','按钮 · 完成'].includes(label))r6Close(n);
  else if(label==='方式 · 订阅')r6Route(n,'Import profile','SWAP');
  else if(label==='方式 · 单个节点')r6Route(n,'Manual node','SWAP');
  else if(['输入 · 订阅链接','按钮 · 粘贴链接','按钮 · 识别示例二维码'].includes(label))r6Route(n,'Import ready','SWAP');
  else if(label==='按钮 · 扫码导入')r6Route(n,'QR import','SWAP');
  else if(label==='按钮 · 返回链接导入')r6Route(n,'Import profile','SWAP');
  else if(label==='确认导入订阅'&&['Import ready','Import error'].includes(key))r6Route(n,'Import loading','SWAP');
  else if(label==='按钮 · 添加节点'&&key==='Manual node')r6Route(n,'Manual success','NAVIGATE');
 }
 for(let i=r6Routes.length-1;i>=0;i--)if(rootOf(r6Routes[i].n).parent===dsPage)r6Routes.splice(i,1);
 let changedEntrances=0;const overlayKeyById=Object.fromEntries([...Object.entries(registry.desktop),...Object.entries(registry.mobile)].filter(([k,n])=>r6OverlayIds.has(n.id)).map(([k,n])=>[n.id,k]));
 for(const [reg,mobile]of [[registry.desktop,false],[registry.mobile,true]])for(const s of Object.values(reg).filter(n=>!r6OverlayIds.has(n.id))){
  for(const n of s.findAll(n=>'reactions'in n&&n.reactions.length)){
   const reactions=JSON.parse(JSON.stringify(n.reactions));let changed=false;for(const r of reactions)for(const a of r.actions||[])if(a.type==='NODE'&&r6OverlayIds.has(a.destinationId)&&['NAVIGATE','OVERLAY'].includes(a.navigation)){a.destinationId=reg[overlayKeyById[a.destinationId]].id;a.navigation='OVERLAY';changed=true;}
   if(changed){try{await n.setReactionsAsync(reactions);}catch(e){throw new Error('入口 '+s.name+' / '+n.name+' ('+n.id+'): '+String(e.message||e));}changedEntrances++;r6Changes.add(s.id);const label=uFind(n,'Label');if(label?.characters==='添加节点'){r6Copy(label,'添加');r6Name(n,'Button · 添加');}}
  }
 }
 figma.ui.postMessage({status:'更新概览公网 IP、国旗与检测状态…'});const egress=await r6EgressUpdate();
 figma.ui.postMessage({status:'接入原生打开、切换与关闭弹窗交互…'});const routeCount=await r6ApplyRoutes();
 for(const [reg,mobile]of [[registry.desktop,false],[registry.mobile,true]]){
  const s=reg['Import loading'];await s.setReactionsAsync([{trigger:{type:'AFTER_TIMEOUT',timeout:1.0},actions:[{type:'NODE',destinationId:(reg['Source success']||reg['Import success']).id,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false,resetInteractiveComponents:false}]}]);
  for(const [key,overlay]of [['添加订阅预览','Import ready'],['添加单个节点预览','Manual node'],['订阅详情预览','Subscription info · 主订阅']])r6Preview(mobile,key,overlay);
 }
 const gallery=r6Gallery();let y=1000;for(const c of dsPage.children.filter(n=>n.type==='COMPONENT'&&n.getPluginData('rainlink-subscription-component')==='6.0'&&!r5Name(n).startsWith('Group / '))){c.x=8160;c.y=y;y+=c.height+48;}
 desktopPage.flowStartingPoints=[{nodeId:registry.desktop.Disconnected.id,name:'桌面端 / 概览开启 VPN'},{nodeId:registry.desktop.Profiles.id,name:'桌面端 / 自动归组与选择'}];mobilePage.flowStartingPoints=[{nodeId:registry.mobile.Disconnected.id,name:'移动端 / 概览开启 VPN'},{nodeId:registry.mobile.Profiles.id,name:'移动端 / 自动归组与选择'}];
 for(const [reg,step,columns]of [[registry.desktop,1540,3],[registry.mobile,473,5]]){let i=0;for(const s of Object.values(reg)){s.x=(i%columns)*step;s.y=150+Math.floor(i/columns)*(columns===3?1020:980);i++;}}
 figma.ui.postMessage({status:'核验弹窗、元信息与 Auto Layout…'});const report=await r5AuditDocument();report.version='6.0';report.desktop=Object.fromEntries(Object.entries(registry.desktop).map(([k,n])=>[k,n.id]));report.mobile=Object.fromEntries(Object.entries(registry.mobile).map(([k,n])=>[k,n.id]));report.counts={...report.counts,desktop:Object.keys(registry.desktop).length,mobile:Object.keys(registry.mobile).length,components:dsPage.findAll(n=>n.type==='COMPONENT').length};
 report.subscriptionDialogs={version:'6.0',addIsOverlay:true,subscriptionNameFieldRemoved:true,nameSource:'订阅返回名称；缺失时域名或自动编号',nameFollowsSubscription:true,metadataFields:['已用流量','总额度','剩余流量','上传','下载','到期时间','更新时间'],missingDataExplicit:true,statuses:['正常','即将到期','流量不足','已过期','流量已耗尽','信息未提供'],manualNodesNoSubscriptionQuota:true,changedEntrances,routeCount,changedScreenIds:[...r6Changes],overlayIds:[...r6OverlayIds],systemGallery:gallery.id};report.egress=egress;
 delete report.nativeBackup;delete report.screenshotVerification;report.livePrototypeVerification={status:'pending refreshed scan'};figma.root.setPluginData('rainlink-report',JSON.stringify(report));figma.root.setPluginData('rainlink-subscription-version','6.0');const audit=uFind(dsPage,'Delivery / Native audit');audit.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);audit.visible=false;return report;
}
async function r6SubscriptionMain(){
 figma.showUI('<body style="padding:24px;background:#151617;color:#c0c2c8;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#8adcbf">RainLink / 添加与订阅信息</h2><p id="s">载入已有设计，不重建原型…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:520,height:170});
 await r5Yield();const report=await r6Update();await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Profiles,registry.desktop['添加订阅预览']];figma.viewport.scrollAndZoomIntoView(figma.currentPage.selection);figma.notify('弹窗与订阅信息已更新 · '+report.overflow.length+' 处排版待检');figma.closePlugin();
}

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

// Compact the actual document: interactions live in component variants, not copies
// of the entire application. Existing principal screen IDs are retained.
const R7_MAIN_D=['Dashboard','Nodes','Profiles','Rules','Connections','Traffic','Logs','Settings'];
const R7_MAIN_M=['Home','Nodes','Profiles','Traffic','Settings','Quick switch','DNS','Chain editor'];
const r7Sets=[],r7Changes=[];
const r7Click=(id,navigation='CHANGE_TO')=>[{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:id,navigation,transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false}]}];
const r7Timer=id=>[{trigger:{type:'AFTER_TIMEOUT',timeout:1.2},actions:[{type:'NODE',destinationId:id,navigation:'CHANGE_TO',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18}}]}];
async function r7Clear(root){for(const n of [root,...root.findAll(n=>'reactions'in n)])if('setReactionsAsync'in n&&n.reactions.length)await n.setReactionsAsync([]);}
function r7Body(name,w){return component(name,c=>{c.layoutMode='VERTICAL';c.resize(w,1);c.primaryAxisSizingMode='AUTO';c.counterAxisSizingMode='FIXED';c.itemSpacing=12;c.clipsContent=false;c.setPluginData('rainlink-compact-component','7.0');});}
function r7VariantSet(name,children,columns=3){const set=figma.combineAsVariants(children,dsPage);r6Name(set,name);set.layoutMode='NONE';const maxW=Math.max(...children.map(c=>c.width)),maxH=Math.max(...children.map(c=>c.height));children.forEach((c,i)=>{c.x=24+(i%columns)*(maxW+32);c.y=24+Math.floor(i/columns)*(maxH+40);});set.resize(48+Math.min(columns,children.length)*(maxW+32)-32,48+Math.ceil(children.length/columns)*(maxH+40)-40);r7Sets.push(set);return set;}
function r7Instance(c,name){return r6Name(c.createInstance(),name);}
function r7CloneBody(screen,c){const content=uFind(screen,'Content');for(const n of content.children)if(r5Name(n)!=='Page header'){const clone=n.clone();add(c,clone);if(clone.type==='INSTANCE'&&['代理链交互编排','连接开关与出口'].includes(r5Name(clone))){const detached=clone.detachInstance();for(const child of [...detached.children])add(c,child);detached.remove();}}}
async function r7Home(mobile){
 const reg=mobile?registry.mobile:registry.desktop,base=reg[mobile?'Home':'Dashboard'],w=mobile?353:1120,variants={};
 for(const state of ['关闭','连接中','开启','断开中']){
  const off=state==='关闭'||state==='连接中',src=off?reg.Disconnected:(reg['已连接 · 主订阅 · 东京 · 樱花']||base),c=r7Body('连接='+state,w);const saved=!off&&base.getPluginData('rainlink-r7-home-source');if(saved){const original=await figma.getNodeByIdAsync(saved);for(const n of original.children)add(c,n.clone());}else r7CloneBody(src,c);await r7Clear(c);
  const network=uFind(c,'概览出口与模式');if(network){const parent=network.parent,i=parent.children.indexOf(network);network.remove();parent.insertChild(i,r6NetworkInstance(mobile,state==='开启','规则',state.endsWith('中')?'检测中':'已获取'));}
  if(state.endsWith('中'))for(const t of c.findAll(n=>n.type==='TEXT')){if(['VPN 已开启','VPN 已关闭'].includes(t.characters))r6Copy(t,state==='连接中'?'正在连接…':'正在断开…');if(['开启 VPN','关闭 VPN'].includes(t.characters))r6Copy(t,'处理中…');}
  variants[state]=c;
 }
 r7VariantSet('交互 / '+(mobile?'移动端':'桌面端')+' / 连接开关',Object.values(variants),2);
 for(const [state,c]of Object.entries(variants)){
  const power=c.findOne(n=>n.getPluginData('rainlink-control-kind')==='vpn-power');
  if(power&&!state.endsWith('中'))await power.setReactionsAsync(r7Click(variants[state==='开启'?'断开中':'连接中'].id));
  if(state.endsWith('中'))await c.setReactionsAsync(r7Timer(variants[state==='连接中'?'开启':'关闭'].id));
 }
 const content=uFind(base,'Content');if(!base.getPluginData('rainlink-r7-home-source')){const source=r7Body('原始概览内容 / '+(mobile?'移动端':'桌面端'),w);r7CloneBody(reg['已连接 · 主订阅 · 东京 · 樱花']||base,source);base.setPluginData('rainlink-r7-home-source',source.id);source.setPluginData('rainlink-compact-component','source');source.visible=false;}for(const n of [...content.children])if(r5Name(n)!=='Page header')n.remove();add(content,r7Instance(variants['开启'],'连接开关与出口'));r7Changes.push(base.id);
 return {set:variants['开启'].parent.id,states:Object.fromEntries(Object.entries(variants).map(([k,v])=>[k,v.id]))};
}
async function r7Groups(mobile){
 const reg=mobile?registry.mobile:registry.desktop,w=mobile?353:1120,variants={},names=['主订阅','备用订阅','未分组','旅行订阅'];
 for(const selected of names){
  const c=r7Body('选中='+selected,w);
  for(const [name,data,count,type]of [['主订阅',G_MAIN[0],8,'订阅'],['备用订阅',G_BACKUP[0],3,'订阅'],['未分组',G_LOOSE[0],3,'未分组'],['旅行订阅',G_MAIN[2],4,'订阅']]){
   const n=instance('Group / '+(mobile?'Mobile':'Desktop'));r6Name(n,'Group · '+name);for(const [field,value]of [['组名称',name],['组信息',count+' 个节点 · '+(type==='订阅'?'订阅自动更新':'手动添加')],['组当前节点',data.name],['组延迟',data.ping+' ms']])r6Copy(uFind(n,field),value);const check=uFind(n,'分组选中');if(check){check.setBoundVariable('visible',null);check.visible=name===selected;}r6GroupInfo(n,mobile,R6_INFO[name]);
   fill(n,name===selected?'PrimarySurface':'Surface');stroke(n,name===selected?'Primary':'Stroke');add(c,n);
  }
  variants[selected]=c;await r7Clear(c);
 }
 r7VariantSet('交互 / '+(mobile?'移动端':'桌面端')+' / 分组选择',Object.values(variants),2);
 for(const c of Object.values(variants))for(const card of c.children){const group=r5Name(card).slice(8);await card.setReactionsAsync(group===c.name.slice(3)?[]:r7Click(variants[group].id));}
 const build=b=>{add(b,r7Instance(variants['主订阅'],'分组选择列表'),r6Text('订阅自动成组 · 单个节点默认进入未分组',12,'Muted','Regular',w));};
 if(mobile)gM('Profiles','分组','点击选中，在概览开启 VPN',build,'Profiles','M/Import profile',true);else gD('Profiles','分组','选择分组与节点，在概览开启 VPN。',build,'Profiles',uButton('添加','D/Import profile','Primary','plus'));
 if(mobile&&reg['Quick switch']){const b=uFind(reg['Quick switch'],'Content');for(const n of [...b.children])n.remove();add(b,r7Instance(variants['主订阅'],'分组选择列表'),r6Text('选中即可，返回概览后开启 VPN。',12,'Muted','Regular',353),uButton('返回概览','M/Home','Secondary','grid',353));}
 r7Changes.push(reg.Profiles.id);return variants['主订阅'].parent.id;
}
async function r7Nodes(mobile){
 const reg=mobile?registry.mobile:registry.desktop,w=mobile?353:1120,groups={'主订阅':G_MAIN,'备用订阅':G_BACKUP,'未分组':G_LOOSE,'旅行订阅':G_MAIN.slice(0,4)},variants={};
 for(const [group,data]of Object.entries(groups))for(let selected=0;selected<data.length;selected++){
  const c=r7Body('分组='+group+', 选中='+selected,w),tabs=row('节点分组选项',w,40,6);
  for(const name of Object.keys(groups)){const t=center(rad(row('选择节点分组 · '+name,mobile?83:140,36,0,0,name===group?'PrimarySurface':'Raised'),8));add(t,r6Text(name,13,name===group?'Primary':'Secondary'));add(tabs,t);}add(c,tabs);
  if(!mobile)add(c,r5TableHeader());
  for(let i=0;i<data.length;i++){const n=gNode(data[i],mobile,i===selected,group==='未分组');r6Name(n,'选择节点 · '+i);add(c,n);}
  c.itemSpacing=mobile?12:0;await r7Clear(c);variants[group+'/'+selected]=c;
 }
 r7VariantSet('交互 / '+(mobile?'移动端':'桌面端')+' / 节点选择',Object.values(variants),mobile?4:3);
 for(const [key,c]of Object.entries(variants)){
  const [group,selected]=key.split('/');
  for(const name of Object.keys(groups))await uFind(c,'选择节点分组 · '+name).setReactionsAsync(name===group?[]:r7Click(variants[name+'/0'].id));
  for(const n of c.children.filter(n=>r5Name(n).startsWith('选择节点 · '))){const index=r5Name(n).slice(7);await n.setReactionsAsync(index===selected?[]:r7Click(variants[group+'/'+index].id));}
 }
 const speeds={};for(const state of ['测速','测量中…','测速完成']){const c=r7Body('状态='+state,100);add(c,r6Button(state,'Secondary','speed',100));speeds[state]=c;}r7VariantSet('交互 / '+(mobile?'移动端':'桌面端')+' / 测速',Object.values(speeds),3);await speeds['测速'].children[0].setReactionsAsync(r7Click(speeds['测量中…'].id));await speeds['测量中…'].setReactionsAsync(r7Timer(speeds['测速完成'].id));await speeds['测速完成'].children[0].setReactionsAsync(r7Click(speeds['测量中…'].id));
 const build=b=>{const bar=between(row('节点操作',w,44,8)),actions=row('节点操作按钮',null,44,8);add(actions,uButton('代理链',(mobile?'M/':'D/')+'Chain editor','Secondary','link'),r7Instance(speeds['测速'],'测速操作'));add(bar,uButton('全部分组',(mobile?'M/':'D/')+'Profiles','Ghost','folder'),actions);add(b,bar,r7Instance(variants['主订阅/0'],'节点分组与选择'));};
 if(mobile)gM('Nodes','节点','选择节点后，在概览开启 VPN',build,'Nodes','M/Profiles');else gD('Nodes','节点','按分组浏览，点击仅更换选择。',build,'Nodes',uButton('添加','D/Import profile','Primary','plus'));
 r7Changes.push(reg.Nodes.id);return variants['主订阅/0'].parent.id;
}
async function r7Dialogs(mobile){
 const reg=mobile?registry.mobile:registry.desktop,platform=mobile?'移动端':'桌面端',w=mobile?393:520,variants={};
 for(const [key,mode,state]of [['订阅','subscription','empty'],['订阅已填','subscription','ready'],['导入中','subscription','loading'],['订阅错误','subscription','error'],['单个节点','manual','ready'],...(mobile?[['扫码','qr','ready']]:[])]){
  const source=masters['弹窗 / '+platform+' / '+mode+' / '+state],c=source.clone();dsPage.appendChild(c);r6Name(c,'状态='+key);c.setPluginData('rainlink-compact-component','7.0');await r7Clear(c);variants[key]=c;
 }
 for(const [key,title,copy]of [['订阅成功','订阅已导入','已自动创建「旅行订阅」，包含 4 个节点。名称随订阅更新。'],['节点成功','节点已添加','「备用 HTTP」已放入未分组，可在节点列表移动到其他组。']]){
  const c=r7Body('状态='+key,w);fill(c,'Surface');stroke(c);rad(c,24);c.paddingTop=c.paddingBottom=24;c.paddingLeft=c.paddingRight=24;c.itemSpacing=16;add(c,r6Badge('完成','Success'),r6Text(title,24,'Text','Medium'),r6Text(copy,14,'Secondary','Regular',w-48),r6Button('完成','Primary',null,w-48));variants[key]=c;
 }
 r7VariantSet('交互 / '+platform+' / 添加弹窗',Object.values(variants),3);
 for(const [key,c]of Object.entries(variants))for(const n of c.findAll(n=>'setReactionsAsync'in n)){
  const label=r5Name(n);let next;
  if(label==='方式 · 订阅')next='订阅';else if(label==='方式 · 单个节点')next='单个节点';
  else if(['输入 · 订阅链接','按钮 · 粘贴链接','按钮 · 识别示例二维码'].includes(label))next='订阅已填';
  else if(label==='按钮 · 扫码导入')next='扫码';else if(label==='按钮 · 返回链接导入')next='订阅';
  else if(label==='确认导入订阅'&&['订阅已填','订阅错误'].includes(key))next='导入中';
  else if(label==='按钮 · 添加节点')next='节点成功';
  if(next&&next!==key)await n.setReactionsAsync(r7Click(variants[next].id));
  else if(['关闭弹窗','按钮 · 取消','按钮 · 完成'].includes(label))await n.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'CLOSE'}]}]);
 }
 await variants['导入中'].setReactionsAsync(r7Timer(variants['订阅成功'].id));
 r6Overlay(mobile,'Import profile',variants['订阅']);
 const info=r7Body('弹窗 / '+platform+' / 全部订阅信息',w);fill(info,'Surface');stroke(info);rad(info,24);info.paddingLeft=info.paddingRight=24;info.paddingTop=info.paddingBottom=24;info.itemSpacing=16;
 add(info,r6Text('订阅信息',22,'Text','Medium'),r6Text('套餐信息由订阅服务返回',12,'Muted','Regular',w-48));
 for(const group of ['主订阅','备用订阅','旅行订阅']){const d=R6_INFO[group],card=borderCard('订阅套餐 · '+group,w-48,null,16,8,'Raised');rad(card,12);add(card,between(add(row('订阅名称与状态',w-80,24),r6Text(group,15,'Text','Medium'),r6Badge(d.status,d.tone==='Primary'?'Success':d.tone==='Warning'?'Warning':'Neutral'))),r6Text(d.used?d.used+' / '+d.total+' GB · 剩余 '+d.remaining+' GB':'流量未提供',13,'Secondary','Regular',w-80),r6Text(d.expires?d.expires+' 到期':'到期时间未提供',12,'Muted','Regular',w-80));if(d.used)add(card,r6Text('↑ '+d.up+'　↓ '+d.down+' · '+d.updated+' 更新',11,'Muted','Regular',w-80));add(info,card);}add(info,r6Button('完成','Primary',null,w-48));
 for(const n of info.findAll(n=>r5Name(n)==='按钮 · 完成'))await n.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'CLOSE'}]}]);r6Overlay(mobile,'Subscription info · 主订阅',info);
 const moves={};for(const state of ['选择分组','主订阅','备用订阅']){const moved=state!=='选择分组',c=r7Body('状态='+state,w);fill(c,'Surface');stroke(c);rad(c,24);c.paddingLeft=c.paddingRight=24;c.paddingTop=c.paddingBottom=24;c.itemSpacing=16;add(c,r6Text(moved?'已移入'+state:'移动到分组',22,'Text','Medium'),r6Text(moved?'办公 HTTP 已归组；之后不再显示移动入口。':'仅未分组节点可以移动',13,'Muted','Regular',w-48));if(!moved)for(const name of ['主订阅','备用订阅'])add(c,r6Button(name,'Secondary','folder',w-48));add(c,r6Button(moved?'完成':'取消','Primary',null,w-48));moves[state]=c;}
 r7VariantSet('交互 / '+platform+' / 移动节点',Object.values(moves),3);for(const n of moves['选择分组'].findAll(n=>'setReactionsAsync'in n))if(['按钮 · 主订阅','按钮 · 备用订阅'].includes(r5Name(n)))await n.setReactionsAsync(r7Click(moves[r5Name(n).slice(5)].id));for(const c of Object.values(moves))for(const n of c.findAll(n=>['按钮 · 完成','按钮 · 取消'].includes(r5Name(n))))await n.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'CLOSE'}]}]);r6Overlay(mobile,'Move group',moves['选择分组']);
 for(const key of ['Import profile','Subscription info · 主订阅','Move group']){const scrim=uFind(reg[key],'关闭弹窗遮罩');await scrim.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'CLOSE'}]}]);r7Changes.push(reg[key].id);}return variants['订阅'].parent.id;
}
async function r7Chains(mobile){
 const reg=mobile?registry.mobile:registry.desktop,w=mobile?353:1120,keys=['Chain editor','Chain reordered','Chain tested','Chain reverse tested','Chain empty'],variants={};
 for(const key of keys){const c=r7Body('状态='+key.replace('Chain ','').replace('editor','默认').replace('reordered','调整顺序').replace('tested','测试通过').replace('empty','缺少出口'),w);r7CloneBody(reg[key],c);if(mobile){const footer=uFind(reg[key],'Fixed chain actions');if(footer)add(c,footer.children[0].clone());}variants[key]=c;}
 r7VariantSet('交互 / '+(mobile?'移动端':'桌面端')+' / 代理链编排',Object.values(variants),mobile?3:2);
 for(const [key,c]of Object.entries(variants))for(const n of c.findAll(n=>'setReactionsAsync'in n&&n.reactions.length)){const rr=JSON.parse(JSON.stringify(n.reactions));let changed=false;for(const r of rr)for(const a of r.actions||[])if(a.type==='NODE'&&a.navigation==='NAVIGATE'){const target=Object.keys(reg).find(k=>reg[k].id===a.destinationId),next=variants[target]||(target==='Chain picker'?variants['Chain editor']:null);if(next){a.destinationId=next.id;a.navigation='CHANGE_TO';changed=true;}}if(changed){for(const r of rr)r.actions=(r.actions||[]).filter(a=>!(a.type==='NODE'&&a.navigation==='CHANGE_TO'&&a.destinationId===c.id));try{await n.setReactionsAsync(rr.filter(r=>r.actions.length));}catch(e){throw new Error('链路组件 '+key+' / '+n.name+' → '+JSON.stringify(rr)+': '+String(e));}}}
 const screen=reg['Chain editor'],b=uFind(screen,'Content');for(const n of [...b.children])if(r5Name(n)!=='Page header')n.remove();add(b,r7Instance(variants['Chain editor'],'代理链交互编排'));const footer=uFind(screen,'Fixed chain actions');if(footer)footer.remove();r7Changes.push(screen.id);return variants['Chain editor'].parent.id;
}
function r7Section(page,name,nodes,columns,y){const section=figma.createSection();page.appendChild(section);r6Name(section,name);section.setPluginData('rainlink-compact-section','7.0');section.x=0;section.y=y;section.fills=[{type:'SOLID',color:{r:.075,g:.08,b:.087}}];const w=Math.max(...nodes.map(n=>n.width)),h=Math.max(...nodes.map(n=>n.height));nodes.forEach((n,i)=>{section.appendChild(n);n.x=48+(i%columns)*(w+80);n.y=80+Math.floor(i/columns)*(h+100);});section.resizeWithoutConstraints(96+columns*(w+80)-80,128+Math.ceil(nodes.length/columns)*(h+100)-100);return section;}
function r7Arrange(){for(const [reg,page,main]of [[registry.desktop,desktopPage,R7_MAIN_D],[registry.mobile,mobilePage,R7_MAIN_M]]){const one=r7Section(page,'01 · 主要画面 · 4 × 2',main.map(k=>reg[k]),4,0);const support=Object.keys(reg).filter(k=>!main.includes(k));r7Section(page,'02 · 必要弹窗与代理链',support.map(k=>reg[k]),4,one.height+200);for(const n of page.children)if(n.type==='TEXT')n.visible=false;}}
async function r7Remap(old){
 const kept=new Set([...Object.values(registry.desktop),...Object.values(registry.mobile)].map(n=>n.id));
 const maps={};for(const [platform,reg]of [['desktop',registry.desktop],['mobile',registry.mobile]])for(const [key,id]of Object.entries(old[platform])){
  let target=key;if(!reg[key])target=/Import|Manual node|QR import/.test(key)?'Import profile':key.startsWith('Subscription info')?'Subscription info · 主订阅':/Move group|New group/.test(key)?'Move group':/Chain/.test(key)?'Chain editor':/选择分组|Source success|Manual success|Import success|Moved$|Groups custom|Quick switch/.test(key)?'Profiles':/Nodes|group|grouped|选择节点|added nodes|Moved backup|Moved nodes/.test(key)?'Nodes':/Rule editor/.test(key)?'Rules':/Profile editor|Appearance/.test(key)?'Settings':platform==='mobile'?'Home':'Dashboard';
  maps[id]={id:reg[target].id,key:target};
 }
 let rewritten=0;for(const root of [...Object.values(registry.desktop),...Object.values(registry.mobile),dsPage])for(const node of root.findAll(n=>'setReactionsAsync'in n&&n.reactions.length)){
  const rr=JSON.parse(JSON.stringify(node.reactions));let changed=false;
  if(root===dsPage){let changed=false;for(const r of rr){const before=(r.actions||[]).length;r.actions=(r.actions||[]).filter(a=>!(a.type==='NODE'&&a.navigation!=='CHANGE_TO'&&maps[a.destinationId]));if(r.actions.length!==before)changed=true;}if(changed)await node.setReactionsAsync(rr.filter(r=>r.actions.length));continue;}
  for(const r of rr)for(const a of r.actions||[])if(a.type==='NODE'&&a.destinationId&&maps[a.destinationId]&&a.navigation!=='CHANGE_TO'){
   const dest=maps[a.destinationId];if(a.destinationId!==dest.id){a.destinationId=dest.id;changed=true;}
   if(['Import profile','Subscription info · 主订阅','Move group'].includes(dest.key)&&a.navigation!=='OVERLAY'){a.navigation='OVERLAY';changed=true;}
  }
  if(changed){for(const r of rr)r.actions=(r.actions||[]).filter(a=>!(a.type==='NODE'&&a.navigation==='NAVIGATE'&&a.destinationId===root.id));try{await node.setReactionsAsync(rr.filter(r=>r.actions.length));}catch(e){throw new Error('精简路由 '+root.name+' / '+node.name+' → '+JSON.stringify(rr)+': '+String(e));}rewritten++;}
 }
 return {rewritten,kept:[...kept]};
}
async function r7WireScreens(){
 const valid=new Set([...Object.values(registry.desktop),...Object.values(registry.mobile)].map(n=>n.id));
 for(const link of uLinks){if(!link.node||link.node.removed)continue;let root=link.node;while(root.parent&&root.parent.type!=='PAGE')root=root.parent;if(!valid.has(root.id))continue;const [p,...k]=link.target.split('/'),reg=p==='M'?registry.mobile:registry.desktop,key=k.join('/');const dest=reg[key]||(/Chain/.test(key)?reg['Chain editor']:/Import|Manual/.test(key)?reg['Import profile']:/Nodes|group/.test(key)?reg.Nodes:reg.Profiles);if(dest.id===root.id)continue;await link.node.setReactionsAsync(r7Click(dest.id,['Import profile','Move group','Subscription info · 主订阅'].includes(key)?'OVERLAY':'NAVIGATE'));}
 for(const reg of [registry.desktop,registry.mobile])for(const screen of Object.values(reg))for(const n of screen.findAll(n=>'setReactionsAsync'in n)){
  const name=r5Name(n);let key;
  if(name==='未分组节点移动'&&n.visible)key='Move group';else if(name==='查看订阅信息'&&n.visible)key='Subscription info · 主订阅';
  else if(n.type==='INSTANCE'&&!n.reactions.some(r=>(r.actions||[]).some(a=>a.navigation==='CHANGE_TO'))){const texts=n.findAll(t=>t.type==='TEXT').map(t=>t.characters);if(texts.length===1){const label=texts[0];if(label==='节点')key='Nodes';else if(['选择分组','切换分组','管理分组','全部分组','返回分组'].includes(label))key='Profiles';else if(['代理链','编排代理链'].includes(label))key='Chain editor';else if(label==='返回节点')key='Nodes';else if(label==='添加')key='Import profile';else if(label==='保存并选中')key=reg===registry.mobile?'Home':'Dashboard';}}
  if(key&&reg[key].id!==screen.id)await n.setReactionsAsync(r7Click(reg[key].id,['Import profile','Move group','Subscription info · 主订阅'].includes(key)?'OVERLAY':'NAVIGATE'));
 }
}
async function r7CompactMain(){
 figma.showUI('<body style="padding:24px;background:#151617;color:#c0c2c8;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#8adcbf">RainLink / 精简画布</h2><p id="s">将整页状态合并为组件交互…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:480,height:170});
 await r5Yield();await r5Initialize();figma.skipInvisibleInstanceChildren=false;Object.assign(C,R5_COLORS);
 if(figma.root.getPluginData('rainlink-compact-version')==='7.0'){await r7FinishMain();return;}
 for(const n of [...dsPage.children])if(n.type==='COMPONENT_SET'&&n.children.some(c=>c.getPluginData('rainlink-compact-component')==='7.0'))n.remove();
 const collections=await figma.variables.getLocalVariableCollectionsAsync();collection=collections.find(c=>/Colors \/ Dark|颜色 \/ 深色/.test(c.name));lightCollection=collections.find(c=>/Colors \/ Light|颜色 \/ 浅色/.test(c.name));darkMode=collection.defaultModeId;for(const variable of await figma.variables.getLocalVariablesAsync('COLOR')){const key=Object.keys(R5_TOKEN_NAMES).find(k=>variable.name===k||variable.name===R5_TOKEN_NAMES[k]);if(key)(variable.variableCollectionId===lightCollection.id?lightVars:vars)[key]=variable;}
 gInteractionCollection=collections.find(c=>c.name==='RainLink / 交互状态');for(const variable of await figma.variables.getLocalVariablesAsync())if(variable.variableCollectionId===gInteractionCollection.id)gVars[variable.name]=variable;
 const prior=JSON.parse(figma.root.getPluginData('rainlink-report')),old={desktop:{...prior.desktop},mobile:{...prior.mobile}},home={},selection={};
 await r6NetworkLibrary();
 for(const mobile of [false,true]){const platform=mobile?'mobile':'desktop';figma.ui.postMessage({status:'合并'+(mobile?'移动端':'桌面端')+'的选择、弹窗与连接状态…'});home[platform]=await r7Home(mobile);await r7Dialogs(mobile);selection[platform]={groups:await r7Groups(mobile),nodes:await r7Nodes(mobile),chains:await r7Chains(mobile)};}
 const removed=[];for(const [reg,main]of [[registry.desktop,R7_MAIN_D],[registry.mobile,R7_MAIN_M]]){const keep=new Set([...main,'Chain editor','Import profile','Subscription info · 主订阅','Move group']);for(const key of Object.keys(reg))if(!keep.has(key)){removed.push({key,id:reg[key].id,node:reg[key]});delete reg[key];}}
 figma.ui.postMessage({status:'重接精简后的原型并移除重复整页稿…'});const routes=await r7Remap(old);await r7WireScreens();for(const x of removed)x.node.remove();
 r7Arrange();const ys={desktop:8000,mobile:8000};for(const set of r7Sets){const mobile=set.name.includes('移动端'),platform=mobile?'mobile':'desktop';set.x=mobile?4400:0;set.y=ys[platform];ys[platform]+=set.height+180;}
 desktopPage.flowStartingPoints=[{nodeId:registry.desktop.Dashboard.id,name:'桌面端 / 主要交互'},{nodeId:registry.desktop.Profiles.id,name:'桌面端 / 添加与自动归组'}];mobilePage.flowStartingPoints=[{nodeId:registry.mobile.Home.id,name:'移动端 / 主要交互'},{nodeId:registry.mobile.Profiles.id,name:'移动端 / 添加与自动归组'}];
 const report=await r5AuditDocument();report.version='7.0';report.desktop=Object.fromEntries(Object.entries(registry.desktop).map(([k,n])=>[k,n.id]));report.mobile=Object.fromEntries(Object.entries(registry.mobile).map(([k,n])=>[k,n.id]));report.counts={desktop:Object.keys(registry.desktop).length,mobile:Object.keys(registry.mobile).length,components:dsPage.findAll(n=>n.type==='COMPONENT').length};
 report.compactCanvas={previousScreens:Object.keys(old.desktop).length+Object.keys(old.mobile).length,removedFullScreens:removed.length,mainDesktop:R7_MAIN_D,mainMobile:R7_MAIN_M,homeStates:home,selectionComponents:selection,rewrittenRoutes:routes.rewritten,statesAreComponentVariants:true,crossPageSelection:'Representative Figma interactions; local interactive state is not a runtime shared store'};
 report.subscriptionDialogs.changedScreenIds=r7Changes;report.subscriptionDialogs.overlayIds=[...Object.values(registry.desktop),...Object.values(registry.mobile)].filter(n=>n.getPluginData('rainlink-dialog')).map(n=>n.id);report.egress.powerTransitions=home;delete report.nativeBackup;delete report.screenshotVerification;report.livePrototypeVerification={status:'pending compact rescan'};
 for(const panel of dsPage.children.filter(n=>n.type==='FRAME'))for(const t of panel.findAll(n=>n.type==='TEXT')){if(/164|162|225|223|326|448|3810/.test(t.characters)&&!isTechnicalText(t.characters))r6Copy(t,t.characters.replace(/164|225/g,'12').replace(/162|223/g,'11').replace(/326|448/g,'23').replace(/3810/g,'组件交互'));}
 await r71ApplyHomeControls(report);await r72ApplyDensity(report);const controlsAudit=await r5AuditDocument();report.overflow=controlsAudit.overflow;report.untranslatedDisplayCopy=controlsAudit.untranslatedDisplayCopy;
 const audit=uFind(dsPage,'Delivery / Native audit');audit.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);audit.visible=false;figma.root.setPluginData('rainlink-report',JSON.stringify(report));figma.root.setPluginData('rainlink-compact-version','7.0');
 await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Dashboard];figma.viewport.scrollAndZoomIntoView(figma.currentPage.selection);figma.notify('已精简：桌面 8 个主页面，移动 8 个主要画面；移除 '+removed.length+' 个重复状态稿。');figma.closePlugin();
}
async function r7FinishMain(){
 figma.showUI('<body style="padding:24px;background:#151617;color:#c0c2c8;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#8adcbf">RainLink / 精简稿核验</h2><p id="s">保留现有画面，核验导航、中文与原型…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:480,height:170});
 await r5Initialize();figma.skipInvisibleInstanceChildren=false;
 // Repair controls created after localization, whose base text is still "按钮".
 for(const page of [desktopPage,mobilePage,dsPage])for(const n of page.findAll(n=>n.type==='INSTANCE'&&r5Name(n).startsWith('Button · '))){
  const label=r5Name(n).slice(9),text=uFind(n,'Label'),slot=uFind(n,'Icon slot');
  if(text){r6Copy(text,label);text.visible=!!label;}
  const symbol={'添加':'plus','全部分组':'folder','代理链':'link','返回概览':'grid'}[label];
  if(slot&&(symbol||!label)){slot.visible=true;if(symbol&&icons[symbol])slot.swapComponent(icons[symbol]);}
 }
 const groupHeader=uFind(registry.mobile.Profiles,'Page header'),nodeHeader=uFind(registry.mobile.Nodes,'Page header');
 for(const header of [groupHeader,nodeHeader]){
  const title=header.children.find(n=>n.type==='FRAME'),back=header.children.find(n=>n.type==='INSTANCE');
  if(back){back.primaryAxisSizingMode='FIXED';back.resize(40,44);}
  if(header===nodeHeader&&!header.children.some(n=>r5Name(n)==='按钮 · 添加节点')){
   const addNode=r6Button('','Ghost','plus',40);r6Name(addNode,'按钮 · 添加节点');add(header,addNode);await addNode.setReactionsAsync(r7Click(registry.mobile['Import profile'].id,'OVERLAY'));
  }
  const width=header===nodeHeader?249:301;if(title){title.resize(width,title.height);for(const t of title.findAll(n=>n.type==='TEXT')){t.resize(width,t.height);t.textAutoResize='HEIGHT';}}
 }
 for(const reg of [registry.desktop,registry.mobile])for(const screen of Object.values(reg))for(const n of screen.findAll(n=>n.type==='INSTANCE')){
  const name=r5Name(n),label=name.startsWith('Button · ')?name.slice(9):'',route={'添加':'Import profile','全部分组':'Profiles','代理链':'Chain editor','返回概览':reg===registry.mobile?'Home':'Dashboard'}[label];
  if(route&&reg[route].id!==screen.id)await n.setReactionsAsync(r7Click(reg[route].id,route==='Import profile'?'OVERLAY':'NAVIGATE'));
 }
 const report=JSON.parse(figma.root.getPluginData('rainlink-report')),names={Dashboard:'概览',Home:'首页',Nodes:'节点',Profiles:'分组',Rules:'规则',Connections:'连接',Traffic:'流量',Logs:'日志',Settings:'设置','Quick switch':'快速选择',DNS:'DNS 设置','Chain editor':'代理链编排','Import profile':'添加弹窗','Move group':'移动节点弹窗','Subscription info · 主订阅':'订阅信息弹窗'},nav={概览:'Dashboard',首页:'Home',节点:'Nodes',分组:'Profiles',规则:'Rules',连接:'Connections',流量:'Traffic',日志:'Logs',设置:'Settings'};
 for(const [reg,page,platform]of [[registry.desktop,desktopPage,'桌面端'],[registry.mobile,mobilePage,'移动端']]){
  for(const screen of Object.values(reg)){
   screen.name=platform+' / '+names[screen.getPluginData('rainlink').split('/').slice(1).join('/')];
   for(const t of screen.findAll(n=>n.type==='TEXT'&&n.characters==='Connected'))r6Copy(t,'已连接');
   const side=uFind(screen,'Primary navigation'),bottom=uFind(screen,'Mobile / Bottom navigation');
   for(const n of [...(side?.children||[]),...(bottom?.children||[])]){const label=n.findOne(t=>t.type==='TEXT'&&nav[t.characters]);if(label&&reg[nav[label.characters]])await n.setReactionsAsync(reg[nav[label.characters]].id===screen.id?[]:r7Click(reg[nav[label.characters]].id,'NAVIGATE'));}
   for(const n of screen.findAll(n=>'setReactionsAsync'in n)){
    if(r5Name(n)==='未分组节点移动')await n.setReactionsAsync(r7Click(reg['Move group'].id,'OVERLAY'));
    if(n.type==='INSTANCE'&&screen===reg.Home){const texts=n.findAll(t=>t.type==='TEXT');if(texts.length===1&&texts[0].characters==='选择')await n.setReactionsAsync(r7Click(reg['Quick switch'].id,'NAVIGATE'));}
   }
  }
  for(const n of [...page.children])if(n.type!=='SECTION')n.remove();
 }
 for(const set of dsPage.children.filter(n=>n.type==='COMPONENT_SET'&&r5Name(n).endsWith('节点选择'))){
  const groups={'主订阅':G_MAIN,'备用订阅':G_BACKUP,'未分组':G_LOOSE,'旅行订阅':G_MAIN.slice(0,4)};
  for(const c of set.children){const group=c.name.match(/^分组=([^,]+)/)?.[1];for(const row of c.children.filter(n=>r5Name(n).startsWith('选择节点 · '))){const data=groups[group]?.[Number(r5Name(row).slice(7))],tag=uFind(row,'节点协议');if(data&&tag)r6Copy(tag.findOne(n=>n.type==='TEXT'),data.p);}}
 }
 // Restore chain controls after maintenance reruns; no additional full screen is made.
 for(const set of dsPage.children.filter(n=>n.type==='COMPONENT_SET'&&r5Name(n).endsWith('代理链编排'))){
  const parts=set.children,normal=parts.find(c=>/默认/.test(c.name)),reorder=parts.find(c=>/调整顺序/.test(c.name)),tested=parts.find(c=>/测试通过/.test(c.name)&&!/reverse/.test(c.name)),reverse=parts.find(c=>/reverse/.test(c.name)),empty=parts.find(c=>/缺少出口/.test(c.name));
  for(const c of parts)for(const n of c.findAll(n=>n.type==='INSTANCE')){const texts=n.findAll(t=>t.type==='TEXT').map(t=>t.characters);if(texts.length!==1)continue;const label=texts[0],swapped=c===reorder||c===reverse;let next;if(['测试链路','测试整链'].includes(label))next=swapped?reverse:tested;else if(['上移','下移'].includes(label)&&n.opacity>.5)next=swapped?normal:reorder;else if(label==='移除')next=empty;else if(['更换节点','选择出口节点'].includes(label))next=normal;if(next&&next.id!==c.id)await n.setReactionsAsync(r7Click(next.id));else if(['保存并选中','保存代理链','选中代理链'].includes(label))await n.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'BACK'}]}]);}
 }
 await r71ApplyHomeControls(report);
 await r72ApplyDensity(report);
 const audit=await r5AuditDocument();report.overflow=audit.overflow;report.untranslatedDisplayCopy=audit.untranslatedDisplayCopy;report.compactCanvas.maintenanceCompleted=true;report.compactCanvas.controlLabelsRestored=true;report.counts.components=dsPage.findAll(n=>n.type==='COMPONENT').length;
 const text=uFind(dsPage,'Delivery / Native audit');text.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);text.visible=false;figma.root.setPluginData('rainlink-report',JSON.stringify(report));await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Dashboard];figma.viewport.scrollAndZoomIntoView(figma.currentPage.selection);figma.notify('精简完成 · 16 个主要画面 · 7 个必要弹窗与编排画面');figma.closePlugin();
}

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

// RainLink 7.5 — complete settings inside the existing product frames.
// Native component variants demonstrate UI states; no OS/network action is run.
const R75_UI='设置工作区';
const R75_REVISION='4';
let r75Section,r75ShelfX=32,r75ShelfY=104,r75ShelfH=0;
const r75Libraries={};
function r75Mark(n){n.setPluginData('rainlink-settings-version','7.5');return n;}
function r75Place(n){
  if(r75ShelfX+n.width>5000&&r75ShelfX>32){r75ShelfY+=r75ShelfH+64;r75ShelfX=32;r75ShelfH=0;}
  r75Section.appendChild(n);n.x=r75ShelfX;n.y=r75ShelfY;r75ShelfX+=n.width+48;r75ShelfH=Math.max(r75ShelfH,n.height);return n;
}
function r75Set(name,variants,columns=3){
  const set=r7VariantSet(name,Object.values(variants),columns);r75Mark(set);for(const c of Object.values(variants))r75Mark(c);if(Object.keys(variants).some(k=>k.endsWith(' · 展开')))r75ChoiceGeometry(set);r75Place(set);return {set,variants};
}
function r75ChoiceGeometry(set){
  const cs=set.children,cols=Math.min(3,cs.length),w=Math.max(...cs.map(c=>c.width)),h=Math.max(...cs.map(c=>Math.max(c.height,...c.children.map(n=>n.y+n.height))));
  cs.forEach((c,i)=>{c.x=24+(i%cols)*(w+32);c.y=24+Math.floor(i/cols)*(h+40);});
  set.resize(48+cols*(w+32)-32,48+Math.ceil(cs.length/cols)*(h+40)-40);set.clipsContent=false;
}
async function r75RefreshChoiceLayouts(ui,section){
  for(const lib of Object.values(ui.controls))if(Object.keys(lib.states).some(k=>k.endsWith(' · 展开')))r75ChoiceGeometry(await figma.getNodeByIdAsync(lib.set));
  r75Section=section;r75ShelfX=32;r75ShelfY=104;r75ShelfH=0;
  for(const n of [...section.children])if(r5Name(n)!=='设置组件库说明')r75Place(n);
  section.resizeWithoutConstraints(5032,r75ShelfY+r75ShelfH+32);ui.choiceMenus='Full dropdown bounds reserved in component library';
}
function r75Text(s,size=13,color='Text',weight='Regular',w=null){return r6Text(s,size,color,weight,w);}
function r75Body(name,w){const c=r7Body(name,w);r75Mark(c);c.itemSpacing=12;return c;}
function r75Copy(title,desc,w,size=14){return add(r6Name(v('设置文案',w,3),'设置文案'),r6Name(r75Text(title,size,'Text','Medium',w),'设置项标题'),desc?r6Name(r75Text(desc,11,'Muted','Regular',w),'设置项说明'):null);}
function r75Card(title,mobile){const w=mobile?353:912,p=mobile?16:20,n=r6Name(borderCard(title,w,null,p,0,'Surface'),title);return {n,w:w-p*2-2};}
function r75Heading(body,title,desc,mobile){add(body,r75Text(title,mobile?20:22,'Text','Medium',mobile?353:912),desc?r75Text(desc,12,'Muted','Regular',mobile?353:912):null);}
function r75Button(label,tone='Secondary',ic=null,w=null){const b=r6Button(label,tone,ic,w);return r75Mark(b);}
function r75BackMaster(){
  const c=component('Icon / 返回',n=>{n.resize(24,24);n.layoutMode='HORIZONTAL';n.primaryAxisSizingMode=n.counterAxisSizingMode='FIXED';const svg=figma.createNodeFromSvg('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#c0c2c8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m15 5-7 7 7 7"/></svg>');add(n,svg);});
  r6Name(c,'Icon / 返回');r75Place(r75Mark(c));icons['返回']=c;
}
function r75Route(n,view){n.setPluginData('rainlink-settings-route',view);return n;}
function r75Item(title,desc,w,right=null,mobile=false){
  const n=r6Name(row('设置项 · '+title,w,mobile?56:60,12),'设置项 · '+title),copy=r75Copy(title,desc,Math.max(80,w-(right?right.width:0)-12),mobile?13:14);
  add(n,copy,right);return n;
}
function r75Rows(card,rows){rows.forEach((r,i)=>{if(i)add(card.n,divider(card.w));add(card.n,r);});return card.n;}
function r75Note(title,desc,w,tone='Info'){const p=14,n=r6Name(borderCard(title,w,null,p,6,tone==='Success'?'PrimarySurface':tone+'Surface'),title);stroke(n,tone,.5);add(n,r75Text(title,12,tone,'Medium',w-p*2-2),r75Text(desc,11,'Secondary','Regular',w-p*2-2));return n;}

async function r75ToggleLibrary(mobile){
  const platform=mobile?'移动端':'桌面端',w=mobile?319:420,variants={};
  for(const on of [true,false]){
    const c=r75Body('状态='+(on?'开启':'关闭'),w);c.resize(w,56);c.primaryAxisSizingMode='FIXED';c.layoutMode='HORIZONTAL';c.counterAxisAlignItems='CENTER';c.itemSpacing=12;
    const copy=r75Copy('设置项目','简短说明',w-56,mobile?13:14);add(c,copy);copy.layoutSizingHorizontal='FILL';
    const hit=center(r6Name(row('设置开关命中区',44,44),'设置开关命中区'));add(hit,sw(on));add(c,hit);variants[on?'on':'off']=c;
  }
  const lib=r75Set('设置 / '+platform+' / 开关行',variants,2);
  for(const [key,c]of Object.entries(variants))await uFind(c,'设置开关命中区').setReactionsAsync(r7Click(variants[key==='on'?'off':'on'].id));
  r75Libraries['toggle'+mobile]=lib;return lib;
}
function r75Toggle(title,desc,w,mobile,on=false){
  const n=r7Instance(r75Libraries['toggle'+mobile].variants[on?'on':'off'],'设置项 · '+title);n.resize(w,56);
  r6Copy(uFind(n,'设置项标题'),title);r6Copy(uFind(n,'设置项说明'),desc);return n;
}
async function r75ChoiceLibrary(key,values,mobile){
  const name='设置 / '+(mobile?'移动端':'桌面端')+' / '+key,w=mobile?148:192,h=mobile?44:36,variants={};
  for(const value of values)for(const open of [false,true]){
    const state=value+(open?' · 展开':''),c=r75Body('选项='+state,w);c.resize(w,h);c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.itemSpacing=0;
    const face=rad(r6Name(row('选择器按钮',w,h,8,10,'Raised'),'选择器按钮'),8);stroke(face);const t=r6Name(r75Text(value,12,'Secondary'),'选择器值');add(face,t);t.layoutSizingHorizontal='FILL';add(face,icon('down',14,'Muted'));add(c,face);
    if(open){
      const menu=borderCard('选择器菜单',w,null,4,2,'Raised');r6Name(menu,'选择器菜单');add(c,menu);menu.layoutPositioning='ABSOLUTE';menu.x=0;menu.y=h+4;
      for(const item of values){const optionRow=between(r6Name(row('选项 · '+item,w-10,mobile?44:36,6,8,item===value?'PrimarySurface':null),'选项 · '+item));add(optionRow,r75Text(item,12,item===value?'Primary':'Secondary'),item===value?icon('check',14,'Primary'):null);rad(optionRow,6);add(menu,optionRow);}
    }
    variants[state]=c;
  }
  const lib=r75Set(name,variants,Math.min(3,Object.keys(variants).length));
  for(const value of values){
    const closed=variants[value],opened=variants[value+' · 展开'];
    await uFind(closed,'选择器按钮').setReactionsAsync(r7Click(opened.id));
    await uFind(opened,'选择器按钮').setReactionsAsync(r7Click(closed.id));
    for(const item of values)await uFind(opened,'选项 · '+item).setReactionsAsync(r7Click(variants[item].id));
  }
  lib.defaultValue=values[0];
  r75Libraries[key+mobile]=lib;return lib;
}
function r75Choice(key,mobile,value=null){const lib=r75Libraries[key+mobile];return r7Instance(lib.variants[value||lib.defaultValue],'设置选择器 · '+key);}
async function r75ThemeLibrary(mobile){
  const w=mobile?319:870,variants={},options=['跟随系统','深色','浅色'];
  for(const selected of options){
    const c=r75Body('主题='+selected,w),tiles=row('主题选项',w,112,8);add(c,tiles);
    for(const option of options){
      const tw=(w-16)/3,card=borderCard('主题 · '+option,tw,112,8,8,selected===option?'PrimarySurface':'Raised');stroke(card,selected===option?'Primary':'Stroke');r6Name(card,'主题 · '+option);
      const dark=option!=='浅色',preview=rad(row('主题预览',tw-18,54,4,6,dark?'Background':'#FAFAFA'),5),side=rad(v('预览侧栏',Math.max(12,tw*.18),3,3,dark?'Raised':'#E4E4E7'),3),lines=v('预览内容',tw*.53,4);
      side.resize(Math.max(12,tw*.18),40);side.primaryAxisSizingMode='FIXED';
      add(lines,rad(row('预览标题',tw*.42,5,0,0,dark?'Secondary':'#55585F'),2),rad(row('预览条目',tw*.5,12,0,0,dark?'PrimarySurface':'#E7F5EE'),3),rad(row('预览辅助',tw*.4,5,0,0,dark?'Stroke':'#E4E4E7'),2));add(preview,side,lines);
      const bottom=between(row('主题标签',tw-18,24,4));add(bottom,r75Text(option,12,selected===option?'Primary':'Secondary'),selected===option?icon('check',14,'Primary'):null);add(card,preview,bottom);add(tiles,card);
    }
    add(c,r75Text('当前：'+selected+(selected==='跟随系统'?' · 随系统切换外观':''),11,'Muted'));variants[selected]=c;
  }
  const lib=r75Set('设置 / '+(mobile?'移动端':'桌面端')+' / 主题',variants,3);
  for(const [value,c]of Object.entries(variants))for(const option of options)if(option!==value)await uFind(c,'主题 · '+option).setReactionsAsync(r7Click(variants[option].id));
  r75Libraries['theme'+mobile]=lib;return lib;
}
async function r75DNSLibrary(mobile){
  const outer=mobile?353:912,pad=mobile?16:20,w=outer-pad*2-2,variants={},states=['加密 DNS','系统 DNS','自定义 DNS','测试中','测试通过','已保存','地址错误'];
  for(const state of states){
    const c=r75Body('状态='+state,outer);c.paddingLeft=c.paddingRight=pad;c.paddingTop=c.paddingBottom=pad;fill(c,'Surface');stroke(c);rad(c,12);c.itemSpacing=12;
    const mode=state==='系统 DNS'?state:state==='自定义 DNS'?state:'加密 DNS',tabs=row('DNS 模式选项',w,mobile?44:36,4);
    for(const name of ['加密 DNS','系统 DNS','自定义 DNS']){const t=center(rad(r6Name(row('DNS 模式 · '+name,(w-8)/3,mobile?44:36,0,0,name===mode?'PrimarySurface':'Raised'),'DNS 模式 · '+name),7));add(t,r75Text(name,12,name===mode?'Primary':'Secondary'));add(tabs,t);}add(c,tabs);
    if(state==='系统 DNS')add(c,r75Note('使用系统解析器','使用设备当前网络提供的 DNS，切换网络时自动更新。',w));
    else{
      const fields=mobile?v('DNS 解析器',w,12):row('DNS 解析器',w,null,16);
      const fw=mobile?w:(w-16)/2,first=r6Field('首选解析器',state==='地址错误'?'http://':state==='自定义 DNS'?'tls://1.1.1.1':'https://dns.google/dns-query',fw),second=r6Field('备用解析器','https://cloudflare-dns.com/dns-query',fw);
      for(const f of [first,second]){const input=uFind(f,'Input / Default');if(input){input.resize(fw,44);const text=uFind(input,'Value');if(text)text.fontSize=mobile?11:12;}}
      if(state==='地址错误'){const input=first.findOne(n=>n.type==='INSTANCE');stroke(input,'Error');add(first,r75Text('请输入完整的解析器地址',11,'Error','Regular',fw));}
      add(fields,first,second);add(c,fields,r75Text(state==='自定义 DNS'?'支持 HTTPS、TLS 或 IP 地址。':'通过 HTTPS 加密解析请求。',11,'Muted','Regular',w));
    }
    const actions=between(row('DNS 操作',w,44,8));add(actions,r6Name(r75Button(state==='测试中'?'测试中…':'测试解析','Secondary','globe',mobile?120:124),'测试 DNS'),r6Name(r75Button('保存设置','Primary',null,mobile?147:124),'保存 DNS'));add(c,actions);
    if(state==='地址错误')for(const action of actions.children)action.opacity=.4;
    if(['测试中','测试通过','已保存','地址错误'].includes(state))add(c,r75Note(state==='测试中'?'正在解析 example.com':state==='测试通过'?'解析成功 · 28 ms':state==='已保存'?'DNS 设置已保存':'解析器地址不完整',state==='测试中'?'请稍候…':state==='测试通过'?'首选解析器可用，备用解析器待命。':state==='已保存'?'新建连接将使用当前设置。':'补全地址后再保存。',w,state==='地址错误'?'Error':state==='测试中'?'Info':'Success'));
    variants[state]=c;
  }
  const lib=r75Set('设置 / '+(mobile?'移动端':'桌面端')+' / DNS 解析',variants,mobile?3:2);
  for(const [state,c]of Object.entries(variants)){
    for(const mode of ['加密 DNS','系统 DNS','自定义 DNS'])if(mode!==state)await uFind(c,'DNS 模式 · '+mode).setReactionsAsync(r7Click(variants[mode].id));
    if(!['测试中','地址错误'].includes(state))await uFind(c,'测试 DNS').setReactionsAsync(r7Click(variants['测试中'].id));
    if(!['已保存','地址错误'].includes(state))await uFind(c,'保存 DNS').setReactionsAsync(r7Click(variants['已保存'].id));
    if(state==='测试中')await c.setReactionsAsync(r7Timer(variants['测试通过'].id));
  }
  r75Libraries['dns'+mobile]=lib;return lib;
}
async function r75EngineLibrary(mobile){
  const outer=mobile?353:912,variants={};
  for(const state of ['运行中','确认重启','重启中','已重启']){
    const {n:c,w}=r75Card('核心状态',mobile),master=r75Body('状态='+state,outer);for(const child of [...c.children])child.remove();
    const title=between(row('引擎身份',w,48,12));add(title,add(row('引擎名称',null,48,12),miniIcon('terminal','Primary',40,'PrimarySurface'),r75Copy('sing-box','核心版本 1.12.0',mobile?144:360)),r6Badge(state==='重启中'?'重启中':'运行中',state==='重启中'?'Warning':'Success'));add(c,title,space(14));
    if(state==='确认重启')add(c,r75Note('重新启动核心引擎？','当前连接会短暂中断，完成后恢复。',w,'Warning'),space(12),add(row('重启确认操作',w,44,8),r6Name(r75Button('取消','Secondary',null,mobile?100:120),'取消重启'),r6Name(r75Button('确认重启','Primary','refresh',mobile?180:140),'确认重启')));
    else{
      const bar=between(row('引擎操作',w,44,8));add(bar,r75Text(state==='已重启'?'重启完成，配置已重新载入。':state==='重启中'?'正在重新载入配置…':'独立管理核心与日志。',11,state==='已重启'?'Primary':'Muted','Regular',mobile?170:520),r6Name(r75Button(state==='重启中'?'重启中…':'重启核心','Secondary','refresh',mobile?124:128),'重启核心'));add(c,bar);
    }
    add(master,c);variants[state]=master;
  }
  const lib=r75Set('设置 / '+(mobile?'移动端':'桌面端')+' / 核心状态',variants,2);
  for(const state of ['运行中','已重启'])await uFind(variants[state],'重启核心').setReactionsAsync(r7Click(variants['确认重启'].id));
  await uFind(variants['确认重启'],'取消重启').setReactionsAsync(r7Click(variants['运行中'].id));await uFind(variants['确认重启'],'确认重启').setReactionsAsync(r7Click(variants['重启中'].id));await variants['重启中'].setReactionsAsync(r7Timer(variants['已重启'].id));
  r75Libraries['engine'+mobile]=lib;return lib;
}
async function r75UpdateLibrary(mobile){
  const outer=mobile?353:912,variants={},states=mobile?['待检查','检查中','已是最新','发现更新','商店更新','检查失败']:['待检查','检查中','已是最新','发现更新','下载中','等待重启','确认更新','更新完成','检查失败'];
  for(const state of states){
    const card=r75Card('应用更新',mobile),c=r75Body('状态='+state,outer),available=['发现更新','下载中','等待重启'].includes(state);
    add(card.n,between(add(row('应用版本',card.w,52,12),add(row('版本标识',null,52,12),instance('Brand / Mark'),r75Copy('RainLink '+(['已是最新','更新完成'].includes(state)?'1.1.0':'1.0.0'),'当前版本 · 稳定版',mobile?174:450)),!mobile?r6Badge(available?'发现更新':state==='检查中'?'检查中':'当前版本',available?'Success':'Neutral'):null)),space(16));
    add(card.n,r75Text(state==='待检查'?'随时获取新功能与修复。':state==='检查中'?'正在检查更新…':state==='已是最新'?'当前已是最新版本':state==='检查失败'?'暂时无法检查更新':state==='等待重启'?'更新已准备就绪':state==='商店更新'?'在 App Store 中完成更新':state==='确认更新'?'重启 RainLink 并更新？':state==='更新完成'?'更新完成':'RainLink 1.1.0 可用',mobile?14:18,state==='检查失败'?'Error':'Text','Medium',card.w),space(8));
    if(available)add(card.n,r75Text('改进节点筛选、连接稳定性与使用体验。',12,'Muted','Regular',card.w),space(12));
    if(state==='检查失败')add(card.n,r75Text('检查网络连接后重试。',12,'Muted','Regular',card.w),space(12));
    if(state==='下载中'){const track=rad(row('下载进度',card.w,4,0,0,'Stroke'),2);add(track,rad(row('已下载',card.w*.64,4,0,0,'Primary'),2));add(card.n,track,space(12),r75Text('正在下载 · 64%',11,'Primary'),space(12));}
    if(state==='商店更新')add(card.n,r75Text('打开 App Store，进入账户页查看可用更新。',12,'Secondary','Regular',card.w),space(12));
    if(state==='确认更新')add(card.n,r75Note('当前连接会短暂中断','重启完成后恢复上次选择的连接。',card.w,'Warning'),space(12));
    const label=state==='检查中'?'检查中…':state==='发现更新'?(mobile?'前往 App Store':'下载更新'):state==='下载中'?'正在下载…':state==='等待重启'?'重启并更新':state==='确认更新'?'确认重启':state==='商店更新'?'知道了':state==='更新完成'?'完成':state==='检查失败'?'重试':'检查更新';
    const b=r6Name(r75Button(label,available?'Primary':'Secondary',state==='发现更新'?'download':'refresh',mobile?card.w:156),'更新操作');add(card.n,b);
    if(mobile&&state==='发现更新')add(card.n,space(8),r75Text('通过 App Store 完成更新。',11,'Muted','Regular',card.w));
    if(state==='等待重启')add(card.n,space(8),r75Text('重启会短暂中断当前连接。',11,'Muted','Regular',card.w));
    if(state==='确认更新')add(card.n,space(8),r6Name(r75Button('暂不重启','Ghost',null,mobile?card.w:156),'取消更新重启'));
    add(card.n,space(12),r75Text(state==='待检查'?'上次检查：尚未检查':'上次检查：刚刚',11,'Muted','Regular',card.w));
    add(c,card.n);variants[state]=c;
  }
  const lib=r75Set('设置 / '+(mobile?'移动端':'桌面端')+' / 应用更新',variants,2);
  for(const state of ['待检查','已是最新','检查失败'])await uFind(variants[state],'更新操作').setReactionsAsync(r7Click(variants['检查中'].id));
  await variants['检查中'].setReactionsAsync(r7Timer(variants['发现更新'].id));
  if(!mobile){await uFind(variants['发现更新'],'更新操作').setReactionsAsync(r7Click(variants['下载中'].id));await variants['下载中'].setReactionsAsync(r7Timer(variants['等待重启'].id));await uFind(variants['等待重启'],'更新操作').setReactionsAsync(r7Click(variants['确认更新'].id));await uFind(variants['确认更新'],'更新操作').setReactionsAsync(r7Click(variants['更新完成'].id));await uFind(variants['确认更新'],'取消更新重启').setReactionsAsync(r7Click(variants['等待重启'].id));await uFind(variants['更新完成'],'更新操作').setReactionsAsync(r7Click(variants['已是最新'].id));}
  else{await uFind(variants['发现更新'],'更新操作').setReactionsAsync(r7Click(variants['商店更新'].id));await uFind(variants['商店更新'],'更新操作').setReactionsAsync(r7Click(variants['待检查'].id));}
  r75Libraries['updates'+mobile]=lib;return lib;
}
function r75LinkRow(title,desc,view,w,mobile){const control=center(row('打开设置详情',mobile?28:36,44));add(control,icon('chevron',16,'Muted'));return r75Route(r75Item(title,desc,w,control,mobile),view);}
function r75PageIntro(c,title,desc,mobile){if(mobile)add(c,r76DetailHeader(title,desc,true,'首页'));else r75Heading(c,title,desc,false);}
function r75General(c,mobile){
  r75PageIntro(c,'通用','管理启动、窗口与通知偏好。',mobile);const a=r75Card('启动与行为',mobile);
  add(c,r75Rows(a,[r75Toggle('开机启动','系统启动后运行 RainLink',a.w,mobile,true),r75Toggle('启动时自动连接','恢复上次选择的分组与节点',a.w,mobile,false),r75Item('关闭窗口时','选择主窗口关闭后的行为',a.w,r75Choice('关闭行为',mobile),mobile)]));
  const b=r75Card('通知与语言',mobile);add(c,r75Rows(b,[r75Toggle('连接状态通知','连接变化与订阅到期时提醒',b.w,mobile,true),r75Toggle('显示托盘或菜单栏图标','从系统栏快速访问 RainLink',b.w,mobile,true),r75Item('界面语言','默认使用简体中文',b.w,r75Choice('语言',mobile),mobile)]));
}
function r75Appearance(c,mobile){
  r75PageIntro(c,'外观与语言','选择适合你的界面风格。',mobile);const a=r75Card('主题设置',mobile);add(a.n,r75Text('主题',13,'Secondary','Medium'),space(12),r7Instance(r75Libraries['theme'+mobile].variants['深色'],'主题选择'));add(c,a.n);
  const b=r75Card('显示偏好',mobile),rows=[r75Item('界面密度','调整列表和控件的留白',b.w,r75Choice('密度',mobile),mobile),r75Item('文字大小',null,b.w,r75Choice('文字',mobile),mobile),r75Toggle('减少动效','简化界面过渡动画',b.w,mobile,false)];
  if(mobile)rows.push(r75Item('界面语言',null,b.w,r75Choice('语言',mobile),mobile));add(c,r75Rows(b,rows));
}
function r75Network(c,mobile){
  r75PageIntro(c,'网络','管理解析方式与连接选项。',mobile);
  if(mobile){const a=r75Card('解析与连接',true);add(c,r75Rows(a,[r75LinkRow('DNS 解析','加密 DNS · 自动选择备用解析器','@DNS',a.w,true),r75Toggle('IPv6','允许通过 IPv6 建立连接',a.w,true,true),r75Toggle('DNS 缓存','复用近期解析结果',a.w,true,true)]));const b=r75Card('本地监听',true);add(c,r75Rows(b,[r75Item('混合端口','HTTP / SOCKS5',b.w,r75Choice('端口',true),true),r75Toggle('允许局域网连接','让同一网络设备使用本地代理',b.w,true,false)]));}
  else{add(c,r7Instance(r75Libraries['dnsfalse'].variants['加密 DNS'],'DNS 设置'));const a=r75Card('连接选项',false);add(c,r75Rows(a,[r75Toggle('IPv6','允许通过 IPv6 建立连接',a.w,false,true),r75Item('混合端口','HTTP / SOCKS5 本地监听',a.w,r75Choice('端口',false),false),r75Toggle('允许局域网连接','让同一网络设备使用本地代理',a.w,false,false)]));}
}
function r75Core(c,mobile){
  r75PageIntro(c,'核心引擎','查看引擎状态与高级选项。',mobile);add(c,r7Instance(r75Libraries['engine'+mobile].variants['运行中'],'核心重启交互'));
  const a=r75Card('引擎偏好',mobile);add(c,r75Rows(a,[r75Item('日志级别','调整事件记录的详细程度',a.w,r75Choice('日志',mobile),mobile),r75LinkRow('高级配置','查看与编辑 YAML / JSON','高级配置',a.w,mobile)]));
  add(c,r75Note('配置变更需要确认应用','保留当前可用配置，校验通过后再重新载入。',mobile?353:912));
}
function r75Updates(c,mobile){
  r75PageIntro(c,'更新','管理应用版本与更新渠道。',mobile);add(c,r7Instance(r75Libraries['updates'+mobile].variants['待检查'],'应用更新交互'));
  const a=r75Card('更新偏好',mobile);add(c,r75Rows(a,[r75Toggle('自动检查更新','发现新版本时通知',a.w,mobile,true),r75Item('更新渠道',mobile?'安装渠道管理更新':'选择接收版本的范围',a.w,mobile?r75Text('App Store',12,'Secondary'):r75Choice('渠道',false),mobile)]));
}
function r75About(c,mobile){
  r75PageIntro(c,'关于 RainLink','跨平台多协议网络客户端。',mobile);const a=r75Card('产品信息',mobile),brand=row('关于品牌',a.w,64,12);add(brand,instance('Brand / Mark'),r75Copy('RainLink','版本 1.0.0 · 稳定版',a.w-56,18));add(a.n,brand,space(12),divider(a.w),r75Item('核心版本',null,a.w,r75Text('sing-box 1.12.0',12,'Secondary'),mobile),divider(a.w),r75Item('界面语言',null,a.w,r75Text('简体中文',12,'Primary'),mobile));add(c,a.n);
  const b=r75Card('说明与许可',mobile);add(c,r75Rows(b,[r75LinkRow('隐私说明','了解本地数据与网络请求','隐私说明',b.w,mobile),r75LinkRow('第三方开源许可','查看使用的开源组件','开源许可',b.w,mobile)]));
}
function r75LegalHeader(mobile,privacy){
  const w=mobile?353:912,header=r6Name(row('关于详情导航',w,52,4),'关于详情导航');
  const back=r75Route(r76BackIcon(r75Button('','Ghost','返回',44),'返回关于箭头'),'关于');
  add(header,back,r75Copy(privacy?'隐私说明':'第三方开源许可',privacy?'清晰了解数据的使用方式。':'感谢开源社区。',w-48,mobile?20:22));return header;
}
function r75Legal(c,mobile,privacy){
  add(c,r75LegalHeader(mobile,privacy));const a=r75Card(privacy?'数据说明':'依赖与许可',mobile);
  const items=privacy?[['本地保存','节点、订阅地址与个人偏好保存在本机。'],['必要的网络请求','订阅更新、DNS 解析与公网出口检测会访问相应服务。'],['诊断日志','导出前可查看内容并移除敏感信息。']]:[['sing-box','网络核心 · GPL-3.0-or-later'],['第三方依赖','各组件保留原作者与许可信息。'],['许可声明','开源组件各自保留版权声明与许可条款。']];
  for(const [i,[title,desc]]of items.entries()){if(i)add(a.n,space(16),divider(a.w),space(16));add(a.n,r75Text(title,14,'Text','Medium',a.w),space(6),r75Text(desc,12,'Secondary','Regular',a.w));}add(c,a.n);
}
async function r75RefreshLegalBack(ui){
  for(const [platform,mobile]of [['desktop',false],['mobile',true]])for(const name of ['隐私说明','开源许可']){
    const c=await figma.getNodeByIdAsync(ui[platform].variants[name]),body=mobile?c:uFind(c,'设置详情');
    let header=uFind(body,'关于详情导航');
    if(!header){const card=body.children.find(n=>r5Name(n)===(name==='隐私说明'?'数据说明':'依赖与许可'));if(!card)throw new Error(platform+' '+name+' 详情卡缺失');for(const n of [...body.children])if(n!==card)n.remove();header=r75LegalHeader(mobile,name==='隐私说明');body.insertChild(0,header);}
    header.resize(mobile?353:912,52);header.itemSpacing=4;const back=r76BackIcon(uFind(header,'返回关于箭头'),'返回关于箭头');await back.setReactionsAsync(r7Click(ui[platform].variants['关于']));
  }
  ui.legalBackNavigation='top-left-arrow';
}
function r75Advanced(c,mobile,state='YAML'){
  add(c,r76DetailHeader('高级配置','校验后应用，出错时保留当前配置。',mobile,'核心引擎'));const a=r75Card('配置编辑器',mobile),format=state==='JSON'?'JSON':'YAML';
  const tabs=row('配置格式',a.w,44,8);for(const name of ['YAML','JSON']){const b=r75Route(r75Button(name,format===name?'Primary':'Secondary',null,84),'配置'+name);add(tabs,b);}add(a.n,tabs,space(12));
  const code=state==='错误'?'dns:\n  servers: [':format==='JSON'?'{\n  "log": { "level": "info" },\n  "dns": {\n    "servers": [\n      { "type": "https",\n        "server": "dns.google" }\n    ]\n  }\n}':'# RainLink 高级配置\nlog:\n  level: info\ndns:\n  servers:\n    - type: https\n      server: dns.google';
  const editor=borderCard('可编辑代码',a.w,mobile?224:256,14,0,'Background');stroke(editor,state==='错误'?'Error':'Stroke');const t=r75Text(code,mobile?11:13,'Secondary','Regular',a.w-30);t.fontName={family:'Roboto Mono',style:'Regular'};if(/[\u3400-\u9fff]/.test(code))t.fontName={family:zhFamily,style:zhStyles.Regular};add(editor,t);add(a.n,editor,space(12));
  if(['已校验','已应用','错误'].includes(state))add(a.n,r75Note(state==='错误'?'第 2 行：数组未闭合':state==='已应用'?'配置已应用':'配置校验通过',state==='错误'?'请补全右方括号后重试。当前配置继续生效。':state==='已应用'?'核心已重新载入当前配置。':'语法有效，可以应用到核心。',a.w,state==='错误'?'Error':'Success'),space(12));
  const actions=row('高级配置操作',a.w,44,8),validate=r75Route(r75Button('校验配置','Secondary','check',mobile?120:132),'配置校验'),apply=r75Button('应用配置','Primary',null,mobile?160:132);if(state==='已校验')r75Route(apply,'配置应用');else apply.opacity=.4;add(actions,validate,apply);add(a.n,actions);add(c,a.n);
}
function r75MobileHome(c){
  const a=r75Card('应用信息',true),id=row('应用标识',a.w,40,12);add(id,instance('Brand / Mark'),r75Copy('RainLink','1.0.0 · 稳定版',210,16));add(a.n,id);add(c,a.n);
  const b=r75Card('常用偏好',true);add(c,r75Rows(b,[r75Toggle('自动连接','启动时恢复上次选择',b.w,true,false),r75Toggle('连接与到期通知','连接变化与订阅到期时提醒',b.w,true,true)]));
  const d=r75Card('设置分类',true);add(c,r75Rows(d,[r75LinkRow('外观与语言','深色 · 简体中文','外观',d.w,true),r75LinkRow('网络与 DNS','加密解析 · IPv6','网络',d.w,true),r75LinkRow('核心与高级配置','sing-box · 运行中','核心引擎',d.w,true),r75LinkRow('更新','通过应用商店更新','更新',d.w,true),r75LinkRow('关于 RainLink','版本信息、隐私与开源许可','关于',d.w,true)]));
}
function r75DesktopNav(selected){
  const n=borderCard('设置分类导航',184,652,10,4,'Surface');r6Name(n,'设置分类导航');
  for(const [name,ic]of [['通用','settings'],['外观','sun'],['网络','globe'],['核心引擎','terminal'],['更新','refresh'],['关于','rain']]){
    const active=name===selected,b=r75Route(rad(row('设置分类 · '+name,162,44,10,12,active?'PrimarySurface':null),8),name);r6Name(b,'设置分类 · '+name);add(b,icon(ic,16,active?'Primary':'Muted'),r75Text(name,13,active?'Primary':'Secondary'));add(n,b);
  }
  const spacer=space();add(n,spacer);spacer.layoutGrow=1;add(n,r75Text('1.0.0 · 稳定版',11,'Muted'));return n;
}
async function r75Workspace(mobile){
  const platform=mobile?'移动端':'桌面端',views=mobile?['首页','外观','网络','核心引擎','更新','关于','高级配置','配置JSON','配置已校验','配置已应用','配置错误','隐私说明','开源许可']:['通用','外观','网络','核心引擎','更新','关于','高级配置','配置JSON','配置已校验','配置已应用','配置错误','隐私说明','开源许可'],variants={};
  for(const view of views){
    const c=r75Body('分类='+view,mobile?353:1120),body=mobile?c:v('设置详情',912,12);
    if(!mobile){c.layoutMode='HORIZONTAL';c.counterAxisAlignItems='MIN';c.itemSpacing=24;c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.resize(1120,652);add(c,r75DesktopNav(/配置/.test(view)?'核心引擎':['隐私说明','开源许可'].includes(view)?'关于':view),body);}
    if(view==='首页')r75MobileHome(body);else if(view==='通用')r75General(body,mobile);else if(view==='外观')r75Appearance(body,mobile);else if(view==='网络')r75Network(body,mobile);else if(view==='核心引擎')r75Core(body,mobile);else if(view==='更新')r75Updates(body,mobile);else if(view==='关于')r75About(body,mobile);else if(['隐私说明','开源许可'].includes(view))r75Legal(body,mobile,view==='隐私说明');else r75Advanced(body,mobile,view==='配置JSON'?'JSON':view==='配置已校验'?'已校验':view==='配置已应用'?'已应用':view==='配置错误'?'错误':'YAML');
    variants[view]=c;
  }
  const lib=r75Set('设置 / '+platform+' / 分类与详情',variants,mobile?4:2);
  const libraryPosition={x:lib.set.x,y:lib.set.y};
  // Navigation routes are authored on the destination's product page before
  // the component library is returned to the shared design-system section.
  if(mobile)mobilePage.appendChild(lib.set);
  for(const [view,c]of Object.entries(variants))for(const n of c.findAll(n=>!!n.getPluginData('rainlink-settings-route'))){
    const route=n.getPluginData('rainlink-settings-route');let dest=route==='配置YAML'?'高级配置':route==='配置JSON'?'配置JSON':route==='配置校验'?'配置已校验':route==='配置应用'?'配置已应用':route;
    if(route==='@DNS')await n.setReactionsAsync(r7Click(registry.mobile.DNS.id,'NAVIGATE'));
    else if(variants[dest]&&dest!==view)await n.setReactionsAsync(r7Click(variants[dest].id));
  }
  if(mobile){r75Section.appendChild(lib.set);lib.set.x=libraryPosition.x;lib.set.y=libraryPosition.y;}
  const screen=(mobile?registry.mobile:registry.desktop).Settings,content=uFind(screen,'Content');for(const n of [...content.children])if(r5Name(n)!=='Page header')n.remove();
  add(content,r7Instance(variants[mobile?'首页':'通用'],R75_UI));content.itemSpacing=mobile?12:16;content.paddingBottom=mobile?16:24;
  if(!mobile){const header=uFind(screen,'Page header');for(const n of [...header.children])if(n.type==='INSTANCE'&&n.findOne(t=>t.type==='TEXT'&&t.characters==='高级配置'))n.remove();}
  for(const t of screen.findAll(n=>n.type==='TEXT'))if(t.characters==='让 RainLink 符合你的习惯。')r6Copy(t,'偏好即时保存，网络与配置在确认后应用。');else if(t.characters==='小处贴心，日常顺手。')r6Copy(t,'管理偏好与网络选项');
  return {set:lib.set.id,initial:variants[mobile?'首页':'通用'].id,variants:Object.fromEntries(Object.entries(variants).map(([name,c])=>[name,c.id]))};
}
async function r75ApplySettings(report){
  const installed=uFind(registry.desktop.Settings,R75_UI),existing=dsPage.findOne(n=>n.type==='SECTION'&&n.getPluginData('rainlink-settings-version')==='7.5');
  if(installed&&uFind(registry.mobile.Settings,R75_UI)&&existing&&existing.getPluginData('rainlink-settings-revision')===R75_REVISION&&report.settingsUI?.revision===R75_REVISION){await r75RefreshChoiceLayouts(report.settingsUI,existing);await r75RefreshLegalBack(report.settingsUI);report.version='7.5';return report.settingsUI;}
  for(const reg of [registry.desktop,registry.mobile]){const view=uFind(reg.Settings,R75_UI);if(view)view.remove();}
  if(existing)existing.remove();
  for(const n of [...dsPage.children])if(n.getPluginData('rainlink-settings-version')==='7.5')n.remove();
  for(const page of [desktopPage,mobilePage])for(const n of [...page.children])if(n.type==='FRAME'&&['解析成功 · 28 ms','DNS 设置已保存','解析器地址不完整'].includes(r5Name(n)))n.remove();
  await figma.setCurrentPageAsync(dsPage);
  r75Section=figma.createSection();r75Section.name='设置 / 分类、控件与状态';r75Mark(r75Section);r75Section.setPluginData('rainlink-settings-revision',R75_REVISION);dsPage.appendChild(r75Section);r75Section.x=0;r75Section.y=Math.max(...dsPage.children.filter(n=>n!==r75Section&&n.visible).map(n=>n.y+n.height))+80;
  const title=add(v('设置组件库说明',4800,10),r75Text('设置 · 两端统一',26,'Text','Medium'),r75Text('分类、开关、主题、选择器、DNS、核心重启、更新与配置编辑，复用组件表达状态，不复制产品整页。',14,'Muted','Regular',4700));r75Section.appendChild(title);title.x=32;title.y=24;
  r75BackMaster();
  for(const mobile of [false,true]){
    await r75ToggleLibrary(mobile);
    for(const [key,options]of Object.entries({语言:['简体中文','繁體中文','English'],密度:['紧凑','标准'],文字:['标准','较大'],端口:['7890','8080','1080'],日志:['信息','警告','调试'],...(mobile?{}:{关闭行为:['最小化到托盘','退出应用'],渠道:['稳定版','预览版']})}))await r75ChoiceLibrary(key,options,mobile);
    await r75ThemeLibrary(mobile);await r75DNSLibrary(mobile);await r75EngineLibrary(mobile);await r75UpdateLibrary(mobile);
  }
  const desktop=await r75Workspace(false),mobile=await r75Workspace(true),dnsScreen=registry.mobile.DNS,dnsContent=uFind(dnsScreen,'Content');for(const n of [...dnsContent.children])n.remove();add(dnsContent,r7Instance(r75Libraries['dnstrue'].variants['加密 DNS'],'DNS 设置'),r75Toggle('DNS 缓存','复用近期解析结果',353,true,true),r75Button('返回网络设置','Secondary','返回',353));
  const back=dnsContent.children[dnsContent.children.length-1];
  const backReaction=[{trigger:{type:'ON_CLICK'},actions:[{type:'BACK'}]}];await back.setReactionsAsync(backReaction);
  const header=uFind(dnsScreen,'Page header'),close=header.children.find(n=>n.type==='INSTANCE');if(close)await close.setReactionsAsync(backReaction);
  const settingsHeader=uFind(registry.mobile.Settings,'Page header');for(const n of [...settingsHeader.children])if(n.type==='INSTANCE')n.remove();
  for(const screen of [registry.mobile.Settings,dnsScreen]){const nav=uFind(screen,'Mobile / Bottom navigation');for(const tab of nav.children){const label=tab.findOne(n=>n.type==='TEXT'),active=label?.characters==='设置';if(label)fill(label,active?'Primary':'Muted');const ic=tab.findOne(n=>n.type==='INSTANCE');if(ic)tint(ic,active?'Primary':'Muted');}}
  r75Section.resizeWithoutConstraints(5032,r75ShelfY+r75ShelfH+32);
  const controls=Object.fromEntries(Object.entries(r75Libraries).map(([key,{set,variants}])=>[key,{set:set.id,states:Object.fromEntries(Object.entries(variants).map(([name,c])=>[name,c.id]))}]));
  report.version='7.5';report.settingsUI={version:'7.5',revision:R75_REVISION,screensAdded:0,desktop,mobile,controls,section:r75Section.id,choiceMenus:'Full dropdown bounds reserved in component library',systemProxyAndTun:'overview only',defaultLanguage:'简体中文',desktopCategoryCount:6,mobileCategoryCount:5,prototypeBoundary:'Native component UI examples; no OS action, update download, arbitrary text editing or actual network request is performed.'};
  await r75RefreshLegalBack(report.settingsUI);report.counts.components=dsPage.findAll(n=>n.type==='COMPONENT').length;report.counts.instances=[desktopPage,mobilePage,dsPage].reduce((sum,p)=>sum+p.findAll(n=>n.type==='INSTANCE').length,0);figma.root.setPluginData('rainlink-settings-version','7.5');return report.settingsUI;
}
async function r75VerifySettings(report){
  const ui=report.settingsUI,errors=[],result={version:'7.5',revision:R75_REVISION,verifiedAt:new Date().toISOString(),errors,desktopViews:[],mobileViews:[],routeCount:0,choiceCount:0,toggleHitHeight:44};
  const check=(ok,detail)=>{if(!ok)errors.push(detail);};
  const actions=n=>(n?.reactions||[]).flatMap(r=>r.actions||[]),destination=(n,id)=>actions(n).some(a=>a.destinationId===id);
  check(figma.root.children.length===3,'文档页签应为 3 个');
  for(const [platform,page,reg,expected]of [['desktop',desktopPage,registry.desktop,12],['mobile',mobilePage,registry.mobile,11]]){
    const screens=page.findAll(n=>n.type==='FRAME'&&n.getPluginData('rainlink'));
    result[platform+'ScreenCount']=screens.length;check(screens.length===expected,platform+' 产品画面数量变化');
    check(screens.every(n=>n.layoutMode&&n.layoutMode!=='NONE'),platform+' 产品画面缺少 Auto Layout');
    const view=uFind(reg.Settings,R75_UI);check(!!view,platform+' 设置工作区缺失');
    check(!reg.Settings.findOne(n=>n.type==='TEXT'&&/系统代理|TUN\s*模式/i.test(n.characters)),platform+' 设置重复显示系统代理或 TUN');
    const lib=await figma.getNodeByIdAsync(ui[platform].set);check(lib.children.length===13,platform+' 设置详情不完整');
    for(const [name,id]of Object.entries(ui[platform].variants)){
      const c=await figma.getNodeByIdAsync(id),body=platform==='desktop'?uFind(c,'设置详情'):c;
      let expandedHeight=body.height;
      if(platform==='desktop')for(const child of body.children)if(child.type==='INSTANCE'){
        const main=await child.getMainComponentAsync(),parent=main?.parent;
        if(parent?.type==='COMPONENT_SET'&&parent.getPluginData('rainlink-settings-version')==='7.5')expandedHeight+=Math.max(...parent.children.map(n=>n.height))-child.height;
      }
      result[platform+'Views'].push({name,height:body.height,expandedHeight});
      if(platform==='desktop')check(expandedHeight<=652.1,'桌面 '+name+' 内容超过可用高度');
      if(platform==='mobile'&&name==='首页')check(body.height<=622,'移动设置首屏超高');
      if(['隐私说明','开源许可'].includes(name)){
        const header=uFind(body,'关于详情导航'),back=uFind(header,'返回关于箭头');
        check(body.children[0]===header&&header.children[0]===back,platform+' '+name+' 返回箭头应在内容区左上角');
        check(back?.width>=44&&back?.height>=44&&destination(back,ui[platform].variants['关于']),platform+' '+name+' 返回箭头命中区或目标无效');
        check(!c.findOne(n=>n.type==='TEXT'&&n.characters==='返回关于'),platform+' '+name+' 仍显示返回关于文字按钮');
        const slot=back?.children.find(n=>n.type==='INSTANCE'&&n.visible),master=slot&&await slot.getMainComponentAsync();check(master&&r5Name(master)==='Icon / 返回',platform+' '+name+' 返回箭头图标无效');
      }
      for(const n of c.findAll(n=>!!n.getPluginData('rainlink-settings-route'))){
        const route=n.getPluginData('rainlink-settings-route'),target=route==='配置YAML'?'高级配置':route==='配置JSON'?'配置JSON':route==='配置校验'?'配置已校验':route==='配置应用'?'配置已应用':route;
        if(route==='@DNS')check(destination(n,registry.mobile.DNS.id),'移动 DNS 入口无效');
        else if(target!==name)check(destination(n,ui[platform].variants[target]),platform+' '+name+' 到 '+target+' 的入口无效');
        result.routeCount++;
      }
    }
    const initial=await figma.getNodeByIdAsync(ui[platform].initial);
    if(platform==='desktop')check(uFind(initial,'设置分类导航').children.filter(n=>n.getPluginData('rainlink-settings-route')).length===6,'桌面设置分类应为 6 个');
    const network=await figma.getNodeByIdAsync(ui[platform].variants['网络']),port=uFind(network,'设置选择器 · 端口');
    check(uFind(port,'选择器值')?.characters==='7890',platform+' 默认混合端口不正确');
    for(const name of ['高级配置','配置JSON','配置错误','配置已应用']){
      const c=await figma.getNodeByIdAsync(ui[platform].variants[name]),apply=c.findOne(n=>n.type==='INSTANCE'&&n.findOne(t=>t.type==='TEXT'&&t.characters==='应用配置'));
      check(apply&&apply.opacity<.5&&actions(apply).length===0,platform+' 未校验配置不应直接应用');
    }
    const valid=await figma.getNodeByIdAsync(ui[platform].variants['配置已校验']),apply=valid.findOne(n=>n.type==='INSTANCE'&&n.findOne(t=>t.type==='TEXT'&&t.characters==='应用配置'));
    check(destination(apply,ui[platform].variants['配置已应用']),platform+' 已校验配置无法应用');
  }
  for(const [key,lib]of Object.entries(ui.controls)){
    if(key.startsWith('toggle'))for(const state of ['on','off']){
      const c=await figma.getNodeByIdAsync(lib.states[state]),hit=uFind(c,'设置开关命中区');
      check(hit?.height>=44&&hit?.width>=44&&destination(hit,lib.states[state==='on'?'off':'on']),key+' 开关命中区域或切换无效');
    }
    else if(Object.keys(lib.states).some(k=>k.endsWith(' · 展开'))){
      result.choiceCount++;
      for(const value of Object.keys(lib.states).filter(k=>!k.endsWith(' · 展开'))){
        const c=await figma.getNodeByIdAsync(lib.states[value]),open=await figma.getNodeByIdAsync(lib.states[value+' · 展开']);
        check(destination(uFind(c,'选择器按钮'),open.id)&&uFind(open,'选择器值').characters===value,key+' 选择器丢失当前值');
        const menu=uFind(open,'选择器菜单');check(open.y+menu.y+menu.height<=open.parent.height,key+' 展开菜单被组件集裁切');
        for(const option of Object.keys(lib.states).filter(k=>!k.endsWith(' · 展开')))check(destination(uFind(open,'选项 · '+option),lib.states[option]),key+' 选择器选项无效');
      }
    }
    else if(key.startsWith('dns')){
      const invalid=await figma.getNodeByIdAsync(lib.states['地址错误']);
      for(const name of ['保存 DNS','测试 DNS']){const n=uFind(invalid,name);check(n.opacity<.5&&!actions(n).length,key+' 地址错误时操作应禁用');}
    }
  }
  const dns=uFind(registry.mobile.DNS,'Content'),back=report.backNavigation?uFind(uFind(registry.mobile.DNS,'Page header'),'返回网络设置箭头'):dns.children[dns.children.length-1];
  check(actions(back).some(a=>a.type==='BACK'),'DNS 返回应保留设置分类');
  const backMaster=await back.children.find(n=>n.type==='INSTANCE'&&n.visible).getMainComponentAsync();
  check(r5Name(backMaster)==='Icon / 返回','DNS 返回箭头方向不正确');
  result.legalBackNavigation='top-left-arrow';result.legalBackViews=4;result.systemProxyAndTunAbsentFromSettings=true;result.productScreens=23;result.pageCount=3;report.settingsUIVerification=result;
}
async function r75SettingsMain(){
  figma.showUI('<body style="padding:24px;background:#151617;color:#c0c2c8;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#8adcbf">RainLink / 补全设置</h2><p id="s">补全两端分类、控件与交互…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:520,height:200});
  await r5Initialize();figma.skipInvisibleInstanceChildren=false;await r71Palette();const report=JSON.parse(figma.root.getPluginData('rainlink-report'));
  try{
    await r75ApplySettings(report);await r76UpdateBackNavigation(report);figma.ui.postMessage({status:'核验设置布局与全部原型目标…'});await r75VerifySettings(report);await r76VerifyBackNavigation(report);await r71VerifyControls(report);
  }catch(e){const t=uFind(dsPage,'Delivery / Native audit');t.characters='RainLink 设计核验\n'+JSON.stringify({...report,settingsUIBuildError:String(e)+'\n'+String(e.stack||'')},null,2);throw e;}
  const audit=await r5AuditDocument();report.overflow=audit.overflow;report.untranslatedDisplayCopy=audit.untranslatedDisplayCopy;delete report.nativeBackup;delete report.screenshotVerification;
  const text=uFind(dsPage,'Delivery / Native audit');text.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);text.visible=false;figma.root.setPluginData('rainlink-report',JSON.stringify(report));
  await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Settings];figma.viewport.scrollAndZoomIntoView(figma.currentPage.selection);figma.notify('两端设置已补全 · 保持 23 个产品画面');figma.closePlugin();
}

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

// RainLink 7.5 / review repair revision 1. UI examples only; keep 23 product frames.
const R77_REV='1';
let r77Section,r77X=24,r77Y=96,r77H=0;
const r77Edges=[],r77Libs={};
const R77_PROTOCOLS=['Shadowsocks','VLESS','VMess','Trojan','Hysteria','TUIC','SOCKS5','HTTP'];
async function r77Initialize(){
  figma.skipInvisibleInstanceChildren=true;for(const page of figma.root.children){figma.ui.postMessage({status:'载入页签 '+page.name+'…'});await page.loadAsync();}const report=JSON.parse(figma.root.getPluginData('rainlink-report'));zhFamily=report.chineseFont.family;zhStyles=report.chineseFont.styles;
  await Promise.all([...new Set(Object.values(zhStyles))].map(async style=>{figma.ui.postMessage({status:'载入中文字体 '+style+'…'});await figma.loadFontAsync({family:zhFamily,style});}));
  // Optional remote Latin weights can hang while offline. New and edited copy uses
  // the already-loaded Chinese family, which also contains Latin characters.
  uText=function(s,size=14,color='Text',weight='Regular',w=null){const n=figma.createText();n.fontName={family:zhFamily,style:zhStyles[weight]||zhStyles.Regular};n.fontSize=size;n.characters=s;n.lineHeight={unit:'PIXELS',value:Math.ceil(size*1.45)};fill(n,color);if(w){n.resize(w,Math.ceil(size*1.45));n.textAutoResize='HEIGHT';}else n.textAutoResize='WIDTH_AND_HEIGHT';return n;};
  r6Copy=function(n,s){if(!n)return;n.setBoundVariable('characters',null);n.fontName={family:zhFamily,style:zhStyles.Regular};n.characters=s;n.setPluginData('rainlink-original-text',s);};
  desktopPage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='desktop');mobilePage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='mobile');dsPage=figma.root.children.find(p=>p.getPluginData('rainlink-role')==='system');
  for(const [reg,page,prefix]of [[registry.desktop,desktopPage,'desktop/'],[registry.mobile,mobilePage,'mobile/']])for(const s of page.findAll(n=>n.type==='FRAME'&&n.getPluginData('rainlink').startsWith(prefix)))reg[s.getPluginData('rainlink').slice(prefix.length)]=s;
  for(const c of dsPage.findAll(n=>n.type==='COMPONENT')){const name=r5Name(c);if(name.startsWith('Icon / '))icons[name.slice(7)]=c;else if(name.startsWith('Style=')){const p=name.split(', ');masters['Button / '+p[0].slice(6)+' / '+p[1].slice(5)]=c;}else if(name.startsWith('Tone='))masters['Badge / '+name.slice(5)]=c;else masters[name]=c;}
}
function r77Mark(n){n.setPluginData('rainlink-review-fix',R77_REV);return n;}
function r77Place(n){
  if(r77X+n.width>6000&&r77X>24){r77Y+=r77H+64;r77X=24;r77H=0;}
  r77Section.appendChild(n);n.x=r77X;n.y=r77Y;r77X+=n.width+48;r77H=Math.max(r77H,n.height);return n;
}
function r77Body(name,w){return r77Mark(r7Body(name,w));}
function r77Set(name,states,mobile,build,cols=2){
  const edgeAt=r77Edges.length,variants={};for(const key of states){const c=build(key);r6Name(c,'状态='+key);variants[key]=r77Mark(c);}
  const set=r7VariantSet('修订 / '+(mobile?'移动端':'桌面端')+' / '+name,Object.values(variants),cols);r77Place(set);r77Mark(set);
  const lib={set,variants,initial:variants[states[0]]};for(const edge of r77Edges.slice(edgeAt))if(typeof edge.to==='string'&&variants[edge.to])edge.to=variants[edge.to];r77Libs[(mobile?'M/':'D/')+name]=lib;return lib;
}
function r77Go(n,to,nav='CHANGE_TO'){if(n&&to)r77Edges.push({n,to,nav});return n;}
function r77Close(n){r77Edges.push({n,close:true});return n;}
function r77Button(label,to=null,tone='Secondary',ic=null,w=null,nav='CHANGE_TO'){
  return r77Go(r6Button(label,tone,ic,w),to,nav);
}
function r77Text(s,size=14,tone='Text',w=null){return r6Text(s,size,tone,'Regular',w);}
function r77Note(title,copy,w,tone='Info'){
  const n=borderCard('反馈 · '+title,w,null,12,4,tone==='Success'?'PrimarySurface':tone+'Surface');rad(n,10);stroke(n,tone);
  add(n,r6Text(title,13,tone,'Medium',w-26),copy?r77Text(copy,12,'Secondary',w-26):null);return n;
}
function r77Back(title,w,to){
  const n=row('局部返回导航',w,44,4),back=r76BackIcon(r6Button('','Ghost',null,44),'返回上一级箭头');
  add(n,r77Go(back,to),r6Text(title,20,'Text','Medium',w-48));return n;
}
function r77Tabs(labels,active,w,mobile,prefix='切换'){
  const n=rad(row(prefix,w,44,4,0,'Raised'),8),each=(w-(labels.length-1)*4)/labels.length;
  for(const name of labels){const t=center(rad(row(prefix+' · '+name,each,44,0,0,active===name?'PrimarySurface':null),8));add(t,r77Text(name,13,active===name?'Primary':'Secondary'));add(n,t);}return n;
}
function r77Field(label,value,w){const n=r6Field(label,value,w);n.itemSpacing=4;const input=uFind(n,'输入 · '+label);input.paddingLeft=input.paddingRight=12;const t=uFind(input,'Value');if(t){t.layoutSizingHorizontal='FILL';t.fontSize=13;}return n;}
function r77Install(screen,c,name,keepHeader=true){
  const b=uFind(screen,'Content');for(const n of [...b.children])if(!keepHeader||r5Name(n)!=='Page header')n.remove();
  const instance=r7Instance(c,name);add(b,instance);return instance;
}
function r77Dialog(mobile,title,backTo=null){
  const w=mobile?393:520,p=mobile?20:24,iw=w-p*2,c=r77Body('弹窗',w);
  fill(c,'Surface');stroke(c);rad(c,mobile?24:16);c.paddingLeft=c.paddingRight=p;c.paddingTop=mobile?12:24;c.paddingBottom=mobile?34:24;c.itemSpacing=12;c.clipsContent=true;
  if(mobile){const cap=center(row('弹窗拖拽柄容器',iw,8));add(cap,rad(row('弹窗拖拽柄',36,4,0,0,'Stroke'),2));add(c,cap);}
  const head=row('弹窗标题',iw,44,4);if(backTo)add(head,r77Go(r76BackIcon(r6Button('','Ghost',null,44),'返回上一级箭头'),backTo));
  const text=r6Text(title,22,'Text','Medium',iw-(backTo?96:48));add(head,text);text.layoutSizingHorizontal='FILL';add(head,r77Close(r6Name(r6Button('','Ghost','close',44),'关闭弹窗')));add(c,head);
  return {c,w,iw};
}
function r77ClampScroll(n,maxHeight){n.primaryAxisSizingMode='FIXED';n.resize(n.width,Math.min(n.height,maxHeight));n.clipsContent=true;n.overflowDirection='VERTICAL';n.setPluginData('rainlink-keyboard-scroll','resize viewport with keyboard; fixed footer above keyboard');}
async function r77Add(mobile){
  const names=['订阅','订阅已填','地址错误','获取失败','导入中','重试中','订阅成功','节点成功','协议选择','校验错误','扫码','相机拒绝',...R77_PROTOCOLS.flatMap(p=>[p,p+' · 更多'])];
  const lib=r77Set('添加',names,mobile,key=>{
    const manual=R77_PROTOCOLS.some(p=>key.startsWith(p))||['协议选择','校验错误','节点成功'].includes(key),picker=key==='协议选择',qr=['扫码','相机拒绝'].includes(key);
    const {c,w,iw}=r77Dialog(mobile,picker?'选择协议':qr?'扫码导入':key.endsWith('成功')?'添加完成':'添加');
    if(key.endsWith('成功')){
      add(c,r6Badge('已完成','Success'),r6Text(key==='节点成功'?'节点已加入未分组':'订阅已自动成组',22,'Text','Medium',iw),r77Text(key==='节点成功'?'新节点仅被保存。选择节点后，在概览开启 VPN。':'已导入「旅行订阅」及 4 个节点，名称由订阅自动识别。',14,'Secondary',iw),r77Close(r6Button('完成','Primary',null,iw)));return c;
    }
    if(picker){
      const back=r77Back('单个节点',iw,'HTTP');add(c,back,r77Text('选择协议后填写连接参数',12,'Muted',iw));
      for(let i=0;i<R77_PROTOCOLS.length;i+=2){const line=row('协议选项',iw,44,8);for(const p of R77_PROTOCOLS.slice(i,i+2))add(line,r77Button(p,p,'Secondary',null,(iw-8)/2));add(c,line);}return c;
    }
    if(qr){
      if(key==='扫码'){
        const scan=center(borderCard('二维码识别区域',iw,220,16,12,'Raised'));add(scan,icon('qr',96,'Primary'),r77Text('扫描订阅或节点二维码',13,'Secondary'));add(c,scan,r77Button('识别示例二维码','订阅已填','Primary','qr',iw),r77Button('相机权限不可用','相机拒绝','Ghost',null,iw));
      }else add(c,r77Note('无法使用相机','请在系统设置中允许相机访问，或粘贴订阅链接。',iw,'Warning'),r77Button('使用链接导入','订阅','Primary',null,iw),r77Button('重新授权','扫码','Secondary',null,iw));
      c.insertChild(mobile?2:1,r77Back('链接导入',iw,'订阅'));return c;
    }
    const tabs=r77Tabs(['订阅','单个节点'],manual?'单个节点':'订阅',iw,mobile,'添加方式');add(c,tabs);r77Go(tabs.children[0],'订阅');r77Go(tabs.children[1],'HTTP');
    const scroll=v('表单滚动区',iw,12);add(c,scroll);
    if(!manual){
      const empty=key==='订阅',bad=key==='地址错误',loading=['导入中','重试中'].includes(key);
      const field=r77Field('订阅链接',empty?'粘贴 https:// 订阅地址':bad?'example.com/sub':'https://example.com/sub/travel',iw);add(scroll,field);r77Go(uFind(field,'输入 · 订阅链接'),empty?'订阅已填':bad?'订阅已填':'地址错误');
      if(empty)add(scroll,r77Button('粘贴链接','订阅已填','Secondary','copy',iw));
      const update=between(row('自动更新',iw,44,8));add(update,add(v('自动更新文案',iw-56,2),r77Text('自动更新',14),r77Text('每 6 小时',12,'Muted')),sw(true));add(scroll,update,r77Text('名称自动识别 · 导入后自动创建一个分组',12,'Muted',iw));
      if(bad)add(scroll,r77Note('链接格式不正确','请填写以 https:// 或 http:// 开头的完整地址。',iw,'Error'));
      if(key==='获取失败')add(scroll,r77Note('订阅获取失败','请求超时，已保留链接。检查网络后重试。',iw,'Error'));
      if(loading)add(scroll,r77Note('正在获取订阅','正在读取节点、流量与到期信息…',iw));
      if(mobile)add(scroll,r77Button('扫码导入','扫码','Ghost','qr',iw));
      const actions=row('弹窗操作',iw,44,12);add(actions,r77Close(r6Button('取消','Secondary',null,96)),r77Button(loading?'正在导入…':key==='获取失败'?'重试':'导入订阅',loading?null:empty?'地址错误':key==='获取失败'?'重试中':'导入中','Primary',loading?'refresh':'download',iw-108));add(c,actions);
    }else{
      const p=R77_PROTOCOLS.find(p=>key.startsWith(p))||'HTTP',more=key.endsWith('更多');
      const selector=between(rad(row('协议选择器',iw,44,8,12,'Raised'),8));stroke(selector);add(selector,r77Text(p,14),icon('down',16,'Muted'));add(scroll,r77Text('协议',12,'Secondary'),r77Go(selector,'协议选择'));
      add(scroll,r77Field('服务器',key==='校验错误'?'':'proxy.example.com',iw));
      const pair=row('端口与名称',iw,null,12);add(pair,r77Field('端口',p==='HTTP'?'8080':p==='SOCKS5'?'1080':'443',96),r77Field('名称（可选）','自动使用服务器地址',iw-108));add(scroll,pair);
      if(p==='Shadowsocks'){
        add(scroll,r77Field('加密方式','chacha20-ietf-poly1305',iw),r77Field('密码','••••••••••••',iw));
      }else if(['VLESS','VMess','TUIC'].includes(p)){
        add(scroll,r77Field('用户标识 UUID','a4f3c201-7a9e-4ac1-8a2e-1951b42e3856',iw));
        if(p==='TUIC')add(scroll,r77Field('密码','••••••••••••',iw));
      }else if(['Trojan','Hysteria'].includes(p))add(scroll,r77Field(p==='Hysteria'?'认证密码 · Hysteria 2':'密码','••••••••••••',iw));
      const toggle=r77Button(more?'收起更多参数':'更多参数',more?p:p+' · 更多','Ghost','down',iw);add(scroll,toggle);
      if(more){
        if(['HTTP','SOCKS5'].includes(p))add(scroll,r77Field('用户名（可选）','未设置',iw),r77Field('密码（可选）','未设置',iw));
        else{add(scroll,r77Field('TLS 服务器名称（SNI）','proxy.example.com',iw));if(['VLESS','VMess'].includes(p))add(scroll,r77Field('传输方式','TCP · TLS',iw));if(p==='Shadowsocks')add(scroll,r77Field('插件（可选）','无',iw));if(['TUIC','Hysteria'].includes(p))add(scroll,r77Field('ALPN','h3',iw));}
      }
      if(key==='校验错误')add(scroll,r77Note('请填写服务器','服务器地址不能为空，端口范围为 1–65535。',iw,'Error'));
      add(scroll,r77Text('保存至未分组，可从节点菜单移动到已有分组。',12,'Muted',iw));
      const actions=row('弹窗操作',iw,44,12);add(actions,r77Close(r6Button('取消','Secondary',null,96)),r77Button('添加节点','节点成功','Primary','plus',iw-108));add(c,actions);
      r77Go(uFind(scroll,'输入 · 服务器'),key==='校验错误'?'HTTP':'校验错误');
    }
    r77ClampScroll(scroll,mobile?388:460);return c;
  },3);
  for(const key of ['导入中','重试中'])await lib.variants[key].setReactionsAsync(r7Timer(lib.variants[key==='导入中'?'获取失败':'订阅成功'].id));
  const reg=mobile?registry.mobile:registry.desktop;r6Overlay(mobile,'Import profile',lib.initial);r77Close(uFind(reg['Import profile'],'关闭弹窗遮罩'));
  return lib;
}
function r77SubscriptionPanel(mobile,group,mode,backTo){
  const w=mobile?353:520,p=16,iw=w-p*2,d=R6_INFO[group],c=borderCard('当前订阅 · '+group,w,null,p,12,'Surface');rad(c,16);
  const title=row('订阅详情标题',iw,44,4),back=r76BackIcon(r6Button('','Ghost',null,44),'返回分组箭头');add(title,backTo?r77Go(back,backTo):r77Close(back),r6Text(group,20,'Text','Medium',iw-48));add(c,title);
  if(mode==='删除'){
    add(c,r77Note('删除此订阅？','将删除订阅节点和订阅信息。手动移入的节点会退回未分组。当前连接在下一次切换前保持。',iw,'Warning'),r77Button('确认删除','已删除|'+group,'Primary',null,iw),r77Button('取消','详情|'+group,'Secondary',null,iw));return c;
  }
  if(mode==='编辑'){
    add(c,r77Field('订阅链接','https://example.com/sub/'+(group==='主订阅'?'main':group==='备用订阅'?'backup':'travel'),iw),r77Text('名称从订阅自动识别，无需填写分组名称。',12,'Muted',iw),r77Button('保存链接','已更新|'+group,'Primary',null,iw));return c;
  }
  add(c,between(add(row('套餐状态',iw,24),r77Text('套餐流量',12,'Muted'),r6Badge(d.status,d.tone==='Primary'?'Success':d.tone==='Warning'?'Warning':'Neutral'))),r6Text(d.used?d.used+' / '+d.total+' GB':'服务未提供流量信息',d.used?26:17,'Text','Medium',iw));
  if(d.used)add(c,r6Progress(iw,d.ratio,d.ratio>.9?'Warning':'Primary'),r77Text('剩余 '+d.remaining+' GB · ↓ '+d.down+'  ↑ '+d.up,12,'Secondary',iw));
  for(const [label,value]of [['到期时间',d.expires||'未提供'],['最近更新',mode==='已更新'?'刚刚':d.updated],['自动更新','每 6 小时']])add(c,between(add(row('订阅详情 · '+label,iw,28),r77Text(label,13,'Muted'),r77Text(value,13,'Secondary'))));
  if(mode==='更新中')add(c,r77Note('正在更新','保留已有节点，正在获取最新订阅…',iw));
  if(mode==='失败')add(c,r77Note('更新失败','请求超时，已保留原有节点和套餐信息。',iw,'Error'));
  if(mode==='已更新')add(c,r77Note('更新完成','节点与套餐信息已刷新，手动加入的节点已保留。',iw,'Success'));
  if(!d.used)add(c,r77Text('流量与有效期以服务返回信息为准。',12,'Muted',iw));
  const actions=row('当前订阅管理',iw,44,8);for(const [label,to]of [[mode==='失败'?'重试':'更新',(mode==='失败'?'已更新':'更新中')+'|'+group],['编辑链接','编辑|'+group],['删除','删除|'+group]])add(actions,r77Button(label,to,'Secondary',null,(iw-16)/3));add(c,actions);return c;
}
async function r77Groups(mobile){
  const reg=mobile?registry.mobile:registry.desktop,w=mobile?353:1120,names=['主订阅','备用订阅','未分组','旅行订阅'];
  const old=dsPage.findOne(n=>n.type==='COMPONENT_SET'&&r5Name(n)==='交互 / '+(mobile?'移动端':'桌面端')+' / 分组选择');
  const states=[...names.map(n=>'选中|'+n),'空',...['主订阅','备用订阅','旅行订阅'].flatMap(n=>['详情','编辑','删除','更新中','失败','已更新','已删除'].map(m=>m+'|'+n))];
  const lib=r77Set('分组管理',states,mobile,key=>{
    const [mode,group]=key.split('|'),c=r77Body('分组管理',w);c.itemSpacing=8;
    if(mode==='空'){add(c,r77Note('还没有分组或节点','导入订阅会自动成组，单个节点会加入未分组。',w),r77Button('添加订阅或节点',reg['Import profile'],'Primary','plus',mobile?w:240,'OVERLAY'));return c;}
    const source=old.children.find(n=>n.name==='选中='+(mode==='选中'?group:'主订阅'))||old.children[0],list=source.createInstance();r6Name(list,'紧凑分组列表');add(c,list);
    for(const card of list.children){const n=r5Name(card).replace('Group · ','');if(!names.includes(n))continue;
      r77Go(card,'选中|'+n);const more=uFind(card,'查看订阅信息');if(more&&more.visible)r77Go(more,'详情|'+n);
      const entry=card.findOne(t=>t.type==='INSTANCE'&&t.findAll(n=>n.type==='TEXT').some(t=>t.characters==='节点'));if(entry)r77Go(entry,reg.Nodes,'NAVIGATE');
      for(const a of card.findAll(n=>n.type==='INSTANCE'&&r5Name(n).includes('chevron')))r77Go(a.parent===card?a:a.parent,reg.Nodes,'NAVIGATE');
      if(mode==='已删除'&&n===group)card.visible=false;
    }
    if(mode==='已删除')add(c,r77Note('已删除'+group,'手动加入的节点已退回未分组。',w,'Success'));
    add(c,r77Text('订阅自动成组 · 单个节点默认进入未分组',12,'Muted',w));
    if(!['选中','已删除'].includes(mode)){
      c.resize(w,mobile?592:600);c.primaryAxisSizingMode='FIXED';
      const mask=r77Go(frame('详情遮罩',w,c.height,'VERTICAL','#000000'),'选中|主订阅');mask.fills=[{type:'SOLID',color:{r:0,g:0,b:0},opacity:.58}];add(c,mask);mask.layoutPositioning='ABSOLUTE';mask.x=mask.y=0;
      const panel=r77SubscriptionPanel(mobile,group,mode,'选中|主订阅');add(c,panel);panel.layoutPositioning='ABSOLUTE';panel.x=mobile?0:(w-panel.width)/2;panel.y=mobile?Math.max(0,c.height-panel.height):16;
    }
    return c;
  },3);
  for(const group of ['主订阅','备用订阅','旅行订阅'])await lib.variants['更新中|'+group].setReactionsAsync(r7Timer(lib.variants['失败|'+group].id));
  r77Install(reg.Profiles,lib.initial,'分组管理工作区');
  if(mobile)r77Install(reg['Quick switch'],lib.initial,'分组管理工作区');
  // The existing standalone host remains the entry for the principal subscription only.
  const details=r77Set('订阅详情',['详情','编辑','删除','更新中','失败','已更新','已删除'].map(m=>m+'|主订阅'),mobile,key=>{
    const mode=key.split('|')[0],body=r77Body('当前订阅',mobile?353:520);
    if(mode==='已删除')add(body,r77Note('订阅已删除','手动加入的节点已退回未分组。',body.width,'Success'),r77Close(r6Button('完成','Primary',null,body.width)));
    else add(body,r77SubscriptionPanel(mobile,'主订阅',mode,null));return body;
  },2);
  await details.variants['更新中|主订阅'].setReactionsAsync(r7Timer(details.variants['失败|主订阅'].id));
  r6Overlay(mobile,'Subscription info · 主订阅',details.initial);r77Close(uFind(reg['Subscription info · 主订阅'],'关闭弹窗遮罩'));
  return lib;
}
function r77Hop(data,index,total,w,mobile,state){
  const c=borderCard('跳点 '+(index+1),w,null,mobile?12:16,8,'Surface');rad(c,12);const iw=w-(mobile?26:34);
  const line=between(row('跳点标题',iw,28,8));add(line,r6Text(index===total-1?'出口 · 第 '+(index+1)+' 跳':'入口 · 第 '+(index+1)+' 跳',12,'Muted','Medium'),r6Badge(data.p));add(c,line);
  const identity=between(row('跳点节点',iw,28));add(identity,r6Text(data.name,15,'Text','Medium',iw-70),r77Text(data.ping+' ms',13,'Primary'));add(c,identity);
  const tools=row('跳点操作',iw,44,4),change=r77Button('更换','更换|'+index,'Secondary',null,mobile?88:120);add(tools,change);
  for(const [label,to,ic]of [['上移',state==='倒序'?'默认':'倒序','upload'],['下移',state==='倒序'?'默认':'倒序','download'],['移除','单跳','close']]){
    const b=r77Button(mobile?'':label,to,'Ghost',ic,mobile?44:80);r6Name(b,'跳点'+index+' · '+label);
    if((label==='上移'&&index===0)||(label==='下移'&&index===total-1)){b.opacity=.3;b.setPluginData('rainlink-disabled','true');for(let i=r77Edges.length-1;i>=0;i--)if(r77Edges[i].n===b)r77Edges.splice(i,1);}
    add(tools,b);
  }add(c,tools);return c;
}
async function r77Chain(mobile){
  const reg=mobile?registry.mobile:registry.desktop,w=mobile?353:1120,states=['默认','倒序','单跳','已添加','更换|0','更换|1','更换|2','添加跳点','已更换','测试中','测试失败','测试通过','已选中'];
  const lib=r77Set('代理链',states,mobile,key=>{
    const c=r77Body('代理链',w);c.itemSpacing=mobile?12:16;
    if(key==='已选中'){
      const heading=between(row('节点结果标题',w,44,8));add(heading,r6Text('节点',mobile?26:28,'Text','Medium'),r77Button('全部节点',reg.Nodes,'Secondary','nodes',120,'NAVIGATE'));add(c,heading,r77Note('已选中开发代理链','当前连接保持不变，返回概览开关 VPN 后应用。',w,'Success'));
      const saved=borderCard('已选代理链',w,null,16,10,'PrimarySurface');stroke(saved,'Primary');const head=between(row('已选代理链标题',w-34,28));add(head,r6Text('开发代理链',18,'Text','Medium'),icon('check',20,'Primary'));add(saved,head,r77Text('办公 HTTP → 东京 · 樱花',14,'Secondary',w-34),r77Text('2 跳 · 测试通过 46 ms · 待概览应用',12,'Primary',w-34));add(c,saved,r77Button('前往概览',reg[mobile?'Home':'Dashboard'],'Primary','grid',mobile?w:240,'NAVIGATE'));return c;
    }
    const picker=key.startsWith('更换|')||key==='添加跳点';
    if(picker){
      add(c,r77Back(key==='添加跳点'?'添加跳点':'更换第 '+(+key.split('|')[1]+1)+' 跳',w,'默认'),r77Field('搜索节点','名称、协议或地区',w));
      for(const data of [G_MAIN[0],G_LOOSE[0],G_BACKUP[0]]){const card=borderCard('选择跳点 · '+data.name,w,null,12,4,'Surface');add(card,between(add(row('跳点选项',w-26,32),r6Text(data.name,15,'Text','Medium'),r77Text(data.ping+' ms',13,'Primary'))),r77Text(data.p+' · '+data.region,12,'Muted',w-26));add(c,r77Go(card,key==='添加跳点'?'已添加':'已更换'));}
      add(c,r77Text('HTTP 跳点仅转发 TCP；UDP 不兼容时会在测试中提示。',12,'Muted',w));return c;
    }
    add(c,r77Back('代理链编排',w,reg.Nodes));r77Edges[r77Edges.length-1].nav='NAVIGATE';
    const rowW=mobile?w:728,left=mobile?c:v('可视化代理链',rowW,12),right=mobile?c:borderCard('代理链操作',368,null,20,12,'Surface'),rev=key==='倒序';
    add(left,r77Field('链名称','开发代理链',rowW));
    const route=borderCard('链路路径',rowW,null,12,8,'Raised');add(route,r77Text('本机 → '+(rev?'东京 · 樱花 → 办公 HTTP':key==='单跳'?'办公 HTTP':key==='已添加'?'办公 HTTP → 东京 · 樱花 → 新加坡':'办公 HTTP → 东京 · 樱花')+' → 目标',13,'Secondary',rowW-26));add(left,route);
    const data=key==='单跳'?[G_LOOSE[0]]:key==='已添加'?[G_LOOSE[0],G_MAIN[0],G_MAIN[2]]:rev?[G_MAIN[0],G_LOOSE[0]]:key==='已更换'?[G_LOOSE[0],G_BACKUP[0]]:[G_LOOSE[0],G_MAIN[0]];
    data.forEach((d,i)=>add(left,r77Hop(d,i,data.length,rowW,mobile,key)));add(left,r77Button('添加跳点','添加跳点','Secondary','plus',rowW));
    if(!mobile)add(c,add(row('代理链布局',w,null,24),left,right));
    if(key==='测试失败')add(right,r77Note('第 2 跳握手超时','入口可达，请更换出口节点或重试。原有选择保持不变。',mobile?w:326,'Error'));
    else if(key==='测试通过')add(right,r77Note('测试通过 · 46 ms','两跳 TCP 握手成功 · 出口为日本东京',mobile?w:326,'Success'));
    else if(key==='单跳')add(right,r77Note('还需要一个出口','代理链至少包含两个节点。',mobile?w:326,'Warning'));
    else add(right,r77Text(key==='测试中'?'正在测试第 2 跳…':'按顺序转发，最后一跳作为出口。',13,'Muted',mobile?w:326));
    add(right,r77Button(key==='测试失败'?'重新测试':key==='测试中'?'测试中…':'测试链路',key==='测试中'||key==='单跳'?null:key==='测试失败'?'测试通过':'测试中','Secondary','speed',mobile?w:326));
    const save=r77Button('保存并选中',key==='测试通过'?'已选中':null,'Primary','check',mobile?w:326);if(key!=='测试通过')save.opacity=.4;add(right,save,r77Text('保存只更改选择。VPN 开关与代理模式均在概览。',12,'Muted',mobile?w:326));return c;
  },2);
  await lib.variants['测试中'].setReactionsAsync(r7Timer(lib.variants['测试失败'].id));
  // The header is part of this component, so the saved result can return visually to Nodes.
  const screen=reg['Chain editor'];if(mobile){const h=uFind(screen,'Page header');if(h)h.visible=false;}r77Install(screen,lib.initial,'代理链编排工作区',false);
  return lib;
}
function r77Toolbar(w,left,right){const n=between(row('操作栏',w,null,12));if(left)add(n,left);if(right)add(n,right);return n;}
function r77Metric(label,value,detail,w){const n=borderCard(label,w,null,16,6,'Surface');rad(n,12);add(n,r77Text(label,12,'Muted'),r6Text(value,28,'Text','Medium',w-34),r77Text(detail,12,'Secondary',w-34));return n;}
function r77Table(columns,rows,w,keyPrefix='条目'){
  const n=borderCard('数据列表',w,null,0,0,'Surface');rad(n,12);n.clipsContent=true;
  const make=(values,head=false,index=0)=>{const line=row(head?'表头':keyPrefix+' · '+index,w,head?40:56,16,0,head?'Raised':null);line.paddingLeft=line.paddingRight=16;
    columns.forEach((col,i)=>add(line,r77Text(values[i],head?12:13,head?'Muted':i===0?'Text':'Secondary',col[1])));return line;};
  add(n,make(columns.map(c=>c[0]),true));rows.forEach((r,i)=>{if(i)add(n,divider(w));add(n,make(r,false,i));});return n;
}
function r77ClearHeaderActions(screen){const head=uFind(screen,'Page header');if(head)for(const n of [...head.children])if(n.type==='INSTANCE')n.remove();}
async function r77Rules(){
  const w=1120,states=['全部','域名','IP','添加','编辑','编辑 IP','保存完成','确认删除','删除完成'];
  const rules=[['DOMAIN-SUFFIX','github.com','主订阅','代理'],['DOMAIN-SUFFIX','openai.com','主订阅','代理'],['IP-CIDR','192.168.0.0/16','直连','直连'],['IP-CIDR','10.0.0.0/8','直连','直连'],['MATCH','所有其他请求','主订阅','代理']];
  const lib=r77Set('分流规则',states,false,key=>{
    const c=r77Body('规则工作区',w);c.itemSpacing=16;
    if(['添加','编辑','编辑 IP'].includes(key)){
      const p=borderCard('规则编辑',728,null,24,16,'Surface'),iw=678;add(p,r77Back(key==='添加'?'添加规则':'编辑规则',iw,'全部'));
      const type=r77Tabs(['域名后缀','IP 网段'],key==='编辑 IP'?'IP 网段':'域名后缀',iw,false,'规则类型');r77Go(type.children[0],'编辑');r77Go(type.children[1],'编辑 IP');add(p,type,r77Field(key==='编辑 IP'?'IP 网段 · CIDR':'域名后缀',key==='编辑 IP'?'192.168.0.0/16':'github.com',iw),r77Field('出站策略','主订阅',iw),r77Text('按顺序匹配，首个命中的规则决定出站。',13,'Muted',iw));
      const actions=row('规则编辑操作',iw,44,12);add(actions,r77Button('取消','全部','Secondary',null,120),r77Button('保存规则','保存完成','Primary','check',180));add(p,actions);add(c,p);return c;
    }
    const tabs=r77Tabs(['全部','域名','IP'],['域名','IP'].includes(key)?key:'全部',336,false,'规则过滤');tabs.children.forEach((n,i)=>r77Go(n,['全部','域名','IP'][i]));add(c,r77Toolbar(w,tabs,r77Button('添加规则','添加','Primary','plus',144)));
    add(c,r77Text('当前为规则模式 · 匹配优先级从上到下 · 代理模式在概览切换',13,'Muted',w));
    if(key==='保存完成')add(c,r77Note('规则已保存','配置已校验并应用于后续新连接。',w,'Success'));
    if(key==='删除完成')add(c,r77Note('规则已删除','其余规则顺序保持不变。',w,'Success'));
    const data=rules.filter((r,i)=>(key!=='删除完成'||i!==0)&&(key==='域名'?r[0].startsWith('DOMAIN'):key==='IP'?r[0].startsWith('IP'):true));
    const list=r77Table([['类型',190],['匹配条件',430],['出站',210],['操作',170]],data.map(r=>[r[0],r[1],r[2],'编辑       删除']),w,'规则');
    for(const line of list.children.filter(n=>r5Name(n).startsWith('规则 · '))){const action=line.children[line.children.length-1];action.visible=false;const buttons=row('规则行操作',170,44,4);add(buttons,r77Button('编辑','编辑','Ghost',null,76),r77Button('删除','确认删除','Ghost',null,76));add(line,buttons);}add(c,list);
    if(key==='确认删除')add(c,r77Note('删除 github.com 的规则？','删除后，该域名将继续匹配后续规则。',w,'Warning'),add(row('确认删除规则',w,44,12),r77Button('取消','全部','Secondary',null,120),r77Button('确认删除','删除完成','Primary',null,144)));
    return c;
  },2);r77ClearHeaderActions(registry.desktop.Rules);r77Install(registry.desktop.Rules,lib.initial,'规则工作区');return lib;
}
function r77Chart(w,mobile,period,point=false,to=null){
  const p=mobile?16:20,iw=w-p*2-2,n=borderCard('流量趋势图',w,null,p,12,'Surface'),unit=period==='今日'?'MB/s':'GB',plotH=mobile?140:170;
  add(n,between(add(row('图表标题',iw,24),r6Text('流量趋势',14,'Text','Medium'),r77Text(unit,12,'Muted'))));
  const plot=frame('图表选点区',iw,plotH,'NONE');plot.clipsContent=true;add(n,r77Go(plot,to));
  for(let i=0;i<3;i++){const line=frame('网格线',iw-36,1,'NONE','Stroke');add(plot,line);line.x=36;line.y=16+i*(plotH-40)/2;const label=r77Text(String(period==='今日'?24-i*12:18-i*9),12,'Muted');add(plot,label);label.x=0;label.y=line.y-8;}
  const base=[.12,.18,.1,.39,.26,.31,.28,.62,.38,.46,.83,.57,.61,.43,.75,.5,.36,.28,.55,.44,.51,.79,.62,.84];
  for(const [k,tone,scale]of [[0,'Primary',1],[1,'Chart2',.33]]){const path=base.map((v,i)=>`${i?'L':'M'} ${36+i*(iw-40)/(base.length-1)} ${plotH-15-v*scale*(plotH-35)}`).join(' '),vector=figma.createVector();r6Name(vector,k?'上传曲线':'下载曲线');vector.vectorPaths=[{windingRule:'NONE',data:path}];vector.fills=[];stroke(vector,tone,2);add(plot,vector);}
  if(point){const tip=borderCard('选点数据',mobile?150:210,null,10,2,'Raised');stroke(tip,'Primary');add(tip,r77Text(period==='今日'?'12:00':'10 月 12 日',12),r77Text('↓ '+(period==='今日'?'18.2 MB/s':'12.4 GB'),12,'Primary'),r77Text('↑ '+(period==='今日'?'1.8 MB/s':'860 MB'),12,'Chart2'));add(plot,tip);tip.x=iw-tip.width-12;tip.y=8;}
  const axis=between(row('横轴',iw,20));for(const label of period==='今日'?['00:00','06:00','12:00','18:00']:period==='本周'?['周一','周三','周五','周日']:['1 日','10 日','20 日','30 日'])add(axis,r77Text(label,12,'Muted'));add(n,axis,add(row('图例',iw,20,16),r77Text('● 下载',12,'Primary'),r77Text('● 上传',12,'Chart2')));return n;
}
async function r77Traffic(mobile){
  const w=mobile?353:1120,states=['今日','本周','本月','今日 · 选点','本周 · 选点','本月 · 选点','导出完成'];
  const lib=r77Set('流量统计',states,mobile,key=>{
    const period=key.split(' · ')[0]==='导出完成'?'今日':key.split(' · ')[0],point=key.includes('选点'),c=r77Body('流量统计',w);c.itemSpacing=16;
    const tabs=r77Tabs(['今日','本周','本月'],period,mobile?w:360,mobile,'流量周期');tabs.children.forEach((n,i)=>r77Go(n,['今日','本周','本月'][i]));
    if(mobile)add(c,tabs);else add(c,r77Toolbar(w,tabs,r77Button('导出 CSV','导出完成','Secondary','download',148)));
    if(key==='导出完成')add(c,r77Note('流量统计已导出','当前周期的上传、下载和用量排行已包含在内。',w,'Success'));
    const total=period==='今日'?'8.42 GB':period==='本周'?'42.8 GB':'126.4 GB',down=period==='今日'?'7.86 GB':period==='本周'?'39.6 GB':'117.2 GB',up=period==='今日'?'560 MB':period==='本周'?'3.2 GB':'9.2 GB';
    if(mobile){const card=r77Metric('总流量 · '+period,total,'↓ '+down+'    ↑ '+up,w);fill(card,'PrimarySurface');add(c,card);}else add(c,add(row('周期总计',w,null,16),r77Metric('总流量',total,period,(w-32)/3),r77Metric('已下载',down,'当前周期 · 下载',(w-32)/3),r77Metric('已上传',up,'当前周期 · 上传',(w-32)/3)));
    add(c,r77Chart(w,mobile,period,point,point?period:period+' · 选点'));
    const ranking=borderCard('使用排行',w,null,16,8,'Surface');add(ranking,r6Text('使用排行',14,'Text','Medium'));
    for(const [i,label,value,ratio]of [[1,'浏览器',period==='今日'?'4.28 GB':'24.6 GB',.67],[2,'代码编辑器',period==='今日'?'2.46 GB':'12.2 GB',.44],[3,'终端',period==='今日'?'1.68 GB':'6.0 GB',.28]]){const line=between(row('流量排行 · '+label,w-34,36));add(line,r77Text(i+'  '+label,13),r77Text(value,12,'Secondary'));add(ranking,line,r6Progress(w-34,ratio));}add(c,ranking);
    if(mobile)add(c,r77Button('导出当前统计','导出完成','Ghost','download',w));return c;
  },2);const screen=(mobile?registry.mobile:registry.desktop).Traffic;r77ClearHeaderActions(screen);r77Install(screen,lib.initial,'流量统计工作区');return lib;
}
async function r77Connections(){
  const w=1120,states=['全部','代理','直连','已暂停','搜索','无结果','关闭单条','确认关闭全部','全部关闭','导出完成'];
  const rows=[['api.github.com:443','代码编辑器','DOMAIN-SUFFIX','代理','4.2 MB','04:32'],['registry.npmjs.org:443','终端','DOMAIN-SUFFIX','代理','168.2 MB','02:18'],['developer.apple.com:443','浏览器','DOMAIN-SUFFIX','代理','12.4 MB','01:54'],['192.168.1.1:80','浏览器','IP-CIDR','直连','284 KB','00:41'],['docs.rs:443','代码编辑器','MATCH','代理','3.8 MB','00:26'],['api.openai.com:443','终端','DOMAIN','代理','1.2 MB','00:14']];
  const lib=r77Set('实时连接',states,false,key=>{
    const c=r77Body('实时连接',w),zero=key==='全部关闭';c.itemSpacing=16;add(c,add(row('连接指标',w,null,16),r77Metric('活跃连接',zero?'0':key==='关闭单条'?'141':'142',key==='已暂停'?'列表已暂停刷新':'每秒刷新',(w-32)/3),r77Metric('代理 / 直连',zero?'0 / 0':key==='关闭单条'?'127 / 14':'128 / 14','当前活跃连接',(w-32)/3),r77Metric('累计传输','2.84 GB','本次会话',(w-32)/3)));
    const search=r77Go(r77Field('连接筛选',key==='搜索'?'github':key==='无结果'?'不存在的域名':'搜索域名、进程或规则',360),key==='搜索'?'无结果':key==='无结果'?'全部':'搜索');
    const filters=r77Tabs(['全部','代理','直连'],['代理','直连'].includes(key)?key:'全部',252,false,'连接类型');filters.children.forEach((n,i)=>r77Go(n,['全部','代理','直连'][i]));
    const controls=row('连接操作',null,44,8);add(controls,filters,r77Button(key==='已暂停'?'继续刷新':'暂停刷新',key==='已暂停'?'全部':'已暂停','Secondary',null,108),r77Button('关闭全部','确认关闭全部','Secondary','close',120),r77Button('导出','导出完成','Secondary','download',92));add(c,r77Toolbar(w,search,controls));
    if(key==='已暂停')add(c,r77Note('已暂停列表刷新','连接仍在运行，继续刷新可查看最新数据。',w));
    if(key==='关闭单条')add(c,r77Note('已关闭所选连接','应用下次请求时会按规则重新建立连接。',w,'Success'));
    if(key==='导出完成')add(c,r77Note('连接快照已导出','已包含目标、进程、规则、出站与流量。',w,'Success'));
    if(key==='确认关闭全部')add(c,r77Note('关闭全部 142 条连接？','应用可能立即重连，VPN 状态保持开启。',w,'Warning'),add(row('关闭全部确认',w,44,12),r77Button('取消','全部','Secondary',null,120),r77Button('确认关闭','全部关闭','Primary',null,144)));
    let data=zero||key==='无结果'?[]:rows.filter((r,i)=>(key!=='关闭单条'||i!==0)&&(key==='代理'?r[3]==='代理':key==='直连'?r[3]==='直连':key==='搜索'?r[0].includes('github'):true));
    if(!data.length)add(c,r77Note(zero?'暂无活跃连接':'没有匹配的连接',zero?'新的网络请求会自动出现在这里。':'调整关键词，或清空筛选。',w),r77Button('清空筛选','全部','Secondary',null,144));
    else{const table=r77Table([['目标地址',280],['进程',160],['匹配规则',190],['出站',90],['流量',100],['操作',150]],data.map(r=>[r[0],r[1],r[2],r[3],r[4],'关闭']),w,'连接');for(const line of table.children.filter(n=>r5Name(n).startsWith('连接 · '))){line.children[5].visible=false;add(line,r77Button('关闭','关闭单条','Ghost','close',100));}add(c,table);}return c;
  },2);r77ClearHeaderActions(registry.desktop.Connections);r77Install(registry.desktop.Connections,lib.initial,'实时连接工作区');return lib;
}
async function r77Logs(){
  const w=1120,states=['全部','信息','警告','错误','搜索','无结果','暂停','确认清空','已清空','已导出'];
  const logs=[['10:42:18.023','信息','隧道已建立 · 东京 · 樱花'],['10:42:18.108','信息','订阅已载入 · 126 条规则 · 8 个节点'],['10:42:18.246','信息','DNS 解析器就绪 · fake-ip 已开启'],['10:42:19.504','信息','TCP · 代码编辑器 → api.github.com:443 · VLESS · 24 ms'],['10:42:21.811','警告','备用 · 韩国首尔 · 探测超时，已保留当前节点'],['10:42:23.054','信息','健康检查完成 · 8 个节点中 7 个在线'],['10:42:24.026','错误','备用订阅更新失败 · 请求超时，保留上次可用配置'],['10:42:29.158','信息','活跃连接 142 · 当前下载 12.8 MB/s']];
  const lib=r77Set('运行日志',states,false,key=>{
    const c=r77Body('运行日志',w);c.itemSpacing=16;const search=r77Go(r77Field('搜索日志',key==='搜索'?'DNS':key==='无结果'?'不存在的事件':'搜索事件或关键词',360),key==='搜索'?'无结果':key==='无结果'?'全部':'搜索'),tabs=r77Tabs(['全部','信息','警告','错误'],['信息','警告','错误'].includes(key)?key:'全部',320,false,'日志级别');tabs.children.forEach((n,i)=>r77Go(n,['全部','信息','警告','错误'][i]));
    const controls=row('日志操作',null,44,8);add(controls,tabs,r77Button(key==='暂停'?'继续':'暂停',key==='暂停'?'全部':'暂停','Secondary',null,80),r77Button('清空','确认清空','Secondary',null,80),r77Button('导出','已导出','Secondary','download',100));add(c,r77Toolbar(w,search,controls));
    if(key==='确认清空')add(c,r77Note('清空当前日志？','此操作只清空本地记录，不影响连接。',w,'Warning'),add(row('日志清空确认',w,44,12),r77Button('取消','全部','Secondary',null,100),r77Button('确认清空','已清空','Primary',null,144)));
    if(key==='已导出')add(c,r77Note('日志已导出','已隐藏订阅令牌、密码与认证信息。',w,'Success'));
    if(key==='暂停')add(c,r77Note('已暂停自动滚动','新事件仍在后台记录。',w));
    const data=['已清空','无结果'].includes(key)?[]:logs.filter(r=>['信息','警告','错误'].includes(key)?r[1]===key:key==='搜索'?r[2].includes('DNS'):true);
    if(!data.length)add(c,r77Note(key==='已清空'?'日志已清空':'未找到匹配日志','新的事件会继续记录，可清空筛选查看全部。',w),r77Button('查看全部','全部','Secondary',null,144));
    else add(c,r77Table([['时间',170],['级别',100],['事件',770]],data,w,'日志'));
    add(c,r77Text('日志保留 7 天 · 自动隐藏认证信息',12,'Muted',w));return c;
  },2);r77ClearHeaderActions(registry.desktop.Logs);r77Install(registry.desktop.Logs,lib.initial,'运行日志工作区');return lib;
}
async function r77NodeActions(mobile){
  const states=['未收藏','已收藏','菜单','已收藏菜单','编辑','订阅说明','删除确认','已删除','已保存'];
  const lib=r77Set('节点操作',states,mobile,key=>{
    const c=r77Body('节点操作',mobile?88:80);c.layoutMode='HORIZONTAL';c.primaryAxisSizingMode=c.counterAxisSizingMode='FIXED';c.resize(mobile?88:80,44);c.itemSpacing=0;c.clipsContent=false;
    const fav=key.startsWith('已收藏'),star=r77Button('',fav?'未收藏':'已收藏','Ghost','star',44),more=r77Button('',fav?'已收藏菜单':'菜单','Ghost','more',mobile?44:36);r6Name(star,'节点收藏');r6Name(more,'节点更多');if(fav){tint(star,'Primary');fill(star,'PrimarySurface');}add(c,star,more);
    if(['未收藏','已收藏'].includes(key))return c;
    const menu=borderCard('节点操作菜单',mobile?280:320,null,12,8,'Raised');rad(menu,12);stroke(menu);add(c,menu);menu.layoutPositioning='ABSOLUTE';menu.x=c.width-menu.width;menu.y=48;const iw=menu.width-26;
    if(key.includes('菜单'))add(menu,r6Text('当前节点',15,'Text','Medium'),r77Button('编辑手动节点','编辑','Ghost',null,iw),r77Button('查看订阅节点','订阅说明','Ghost',null,iw),r77Button('删除节点','删除确认','Ghost',null,iw),r77Button('收起','未收藏','Ghost',null,iw));
    else if(key==='编辑')add(menu,r77Back('编辑节点',iw,'菜单'),r77Field('名称','办公 HTTP',iw),r77Field('服务器','proxy.backup.example.com',iw),r77Field('端口','8080',iw),r77Button('保存修改','已保存','Primary',null,iw));
    else if(key==='订阅说明')add(menu,r77Back('订阅节点',iw,'菜单'),r77Text('订阅节点的连接参数跟随订阅更新。名称别名、收藏与隐藏状态保存在本地。',12,'Secondary',iw),r77Button('更新所属订阅',(mobile?registry.mobile:registry.desktop)['Subscription info · 主订阅'],'Secondary','refresh',iw,'OVERLAY'));
    else if(key==='删除确认')add(menu,r77Back('删除此节点？',iw,'菜单'),r77Text('手动节点会被删除；订阅节点只在本地隐藏，下次更新仍保持隐藏。',12,'Secondary',iw),r77Button('确认删除','已删除','Primary',null,iw));
    else add(menu,r77Note(key==='已保存'?'节点已保存':'节点已删除',key==='已保存'?'已保留所属分组与收藏状态。':'当前出站在断开前保持。',iw,'Success'),r77Button('完成','未收藏','Primary',null,iw));
    return c;
  },3);
  const master=masters['Group node / '+(mobile?'Mobile':'Desktop')],parent=uFind(master,mobile?'Node actions':'Node facts');
  const star=parent.children.find(n=>r5Name(n)==='节点收藏与菜单')||parent.children.find(n=>n.type==='INSTANCE'&&/^Button · |^按钮 · /.test(r5Name(n)));const index=star?parent.children.indexOf(star):parent.children.length;if(star)star.remove();parent.insertChild(index,r7Instance(lib.initial,'节点收藏与菜单'));
  if(mobile){const region=uFind(master,'节点地区');if(region)region.visible=false;const copy=uFind(master,'紧凑节点内容');if(copy){const name=uFind(copy,'节点名称');name.textAutoResize='TRUNCATE';name.maxLines=1;name.layoutSizingHorizontal='FILL';} }
  // Source and result instances retain their per-node values; new operations inherit the master.
  return lib;
}
async function r77PlatformControls(){
  const lib=r77Set('平台网络能力',['iOS · 已授权','iOS · 未授权','Android · 已授权','Android · 未授权'],true,key=>{
    const c=r77Body('平台网络能力',353);c.resize(353,56);c.primaryAxisSizingMode='FIXED';fill(c,'Surface');stroke(c);rad(c,12);c.layoutMode='HORIZONTAL';c.counterAxisAlignItems='CENTER';c.paddingLeft=c.paddingRight=12;c.itemSpacing=8;
    const label=add(v('系统 VPN 说明',245,3),r6Text('系统 VPN · '+(key.startsWith('iOS')?'iOS':'Android'),13,'Text','Medium'),r77Text('系统代理不可用 · 通过 VPN 隧道接管',12,'Muted',245));add(c,label,r6Badge(key.endsWith('未授权')?'待授权':'已授权',key.endsWith('未授权')?'Warning':'Success'));return c;
  },2);lib.set.description='移动端保留首页接管信息。iOS 使用 NetworkExtension，Android 使用 VpnService；均不提供桌面式全局系统代理。VPN 总开关在概览，首次连接触发系统授权。';return lib;
}
async function r77Homes(report,platformLib){
  const result={};
  for(const mobile of [false,true]){
    const platform=mobile?'mobile':'desktop',ui=report.compactCanvas.homeStates[platform],set=await figma.getNodeByIdAsync(ui.set),states={};for(const [key,id]of Object.entries(ui.states))states[key]=await figma.getNodeByIdAsync(id);
    const extra=['连接详情','检测中','连接失败','连接超时','需要授权','授权拒绝','首次使用'];
    for(const key of extra){const old=set.children.find(n=>n.name==='连接='+key);if(old)old.remove();const c=states[key==='连接详情'?'开启':'关闭'].clone();set.appendChild(c);r6Name(c,'连接='+key);await r7Clear(c);states[key]=c;}
    for(const key of extra){const c=states[key];
      const feedback={连接详情:['连接正常','当前出站：东京 · 樱花 · VLESS · 24 ms','Info'],检测中:['正在检测链路','检查本地网络、节点握手和出口连通性…','Info'],连接失败:['无法建立连接','节点握手失败。已保留当前选择，可重试或更换节点。','Error'],连接超时:['连接超时','节点未在 10 秒内响应。请检查网络或更换节点。','Error'],需要授权:['允许系统 VPN',mobile?'连接需要系统 VPN 授权，RainLink 将在确认后请求系统许可。':'TUN 模式需要网络适配器权限，请允许系统授权。','Info'],授权拒绝:['未获得 VPN 权限','请重新授权后再连接，或在系统设置中允许 RainLink。','Warning'],首次使用:['添加第一个节点','订阅自动成组，单个节点进入未分组。','Info']}[key];
      const note=r77Note(...[feedback[0],feedback[1],mobile?353:1120,feedback[2]]);c.insertChild(1,note);
      const actions=row('连接反馈操作',mobile?353:1120,44,8);add(c,actions);
      const go=(label,to,tone='Secondary',ic=null)=>add(actions,r77Button(label,to,tone,ic,mobile?((353-8)/2):160));
      if(key==='连接详情'){go('检查链路',states['检测中']);go('关闭详情',states['开启']);}
      else if(key==='检测中')go('取消检测',states['开启']);
      else if(['连接失败','连接超时'].includes(key)){go('重试连接',states['连接中'],'Primary','refresh');go('更换节点',(mobile?registry.mobile:registry.desktop).Nodes,'Secondary','nodes');r77Edges[r77Edges.length-1].nav='NAVIGATE';}
      else if(key==='需要授权'){go('允许 VPN',states['连接中'],'Primary','shield');go('暂不允许','授权拒绝');}
      else if(key==='授权拒绝'){go('重新授权',states['需要授权'],'Primary');go('取消',states['关闭']);}
      else if(key==='首次使用'){go('添加',(mobile?registry.mobile:registry.desktop)['Import profile'],'Primary','plus');r77Edges[r77Edges.length-1].nav='OVERLAY';}
      if(!['连接详情','检测中','首次使用'].includes(key))for(const t of c.findAll(n=>n.type==='TEXT'))if(['VPN 已关闭','点按开启 VPN','等待连接'].includes(t.characters))r6Copy(t,t.characters==='VPN 已关闭'?feedback[0]:'检查网络后重试');
      const power=c.findOne(n=>n.getPluginData('rainlink-control-kind')==='vpn-power');if(power&&key!=='首次使用')r77Go(power,states[mobile&&['需要授权','授权拒绝'].includes(key)?'需要授权':'连接中']);
    }
    // Resolve references to variants created later in the same loop.
    for(const e of r77Edges)if(typeof e.to==='string'&&states[e.to])e.to=states[e.to];
    for(const [key,c]of Object.entries(states)){
      if(mobile){const old=uFind(c,'首页网络接管')||uFind(c,'首页平台网络接管');if(old){const p=old.parent,i=p.children.indexOf(old);old.remove();p.insertChild(i,r7Instance(platformLib.variants[key==='需要授权'||key==='授权拒绝'?'iOS · 未授权':'iOS · 已授权'],'首页平台网络接管'));}}
      const summary=uFind(c,mobile?'Connection summary':'Connection group hero');
      const hero=uFind(c,mobile?'VPN control':'Connection group hero'),copy=mobile?uFind(hero,'连接状态摘要'):null;
      if(copy&&['开启','关闭'].includes(key)){const caption=copy.children.find(n=>n.type==='TEXT'&&n.fontSize<18);if(caption)r6Copy(caption,'连接详情 ›');r77Go(copy,states['连接详情']);}
      if(!mobile&&['开启','关闭'].includes(key)){const old=uFind(c,'概览连接详情');if(old)old.remove();const line=row('概览连接详情',1120,32,8);add(line,r77Go(r6Text('连接详情 ›',13,'Muted','Regular',1120),states['连接详情']));add(c,line);}
      if(mobile&&key==='关闭'){const power=c.findOne(n=>n.getPluginData('rainlink-control-kind')==='vpn-power');r77Go(power,states['需要授权']);}
      if(!['开启','连接中','断开中'].includes(key))for(const t of c.findAll(n=>n.type==='TEXT'))if(t.characters==='12.8'||t.characters==='1.4')r6Copy(t,'0');
    }
    await states['检测中'].setReactionsAsync(r7Timer(states['连接超时'].id));
    // Failure is reached from a timed-out handshake; retry returns to the normal connection flow.
    const timeout=states['连接超时'],retry=uFind(timeout,'按钮 · 重试连接');if(retry)r77Go(retry,states['连接失败']);
    const maxW=Math.max(...set.children.map(n=>n.width)),maxH=Math.max(...set.children.map(n=>n.height));set.children.forEach((n,i)=>{n.x=24+(i%2)*(maxW+32);n.y=24+Math.floor(i/2)*(maxH+40);});set.resize(48+2*(maxW+32)-32,48+Math.ceil(set.children.length/2)*(maxH+40)-40);
    result[platform]={set:set.id,states:Object.fromEntries(Object.entries(states).map(([k,v])=>[k,v.id]))};
  }return result;
}
async function r77Consistency(report){
  for(const screen of Object.values(registry.desktop)){
    const bar=screen.findOne(n=>n.type==='FRAME'&&(r5Name(n)==='Top status bar'||n.name==='连接状态栏'));
    if(bar)for(const t of bar.findAll(n=>n.type==='TEXT')){const s=t.characters;if(s==='未连接')r6Copy(t,'已连接 · 东京 · 樱花');if(/↓\s*0\s*MB\/s/.test(s))r6Copy(t,'↓ 12.8 MB/s');if(/↑\s*0\s*MB\/s/.test(s))r6Copy(t,'↑ 1.4 MB/s');}
  }
  // The Nodes tab is a top-level destination, so it has no fixed Profiles back link.
  const header=uFind(registry.mobile.Nodes,'Page header');
  if(header){const left=header.children[0];if(left?.type==='INSTANCE')left.remove();header.itemSpacing=8;header.primaryAxisAlignItems='SPACE_BETWEEN';const title=header.children.find(n=>n.type==='FRAME');if(title){title.resize(293,title.height);for(const t of title.findAll(n=>n.type==='TEXT')){t.resize(293,t.height);t.textAutoResize='HEIGHT';}}}
  // Remove the second group-selection action in each desktop overview variant.
  const home=await figma.getNodeByIdAsync(report.compactCanvas.homeStates.desktop.set);
  for(const c of home.children){const actions=c.findAll(n=>n.type==='INSTANCE'&&n.findAll(t=>t.type==='TEXT').length===1&&n.findAll(t=>t.type==='TEXT')[0].characters==='选择分组');for(const n of actions.slice(1))n.visible=false;
    const trends=uFind(c,'Connection trends'),chart=trends?.children[0];if(chart&&!chart.findOne(n=>r5Name(n)==='延迟单位')){const text=r6Name(r77Text('延迟 · ms',12,'Muted'),'延迟单位');add(chart,text);text.layoutPositioning='ABSOLUTE';text.x=16;text.y=chart.height-24;}
    if(!uFind(c,'Recent connection record')&&!uFind(c,'最近连接记录')){const recent=between(row('最近连接记录',1120,44,12));add(recent,r77Text('最近连接',12,'Muted'),r77Text('api.github.com · 主订阅 · 24 ms',13,'Secondary'),r77Button('查看全部',registry.desktop.Connections,'Ghost','connections',120,'NAVIGATE'));add(c,recent);}
  }
  // Mobile update wording follows the installation source rather than assuming one store.
  const section=await figma.getNodeByIdAsync(report.settingsUI.section);
  for(const t of section.findAll(n=>n.type==='TEXT'&&/App Store/.test(n.characters))){r6Copy(t,t.characters.replace(/前往 App Store/g,'打开安装来源').replace(/App Store/g,'安装来源'));}
  return {defaultScenario:'VPN 开启 / 规则 / 主订阅 / 东京 · 樱花 / 24 ms / 下载 12.8 MB/s / 上传 1.4 MB/s',mobileTopLevelBackRemoved:true,proxyControls:'概览',selectionOnly:true};
}
async function r77ReadableAndHits(report){
  const changed=[];const mobileRoots=[mobilePage,...dsPage.findAll(n=>(n.type==='COMPONENT_SET'||n.type==='COMPONENT')&&/移动端|Mobile/.test(r5Name(n)))];
  const seen=new Set();for(const root of mobileRoots)for(const n of [root,...root.findAll(()=>true)]){
    if(seen.has(n.id))continue;seen.add(n.id);
    // Edit source nodes once. Traversing every nested instance creates thousands
    // of overrides and makes the Figma editor unresponsive.
    let inherited=false;for(let a=n.parent;a&&a!==root;a=a.parent)if(a.type==='INSTANCE'){inherited=true;break;}if(inherited)continue;
    if(n.type==='TEXT'&&typeof n.fontSize==='number'&&n.fontSize<12&&n.characters.trim()){
      n.fontName={family:zhFamily,style:zhStyles.Regular};n.fontSize=12;const line=n.lineHeight;if(line.unit==='PIXELS'&&line.value<16)n.lineHeight={unit:'PIXELS',value:16};changed.push(n.id);
    }
    if(!('reactions'in n)||!n.reactions.length||!('resize'in n)||n.type==='TEXT'||n.width>=44&&n.height>=44)continue;
    const name=r5Name(n);
    if(name.startsWith('出口模式 · ')){
      n.resize(n.width,44);const tabs=n.parent;if(tabs.height<44){const delta=44-tabs.height;tabs.resize(tabs.width,44);const card=tabs.parent;if(card.primaryAxisSizingMode==='FIXED')card.resize(card.width,card.height+delta);}
    }else if(name.startsWith('选择节点分组 · ')){
      n.resize(Math.max(44,n.width),44);n.parent.resize(n.parent.width,44);
    }else if(n.type==='INSTANCE'&&n.width<44){n.resize(44,Math.max(44,n.height));n.primaryAxisSizingMode=n.counterAxisSizingMode='FIXED';n.paddingLeft=n.paddingRight=0;}
    else if(n.type==='INSTANCE'||n.type==='FRAME'){n.resize(Math.max(n.width,44),Math.max(n.height,44));if(n.layoutMode==='HORIZONTAL')n.counterAxisSizingMode='FIXED';}
  }
  // Parent chip strips reserve the full hit height without increasing node-card heights.
  for(const set of dsPage.findAll(n=>n.type==='COMPONENT_SET'&&/移动端 \/ 节点选择$/.test(r5Name(n))))for(const c of set.children){const strip=uFind(c,'节点分组选项');if(strip)strip.resize(strip.width,44);}
  const mobileHeader=uFind(registry.mobile.Home,'Page header');if(mobileHeader)for(const b of mobileHeader.children.filter(n=>n.type==='INSTANCE'))b.resize(Math.max(44,b.width),44);
  return {minimumReadableSize:12,mobileHitMinimum:44,textLayersUpdated:changed.length,compactNodeHeight:72,transparentOrExistingContainers:true};
}
function r77Contract(){
  const c=borderCard('状态与平台交付约定',1120,null,24,16,'Surface');add(c,r6Text('状态、平台与布局约定',26,'Text','Medium'));
  const notes=[
    ['选择与连接','selectedTarget（所选分组、节点或链）与 activeOutbound（实际出站）分别保存。选择只更新 selectedTarget；已连接时显示“待应用”，原出站保持。在概览关闭再开启 VPN 才应用新选择；代理模式也只在概览设置。'],
    ['跨页与持久化','运行时由统一状态仓库驱动所有页面；每组记住上次选中的节点。Figma Starter 使用局部变体与一致的默认示例，不支持跨页面的实时全局状态。代理链保存结果在同一组件呈现返回节点后的选中反馈。'],
    ['自动归组','订阅由服务名称自动成组，缺失名称时用域名或自动编号；单个节点进入未分组。仅未分组节点可移动，移入订阅后更新保留手动节点。删除订阅会把手动节点退回未分组。'],
    ['节点管理','手动节点可编辑连接参数、收藏、删除。订阅节点只允许别名、收藏和本地隐藏，连接参数随订阅同步；隐藏不会在下次更新后恢复。删除正在使用的节点时，现有会话在断开前保持。'],
    ['桌面平台','Windows、macOS、Linux 在概览提供系统代理与 TUN 两个独立选项。TUN 按平台请求适配器或管理员权限；平台不可用时禁用并说明原因。权限失败不静默开启。'],
    ['移动平台','iOS 使用 NetworkExtension，Android 使用 VpnService。首次连接先请求系统 VPN 授权；拒绝后保留选择并提供重新授权。移动端没有桌面式系统代理开关，TUN 能力通过系统 VPN 接管，VPN 总开关保留在概览。'],
    ['安装来源','iOS 按 App Store / TestFlight 更新。Android 按 Google Play、应用商店或独立安装包更新，商店版打开原商店，独立安装提示下载后安装。不会在商店版中展示桌面式原位替换。'],
    ['异常与首次使用','无节点时显示首次使用状态与添加入口，禁用 VPN 按钮。订阅地址错误就地提示；超时保留链接并可重试。连接失败保留所选目标，正在建立连接时允许取消；授权拒绝不继续连接。'],
    ['弹窗与键盘','移动弹窗上限随可用高度变化。键盘出现时正文缩为可滚动区域，固定操作栏位于键盘上方；底部保留系统安全区。长名称单行省略，详情显示完整内容；IP 地址允许两行，不破坏国家图标与刷新命中区。'],
    ['响应式与大字','桌面 1100–1440：侧栏保持 216 px，内容列使用 Fill；低于 1100 收为图标侧栏。移动 360–430：左右边距 16–20 px，列表宽度 Fill，按钮命中不小于 44 px。大字模式辅助文字至少 14 px，卡片随内容增长。'],
    ['图表与导出','今日流量曲线单位 MB/s，周/月按日汇总为 GB。点击或悬停显示时间与上传/下载值。原型导出仅演示 UI 反馈，不创建真实 CSV 或日志；真实导出先隐藏认证信息。']
  ];for(const [label,text]of notes)add(c,r6Text(label,15,'Text','Medium'),r77Text(text,13,'Secondary',1070));r77Place(c);return c;
}
function r77Reflow(n,w){
  if(!('children'in n)||n.type==='VECTOR')return;
  const before=n.width;
  if(n.layoutMode&&n.layoutMode!=='NONE'){
    if(n.layoutMode==='HORIZONTAL')n.primaryAxisSizingMode='FIXED';else n.counterAxisSizingMode='FIXED';
  }
  if('resize'in n&&w>0&&Math.abs(before-w)>.1)n.resize(w,n.height);
  if(!n.layoutMode||n.layoutMode==='NONE'||/^Icon \/|图标 \/|国家图标/.test(n.name))return;
  if(/^按钮 ·|^刷新出口$/.test(n.name)){
    for(const t of n.children.filter(c=>c.type==='TEXT'))t.textAutoResize='WIDTH_AND_HEIGHT';
    return;
  }
  const cs=n.children.filter(c=>c.visible&&c.layoutPositioning!=='ABSOLUTE'),inner=n.width-(n.paddingLeft||0)-(n.paddingRight||0);
  if(n.layoutMode==='VERTICAL'){
    for(const c of cs){if(c.width>inner||Math.abs(c.width-before+(n.paddingLeft||0)+(n.paddingRight||0))<4){if(c.type==='TEXT'){c.resize(inner,c.height);c.textAutoResize='HEIGHT';}else r77Reflow(c,inner);}}
  }else{
    const total=cs.reduce((s,c)=>s+c.width,0)+(n.itemSpacing||0)*Math.max(0,cs.length-1),delta=Math.max(0,total-inner),flex=cs.filter(c=>c.width>100&&!/^按钮 ·|^刷新出口$/.test(c.name)),room=flex.reduce((s,c)=>s+Math.max(0,c.width-80),0);
    for(const c of flex){const next=Math.max(80,c.width-(room?delta*(c.width-80)/room:0));if(c.type==='TEXT'){c.resize(next,c.height);c.textAutoResize='HEIGHT';}else r77Reflow(c,next);}
  }
}
function r77AlignOverview(c){
  const metrics=uFind(c,'Network stats')||uFind(c,'Network metrics')||c.findOne(n=>n.name==='网络统计'),trends=uFind(c,'Connection trends');
  if(!metrics||!trends||metrics.children.length!==3||trends.children.length!==2)return;
  const quality=metrics.children[2],gap=metrics.itemSpacing,health=trends.children[1],chart=trends.children[0];
  // The lower row spans the same three-column grid as the metrics above it.
  // Read the actual third-column width so narrower previews stay aligned too.
  trends.itemSpacing=gap;
  r77Reflow(chart,metrics.width-quality.width-gap);
  r77Reflow(health,quality.width);
  trends.resize(metrics.width,trends.height);
}
function r77Preview(source,name,w,h,light=false,big=false,edge=false){
  const clone=source.clone();clone.setPluginData('rainlink','');const c=figma.createComponentFromNode(clone);r6Name(c,name);r77Mark(c);c.setPluginData('rainlink-review-preview','1');dsPage.appendChild(c);c.resize(w,h);
  // Boundary specimens are editable component snapshots. Detach nested source
  // instances before reflow: inherited fixed dimensions cannot be resized.
  const detach=n=>{for(const child of [...n.children||[]]){const item=child.type==='INSTANCE'?child.detachInstance():child;if('children'in item)detach(item);}};detach(c);
  for(const t of c.findAll(n=>n.type==='TEXT'))t.fontName={family:zhFamily,style:zhStyles.Regular};
  if(w<600){r77Reflow(c,w);}else{
    const side=c.children[0],main=c.children[1];if(side)r77Reflow(side,216);if(main){main.resize(w-216,h);r77Reflow(main,w-216);}
  }
  if(w<600){const nav=uFind(c,'Mobile / Bottom navigation');if(nav){nav.resize(w,80);nav.children.forEach(t=>{t.layoutSizingHorizontal='FILL';});}}
  if(big)for(const t of c.findAll(n=>n.type==='TEXT'&&typeof n.fontSize==='number'&&n.fontSize<14)){t.fontName={family:zhFamily,style:zhStyles.Regular};t.fontSize=14;t.lineHeight={unit:'PIXELS',value:20};}
  if(edge)for(const t of c.findAll(n=>n.type==='TEXT')){
    if(t.characters==='东京 · 樱花'){r6Copy(t,'日本东京 · 开发环境备用高速节点');t.textAutoResize='TRUNCATE';t.maxLines=1;}
    if(t.characters==='203.0.113.24'){r6Copy(t,'2001:db8:85a3::8a2e:370:7334');t.fontSize=13;t.resize(Math.min(224,t.width),38);t.textAutoResize='HEIGHT';}
  }
  if(w>=600)r77AlignOverview(c);
  if(light)applyLight(c);r77Place(c);return c;
}
function r77Extensions(report){
  for(const n of dsPage.findAll(n=>n.type==='COMPONENT'&&(n.getPluginData('rainlink-review-preview')==='1'||n.name==='验收 · 键盘与弹窗滚动')))n.remove();
  const previews={};
  previews.lightDesktop=r77Preview(registry.desktop.Dashboard,'验收 · 浅色概览 · 1100',1100,900,true).id;
  previews.smallMobile=r77Preview(registry.mobile.Home,'验收 · 小屏浅色 · 360',360,780,true).id;
  previews.largeText=r77Preview(registry.mobile.Home,'验收 · 大字与长名称 IPv6',393,852,false,true,true).id;
  const addLib=r77Libs['M/添加'],keyboard=r77Body('验收 · 键盘与弹窗滚动',393),dialog=addLib.variants['VLESS · 更多'].createInstance().detachInstance();keyboard.setPluginData('rainlink-review-preview','1');add(keyboard,dialog);const scroll=uFind(dialog,'表单滚动区');scroll.primaryAxisSizingMode='FIXED';scroll.resize(scroll.width,200);dialog.primaryAxisSizingMode='AUTO';
  const kb=borderCard('系统键盘占位',393,210,12,10,'Raised');for(const letters of [['Q','W','E','R','T','Y','U','I','O','P'],['A','S','D','F','G','H','J','K','L'],['⇧','Z','X','C','V','B','N','M','⌫']]){const line=center(row('键盘行',369,40,4));for(const s of letters)add(line,center(add(rad(row('键帽',30,40,0,0,'Surface'),5),r77Text(s,14))));add(kb,line);}add(keyboard,kb);r77Place(keyboard);previews.keyboard=keyboard.id;
  return {previews,productFramesAdded:0,sizes:{narrowDesktop:[1100,900],smallMobile:[360,780],largeText:[393,852]},keyboardViewport:200,theme:'real core components with light color bindings',boundary:'Representative reflow previews; runtime layout and OS keyboard behavior still require implementation testing.'};
}
async function r77Wire(){
  const latest=new Map();for(const edge of r77Edges)latest.set(edge.n.id,edge);
  let count=0;for(const edge of latest.values()){if(edge.n.removed)continue;if(typeof edge.to==='string')throw new Error('未解析修复状态 '+edge.to+' / '+r5Name(edge.n));
    let owner=edge.n;while(owner&&owner.type!=='COMPONENT')owner=owner.parent;
    if(edge.nav==='CHANGE_TO'&&owner===edge.to)continue;
    const actions=edge.close?[{type:'CLOSE'}]:[{type:'NODE',destinationId:edge.to.id,navigation:edge.nav,transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18},preserveScrollPosition:false,resetInteractiveComponents:false}];
    try{await edge.n.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions}]);}catch(e){throw new Error(r5Name(edge.n)+' ['+edge.n.id+'] → '+(edge.to?r5Name(edge.to):'关闭')+' ['+edge.nav+']: '+String(e));}count++;if(count%100===0)await r5Yield();
  }return count;
}
function r77LibraryGeometry(){
  const live=new Set(Object.values(r77Libs).map(v=>v.set.id));for(const n of [...r77Section.children])if(n.type==='COMPONENT_SET'&&!live.has(n.id))n.remove();
  for(const lib of Object.values(r77Libs)){
    const cs=lib.set.children,cols=Math.min(3,cs.length),left=Math.max(0,...cs.flatMap(c=>c.children.filter(n=>n.visible&&n.layoutPositioning==='ABSOLUTE').map(n=>-n.x))),w=Math.max(...cs.map(c=>Math.max(c.width,...c.children.filter(n=>n.visible).map(n=>n.x+n.width))))+left,h=Math.max(...cs.map(c=>Math.max(c.height,...c.children.filter(n=>n.visible).map(n=>n.y+n.height))));
    cs.forEach((c,i)=>{c.x=24+left+i%cols*(w+32);c.y=24+Math.floor(i/cols)*(h+40);});lib.set.resize(48+cols*(w+32)-32,48+Math.ceil(cs.length/cols)*(h+40)-40);
  }
  const nodes=[...r77Section.children];r77X=24;r77Y=96;r77H=0;nodes.forEach(r77Place);r77Section.resizeWithoutConstraints(6050,r77Y+r77H+32);
}
async function r77LocalLibraries(report){
  const result={};
  for(const mobile of [false,true]){
    const page=mobile?mobilePage:desktopPage,prefix=mobile?'M/':'D/',name='原型组件 · '+(mobile?'移动端':'桌面端')+' · 局部状态',existing=page.children.find(n=>n.type==='SECTION'&&r5Name(n)===name),section=existing||figma.createSection();
    page.appendChild(section);r6Name(section,name);section.x=10000;section.y=1000;section.fills=[paint('Background')];
    const sets=Object.entries(r77Libs).filter(([k])=>k.startsWith(prefix)).map(([,v])=>v.set);sets.push(await figma.getNodeByIdAsync(report.compactCanvas.homeStates[mobile?'mobile':'desktop'].set));
    let x=24,y=96,h=0;for(const set of sets){if(x+set.width>6000&&x>24){x=24;y+=h+64;h=0;}section.appendChild(set);set.x=x;set.y=y;x+=set.width+48;h=Math.max(h,set.height);}section.resizeWithoutConstraints(6050,y+h+32);result[mobile?'mobile':'desktop']=section.id;
  }return result;
}
async function r77Verify(report){
  const errors=[],check=(ok,msg)=>{if(!ok)errors.push(msg);},scan={};
  check(figma.root.children.length===3,'页签数量改变');check(Object.keys(registry.desktop).length===12&&Object.keys(registry.mobile).length===11,'产品画面数量改变');
  for(const reg of [registry.desktop,registry.mobile])check(Object.values(reg).every(n=>n.layoutMode!=='NONE'),'产品画面缺少 Auto Layout');
  for(const mobile of [false,true]){
    const p=mobile?'M/':'D/',lib=r77Libs[p+'添加'];for(const protocol of R77_PROTOCOLS){check(!!lib.variants[protocol],'缺少协议 '+p+protocol);const selector=uFind(lib.variants[protocol],'协议选择器');check(selector?.reactions.length>0,'协议选择不可用 '+p+protocol);}
    check(lib.variants['获取失败'].findOne(n=>n.type==='INSTANCE'&&r5Name(n)==='按钮 · 重试')?.reactions.length>0,'订阅重试未接入');
    const chain=r77Libs[p+'代理链'];check(uFind(chain.variants['测试通过'],'按钮 · 保存并选中')?.reactions.some(r=>r.actions.some(a=>a.destinationId===chain.variants['已选中'].id)),'代理链没有保存选中反馈');
    check(!registry[mobile?'mobile':'desktop']['Chain editor'].findOne(n=>n.type==='TEXT'&&/保存并连接/.test(n.characters)),'代理链仍自动连接');
  }
  for(const key of ['D/分流规则','D/实时连接','D/流量统计','D/运行日志','M/流量统计'])check(r77Libs[key].initial.findAll(n=>'reactions'in n&&n.reactions.length).length>0,'工具业务未接入 '+key);
  const overviewGrid=[];
  for(const id of [...Object.values(report.reviewFix.homes.desktop.states),report.reviewFix.extensions.previews.lightDesktop]){
    const c=await figma.getNodeByIdAsync(id),metrics=uFind(c,'Network stats')||uFind(c,'Network metrics')||c.findOne(n=>n.name==='网络统计'),trends=uFind(c,'Connection trends');
    if(!metrics||!trends||!metrics.visible||!trends.visible)continue;
    const quality=metrics.children[2],health=trends.children[1],delta=Math.abs(metrics.x+quality.x-trends.x-health.x),widthDelta=Math.abs(quality.width-health.width);
    overviewGrid.push({id,name:c.name,width:metrics.width,gap:trends.itemSpacing,qualityX:metrics.x+quality.x,healthX:trends.x+health.x,delta,widthDelta});
    check(delta<.1&&widthDelta<.1&&metrics.itemSpacing===trends.itemSpacing,'概览右侧卡片未对齐 '+c.name);
  }
  report.reviewFix.overviewGrid={verified:true,states:overviewGrid};
  const small=[];for(const screen of Object.values(registry.mobile))for(const n of screen.findAll(n=>'reactions'in n&&n.reactions.length)){
    let visible=true;for(let a=n;a&&a!==screen;a=a.parent)if(!a.visible)visible=false;if(visible&&(n.width<43.9||n.height<43.9))small.push({id:n.id,name:r5Name(n),width:n.width,height:n.height});
  }
  for(const [p,page]of [['desktop',desktopPage],['mobile',mobilePage],['system',dsPage]]){
    const nodes=[page,...page.findAll(()=>true)],destinations=new Set(),connections=[];for(const n of nodes)if('reactions'in n&&n.reactions.length){connections.push(n);for(const r of n.reactions)for(const a of r.actions||[])if(a.destinationId)destinations.add(a.destinationId);}
    const unresolved=[];for(const id of destinations)if(!(await figma.getNodeByIdAsync(id)))unresolved.push(id);check(!unresolved.length,'存在失效目标 '+p);scan[p]={nodesScanned:nodes.length,connectedNodes:connections.length,unresolved,unscannedScreens:[]};
  }
  report.reviewFixVerification={verifiedAt:new Date().toISOString(),errors,smallMobileTargets:small,prototype:scan,productScreens:23,pageCount:3,protocols:R77_PROTOCOLS};report.livePrototypeVerification={status:'verified',verifiedAt:new Date().toISOString(),...scan};
  if(errors.length)throw new Error(errors.join('；'));
}
function r77AuditDocument(){
  const overflow=[],untranslatedDisplayCopy=[];
  for(const screen of [...Object.values(registry.desktop),...Object.values(registry.mobile)])for(const n of screen.findAll(()=>true)){
    let hidden=false;for(let a=n;a&&a!==screen.parent;a=a.parent)if('visible'in a&&!a.visible){hidden=true;break;}if(hidden)continue;
    if(n.type==='TEXT'&&/[a-zA-Z]{3,}/.test(n.characters)&&!/[\u3400-\u9fff]/.test(n.characters)&&!isTechnicalText(n.characters))untranslatedDisplayCopy.push({id:n.id,text:n.characters});
    if(!['FRAME','INSTANCE'].includes(n.type)||!n.layoutMode||n.layoutMode==='NONE'||n.primaryAxisSizingMode!=='FIXED')continue;
    if(r5Name(n)==='Scrollable content'||/^Icon \/|国家图标/.test(r5Name(n))||n.clipsContent&&n.overflowDirection==='VERTICAL')continue;
    const children=n.children.filter(c=>c.visible&&c.layoutPositioning!=='ABSOLUTE');if(!children.length)continue;
    const vertical=n.layoutMode==='VERTICAL',edge=Math.max(...children.map(c=>vertical?c.y+c.height:c.x+c.width)),size=vertical?n.height:n.width;
    if(edge>size+2)overflow.push({screen:screen.name,id:n.id,name:n.name,axis:vertical?'vertical':'horizontal',amount:Math.round(edge-size)});
  }return {overflow,untranslatedDisplayCopy};
}
async function r77FinalPolish(report){
  const homeHeader=uFind(registry.desktop.Dashboard,'Page header');if(homeHeader)for(const n of homeHeader.children.filter(n=>n.type==='INSTANCE'))if(n.findAll(t=>t.type==='TEXT').some(t=>t.characters==='选择分组'))n.visible=false;
  for(const mobile of [false,true]){
    const home=report.reviewFix.homes[mobile?'mobile':'desktop'],set=await figma.getNodeByIdAsync(home.set);
    if(!mobile&&!home.states['延迟选点']){
      const selected=(await figma.getNodeByIdAsync(home.states['开启'])).clone();set.appendChild(selected);r6Name(selected,'连接=延迟选点');home.states['延迟选点']=selected.id;
      const chart=uFind(selected,'Connection trends')?.children[0];
      if(chart){
        const marker=row('延迟选点指示线',1,82,0,0,'Primary');add(chart,marker);marker.layoutPositioning='ABSOLUTE';marker.x=Math.round(chart.width*.62);marker.y=50;marker.opacity=.5;
        const tip=borderCard('延迟选点浮层',164,null,10,3,'Raised');add(tip,r77Text('10:20',12,'Muted'),r77Text('延迟 24 ms',14,'Primary'),r77Text('抖动 2 ms · 无丢包',12,'Secondary'));add(chart,tip);tip.layoutPositioning='ABSOLUTE';tip.x=Math.min(chart.width-180,Math.round(chart.width*.62)+12);tip.y=38;
        await chart.setReactionsAsync(r7Click(home.states['开启']));
      }
      const plain=await figma.getNodeByIdAsync(home.states['开启']),target=uFind(plain,'Connection trends')?.children[0];if(target)await target.setReactionsAsync(r7Click(selected.id));
      const maxW=Math.max(...set.children.map(n=>n.width)),maxH=Math.max(...set.children.map(n=>n.height));set.children.forEach((n,i)=>{n.x=24+i%2*(maxW+32);n.y=24+Math.floor(i/2)*(maxH+40);});set.resize(48+2*(maxW+32)-32,48+Math.ceil(set.children.length/2)*(maxH+40)-40);
    }
    for(const c of set.children){
      const old=uFind(c,'概览连接详情');if(old)old.remove();
      if(mobile){
        for(const b of c.findAll(n=>n.type==='INSTANCE'&&n.findAll(t=>t.type==='TEXT').some(t=>t.characters==='选择')))if(b.height<44)b.resize(b.width,44);
        if(c.id===home.states['开启']){const summary=uFind(c,'连接状态摘要');if(summary){const text=summary.findOne(n=>n.type==='TEXT'&&/点按关闭/.test(n.characters));if(text)r6Copy(text,'连接详情 ›');if(summary.height<44)summary.resize(summary.width,44);await summary.setReactionsAsync(r7Click(home.states['连接详情']));}}
      }else{
        r77AlignOverview(c);
        c.itemSpacing=6;
        const recent=uFind(c,'最近连接记录');if(recent){recent.resize(recent.width,36);for(const b of recent.children.filter(n=>n.type==='INSTANCE'))b.resize(b.width,36);}
        if(c.id===home.states['开启']){
          const footer=c.findOne(n=>n.type==='FRAME'&&n.children.some(t=>t.type==='TEXT'&&/^当前连接/.test(t.characters)));
          if(footer){const t=footer.children.find(t=>t.type==='TEXT'&&/^当前连接/.test(t.characters)),i=footer.children.indexOf(t);t.remove();const b=r6Button('连接详情 · 24 ms','Ghost',null,180);b.resize(180,36);footer.insertChild(i,b);await b.setReactionsAsync(r7Click(home.states['连接详情']));}
          for(const b of c.findAll(n=>n.name==='按钮 · 连接详情 · 24 ms'))for(const t of b.findAll(n=>n.type==='TEXT'))t.textAutoResize='WIDTH_AND_HEIGHT';
          for(const b of c.findAll(n=>n.name==='按钮 · 连接详情 · 24 ms'))for(const sibling of b.parent.children)if(sibling.type==='TEXT'&&sibling.characters==='24 ms')sibling.visible=false;
        }
      }
      if(c.id===home.states['首次使用']){
        for(const t of c.findAll(n=>n.type==='TEXT')){if(t.characters==='主订阅')r6Copy(t,'尚未选择节点');if(t.characters==='东京 · 樱花')r6Copy(t,'先添加订阅或单个节点');if(t.characters==='点按开启 VPN')r6Copy(t,'添加节点后即可连接');if(t.characters==='VPN 已关闭')r6Copy(t,'尚未就绪');}
        for(const name of mobile?['Connection summary','概览出口与模式','Mobile live speed','Today traffic']:['Network metrics','Connection trends','最近连接记录']){const n=uFind(c,name);if(n)n.visible=false;}
        const emptyOnly=new Set(mobile?['当前连接分组','今日流量','概览出口与模式','实时速度']:['网络统计','网络趋势','最近连接记录','首页网络接管','概览出口与模式']);
        for(const child of c.children)if(emptyOnly.has(child.name))child.visible=false;
        if(!mobile){const footer=c.findOne(n=>n.name==='连接卡片底栏');if(footer)footer.visible=false;}
        const power=c.findOne(n=>n.getPluginData('rainlink-control-kind')==='vpn-power');if(power){power.opacity=.35;await power.setReactionsAsync([]);}
        const platform=uFind(c,'首页平台网络接管');if(platform)for(const t of platform.findAll(n=>n.type==='TEXT'&&n.characters==='已授权'))r6Copy(t,'待授权');
      }
    }
  }
  const traffic=r77Libs['D/流量统计'];for(const c of Object.values(traffic.variants)){
    c.itemSpacing=12;
    for(const m of c.findAll(n=>n.type==='FRAME'&&['总流量','已下载','已上传'].includes(r5Name(n))))m.paddingTop=m.paddingBottom=12;
    const chart=uFind(c,'流量趋势图');if(chart)chart.paddingTop=chart.paddingBottom=16;
    const ranking=uFind(c,'使用排行');if(ranking&&ranking.type!=='TEXT'){ranking.itemSpacing=6;ranking.paddingTop=ranking.paddingBottom=14;}
  }
  const nav=uFind(registry.mobile.Profiles,'Mobile / Bottom navigation');if(nav)for(let i=0;i<nav.children.length;i++)tint(nav.children[i],i===2?'Primary':'Muted');
  for(const key of ['Rules','Connections','Traffic','Logs','Settings','Chain editor']){const content=uFind(registry.desktop[key],'Content');if(content){content.clipsContent=true;content.overflowDirection='VERTICAL';}}
  for(const id of Object.values(report.reviewFix.extensions.previews)){const c=await figma.getNodeByIdAsync(id);if(!c)continue;const head=uFind(c,'Page header');if(head)for(const b of head.children.filter(n=>n.type==='INSTANCE'))if(b.findAll(t=>t.type==='TEXT').some(t=>t.characters==='选择分组'))b.visible=false;for(const b of c.findAll(n=>n.name==='按钮 · 连接详情 · 24 ms'))for(const sibling of b.parent.children)if(sibling.type==='TEXT'&&sibling.characters==='24 ms')sibling.visible=false;}
  report.reviewFix.finalPolish='9';
}
async function r77ReviewFixMain(){
  figma.showUI('<body style="padding:24px;background:#151617;color:#c0c2c8;font:13px Microsoft YaHei,sans-serif"><h2 style="color:#8adcbf">RainLink / 修复已知问题</h2><p id="s">载入现有设计…</p><script>onmessage=e=>document.getElementById("s").textContent=e.data.pluginMessage.status</script></body>',{width:520,height:200});
  await r77Initialize();figma.skipInvisibleInstanceChildren=false;await r71Palette();const report=JSON.parse(figma.root.getPluginData('rainlink-report'));
  if(report.reviewFix?.revision===R77_REV&&report.reviewFix.finalPolish==='9'&&!report.reviewFixBuildError&&report.reviewFixVerification&&!report.reviewFixVerification.errors.length){figma.notify('本次修复已应用');figma.closePlugin();return;}
  // Persist each completed phase so retries do not recreate the whole library.
  let checkpoint;try{checkpoint=JSON.parse(figma.root.getPluginData('rainlink-review-checkpoint'));}catch(e){}
  if(checkpoint?.chunks){let value='';for(let i=0;i<checkpoint.chunks;i++)value+=figma.root.getPluginData('rainlink-review-checkpoint-'+i);checkpoint=JSON.parse(value);}
  if(checkpoint?.schema===2&&checkpoint.revision===R77_REV)r77Section=await figma.getNodeByIdAsync(checkpoint.section);
  if(r77Section){
    if(!['8','9'].includes(report.reviewFix?.finalPolish))delete checkpoint.completed['浅色与边界预览'];
    for(const [key,lib]of Object.entries(checkpoint.libraries)){
      const set=await figma.getNodeByIdAsync(lib.set),variants={};for(const [name,id]of Object.entries(lib.states))variants[name]=await figma.getNodeByIdAsync(id);
      r77Libs[key]={set,variants,initial:await figma.getNodeByIdAsync(lib.initial)};
    }
    for(const e of checkpoint.edges){const n=await figma.getNodeByIdAsync(e.node),to=e.destination?(e.named?e.destination:await figma.getNodeByIdAsync(e.destination)):undefined;if(n)r77Edges.push({n,to,nav:e.nav,close:e.close});}
  }else{
    for(const n of [...dsPage.children])if(r5Name(n)==='评估修复 · 组件与验收')n.remove();
    r77Section=figma.createSection();dsPage.appendChild(r77Section);r6Name(r77Section,'评估修复 · 组件与验收');r77Section.x=12000;r77Section.y=1000;r77Section.fills=[paint('Background')];
    checkpoint={schema:2,revision:R77_REV,section:r77Section.id,completed:{}};
  }
  const libraries=()=>Object.fromEntries(Object.entries(r77Libs).map(([k,v])=>[k,{set:v.set.id,initial:v.initial.id,states:Object.fromEntries(Object.entries(v.variants).map(([s,c])=>[s,c.id]))}]));
  const remember=()=>{checkpoint.libraries=libraries();checkpoint.edges=r77Edges.filter(e=>!e.n.removed).map(e=>({node:e.n.id,destination:typeof e.to==='string'?e.to:e.to?.id,named:typeof e.to==='string',nav:e.nav,close:e.close}));const value=JSON.stringify(checkpoint),chunks=Math.ceil(value.length/20000);for(let i=0;i<chunks;i++)figma.root.setPluginData('rainlink-review-checkpoint-'+i,value.slice(i*20000,(i+1)*20000));figma.root.setPluginData('rainlink-review-checkpoint',JSON.stringify({chunks}));};
  const step=async(name,fn)=>{if(Object.prototype.hasOwnProperty.call(checkpoint.completed,name))return checkpoint.completed[name];figma.ui.postMessage({status:name+'…'});await r5Yield();const value=await fn();checkpoint.completed[name]=value===undefined?true:value;remember();return value;};
  const save=()=>{figma.root.setPluginData('rainlink-report',JSON.stringify(report));const text=uFind(dsPage,'Delivery / Native audit');text.characters='RainLink 设计核验\n'+JSON.stringify(report,null,2);text.setPluginData('rainlink-original-text','');text.visible=false;};
  try{
    for(const mobile of [false,true]){const prefix=mobile?'移动端':'桌面端';await step(prefix+'多协议弹窗',async()=>{await r77Add(mobile);});await step(prefix+'订阅管理',async()=>{await r77Groups(mobile);});await step(prefix+'代理链',async()=>{await r77Chain(mobile);});await step(prefix+'节点操作',async()=>{await r77NodeActions(mobile);});}
    await step('分流规则',async()=>{await r77Rules();});await step('实时连接',async()=>{await r77Connections();});await step('桌面流量',async()=>{await r77Traffic(false);});await step('移动流量',async()=>{await r77Traffic(true);});await step('运行日志',async()=>{await r77Logs();});
    await step('移动平台能力',async()=>{await r77PlatformControls();});const homes=await step('连接异常与授权',()=>r77Homes(report,r77Libs['M/平台网络能力'])),consistency=await step('统一状态与导航',()=>r77Consistency(report));
    const accessibility=await step('字号与命中区域',()=>r77ReadableAndHits(report)),localLibraries=await step('页内原型组件',()=>r77LocalLibraries(report)),routeCount=await step('连接全部操作',()=>r77Wire()),extensions=await step('浅色与边界预览',()=>r77Extensions(report)),contractId=await step('交付约定',()=>r77Contract().id);r77LibraryGeometry();
    const connectionTerminology=report.reviewFix?.connectionTerminology;
    report.reviewFix={revision:R77_REV,screensAdded:0,section:r77Section.id,localLibraries,routeCount,homes,consistency,accessibility,extensions,contract:contractId,libraries:libraries(),connectionTerminology};
    await r77FinalPolish(report);await r79RemoveVpnCopy(report);remember();
    await r77Verify(report);const audit=r77AuditDocument();report.overflow=audit.overflow;report.untranslatedDisplayCopy=audit.untranslatedDisplayCopy;report.counts.components=[desktopPage,mobilePage,dsPage].reduce((s,p)=>s+p.findAll(n=>n.type==='COMPONENT').length,0);report.counts.instances=[desktopPage,mobilePage,dsPage].reduce((s,p)=>s+p.findAll(n=>n.type==='INSTANCE').length,0);delete report.nativeBackup;delete report.screenshotVerification;delete report.reviewFixBuildError;save();
  }catch(e){report.reviewFixBuildError=String(e)+'\n'+String(e.stack||'');save();throw e;}
  await figma.setCurrentPageAsync(desktopPage);figma.currentPage.selection=[registry.desktop.Dashboard];figma.viewport.scrollAndZoomIntoView(figma.currentPage.selection);figma.notify('已修复评估中的流程与交互问题 · 保持 23 个产品画面');figma.closePlugin();
}

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

(figma.command==='reviewfix'||figma.command==='settingsui'||figma.command==='backnav'?r77ReviewFixMain():figma.command==='nodesearch'?r74SearchMain():figma.command==='density'?r72DensityMain():figma.command==='homeoffline'?r71DesktopOfflineMain():figma.command==='homeprobe'?r71ProbeMain():figma.command==='homecontrols'?r71HomeControlsMain():figma.command==='compact'?r7CompactMain():figma.command==='subscriptions'?r6SubscriptionMain():figma.command==='designmd'?r5PolishMain():figma.command==='touchup'?gTouchupMain():figma.command==='probe'?gPrototypePlanProbe():figma.command==='repair'?gFinalizeStaticMain():figma.command==='groups'||figma.command==='sources'?groupSimplificationMain():figma.command==='localize'?localizeMain():figma.command==='finalize'?finalizeMain():figma.command==='refine'?refineMain():main()).catch(e=>{console.error('RainLink 设计更新失败',e);figma.ui.postMessage({status:'更新失败：'+String(e && e.message || e)+' '+String(e && e.stack || '')});figma.notify('RainLink: '+String(e && (e.message||e.stack) || e),{error:true,timeout:15000});});
