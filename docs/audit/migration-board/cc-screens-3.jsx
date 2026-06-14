/* ============================================================
   CONDUIT — backend-backed screens that were missing from the board
   Each surfaces an IMPLEMENTED capability (conduitd RPC or push-backend route):
     • EditRunScreen / AllowAlwaysSheet  — agent.approval.response (edit / standing-rule)
     • AgentRunDetailScreen              — agent.status + agent.cancel (run-control)
     • PolicyYamlScreen                  — agent.policy.get / set / reload (raw YAML)
     • NotificationsScreen               — APNs categories + quiet hours
     • ProviderKeysScreen                — provider key storage/test (+ OpenRouter)
     • BillingScreen / PaywallScreen     — /billing/* + /billing/quota + /billing/credits
     • TofuSheet                         — host-key trust-on-first-use
     • TerminalScreen                    — live block session (kept, power-user)
   ============================================================ */

const XIC = {
  stop:<rect x="7" y="7" width="10" height="10" rx="1"/>,
  refresh:<><path d="M21 12a9 9 0 1 1-3-6.7"/><path d="M21 4v5h-5"/></>,
  gauge:<><path d="M12 13l4-4"/><path d="M3.5 16a8.5 8.5 0 1 1 17 0"/></>,
  sliders:<><path d="M4 7h9M17 7h3M4 12h3M11 12h9M4 17h7M15 17h5"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="13" cy="17" r="2"/></>,
  moon:<path d="M21 12.8A8 8 0 1 1 11.2 3a6 6 0 0 0 9.8 9.8z"/>,
  nudge:<><path d="M12 3v9"/><path d="M8 7l4-4 4 4"/><circle cx="12" cy="17" r="1.4"/></>,
  pause:<><rect x="7" y="6" width="3.5" height="12" rx="1"/><rect x="13.5" y="6" width="3.5" height="12" rx="1"/></>,
};

/* ---------- REDESIGN · Edit & run (the 3rd decision action) ---------- */
function EditRunScreen(){
  return (
    <div className="cc">
      <SubNav title="edit &amp; run" right={<RiskChip level="high"/>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Adjust the command before it runs. Conduit re-checks the edited version against your policy.</p>
          <div className="cc-card" style={{padding:'12px 14px',marginBottom:12,display:'flex',alignItems:'center',gap:10}}>
            <VendorMark vendor="claude"/>
            <span style={{marginLeft:'auto',fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink-3)'}}>~/repos/conduit</span>
          </div>
          <div className="cc-sec">original<span className="rule"/></div>
          <div className="cc-cmd" data-r="high" style={{opacity:.6}}><div className="gut"/><div className="body"><span className="sigil">$ </span>rm -rf build/ dist/</div></div>
          <div className="cc-sec">edited<span className="rule"/></div>
          <CCInput value="rm -rf build/" onChange={()=>{}} multiline mono/>
          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start',borderColor:'var(--r-low-bd)',background:'var(--r-low-bg)'}}>
            <span style={{color:'var(--r-low)',flex:'none',marginTop:1}}><Ic d={ICON.check} s={15}/></span>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Narrowing to <b style={{color:'var(--ink)'}}>build/</b> drops the <b style={{color:'var(--ink)'}}>dist/</b> deletion — risk falls to <b style={{color:'var(--r-low)'}}>low</b>.</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <div className="cc-btnrow">
          <button className="cc-btn cc-btn--quiet" style={{flex:1}}><Ic d={ICON.x} s={14}/>Cancel</button>
          <button className="cc-btn cc-btn--primary" style={{flex:1.4}}><Ic d={ICON.check} s={15}/>Run edited</button>
        </div>
      </div>
    </div>
  );
}

/* ---------- ADD · Allow always → a standing rule gets written ---------- */
function AllowAlwaysSheet(){
  return (
    <div className="cc-sheetwrap">
      <div className="cc-scrim"/>
      <div className="cc-sheet">
        <div className="grip"/>
        <div className="sheetscroll">
          <h2 className="cc-h2" style={{marginBottom:6}}>Create a standing rule?</h2>
          <div className="cc-note" style={{marginBottom:16}}>Future matches auto-allow — you won't be asked again.</div>
          <div className="cc-sec">rule to write<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 0'}}>
            {[['tool','command'],['input','git status'],['path','~/repos/conduit'],['effect','allow']].map(([k,v],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <span style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-4)',width:54,flex:'none'}}>{k}</span>
                <span style={{fontFamily:'var(--mono)',fontSize:13,color:k==='effect'?'var(--r-low)':'var(--ink)'}}>{v}</span>
              </div>
            ))}
          </div>
          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.shield} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Scoped to this exact tool, input &amp; path. Edit or revoke any time in <b style={{color:'var(--ink)'}}>Settings → Policy</b>.</span>
          </div>
        </div>
        <div className="sheetfoot">
          <div className="cc-btnrow">
            <button className="cc-btn cc-btn--quiet" style={{flex:1}}>Just once</button>
            <button className="cc-btn cc-btn--primary" style={{flex:1.3}}><Ic d={ICON.check} s={15}/>Write rule</button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ---------- ADD · Agent run detail + run-control (agent.status / agent.cancel) ---------- */
function CtrlBtn({icon, label, soon, danger}){
  return <button className="cc-btn cc-btn--quiet" style={{flex:1,flexDirection:'column',gap:5,height:'auto',padding:'12px 4px',position:'relative',color:danger?'var(--r-crit)':'var(--ink-2)',borderColor:danger?'var(--r-crit-bd)':'var(--line)'}}>
    <Ic d={icon} s={17}/>
    <span style={{fontSize:11}}>{label}</span>
    {soon && <span style={{position:'absolute',top:5,right:5,fontFamily:'var(--mono)',fontSize:8,letterSpacing:'.06em',color:'var(--ink-4)',border:'1px solid var(--line)',borderRadius:2,padding:'1px 3px'}}>SOON</span>}
  </button>;
}
function AgentRunDetailScreen(){
  const out=[
    ['$ swift build','c'],
    ['Compiling ConduitKit (38 files)','o'],
    ['[142/318] Compiling SessionViewModel.swift','o'],
    ['patch src/auth/session.swift','o'],
    ['› waiting on your decision in Inbox','w'],
  ];
  return (
    <div className="cc">
      <SubNav title="run" right={<span className="cc-sd"><span className="d working"/>working</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div className="cc-card" style={{padding:'14px 15px'}}>
            <div style={{display:'flex',alignItems:'center',gap:10}}>
              <PixelAvatar seed="claudeconduit" size={38} color={VENDOR.claude.c}/>
              <div className="grow" style={{minWidth:0}}>
                <div style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink)',fontWeight:500}}>Claude Code <span style={{color:'var(--ink-4)',fontSize:11.5}}>conduit</span></div>
                <div className="s" style={{marginTop:3}}>Dev VPS · claude-sonnet-4.6</div>
              </div>
              <div style={{textAlign:'right'}}>
                <div style={{fontFamily:'var(--mono)',fontSize:15,color:'var(--ink)'}}>$3.18</div>
                <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginTop:2}}>of $5.00</div>
              </div>
            </div>
            <div style={{display:'flex',gap:4,marginTop:13,height:5,borderRadius:3,overflow:'hidden',background:'var(--surface-2)'}}>
              <div style={{width:'64%',background:'var(--brand)'}}/>
            </div>
          </div>

          <div className="cc-sec">live output<span className="n">· tail</span><span className="rule"/></div>
          <div className="cc-cmd" style={{display:'block',padding:0}}>
            <div className="body" style={{whiteSpace:'pre-wrap',padding:'11px 13px',fontSize:11.5,lineHeight:1.75}}>
              {out.map(([t,k],i)=>(
                <div key={i} style={{color:k==='c'?'var(--ink)':k==='w'?'var(--r-med)':'var(--ink-3)'}}>{t}{k==='w'&&<span className="cursor" style={{height:'.8em'}}/>}</div>
              ))}
            </div>
          </div>

          <div className="cc-sec">controls <span className="n">· two-way v1</span><span className="rule"/></div>
          <div className="cc-btnrow" style={{gap:8}}>
            <CtrlBtn icon={XIC.stop} label="Stop" danger/>
            <CtrlBtn icon={XIC.pause} label="Pause"/>
            <CtrlBtn icon={XIC.gauge} label="Budget"/>
          </div>
          <p className="cc-note" style={{margin:'12px 4px 0'}}><b style={{color:'var(--ink-2)'}}>Stop · pause/resume · set-budget</b> ship in v1 two-way control. Nudge and mid-run model/account switch are deferred (see the roadmap ledger).</p>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- REDESIGN · Policy.yaml editor + reload-on-bridge (agent.policy.set/reload) ---------- */
function PolicyYamlScreen(){
  const yaml=[
    ['default: ask','k'],
    ['rules:','k'],
    ['  - match: {tool: read}      effect: allow','a'],
    ['  - match: {tool: write, path: "*.{ts,go}"}','a'],
    ['    effect: allow','a'],
    ['  - match: {tool: delete}    effect: ask','m'],
    ['  - match: {tool: network}   effect: ask','m'],
    ['  - match: {path: ".env"}    effect: deny','d'],
  ];
  return (
    <div className="cc">
      <SubNav title="policy.yaml" right={<span className="cc-chip"><Ic d={ICON.git} s={12}/>on host</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Edit the raw policy the bridge enforces. Changes are saved to the host and applied when you reload.</p>
          <div className="cc-cmd" style={{display:'block',padding:0}}>
            <div className="body" style={{whiteSpace:'pre',padding:'12px 13px',fontSize:11.5,lineHeight:1.8}}>
              {yaml.map(([t,k],i)=>(
                <div key={i} style={{color:k==='a'?'var(--r-low)':k==='m'?'var(--r-med)':k==='d'?'var(--r-crit)':'var(--ink-2)'}}>{t}</div>
              ))}
            </div>
          </div>
          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.shield} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Validated before save. The bridge reloads in place — running agents pick up new rules on their next call.</span>
          </div>
          <p className="cc-note" style={{margin:'10px 4px 0'}}>Editing is enabled only while the bridge is connected.</p>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <div className="cc-btnrow">
          <button className="cc-btn cc-btn--quiet" style={{flex:1}}>Discard</button>
          <button className="cc-btn cc-btn--primary" style={{flex:1.5}}><Ic d={XIC.refresh} s={15}/>Save &amp; reload bridge</button>
        </div>
      </div>
    </div>
  );
}

/* ---------- REDESIGN · Notifications (severity filters + quiet hours) ---------- */
function NotifRow({label, sub, on, locked}){
  return <div className="cc-row" style={{cursor:locked?'default':'pointer'}}>
    <div className="grow"><div className="t" style={{fontSize:14}}>{label}</div>{sub&&<div className="s" style={{whiteSpace:'normal'}}>{sub}</div>}</div>
    {locked
      ? <span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--r-crit)',border:'1px solid var(--r-crit-bd)',background:'var(--r-crit-bg)',borderRadius:2,padding:'2px 7px'}}>always</span>
      : <span className={'cc-toggle'+(on?' on':'')}><span className="knob"/></span>}
  </div>;
}
function NotificationsScreen(){
  return (
    <div className="cc">
      <SubNav title="notifications"/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Only the severities you choose reach your phone. Everything else resolves under policy, silently.</p>
          <div className="cc-sec">push when an action is<span className="rule"/></div>
          <div className="cc-card">
            <NotifRow label="Critical" sub="secrets · network · destructive" locked/>
            <NotifRow label="High" sub="deletes, broad writes" on/>
            <NotifRow label="Medium" sub="ordinary writes &amp; patches"/>
            <NotifRow label="Low" sub="read-only — never escalated"/>
          </div>
          <div className="cc-sec">quiet hours<span className="rule"/></div>
          <div className="cc-card">
            <div className="cc-row" style={{cursor:'pointer'}}>
              <span style={{width:30,height:30,borderRadius:2,background:'var(--surface-2)',border:'1px solid var(--line)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--ink-2)',flex:'none'}}><Ic d={XIC.moon} s={15}/></span>
              <div className="grow"><div className="t" style={{fontSize:14}}>11:00 PM – 8:00 AM</div><div className="s">mute high &amp; below while you sleep</div></div>
              <span className="cc-toggle on"><span className="knob"/></span>
            </div>
          </div>
          <p className="cc-note" style={{margin:'10px 4px 0'}}>Critical actions break through quiet hours — a destructive or credential action always wakes you.</p>
          <button className="cc-btn cc-btn--ghost cc-btn--block" style={{marginTop:14}}><Ic d={ICON.bell} s={15}/>Send a test notification</button>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- REDESIGN · Provider keys (multi-vendor; keys go direct to provider) ---------- */
function KeyRow({vendor, label, sub, state, accent}){
  return <div className="cc-row" style={{cursor:'pointer'}}>
    <PixelAvatar seed={vendor} size={30} color={accent}/>
    <div className="grow" style={{minWidth:0}}><div className="t" style={{fontSize:14}}>{label}</div><div className="s">{sub}</div></div>
    {state==='local'
      ? <span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--r-low)',border:'1px solid var(--r-low-bd)',background:'var(--r-low-bg)',borderRadius:2,padding:'2px 7px'}}>no key · local</span>
      : state==='add'
      ? <span className="cc-chip" style={{color:'var(--brand)',borderColor:'var(--brand)'}}>add</span>
      : <span className="cc-sd"><span className="d done"/>connected</span>}
  </div>;
}
function ProviderKeysScreen(){
  return (
    <div className="cc">
      <SubNav title="provider keys"/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Add the providers your agents use. Keys live in the Keychain and go straight to the provider — Conduit's relay never sees them.</p>
          <div className="cc-card">
            <KeyRow vendor="claude" accent={VENDOR.claude.c} label="Anthropic" sub="sk-ant-…M2 · Claude Code" state="ok"/>
            <KeyRow vendor="codex" accent={VENDOR.codex.c} label="OpenAI" sub="sk-…9f · Codex" state="ok"/>
            <KeyRow vendor="openrouter" accent="#56b3c2" label="OpenRouter" sub="one key, many models · balance shown in Billing" state="add"/>
            <KeyRow vendor="opencode" accent={VENDOR.opencode.c} label="Local · Ollama / llama.cpp" sub="opencode → self-hosted model" state="local"/>
          </div>
          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.lock} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Each key is tested against the provider before it's saved. Local models need no key — and nothing leaves the host.</span>
          </div>
          <button className="cc-btn cc-btn--ghost cc-btn--block" style={{marginTop:14}}><Ic d={ICON.plus} s={15}/>Add a provider</button>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- REDESIGN · Billing & usage (/billing/quota · /billing/credits · subscription) ---------- */
function QuotaRow({label, sub, pct, tone}){
  const c=tone||'var(--brand)';
  return <div style={{padding:'11px 0'}}>
    <div style={{display:'flex',alignItems:'baseline',justifyContent:'space-between',marginBottom:7}}>
      <span style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)'}}>{label}</span>
      <span style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink-3)'}}>{sub}</span>
    </div>
    <div style={{display:'flex',gap:4,height:6,borderRadius:3,overflow:'hidden',background:'var(--surface-2)'}}>
      <div style={{width:pct+'%',background:c}}/>
    </div>
  </div>;
}
function BillingScreen(){
  return (
    <div className="cc">
      <SubNav title="billing &amp; usage" right={<span className="cc-chip"><Ic d={ICON.bolt} s={12}/>Pro</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          {/* spend hero — cross-vendor, the Tier-1 usage glance */}
          <div className="cc-card" style={{padding:'16px 16px 14px'}}>
            <div style={{display:'flex',alignItems:'flex-end',justifyContent:'space-between'}}>
              <div>
                <div style={{fontFamily:'var(--mono)',fontSize:34,fontWeight:700,color:'var(--ink)',lineHeight:1,letterSpacing:'-.02em'}}>$4.94</div>
                <div className="cc-note" style={{marginTop:5}}>AI spend today · across vendors</div>
              </div>
              <div style={{textAlign:'right'}}>
                <div style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-2)'}}>≈ $6 / day</div>
                <div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)',marginTop:3}}>$25 cap</div>
              </div>
            </div>
          </div>

          <div className="cc-sec">quota remaining<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 15px 10px'}}>
            <QuotaRow label="Claude · 5-hour window" sub="62% used · resets 2:40" pct={62} tone="#b5352a"/>
            <QuotaRow label="Claude · weekly" sub="41% used" pct={41} tone="#c2622c"/>
            <QuotaRow label="Codex · API credit" sub="$13.40 left" pct={46} tone="#8a5fbf"/>
            <QuotaRow label="OpenRouter · balance" sub="$22.10 left" pct={78} tone="#4f63c9"/>
          </div>
          <p className="cc-note" style={{margin:'10px 4px 0'}}>Read best-effort from each provider on the host. A usage read never blocks an agent.</p>

          <div className="cc-sec">plan<span className="rule"/></div>
          <div className="cc-card">
            <div className="cc-row" style={{cursor:'default'}}>
              <span style={{width:30,height:30,borderRadius:2,background:'var(--surface-2)',border:'1px solid var(--line)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--brand)',flex:'none'}}><Ic d={ICON.bolt} s={16}/></span>
              <div className="grow"><div className="t" style={{fontSize:14}}>Conduit Pro</div><div className="s">cloud agents · multi-host · team org</div></div>
              <span className="cc-sd"><span className="d done"/>active</span>
            </div>
            <div className="cc-row" style={{cursor:'pointer'}}>
              <span style={{width:30,height:30,borderRadius:2,background:'var(--surface-2)',border:'1px solid var(--line)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--ink-2)',flex:'none'}}><Ic d={ICON.card} s={16}/></span>
              <div className="grow"><div className="t" style={{fontSize:14}}>Manage subscription</div><div className="s">Stripe portal · invoices · restore</div></div>
              <Ic d={ICON.chev} s={16}/>
            </div>
          </div>
          <p className="cc-note" style={{textAlign:'center',margin:'18px 0 0'}}>BYO-host stays free forever. Pro only unlocks hosted execution.</p>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- REDESIGN · Paywall (/billing/checkout) ---------- */
function PaywallSheet(){
  const feats=[
    ['Cloud agents','run tasks when your machine is off'],
    ['Multi-host fleet','route a run to the cheapest free host'],
    ['Team org','shared policy & a team approval inbox'],
    ['Priority relay','first in line when notifications spike'],
  ];
  return (
    <div className="cc-sheetwrap">
      <div className="cc-scrim"/>
      <div className="cc-sheet" style={{maxHeight:'88%'}}>
        <div className="grip"/>
        <div className="sheetscroll">
          <Spectrum/>
          <h2 className="cc-h2" style={{margin:'14px 0 4px'}}>Conduit Pro</h2>
          <div className="cc-note" style={{marginBottom:18}}>The private bridge is free. Pro adds hosted muscle.</div>
          <div style={{display:'flex',flexDirection:'column',gap:2}}>
            {feats.map(([t,s],i)=>(
              <div key={i} style={{display:'flex',gap:11,alignItems:'flex-start',padding:'10px 0'}}>
                <span style={{color:'var(--brand)',flex:'none',marginTop:1}}><Ic d={ICON.check} s={16}/></span>
                <div><div style={{fontFamily:'var(--mono)',fontSize:13.5,color:'var(--ink)'}}>{t}</div><div className="s">{s}</div></div>
              </div>
            ))}
          </div>
          <div className="cc-seg" style={{marginTop:16}}>
            <button className="on">$79 lifetime</button>
            <button>$8 / month</button>
          </div>
        </div>
        <div className="sheetfoot">
          <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}}><Ic d={ICON.bolt} s={16}/>Unlock Pro</button>
          <p className="cc-note" style={{textAlign:'center',margin:'10px 0 0'}}>Restore purchase · payments via the App Store</p>
        </div>
      </div>
    </div>
  );
}

/* ---------- ADD · TOFU host-key trust (advanced SSH path) ---------- */
function TofuSheet(){
  return (
    <div className="cc-sheetwrap">
      <div className="cc-scrim"/>
      <div className="cc-sheet">
        <div className="grip"/>
        <div className="sheetscroll">
          <div style={{display:'flex',alignItems:'center',gap:10,margin:'4px 0 14px'}}>
            <span style={{color:'var(--r-med)'}}><Ic d={ICON.shield} s={20}/></span>
            <h2 className="cc-h2" style={{margin:0}}>New host key</h2>
          </div>
          <p style={{fontSize:13.5,color:'var(--ink-2)',lineHeight:1.55,margin:'0 0 16px'}}>First time connecting to <b style={{color:'var(--ink)',fontFamily:'var(--mono)'}}>dev-vps</b>. Verify this fingerprint matches the server before you trust it.</p>
          <div className="cc-sec">ed25519 fingerprint<span className="rule"/></div>
          <div className="cc-cmd"><div className="gut"/><div className="body" style={{fontSize:11.5,padding:'11px 12px',color:'var(--ink-2)',wordBreak:'break-all'}}>SHA256:k7Hf3…Qx9Lm2pR8vNcUeJdW0aZ</div></div>
          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.lock} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Pinned after you trust it — Conduit warns you if it ever changes (possible man-in-the-middle).</span>
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

/* ---------- KEEP · Live block session (power-user, demoted from a tab) ---------- */
function TermBlock({prompt, cmd, lines, status, live}){
  return <div className="cc-card" style={{padding:0,marginBottom:10,overflow:'hidden',borderColor:live?'var(--brand)':'var(--line)'}}>
    <div style={{display:'flex',alignItems:'center',gap:8,padding:'8px 12px',borderBottom:'1px solid var(--line-2)',background:'var(--surface-2)'}}>
      <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>{prompt}</span>
      <span style={{marginLeft:'auto'}}>{status==='ok'
        ? <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--r-low)'}}>✓ exit 0</span>
        : <span className="cc-sd"><span className="d working"/>running</span>}</span>
    </div>
    <div style={{fontFamily:'var(--mono)',fontSize:12,padding:'10px 12px'}}>
      <div style={{color:'var(--ink)'}}><span style={{color:'var(--brand)'}}>$ </span>{cmd}</div>
      {lines&&lines.map((l,i)=>(<div key={i} style={{color:'var(--ink-3)',marginTop:4}}>{l}</div>))}
      {live&&<div style={{color:'var(--r-med)',marginTop:4}}>● thinking<span className="cursor" style={{height:'.8em'}}/></div>}
    </div>
  </div>;
}
function TerminalScreen(){
  return (
    <div className="cc">
      <SubNav title="session" right={<span className="cc-sd"><span className="d working"/>dev-vps</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-note" style={{margin:'0 0 12px'}}>Power-user · the real PTY in Warp-style blocks. Reachable from <b style={{color:'var(--ink-2)'}}>Settings → Open terminal</b>.</p>
          <TermBlock prompt="~/repos/conduit ›" cmd="swift build" lines={['Build complete! (12.4s)']} status="ok"/>
          <TermBlock prompt="~/repos/conduit ›" cmd="claude" status="run" live/>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <div style={{display:'flex',alignItems:'center',background:'var(--bg-2)',border:'1px solid var(--line)',borderRadius:'var(--r-md)',height:46,padding:'0 13px',gap:9}}>
          <span style={{fontFamily:'var(--mono)',color:'var(--brand)',fontSize:14}}>›</span>
          <span style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink-4)'}}>type a command or talk to the agent…<span className="cursor" style={{height:'.8em'}}/></span>
        </div>
      </div>
    </div>
  );
}

/* ---------- KEEP · SSH keys (real data, no fake host counts) — kept because SSH stays as the advanced path ---------- */
function SshKeyRow({name, fp, used, host}){
  return <div className="cc-row" style={{cursor:'pointer'}}>
    <PixelAvatar seed={name} size={30} color="#56b3c2"/>
    <div className="grow" style={{minWidth:0}}>
      <div className="t" style={{fontSize:14}}>{name}</div>
      <div className="s" style={{fontFamily:'var(--mono)'}}>ed25519 · {fp}</div>
    </div>
    <div style={{flex:'none',textAlign:'right'}}>
      <div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>{host}</div>
      <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginTop:2}}>{used}</div>
    </div>
  </div>;
}
function SshKeysScreen(){
  return (
    <div className="cc">
      <SubNav title="ssh keys"/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Keys for reaching your hosts over SSH — the advanced path. Generated on-device and held in the Keychain; the private key never leaves this phone.</p>
          <div className="cc-card">
            <SshKeyRow name="conduit-dev" fp="SHA256:k7Hf3…Lm2" used="used 2h ago" host="dev-vps"/>
            <SshKeyRow name="ci-runner" fp="SHA256:9aQ2x…pR8" used="used Jun 11" host="staging"/>
          </div>
          <div className="cc-btnrow" style={{marginTop:14}}>
            <button className="cc-btn cc-btn--ghost" style={{flex:1}}><Ic d={ICON.plus} s={15}/>Generate</button>
            <button className="cc-btn cc-btn--ghost" style={{flex:1}}><Ic d={ICON.copy} s={14}/>Import</button>
          </div>
          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.lock} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Tap a key to copy its public half, rotate, or revoke. Each shows its real fingerprint and where it was last used — no placeholder counts.</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- ADD · full-file viewer — tap a file → bottom drawer ---------- */
function FileViewerSheet(){
  const lines=[
    'import Foundation','','final class SessionViewModel: ObservableObject {','  @Published var blocks: [Block] = []','  private let bridge: PTYBridge','','  init(bridge: PTYBridge) {','    self.bridge = bridge','  }','','  func onBlockBytes(_ data: Data) {','    let timeout = 60','    let retries = 3','    bridge.feed(data, timeout: timeout)','  }','}',
  ];
  return (
    <div className="cc-sheetwrap">
      <div className="cc-scrim"/>
      <div className="cc-sheet" style={{maxHeight:'90%'}}>
        <div className="grip"/>
        <div style={{display:'flex',alignItems:'center',gap:9,padding:'2px 18px 10px',borderBottom:'1px solid var(--line-2)'}}>
          <Ic d={ICON.file} s={15}/>
          <div style={{minWidth:0}}>
            <div style={{fontFamily:'var(--mono)',fontSize:13.5,color:'var(--ink)',fontWeight:600}}>session.swift</div>
            <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)'}}>~/repos/conduit/Sources · 16 lines · read-only</div>
          </div>
          <button className="cc-btn cc-btn--quiet" style={{marginLeft:'auto',width:34,height:34,padding:0}}><Ic d={ICON.x} s={16}/></button>
        </div>
        <div className="sheetscroll" style={{padding:0,flex:1,overflowY:'auto'}}>
          <div style={{fontFamily:'var(--mono)',fontSize:12,lineHeight:1.85,padding:'10px 0'}}>
            {lines.map((l,i)=>(
              <div key={i} style={{display:'flex',gap:12,padding:'0 16px'}}>
                <span style={{color:'var(--ink-4)',textAlign:'right',width:20,flex:'none',userSelect:'none'}}>{i+1}</span>
                <span style={{color:l.includes('let ')||l.includes('func ')||l.includes('class ')||l.includes('import ')?'var(--ink)':'var(--ink-2)',whiteSpace:'pre'}}>{l||' '}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="sheetfoot" style={{display:'flex',alignItems:'center',gap:10}}>
          <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)'}}>tap-to-open · swipe down to dismiss</span>
          <button className="cc-btn cc-btn--quiet" style={{marginLeft:'auto'}}><Ic d={ICON.copy} s={14}/>Copy</button>
        </div>
      </div>
    </div>
  );
}

Object.assign(window,{
  XIC,EditRunScreen,AllowAlwaysSheet,AgentRunDetailScreen,PolicyYamlScreen,
  NotificationsScreen,ProviderKeysScreen,BillingScreen,PaywallSheet,TofuSheet,TerminalScreen,
  SshKeysScreen,SshKeyRow,FileViewerSheet,
});
