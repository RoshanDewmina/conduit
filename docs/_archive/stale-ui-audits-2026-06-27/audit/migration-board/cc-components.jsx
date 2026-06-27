/* ============================================================
   LANCER — shared atoms + sample data (exported to window)
   ============================================================ */

/* ---------- deterministic pixel avatar ---------- */
function ccHash(str){let h=2166136261;for(let i=0;i<str.length;i++){h^=str.charCodeAt(i);h=Math.imul(h,16777619);}return h>>>0;}
function PixelAvatar({seed='x', size=38, color}){
  const h=ccHash(seed);
  const palettes=[['#d97757','#7a3f2c'],['#5b8def','#2c3f7a'],['#6ac285','#2c5a3a'],['#b07ad9','#4a2c66'],['#d9b24a','#6a5320'],['#56b3c2','#1f5159']];
  const pal = color ? [color, color] : palettes[h%palettes.length];
  const n=5; const cell=size/n; const rects=[];
  for(let y=0;y<n;y++){
    for(let x=0;x<Math.ceil(n/2);x++){
      const bit=(ccHash(seed+':'+x+':'+y))%100;
      if(bit<52){
        const c = bit<14 ? pal[1] : pal[0];
        rects.push([x,y,c]); if(x!==n-1-x) rects.push([n-1-x,y,c]);
      }
    }
  }
  return (
    <svg className="cc-px" width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{background:'#0f0f14'}}>
      {rects.map(([x,y,c],i)=>(<rect key={i} x={x*cell} y={y*cell} width={cell+.5} height={cell+.5} fill={c}/>))}
    </svg>
  );
}

/* ---------- spectrum rule ---------- */
function Spectrum(){return <div className="cc-spectrum"><i/><i/><i/><i/><i/><i/><i/></div>;}

/* ---------- prompt header ---------- */
function PromptHeader({title, crumb, right}){
  return (
    <div className="cc-head">
      <div className="ttl">{title}<span className="cursor"/></div>
      <div className="crumb"><b>~/lancer</b><span className="chev">›</span>{crumb}{right&&<span className="right">{right}</span>}</div>
      <Spectrum/>
    </div>
  );
}

/* ---------- bridge status header (replaces 'no active session') ---------- */
function StatusHeader({state='ok', label, detail, spend}){
  return (
    <div className="cc-status">
      <span className={'dot '+state}/>
      <b>{label}</b>{detail&&<span>· {detail}</span>}
      {spend&&<span className="sp">today <em>{spend}</em></span>}
    </div>
  );
}

/* ---------- risk chip ---------- */
function RiskChip({level}){return <span className="cc-risk" data-r={level}><span className="sq"/>{level}</span>;}

/* ---------- vendor glyph ---------- */
const VENDOR={claude:{label:'Claude Code',c:'#d97757'},codex:{label:'Codex',c:'#9b9ca6'},opencode:{label:'opencode',c:'#b07ad9'}};
function VendorMark({vendor,size=22}){
  const v=VENDOR[vendor]||VENDOR.claude;
  return <span style={{display:'inline-flex',alignItems:'center',gap:8,flexShrink:0}}>
    <PixelAvatar seed={vendor} size={size} color={v.c}/>
    <span style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)',fontWeight:500,whiteSpace:'nowrap'}}>{v.label}</span>
  </span>;
}

/* ---------- small icons ---------- */
function Ic({d,s=16,sw=1.7,fill='none'}){return <svg width={s} height={s} viewBox="0 0 24 24" fill={fill} stroke={fill==='none'?'currentColor':'none'} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">{d}</svg>;}
const ICON={
  inbox:<><path d="M3 13h4l2 3h6l2-3h4"/><path d="M5 5h14l2 8v5a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-5z"/></>,
  fleet:<><rect x="3" y="4" width="18" height="7" rx="1.5"/><rect x="3" y="13" width="18" height="7" rx="1.5"/><circle cx="7" cy="7.5" r="1"/><circle cx="7" cy="16.5" r="1"/></>,
  activity:<><path d="M3 12h4l2 6 4-14 2 8h6"/></>,
  settings:<><circle cx="12" cy="12" r="3.2"/><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1"/></>,
  chev:<path d="M9 5l7 7-7 7"/>,
  back:<path d="M15 5l-7 7 7 7"/>,
  plus:<><path d="M12 5v14M5 12h14"/></>,
  git:<><circle cx="6" cy="6" r="2.4"/><circle cx="6" cy="18" r="2.4"/><circle cx="18" cy="9" r="2.4"/><path d="M6 8.4v7.2M18 11.4c0 4-6 2.6-6 6.6"/></>,
  net:<><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.6 2.5 15.4 0 18M12 3c-2.5 2.6-2.5 15.4 0 18"/></>,
  file:<><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/></>,
  shield:<path d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z"/>,
  bell:<><path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/></>,
  key:<><circle cx="8" cy="15" r="4"/><path d="M10.8 12.2L20 3M17 6l2 2M15 8l1.5 1.5"/></>,
  book:<><path d="M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2z"/><path d="M4 19a2 2 0 0 1 2-2h13"/></>,
  card:<><rect x="2.5" y="5" width="19" height="14" rx="2.5"/><path d="M2.5 10h19"/></>,
  bolt:<path d="M13 2L4 14h7l-2 8 9-12h-7z"/>,
  check:<path d="M5 12l4.5 4.5L19 6"/>,
  x:<path d="M6 6l12 12M18 6L6 18"/>,
  edit:<><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/></>,
  copy:<><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h8"/></>,
  term:<><rect x="3" y="4" width="18" height="16" rx="2.5"/><path d="M7 9l3 3-3 3M13 15h4"/></>,
  clock:<><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></>,
  lock:<><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></>,
  folder:<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>,
};

/* ---------- blast-radius chips ---------- */
function BlastChips({files, git, net, creds}){
  return <div className="cc-chiprow">
    {files!=null && <span className="cc-chip"><Ic d={ICON.file} s={12}/>{files} {files===1?'file':'files'}</span>}
    {git && <span className="cc-chip"><Ic d={ICON.git} s={12}/>touches git</span>}
    {net && <span className="cc-chip" style={{color:'var(--r-high)',borderColor:'var(--r-high-bd)'}}><Ic d={ICON.net} s={12}/>network</span>}
    {creds && <span className="cc-chip" style={{color:'var(--r-crit)',borderColor:'var(--r-crit-bd)'}}><Ic d={ICON.lock} s={12}/>credentials</span>}
  </div>;
}

/* ---------- command renderer ---------- */
function CommandBlock({cmd, level}){
  return <div className="cc-cmd" data-r={level}>
    <div className="gut"/>
    <div className="body"><span className="sigil">$ </span>{cmd}</div>
  </div>;
}

/* ---------- tab bar ---------- */
function TabBar({active, onChange, inboxCount}){
  const tabs=[['inbox','inbox',ICON.inbox],['fleet','fleet',ICON.fleet],['activity','activity',ICON.activity],['settings','settings',ICON.settings]];
  return <div className="cc-tabs">
    {tabs.map(([id,label,ic])=>(
      <button key={id} className={'cc-tab'+(active===id?' active':'')} onClick={()=>onChange(id)}>
        <span className="tick"/>
        <span className="ic"><Ic d={ic} s={23} sw={active===id?2:1.7}/>{id==='inbox'&&inboxCount>0&&<span className="badge">{inboxCount}</span>}</span>
        {label}
      </button>
    ))}
  </div>;
}

/* ---------- sample data ---------- */
const AGENTS=[
  {id:'a1',vendor:'claude',name:'lancer',model:'claude-sonnet-4.6',host:'Dev VPS',status:'working',spend:'$3.18',sessions:2,cwd:'~/repos/lancer'},
  {id:'a2',vendor:'codex',name:'auth-svc',model:'gpt-5.1-codex',host:'Dev VPS',status:'waiting',spend:'$0.74',sessions:1,cwd:'~/work/auth'},
  {id:'a3',vendor:'claude',name:'staging-bot',model:'claude-sonnet-4.6',host:'Staging',status:'idle',spend:'$1.02',sessions:0,cwd:'~/deploy'},
  {id:'a4',vendor:'opencode',name:'pi-runner',model:'—',host:'Raspberry Pi',status:'offline',spend:'—',sessions:0,cwd:'~'},
];
const APPROVALS=[
  {id:'p1',vendor:'claude',cwd:'~/repos/lancer',kind:'command',verb:'run a shell command',cmd:'rm -rf build/ dist/',level:'high',time:'now',blast:{files:2,git:false},rule:'ask-on-delete'},
  {id:'p2',vendor:'codex',cwd:'~/work/auth',kind:'patch',verb:'apply a code patch',cmd:'patch src/auth/session.swift',diff:'+18 / −4',level:'medium',time:'2m',blast:{files:1,git:true},rule:'ask-on-write'},
  {id:'p3',vendor:'claude',cwd:'~/repos/lancer',kind:'network',verb:'make a network request',cmd:'curl https://api.stripe.com/v1/... | sh',level:'critical',time:'4m',blast:{net:true,creds:true},rule:'ask-network'},
];
const DECIDED=[
  {vendor:'claude',cmd:'npm run build',decision:'allowed',time:'12m'},
  {vendor:'codex',cmd:'git status',decision:'always',time:'18m'},
];
const AUDIT=[
  {group:'this morning',rows:[
    {t:'09:15',act:'escalate',vendor:'claude',cmd:'patch session.swift',rule:'ask-on-write'},
    {t:'09:14',act:'auto-deny',vendor:'codex',cmd:'curl … | sh',rule:'deny-network'},
    {t:'09:12',act:'auto-allow',vendor:'claude',cmd:'ls -la',rule:'allow-read-only'},
    {t:'08:47',act:'you-allow',vendor:'claude',cmd:'npm run build',rule:'manual'},
  ]},
  {group:'overnight',rows:[
    {t:'02:18',act:'auto-allow',vendor:'claude',cmd:'swift test',rule:'allow-read-only'},
    {t:'02:03',act:'dispatch',vendor:'claude',cmd:'"run the nightly test suite"',rule:'schedule'},
    {t:'01:55',act:'auto-deny',vendor:'opencode',cmd:'rm -rf /',rule:'deny-destructive'},
  ]},
];

Object.assign(window,{
  PixelAvatar,Spectrum,PromptHeader,StatusHeader,RiskChip,VendorMark,VENDOR,Ic,ICON,
  BlastChips,CommandBlock,TabBar,AGENTS,APPROVALS,DECIDED,AUDIT,ccHash,
});
