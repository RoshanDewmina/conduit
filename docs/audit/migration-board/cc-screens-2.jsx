/* ============================================================
   CONDUIT — Onboarding, Dispatch, Policy, Settings
   ============================================================ */

/* ---------- shared sub-screen nav (custom, no platform back) ---------- */
function SubNav({title, onBack, right}){
  return <div className="cc-nav">
    <button className="back" onClick={onBack}><Ic d={ICON.back} s={18}/></button>
    <div style={{fontFamily:'var(--mono)',fontSize:17,fontWeight:600,color:'var(--ink)'}}>{title}<span className="cursor" style={{height:'.7em'}}/></div>
    <div style={{marginLeft:'auto'}}>{right}</div>
  </div>;
}

/* ---------- Onboarding (CTA anchored LOW) ---------- */
function OnboardingFlow({onDone, initialStep=0}){
  const [step,setStep]=React.useState(initialStep);
  const [host,setHost]=React.useState('');
  const [caution,setCaution]=React.useState('balanced');
  const next=()=>step<3?setStep(step+1):onDone();
  React.useEffect(()=>{window.__onbNext=next;});
  const steps=[
    /* 0 — hero */
    <div key="0" style={{display:'flex',flexDirection:'column',height:'100%'}}>
      <div className="cc-pad" style={{paddingTop:70}}>
        <Spectrum/>
        <div style={{fontFamily:'var(--mono)',fontSize:11,letterSpacing:'.3em',color:'var(--ink-3)',margin:'18px 0 30px'}}>CONDUIT</div>
        <h1 style={{fontFamily:'var(--mono)',fontWeight:700,fontSize:42,lineHeight:1.04,letterSpacing:'-.02em',margin:0}}>
          <div style={{color:'var(--ink)'}}>agents ask.</div>
          <div style={{color:'var(--brand)'}}>you approve.</div>
          <div style={{color:'var(--ink)',opacity:.62}}>work resumes.</div>
        </h1>
        <p style={{fontSize:15.5,color:'var(--ink-2)',lineHeight:1.6,marginTop:24,maxWidth:'30ch'}}>
          Your coding agents run on your own machines. Conduit taps you only when one needs a decision — and resumes the moment you choose.
        </p>
      </div>
      <div style={{flex:1}}/>
      <div className="cc-pad" style={{paddingBottom:46}}>
        <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}} onClick={next}>Get started</button>
        <button className="cc-btn cc-btn--block" style={{background:'none',color:'var(--ink-3)',marginTop:8,height:46}} onClick={onDone}>I already use Conduit</button>
      </div>
    </div>,
    /* 1 — install bridge */
    <OnbStep key="1" n={1} title="Install the bridge" lead="Run this once on the machine where your agents work. It installs conduitd — the helper that enforces your policy and survives disconnects.">
      <CommandBlock cmd="curl -fsSL conduit.dev/install | sh" level="low"/>
      <button className="cc-btn cc-btn--quiet cc-btn--block" style={{marginTop:10}}><Ic d={ICON.copy} s={14}/>Copy command</button>
      <div style={{display:'flex',alignItems:'center',gap:14,margin:'22px 0 0'}}>
        <div style={{width:88,height:88,borderRadius:10,background:'var(--surface)',border:'1px solid var(--line)',display:'grid',gridTemplateColumns:'repeat(7,1fr)',gridTemplateRows:'repeat(7,1fr)',padding:8,gap:2,flex:'none'}}>
          {Array.from({length:49}).map((_,i)=>(<div key={i} style={{background:(ccHash('qr'+i)%10<4)?'var(--ink-2)':'transparent',borderRadius:1}}/>))}
        </div>
        <div className="cc-note">Or scan to install on a paired<br/>machine. The bridge pairs to this<br/>phone automatically.</div>
      </div>
    </OnbStep>,
    /* 2 — connect host */
    <OnbStep key="2" n={2} title="Connect your host" lead="Paste the SSH command for that machine. Your code never leaves it — Conduit only carries decisions.">
      <div className="cc-seg" style={{marginBottom:14}}>
        <button className="on">bring your own</button>
        <button>conduit cloud →</button>
      </div>
      <CCInput value={host} onChange={setHost} placeholder="ssh user@host -p 22" mono prefix="$"/>
      <button className="cc-row" style={{padding:'12px 0',marginTop:6,cursor:'pointer'}}>
        <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink-2)'}}>advanced · auth · tmux · startup</span>
        <Ic d={ICON.chev} s={15}/>
      </button>
    </OnbStep>,
    /* 3 — caution */
    <OnbStep key="3" n={3} title="How cautious?" lead="Set the default policy. You can change any rule later — unmatched actions always ask.">
      {[['cautious','Auto-allow read-only · ask on every write · deny secrets & network'],['balanced','Auto-allow safe writes · ask on deletes, network & secrets'],['bypass','Auto-allow everything except critical · for trusted repos']].map(([id,desc])=>(
        <div key={id} onClick={()=>setCaution(id)} className="cc-card" style={{padding:'12px 14px',marginBottom:8,cursor:'pointer',borderColor:caution===id?'var(--brand)':'var(--line)',background:caution===id?'var(--brand-soft)':'var(--surface)'}}>
          <div style={{display:'flex',alignItems:'center',gap:10}}>
            <span style={{width:18,height:18,borderRadius:'50%',border:'2px solid '+(caution===id?'var(--brand)':'var(--ink-4)'),flex:'none',display:'flex',alignItems:'center',justifyContent:'center'}}>{caution===id&&<span style={{width:8,height:8,borderRadius:'50%',background:'var(--brand)'}}/>}</span>
            <span style={{fontFamily:'var(--mono)',fontSize:14,fontWeight:600,color:'var(--ink)',textTransform:'capitalize'}}>{id}</span>
            {id==='balanced'&&<span className="cc-chip" style={{marginLeft:'auto',color:'var(--brand)',borderColor:'var(--brand)'}}>recommended</span>}
          </div>
          <p style={{fontSize:12.5,color:'var(--ink-3)',margin:'7px 0 0',lineHeight:1.5}}>{desc}</p>
        </div>
      ))}
    </OnbStep>,
  ];
  return (
    <div className="cc" style={{position:'relative'}}>
      {step>0 && <div style={{position:'absolute',top:54,left:0,right:0,zIndex:5,display:'flex',alignItems:'center',gap:14,padding:'0 16px'}}>
        <button className="back" onClick={()=>setStep(step-1)} style={{width:38,height:38,borderRadius:10,border:'1px solid var(--line)',background:'var(--surface)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--ink-2)'}}><Ic d={ICON.back} s={17}/></button>
        <div style={{display:'flex',gap:6,marginLeft:'auto'}}>{[1,2,3].map(i=>(<span key={i} style={{width:i===step?20:7,height:7,borderRadius:4,background:i===step?'var(--brand)':i<step?'var(--ink-3)':'var(--surface-3)',transition:'all .2s'}}/>))}</div>
      </div>}
      {steps[step]}
    </div>
  );
}
function OnbStep({n,title,lead,children}){
  return <div style={{display:'flex',flexDirection:'column',height:'100%'}}>
    <div className="cc-scroll" style={{paddingTop:96}}>
      <div className="cc-pad">
        <div style={{fontFamily:'var(--mono)',fontSize:11,letterSpacing:'.2em',color:'var(--ink-4)',marginBottom:8}}>STEP {n} / 3</div>
        <h1 style={{fontFamily:'var(--mono)',fontSize:28,fontWeight:700,letterSpacing:'-.01em',margin:'0 0 12px',color:'var(--ink)'}}>{title}</h1>
        <p style={{fontSize:14.5,color:'var(--ink-2)',lineHeight:1.6,margin:'0 0 16px',maxWidth:'34ch'}}>{lead}</p>
        {children}
      </div>
      <div style={{height:12}}/>
    </div>
    <div className="cc-foot">
      <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}} onClick={()=>window.__onbNext&&window.__onbNext()}>{n===3?'Connect & finish':'Continue'}</button>
    </div>
  </div>;
}

/* ---------- input ---------- */
function CCInput({value,onChange,placeholder,mono,prefix,multiline}){
  const st={width:'100%',background:'var(--bg-2)',border:'1px solid var(--line)',borderRadius:'var(--r-md)',color:'var(--ink)',fontFamily:mono?'var(--mono)':'var(--sans)',fontSize:14,padding:multiline?'12px 13px':'0 13px',height:multiline?'auto':46,outline:'none',resize:'none'};
  if(multiline) return <textarea rows={4} value={value} onChange={e=>onChange(e.target.value)} placeholder={placeholder} style={st}/>;
  return <div style={{display:'flex',alignItems:'center',background:'var(--bg-2)',border:'1px solid var(--line)',borderRadius:'var(--r-md)',height:46,padding:'0 13px',gap:9}}>
    {prefix&&<span style={{fontFamily:'var(--mono)',color:'var(--brand)',fontSize:14}}>{prefix}</span>}
    <input value={value} onChange={e=>onChange(e.target.value)} placeholder={placeholder} style={{...st,border:'none',background:'none',padding:0,height:'100%'}}/>
  </div>;
}

/* ---------- Dispatch ---------- */
function DispatchScreen({onBack, onSubmit}){
  const [agent,setAgent]=React.useState('a1');
  const [prompt,setPrompt]=React.useState('');
  const a=AGENTS.find(x=>x.id===agent);
  return (
    <div className="cc">
      <SubNav title="dispatch" onBack={onBack}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 6px'}}>Start a new task. The bridge applies your policy and budget before anything runs.</p>
          <div className="cc-sec">agent<span className="rule"/></div>
          <div className="cc-card">
            {AGENTS.filter(x=>x.status!=='offline').map(x=>(
              <div key={x.id} className="cc-row" onClick={()=>setAgent(x.id)}>
                <PixelAvatar seed={x.vendor+x.name} size={32} color={VENDOR[x.vendor].c}/>
                <div className="grow"><div className="t" style={{fontFamily:'var(--mono)',fontSize:13.5}}>{VENDOR[x.vendor].label} · {x.name}</div><div className="s">{x.host}</div></div>
                <span style={{width:20,height:20,borderRadius:'50%',border:'2px solid '+(agent===x.id?'var(--brand)':'var(--ink-4)'),display:'flex',alignItems:'center',justifyContent:'center',flex:'none'}}>{agent===x.id&&<span style={{width:9,height:9,borderRadius:'50%',background:'var(--brand)'}}/>}</span>
              </div>
            ))}
          </div>
          <div className="cc-sec">working directory<span className="rule"/></div>
          <CCInput value={a.cwd} onChange={()=>{}} mono prefix="~"/>
          <div className="cc-sec">task<span className="rule"/></div>
          <CCInput value={prompt} onChange={setPrompt} multiline placeholder="Describe what the agent should do…"/>
          <div className="cc-sec">daily budget <span className="n">· optional</span><span className="rule"/></div>
          <CCInput value="$5.00" onChange={()=>{}} mono prefix="$"/>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}} onClick={onSubmit} disabled={!prompt}><Ic d={ICON.bolt} s={16}/>Dispatch task</button>
      </div>
    </div>
  );
}

/* ---------- Policy editor ---------- */
const EFFECT={allow:{c:'var(--r-low)',bg:'var(--r-low-bg)',bd:'var(--r-low-bd)'},ask:{c:'var(--r-med)',bg:'var(--r-med-bg)',bd:'var(--r-med-bd)'},deny:{c:'var(--r-crit)',bg:'var(--r-crit-bg)',bd:'var(--r-crit-bd)'}};
function EffectChip({e}){const m=EFFECT[e];return <span style={{fontFamily:'var(--mono)',fontSize:10.5,fontWeight:600,letterSpacing:'.08em',textTransform:'uppercase',color:m.c,background:m.bg,border:'1px solid '+m.bd,borderRadius:3,padding:'3px 8px'}}>{e}</span>;}
function PolicyScreen({onBack}){
  const [preset,setPreset]=React.useState('balanced');
  const RULES=[
    ['read · grep · list','any','allow'],['write · patch','*.{ts,swift,go}','allow'],
    ['delete','any','ask'],['network','any','ask'],['credentials · .env','any','deny'],['command','rm -rf /','deny'],
  ];
  return (
    <div className="cc">
      <SubNav title="policy" onBack={onBack} right={<span className="cc-chip"><Ic d={ICON.git} s={12}/>global</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 14px'}}>Rules decide what auto-allows, what asks you, and what's forbidden. Most actions never reach you.</p>
          <div className="cc-seg">
            {['cautious','balanced','bypass'].map(p=>(<button key={p} className={preset===p?'on':''} onClick={()=>setPreset(p)}>{p}</button>))}
          </div>
          <div className="cc-sec">rules <span className="n">· {RULES.length}</span><span className="rule"/></div>
          <div className="cc-card">
            {RULES.map(([m,glob,e],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <div className="grow">
                  <div style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)'}}>{m}</div>
                  <div className="s" style={{marginTop:3}}>match: {glob}</div>
                </div>
                <EffectChip e={e}/>
              </div>
            ))}
          </div>
          <div className="cc-card" style={{marginTop:12,padding:'13px 15px',display:'flex',alignItems:'center',gap:10}}>
            <Ic d={ICON.shield} s={16} fill="none"/>
            <span style={{fontSize:13,color:'var(--ink-2)'}}>Anything unmatched <b style={{color:'var(--r-med)'}}>asks</b> you — fail-safe by default.</span>
          </div>
          <button className="cc-btn cc-btn--ghost cc-btn--block" style={{marginTop:14}}><Ic d={ICON.plus} s={15}/>Add rule</button>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- Settings (cleaned of SSH-first remnants) ---------- */
function SettingsRow({icon,title,detail,toggle,on,onToggle,onClick,danger}){
  return <div className="cc-row" onClick={onClick||onToggle} style={{cursor:'pointer'}}>
    <span style={{width:30,height:30,borderRadius:8,background:'var(--surface-2)',border:'1px solid var(--line)',display:'flex',alignItems:'center',justifyContent:'center',color:danger?'var(--r-crit)':'var(--ink-2)',flex:'none'}}><Ic d={icon} s={16}/></span>
    <div className="grow"><div className="t" style={{fontSize:14.5,color:danger?'var(--r-crit)':'var(--ink)'}}>{title}</div>{detail&&<div className="s" style={{whiteSpace:'normal'}}>{detail}</div>}</div>
    {toggle ? <span className={'cc-toggle'+(on?' on':'')}><span className="knob"/></span> : <Ic d={ICON.chev} s={16}/>}
  </div>;
}
function SettingsScreen({onPolicy, onLibrary, onReplay}){
  const [faceid,setFaceid]=React.useState(true);
  const [redact,setRedact]=React.useState(true);
  return (
    <div className="cc-scroll">
      <StatusHeader state="ok" label="bridge connected" detail="conduitd v1.0"/>
      <PromptHeader title="settings" crumb={<b>device &amp; policy</b>}/>
      <div className="cc-pad">
        <div className="cc-sec">bridge &amp; hosts<span className="rule"/></div>
        <div className="cc-card">
          <SettingsRow icon={ICON.fleet} title="Hosts" detail="3 connected · Dev VPS, Staging, Pi"/>
          <SettingsRow icon={ICON.shield} title="Bridge status" detail="running · attached"/>
          <SettingsRow icon={ICON.term} title="Open terminal" detail="power-user · live session"/>
        </div>

        <div className="cc-sec">approvals<span className="rule"/></div>
        <div className="cc-card">
          <SettingsRow icon={ICON.shield} title="Policy" detail="balanced · 6 rules" onClick={onPolicy}/>
          <SettingsRow icon={ICON.bell} title="Notifications" detail="high & critical · quiet 11pm–8am"/>
        </div>

        <div className="cc-sec">security<span className="rule"/></div>
        <div className="cc-card">
          <SettingsRow icon={ICON.lock} title="Face ID lock" detail="require to open & approve critical" toggle on={faceid} onToggle={()=>setFaceid(!faceid)}/>
          <SettingsRow icon={ICON.shield} title="Redact secrets in output" toggle on={redact} onToggle={()=>setRedact(!redact)}/>
          <SettingsRow icon={ICON.clock} title="Audit log" detail="every decision, on-device"/>
        </div>

        <div className="cc-sec">library<span className="rule"/></div>
        <div className="cc-card">
          <SettingsRow icon={ICON.book} title="Snippets & keys" detail="7 snippets · enclave-backed keys" onClick={onLibrary}/>
        </div>

        <div className="cc-sec">account<span className="rule"/></div>
        <div className="cc-card">
          <SettingsRow icon={ICON.bolt} title="Conduit Pro" detail="lifetime · unlocked"/>
          <SettingsRow icon={ICON.card} title="Billing & usage" detail="$4.94 today · across vendors"/>
        </div>

        <p className="cc-note" onClick={onReplay} style={{textAlign:'center',margin:'22px 0 0',cursor:'pointer'}}>Conduit 1.0 · conduitd v1.0 · your code stays on your host</p>
      </div>
      <div className="cc-bottompad"/>
    </div>
  );
}

Object.assign(window,{SubNav,OnboardingFlow,OnbStep,CCInput,DispatchScreen,PolicyScreen,EffectChip,SettingsScreen,SettingsRow});
