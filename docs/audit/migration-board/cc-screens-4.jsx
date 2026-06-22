/* ============================================================
   LANCER — Live session, Chat, QR/Bridge pairing, Hosts
   ============================================================ */

/* ---------- 1. SessionView — Full-screen live block terminal ---------- */
function SessionView(){
  const blocks=[
    {prompt:'~/repos/lancer ›',cmd:'swift build',lines:['Build complete! (12.4s)'],status:'ok'},
    {prompt:'~/repos/lancer ›',cmd:'claude',lines:['● Analyzing codebase structure…','● Identified 3 files to modify'],status:'running',live:true},
  ];
  return (
    <div className="cc">
      <SubNav title="dev-vps" right={
        <div style={{display:'flex',alignItems:'center',gap:10}}>
          <span className="cc-sd"><span className="d working"/>connected</span>
          <VendorMark vendor="claude" size={20}/>
        </div>
      }/>
      <Spectrum/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <StatusHeader state="ok" label="session active" detail="agent working"/>
          {blocks.map((b,i)=>(
            <div key={i} className="cc-card" style={{padding:0,marginBottom:10,overflow:'hidden',borderColor:b.live?'var(--brand)':'var(--line)'}}>
              <div style={{display:'flex',alignItems:'center',gap:8,padding:'8px 12px',borderBottom:'1px solid var(--line-2)',background:'var(--surface-2)'}}>
                <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>{b.prompt}</span>
                <span style={{marginLeft:'auto'}}>
                  {b.status==='ok'
                    ? <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--r-low)'}}>✓ exit 0</span>
                    : <span className="cc-sd"><span className="d working"/>running</span>}
                </span>
              </div>
              <div style={{fontFamily:'var(--mono)',fontSize:12,padding:'10px 12px'}}>
                <div style={{color:'var(--ink)'}}><span style={{color:'var(--brand)'}}>$ </span>{b.cmd}</div>
                {b.lines&&b.lines.map((l,j)=>(<div key={j} style={{color:'var(--ink-3)',marginTop:4}}>{l}</div>))}
                {b.live&&<div style={{color:'var(--r-med)',marginTop:4}}>● thinking<span className="cursor" style={{height:'.8em'}}/></div>}
              </div>
            </div>
          ))}
          <div className="cc-card" style={{padding:0,marginBottom:10,overflow:'hidden',borderColor:'var(--line)'}}>
            <div style={{display:'flex',alignItems:'center',gap:8,padding:'8px 12px',borderBottom:'1px solid var(--line-2)',background:'var(--surface-2)'}}>
              <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>~/repos/lancer ›</span>
              <span style={{marginLeft:'auto'}}><span className="cc-sd"><span className="d working"/>running</span></span>
            </div>
            <div style={{fontFamily:'var(--mono)',fontSize:12,padding:'10px 12px'}}>
              <div style={{color:'var(--ink)'}}><span style={{color:'var(--brand)'}}>$ </span>patch src/auth/session.swift</div>
              <div style={{color:'var(--ink-3)',marginTop:4}}>+18 / −4 lines</div>
              <div style={{color:'var(--r-med)',marginTop:4}}>● waiting on your decision<span className="cursor" style={{height:'.8em'}}/></div>
            </div>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot" style={{paddingBottom:12}}>
        <ChatInputBar/>
      </div>
    </div>
  );
}

/* ---------- 2. ChatTranscriptView — Block-based transcript ---------- */
function ChatTranscriptView(){
  const cards=[
    {agent:'Claude Code',model:'claude-sonnet-4.6',vendor:'claude',cmd:'swift build',risk:'low',blast:{files:38},output:['[142/318] Compiling SessionViewModel.swift','[218/318] Compiling PTYBridge.swift','Build complete! (12.4s)'],status:'done'},
    {agent:'Codex',model:'gpt-5.1-codex',vendor:'codex',cmd:'curl -s https://api.github.com/repos/...',risk:'medium',blast:{net:true},output:['HTTP 200 · 1.2s'],status:'done'},
    {agent:'Claude Code',model:'claude-sonnet-4.6',vendor:'claude',cmd:'rm -rf build/ dist/',risk:'high',blast:{files:2,git:false},output:['› waiting on your decision in Inbox'],status:'waiting'},
  ];
  return (
    <div className="cc-scroll">
      <div className="cc-pad" style={{paddingTop:10}}>
        {cards.map((c,i)=>(
          <ToolCardView key={i} {...c}/>
        ))}
      </div>
      <div className="cc-bottompad"/>
    </div>
  );
}

/* ---------- 3. ToolCardView — Agent tool card ---------- */
function ToolCardView({agent,model,vendor,cmd,risk,blast,output,status}){
  return (
    <div className="cc-card" style={{padding:0,marginBottom:12,overflow:'hidden',borderColor:status==='waiting'?'var(--r-med-bd)':status==='running'?'var(--brand)':'var(--line)'}}>
      <div style={{display:'flex',alignItems:'center',gap:10,padding:'11px 14px',borderBottom:'1px solid var(--line-2)',background:'var(--surface-2)'}}>
        <VendorMark vendor={vendor} size={24}/>
        <div className="grow" style={{minWidth:0}}>
          <div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)',fontWeight:500}}>{agent}</div>
          <div style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-4)',marginTop:1}}>{model}</div>
        </div>
        {status==='waiting'
          ? <RiskChip level={risk}/>
          : <span className="cc-sd"><span className={'d '+(status==='done'?'done':'working')}/>{status}</span>}
      </div>
      <div style={{padding:'10px 14px 8px'}}>
        <CommandBlock cmd={cmd} level={risk}/>
        {blast&&<BlastChips {...blast}/>}
        {output&&(
          <div style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink-3)',padding:'8px 0 0',lineHeight:1.7}}>
            {output.map((l,j)=><div key={j} style={{color:l.includes('waiting')?'var(--r-med)':'var(--ink-3)'}}>{l}{l.includes('waiting')&&<span className="cursor" style={{height:'.7em'}}/>}</div>)}
          </div>
        )}
      </div>
      {status==='waiting'&&(
        <div style={{display:'flex',gap:10,padding:'8px 14px 12px',borderTop:'1px solid var(--line-2)'}}>
          <button className="cc-btn cc-btn--quiet" style={{flex:1,height:38,minHeight:38,fontSize:12}}><Ic d={ICON.edit} s={13}/>Edit</button>
          <button className="cc-btn cc-btn--danger" style={{flex:1,height:38,minHeight:38,fontSize:12}}><Ic d={ICON.x} s={13}/>Deny</button>
          <button className="cc-btn cc-btn--primary" style={{flex:1.4,height:38,minHeight:38,fontSize:12}}><Ic d={ICON.check} s={13}/>Approve</button>
        </div>
      )}
    </div>
  );
}

/* ---------- 4. ChatInputBar — Bottom input bar ---------- */
function ChatInputBar(){
  return (
    <div style={{display:'flex',alignItems:'center',background:'var(--bg-2)',border:'1px solid var(--line)',borderRadius:'var(--r-md)',height:46,padding:'0 10px',gap:8}}>
      <span style={{fontFamily:'var(--mono)',color:'var(--brand)',fontSize:15,flex:'none'}}>›</span>
      <input placeholder="type a command or ask the agent…" style={{flex:1,background:'none',border:'none',outline:'none',color:'var(--ink)',fontFamily:'var(--mono)',fontSize:13,minWidth:0}}/>
      <button style={{background:'none',border:'none',color:'var(--ink-3)',cursor:'pointer',padding:6,display:'flex',flex:'none'}}><Ic d={ICON.term} s={16}/></button>
      <button style={{background:'none',border:'none',color:'var(--ink-3)',cursor:'pointer',padding:6,display:'flex',flex:'none'}}><Ic d={ICON.plus} s={16}/></button>
      <button className="cc-btn cc-btn--primary" style={{width:36,height:36,minHeight:36,padding:0,borderRadius:'var(--r-sm)',flex:'none'}}><Ic d={ICON.chev} s={16} sw={2.5}/></button>
    </div>
  );
}

/* ---------- 5. KeyboardAccessoryRail — Shortcut toolbar ---------- */
function KeyboardAccessoryRail(){
  const shortcuts=['$ git status','$ npm run','$ swift build','$ ls -la','$ cd ~','$ ssh','$ docker','$ curl','$ tmux'];
  return (
    <div style={{display:'flex',alignItems:'center',gap:8,padding:'8px 12px',background:'var(--bg-2)',borderTop:'1px solid var(--line)',overflowX:'auto',flex:'none'}}>
      <span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-4)',letterSpacing:'.1em',textTransform:'uppercase',flex:'none'}}>Favs</span>
      {shortcuts.map((s,i)=>(
        <button key={i} className="cc-chip" style={{background:'var(--surface)',cursor:'pointer',border:'1px solid var(--line)',fontSize:11,padding:'4px 10px',flex:'none',whiteSpace:'nowrap'}}>{s}</button>
      ))}
    </div>
  );
}

/* ---------- 6. QRScannerView — Camera-based QR scanner ---------- */
function QRScannerView(){
  const cells=Array.from({length:15});
  return (
    <div className="cc" style={{background:'#000',display:'flex',flexDirection:'column'}}>
      <div style={{flex:1,position:'relative',display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center'}}>
        <div style={{position:'absolute',inset:0,opacity:.06,backgroundImage:'radial-gradient(circle at 50% 0, var(--brand), transparent 70%)'}}/>
        {/* scanning grid overlay */}
        <div style={{position:'absolute',inset:0,display:'grid',gridTemplateColumns:'repeat(15,1fr)',gridTemplateRows:'repeat(15,1fr)',opacity:.08}}>
          {cells.map((_,i)=>cells.map((_,j)=>(
            <div key={i+'-'+j} style={{background:(ccHash('scan'+i+':'+j)%10<3)?'var(--brand)':'transparent',opacity:.5}}/>
          ))).flat()}
        </div>
        {/* viewfinder square */}
        <div style={{position:'relative',width:220,height:220,border:'2px solid rgba(255,255,255,.2)',borderRadius:6}}>
          <div style={{position:'absolute',top:-2,left:-2,width:24,height:24,borderTop:'3px solid var(--brand)',borderLeft:'3px solid var(--brand)',borderRadius:'2px 0 0 0'}}/>
          <div style={{position:'absolute',top:-2,right:-2,width:24,height:24,borderTop:'3px solid var(--brand)',borderRight:'3px solid var(--brand)',borderRadius:'0 2px 0 0'}}/>
          <div style={{position:'absolute',bottom:-2,left:-2,width:24,height:24,borderBottom:'3px solid var(--brand)',borderLeft:'3px solid var(--brand)',borderRadius:'0 0 0 2px'}}/>
          <div style={{position:'absolute',bottom:-2,right:-2,width:24,height:24,borderBottom:'3px solid var(--brand)',borderRight:'3px solid var(--brand)',borderRadius:'0 0 2px 0'}}/>
          <div style={{position:'absolute',top:'50%',left:0,right:0,height:2,background:'linear-gradient(to right, transparent, var(--brand), transparent)',opacity:.5,animation:'scanline 2.2s ease-in-out infinite'}}/>
        </div>
        <style>{'@keyframes scanline{0%,100%{transform:translateY(-70px)}50%{transform:translateY(70px)}}'}</style>
        <p style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink-2)',marginTop:28,textAlign:'center'}}>Scan QR code from your terminal</p>
        <p style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-4)',marginTop:8}}>or enter the pairing code below</p>
      </div>
      <div style={{padding:'0 18px 40px',textAlign:'center'}}>
        <button className="cc-btn cc-btn--ghost cc-btn--block" style={{height:44}}><Ic d={ICON.key} s={14}/>Enter pairing code</button>
      </div>
    </div>
  );
}

/* ---------- 7. BridgePairingView — Pairing code + QR toggle ---------- */
function BridgePairingView(){
  const [showQR,setShowQR]=React.useState(false);
  return (
    <div className="cc">
      <SubNav title="pair bridge" right={<span className="cc-sd"><span className="d waiting"/>pairing</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:16}}>
          <StatusHeader state="warn" label="waiting for bridge" detail="pair from your host"/>
          <div style={{display:'flex',flexDirection:'column',alignItems:'center',padding:'24px 0 16px'}}>
            <Spectrum/>
            {showQR ? (
              <div style={{width:200,height:200,borderRadius:6,background:'var(--surface)',border:'1px solid var(--line)',display:'grid',gridTemplateColumns:'repeat(11,1fr)',gridTemplateRows:'repeat(11,1fr)',padding:12,gap:2,marginTop:20}}>
                {Array.from({length:121}).map((_,i)=>(<div key={i} style={{background:(ccHash('bridgeqr'+i)%10<5)?'var(--ink-2)':'transparent',borderRadius:1}}/>))}
              </div>
            ) : (
              <div style={{textAlign:'center',marginTop:20}}>
                <div style={{fontFamily:'var(--mono)',fontSize:11,letterSpacing:'.25em',color:'var(--ink-4)',marginBottom:10}}>PAIRING CODE</div>
                <div style={{display:'flex',gap:12,justifyContent:'center'}}>
                  {['8','3','J','7','K','2'].map((d,i)=>(
                    <span key={i} style={{fontFamily:'var(--mono)',fontSize:40,fontWeight:700,color:'var(--brand)',background:'var(--surface)',border:'1px solid var(--line)',borderRadius:'var(--r-md)',width:48,height:58,display:'flex',alignItems:'center',justifyContent:'center',letterSpacing:0}}>{d}</span>
                  ))}
                </div>
                <p style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink-2)',margin:'18px 0 6px'}}>bridge-8a3f · lancerd v1.0</p>
                <p style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink-4)',lineHeight:1.5}}>Enter this code on your host, or scan the QR<br/>to pair this device with the bridge.</p>
              </div>
            )}
          </div>
          <button className="cc-btn cc-btn--ghost cc-btn--block" onClick={()=>setShowQR(!showQR)} style={{marginTop:4}}>
            <Ic d={showQR?ICON.key:ICON.copy} s={14}/>{showQR?'Enter pairing code instead':'Show QR code'}
          </button>
          <div className="cc-card" style={{marginTop:20,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.shield} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>The bridge is <b style={{color:'var(--ink)'}}>waiting</b> for a device to claim it. Once paired, it&apos;s bound to this phone until you explicitly unbind.</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 8. SSHConnectOverlay — Connecting overlay with orb animation ---------- */
function SSHConnectOverlay(){
  const phases=['Connecting','Verifying host key','Setting up session'];
  const [phase]=React.useState(0);
  const rings=[{s:80,d:.8},{s:116,d:1.2},{s:152,d:1.6}];
  return (
    <div className="cc" style={{background:'rgba(0,0,0,.88)',display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center',zIndex:80}}>
      <style>{'@keyframes orbPulse{0%,100%{transform:scale(1);opacity:.7}50%{transform:scale(1.12);opacity:1}}@keyframes orbGlow{0%,100%{opacity:.18}50%{opacity:.35}}'}</style>
      {/* animated orb */}
      <div style={{position:'relative',width:160,height:160,marginBottom:40,display:'flex',alignItems:'center',justifyContent:'center'}}>
        <div style={{position:'absolute',width:160,height:160,borderRadius:'50%',background:'radial-gradient(circle at 30% 20%, var(--brand), transparent 65%)',opacity:.2,animation:'orbGlow 1.8s ease-in-out infinite'}}/>
        {rings.map((r,i)=>(
          <div key={i} style={{position:'absolute',width:r.s,height:r.s,borderRadius:'50%',border:'1px solid rgba(47,67,255,'+r.d*0.2+')',animation:'orbPulse '+(1.8+i*0.3)+'s ease-in-out infinite',animationDelay:i*0.15+'s'}}/>
        ))}
        <PixelAvatar seed="lancer-connect" size={48} color="var(--brand)"/>
      </div>
      <div style={{textAlign:'center'}}>
        <div style={{fontFamily:'var(--mono)',fontSize:17,fontWeight:600,color:'var(--ink)',marginBottom:4}}>{phases[phase]}<span className="cursor" style={{height:'.75em'}}/></div>
        <div style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink-4)',marginTop:8}}>dev-vps · 192.168.1.42:22</div>
      </div>
      <button className="cc-btn cc-btn--quiet" style={{marginTop:60,width:'auto',padding:'0 28px'}}><Ic d={ICON.x} s={15}/>Cancel</button>
    </div>
  );
}

/* ---------- 9. WorkspacesView — Saved hosts list ---------- */
const HOSTS=[
  {name:'dev-vps',addr:'192.168.1.42:22',user:'roshan',status:'online',last:'now',vendor:'claude'},
  {name:'staging',addr:'staging.conduit.dev:22',user:'deploy',status:'online',last:'2h ago',vendor:'codex'},
  {name:'pi-runner',addr:'10.0.0.5:22',user:'pi',status:'offline',last:'yesterday',vendor:'opencode'},
  {name:'prod-sjc1',addr:'prod.example.com:22',user:'sre',status:'offline',last:'3d ago',vendor:'claude'},
];
function WorkspacesView({onAdd}){
  return (
    <div className="cc" style={{position:'relative'}}>
      <SubNav title="hosts" right={<span className="cc-chip"><Ic d={ICON.fleet} s={12}/>{HOSTS.filter(h=>h.status==='online').length} online</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div className="cc-card">
            {HOSTS.map((h,i)=>(
              <div key={i} className="cc-row">
                <PixelAvatar seed={h.name} size={34} color={VENDOR[h.vendor]?.c}/>
                <div className="grow">
                  <div style={{display:'flex',alignItems:'center',gap:8}}>
                    <span style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink)',fontWeight:500}}>{h.name}</span>
                    <span className={'cc-sd'} style={{fontSize:10}}><span className={'d '+(h.status==='online'?'done':'offline')}/></span>
                  </div>
                  <div className="s" style={{marginTop:3}}>{h.user}@{h.addr}</div>
                </div>
                <div style={{textAlign:'right',flex:'none'}}>
                  <div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>{h.last}</div>
                  <div style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-4)',marginTop:2}}>{h.status}</div>
                </div>
              </div>
            ))}
          </div>
          <button className="cc-btn cc-btn--ghost cc-btn--block" style={{marginTop:14}}><Ic d={ICON.plus} s={15}/>Add host</button>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <button className="cc-fab" onClick={onAdd}><Ic d={ICON.plus} s={22}/></button>
    </div>
  );
}

/* ---------- 10. HostEditorView — Host editor form ---------- */
function HostEditorView({onSave, onTest}){
  const [auth,setAuth]=React.useState('password');
  const [name,setName]=React.useState('dev-vps');
  const [host,setHost]=React.useState('192.168.1.42');
  const [port,setPort]=React.useState('22');
  const [user,setUser]=React.useState('roshan');
  return (
    <div className="cc">
      <SubNav title="edit host" right={<span className="cc-sd"><span className="d done"/>online</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div style={{display:'flex',justifyContent:'center',margin:'6px 0 16px'}}>
            <PixelAvatar seed={name||'new'} size={52} color={VENDOR.claude.c}/>
          </div>
          <div className="cc-sec">connection<span className="rule"/></div>
          <div style={{display:'flex',flexDirection:'column',gap:10}}>
            <CCInput value={name} onChange={setName} placeholder="Display name" mono/>
            <CCInput value={host} onChange={setHost} placeholder="Hostname or IP" mono/>
            <div style={{display:'flex',gap:10}}>
              <div style={{flex:'0 0 80px'}}><CCInput value={port} onChange={setPort} placeholder="Port" mono/></div>
              <div style={{flex:1}}><CCInput value={user} onChange={setUser} placeholder="Username" mono/></div>
            </div>
          </div>
          <div className="cc-sec">authentication<span className="rule"/></div>
          <div className="cc-seg" style={{marginBottom:12}}>
            {['password','key'].map(m=>(
              <button key={m} className={auth===m?'on':''} onClick={()=>setAuth(m)}>{m}</button>
            ))}
          </div>
          {auth==='password'
            ? <CCInput value="" onChange={()=>{}} placeholder="Password (stored in Keychain)" mono/>
            : <div className="cc-card" style={{padding:'4px 0'}}>
                <div className="cc-row" style={{cursor:'pointer'}}>
                  <Ic d={ICON.key} s={16}/>
                  <div className="grow"><span style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)'}}>ed25519 · lancer-dev</span></div>
                  <Ic d={ICON.chev} s={16}/>
                </div>
              </div>}
          <div className="cc-card" style={{marginTop:16,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.shield} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Credentials never leave this device. Lancer uses the SSH agent on your host for key-based auth.</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <div className="cc-btnrow">
          <button className="cc-btn cc-btn--quiet" style={{flex:1}} onClick={onTest}><Ic d={ICON.net} s={14}/>Test</button>
          <button className="cc-btn cc-btn--primary" style={{flex:1.5}} onClick={onSave}><Ic d={ICON.check} s={15}/>Save host</button>
        </div>
      </div>
    </div>
  );
}

/* ---------- 11. HostKeyConfirmSheet — TOFU host key trust ---------- */
function HostKeyConfirmSheet(){
  const fpGroups=['k7Hf3','Qx9Lm','2pR8v','NcUeJ','dW0aZ'];
  return (
    <div className="cc-sheetwrap">
      <div className="cc-scrim"/>
      <div className="cc-sheet">
        <div className="grip"/>
        <div className="sheetscroll">
          <div style={{display:'flex',alignItems:'center',gap:10,margin:'4px 0 14px'}}>
            <span style={{color:'var(--r-med)'}}><Ic d={ICON.shield} s={20}/></span>
            <h2 className="cc-h2" style={{margin:0}}>Trust this host?</h2>
          </div>
          <p style={{fontSize:13.5,color:'var(--ink-2)',lineHeight:1.55,margin:'0 0 16px'}}>First time connecting to <b style={{color:'var(--ink)',fontFamily:'var(--mono)'}}>dev-vps</b>. Verify the fingerprint before trusting.</p>
          <div className="cc-sec">ed25519 fingerprint<span className="rule"/></div>
          <div className="cc-cmd"><div className="gut"/><div className="body" style={{fontSize:11.5,padding:'11px 12px',color:'var(--ink-2)',wordBreak:'break-all'}}>SHA256:k7Hf3Qx9Lm2pR8vNcUeJdW0aZ</div></div>
          <div style={{marginTop:10,display:'flex',gap:6,justifyContent:'center'}}>
            {fpGroups.map((g,i)=>(
              <div key={i} style={{display:'flex',gap:2}}>
                {g.split('').map((ch,j)=>(
                  <div key={j} style={{width:24,height:20,borderRadius:1,background:(ccHash('fp'+g+':'+j)%10<5)?'var(--brand)':'var(--surface-3)',display:'flex',alignItems:'center',justifyContent:'center'}}>
                    <span style={{fontFamily:'var(--mono)',fontSize:8,color:(ccHash('fp'+g+':'+j)%10<5)?'#fff':'var(--ink-4)'}}>{ch}</span>
                  </div>
                ))}
              </div>
            ))}
          </div>
          <div className="cc-card" style={{marginTop:14,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.lock} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Pinned after trust. Lancer warns you if the key ever changes — possible man-in-the-middle.</span>
          </div>
        </div>
        <div className="sheetfoot">
          <div className="cc-btnrow">
            <button className="cc-btn cc-btn--danger" style={{flex:1}}><Ic d={ICON.x} s={15}/>Cancel</button>
            <button className="cc-btn cc-btn--primary" style={{flex:1.4}}><Ic d={ICON.shield} s={15}/>Trust &amp; connect</button>
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window,{
  SessionView,ChatTranscriptView,ToolCardView,ChatInputBar,KeyboardAccessoryRail,
  QRScannerView,BridgePairingView,SSHConnectOverlay,WorkspacesView,HostEditorView,HostKeyConfirmSheet,
});
