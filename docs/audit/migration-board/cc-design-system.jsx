/* ============================================================
   LANCER — design system component gallery (all components)
   Each artboard shows ONE design system component category.
   ============================================================ */

/* ---------- 1 · BUTTONS ---------- */
function DSButtonGallery(){
  const variants=[
    {kind:'primary',cls:'cc-btn--primary',desc:'Brand #2f43ff bg'},
    {kind:'ghost',cls:'cc-btn--ghost',desc:'Transparent + border'},
    {kind:'danger',cls:'cc-btn--danger',desc:'Red border'},
    {kind:'quiet',cls:'cc-btn--quiet',desc:'Subtle'},
  ];
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="buttons"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>All button variants: primary, ghost, danger, quiet — in normal, hover, disabled states.</p>
            {variants.map(({kind,cls,desc})=>(
              <div key={kind} style={{marginBottom:14}}>
                <div className="cc-sec">{kind}<span className="n"> · {desc}</span><span className="rule"/></div>
                <div className="cc-card" style={{padding:'12px 14px',display:'flex',flexDirection:'column',gap:8}}>
                  <button className={'cc-btn '+cls}>{kind}</button>
                  <button className={'cc-btn '+cls} disabled>{kind} · disabled</button>
                </div>
              </div>
            ))}
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 2 · CHIPS ---------- */
function DSChipGallery(){
  const chips=[
    {label:'14 files',icon:ICON.file,c:''},
    {label:'touches git',icon:ICON.git,c:'color:var(--r-low);border-color:var(--r-low-bd)'},
    {label:'network',icon:ICON.net,c:'color:var(--r-high);border-color:var(--r-high-bd)'},
    {label:'credentials',icon:ICON.lock,c:'color:var(--r-crit);border-color:var(--r-crit-bd)'},
    {label:'Pro',icon:ICON.bolt,c:'color:var(--brand);border-color:var(--brand)'},
    {label:'soon',icon:null,c:'color:var(--ink-4);border-color:var(--line)'},
    {label:'new',icon:null,c:'color:var(--r-low);border-color:var(--r-low-bd)'},
  ];
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="chips &amp; badges"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Meta chips: file count, git, network, credentials, pro badge — each with proper coloring.</p>
            <div className="cc-sec">chips<span className="rule"/></div>
            <div className="cc-card" style={{padding:'14px 16px',display:'flex',flexWrap:'wrap',gap:8}}>
              {chips.map((c,i)=>(
                <span key={i} className="cc-chip" style={c.c?Object.fromEntries(c.c.split(';').filter(Boolean).map(s=>s.split(':').map(x=>x.trim()))):{}}>
                  {c.icon && <Ic d={c.icon} s={12}/>}{c.label}
                </span>
              ))}
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 3 · RISK BADGES ---------- */
function RiskBadgeGallery(){
  const levels=['low','medium','high','critical'];
  const colors={low:'#3fb57e',medium:'#e0a33a',high:'#f07a2e',critical:'#f24b3d'};
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="risk badges"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Risk levels: low (green), medium (amber), high (orange), critical (red).</p>
            <div className="cc-sec">risk levels<span className="rule"/></div>
            <div className="cc-card" style={{padding:'14px 16px',display:'flex',gap:10,flexWrap:'wrap'}}>
              {levels.map(l=><RiskChip key={l} level={l}/>)}
            </div>
            <div className="cc-sec">inline usage<span className="rule"/></div>
            <div className="cc-card" style={{padding:'14px 16px'}}>
              <div style={{display:'flex',alignItems:'center',gap:10,fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)'}}>
                rm -rf build/ <RiskChip level="high"/>
              </div>
            </div>
            <p className="cc-note" style={{marginTop:12}}>Risk ramp: <span style={{color:colors.low}}>■</span> {colors.low} · <span style={{color:colors.medium}}>■</span> {colors.medium} · <span style={{color:colors.high}}>■</span> {colors.high} · <span style={{color:colors.critical}}>■</span> {colors.critical}</p>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 4 · STATUS DOTS ---------- */
function StatusDotGallery(){
  const dots=[
    {id:'working',label:'Working',c:'var(--brand)'},
    {id:'waiting',label:'Waiting',c:'var(--r-med)'},
    {id:'idle',label:'Idle',c:'var(--idle)'},
    {id:'error',label:'Error',c:'var(--r-crit)'},
    {id:'offline',label:'Offline',c:'transparent'},
    {id:'done',label:'Done',c:'var(--ok)'},
  ];
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="status dots"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Status dots: working (brand blue glow), waiting (amber glow), idle (gray), error (red), offline (transparent border), done (green).</p>
            <div className="cc-sec">dots<span className="rule"/></div>
            <div className="cc-card" style={{padding:'14px 16px',display:'flex',flexDirection:'column',gap:12}}>
              {dots.map(d=>(
                <div key={d.id} style={{display:'flex',alignItems:'center',gap:10}}>
                  <span className="cc-sd"><span className={'d '+d.id}/>{d.label}</span>
                </div>
              ))}
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 5 · BLOCK CARD ---------- */
function DSBlockCardGallery(){
  const states=[
    {status:'running',color:'var(--brand)',exit:null,output:'Compiling SessionViewModel.swift…'},
    {status:'completed',color:'var(--r-low)',exit:'✓ exit 0',output:'Build complete! (12.4s)'},
    {status:'failed',color:'var(--r-crit)',exit:'✗ exit 1',output:'error: command not found'},
  ];
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="block cards"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Block card with left state gutter, prompt header, output area, and exit status footer.</p>
            <div className="cc-sec">states<span className="rule"/></div>
            {states.map(s=>(
              <div key={s.status} style={{marginBottom:10}}>
                <div className="cc-card" style={{padding:0,overflow:'hidden'}}>
                  <div style={{display:'flex',alignItems:'center',gap:8,padding:'8px 12px',borderBottom:'1px solid var(--line-2)',background:'var(--surface-2)'}}>
                    <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>~/repos/lancer</span>
                    <span style={{marginLeft:'auto'}}>
                      {s.exit
                        ? <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--r-low)'}}>{s.exit}</span>
                        : <span className="cc-sd"><span className="d working"/>running</span>}
                    </span>
                  </div>
                  <div className="cc-cmd" style={{display:'block',padding:0,border:'none',borderRadius:0}}>
                    <div className="body" style={{whiteSpace:'pre-wrap',padding:'10px 12px',fontSize:12,lineHeight:1.7,background:'var(--bg-2)'}}>
                      <div><span style={{color:'var(--brand)'}}>$ </span>swift build</div>
                      <div style={{color:'var(--ink-3)',marginTop:4}}>{s.output}</div>
                      {s.status==='running'&&<div style={{color:'var(--r-med)',marginTop:4}}>●<span className="cursor" style={{height:'.8em',marginLeft:4}}/></div>}
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 6 · MESSAGE BUBBLES ---------- */
function DSMessageBubbleGallery(){
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="message bubbles"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Chat bubbles: user (brand accent), assistant (surface), system event (dimmed, italic).</p>
            <div className="cc-sec">user<span className="rule"/></div>
            <div className="cc-card" style={{padding:'12px 14px',display:'flex',gap:10,justifyContent:'flex-end'}}>
              <div style={{maxWidth:'75%',background:'var(--brand-soft)',border:'1px solid var(--brand)',borderRadius:'2px 8px 2px 8px',padding:'10px 13px'}}>
                <div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)',lineHeight:1.55}}>Run the test suite and report back with coverage</div>
              </div>
            </div>
            <div className="cc-sec">assistant<span className="rule"/></div>
            <div className="cc-card" style={{padding:'12px 14px',display:'flex',gap:10}}>
              <PixelAvatar seed="claude" size={28}/>
              <div style={{maxWidth:'75%',background:'var(--surface)',border:'1px solid var(--line)',borderRadius:'2px 8px 2px 8px',padding:'10px 13px'}}>
                <div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)',lineHeight:1.55}}>Running <b>swift test</b> — 142 test cases across 6 targets.</div>
              </div>
            </div>
            <div className="cc-sec">system event<span className="rule"/></div>
            <div className="cc-card" style={{padding:'12px 14px',display:'flex',gap:10,justifyContent:'center'}}>
              <div style={{maxWidth:'80%',padding:'8px 14px',borderRadius:2}}>
                <div style={{fontSize:11.5,color:'var(--ink-4)',fontStyle:'italic',textAlign:'center',lineHeight:1.55,fontFamily:'var(--mono)'}}>Approval timeout — policy denied by default</div>
              </div>
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 7 · APPROVAL CARDS ---------- */
function DSApprovalCardGallery(){
  const actions=[
    {action:'approve',icon:ICON.check,c:'var(--r-low)',label:'Approve'},
    {action:'deny',icon:ICON.x,c:'var(--r-crit)',label:'Deny'},
    {action:'edit',icon:ICON.edit,c:'var(--r-med)',label:'Edit & run'},
    {action:'allow-always',icon:ICON.shield,c:'var(--brand)',label:'Allow always'},
  ];
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="redesign"><span className="d"/>redesign</span>
      <div className="cc">
        <SubNav title="approval cards"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Approval decision cards: approve (green tick), deny (red x), edit (pencil), allow-always (shield).</p>
            <div className="cc-sec">decisions<span className="rule"/></div>
            {actions.map(a=>(
              <div key={a.action} className="cc-card" style={{marginBottom:10,padding:'12px 14px'}}>
                <div style={{display:'flex',alignItems:'center',gap:10,marginBottom:10}}>
                  <span style={{width:26,height:26,borderRadius:2,background:a.c+'1a',border:'1px solid '+a.c,borderRadius:2,display:'flex',alignItems:'center',justifyContent:'center',color:a.c,flex:'none'}}><Ic d={a.icon} s={14}/></span>
                  <span style={{fontFamily:'var(--mono)',fontSize:13.5,fontWeight:600,color:'var(--ink)'}}>{a.label}</span>
                  <span style={{marginLeft:'auto'}}><RiskChip level="high"/></span>
                </div>
                <CommandBlock cmd="rm -rf build/ dist/" level="high"/>
                <div style={{marginTop:8}}>
                  <BlastChips files={2} git={false}/>
                </div>
              </div>
            ))}
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 8 · DECISION SHEET ---------- */
function DSDecisionSheetGallery(){
  const actions=[
    {id:'approve',icon:ICON.check,label:'Approve',desc:'Allow this one command',c:'var(--r-low)',bg:'var(--r-low-bg)'},
    {id:'deny',icon:ICON.x,label:'Deny',desc:'Block and notify the agent',c:'var(--r-crit)',bg:'var(--r-crit-bg)'},
    {id:'edit-run',icon:ICON.edit,label:'Edit & run',desc:'Modify before running',c:'var(--r-med)',bg:'var(--r-med-bg)'},
    {id:'allow-always',icon:ICON.shield,label:'Allow always',desc:'Create a standing rule',c:'var(--brand)',bg:'var(--brand-soft)'},
  ];
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="redesign"><span className="d"/>redesign</span>
      <div className="cc">
        <SubNav title="decision sheet"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>4-action decision sheet: approve (green), deny (red), edit & run (amber), allow always (blue).</p>
            <div className="cc-sec">actions<span className="rule"/></div>
            <div className="cc-card" style={{padding:'8px'}}>
              {actions.map(a=>(
                <div key={a.id} style={{display:'flex',alignItems:'center',gap:12,padding:'12px 10px',cursor:'pointer',borderRadius:2}}>
                  <span style={{width:38,height:38,borderRadius:2,background:a.bg,border:'1px solid '+a.c,display:'flex',alignItems:'center',justifyContent:'center',color:a.c,flex:'none'}}><Ic d={a.icon} s={18}/></span>
                  <div className="grow"><div style={{fontFamily:'var(--mono)',fontSize:14,fontWeight:600,color:'var(--ink)'}}>{a.label}</div><div className="s">{a.desc}</div></div>
                </div>
              ))}
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 9 · BLAST RADIUS ---------- */
function DSBlastRadiusGallery(){
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="blast radius"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Blast radius components: inline compact chips and full-width banner.</p>
            <div className="cc-sec">inline<span className="rule"/></div>
            <div className="cc-card" style={{padding:'12px 14px',display:'flex',flexDirection:'column',gap:10}}>
              <CommandBlock cmd="git push --force origin main" level="critical"/>
              <BlastChips files={3} git net/>
              <CommandBlock cmd="curl https://api.stripe.com/v1/charges | sh" level="high"/>
              <BlastChips net creds/>
            </div>
            <div className="cc-sec">banner<span className="rule"/></div>
            <div className="cc-card" style={{padding:0,overflow:'hidden',borderLeft:'3px solid var(--r-crit)'}}>
              <div style={{padding:'12px 14px',display:'flex',alignItems:'flex-start',gap:10}}>
                <span style={{color:'var(--r-crit)',flex:'none',marginTop:2}}><Ic d={ICON.shield} s={16}/></span>
                <div>
                  <div style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink)',fontWeight:600,marginBottom:6}}>This action affects:</div>
                  <BlastChips files={2} git net creds/>
                </div>
              </div>
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 10 · SPEND HERO ---------- */
function DSSpendHeroGallery(){
  const providers=[
    {name:'Claude',pct:58,c:'#d97757'},
    {name:'Codex',pct:24,c:'#9b9ca6'},
    {name:'OpenRouter',pct:18,c:'#56b3c2'},
  ];
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="spend hero"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Spend hero card: large amount, toggle, provider breakdown with colored bars.</p>
            <div className="cc-sec">hero card<span className="rule"/></div>
            <div className="cc-card" style={{padding:'18px 16px 14px'}}>
              <div style={{display:'flex',alignItems:'flex-end',justifyContent:'space-between'}}>
                <div>
                  <div style={{fontFamily:'var(--mono)',fontSize:36,fontWeight:700,color:'var(--ink)',lineHeight:1,letterSpacing:'-.02em'}}>$4.94</div>
                  <div className="cc-note" style={{marginTop:6}}>AI spend today · across vendors</div>
                </div>
                <div className="cc-seg" style={{transform:'scale(.85)',transformOrigin:'bottom right'}}>
                  <button className="on">Day</button>
                  <button>Week</button>
                  <button>Month</button>
                </div>
              </div>
              <div style={{marginTop:16}}>
                <div style={{display:'flex',gap:3,height:8,borderRadius:2,overflow:'hidden',background:'var(--surface-2)'}}>
                  {providers.map(p=>(
                    <div key={p.name} style={{width:p.pct+'%',background:p.c}}/>
                  ))}
                </div>
                <div style={{display:'flex',gap:16,marginTop:10,flexWrap:'wrap'}}>
                  {providers.map(p=>(
                    <div key={p.name} style={{display:'flex',alignItems:'center',gap:6}}>
                      <span style={{width:7,height:7,borderRadius:1,background:p.c,flex:'none'}}/>
                      <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>{p.name}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 11 · PROOF CARD ---------- */
function ProofCardViewGallery(){
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="proof card"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Completion proof card: goal summary, changed files, CI status, commit hash, timestamp.</p>
            <div className="cc-sec">completed<span className="rule"/></div>
            <div className="cc-card" style={{padding:0,overflow:'hidden',borderLeft:'3px solid var(--r-low)'}}>
              <div style={{padding:'14px 16px'}}>
                <div style={{display:'flex',alignItems:'center',gap:8,marginBottom:10}}>
                  <span style={{color:'var(--r-low)'}}><Ic d={ICON.check} s={16}/></span>
                  <span style={{fontFamily:'var(--mono)',fontSize:13.5,fontWeight:600,color:'var(--ink)'}}>exit 0</span>
                  <span style={{marginLeft:'auto',fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)'}}>2m ago</span>
                </div>
                <div style={{fontSize:13,color:'var(--ink-2)',lineHeight:1.5,marginBottom:10}}>Refactored auth session handler — patched <b style={{color:'var(--ink)'}}>session.swift</b> with retry logic.</div>
                <div style={{display:'flex',gap:8,flexWrap:'wrap'}}>
                  <span className="cc-chip"><Ic d={ICON.git} s={12}/>a3f8e2c</span>
                  <span className="cc-chip"><Ic d={ICON.file} s={12}/>2 files changed</span>
                  <span className="cc-chip" style={{color:'var(--r-low)',borderColor:'var(--r-low-bd)'}}><Ic d={ICON.check} s={12}/>CI passed</span>
                </div>
              </div>
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 12 · SCREEN HEADERS ---------- */
function DSScreenHeaderGallery(){
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="screen headers"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Screen headers: page title with cursor blink, breadcrumb trail, spectrum bar.</p>
            <div className="cc-sec">prompt header<span className="rule"/></div>
            <PromptHeader title="approvals" crumb={<b>agent approvals</b>}/>
            <div className="cc-sec">less detail<span className="rule"/></div>
            <PromptHeader title="inbox" crumb={<b>fleet</b>}/>
            <div className="cc-sec">breadcrumb trail<span className="rule"/></div>
            <div style={{padding:'10px 0 4px',fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink-3)',display:'flex',alignItems:'center',gap:2}}>
              <b style={{color:'var(--ink-2)',fontWeight:500}}>~/lancer</b>
              <span style={{color:'var(--brand)',padding:'0 .3em'}}>›</span>
              <b style={{color:'var(--ink-2)',fontWeight:500}}>agent approvals</b>
              <span style={{color:'var(--brand)',padding:'0 .3em'}}>›</span>
              detail
            </div>
            <Spectrum/>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 13 · STATUS HEADERS ---------- */
function DSStatusHeaderGallery(){
  const variants=[
    {state:'ok',label:'bridge connected',detail:'lancerd v1.0',spend:'$4.94'},
    {state:'warn',label:'bridge degraded',detail:'reconnecting…',spend:'$4.94'},
    {state:'bad',label:'bridge disconnected',detail:'last seen 2h ago',spend:null},
    {state:'offline',label:'no bridge',detail:'tap to configure',spend:null},
  ];
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="status headers"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Status headers: bridge status with animated dot, host label, today's spend, connection detail.</p>
            <div className="cc-sec">variants<span className="rule"/></div>
            <div className="cc-card" style={{padding:'4px 0'}}>
              {variants.map(v=>(
                <div key={v.state} className="cc-row" style={{cursor:'default'}}>
                  <span className={'dot '+v.state} style={{width:7,height:7,borderRadius:'50%',flex:'none',background:v.state==='ok'?'var(--ok)':v.state==='warn'?'var(--warn)':v.state==='bad'?'var(--bad)':'transparent',border:v.state==='offline'?'1.5px solid var(--ink-4)':'none'}}/>
                  <div className="grow" style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink-3)'}}>
                    <b style={{color:'var(--ink-2)',fontWeight:500}}>{v.label}</b>
                    {v.detail && <span> · {v.detail}</span>}
                  </div>
                  {v.spend && <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-2)'}}>today <em style={{fontStyle:'normal',fontWeight:600,color:'var(--ink)'}}>{v.spend}</em></span>}
                </div>
              ))}
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 14 · AGENT ISLAND ---------- */
function AgentIslandGallery(){
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="agent island"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Agent status island: compact card with PixelAvatar, name, model, status dot, progress, approval button.</p>
            <div className="cc-sec">compact<span className="rule"/></div>
            <div className="cc-card" style={{padding:'12px 14px'}}>
              <div style={{display:'flex',alignItems:'center',gap:10}}>
                <PixelAvatar seed="claudelancer" size={36} color="#d97757"/>
                <div className="grow" style={{minWidth:0}}>
                  <div style={{display:'flex',alignItems:'center',gap:8}}>
                    <span style={{fontFamily:'var(--mono)',fontSize:13.5,fontWeight:600,color:'var(--ink)'}}>Claude Code</span>
                    <span className="cc-sd"><span className="d working"/>working</span>
                  </div>
                  <div className="s" style={{marginTop:2}}>claude-sonnet-4.6 · Dev VPS</div>
                </div>
                <button className="cc-btn cc-btn--quiet" style={{height:32,minHeight:32,padding:'0 10px',fontSize:11}}><Ic d={ICON.check} s={12}/>Approve</button>
              </div>
              <div style={{display:'flex',gap:4,marginTop:10,height:4,borderRadius:2,overflow:'hidden',background:'var(--surface-2)'}}>
                <div style={{width:'64%',background:'var(--brand)'}}/>
              </div>
              <div style={{display:'flex',justifyContent:'space-between',marginTop:6}}>
                <span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-4)'}}>$3.18 of $5.00</span>
                <span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-4)'}}>6 calls</span>
              </div>
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 15 · HOST ROWS ---------- */
function DSHostRowGallery(){
  const hosts=[
    {name:'Dev VPS',addr:'dev-vps.local',status:'connected',dotClass:'working',last:'now'},
    {name:'Staging',addr:'192.168.1.42',status:'connecting',dotClass:'waiting',last:'2m ago'},
    {name:'Raspberry Pi',addr:'10.0.0.5',status:'disconnected',dotClass:'offline',last:'3d ago'},
  ];
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="host rows"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Host list rows: host name, PixelAvatar, address, connection status dot, last used time.</p>
            <div className="cc-sec">variants<span className="rule"/></div>
            <div className="cc-card" style={{padding:'4px 0'}}>
              {hosts.map(h=>(
                <div key={h.name} className="cc-row">
                  <PixelAvatar seed={h.name} size={32}/>
                  <div className="grow">
                    <div className="t" style={{fontSize:14}}>{h.name}</div>
                    <div className="s">{h.addr}</div>
                  </div>
                  <div style={{textAlign:'right',flex:'none'}}>
                    <span className="cc-sd"><span className={'d '+h.dotClass}/>{h.status}</span>
                    <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginTop:2}}>{h.last}</div>
                  </div>
                </div>
              ))}
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 16 · SESSION ROWS ---------- */
function DSSessionRowGallery(){
  const sessions=[
    {name:'lancer',agent:'Claude Code',status:'working',time:'now',unread:2},
    {name:'auth-svc',agent:'Codex',status:'waiting',time:'2m ago',unread:0},
    {name:'pi-runner',agent:'opencode',status:'offline',time:'3d ago',unread:0},
  ];
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="session rows"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Session rows: session name, agent badge, status dot, timestamp, unread indicator.</p>
            <div className="cc-sec">variants<span className="rule"/></div>
            <div className="cc-card" style={{padding:'4px 0'}}>
              {sessions.map(s=>(
                <div key={s.name} className="cc-row">
                  <PixelAvatar seed={s.agent+s.name} size={32}/>
                  <div className="grow">
                    <div style={{display:'flex',alignItems:'center',gap:8}}>
                      <div className="t" style={{fontSize:14}}>{s.name}</div>
                      <span className="cc-chip" style={{fontSize:9.5,padding:'1px 6px'}}>{s.agent}</span>
                    </div>
                    <div className="s" style={{display:'flex',alignItems:'center',gap:6}}>
                      <span className="cc-sd" style={{fontSize:10.5}}><span className={'d '+s.status}/>{s.status}</span>
                      <span>· {s.time}</span>
                    </div>
                  </div>
                  {s.unread>0 && (
                    <span style={{minWidth:20,height:20,borderRadius:'50%',background:'var(--brand)',color:'#fff',fontSize:10,fontWeight:700,display:'flex',alignItems:'center',justifyContent:'center',fontFamily:'var(--mono)'}}>{s.unread}</span>
                  )}
                </div>
              ))}
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 17 · STATES ---------- */
function DSStateGallery(){
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="states"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Empty, loading, error, offline states — skeleton rows, empty state, error card.</p>
            <div className="cc-sec">skeleton list<span className="rule"/></div>
            <div className="cc-card" style={{padding:'14px 16px'}}>
              {[1,2,3].map(i=>(
                <div key={i} style={{display:'flex',alignItems:'center',gap:12,padding:'8px 0'}}>
                  <div style={{width:32,height:32,borderRadius:2,background:'var(--surface-2)',animation:'ds-pulse 1.8s ease-in-out infinite'}}/>
                  <div className="grow">
                    <div style={{width:'55%',height:12,borderRadius:2,background:'var(--surface-2)',animation:'ds-pulse 1.8s ease-in-out infinite',marginBottom:6}}/>
                    <div style={{width:'35%',height:9,borderRadius:2,background:'var(--surface-2)',animation:'ds-pulse 1.8s ease-in-out infinite'}}/>
                  </div>
                </div>
              ))}
            </div>
            <div className="cc-sec">empty state<span className="rule"/></div>
            <div className="cc-empty" style={{padding:'32px 16px'}}>
              <div className="glyph"><Ic d={ICON.inbox} s={24}/></div>
              <h3>No sessions</h3>
              <p>Connect a host or dispatch a task to get started.</p>
              <button className="cc-btn cc-btn--primary" style={{marginTop:12,height:40,minHeight:40,fontSize:12}}>Create a session</button>
            </div>
            <div className="cc-sec">error card<span className="rule"/></div>
            <div className="cc-card" style={{padding:'14px 16px',display:'flex',gap:10,alignItems:'flex-start',borderLeft:'3px solid var(--r-crit)'}}>
              <span style={{color:'var(--r-crit)',flex:'none',marginTop:1}}><Ic d={ICON.x} s={18}/></span>
              <div className="grow">
                <div style={{fontFamily:'var(--mono)',fontSize:13.5,fontWeight:600,color:'var(--ink)'}}>Connection failed</div>
                <div className="s" style={{whiteSpace:'normal',marginTop:4}}>Could not reach the bridge on dev-vps.local. Check the host is running.</div>
                <button className="cc-btn cc-btn--ghost" style={{height:36,minHeight:36,marginTop:10,padding:'0 14px',fontSize:12}}><svg width={13} height={13} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.7} strokeLinecap="round" strokeLinejoin="round"><path d="M21 12a9 9 0 1 1-3-6.7"/><path d="M21 4v5h-5"/></svg>Retry</button>
              </div>
            </div>
            <div className="cc-sec">offline state<span className="rule"/></div>
            <div className="cc-empty" style={{padding:'24px 16px'}}>
              <div className="glyph"><Ic d={ICON.fleet} s={24}/></div>
              <h3>Bridge disconnected</h3>
              <p>Agents can't run without a bridge. Install one on your host.</p>
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 18 · TAB BAR ---------- */
function DSTabBarGallery(){
  const [active,setActive]=React.useState('inbox');
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="keep"><span className="d"/>keep</span>
      <div className="cc" style={{position:'relative'}}>
        <SubNav title="tab bar"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Tab bar with inbox (badge count 3), fleet, activity, settings. Active tab highlighted brand blue.</p>
            <div className="cc-sec">interactive variant<span className="rule"/></div>
            <div className="cc-card" style={{padding:'14px 16px',display:'flex',flexDirection:'column',gap:10}}>
              {['inbox','fleet','activity','settings'].map(t=>(
                <div key={t} onClick={()=>setActive(t)} style={{display:'flex',alignItems:'center',gap:10,padding:'8px 10px',borderRadius:2,cursor:'pointer',background:active===t?'var(--brand-soft)':'transparent',border:active===t?'1px solid var(--brand)':'1px solid transparent'}}>
                  <Ic d={ICON[t]} s={18}/>
                  <span style={{fontFamily:'var(--mono)',fontSize:13,fontWeight:active===t?600:400,color:active===t?'var(--brand)':'var(--ink-2)',textTransform:'capitalize'}}>{t}</span>
                  {t==='inbox'&&<span style={{marginLeft:'auto',minWidth:18,height:18,borderRadius:9,background:'var(--brand)',color:'#fff',fontSize:9,fontWeight:700,display:'flex',alignItems:'center',justifyContent:'center',fontFamily:'var(--mono)'}}>3</span>}
                  {active===t&&<span style={{marginLeft:'auto',width:6,height:6,borderRadius:1,background:'var(--brand)'}}/>}
                </div>
              ))}
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
        <div style={{position:'absolute',left:0,right:0,bottom:0,zIndex:40,display:'flex',alignItems:'stretch',height:76,padding:'0 8px 16px'}}>
          {[['inbox','inbox',ICON.inbox],['fleet','fleet',ICON.fleet],['activity','activity',ICON.activity],['settings','settings',ICON.settings]].map(([id,label,ic])=>(
            <div key={id} onClick={()=>setActive(id)} style={{flex:1,display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center',gap:4,cursor:'pointer',color:active===id?'var(--brand)':'var(--ink-3)',fontFamily:'var(--mono)',fontSize:10,letterSpacing:'.12em',textTransform:'uppercase',position:'relative',paddingTop:6}}>
              {active===id&&<span style={{position:'absolute',top:0,width:14,height:2,borderRadius:2,background:'var(--brand)'}}/>}
              <span style={{position:'relative'}}>
                <Ic d={ic} s={22} sw={active===id?2:1.7}/>
                {id==='inbox'&&<span style={{position:'absolute',top:-3,right:-9,minWidth:15,height:15,borderRadius:8,background:'var(--brand)',color:'#fff',fontSize:9,fontWeight:700,display:'flex',alignItems:'center',justifyContent:'center',padding:'0 4px',fontFamily:'var(--sans)'}}>3</span>}
              </span>
              {label}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

/* ---------- 19 · SEGMENTED CONTROLS ---------- */
function DSSegmentedControlGallery(){
  const [seg2,setSeg2]=React.useState(0);
  const [seg3,setSeg3]=React.useState(1);
  const [seg4,setSeg4]=React.useState(0);
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="segmented controls"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Segmented controls: 2, 3, and 4 segments. Active segment in brand blue.</p>
            <div className="cc-sec">2-segment · Free/Pro<span className="rule"/></div>
            <div className="cc-seg">
              {['Free','Pro'].map((l,i)=>(
                <button key={l} className={seg2===i?'on':''} onClick={()=>setSeg2(i)}>{l}</button>
              ))}
            </div>
            <div className="cc-sec" style={{marginTop:20}}>3-segment · Low/Med/High<span className="rule"/></div>
            <div className="cc-seg">
              {['Low','Med','High'].map((l,i)=>(
                <button key={l} className={seg3===i?'on':''} onClick={()=>setSeg3(i)}>{l}</button>
              ))}
            </div>
            <div className="cc-sec" style={{marginTop:20}}>4-segment · All/Active/Stale/Merged<span className="rule"/></div>
            <div className="cc-seg">
              {['All','Active','Stale','Merged'].map((l,i)=>(
                <button key={l} className={seg4===i?'on':''} onClick={()=>setSeg4(i)}>{l}</button>
              ))}
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 20 · TOASTS ---------- */
function DSToastGallery(){
  const toasts=[
    {icon:ICON.check,c:'var(--r-low)',msg:'Command approved and dispatched'},
    {icon:ICON.shield,c:'var(--r-med)',msg:'Action requires your review'},
    {icon:ICON.x,c:'var(--r-crit)',msg:'Connection to bridge lost'},
    {icon:ICON.bell,c:'var(--ink-2)',msg:'Agent completed its task'},
  ];
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="toasts"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Toast notifications: success (green), warning (amber), error (red), info (default).</p>
            <div className="cc-sec">variants<span className="rule"/></div>
            <div style={{display:'flex',flexDirection:'column',gap:10}}>
              {toasts.map((t,i)=>(
                <div key={i} className="cc-toast" style={{position:'relative',left:'auto',right:'auto',bottom:'auto',animation:'none',boxShadow:'none'}}>
                  <span className="ic" style={{color:t.c}}><Ic d={t.icon} s={18}/></span>
                  <span style={{flex:1}}>{t.msg}</span>
                  <span className="undo">{i===0?'Undo':'Dismiss'}</span>
                </div>
              ))}
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 21 · SHEET ---------- */
function DSSheetGallery(){
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="bottom sheet"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Bottom sheet pattern: grip handle, title, scrollable body, fixed footer with actions.</p>
            <div className="cc-sec">sheet mockup<span className="rule"/></div>
            <div style={{background:'var(--bg-2)',border:'1px solid var(--line)',borderRadius:'2px',overflow:'hidden',display:'flex',flexDirection:'column'}}>
              <div style={{width:38,height:5,borderRadius:3,background:'var(--line-strong)',margin:'9px auto 2px',flex:'none'}}/>
              <div style={{padding:'8px 18px 4px'}}>
                <h2 className="cc-h2" style={{marginBottom:6}}>Approve this action?</h2>
                <div className="cc-note" style={{marginBottom:12}}>The agent wants to run this command on <b style={{color:'var(--ink-2)'}}>Dev VPS</b>.</div>
                <div className="cc-cmd" style={{marginBottom:12}}><div className="gut"/><div className="body"><span className="sigil">$ </span>rm -rf build/ dist/</div></div>
                <BlastChips files={2} git/>
              </div>
              <div style={{flex:1,minHeight:80}}/>
              <div style={{padding:'14px 18px',borderTop:'1px solid var(--line)',background:'var(--bg-2)'}}>
                <div className="cc-btnrow">
                  <button className="cc-btn cc-btn--quiet" style={{flex:1}}><Ic d={ICON.x} s={14}/>Deny</button>
                  <button className="cc-btn cc-btn--primary" style={{flex:1.4}}><Ic d={ICON.check} s={15}/>Approve</button>
                </div>
              </div>
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 22 · DIVIDERS ---------- */
function DSDividerGallery(){
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="dividers"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Dividers: thin line, spectrum bar (7-color gradient), dot matrix.</p>
            <div className="cc-sec">thin line<span className="rule"/></div>
            <div className="cc-divider" style={{margin:0,height:1,background:'var(--line)'}}/>
            <div className="cc-sec" style={{marginTop:20}}>spectrum bar<span className="rule"/></div>
            <Spectrum/>
            <div className="cc-sec" style={{marginTop:20}}>dot matrix<span className="rule"/></div>
            <div style={{display:'grid',gridTemplateColumns:'repeat(12,1fr)',gap:4,padding:'8px 0'}}>
              {Array.from({length:48}).map((_,i)=>(
                <div key={i} style={{width:'100%',aspectRatio:1,borderRadius:1,background:'var(--surface-3)',opacity:0.3+((ccHash('dot'+i)%100)/200)}}/>
              ))}
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 23 · PIXEL AVATARS ---------- */
function PixelAvatarGallery(){
  const seeds=['claude','codex','opencode','dev-vps','staging','pi-runner','auth-svc','ci-bot'];
  const palettes=[['#d97757','#7a3f2c'],['#5b8def','#2c3f7a'],['#6ac285','#2c5a3a'],['#b07ad9','#4a2c66'],['#d9b24a','#6a5320'],['#56b3c2','#1f5159'],['#e07a8f','#6a2a3a'],['#8ac96a','#3a5a2a']];
  const sizes=[24,32,38,48];
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="keep"><span className="d"/>keep</span>
      <div className="cc">
        <SubNav title="pixel avatars"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Pixel avatars: deterministic art seeded by string, different color palettes and sizes.</p>
            <div className="cc-sec">8 palettes · size 38<span className="rule"/></div>
            <div className="cc-card" style={{padding:'14px 16px',display:'flex',gap:12,flexWrap:'wrap'}}>
              {seeds.map((s,i)=>(
                <div key={s} style={{display:'flex',flexDirection:'column',alignItems:'center',gap:6}}>
                  <PixelAvatar seed={s} size={38} color={palettes[i%palettes.length][0]}/>
                  <span style={{fontFamily:'var(--mono)',fontSize:9.5,color:'var(--ink-4)'}}>{s}</span>
                </div>
              ))}
            </div>
            <div className="cc-sec">sizes<span className="rule"/></div>
            <div className="cc-card" style={{padding:'14px 16px',display:'flex',alignItems:'flex-end',gap:16}}>
              {sizes.map(s=>(
                <div key={s} style={{display:'flex',flexDirection:'column',alignItems:'center',gap:4}}>
                  <PixelAvatar seed="claude" size={s} color="#d97757"/>
                  <span style={{fontFamily:'var(--mono)',fontSize:9.5,color:'var(--ink-4)'}}>{s}px</span>
                </div>
              ))}
            </div>
            <p className="cc-note" style={{marginTop:12}}>Seeded by host/agent name · 8 color palettes · deterministic pixel grid (5×5 mirrored)</p>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 24 · E2E RELAY STATUS ---------- */
function E2ERelayStatusBadge(){
  const states=[
    {status:'paired',color:'var(--r-low)',icon:ICON.lock,label:'Paired'},
    {status:'pairing',color:'var(--r-med)',icon:ICON.clock,label:'Pairing'},
    {status:'disconnected',color:'var(--ink-4)',icon:ICON.x,label:'Disconnected'},
  ];
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="e2e relay"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>E2E relay status badge: paired (green lock), pairing (amber), disconnected (gray).</p>
            <div className="cc-sec">states<span className="rule"/></div>
            <div className="cc-card" style={{padding:'14px 16px',display:'flex',flexDirection:'column',gap:12}}>
              {states.map(s=>(
                <div key={s.status} style={{display:'flex',alignItems:'center',gap:10}}>
                  <span style={{width:28,height:28,borderRadius:2,background:s.color+'1a',border:'1px solid '+s.color,display:'flex',alignItems:'center',justifyContent:'center',color:s.color,flex:'none'}}><Ic d={s.icon} s={14}/></span>
                  <div className="grow">
                    <div style={{fontFamily:'var(--mono)',fontSize:13,fontWeight:600,color:'var(--ink)'}}>{s.label}</div>
                    <div className="s">X25519 · ChaCha20-Poly1305</div>
                  </div>
                  <span className="cc-sd"><span className={'d '+(s.status==='paired'?'done':s.status==='pairing'?'waiting':'offline')}/>{s.status}</span>
                </div>
              ))}
            </div>
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ---------- 25 · HOST HEALTH BADGES ---------- */
function HostHealthBadgeGallery(){
  const badges=[
    {status:'healthy',color:'var(--r-low)',dot:'done',cpu:'12%',mem:'34%',disk:'52%',uptime:'14d'},
    {status:'degraded',color:'var(--r-med)',dot:'waiting',cpu:'78%',mem:'82%',disk:'66%',uptime:'3d'},
    {status:'offline',color:'var(--r-crit)',dot:'offline',cpu:'—',mem:'—',disk:'—',uptime:'0'},
  ];
  return (
    <div className="cc-frame">
      <span className="cc-tag" data-k="add"><span className="d"/>add</span>
      <div className="cc">
        <SubNav title="host health"/>
        <div className="cc-scroll">
          <div className="cc-pad" style={{paddingTop:10}}>
            <p className="cc-lead" style={{margin:'0 0 12px'}}>Host health badges: healthy (green), degraded (amber), offline (red). Each with CPU/memory/disk/uptime.</p>
            <div className="cc-sec">badges<span className="rule"/></div>
            {badges.map(b=>(
              <div key={b.status} className="cc-card" style={{marginBottom:10,padding:'12px 14px',borderLeft:'3px solid '+b.color}}>
                <div style={{display:'flex',alignItems:'center',gap:8,marginBottom:10}}>
                  <span className="cc-sd"><span className={'d '+b.dot}/>{b.status}</span>
                  <span style={{marginLeft:'auto',fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)'}}>uptime {b.uptime}</span>
                </div>
                <div style={{display:'flex',gap:12}}>
                  {[['CPU',b.cpu],['Memory',b.mem],['Disk',b.disk]].map(([l,v])=>(
                    <div key={l} style={{flex:1,textAlign:'center',padding:'8px 4px',background:'var(--surface-2)',borderRadius:2}}>
                      <div style={{fontFamily:'var(--mono)',fontSize:15,fontWeight:600,color:'var(--ink)'}}>{v}</div>
                      <div style={{fontFamily:'var(--mono)',fontSize:9.5,color:'var(--ink-4)',marginTop:2,textTransform:'uppercase',letterSpacing:'.06em'}}>{l}</div>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
          <div className="cc-bottompad"/>
        </div>
      </div>
    </div>
  );
}

/* ── pulse keyframes injected once ── */
(function injectDSPulse(){
  if(typeof document==='undefined'||document.getElementById('ds-pulse'))return;
  const s=document.createElement('style');
  s.id='ds-pulse';
  s.textContent='@keyframes ds-pulse{0%,100%{opacity:1}50%{opacity:.35}}';
  document.head.appendChild(s);
})();

Object.assign(window,{
  DSButtonGallery,DSChipGallery,RiskBadgeGallery,StatusDotGallery,
  DSBlockCardGallery,DSMessageBubbleGallery,DSApprovalCardGallery,
  DSDecisionSheetGallery,DSBlastRadiusGallery,DSSpendHeroGallery,
  ProofCardViewGallery,DSScreenHeaderGallery,DSStatusHeaderGallery,
  AgentIslandGallery,DSHostRowGallery,DSSessionRowGallery,DSStateGallery,
  DSTabBarGallery,DSSegmentedControlGallery,DSToastGallery,DSSheetGallery,
  DSDividerGallery,PixelAvatarGallery,E2ERelayStatusBadge,HostHealthBadgeGallery,
});