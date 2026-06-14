/* ============================================================
   CONDUIT — MIGRATION BOARD
   Latest target UI, with decisions applied:
     • square corners (subtle 0–2px) — set in conduit.css
     • production fonts = Chakra Petch + Fira Code (board uses IBM Plex as a stand-in)
     • risk ramp decoupled from brand (green→amber→orange→red)
     • Dispatch INCLUDED · Library DISSOLVED
   Tags on every artboard: ✚ Add · ↻ Redesign · Keep · ✕ Remove
   ============================================================ */

const TAG_LABEL = { add:'✚ Add', redesign:'↻ Redesign', keep:'Keep', remove:'✕ Remove' };
function StatusTag({ k }){ return <div className="cc-tag" data-k={k}><span className="d"/>{TAG_LABEL[k] || k}</div>; }

/* phone-frame wrappers that stamp a migration tag */
function TabFrame({ tag, tab, count=3, children }){
  return <div className="cc cc-frame" style={{position:'relative'}}>
    {tag && <StatusTag k={tag}/>}
    <div style={{flex:1,position:'relative',overflow:'hidden',display:'flex',flexDirection:'column'}}>{children}</div>
    <TabBar active={tab} onChange={()=>{}} inboxCount={count}/>
  </div>;
}
function Frame({ tag, children }){
  return <div className="cc-frame" style={{position:'relative'}}>
    {tag && <StatusTag k={tag}/>}
    {children}
  </div>;
}

/* ---------- ADD · demo approval (sample, nothing runs) ---------- */
function DemoApprovalCard(){
  return (
    <div className="cc-card" style={{padding:16,borderColor:'var(--r-med-bd)'}}>
      <div style={{display:'flex',alignItems:'center',gap:8,marginBottom:10}}>
        <span className="cc-risk" data-r="medium" style={{background:'var(--surface-2)',borderColor:'var(--line)',color:'var(--ink-3)'}}>SAMPLE</span>
        <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>nothing will run</span>
        <span style={{marginLeft:'auto'}}><RiskChip level="medium"/></span>
      </div>
      <div style={{display:'flex',alignItems:'center',gap:10,marginBottom:10}}><VendorMark vendor="claude"/></div>
      <div style={{fontSize:14.5,color:'var(--ink)',lineHeight:1.4,marginBottom:9}}>wants to <b>apply a code patch</b></div>
      <CommandBlock cmd="patch src/app/main.swift" level="medium"/>
      <div className="cc-chiprow" style={{marginTop:10}}>
        <span className="cc-chip"><Ic d={ICON.folder} s={12}/>~/demo/app</span>
        <BlastChips files={1} git/>
      </div>
      <div className="cc-btnrow" style={{marginTop:14}}>
        <button className="cc-btn cc-btn--danger"><Ic d={ICON.x} s={15}/>Deny</button>
        <button className="cc-btn cc-btn--primary"><Ic d={ICON.check} s={15}/>Approve</button>
      </div>
      <p className="cc-note" style={{margin:'10px 2px 0',textAlign:'center'}}>This is a local demo. No host is contacted and no rule is created.</p>
    </div>
  );
}

/* ---------- ADD · first-run inbox (checklist + demo) ---------- */
function ChecklistRow({ n, txt }){
  return <div style={{display:'flex',alignItems:'center',gap:11,padding:'9px 0'}}>
    <span style={{width:22,height:22,borderRadius:2,border:'1px solid var(--line-strong)',display:'flex',alignItems:'center',justifyContent:'center',fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-2)',flex:'none'}}>{n}</span>
    <span style={{fontSize:13.5,color:'var(--ink-2)'}}>{txt}</span>
  </div>;
}
function FirstRunInbox(){
  return (
    <div className="cc-scroll">
      <StatusHeader state="warn" label="no bridge yet" detail="connect a host to begin"/>
      <PromptHeader title="inbox" crumb={<b>agent approvals</b>} right="set up"/>
      <div className="cc-pad">
        <div className="cc-card" style={{padding:'16px 16px 14px',marginTop:4}}>
          <div style={{fontFamily:'var(--mono)',fontSize:11,letterSpacing:'.18em',color:'var(--ink-3)'}}>GET STARTED</div>
          <div style={{marginTop:6}}>
            <ChecklistRow n={1} txt="Install & pair the bridge (one command)"/>
            <ChecklistRow n={2} txt="Set how cautious it should be"/>
            <ChecklistRow n={3} txt="Approve the first action it escalates"/>
          </div>
          <div className="cc-btnrow" style={{marginTop:8}}>
            <button className="cc-btn cc-btn--primary" style={{flex:1.3}}><Ic d={ICON.plus} s={15}/>Pair the bridge</button>
            <button className="cc-btn cc-btn--ghost" style={{flex:1}}>Try demo</button>
          </div>
        </div>
        <div className="cc-sec">try it now<span className="rule"/></div>
        <DemoApprovalCard/>
      </div>
      <div className="cc-bottompad"/>
    </div>
  );
}

/* ---------- REDESIGN · onboarding connect = PAIRING-FIRST (bridge dials out, no SSH) ---------- */
function ConnectBridgeScreen(){
  return (
    <div className="cc">
      <div style={{position:'absolute',top:54,left:0,right:0,zIndex:5,display:'flex',alignItems:'center',padding:'0 16px'}}>
        <button className="back" style={{width:38,height:38,borderRadius:2,border:'1px solid var(--line)',background:'var(--surface)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--ink-2)'}}><Ic d={ICON.back} s={17}/></button>
        <div style={{display:'flex',gap:6,marginLeft:'auto'}}>{[1,2,3].map(i=>(<span key={i} style={{width:i===2?20:7,height:7,borderRadius:2,background:i===2?'var(--brand)':i<2?'var(--ink-3)':'var(--surface-3)'}}/>))}</div>
      </div>
      <div className="cc-scroll" style={{paddingTop:104}}>
        <div className="cc-pad">
          <div style={{fontFamily:'var(--mono)',fontSize:11,letterSpacing:'.2em',color:'var(--ink-4)',marginBottom:8}}>STEP 2 / 3</div>
          <h1 style={{fontFamily:'var(--mono)',fontSize:28,fontWeight:700,letterSpacing:'-.01em',margin:'0 0 12px',color:'var(--ink)'}}>Pair the bridge</h1>
          <p style={{fontSize:14.5,color:'var(--ink-2)',lineHeight:1.6,margin:'0 0 18px',maxWidth:'34ch'}}>
            Install the bridge on the machine where your agents run — it dials out and pairs to this phone. No SSH, no port-forwarding, works on any network.
          </p>
          <CommandBlock cmd="curl -fsSL conduit.dev/install | sh" level="low"/>
          <button className="cc-btn cc-btn--quiet cc-btn--block" style={{marginTop:10}}><Ic d={ICON.copy} s={14}/>Copy command</button>

          {/* pairing panel — QR + large pairing code + waiting line */}
          <div className="cc-card" style={{marginTop:14,padding:'16px 15px'}}>
            <div style={{display:'flex',alignItems:'center',gap:16}}>
              <div style={{width:96,height:96,background:'var(--bg-2)',border:'1px solid var(--line)',borderRadius:'var(--r-md)',display:'grid',gridTemplateColumns:'repeat(7,1fr)',gridTemplateRows:'repeat(7,1fr)',padding:8,gap:2,flex:'none'}}>
                {Array.from({length:49}).map((_,i)=>(<div key={i} style={{background:(ccHash('qr'+i)%10<4)?'var(--ink-2)':'transparent',borderRadius:1}}/>))}
              </div>
              <div style={{minWidth:0}}>
                <div style={{fontFamily:'var(--mono)',fontSize:10,letterSpacing:'.18em',color:'var(--ink-4)',marginBottom:7}}>PAIRING CODE</div>
                <div style={{fontFamily:'var(--mono)',fontSize:26,fontWeight:700,letterSpacing:'.14em',color:'var(--ink)',lineHeight:1}}>4 8 2 9 1 7</div>
                <div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)',marginTop:9,lineHeight:1.45}}>scan, or it auto-pairs on install</div>
              </div>
            </div>
            <div style={{marginTop:14,paddingTop:13,borderTop:'1px solid var(--line-2)'}}>
              <span className="cc-sd"><span className="d working"/>waiting for bridge…</span>
            </div>
          </div>

          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.shield} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-3)',lineHeight:1.5}}>The bridge and phone derive keys at pairing. The relay forwards ciphertext it can't read — only your decisions cross the wire.</span>
          </div>
          <button className="cc-row" style={{padding:'12px 0',marginTop:6}}>
            <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink-2)'}}>advanced · connect a remote host over SSH</span>
            <Ic d={ICON.chev} s={15}/>
          </button>
        </div>
        <div style={{height:40}}/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}}><span className="cc-sd" style={{color:'#fff'}}><span className="d working"/></span>Pairing… done when paired</button>
      </div>
    </div>
  );
}

/* ---------- REDESIGN · Fleet with model + privacy badge (opencode + local models) ---------- */
function PrivacyChip({local}){
  if(local) return <span style={{fontFamily:'var(--mono)',fontSize:10,fontWeight:600,letterSpacing:'.04em',color:'var(--r-low)',border:'1px solid var(--r-low-bd)',background:'var(--r-low-bg)',borderRadius:'var(--r-sm)',padding:'2px 7px',whiteSpace:'nowrap'}}>local · stays on host</span>;
  return <span style={{fontFamily:'var(--mono)',fontSize:10,fontWeight:600,letterSpacing:'.04em',color:'var(--ink-3)',border:'1px solid var(--line)',borderRadius:'var(--r-sm)',padding:'2px 7px',whiteSpace:'nowrap'}}>cloud</span>;
}
function FleetPrivacyRow({a}){
  const v=VENDOR[a.vendor]||VENDOR.claude;
  return (
    <div className="cc-row" style={{cursor:'pointer',alignItems:'flex-start'}}>
      <PixelAvatar seed={a.vendor+a.name} size={38} color={v.c}/>
      <div className="grow" style={{minWidth:0}}>
        <div style={{display:'flex',alignItems:'baseline',gap:7,whiteSpace:'nowrap',overflow:'hidden'}}>
          <span style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink)',fontWeight:500}}>{v.label}</span>
          <span style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink-4)'}}>{a.name}</span>
        </div>
        <div className="s" style={{marginTop:3,whiteSpace:'normal'}}>{a.model}</div>
        <div style={{display:'flex',alignItems:'center',gap:8,marginTop:7,flexWrap:'wrap'}}>
          <span className="cc-sd"><span className={'d '+a.status}/>{a.host} · {a.status}</span>
          <PrivacyChip local={a.local}/>
        </div>
      </div>
      <div style={{flex:'none',display:'flex',flexDirection:'column',alignItems:'flex-end',gap:5,paddingTop:1}}>
        {a.spend!=='—'?<span style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-2)'}}>{a.spend}</span>:<span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)'}}>local</span>}
      </div>
    </div>
  );
}
function FleetPrivacyScreen(){
  const FLEET=[
    {vendor:'claude',name:'conduit',model:'claude-sonnet-4.6',host:'Dev VPS',status:'working',spend:'$3.18',local:false},
    {vendor:'opencode',name:'api-svc',model:'qwen2.5-coder:32b (Ollama)',host:'Workstation',status:'waiting',spend:'—',local:true},
    {vendor:'codex',name:'auth',model:'gpt-5.1-codex',host:'Dev VPS',status:'idle',spend:'$0.74',local:false},
    {vendor:'opencode',name:'pi-bot',model:'llama3.3 (llama.cpp)',host:'Raspberry Pi',status:'offline',spend:'—',local:true},
  ];
  const localCount=FLEET.filter(a=>a.local).length;
  return (
    <div className="cc-scroll">
      <StatusHeader state="ok" label="bridge connected" detail="3 hosts" spend="$3.92"/>
      <PromptHeader title="fleet" crumb={<b>model &amp; privacy</b>} right={`${FLEET.length} agents`}/>
      <div className="cc-pad">
        {/* cross-vendor spend hero */}
        <div className="cc-card" style={{padding:'16px 16px 14px',marginTop:4}}>
          <div style={{display:'flex',alignItems:'flex-end',justifyContent:'space-between'}}>
            <div>
              <div style={{fontFamily:'var(--mono)',fontSize:34,fontWeight:700,color:'var(--ink)',lineHeight:1,letterSpacing:'-.02em'}}>$3.92</div>
              <div className="cc-note" style={{marginTop:5}}>spend today · cloud models only</div>
            </div>
            <div style={{textAlign:'right'}}>
              <div style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-2)'}}>2 cloud · 2 local</div>
              <div style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--r-low)',marginTop:3}}>{localCount} stay on host</div>
            </div>
          </div>
          <div style={{display:'flex',gap:4,marginTop:14,height:6,borderRadius:3,overflow:'hidden',background:'var(--surface-2)'}}>
            <div style={{width:'81%',background:'#d97757'}}/>
            <div style={{width:'19%',background:'#9b9ca6'}}/>
          </div>
          <div style={{display:'flex',gap:16,marginTop:9}}>
            <span className="cc-chip" style={{border:'none',background:'none',padding:0,color:'var(--ink-3)'}}><span style={{width:8,height:8,borderRadius:2,background:'#d97757'}}/>Claude $3.18</span>
            <span className="cc-chip" style={{border:'none',background:'none',padding:0,color:'var(--ink-3)'}}><span style={{width:8,height:8,borderRadius:2,background:'#9b9ca6'}}/>Codex $0.74</span>
            <span style={{marginLeft:'auto',fontFamily:'var(--mono)',fontSize:11,color:'var(--r-low)'}}>local = $0</span>
          </div>
        </div>

        <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start',borderColor:'var(--r-low-bd)',background:'var(--r-low-bg)'}}>
          <span style={{color:'var(--r-low)',flex:'none',marginTop:1}}><Ic d={ICON.shield} s={16}/></span>
          <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>{localCount} agents run a <b style={{color:'var(--ink)'}}>local model</b> — those prompts and code never leave the host.</span>
        </div>

        <div className="cc-sec">agents <span className="n">· {FLEET.length}</span><span className="rule"/></div>
        <div className="cc-card">
          {FLEET.map((a,i)=>(<FleetPrivacyRow key={i} a={a}/>))}
        </div>
        <button className="cc-btn cc-btn--ghost cc-btn--block" style={{marginTop:14}}><Ic d={ICON.plus} s={16}/>Add a host</button>
      </div>
      <div className="cc-bottompad"/>
    </div>
  );
}

/* ---------- REDESIGN · Add Host (paste-to-parse + inline Ed25519, de-Library copy) ---------- */
function AddHostScreen(){
  return (
    <div className="cc">
      <SubNav title="add host"/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 10px'}}>Paste an SSH command — Conduit parses host, user, and port.</p>
          <CCInput value="ssh ubuntu@dev-vps -p 22" onChange={()=>{}} mono prefix="$"/>
          <div className="cc-chiprow" style={{marginTop:10}}>
            <span className="cc-chip">host: dev-vps</span>
            <span className="cc-chip">user: ubuntu</span>
            <span className="cc-chip">port: 22</span>
          </div>
          <div className="cc-sec">auth<span className="rule"/></div>
          <div className="cc-seg"><button>password</button><button className="on">ed25519 key</button></div>
          <div className="cc-card" style={{marginTop:12,padding:'14px 15px'}}>
            <div style={{display:'flex',alignItems:'center',gap:9,marginBottom:8}}><Ic d={ICON.key} s={16}/><span style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)',fontWeight:600}}>Generate Ed25519 key</span></div>
            <div className="cc-cmd" style={{marginBottom:8}}><div className="gut"/><div className="body" style={{fontSize:11.5,padding:'9px 11px',color:'var(--ink-2)'}}>ssh-ed25519 AAAAC3Nz…u9Qe conduit</div></div>
            <button className="cc-btn cc-btn--quiet cc-btn--block"><Ic d={ICON.copy} s={14}/>Copy public key</button>
            <p className="cc-note" style={{margin:'10px 2px 0'}}>Stored in the Keychain. Copy or rotate keys from <b style={{color:'var(--ink-2)'}}>Settings → Security</b>.</p>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}}>Connect</button>
      </div>
    </div>
  );
}

/* ---------- KEEP · Diff viewer (free; only partial-hunk apply is Pro) ---------- */
function DiffScreen(){
  const lines=[['@@ -1,6 +1,8 @@ func session()','h'],[' import Foundation','c'],['-  let timeout = 30','d'],['+  let timeout = 60','a'],['+  let retries = 3','a'],[' ','c'],['   connect(timeout)','c']];
  return (
    <div className="cc">
      <SubNav title="diff" right={<span className="cc-chip"><Ic d={ICON.file} s={12}/>session.swift</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div style={{display:'flex',alignItems:'center',gap:10,marginBottom:12}}>
            <RiskChip level="medium"/>
            <span style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-3)'}}><span style={{color:'var(--r-low)'}}>+18</span> &nbsp;<span style={{color:'var(--r-crit)'}}>−4</span> &nbsp;lines</span>
          </div>
          <div className="cc-cmd" style={{display:'block',padding:0}}>
            <div className="body" style={{whiteSpace:'pre',padding:'12px 12px',fontSize:12,lineHeight:1.7}}>
              {lines.map(([t,k],i)=>(
                <div key={i} style={{color:k==='a'?'var(--r-low)':k==='d'?'var(--r-crit)':k==='h'?'var(--ink-3)':'var(--ink-2)',background:k==='a'?'rgba(63,181,126,.08)':k==='d'?'rgba(242,75,61,.08)':'transparent',margin:'0 -12px',padding:'0 12px'}}>{t}</div>
              ))}
            </div>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <div className="cc-btnrow">
          <button className="cc-btn cc-btn--danger"><Ic d={ICON.x} s={15}/>Deny</button>
          <button className="cc-btn cc-btn--primary"><Ic d={ICON.check} s={15}/>Approve write</button>
        </div>
      </div>
    </div>
  );
}

/* ---------- ADD · Trust & Privacy (what leaves your host · connectivity · how it compares) ---------- */
function LeaveRow({ icon, label, color }){
  return <div style={{display:'flex',alignItems:'center',gap:10,padding:'9px 0'}}>
    <span style={{color:color||'var(--ink-2)',flex:'none'}}><Ic d={icon} s={15}/></span>
    <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink-2)'}}>{label}</span>
  </div>;
}
function ConnRow({ label, sub, on }){
  return <div className="cc-row" style={{cursor:'pointer'}}>
    <span style={{width:18,height:18,borderRadius:'50%',border:'2px solid '+(on?'var(--brand)':'var(--ink-4)'),flex:'none',display:'flex',alignItems:'center',justifyContent:'center'}}>{on&&<span style={{width:8,height:8,borderRadius:'50%',background:'var(--brand)'}}/>}</span>
    <div className="grow"><div className="t" style={{fontSize:14,fontFamily:'var(--mono)'}}>{label}</div>{sub&&<div className="s" style={{whiteSpace:'normal'}}>{sub}</div>}</div>
  </div>;
}
function CompareCell({ v, good }){
  return <span style={{fontFamily:'var(--mono)',fontSize:11,color:good?'var(--r-low)':'var(--ink-3)'}}>{v}</span>;
}
function TrustPrivacyScreen(){
  const COMPARE=[
    ['Omnara','yes','yes','yes',false],
    ['Anthropic','yes','yes','yes',false],
    ['Conduit','no','no','no',true],
  ];
  return (
    <div className="cc">
      <SubNav title="trust &amp; privacy"/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 4px'}}>Your code and your model stay on your host. Only the decisions you make cross the wire.</p>

          <div className="cc-sec">what leaves your host<span className="rule"/></div>
          <div className="cc-card" style={{padding:'10px 15px 12px',borderColor:'var(--r-low-bd)'}}>
            <div style={{fontFamily:'var(--mono)',fontSize:10.5,letterSpacing:'.14em',color:'var(--r-low)',padding:'4px 0 2px'}}>STAYS ON HOST</div>
            <LeaveRow icon={ICON.check} label="code" color="var(--r-low)"/>
            <LeaveRow icon={ICON.check} label="diffs" color="var(--r-low)"/>
            <LeaveRow icon={ICON.check} label="terminal output" color="var(--r-low)"/>
            <LeaveRow icon={ICON.check} label="your model" color="var(--r-low)"/>
          </div>
          <div className="cc-card" style={{marginTop:12,padding:'10px 15px 12px',borderColor:'var(--brand)'}}>
            <div style={{fontFamily:'var(--mono)',fontSize:10.5,letterSpacing:'.14em',color:'var(--brand)',padding:'4px 0 2px'}}>CROSSES THE WIRE — ENCRYPTED</div>
            <LeaveRow icon={ICON.shield} label="the approval card (command, risk, paths)" color="var(--brand)"/>
            <LeaveRow icon={ICON.lock} label="your decision" color="var(--brand)"/>
          </div>

          <div className="cc-sec">connectivity<span className="rule"/></div>
          <div className="cc-card">
            <ConnRow on label="Conduit relay" sub="end-to-end encrypted (default)"/>
            <ConnRow label="Self-hosted relay" sub="run the relay container yourself"/>
            <ConnRow label="Direct / same network" sub="skip the relay entirely"/>
          </div>
          <p className="cc-note" style={{margin:'10px 4px 0'}}>The relay forwards ciphertext it can't read.</p>

          <div className="cc-sec">how it compares<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 0'}}>
            <div style={{display:'flex',alignItems:'center',padding:'9px 14px',gap:8}}>
              <span style={{flex:1,fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-4)'}}>·</span>
              <span style={{width:62,textAlign:'center',fontFamily:'var(--mono)',fontSize:9.5,color:'var(--ink-4)',letterSpacing:'.02em'}}>code leaves?</span>
              <span style={{width:58,textAlign:'center',fontFamily:'var(--mono)',fontSize:9.5,color:'var(--ink-4)',letterSpacing:'.02em'}}>model cloud?</span>
              <span style={{width:62,textAlign:'center',fontFamily:'var(--mono)',fontSize:9.5,color:'var(--ink-4)',letterSpacing:'.02em'}}>relay reads?</span>
            </div>
            {COMPARE.map(([name,a,b,c,good],i)=>(
              <div key={i} style={{display:'flex',alignItems:'center',padding:'10px 14px',gap:8,position:'relative'}}>
                <span style={{position:'absolute',top:0,left:14,right:14,height:1,background:'var(--line-2)'}}/>
                <span style={{flex:1,fontFamily:'var(--mono)',fontSize:12.5,fontWeight:good?700:500,color:good?'var(--r-low)':'var(--ink)'}}>{name}</span>
                <span style={{width:62,textAlign:'center'}}><CompareCell v={a} good={good}/></span>
                <span style={{width:58,textAlign:'center'}}><CompareCell v={b} good={good}/></span>
                <span style={{width:62,textAlign:'center'}}><CompareCell v={c} good={good}/></span>
              </div>
            ))}
          </div>
          <p className="cc-note" style={{margin:'12px 4px 0'}}>Vendor- and model-agnostic, with a thin E2E relay — a stance no single-vendor app can match.</p>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- REDESIGN · Settings (Library dissolved · Trust & Privacy added) ---------- */
function SR({ icon, title, detail, toggle, on, danger }){
  return <div className="cc-row" style={{cursor:'pointer'}}>
    <span style={{width:30,height:30,borderRadius:2,background:'var(--surface-2)',border:'1px solid var(--line)',display:'flex',alignItems:'center',justifyContent:'center',color:danger?'var(--r-crit)':'var(--ink-2)',flex:'none'}}><Ic d={icon} s={16}/></span>
    <div className="grow"><div className="t" style={{fontSize:14.5,color:danger?'var(--r-crit)':'var(--ink)'}}>{title}</div>{detail&&<div className="s" style={{whiteSpace:'normal'}}>{detail}</div>}</div>
    {toggle ? <span className={'cc-toggle'+(on?' on':'')}><span className="knob"/></span> : <Ic d={ICON.chev} s={16}/>}
  </div>;
}
function SettingsCleanScreen(){
  return (
    <div className="cc-scroll">
      <StatusHeader state="ok" label="bridge connected" detail="conduitd v1.0"/>
      <PromptHeader title="settings" crumb={<b>device &amp; policy</b>}/>
      <div className="cc-pad">
        <div className="cc-sec">bridge &amp; hosts<span className="rule"/></div>
        <div className="cc-card">
          <SR icon={ICON.fleet} title="Hosts" detail="paired · Workstation, Dev VPS · +1 SSH (advanced)"/>
          <SR icon={ICON.shield} title="Bridge status" detail="running · attached"/>
          <SR icon={ICON.term} title="Open terminal" detail="power-user · live session"/>
        </div>
        <div className="cc-sec">approvals<span className="rule"/></div>
        <div className="cc-card">
          <SR icon={ICON.shield} title="Policy" detail="balanced · 6 rules"/>
          <SR icon={ICON.bell} title="Notifications" detail="high &amp; critical · quiet 11pm–8am"/>
        </div>
        <div className="cc-sec">security<span className="rule"/></div>
        <div className="cc-card">
          <SR icon={ICON.lock} title="Face ID lock" detail="require to open &amp; approve critical" toggle on/>
          <SR icon={ICON.shield} title="Redact secrets in output" toggle on/>
          <SR icon={ICON.key} title="SSH keys" detail="ed25519 · enclave-backed · copy / rotate"/>
          <SR icon={ICON.clock} title="Audit log" detail="every decision, on-device"/>
        </div>
        <div className="cc-sec">trust &amp; privacy<span className="rule"/></div>
        <div className="cc-card">
          <SR icon={ICON.shield} title="Trust &amp; Privacy" detail="host-key TOFU · Keychain · keys go direct to provider · no account"/>
        </div>
        <div className="cc-sec">account<span className="rule"/></div>
        <div className="cc-card">
          <SR icon={ICON.bolt} title="Conduit Pro" detail="lifetime · unlocked"/>
          <SR icon={ICON.card} title="Billing &amp; usage" detail="$4.94 today · across vendors"/>
        </div>
        <p className="cc-note" style={{textAlign:'center',margin:'22px 0 0'}}>Conduit 1.0 · conduitd v1.0 · your code stays on your host</p>
      </div>
      <div className="cc-bottompad"/>
    </div>
  );
}

/* ---------- REMOVE · ghosted surfaces being cut ---------- */
function RemovedFrame({ children, why }){
  return <div className="cc cc-frame" style={{position:'relative'}}>
    <StatusTag k="remove"/>
    <div className="cc-ghost" style={{flex:1,overflow:'hidden'}}>{children}</div>
    <div className="cc-removebar"><Ic d={ICON.x} s={14}/>{why}</div>
  </div>;
}
function LibraryHubGhost(){
  const cards=[['Snippets','7 saved · run / new',ICON.book],['SSH Keys','3 keys · 3 hosts',ICON.key],['Agents','cloud · 2 hosted',ICON.bolt]];
  return <div className="cc-scroll">
    <PromptHeader title="library" crumb={<b>your toolkit</b>}/>
    <div className="cc-pad">
      {cards.map(([t,s,ic],i)=>(
        <div key={i} className="cc-card" style={{padding:'15px 15px',marginBottom:10,display:'flex',alignItems:'center',gap:12}}>
          <span style={{width:34,height:34,borderRadius:2,background:'var(--surface-2)',border:'1px solid var(--line)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--ink-2)'}}><Ic d={ic} s={17}/></span>
          <div className="grow"><div className="t">{t}</div><div className="s">{s}</div></div>
          <Ic d={ICON.chev} s={16}/>
        </div>
      ))}
    </div>
  </div>;
}
function SessionSwitcherGhost(){
  const tabs=['terminal','preview','files','diff','inbox'];
  return <div className="cc-scroll">
    <PromptHeader title="session" crumb={<b>app-inside-session</b>}/>
    <div className="cc-pad">
      <div style={{display:'flex',gap:4,background:'var(--surface-2)',border:'1px solid var(--line)',borderRadius:2,padding:3,marginTop:6}}>
        {tabs.map((x,i)=>(<span key={i} style={{flex:1,textAlign:'center',fontFamily:'var(--mono)',fontSize:10.5,padding:'8px 2px',borderRadius:2,background:i===0?'var(--brand)':'transparent',color:i===0?'#fff':'var(--ink-3)'}}>{x}</span>))}
      </div>
      <div className="cc-cmd" style={{marginTop:14}}><div className="gut"/><div className="body" style={{padding:'11px 13px',color:'var(--ink-2)'}}>$ ls -la</div></div>
      <div className="cc-card" style={{marginTop:12,padding:'12px 14px',borderColor:'var(--r-med-bd)'}}><span style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--r-med)'}}>⬡ Diff &amp; Inbox gated behind Pro</span></div>
    </div>
  </div>;
}
function MockKeyCountsGhost(){
  const keys=[['conduit-dev','3 hosts'],['ci-runner','1 host'],['backup-key','unused']];
  return <div className="cc-scroll">
    <PromptHeader title="ssh keys" crumb={<b>library › keys</b>}/>
    <div className="cc-pad">
      <div className="cc-card">
        {keys.map(([t,s],i)=>(
          <div key={i} className="cc-row" style={{cursor:'default'}}>
            <PixelAvatar seed={t} size={30}/>
            <div className="grow"><div className="t" style={{fontSize:14}}>{t}</div><div className="s">ed25519</div></div>
            <span className="cc-chip" style={{color:'var(--r-high)',borderColor:'var(--r-high-bd)'}}>{s}</span>
          </div>
        ))}
      </div>
      <p className="cc-note" style={{margin:'12px 4px 0'}}>host counts are mocked — fake data in a security app</p>
    </div>
  </div>;
}

/* ---------- design-system legend artboards ---------- */
function DecisionsLegend(){
  const rows=[
    ['keep','Square corners','BLOCKS identity — subtle 0–2px, not the mock’s 7–12px'],
    ['keep','Chakra Petch + Fira Code','Production faces kept (mock shows IBM Plex as a stand-in)'],
    ['add','Risk decoupled from brand','green→amber→orange→red ramp; electric blue = CTA only'],
    ['add','Dispatch','start an agent task from the phone — wired to a real RPC'],
    ['add','Pairing-first connect','install bridge → it dials out → pair phone — no SSH, no Tailscale'],
    ['add','OSS + self-hosted models','opencode / Goose / local models (Ollama, llama.cpp) — vendor & model agnostic'],
    ['add','Thin E2E relay','only approval metadata crosses the wire; code & model never leave the host'],
    ['add','Surfaced from backend','billing/quota · run-control (stop) · notifications+quiet hours · provider keys · policy.yaml · TOFU — all built, now drawn'],
    ['remove','Library hub','dissolved → keys to Settings·Security, snippets to session'],
  ];
  return <div className="cc cc-frame" style={{height:520,padding:'26px 22px'}}>
    <StatusTag k="keep"/>
    <div style={{fontFamily:'var(--mono)',fontSize:11,letterSpacing:'.2em',color:'var(--ink-3)',marginBottom:18}}>DECISIONS APPLIED</div>
    <div className="cc-legend">
      {rows.map(([k,t,d],i)=>(
        <div key={i} className="li">
          <span className="d" style={{background:k==='add'?'var(--r-low)':k==='remove'?'var(--r-crit)':'var(--ink-3)'}}/>
          <span className="tx"><b>{t}</b> — {d}</span>
        </div>
      ))}
    </div>
  </div>;
}

/* ============================================================
   BOARD COMPOSITION
   ============================================================ */
function MigrationBoard(){
  return (
    <DesignCanvas>
      <DCSection id="loop" title="Core loop" subtitle="The daily heartbeat — agents ask, you decide in seconds, the bridge audits the rest.">
        <DCArtboard id="inbox" label="Inbox · approval queue" width={320} height={660}>
          <TabFrame tag="redesign" tab="inbox"><InboxScreen approvals={APPROVALS} onApprove={()=>{}} onDeny={()=>{}} onOpen={()=>{}}/></TabFrame>
        </DCArtboard>
        <DCArtboard id="sheet" label="Decision sheet · all 4 actions" width={320} height={660}>
          <div className="cc cc-frame" style={{position:'relative'}}><StatusTag k="add"/>
            <div style={{flex:1,position:'relative',overflow:'hidden'}}>
              <InboxScreen approvals={APPROVALS} onApprove={()=>{}} onDeny={()=>{}} onOpen={()=>{}}/>
              <ApprovalSheet a={APPROVALS[0]} onClose={()=>{}} onDecide={()=>{}}/>
            </div>
          </div>
        </DCArtboard>
        <DCArtboard id="critical" label="Critical · Face ID gate" width={320} height={660}>
          <div className="cc cc-frame" style={{position:'relative'}}><StatusTag k="add"/>
            <div style={{flex:1,position:'relative',overflow:'hidden'}}>
              <InboxScreen approvals={APPROVALS} onApprove={()=>{}} onDeny={()=>{}} onOpen={()=>{}}/>
              <ApprovalSheet a={APPROVALS[2]} onClose={()=>{}} onDecide={()=>{}}/>
            </div>
          </div>
        </DCArtboard>
        <DCArtboard id="editrun" label="Decision · edit &amp; run (3rd action)" width={320} height={660}>
          <Frame tag="redesign"><EditRunScreen/></Frame>
        </DCArtboard>
        <DCArtboard id="allowalways" label="Decision · allow always → rule written" width={320} height={660}>
          <div className="cc cc-frame" style={{position:'relative'}}><StatusTag k="add"/>
            <div style={{flex:1,position:'relative',overflow:'hidden'}}>
              <InboxScreen approvals={APPROVALS} onApprove={()=>{}} onDeny={()=>{}} onOpen={()=>{}}/>
              <AllowAlwaysSheet/>
            </div>
          </div>
        </DCArtboard>
        <DCArtboard id="firstrun" label="Inbox · first-run + demo" width={320} height={660}>
          <TabFrame tag="add" tab="inbox" count={0}><FirstRunInbox/></TabFrame>
        </DCArtboard>
        <DCArtboard id="empty" label="Inbox zero · returning user" width={320} height={660}>
          <TabFrame tag="keep" tab="inbox" count={0}><InboxScreen approvals={[]} onApprove={()=>{}} onDeny={()=>{}} onOpen={()=>{}}/></TabFrame>
        </DCArtboard>
        <DCArtboard id="fleet" label="Fleet · cross-vendor spend" width={320} height={660}>
          <TabFrame tag="redesign" tab="fleet"><FleetScreen agents={AGENTS} onOpenAgent={()=>{}} onAddHost={()=>{}}/></TabFrame>
        </DCArtboard>
        <DCArtboard id="rundetail" label="Agent · run detail + stop (NEW)" width={320} height={660}>
          <Frame tag="add"><AgentRunDetailScreen/></Frame>
        </DCArtboard>
        <DCArtboard id="activity" label="Activity · while you were away" width={320} height={660}>
          <TabFrame tag="redesign" tab="activity"><ActivityScreen/></TabFrame>
        </DCArtboard>
      </DCSection>

      <DCSection id="start" title="Start & govern" subtitle="Kick off a loop, then the rules behind autonomy and a settings page cleared of the toolkit hub.">
        <DCArtboard id="dispatch" label="Dispatch · start a task (NEW)" width={320} height={660}>
          <Frame tag="add"><DispatchScreen onBack={()=>{}} onSubmit={()=>{}}/></Frame>
        </DCArtboard>
        <DCArtboard id="policy" label="Policy · presets + effect chips" width={320} height={660}>
          <Frame tag="redesign"><PolicyScreen onBack={()=>{}}/></Frame>
        </DCArtboard>
        <DCArtboard id="policy-yaml" label="Policy · edit policy.yaml + reload" width={320} height={660}>
          <Frame tag="redesign"><PolicyYamlScreen/></Frame>
        </DCArtboard>
        <DCArtboard id="notifications" label="Settings · notifications + quiet hours" width={320} height={660}>
          <Frame tag="redesign"><NotificationsScreen/></Frame>
        </DCArtboard>
        <DCArtboard id="providerkeys" label="Settings · provider keys (multi-vendor)" width={320} height={660}>
          <Frame tag="redesign"><ProviderKeysScreen/></Frame>
        </DCArtboard>
        <DCArtboard id="settings" label="Settings · Library dissolved" width={320} height={660}>
          <TabFrame tag="redesign" tab="settings"><SettingsCleanScreen/></TabFrame>
        </DCArtboard>
      </DCSection>

      <DCSection id="connect" title="Connect · full onboarding flow" subtitle="The whole pairing-first sequence, page by page: hero → pair the bridge → choose caution → first run. SSH is the advanced branch.">
        <DCArtboard id="onb-1" label="Onboarding 1 · hero" width={320} height={660}>
          <Frame tag="keep"><OnboardingFlow onDone={()=>{}} initialStep={0}/></Frame>
        </DCArtboard>
        <DCArtboard id="onb-2" label="Onboarding 2 · pair the bridge (no SSH)" width={320} height={660}>
          <Frame tag="redesign"><ConnectBridgeScreen/></Frame>
        </DCArtboard>
        <DCArtboard id="onb-3" label="Onboarding 3 · choose caution" width={320} height={660}>
          <Frame tag="keep"><OnboardingFlow onDone={()=>{}} initialStep={3}/></Frame>
        </DCArtboard>
        <DCArtboard id="onb-4" label="Onboarding 4 · first run + demo" width={320} height={660}>
          <TabFrame tag="add" tab="inbox" count={0}><FirstRunInbox/></TabFrame>
        </DCArtboard>
        <DCArtboard id="addhost" label="Advanced · add host over SSH" width={320} height={660}>
          <Frame tag="redesign"><AddHostScreen/></Frame>
        </DCArtboard>
        <DCArtboard id="tofu" label="Advanced · trust host key (TOFU)" width={320} height={660}>
          <div className="cc cc-frame" style={{position:'relative'}}><StatusTag k="add"/>
            <div style={{flex:1,position:'relative',overflow:'hidden'}}>
              <AddHostScreen/>
              <TofuSheet/>
            </div>
          </div>
        </DCArtboard>
        <DCArtboard id="sshkeys" label="Advanced · SSH keys (kept · real data)" width={320} height={660}>
          <Frame tag="keep"><SshKeysScreen/></Frame>
        </DCArtboard>
        <DCArtboard id="terminal" label="Power-user · live block session" width={320} height={660}>
          <Frame tag="keep"><TerminalScreen/></Frame>
        </DCArtboard>
        <DCArtboard id="diff" label="Diff · approve a write" width={320} height={660}>
          <Frame tag="keep"><DiffScreen/></Frame>
        </DCArtboard>
        <DCArtboard id="fileviewer" label="File viewer · tap a file → drawer (NEW)" width={320} height={660}>
          <div className="cc cc-frame" style={{position:'relative'}}><StatusTag k="add"/>
            <div style={{flex:1,position:'relative',overflow:'hidden'}}>
              <DiffScreen/>
              <FileViewerSheet/>
            </div>
          </div>
        </DCArtboard>
      </DCSection>

      <DCSection id="trust" title="Trust & vendors" subtitle="Why a self-hosted agent crowd is the wedge — and what that means for privacy.">
        <DCArtboard id="trust-privacy" label="Trust &amp; Privacy · what leaves your host" width={320} height={660}>
          <Frame tag="add"><TrustPrivacyScreen/></Frame>
        </DCArtboard>
        <DCArtboard id="fleet-privacy" label="Fleet · model + privacy" width={320} height={660}>
          <TabFrame tag="redesign" tab="fleet"><FleetPrivacyScreen/></TabFrame>
        </DCArtboard>
      </DCSection>

      <DCSection id="billing" title="Billing & usage" subtitle="Cross-vendor spend and quota-remaining (the Tier-1 usage glance) plus the Stripe-backed Pro paywall — both fully built, neither on the board until now.">
        <DCArtboard id="usage" label="Billing · spend + quota remaining" width={320} height={660}>
          <Frame tag="redesign"><BillingScreen/></Frame>
        </DCArtboard>
        <DCArtboard id="paywall" label="Conduit Pro · paywall" width={320} height={660}>
          <div className="cc cc-frame" style={{position:'relative'}}><StatusTag k="redesign"/>
            <div style={{flex:1,position:'relative',overflow:'hidden'}}>
              <SettingsCleanScreen/>
              <PaywallSheet/>
            </div>
          </div>
        </DCArtboard>
      </DCSection>

      <DCSection id="removing" title="Removing" subtitle="Cut before adding: the toolkit hub and the dead app-inside-session switcher. (SSH keys are kept — moved to Connect with real data, not deleted.)">
        <DCArtboard id="rm-lib" label="Library hub → dissolved" width={320} height={660}>
          <RemovedFrame why="Removed · keys→Settings·Security, snippets→session"><LibraryHubGhost/></RemovedFrame>
        </DCArtboard>
        <DCArtboard id="rm-shell" label="Session surface switcher → deleted" width={320} height={660}>
          <RemovedFrame why="Removed · dead code (SessionShellView) + wrong Pro-gate"><SessionSwitcherGhost/></RemovedFrame>
        </DCArtboard>
        <DCArtboard id="rm-keys" label="Mock SSH host counts → fixed (real data)" width={320} height={660}>
          <RemovedFrame why="Fixed not cut · fake 'N hosts' counts → real fingerprint + last-used (see Connect › SSH keys)"><MockKeyCountsGhost/></RemovedFrame>
        </DCArtboard>
      </DCSection>

      <DCSection id="system" title="Design system" subtitle="Refined, not replaced — risk gets its own ramp, electric blue stays a CTA, corners stay square.">
        <DCArtboard id="decisions" label="Decisions applied" width={320} height={520}>
          <DecisionsLegend/>
        </DCArtboard>
        <DCArtboard id="ramp" label="Risk ramp · independent of brand" width={320} height={420}>
          <div className="cc cc-frame" style={{height:420,padding:'24px 20px',position:'relative'}}>
            <StatusTag k="add"/>
            <div style={{fontFamily:'var(--mono)',fontSize:11,letterSpacing:'.2em',color:'var(--ink-3)',marginBottom:16}}>SEVERITY · GREEN → RED</div>
            <div style={{display:'flex',flexDirection:'column',gap:12}}>
              {['low','medium','high','critical'].map(r=>(
                <div key={r} style={{display:'flex',alignItems:'center',gap:12}}>
                  <RiskChip level={r}/>
                  <div className="cc-cmd" data-r={r} style={{flex:1}}><div className="gut"/><div className="body" style={{fontSize:11,padding:'7px 10px'}}>{r} risk</div></div>
                </div>
              ))}
            </div>
            <div style={{marginTop:22,fontFamily:'var(--mono)',fontSize:11,letterSpacing:'.2em',color:'var(--ink-3)',marginBottom:12}}>BRAND · CTA ONLY</div>
            <button className="cc-btn cc-btn--primary cc-btn--block">Approve</button>
            <p className="cc-note" style={{marginTop:14}}>Electric blue never doubles as a risk level. (Today the app uses blue for “high” risk — this fixes it.)</p>
          </div>
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<MigrationBoard/>);
