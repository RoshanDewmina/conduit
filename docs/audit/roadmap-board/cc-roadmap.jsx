/* ============================================================
   LANCER — ROADMAP BOARD (future / post-launch features)

   A SEPARATE board from the migration board. Every artboard is a
   phone screen for a DEFERRED feature from
   docs/audit/LAUNCH_SCOPE_LEDGER.md §B, grouped by roadmap Tier
   (T0…T4 from the bridge-platform roadmap §5).

   Reuses the migration board's shared assets verbatim (loaded by
   index.html BEFORE this file):
     • lancer.css tokens + the .cc-* component classes
     • cc-components.jsx atoms (StatusHeader, PromptHeader, RiskChip,
       VendorMark, PixelAvatar, Ic/ICON, CommandBlock, BlastChips,
       TabBar, ccHash, VENDOR, sample data)
     • cc-screens-2.jsx (SubNav, CCInput, EffectChip)
     • cc-screens-3.jsx (XIC icon set, QuotaRow, KeyRow patterns)
     • design-canvas.jsx (DesignCanvas / DCSection / DCArtboard)

   Binding rules: docs/audit/LANCER_UI_CONSISTENCY_RULES.md
     - brand blue (#2f43ff) is CTA-only; risk uses its own ramp
     - data bars use the brand spectrum (#b5352a→#4f63c9)
     - .cc-foot for any bottom CTA (never a gradient)
     - 18px gutters; spacing on the 4·6·8·10·12·14·16·18·22·24·28 scale
   ============================================================ */

/* ---------- tier chip (corner badge — mirrors StatusTag) ---------- */
const TIER_META = {
  T0:{label:'T0 · foundations', c:'var(--ink-2)',  bg:'rgba(255,255,255,.06)', bd:'var(--line-strong)'},
  T1:{label:'T1 · usage',       c:'#56b3c2',        bg:'rgba(86,179,194,.16)',  bd:'rgba(86,179,194,.5)'},
  T2:{label:'T2 · control',     c:'#8aa0ff',        bg:'rgba(47,67,255,.18)',   bd:'rgba(47,67,255,.55)'},
  T3:{label:'T3 · awareness',   c:'#d9b24a',        bg:'rgba(217,178,74,.16)',  bd:'rgba(217,178,74,.5)'},
  T4:{label:'T4 · trust',       c:'#b07ad9',        bg:'rgba(176,122,217,.18)', bd:'rgba(176,122,217,.55)'},
};
function TierTag({ t }){
  const m = TIER_META[t] || TIER_META.T0;
  return <div className="cc-tag" style={{color:m.c,background:m.bg,borderColor:m.bd}}>
    <span className="d" style={{background:m.c}}/>{m.label}
  </div>;
}
/* small inline "future" ribbon so each screen reads as not-yet-shipped */
function SoonChip(){
  return <span className="cc-chip" style={{color:'var(--ink-3)',borderColor:'var(--line-strong)',letterSpacing:'.08em',textTransform:'uppercase',fontSize:9.5}}>roadmap</span>;
}

/* phone-frame wrappers that stamp a tier tag */
function RFrame({ t, children }){
  return <div className="cc cc-frame" style={{position:'relative'}}>
    {t && <TierTag t={t}/>}
    {children}
  </div>;
}
function RTabFrame({ t, tab='fleet', count=0, children }){
  return <div className="cc cc-frame" style={{position:'relative'}}>
    {t && <TierTag t={t}/>}
    <div style={{flex:1,position:'relative',overflow:'hidden',display:'flex',flexDirection:'column'}}>{children}</div>
    <TabBar active={tab} onChange={()=>{}} inboxCount={count}/>
  </div>;
}

/* small shared bits ----------------------------------------- */
const RX = {
  relay:<><circle cx="12" cy="12" r="2.4"/><path d="M5 12a7 7 0 0 1 14 0M2 12a10 10 0 0 1 20 0"/></>,
  plug:<><path d="M9 2v6M15 2v6"/><path d="M7 8h10v3a5 5 0 0 1-10 0z"/><path d="M12 16v6"/></>,
  user:<><circle cx="12" cy="8" r="3.4"/><path d="M5 20a7 7 0 0 1 14 0"/></>,
  users:<><circle cx="9" cy="8" r="3"/><path d="M3 20a6 6 0 0 1 12 0"/><path d="M16 5.2a3 3 0 0 1 0 5.6M21 20a6 6 0 0 0-4-5.7"/></>,
  trend:<><path d="M3 17l5-6 4 3 6-8"/><path d="M18 6h3v3"/></>,
  alert:<><path d="M12 4l9 16H3z"/><path d="M12 10v4M12 17.5v.5"/></>,
  swap:<><path d="M7 4L3 8l4 4"/><path d="M3 8h13a4 4 0 0 1 0 8h-2"/><path d="M17 20l4-4-4-4"/></>,
  cpu:<><rect x="6" y="6" width="12" height="12" rx="1.5"/><path d="M9 2v2M15 2v2M9 20v2M15 20v2M2 9h2M2 15h2M20 9h2M20 15h2"/></>,
  branch:<><circle cx="6" cy="6" r="2.2"/><circle cx="6" cy="18" r="2.2"/><circle cx="18" cy="8" r="2.2"/><path d="M6 8v8M18 10c0 4-6 2-6 6"/></>,
  digest:<><path d="M5 4h14v16l-3-2-2 2-2-2-2 2-3-2z"/><path d="M8 8h8M8 12h8M8 16h5"/></>,
  vault:<><rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="12" cy="12" r="3.2"/><path d="M12 12h4"/></>,
  route:<><circle cx="5" cy="6" r="2"/><circle cx="19" cy="18" r="2"/><path d="M7 6h7a3 3 0 0 1 0 6H9a3 3 0 0 0 0 6h8"/></>,
  cloud:<><path d="M7 18a4 4 0 0 1 0-8 5 5 0 0 1 9.6-1.3A3.5 3.5 0 0 1 18 18z"/></>,
  scan:<><path d="M4 7V5a1 1 0 0 1 1-1h2M17 4h2a1 1 0 0 1 1 1v2M20 17v2a1 1 0 0 1-1 1h-2M7 20H5a1 1 0 0 1-1-1v-2"/><path d="M4 12h16"/></>,
  archive:<><rect x="3" y="4" width="18" height="4" rx="1"/><path d="M5 8v11a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8"/><path d="M10 12h4"/></>,
  calendar:<><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 9h18M8 3v4M16 3v4"/></>,
};

/* a section "hero" stat card used a few times (spectrum-bar series) */
function SpectrumBar({ segments }){
  // segments: [{pct, color}] ; colors should come from the brand spectrum
  return <div style={{display:'flex',gap:3,marginTop:14,height:6,borderRadius:3,overflow:'hidden',background:'var(--surface-2)'}}>
    {segments.map((s,i)=>(<div key={i} style={{width:s.pct+'%',background:s.color}}/>))}
  </div>;
}

/* a generic info callout (shield/lock note card) */
function NoteCard({ icon, children, tone }){
  const bd = tone==='ok' ? 'var(--r-low-bd)' : tone==='warn' ? 'var(--r-med-bd)' : 'var(--line)';
  const bg = tone==='ok' ? 'var(--r-low-bg)' : tone==='warn' ? 'var(--r-med-bg)' : 'var(--surface)';
  const ic = tone==='ok' ? 'var(--r-low)' : tone==='warn' ? 'var(--r-med)' : 'var(--ink-2)';
  return <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start',borderColor:bd,background:bg}}>
    <span style={{color:ic,flex:'none',marginTop:1}}><Ic d={icon} s={16}/></span>
    <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>{children}</span>
  </div>;
}

/* ============================================================
   TIER 0 · FOUNDATIONS
   ============================================================ */

/* ---------- T0 · E2E relay setup / status ---------- */
function RelayStatusScreen(){
  return (
    <div className="cc">
      <SubNav title="relay" right={<span className="cc-sd"><span className="d done"/>E2E</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 14px'}}>The live duplex relay carries approval cards and your decisions — ciphertext it can't read. Works on any network, behind NAT, on cellular.</p>

          {/* big connection-state card */}
          <div className="cc-card" style={{padding:'16px 16px 14px',borderColor:'var(--r-low-bd)'}}>
            <div style={{display:'flex',alignItems:'center',gap:11}}>
              <span style={{width:38,height:38,borderRadius:2,background:'var(--r-low-bg)',border:'1px solid var(--r-low-bd)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--r-low)',flex:'none'}}><Ic d={RX.relay} s={20}/></span>
              <div className="grow" style={{minWidth:0}}>
                <div style={{fontFamily:'var(--mono)',fontSize:15,color:'var(--ink)',fontWeight:600}}>relay: connected</div>
                <div className="s" style={{marginTop:2}}>duplex · end-to-end encrypted</div>
              </div>
              <span className="cc-sd"><span className="d done"/></span>
            </div>
            <div style={{display:'flex',gap:18,marginTop:14,paddingTop:13,borderTop:'1px solid var(--line-2)'}}>
              <div><div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)'}}>RTT</div><div style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink)',marginTop:3}}>38 ms</div></div>
              <div><div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)'}}>UPTIME</div><div style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink)',marginTop:3}}>4d 02h</div></div>
              <div><div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)'}}>CHANNEL</div><div style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--r-low)',marginTop:3}}>blind</div></div>
            </div>
          </div>

          <div className="cc-sec">what crosses the wire<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 0'}}>
            {[['the approval card · command, risk, paths',true],['your decision',true],['code · diffs · terminal output',false],['the model',false]].map(([t,on],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <span style={{flex:'none',color:on?'var(--brand)':'var(--r-low)'}}><Ic d={on?ICON.shield:ICON.check} s={15}/></span>
                <div className="grow"><div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink-2)'}}>{t}</div></div>
                <span style={{fontFamily:'var(--mono)',fontSize:10,color:on?'var(--brand)':'var(--r-low)'}}>{on?'encrypted':'stays on host'}</span>
              </div>
            ))}
          </div>

          <div className="cc-sec">transport<span className="rule"/></div>
          <div className="cc-card">
            <div className="cc-row" style={{cursor:'pointer'}}>
              <span style={{width:30,height:30,borderRadius:2,background:'var(--surface-2)',border:'1px solid var(--line)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--ink-2)',flex:'none'}}><Ic d={RX.relay} s={16}/></span>
              <div className="grow"><div className="t" style={{fontSize:14}}>Self-hosted relay</div><div className="s" style={{whiteSpace:'normal'}}>run the relay container yourself · nothing touches Lancer infra</div></div>
              <span className="cc-toggle"><span className="knob"/></span>
            </div>
          </div>
          <NoteCard icon={ICON.lock}>Keys derive at pairing. If the relay ever drops, Lancer falls back to SSH automatically — you stay reachable.</NoteCard>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--ghost cc-btn--block" style={{height:52}}><Ic d={RX.relay} s={16}/>Re-pair relay</button>
      </div>
    </div>
  );
}

/* ---------- T0 · Adapter SPI — add an agent (Class A vs Class B) ---------- */
function AdapterRow({ name, klass, surface, status }){
  const a = klass==='A';
  return <div className="cc-row" style={{cursor:'pointer'}}>
    <PixelAvatar seed={name} size={30} color={a?'#3fb57e':'#b07ad9'}/>
    <div className="grow" style={{minWidth:0}}>
      <div className="t" style={{fontSize:14,fontFamily:'var(--mono)'}}>{name}</div>
      <div className="s" style={{whiteSpace:'normal'}}>{surface}</div>
    </div>
    {status==='live'
      ? <span className="cc-sd"><span className="d done"/>live</span>
      : status==='soon'
      ? <span className="cc-chip" style={{color:'var(--ink-3)',borderColor:'var(--line-strong)'}}>planned</span>
      : <span className="cc-chip" style={{color:'var(--brand)',borderColor:'var(--brand)'}}>add</span>}
  </div>;
}
function AddAgentScreen(){
  return (
    <div className="cc">
      <SubNav title="add an agent" right={<SoonChip/>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Every agent integrates through the same seam — its tool-approval callback. A new agent is one small adapter.</p>

          <div className="cc-sec">class a · external pre-tool hook<span className="rule"/></div>
          <div className="cc-card">
            <AdapterRow name="claude" klass="A" surface="PreToolUse hook · reference adapter" status="live"/>
            <AdapterRow name="codex" klass="A" surface="approval / notify hook" status="live"/>
            <AdapterRow name="opencode" klass="A" surface="permission hook · local models" status="live"/>
            <AdapterRow name="gemini" klass="A" surface="BeforeTool hook · --emit json-decision" status="soon"/>
          </div>
          <p className="cc-note" style={{margin:'8px 4px 0'}}>lancerd's <b style={{color:'var(--ink-2)'}}>agent-hook CLI is the SPI</b> for Class A — copy the hook + a hooks.json fragment.</p>

          <div className="cc-sec">class b · via lancer-mcp gateway<span className="rule"/></div>
          <div className="cc-card">
            <AdapterRow name="goose" klass="B" surface="closed approval · MCP gateway" status="add"/>
            <AdapterRow name="cline" klass="B" surface="closed approval · MCP gateway" status="soon"/>
            <AdapterRow name="roo" klass="B" surface="closed approval · MCP gateway" status="soon"/>
            <AdapterRow name="kilo" klass="B" surface="closed approval · MCP gateway" status="soon"/>
          </div>
          <NoteCard icon={ICON.shield}>One <b style={{color:'var(--ink)'}}>lancer-mcp</b> gateway wraps dangerous tools as MCP and calls agent-hook internally — it unlocks goose, Cline, Roo &amp; Kilo together.</NoteCard>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}}><Ic d={ICON.plus} s={16}/>Install an adapter</button>
      </div>
    </div>
  );
}

/* ---------- T0 · Account registry (multi-account per vendor) ---------- */
function AcctRow({ vendor, accent, email, badge, active }){
  return <div className="cc-row" style={{cursor:'pointer'}}>
    <PixelAvatar seed={vendor+email} size={30} color={accent}/>
    <div className="grow" style={{minWidth:0}}>
      <div className="t" style={{fontSize:14}}>{email}</div>
      <div className="s">{badge}</div>
    </div>
    {active
      ? <span style={{width:18,height:18,borderRadius:'50%',border:'2px solid var(--brand)',display:'flex',alignItems:'center',justifyContent:'center',flex:'none'}}><span style={{width:8,height:8,borderRadius:'50%',background:'var(--brand)'}}/></span>
      : <span style={{width:18,height:18,borderRadius:'50%',border:'2px solid var(--ink-4)',flex:'none'}}/>}
  </div>;
}
function AccountRegistryScreen(){
  return (
    <div className="cc">
      <SubNav title="accounts" right={<SoonChip/>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Hold several accounts per vendor. The active one runs new tasks; failover and mid-run switch draw from the rest.</p>

          <div className="cc-sec">anthropic <span className="n">· 2 accounts</span><span className="rule"/></div>
          <div className="cc-card">
            <AcctRow vendor="claude" accent={VENDOR.claude.c} email="me@personal.dev" badge="Max · 41% weekly left" active/>
            <AcctRow vendor="claude" accent={VENDOR.claude.c} email="team@acme.io" badge="Pro · 88% weekly left"/>
          </div>

          <div className="cc-sec">openai <span className="n">· 1 account</span><span className="rule"/></div>
          <div className="cc-card">
            <AcctRow vendor="codex" accent={VENDOR.codex.c} email="dev@acme.io" badge="Codex · $13.40 credit" active/>
          </div>

          <div className="cc-sec">openrouter <span className="n">· 1 key</span><span className="rule"/></div>
          <div className="cc-card">
            <AcctRow vendor="openrouter" accent="#56b3c2" email="sk-or-…9f" badge="$22.10 balance" active/>
          </div>

          <NoteCard icon={ICON.lock}>Tokens stay in the Keychain on the host. Switching the active account never re-auths in the cloud — it just re-points the bridge.</NoteCard>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--ghost cc-btn--block" style={{height:52}}><Ic d={ICON.plus} s={16}/>Add an account</button>
      </div>
    </div>
  );
}

/* ---------- T0 · lancer user CLI ---------- */
function CliLine({ cmd, out }){
  return <div style={{marginBottom:14}}>
    <div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}><span style={{color:'var(--brand)'}}>$ </span>{cmd}</div>
    {out.map((l,i)=>(<div key={i} style={{fontFamily:'var(--mono)',fontSize:11.5,color:l[1]==='h'?'var(--ink)':l[1]==='w'?'var(--r-med)':'var(--ink-3)',marginTop:3,paddingLeft:14}}>{l[0]}</div>))}
  </div>;
}
function CliScreen(){
  return (
    <div className="cc">
      <SubNav title="lancer cli" right={<span className="cc-chip"><Ic d={ICON.term} s={12}/>your terminal</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>The bridge is a program on its own. Check usage, control runs and read status from any terminal — no phone required.</p>
          <div className="cc-cmd" style={{display:'block',padding:0}}>
            <div className="body" style={{display:'block',whiteSpace:'normal',padding:'13px 13px'}}>
              <CliLine cmd="lancer status" out={[['● bridge connected · relay E2E · 4 agents','h'],['  3 working · 1 waiting · $4.94 today','o']]}/>
              <CliLine cmd="lancer usage" out={[['claude 5h   ▓▓▓▓▓▓░░░░ 62%  resets 2:40','o'],['claude wk   ▓▓▓▓░░░░░░ 41%','o'],['codex       $13.40 credit left','o']]}/>
              <CliLine cmd="lancer runs" out={[['lancer     working   $3.18','o'],['auth-svc    waiting → approve in app','w']]}/>
              <CliLine cmd="lancer pause auth-svc" out={[['paused auth-svc · resume with `lancer resume`','o']]}/>
            </div>
          </div>
          <div className="cc-sec">commands<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 0'}}>
            {[['status','bridge + relay + spend at a glance'],['usage','quota remaining across vendors'],['runs','list active runs + state'],['pause / resume <id>','two-way control from the shell'],['dispatch "task"','start a run from the terminal']].map(([c,d],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)',width:128,flex:'none'}}>lancer {c}</span>
                <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)',whiteSpace:'normal'}}>{d}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--quiet cc-btn--block" style={{height:52}}><Ic d={ICON.copy} s={14}/>Copy install command</button>
      </div>
    </div>
  );
}

/* ---------- T0 · Vendor / model support matrix ---------- */
function MatrixScreen(){
  const ROWS=[
    ['opencode','permission + plugins','local','flagship','live'],
    ['Claude Code','PreToolUse hook','cloud','keep','live'],
    ['Codex','approval / notify','cloud','keep','live'],
    ['goose','MCP gateway','local','add','planned'],
    ['Gemini','BeforeTool hook','cloud','class A','planned'],
    ['Cline','VS Code ext API','local','watch','planned'],
  ];
  const ST={live:{c:'var(--r-low)',t:'live'},planned:{c:'var(--ink-3)',t:'planned'}};
  return (
    <div className="cc">
      <SubNav title="support matrix" right={<SoonChip/>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Agents × hook surface × model location. Vendor- and model-agnostic is the wedge no single-vendor app can match.</p>
          <div className="cc-card" style={{padding:'4px 0'}}>
            <div style={{display:'flex',alignItems:'center',padding:'9px 14px',gap:8}}>
              <span style={{flex:1,fontFamily:'var(--mono)',fontSize:9.5,color:'var(--ink-4)',letterSpacing:'.04em'}}>AGENT</span>
              <span style={{width:54,textAlign:'center',fontFamily:'var(--mono)',fontSize:9.5,color:'var(--ink-4)'}}>MODEL</span>
              <span style={{width:54,textAlign:'right',fontFamily:'var(--mono)',fontSize:9.5,color:'var(--ink-4)'}}>STATUS</span>
            </div>
            {ROWS.map(([name,surface,model,plan,status],i)=>{const s=ST[status];return (
              <div key={i} style={{display:'flex',alignItems:'center',padding:'11px 14px',gap:8,position:'relative'}}>
                <span style={{position:'absolute',top:0,left:14,right:14,height:1,background:'var(--line-2)'}}/>
                <div style={{flex:1,minWidth:0}}>
                  <div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{name}</div>
                  <div style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-4)',marginTop:2}}>{surface}</div>
                </div>
                <span style={{width:54,textAlign:'center'}}>{model==='local'
                  ? <span style={{fontFamily:'var(--mono)',fontSize:9.5,color:'var(--r-low)',border:'1px solid var(--r-low-bd)',background:'var(--r-low-bg)',borderRadius:2,padding:'2px 5px'}}>local</span>
                  : <span style={{fontFamily:'var(--mono)',fontSize:9.5,color:'var(--ink-3)',border:'1px solid var(--line)',borderRadius:2,padding:'2px 5px'}}>cloud</span>}</span>
                <span style={{width:54,textAlign:'right',fontFamily:'var(--mono)',fontSize:11,color:s.c}}>{s.t}</span>
              </div>
            );})}
          </div>
          <NoteCard icon={ICON.shield} tone="ok">Local-model rows run on the host — prompts and code never leave it. The bridge reads the active model to show this live.</NoteCard>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ============================================================
   TIER 1 · USAGE INTELLIGENCE
   ============================================================ */

/* ---------- T1 · Burn-rate projection ---------- */
function BurnRateScreen(){
  // sparkline-ish bars across the day (brand spectrum, climbing heat)
  const bars=[18,24,30,22,40,52,48,61,70,66,82,90];
  const spectrum=['#b5352a','#c2622c','#d09433','#dcc14a','#c07ea0','#8a5fbf','#4f63c9'];
  return (
    <div className="cc">
      <SubNav title="burn rate" right={<span className="cc-chip"><Ic d={RX.trend} s={12}/>today</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div className="cc-card" style={{padding:'16px 16px 14px'}}>
            <div style={{display:'flex',alignItems:'flex-end',justifyContent:'space-between'}}>
              <div>
                <div style={{fontFamily:'var(--mono)',fontSize:34,fontWeight:700,color:'var(--ink)',lineHeight:1,letterSpacing:'-.02em'}}>$4.94</div>
                <div className="cc-note" style={{marginTop:5}}>spent so far · projected <b style={{color:'var(--ink-2)'}}>$11.20</b> by midnight</div>
              </div>
              <div style={{textAlign:'right'}}>
                <div style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--r-med)'}}>↑ $0.86 / hr</div>
                <div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)',marginTop:3}}>$25 cap</div>
              </div>
            </div>
            {/* 12-hour burn sparkbars */}
            <div style={{display:'flex',alignItems:'flex-end',gap:3,height:54,marginTop:16}}>
              {bars.map((h,i)=>(<div key={i} style={{flex:1,height:h+'%',background:spectrum[Math.floor(i/bars.length*spectrum.length)],borderRadius:1,opacity:i>9?1:.85}}/>))}
            </div>
            <div style={{display:'flex',justifyContent:'space-between',marginTop:6,fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-4)'}}><span>08:00</span><span>now</span></div>
          </div>

          <div className="cc-sec">projection<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 0'}}>
            {[['end-of-day spend','≈ $11.20','var(--ink)'],['$25 cap reached','~ 11:40 PM','var(--r-med)'],['claude 5h quota exhausts','~ 2:10 PM','var(--r-high)']].map(([k,v,c],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <div className="grow"><div style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink-2)'}}>{k}</div></div>
                <span style={{fontFamily:'var(--mono)',fontSize:13,color:c}}>{v}</span>
              </div>
            ))}
          </div>
          <NoteCard icon={RX.trend} tone="warn">At the current rate Claude's 5-hour window empties before its 2:40 reset. Auto-failover (next) can route the overflow to your team account.</NoteCard>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- T1 · Limit alerts ---------- */
function AlertRow({ label, sub, pct, on, tone }){
  return <div style={{padding:'12px 16px',position:'relative'}}>
    <div style={{display:'flex',alignItems:'center',gap:10}}>
      <div className="grow"><div style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)'}}>{label}</div><div className="s" style={{marginTop:2}}>{sub}</div></div>
      <span style={{fontFamily:'var(--mono)',fontSize:13,color:tone}}>{pct}%</span>
      <span className={'cc-toggle'+(on?' on':'')}><span className="knob"/></span>
    </div>
  </div>;
}
function LimitAlertsScreen(){
  return (
    <div className="cc">
      <SubNav title="limit alerts" right={<SoonChip/>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Get a push before you hit a wall. Alerts fire once per window and never block an agent.</p>
          <div className="cc-sec">alert when usage crosses<span className="rule"/></div>
          <div className="cc-card" style={{padding:'2px 0'}}>
            <AlertRow label="Claude · weekly" sub="threshold · notify once" pct={80} on tone="var(--r-med)"/>
            <div style={{height:1,background:'var(--line-2)',margin:'0 16px'}}/>
            <AlertRow label="Claude · 5-hour window" sub="threshold · notify once" pct={90} on tone="var(--r-high)"/>
            <div style={{height:1,background:'var(--line-2)',margin:'0 16px'}}/>
            <AlertRow label="Codex · API credit" sub="$ remaining" pct={20} tone="var(--ink-3)"/>
            <div style={{height:1,background:'var(--line-2)',margin:'0 16px'}}/>
            <AlertRow label="Daily spend cap" sub="of $25.00" pct={85} on tone="var(--r-med)"/>
          </div>

          <div className="cc-sec">edit threshold<span className="rule"/></div>
          <div className="cc-card" style={{padding:'14px 15px'}}>
            <div style={{display:'flex',alignItems:'center',justifyContent:'space-between',marginBottom:10}}>
              <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink-2)'}}>Claude weekly</span>
              <span style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--r-med)'}}>80%</span>
            </div>
            {/* slider track in the brand spectrum */}
            <div style={{position:'relative',height:6,borderRadius:3,background:'var(--surface-2)',overflow:'hidden'}}>
              <div style={{position:'absolute',inset:0,width:'80%',background:'linear-gradient(90deg,#4f63c9,#c2622c)'}}/>
            </div>
            <div style={{position:'relative',marginTop:-3}}><span style={{position:'absolute',left:'calc(80% - 8px)',width:16,height:16,borderRadius:'50%',background:'#fff',border:'2px solid var(--r-med)'}}/></div>
          </div>
          <NoteCard icon={RX.alert} tone="warn">Critical-quota alerts break through quiet hours — running out mid-task always wakes you.</NoteCard>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}}><Ic d={ICON.check} s={16}/>Save alerts</button>
      </div>
    </div>
  );
}

/* ---------- T1 · Auto-failover across accounts ---------- */
function FailoverScreen(){
  return (
    <div className="cc">
      <SubNav title="auto-failover" right={<span className="cc-toggle on"><span className="knob"/></span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>When the active account rate-limits, the bridge routes the next call to the following account automatically — no dropped run.</p>

          <div className="cc-sec">failover order · anthropic<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 0'}}>
            {[['1','me@personal.dev','Max · 41% left','active','var(--r-med)'],['2','team@acme.io','Pro · 88% left','standby','var(--r-low)'],['3','overflow@acme.io','Pro · 96% left','standby','var(--r-low)']].map(([n,email,quota,state,c],i)=>(
              <div key={i} className="cc-row" style={{cursor:'pointer'}}>
                <span style={{width:22,height:22,borderRadius:2,border:'1px solid var(--line-strong)',display:'flex',alignItems:'center',justifyContent:'center',fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)',flex:'none'}}>{n}</span>
                <div className="grow" style={{minWidth:0}}>
                  <div style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)'}}>{email}</div>
                  <div className="s" style={{marginTop:2}}>{quota}</div>
                </div>
                {state==='active'
                  ? <span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--brand)',border:'1px solid var(--brand)',borderRadius:2,padding:'2px 7px'}}>active</span>
                  : <span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-3)',border:'1px solid var(--line)',borderRadius:2,padding:'2px 7px'}}>standby</span>}
              </div>
            ))}
          </div>
          <p className="cc-note" style={{margin:'8px 4px 0'}}>Drag to reorder · failover walks the list top-down.</p>

          <div className="cc-sec">recent failovers<span className="rule"/></div>
          <div className="cc-card" style={{padding:'2px 0'}}>
            {[['2:11 PM','me@personal → team@acme','5h limit hit'],['Jun 11','team@acme → overflow','weekly cap']].map(([t,move,why],i)=>(
              <div key={i} style={{display:'flex',alignItems:'flex-start',gap:11,padding:'11px 14px',position:'relative'}}>
                {i>0 && <span style={{position:'absolute',top:0,left:14,right:0,height:1,background:'var(--line-2)'}}/>}
                <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)',width:48,flex:'none',paddingTop:1}}>{t}</span>
                <div style={{flex:1,minWidth:0}}>
                  <div style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink)'}}><Ic d={RX.swap} s={12}/> {move}</div>
                  <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginTop:3}}>reason: {why}</div>
                </div>
              </div>
            ))}
          </div>
          <NoteCard icon={ICON.shield} tone="ok">Failover stays within vendors you've authorized. It never crosses to a paid tier without your standing approval.</NoteCard>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ============================================================
   TIER 2 · TWO-WAY CONTROL (beyond v1)
   ============================================================ */

/* ---------- T2 · Nudge a running agent ---------- */
function NudgeScreen(){
  const out=[
    ['$ refactor the session store','c'],
    ['Editing SessionViewModel.swift…','o'],
    ['Extracting BlockRenderer protocol','o'],
    ['› you: also keep the old API as a shim','n'],
    ['Acknowledged — adding a deprecation shim','w'],
  ];
  return (
    <div className="cc">
      <SubNav title="nudge" right={<span className="cc-sd"><span className="d working"/>working</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div className="cc-card" style={{padding:'12px 14px',display:'flex',alignItems:'center',gap:10}}>
            <PixelAvatar seed="claudelancer" size={34} color={VENDOR.claude.c}/>
            <div className="grow" style={{minWidth:0}}><div style={{fontFamily:'var(--mono)',fontSize:13.5,color:'var(--ink)'}}>Claude Code · lancer</div><div className="s">Dev VPS · mid-run</div></div>
            <span style={{marginLeft:'auto'}}><SoonChip/></span>
          </div>

          <div className="cc-sec">live output<span className="n">· tail</span><span className="rule"/></div>
          <div className="cc-cmd" style={{display:'block',padding:0}}>
            <div className="body" style={{whiteSpace:'pre-wrap',padding:'11px 13px',fontSize:11.5,lineHeight:1.75}}>
              {out.map(([t,k],i)=>(
                <div key={i} style={{color:k==='c'?'var(--ink)':k==='n'?'var(--brand)':k==='w'?'var(--r-med)':'var(--ink-3)'}}>{t}{k==='w'&&<span className="cursor" style={{height:'.8em'}}/>}</div>
              ))}
            </div>
          </div>
          <NoteCard icon={RX.nudge}>A nudge is injected at the agent's next safe checkpoint — it steers the run without stopping it. The agent acknowledges in the transcript.</NoteCard>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <div style={{display:'flex',alignItems:'center',background:'var(--bg-2)',border:'1px solid var(--line)',borderRadius:'var(--r-md)',height:46,padding:'0 13px',gap:9,marginBottom:10}}>
          <span style={{fontFamily:'var(--mono)',color:'var(--brand)',fontSize:14}}>›</span>
          <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink-4)',flex:1}}>add a one-line instruction…</span>
        </div>
        <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}}><Ic d={RX.nudge} s={16}/>Send nudge</button>
      </div>
    </div>
  );
}

/* ---------- T2 · Switch model / account mid-run ---------- */
function SwitchRunScreen(){
  const [acct,setAcct]=React.useState('team');
  return (
    <div className="cc">
      <SubNav title="switch · mid-run" right={<SoonChip/>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Repoint a working run to another model or account — the bridge swaps on the next call, the run continues.</p>

          <div className="cc-sec">model<span className="rule"/></div>
          <div className="cc-seg"><button>sonnet-4.6</button><button className="on">opus-4.6</button><button>local</button></div>

          <div className="cc-sec">account<span className="rule"/></div>
          <div className="cc-card">
            {[['personal','me@personal.dev','Max · 41% left',false],['team','team@acme.io','Pro · 88% left',true]].map(([id,email,quota],i)=>(
              <div key={i} className="cc-row" onClick={()=>setAcct(id)}>
                <PixelAvatar seed={'claude'+email} size={30} color={VENDOR.claude.c}/>
                <div className="grow" style={{minWidth:0}}><div className="t" style={{fontSize:14}}>{email}</div><div className="s">{quota}</div></div>
                <span style={{width:20,height:20,borderRadius:'50%',border:'2px solid '+(acct===id?'var(--brand)':'var(--ink-4)'),display:'flex',alignItems:'center',justifyContent:'center',flex:'none'}}>{acct===id&&<span style={{width:9,height:9,borderRadius:'50%',background:'var(--brand)'}}/>}</span>
              </div>
            ))}
          </div>
          <NoteCard icon={RX.swap}>Switching to <b style={{color:'var(--ink)'}}>opus-4.6</b> raises cost ≈ 5× — the run's budget cap still applies and pauses it if exceeded.</NoteCard>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <div className="cc-btnrow">
          <button className="cc-btn cc-btn--quiet" style={{flex:1}}><Ic d={ICON.x} s={14}/>Cancel</button>
          <button className="cc-btn cc-btn--primary" style={{flex:1.4}}><Ic d={RX.swap} s={15}/>Switch &amp; resume</button>
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   TIER 3 · PROACTIVE AWARENESS
   ============================================================ */

/* ---------- T3 · Host observability ---------- */
function Gauge({ label, val, pct, tone }){
  return <div style={{padding:'12px 0'}}>
    <div style={{display:'flex',alignItems:'baseline',justifyContent:'space-between',marginBottom:7}}>
      <span style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)'}}>{label}</span>
      <span style={{fontFamily:'var(--mono)',fontSize:12,color:tone}}>{val}</span>
    </div>
    <div style={{display:'flex',height:6,borderRadius:3,overflow:'hidden',background:'var(--surface-2)'}}>
      <div style={{width:pct+'%',background:tone}}/>
    </div>
  </div>;
}
function ObservabilityScreen(){
  return (
    <div className="cc">
      <SubNav title="host · dev-vps" right={<span className="cc-sd"><span className="d done"/>healthy</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>The bridge already lives on your machine — so it can watch it. Resource pushes land only when something needs you.</p>
          <div className="cc-sec">resources<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 15px 8px'}}>
            <Gauge label="CPU · 8 cores" val="34%" pct={34} tone="#4f63c9"/>
            <Gauge label="Memory · 32 GB" val="21.4 GB" pct={67} tone="#c2622c"/>
            <Gauge label="Disk · /  · 512 GB" val="88% — low" pct={88} tone="var(--r-high)"/>
          </div>

          <div className="cc-sec">long-running<span className="rule"/></div>
          <div className="cc-card" style={{padding:'2px 0'}}>
            {[['lancer · swift build','running 18m','var(--brand)'],['nightly-suite','running 2h 14m','var(--r-med)']].map(([name,dur,c],i)=>(
              <div key={i} className="cc-row" style={{cursor:'pointer'}}>
                <span style={{width:8,height:8,borderRadius:'50%',background:c,flex:'none'}}/>
                <div className="grow"><div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{name}</div></div>
                <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>{dur}</span>
              </div>
            ))}
          </div>
          <NoteCard icon={RX.cpu} tone="warn">Disk on / crossed 85%. Tap to see the largest paths, or let the agent clean build artifacts under policy.</NoteCard>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- T3 · Git / PR events ---------- */
function GitEventsScreen(){
  const EV=[
    {act:'push',label:'pushed feat/block-renderer',sub:'4 commits · dev-vps',c:'var(--brand)',t:'2m'},
    {act:'pr',label:'opened PR #218',sub:'block terminal · live agents',c:'var(--r-low)',t:'5m'},
    {act:'ci',label:'CI green on #218',sub:'42 tests · 3m12s',c:'var(--r-low)',t:'1m'},
    {act:'ci',label:'CI failed on #215',sub:'SessionViewModelTests',c:'var(--r-crit)',t:'12m'},
    {act:'branch',label:'branch fix/tofu-prompt',sub:'created from master',c:'var(--ink-3)',t:'1h'},
  ];
  return (
    <div className="cc-scroll">
      <StatusHeader state="ok" label="bridge connected" detail="watching 2 repos"/>
      <PromptHeader title="git" crumb={<b>branch &amp; PR events</b>} right="5 today"/>
      <div className="cc-pad">
        <div className="cc-sec">today<span className="rule"/></div>
        <div className="cc-card" style={{padding:'2px 0'}}>
          {EV.map((e,i)=>(
            <div key={i} style={{display:'flex',alignItems:'flex-start',gap:11,padding:'12px 14px',position:'relative',cursor:'pointer'}}>
              {i>0 && <span style={{position:'absolute',top:0,left:14,right:0,height:1,background:'var(--line-2)'}}/>}
              <span style={{flex:'none',marginTop:1,color:e.c}}><Ic d={e.act==='pr'?RX.plug:e.act==='ci'?(e.c==='var(--r-crit)'?ICON.x:ICON.check):RX.branch} s={15}/></span>
              <div style={{flex:1,minWidth:0}}>
                <div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{e.label}</div>
                <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginTop:3}}>{e.sub}</div>
              </div>
              <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',flex:'none',paddingTop:1}}>{e.t}</span>
            </div>
          ))}
        </div>
        <NoteCard icon={RX.branch}>Events stream from the host's git + CI hooks. Tap a failing check to open the run that broke it, or dispatch a fix.</NoteCard>
      </div>
      <div className="cc-bottompad"/>
    </div>
  );
}

/* ---------- T3 · Digests ---------- */
function DigestScreen(){
  return (
    <div className="cc">
      <SubNav title="digest" right={<span className="cc-chip"><Ic d={RX.digest} s={12}/>overnight</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 14px'}}>A quiet summary of what happened while you were away — so you don't scroll the audit log.</p>

          <div className="cc-card" style={{padding:'16px 16px 14px'}}>
            <div style={{fontFamily:'var(--mono)',fontSize:11,letterSpacing:'.18em',color:'var(--ink-3)',marginBottom:12}}>WHILE YOU WERE AWAY · 11PM–8AM</div>
            <div style={{display:'flex',gap:18}}>
              <div><div style={{fontFamily:'var(--mono)',fontSize:24,fontWeight:700,color:'var(--ink)'}}>34</div><div className="cc-note" style={{marginTop:2}}>auto-decided</div></div>
              <div><div style={{fontFamily:'var(--mono)',fontSize:24,fontWeight:700,color:'var(--r-med)'}}>2</div><div className="cc-note" style={{marginTop:2}}>waiting</div></div>
              <div><div style={{fontFamily:'var(--mono)',fontSize:24,fontWeight:700,color:'var(--ink)'}}>$1.28</div><div className="cc-note" style={{marginTop:2}}>spent</div></div>
            </div>
          </div>

          <div className="cc-sec">highlights<span className="rule"/></div>
          <div className="cc-card" style={{padding:'2px 0'}}>
            {[['✓','nightly test suite passed · 42 tests','var(--r-low)'],['→','2 patches auto-allowed under policy','var(--ink-2)'],['!','auth-svc waiting on a network call','var(--r-med)']].map(([g,txt,c],i)=>(
              <div key={i} style={{display:'flex',alignItems:'flex-start',gap:11,padding:'11px 14px',position:'relative'}}>
                {i>0 && <span style={{position:'absolute',top:0,left:14,right:0,height:1,background:'var(--line-2)'}}/>}
                <span style={{fontFamily:'var(--mono)',fontSize:13,color:c,width:14,flex:'none'}}>{g}</span>
                <span style={{fontSize:13,color:'var(--ink-2)',lineHeight:1.45}}>{txt}</span>
              </div>
            ))}
          </div>

          <div className="cc-sec">weekly cost digest<span className="rule"/></div>
          <div className="cc-card" style={{padding:'14px 15px'}}>
            <div style={{display:'flex',alignItems:'flex-end',justifyContent:'space-between',marginBottom:10}}>
              <span style={{fontFamily:'var(--mono)',fontSize:20,fontWeight:700,color:'var(--ink)'}}>$48.10</span>
              <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>this week · ↓ 12%</span>
            </div>
            <SpectrumBar segments={[{pct:64,color:'#b5352a'},{pct:22,color:'#8a5fbf'},{pct:14,color:'#4f63c9'}]}/>
            <div style={{display:'flex',gap:14,marginTop:9}}>
              <span className="cc-chip" style={{border:'none',background:'none',padding:0,color:'var(--ink-3)'}}><span style={{width:8,height:8,borderRadius:2,background:'#b5352a'}}/>Claude</span>
              <span className="cc-chip" style={{border:'none',background:'none',padding:0,color:'var(--ink-3)'}}><span style={{width:8,height:8,borderRadius:2,background:'#8a5fbf'}}/>Codex</span>
              <span className="cc-chip" style={{border:'none',background:'none',padding:0,color:'var(--ink-3)'}}><span style={{width:8,height:8,borderRadius:2,background:'#4f63c9'}}/>OpenRouter</span>
            </div>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ============================================================
   TIER 4 · TRUST & SCALE
   ============================================================ */

/* ---------- T4 · Secrets brokering (authorize a secret use) ---------- */
function SecretsBrokerScreen(){
  return (
    <div className="cc cc-frame-inner">
      <SubNav title="secrets" right={<span className="cc-chip"><Ic d={RX.vault} s={12}/>vault</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>The daemon holds your keys. Agents request a secret by name — they never see the raw value, and every use needs your nod.</p>
          <div className="cc-sec">brokered secrets<span className="rule"/></div>
          <div className="cc-card" style={{padding:'2px 0'}}>
            {[['STRIPE_SECRET_KEY','used 4× today','var(--r-crit)'],['GITHUB_TOKEN','used 12× today','var(--r-high)'],['DATABASE_URL','unused this week','var(--ink-3)']].map(([name,used,c],i)=>(
              <div key={i} className="cc-row" style={{cursor:'pointer'}}>
                <span style={{flex:'none',color:c}}><Ic d={ICON.lock} s={15}/></span>
                <div className="grow" style={{minWidth:0}}><div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{name}</div><div className="s" style={{marginTop:2}}>{used}</div></div>
                <span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-3)'}}>••••••</span>
              </div>
            ))}
          </div>
          <NoteCard icon={RX.vault} tone="ok">Values stay in the host Keychain — they are injected at call time and redacted from output. The phone authorizes; it never receives the secret.</NoteCard>
        </div>
        <div className="cc-bottompad"/>
      </div>
      {/* authorize sheet over the screen */}
      <div className="cc-sheetwrap">
        <div className="cc-scrim"/>
        <div className="cc-sheet">
          <div className="grip"/>
          <div className="sheetscroll">
            <div style={{display:'flex',alignItems:'center',gap:10,margin:'4px 0 14px'}}>
              <span style={{color:'var(--r-crit)'}}><Ic d={ICON.lock} s={20}/></span>
              <h2 className="cc-h2" style={{margin:0}}>Authorize a secret</h2>
            </div>
            <p style={{fontSize:13.5,color:'var(--ink-2)',lineHeight:1.55,margin:'0 0 14px'}}><b style={{color:'var(--ink)',fontFamily:'var(--mono)'}}>Codex</b> wants <b style={{color:'var(--ink)',fontFamily:'var(--mono)'}}>STRIPE_SECRET_KEY</b> to run a payment test on <b style={{color:'var(--ink)'}}>~/work/auth</b>.</p>
            <div className="cc-chiprow"><BlastChips creds net/></div>
            <NoteCard icon={ICON.shield}>Grant once, or for this run only. The agent receives a handle, not the key.</NoteCard>
          </div>
          <div className="sheetfoot">
            <div className="cc-btnrow">
              <button className="cc-btn cc-btn--danger" style={{flex:1}}><Ic d={ICON.x} s={15}/>Deny</button>
              <button className="cc-btn cc-btn--primary" style={{flex:1.4}}><Ic d={ICON.lock} s={15}/>Authorize</button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ---------- T4 · Multi-host fleet routing ---------- */
function HostRouteScreen(){
  const [host,setHost]=React.useState('ws');
  const HOSTS=[
    {id:'ws',name:'Workstation',load:'12% load · idle',cost:'local · $0',c:'var(--r-low)',best:true},
    {id:'vps',name:'Dev VPS',load:'64% load',cost:'$0.02 / min',c:'var(--r-med)'},
    {id:'pi',name:'Raspberry Pi',load:'offline',cost:'—',c:'var(--ink-4)',off:true},
  ];
  return (
    <div className="cc">
      <SubNav title="route run" right={<SoonChip/>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Send a run to the cheapest, least-loaded host. The bridge picks a default; you can override.</p>
          <div className="cc-sec">choose a host<span className="rule"/></div>
          <div className="cc-card">
            {HOSTS.map(h=>(
              <div key={h.id} className="cc-row" onClick={()=>!h.off&&setHost(h.id)} style={{opacity:h.off?.5:1,cursor:h.off?'default':'pointer'}}>
                <span style={{width:8,height:8,borderRadius:'50%',background:h.c,flex:'none'}}/>
                <div className="grow" style={{minWidth:0}}>
                  <div style={{display:'flex',alignItems:'center',gap:7}}>
                    <span style={{fontFamily:'var(--mono)',fontSize:13.5,color:'var(--ink)'}}>{h.name}</span>
                    {h.best && <span style={{fontFamily:'var(--mono)',fontSize:9.5,color:'var(--r-low)',border:'1px solid var(--r-low-bd)',background:'var(--r-low-bg)',borderRadius:2,padding:'1px 6px'}}>cheapest</span>}
                  </div>
                  <div className="s" style={{marginTop:3}}>{h.load} · {h.cost}</div>
                </div>
                {!h.off && <span style={{width:20,height:20,borderRadius:'50%',border:'2px solid '+(host===h.id?'var(--brand)':'var(--ink-4)'),display:'flex',alignItems:'center',justifyContent:'center',flex:'none'}}>{host===h.id&&<span style={{width:9,height:9,borderRadius:'50%',background:'var(--brand)'}}/>}</span>}
              </div>
            ))}
          </div>
          <NoteCard icon={RX.route} tone="ok">Workstation runs a local model — picking it keeps this run's code and prompts entirely on your machine at $0.</NoteCard>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}}><Ic d={RX.route} s={16}/>Route to Workstation</button>
      </div>
    </div>
  );
}

/* ---------- T4 · Scheduling UI ---------- */
function ScheduleScreen(){
  const [cad,setCad]=React.useState('daily');
  return (
    <div className="cc">
      <SubNav title="schedule a run" right={<SoonChip/>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Compose a run and a cadence. The bridge fires it under your policy and budget — results land in Activity.</p>
          <div className="cc-sec">task<span className="rule"/></div>
          <CCInput value="run the nightly test suite and open a PR if green" onChange={()=>{}} multiline/>
          <div className="cc-sec">agent<span className="rule"/></div>
          <div className="cc-card" style={{padding:'12px 14px',display:'flex',alignItems:'center',gap:10}}>
            <VendorMark vendor="claude"/>
            <span style={{marginLeft:'auto',fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink-3)'}}>~/repos/lancer</span>
          </div>
          <div className="cc-sec">cadence<span className="rule"/></div>
          <div className="cc-seg">
            {['hourly','daily','weekly','cron'].map(c=>(<button key={c} className={cad===c?'on':''} onClick={()=>setCad(c)}>{c}</button>))}
          </div>
          <CCInput value="0 2 * * *  ·  02:00 every day" onChange={()=>{}} mono prefix="⏱"/>
          <div className="cc-sec">upcoming<span className="rule"/></div>
          <div className="cc-card" style={{padding:'2px 0'}}>
            {[['nightly-suite','daily 2:00 AM','tonight'],['weekly-deps','Mon 9:00 AM','in 3d']].map(([n,when,next],i)=>(
              <div key={i} className="cc-row" style={{cursor:'pointer'}}>
                <span style={{flex:'none',color:'var(--ink-3)'}}><Ic d={RX.calendar} s={15}/></span>
                <div className="grow"><div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{n}</div><div className="s" style={{marginTop:2}}>{when}</div></div>
                <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>{next}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}}><Ic d={RX.calendar} s={16}/>Schedule run</button>
      </div>
    </div>
  );
}

/* ---------- T4 · Local guardrails (blocked-event card) ---------- */
function GuardrailsScreen(){
  return (
    <div className="cc">
      <SubNav title="guardrails" right={<SoonChip/>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Scan agent output on the host before anything leaves it. Secret-scan and egress-monitor run locally — no output crosses the wire to be checked.</p>

          <div className="cc-sec">active monitors<span className="rule"/></div>
          <div className="cc-card">
            <div className="cc-row" style={{cursor:'pointer'}}>
              <span style={{width:30,height:30,borderRadius:2,background:'var(--surface-2)',border:'1px solid var(--line)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--ink-2)',flex:'none'}}><Ic d={RX.scan} s={16}/></span>
              <div className="grow"><div className="t" style={{fontSize:14}}>Secret-scan</div><div className="s">block keys, tokens &amp; .env values in output</div></div>
              <span className="cc-toggle on"><span className="knob"/></span>
            </div>
            <div className="cc-row" style={{cursor:'pointer'}}>
              <span style={{width:30,height:30,borderRadius:2,background:'var(--surface-2)',border:'1px solid var(--line)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--ink-2)',flex:'none'}}><Ic d={ICON.net} s={16}/></span>
              <div className="grow"><div className="t" style={{fontSize:14}}>Egress-monitor</div><div className="s">flag unexpected outbound hosts</div></div>
              <span className="cc-toggle on"><span className="knob"/></span>
            </div>
          </div>

          <div className="cc-sec">blocked · today<span className="rule"/></div>
          <div className="cc-card" style={{padding:16,borderColor:'var(--r-crit-bd)'}}>
            <div style={{display:'flex',alignItems:'center',gap:8,marginBottom:10}}>
              <span style={{fontFamily:'var(--mono)',fontSize:10,fontWeight:700,letterSpacing:'.08em',color:'var(--r-crit)',background:'var(--r-crit-bg)',border:'1px solid var(--r-crit-bd)',borderRadius:2,padding:'3px 8px'}}>BLOCKED</span>
              <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>secret-scan · 1:12 PM</span>
              <span style={{marginLeft:'auto'}}><RiskChip level="critical"/></span>
            </div>
            <div style={{fontSize:14,color:'var(--ink)',lineHeight:1.4,marginBottom:9}}>Output contained a <b>live Stripe key</b> — redacted before it left the host.</div>
            <div className="cc-cmd" data-r="critical"><div className="gut"/><div className="body" style={{fontSize:11.5}}>echo $STRIPE_SECRET_KEY ▓▓ redacted</div></div>
            <div className="cc-btnrow" style={{marginTop:14}}>
              <button className="cc-btn cc-btn--quiet" style={{flex:1}}>Dismiss</button>
              <button className="cc-btn cc-btn--danger" style={{flex:1}}><Ic d={ICON.shield} s={14}/>Review rule</button>
            </div>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- T4 · Self-hosted relay (enterprise config) ---------- */
function SelfHostRelayScreen(){
  return (
    <div className="cc">
      <SubNav title="self-hosted relay" right={<span className="cc-chip"><Ic d={ICON.shield} s={12}/>enterprise</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Run the relay container in your own infra. Nothing — not even ciphertext — touches Lancer servers. The OSS-trust connectivity tier.</p>
          <CommandBlock cmd="docker run -p 8443:8443 lancer/relay:1.0" level="low"/>
          <button className="cc-btn cc-btn--quiet cc-btn--block" style={{marginTop:10}}><Ic d={ICON.copy} s={14}/>Copy command</button>

          <div className="cc-sec">endpoint<span className="rule"/></div>
          <CCInput value="relay.acme.internal:8443" onChange={()=>{}} mono prefix="wss://"/>
          <div className="cc-chiprow" style={{marginTop:10}}>
            <span className="cc-chip" style={{color:'var(--r-low)',borderColor:'var(--r-low-bd)'}}><span style={{width:7,height:7,borderRadius:'50%',background:'var(--r-low)'}}/>reachable</span>
            <span className="cc-chip">TLS valid</span>
            <span className="cc-chip">v1.0</span>
          </div>

          <div className="cc-sec">health<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 0'}}>
            {[['paired bridges','3'],['active channels','2'],['relay reads payload','never · blind pipe']].map(([k,v],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <div className="grow"><span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink-2)'}}>{k}</span></div>
                <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:i===2?'var(--r-low)':'var(--ink)'}}>{v}</span>
              </div>
            ))}
          </div>
          <NoteCard icon={ICON.shield} tone="ok">Keys derive bridge↔phone at pairing — your relay forwards ciphertext it can't decrypt, exactly like the hosted one.</NoteCard>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}}><Ic d={ICON.check} s={16}/>Use this relay</button>
      </div>
    </div>
  );
}

/* ---------- T4 · Hosted Cloud agents (gated Pro) ---------- */
function CloudAgentsScreen(){
  return (
    <div className="cc">
      <SubNav title="cloud agents" right={<span className="cc-chip" style={{color:'var(--brand)',borderColor:'var(--brand)'}}><Ic d={ICON.bolt} s={12}/>Pro</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Run a task when your own machine is off — on Lancer-managed compute. Secondary to the private bridge; gated behind Pro.</p>
          <div className="cc-sec">running · cloud<span className="rule"/></div>
          <div className="cc-card" style={{padding:'2px 0'}}>
            {[['cloud-1','claude-sonnet-4.6','working · 6m','var(--brand)','$0.42'],['cloud-2','gpt-5.1-codex','queued','var(--r-med)','—']].map(([name,model,state,c,spend],i)=>(
              <div key={i} className="cc-row" style={{cursor:'pointer'}}>
                <span style={{width:30,height:30,borderRadius:2,background:'var(--surface-2)',border:'1px solid var(--line)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--ink-2)',flex:'none'}}><Ic d={RX.cloud} s={16}/></span>
                <div className="grow" style={{minWidth:0}}><div style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)'}}>{name}</div><div className="s">{model}</div></div>
                <div style={{textAlign:'right',flex:'none'}}>
                  <span className="cc-sd"><span className="d" style={{background:c}}/>{state.split(' ')[0]}</span>
                  <div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)',marginTop:3}}>{spend}</div>
                </div>
              </div>
            ))}
          </div>

          <div className="cc-sec">credits<span className="rule"/></div>
          <div className="cc-card" style={{padding:'14px 15px'}}>
            <div style={{display:'flex',alignItems:'flex-end',justifyContent:'space-between',marginBottom:9}}>
              <span style={{fontFamily:'var(--mono)',fontSize:20,fontWeight:700,color:'var(--ink)'}}>$18.40</span>
              <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>cloud credit left</span>
            </div>
            <SpectrumBar segments={[{pct:62,color:'#4f63c9'}]}/>
          </div>
          <NoteCard icon={RX.cloud}>Cloud runs are opt-in per task — your code is uploaded only for that run. The default stays your own host.</NoteCard>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}}><Ic d={ICON.bolt} s={16}/>New cloud agent</button>
      </div>
    </div>
  );
}

/* ---------- T4 · Run-artifact browser ---------- */
function ArtifactsScreen(){
  const FILES=[
    ['build/Lancer.ipa','app bundle','18.4 MB',ICON.folder],
    ['coverage.html','test coverage','412 KB',ICON.file],
    ['test-results.xml','junit report','88 KB',ICON.file],
    ['screenshots/','12 PNGs','6.1 MB',ICON.folder],
    ['build.log','full transcript','240 KB',ICON.term],
  ];
  return (
    <div className="cc">
      <SubNav title="artifacts" right={<span className="cc-chip"><Ic d={RX.archive} s={12}/>run #218</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Files a run produced — preview or download over the same encrypted channel. Nothing is stored off-host without your tap.</p>
          <div className="cc-card" style={{padding:'2px 0'}}>
            {FILES.map(([name,kind,size,ic],i)=>(
              <div key={i} className="cc-row" style={{cursor:'pointer'}}>
                <span style={{flex:'none',color:'var(--ink-3)'}}><Ic d={ic} s={16}/></span>
                <div className="grow" style={{minWidth:0}}><div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{name}</div><div className="s" style={{marginTop:2}}>{kind}</div></div>
                <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)',flex:'none',marginRight:10}}>{size}</span>
                <Ic d={ICON.chev} s={15}/>
              </div>
            ))}
          </div>
          <NoteCard icon={RX.archive}>Tap a file to preview in the bottom drawer; tap download to pull it to this phone. Artifacts expire with the run unless you pin them.</NoteCard>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <div className="cc-btnrow">
          <button className="cc-btn cc-btn--quiet" style={{flex:1}}><Ic d={ICON.copy} s={14}/>Copy path</button>
          <button className="cc-btn cc-btn--primary" style={{flex:1.3}}><Ic d={ICON.file} s={15}/>Download all</button>
        </div>
      </div>
    </div>
  );
}

/* ---------- T4 · Team org + member invite ---------- */
function TeamOrgScreen(){
  const ROLE={admin:{c:'var(--brand)'},member:{c:'var(--ink-2)'},viewer:{c:'var(--ink-3)'}};
  const MEMBERS=[
    ['you@acme.io','admin','active'],
    ['dev@acme.io','member','active'],
    ['ops@acme.io','member','active'],
    ['intern@acme.io','viewer','invited'],
  ];
  return (
    <div className="cc">
      <SubNav title="team · acme" right={<span className="cc-chip" style={{color:'var(--brand)',borderColor:'var(--brand)'}}><Ic d={ICON.bolt} s={12}/>Pro</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Share one policy and a team approval inbox. Invite by email; assign a role.</p>
          <div className="cc-sec">members <span className="n">· {MEMBERS.length}</span><span className="rule"/></div>
          <div className="cc-card">
            {MEMBERS.map(([email,role,state],i)=>(
              <div key={i} className="cc-row" style={{cursor:'pointer'}}>
                <PixelAvatar seed={email} size={30}/>
                <div className="grow" style={{minWidth:0}}><div className="t" style={{fontSize:14}}>{email}</div><div className="s">{role}</div></div>
                {state==='invited'
                  ? <span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--r-med)',border:'1px solid var(--r-med-bd)',background:'var(--r-med-bg)',borderRadius:2,padding:'2px 7px'}}>invited</span>
                  : <span style={{fontFamily:'var(--mono)',fontSize:10,color:ROLE[role].c,border:'1px solid var(--line)',borderRadius:2,padding:'2px 7px',textTransform:'uppercase',letterSpacing:'.06em'}}>{role}</span>}
              </div>
            ))}
          </div>

          <div className="cc-sec">invite a member<span className="rule"/></div>
          <CCInput value="" onChange={()=>{}} placeholder="name@company.com" mono prefix="@"/>
          <div className="cc-seg" style={{marginTop:10}}><button>viewer</button><button className="on">member</button><button>admin</button></div>
          <NoteCard icon={RX.users}>The team shares one policy.yaml and a shared inbox. Admins edit rules; members approve; viewers watch the audit log.</NoteCard>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}}><Ic d={RX.users} s={16}/>Send invite</button>
      </div>
    </div>
  );
}

/* ============================================================
   BOARD COMPOSITION
   ============================================================ */
function RoadmapBoard(){
  return (
    <DesignCanvas>
      <DCSection id="t0" title="Tier 0 · Foundations"
        subtitle="The live duplex relay, the adapter SPI, account registry, the lancer CLI and the support matrix — the pieces that unlock everything above.">
        <DCArtboard id="relay" label="E2E relay · setup &amp; status" width={320} height={660}>
          <RFrame t="T0"><RelayStatusScreen/></RFrame>
        </DCArtboard>
        <DCArtboard id="addagent" label="Adapter SPI · add an agent (A vs B)" width={320} height={660}>
          <RFrame t="T0"><AddAgentScreen/></RFrame>
        </DCArtboard>
        <DCArtboard id="accounts" label="Account registry · multi-account" width={320} height={660}>
          <RFrame t="T0"><AccountRegistryScreen/></RFrame>
        </DCArtboard>
        <DCArtboard id="cli" label="lancer CLI · from your terminal" width={320} height={660}>
          <RFrame t="T0"><CliScreen/></RFrame>
        </DCArtboard>
        <DCArtboard id="matrix" label="Vendor / model support matrix" width={320} height={660}>
          <RFrame t="T0"><MatrixScreen/></RFrame>
        </DCArtboard>
      </DCSection>

      <DCSection id="t1" title="Tier 1 · Usage intelligence"
        subtitle="The flagship post-v1 surface — burn-rate projection, configurable limit alerts and auto-failover across accounts.">
        <DCArtboard id="burn" label="Burn-rate projection" width={320} height={660}>
          <RFrame t="T1"><BurnRateScreen/></RFrame>
        </DCArtboard>
        <DCArtboard id="alerts" label="Limit alerts · configure thresholds" width={320} height={660}>
          <RFrame t="T1"><LimitAlertsScreen/></RFrame>
        </DCArtboard>
        <DCArtboard id="failover" label="Auto-failover across accounts" width={320} height={660}>
          <RFrame t="T1"><FailoverScreen/></RFrame>
        </DCArtboard>
      </DCSection>

      <DCSection id="t2" title="Tier 2 · Two-way control (beyond v1)"
        subtitle="The phone→agent direction past the v1 run-control slice: nudge a working run, switch model or account mid-run.">
        <DCArtboard id="nudge" label="Nudge a running agent" width={320} height={660}>
          <RFrame t="T2"><NudgeScreen/></RFrame>
        </DCArtboard>
        <DCArtboard id="switch" label="Switch model / account mid-run" width={320} height={660}>
          <RFrame t="T2"><SwitchRunScreen/></RFrame>
        </DCArtboard>
      </DCSection>

      <DCSection id="t3" title="Tier 3 · Proactive awareness"
        subtitle="Incremental daemon→phone pushes — host observability, git/PR/CI events, and while-you-were-away + weekly digests.">
        <DCArtboard id="observe" label="Host observability" width={320} height={660}>
          <RFrame t="T3"><ObservabilityScreen/></RFrame>
        </DCArtboard>
        <DCArtboard id="git" label="Git / PR / CI events" width={320} height={660}>
          <RTabFrame t="T3" tab="activity"><GitEventsScreen/></RTabFrame>
        </DCArtboard>
        <DCArtboard id="digest" label="Digests · away + weekly cost" width={320} height={660}>
          <RFrame t="T3"><DigestScreen/></RFrame>
        </DCArtboard>
      </DCSection>

      <DCSection id="t4" title="Tier 4 · Trust &amp; scale"
        subtitle="The deeper moat / enterprise tier — secrets brokering, multi-host routing, scheduling, local guardrails, self-hosted relay, hosted cloud, artifacts and team org.">
        <DCArtboard id="secrets" label="Secrets brokering · authorize a use" width={320} height={660}>
          <RFrame t="T4"><SecretsBrokerScreen/></RFrame>
        </DCArtboard>
        <DCArtboard id="route" label="Multi-host fleet routing" width={320} height={660}>
          <RFrame t="T4"><HostRouteScreen/></RFrame>
        </DCArtboard>
        <DCArtboard id="schedule" label="Scheduling · composer + cadence" width={320} height={660}>
          <RFrame t="T4"><ScheduleScreen/></RFrame>
        </DCArtboard>
        <DCArtboard id="guardrails" label="Local guardrails · blocked event" width={320} height={660}>
          <RFrame t="T4"><GuardrailsScreen/></RFrame>
        </DCArtboard>
        <DCArtboard id="selfrelay" label="Self-hosted relay · enterprise" width={320} height={660}>
          <RFrame t="T4"><SelfHostRelayScreen/></RFrame>
        </DCArtboard>
        <DCArtboard id="cloud" label="Hosted Cloud agents · gated Pro" width={320} height={660}>
          <RFrame t="T4"><CloudAgentsScreen/></RFrame>
        </DCArtboard>
        <DCArtboard id="artifacts" label="Run-artifact browser" width={320} height={660}>
          <RFrame t="T4"><ArtifactsScreen/></RFrame>
        </DCArtboard>
        <DCArtboard id="team" label="Team org + member invite" width={320} height={660}>
          <RFrame t="T4"><TeamOrgScreen/></RFrame>
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<RoadmapBoard/>);
