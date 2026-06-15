/* ============================================================
   CONDUIT — V1 core / roadmap screens missing from the board
   These artboards cover shipped primitives and near-term control-plane
   surfaces that did not yet have phone-frame coverage.
   ============================================================ */
const RX = {};

/* ---------- 1. Proof Card — completion summary ---------- */
function ProofCardScreen({onBack}){
  const DATA={
    agent:'claude', name:'conduit', status:'completed',
    duration:'12m 41s',
    tests:{passed:42, failed:0, failedNames:[]},
    diff:{files:18, insertions:342, deletions:67, filesChanged:['SessionViewModel.swift','BlockRenderer.swift','ToolCardView.swift','ChatTranscriptView.swift','DSBlockCard.swift','PTYBridge.swift','AgentIsland.swift']},
    commands:['swift build','swift test --filter SessionViewModel','patch src/auth/session.swift','curl https://api.stripe.com/v1/...'],
    approvals:{asked:3,approved:2,denied:1},
    policyExceptions:0,
    spend:{total:4.94, tokens:{in:142_000, out:38_000}}
  };
  const d=DATA;
  const linesShown=3;
  return (
    <div className="cc">
      <SubNav title="proof" onBack={onBack} right={<span className="cc-chip"><Ic d={ICON.check} s={12}/>completed</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          {/* agent identity */}
          <div className="cc-card" style={{padding:'14px 15px'}}>
            <div style={{display:'flex',alignItems:'center',gap:10}}>
              <PixelAvatar seed={d.agent+d.name} size={38} color={VENDOR[d.agent].c}/>
              <div className="grow" style={{minWidth:0}}>
                <div style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink)',fontWeight:500}}>{VENDOR[d.agent].label} <span style={{color:'var(--ink-4)',fontSize:11.5}}>{d.name}</span></div>
                <div className="s" style={{marginTop:3}}>Dev VPS · claude-sonnet-4.6</div>
              </div>
              <div style={{textAlign:'right'}}>
                <span className="cc-sd"><span className="d done"/>done</span>
                <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginTop:4}}>{d.duration}</div>
              </div>
            </div>
          </div>

          {/* tests */}
          <div className="cc-sec">tests<span className="rule"/></div>
          <div className="cc-card" style={{padding:'12px 15px',display:'flex',alignItems:'center',gap:12}}>
            <span style={{fontFamily:'var(--mono)',fontSize:28,fontWeight:700,color:'var(--r-low)'}}>{d.tests.passed}</span>
            <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>passed</span>
            {d.tests.failed>0 && <>
              <span style={{fontFamily:'var(--mono)',fontSize:28,fontWeight:700,color:'var(--r-crit)'}}>{d.tests.failed}</span>
              <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>failed</span>
            </>}
            <span style={{marginLeft:'auto',fontFamily:'var(--mono)',fontSize:10.5,color:'var(--r-low)'}}><Ic d={ICON.check} s={14}/> all passing</span>
          </div>

          {/* diff */}
          <div className="cc-sec">diff <span className="n">· {d.diff.filesChanged} files</span><span className="rule"/></div>
          <div className="cc-card" style={{padding:'12px 15px'}}>
            <div style={{display:'flex',gap:18,marginBottom:10}}>
              <span style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--r-low)'}}>+{d.diff.insertions}</span>
              <span style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--r-crit)'}}>−{d.diff.deletions}</span>
              <span style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink-3)'}}>{d.diff.filesChanged} files</span>
            </div>
            {d.diff.filesChanged.slice(0,linesShown).map((f,i)=>(
              <div key={i} style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink-3)',padding:'3px 0'}}>{f}</div>
            ))}
            {d.diff.filesChanged.length>linesShown && <div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--brand)',marginTop:4,cursor:'pointer'}}>+{d.diff.filesChanged.length-linesShown} more files</div>}
          </div>

          {/* commands */}
          <div className="cc-sec">commands run<span className="rule"/></div>
          <div className="cc-card" style={{padding:0}}>
            {d.commands.slice(0,linesShown).map((c,i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}><span style={{color:'var(--brand)'}}>$ </span>{c}</span>
              </div>
            ))}
            {d.commands.length>linesShown && <div className="cc-row" style={{cursor:'pointer',fontFamily:'var(--mono)',fontSize:11,color:'var(--brand)'}}>+{d.commands.length-linesShown} more</div>}
          </div>

          {/* approvals */}
          <div className="cc-sec">approvals<span className="rule"/></div>
          <div className="cc-card" style={{padding:'12px 15px',display:'flex',gap:18}}>
            <div><div style={{fontFamily:'var(--mono)',fontSize:18,fontWeight:700,color:'var(--ink)'}}>{d.approvals.asked}</div><div className="s">asked</div></div>
            <div><div style={{fontFamily:'var(--mono)',fontSize:18,fontWeight:700,color:'var(--r-low)'}}>{d.approvals.approved}</div><div className="s">approved</div></div>
            <div><div style={{fontFamily:'var(--mono)',fontSize:18,fontWeight:700,color:'var(--r-crit)'}}>{d.approvals.denied}</div><div className="s">denied</div></div>
          </div>

          {/* spend */}
          <div className="cc-sec">spend<span className="rule"/></div>
          <div className="cc-card" style={{padding:'12px 15px',display:'flex',alignItems:'baseline',gap:12,justifyContent:'space-between'}}>
            <span style={{fontFamily:'var(--mono)',fontSize:28,fontWeight:700,color:'var(--ink)'}}>${d.spend.total.toFixed(2)}</span>
            {d.spend.tokens && <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>{d.spend.tokens.in.toLocaleString()} in / {d.spend.tokens.out.toLocaleString()} out</span>}
          </div>

          {/* verification stamp */}
          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start',borderColor:'var(--r-low-bd)',background:'var(--r-low-bg)'}}>
            <span style={{color:'var(--r-low)',flex:'none',marginTop:1}}><Ic d={ICON.shield} s={16}/></span>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>This proof attests to the run's outcome. <b style={{color:'var(--ink)'}}>Tamper-evident audit</b> entries back every decision and command.</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <div className="cc-btnrow">
          <button className="cc-btn cc-btn--ghost" style={{flex:1}}><Ic d={ICON.shield} s={14}/>Export proof</button>
          <button className="cc-btn cc-btn--primary" style={{flex:1}}><Ic d={ICON.copy} s={15}/>Share</button>
        </div>
      </div>
    </div>
  );
}

/* ---------- 2. Loop Detail — goal, plan, steps, CI, proof ---------- */
function LoopDetailScreen({onBack}){
  const LOOP={
    goal:'Refactor the session store to use async sequences',
    plan:'1. Extract BlockRenderer protocol\n2. Migrate SessionViewModel to async streams\n3. Add deprecation shims\n4. Run full test suite',
    currentStep:'Step 2/4: SessionViewModel async migration',
    blockedReason:null,
    agent:'claude', name:'conduit', model:'claude-sonnet-4.6',
    host:'Dev VPS', repo:'conduit', branch:'feat/async-session', worktree:'~/repos/conduit',
    filesChanged:7, commandsRun:12, testsRun:156,
    approvalsAsked:3, approvalsApproved:2, approvalsDenied:1,
    spendUSD:4.94,
    status:'running',
    ciEvents:[
      {type:'pullRequest',status:'pending',prNumber:218,prURL:'#'},
      {type:'checkRun',status:'running',context:'swift build'}
    ]
  };
  const l=LOOP;
  return (
    <div className="cc">
      <SubNav title="loop" onBack={onBack} right={<span className="cc-sd"><span className="d working"/>{l.status}</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>

          {/* goal */}
          <div className="cc-card" style={{padding:'14px 15px'}}>
            <div style={{fontFamily:'var(--mono)',fontSize:11,letterSpacing:'.1em',color:'var(--ink-4)',marginBottom:8}}>GOAL</div>
            <div style={{fontSize:15,color:'var(--ink)',lineHeight:1.45,fontWeight:500}}>{l.goal}</div>
          </div>

          {/* agent identity */}
          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',alignItems:'center',gap:10}}>
            <PixelAvatar seed={l.agent+l.name} size={34} color={VENDOR[l.agent].c}/>
            <div className="grow" style={{minWidth:0}}>
              <div style={{fontFamily:'var(--mono)',fontSize:13.5,color:'var(--ink)',fontWeight:500}}>{VENDOR[l.agent].label} <span style={{color:'var(--ink-4)',fontSize:11}}>{l.name}</span></div>
              <div className="s" style={{marginTop:2}}>{l.model} · {l.host}</div>
            </div>
          </div>

          {/* location */}
          <div className="cc-card" style={{marginTop:12,padding:'10px 14px',display:'flex',gap:12,flexWrap:'wrap'}}>
            {[['repo',l.repo],['branch',l.branch],['worktree',l.worktree]].map(([k,v])=>(
              <span key={k} className="cc-chip" style={{border:'none',background:'none',padding:0,color:'var(--ink-3)'}}>
                <span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-4)',marginRight:4}}>{k}</span>
                <span style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink)'}}>{v}</span>
              </span>
            ))}
          </div>

          {/* plan & progress */}
          <div className="cc-sec">plan<span className="rule"/></div>
          <div className="cc-card" style={{padding:'10px 14px'}}>
            {l.plan.split('\n').map((step,i)=>(
              <div key={i} style={{display:'flex',alignItems:'flex-start',gap:9,padding:'6px 0'}}>
                <span style={{width:20,height:20,borderRadius:2,display:'flex',alignItems:'center',justifyContent:'center',fontFamily:'var(--mono)',fontSize:10,fontWeight:600,
                  background:i===1?'var(--brand)':'var(--surface-2)',color:i===1?'#fff':'var(--ink-4)',border:i===1?'none':'1px solid var(--line)'}}>{i+1}</span>
                <span style={{fontSize:12.5,color:i===1?'var(--ink)':'var(--ink-2)',lineHeight:1.5}}>{step.replace(/^\d+\.\s*/,'')}</span>
              </div>
            ))}
          </div>

          {/* live progress counts */}
          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:18,justifyContent:'space-around'}}>
            {[['files',l.filesChanged],['commands',l.commandsRun],['tests',l.testsRun],['approvals',l.approvalsAsked]].map(([k,v])=>(
              <div key={k} style={{textAlign:'center'}}>
                <div style={{fontFamily:'var(--mono)',fontSize:16,fontWeight:600,color:'var(--ink)'}}>{v}</div>
                <div className="s" style={{marginTop:2}}>{k}</div>
              </div>
            ))}
          </div>

          {/* approvals status */}
          <div className="cc-sec">approvals<span className="rule"/></div>
          <div className="cc-card" style={{padding:'10px 14px',display:'flex',gap:18}}>
            {[
              ['asked',l.approvalsAsked,'var(--ink-2)'],
              ['approved',l.approvalsApproved,'var(--r-low)'],
              ['denied',l.approvalsDenied,'var(--r-crit)']
            ].map(([k,v,c])=>(
              <div key={k} style={{flex:1,textAlign:'center'}}>
                <div style={{fontFamily:'var(--mono)',fontSize:18,fontWeight:700,color:c}}>{v}</div>
                <div className="s">{k}</div>
              </div>
            ))}
          </div>

          {/* spend */}
          <div className="cc-sec">spend<span className="rule"/></div>
          <div className="cc-card" style={{padding:'12px 14px',display:'flex',alignItems:'baseline',justifyContent:'space-between'}}>
            <span style={{fontFamily:'var(--mono)',fontSize:20,fontWeight:700,color:'var(--ink)'}}>${l.spendUSD.toFixed(2)}</span>
            <span className="cc-sd"><span className="d done"/>within budget</span>
          </div>

          {/* CI events */}
          <div className="cc-sec">ci status<span className="rule"/></div>
          <div className="cc-card" style={{padding:'2px 0'}}>
            {l.ciEvents.map((e,i)=>(
              <div key={i} className="cc-row" style={{cursor:'pointer'}}>
                <span style={{flex:'none',color:e.status==='running'?'var(--brand)':e.status==='pending'?'var(--r-med)':'var(--r-low)'}}>
                  <Ic d={e.status==='running'?ICON.fleet:ICON.git} s={15}/>
                </span>
                <div className="grow">
                  <div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{e.type==='pullRequest'?`PR #${e.prNumber}`:e.context}</div>
                </div>
                <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:e.status==='running'?'var(--brand)':e.status==='pending'?'var(--r-med)':'var(--r-low)',textTransform:'uppercase'}}>{e.status}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 3. Policy Simulator — simulate policy against audit history ---------- */
function PolicySimulatorScreen({onBack}){
  const [period,setPeriod]=React.useState(7);
  const [simulated,setSimulated]=React.useState(false);
  const sim={totalActions:53,autoApproved:42,asked:8,denied:3,riskDist:[{level:'low',count:28},{level:'medium',count:15},{level:'high',count:7},{level:'critical',count:3}]};
  const ruleHits=[
    ['allow-read','allow',31,'git status, ls, swift build'],
    ['ask-on-write','ask',8,'patch, npm install'],
    ['deny-network','deny',3,'curl, wget'],
    ['deny-destructive','deny',2,'rm -rf'],
  ];
  const yamlText=[
    'default: ask',
    'rules:',
    '  - match: {tool: read}      effect: allow',
    '  - match: {tool: write, path: "*.{ts,swift,go}"}  effect: allow',
    '  - match: {tool: delete}    effect: ask',
    '  - match: {tool: network}   effect: ask',
    '  - match: {path: ".env"}    effect: deny',
  ];
  return (
    <div className="cc">
      <SubNav title="policy simulator" onBack={onBack}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Test a policy against the last N days of audit history to see what would auto-approve, ask, or be denied.</p>

          <div className="cc-sec">period<span className="rule"/></div>
          <div className="cc-seg" style={{marginBottom:12}}>
            {[1,3,7,14,30].map(d=>(<button key={d} className={period===d?'on':''} onClick={()=>setPeriod(d)}>{d}<span style={{fontSize:9.5}}>d</span></button>))}
          </div>

          <div className="cc-sec">policy to test<span className="rule"/></div>
          <div className="cc-cmd" style={{display:'block',padding:0}}>
            <div className="body" style={{whiteSpace:'pre',padding:'11px 13px',fontSize:11.5,lineHeight:1.7}}>
              {yamlText.map((l,i)=>(<div key={i} style={{color:l.includes('allow')?'var(--r-low)':l.includes('deny')?'var(--r-crit)':l.includes('ask')?'var(--r-med)':'var(--ink-2)'}}>{l}</div>))}
            </div>
          </div>

          <button className="cc-btn cc-btn--primary cc-btn--block" style={{marginTop:14}} onClick={()=>setSimulated(true)}>
            <Ic d={XIC.gauge||ICON.shield} s={15}/>Simulate Last {period} Days
          </button>

          {simulated && <>
            <div className="cc-sec" style={{marginTop:18}}>results · {period} days<span className="rule"/></div>
            <div className="cc-card" style={{padding:'14px 15px'}}>
              <div style={{display:'flex',alignItems:'flex-end',justifyContent:'space-between',marginBottom:14}}>
                <div>
                  <div style={{fontFamily:'var(--mono)',fontSize:26,fontWeight:700,color:'var(--ink)'}}>{sim.totalActions}</div>
                  <div className="cc-note" style={{marginTop:3}}>actions replayed</div>
                </div>
                <div style={{textAlign:'right'}}>
                  <div style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--r-low)'}}>{sim.autoApproved} auto-allow</div>
                  <div style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--r-med)'}}>{sim.asked} ask</div>
                  <div style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--r-crit)'}}>{sim.denied} denied</div>
                </div>
              </div>

              {/* bar viz */}
              <div style={{display:'flex',gap:4,height:6,borderRadius:3,overflow:'hidden',background:'var(--surface-2)'}}>
                <div style={{width:Math.round(sim.autoApproved/sim.totalActions*100)+'%',background:'var(--r-low)'}}/>
                <div style={{width:Math.round(sim.asked/sim.totalActions*100)+'%',background:'var(--r-med)'}}/>
                <div style={{width:Math.round(sim.denied/sim.totalActions*100)+'%',background:'var(--r-crit)'}}/>
              </div>
              <div style={{display:'flex',gap:14,marginTop:7}}>
                <span className="cc-chip" style={{border:'none',background:'none',padding:0,color:'var(--r-low)',fontSize:11}}>allow {Math.round(sim.autoApproved/sim.totalActions*100)}%</span>
                <span className="cc-chip" style={{border:'none',background:'none',padding:0,color:'var(--r-med)',fontSize:11}}>ask {Math.round(sim.asked/sim.totalActions*100)}%</span>
                <span className="cc-chip" style={{border:'none',background:'none',padding:0,color:'var(--r-crit)',fontSize:11}}>deny {Math.round(sim.denied/sim.totalActions*100)}%</span>
              </div>
            </div>

            {/* rule hit list */}
            <div className="cc-sec">rule hit count<span className="rule"/></div>
            <div className="cc-card" style={{padding:'2px 0'}}>
              {ruleHits.map(([name,effect,count,examples],i)=>(
                <div key={i} className="cc-row" style={{cursor:'default'}}>
                  <div className="grow">
                    <div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{name}</div>
                    <div className="s" style={{fontFamily:'var(--mono)',marginTop:2}}>{examples}</div>
                  </div>
                  <EffectChip e={effect}/>
                  <span style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink-2)',marginLeft:12,width:32,textAlign:'right'}}>{count}</span>
                </div>
              ))}
            </div>

            {/* risk distribution */}
            <div className="cc-sec">by risk level<span className="rule"/></div>
            <div className="cc-card" style={{padding:'4px 14px 8px'}}>
              {sim.riskDist.map((r,i)=>(
                <div key={i} style={{padding:'8px 0',display:'flex',alignItems:'center',gap:10}}>
                  <RiskChip level={r.level}/>
                  <div style={{flex:1,display:'flex',gap:4,height:6,borderRadius:3,overflow:'hidden',background:'var(--surface-2)'}}>
                    <div style={{width:Math.round(r.count/sim.totalActions*100)+'%',background:r.level==='low'?'var(--r-low)':r.level==='medium'?'var(--r-med)':r.level==='high'?'var(--r-high)':'var(--r-crit)'}}/>
                  </div>
                  <span style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-3)'}}>{r.count}</span>
                </div>
              ))}
            </div>
          </>}

          <p className="cc-note" style={{margin:'16px 4px 0',textAlign:'center'}}>Re-runs the last N days of audit against your proposed rules. Nothing fires — no agents are contacted.</p>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <div className="cc-btnrow">
          <button className="cc-btn cc-btn--quiet" style={{flex:1}}>Discard</button>
          <button className="cc-btn cc-btn--primary" style={{flex:1.5}}><Ic d={ICON.check} s={15}/>Apply as new policy</button>
        </div>
      </div>
    </div>
  );
}

/* ---------- 4. Doctor / Health Check ---------- */
function DoctorScreen({onBack}){
  const checks=[
    {name:'Daemon version',passed:true,message:'conduitd v1.0.3 (7a9f2e1)'},
    {name:'Agent hooks installed',passed:true,message:'Claude · Codex · opencode'},
    {name:'Agent auth configured',passed:true,message:'ANTHROPIC_API_KEY · OPENAI_API_KEY set'},
    {name:'Policy parseable',passed:true,message:'6 rules · 0 errors'},
    {name:'Filesystem permissions',passed:true,message:'~/.conduit/ readable + writable'},
    {name:'Local model endpoints',passed:false,message:'Ollama (:11434) OK · LM Studio (:1234) unreachable'},
    {name:'Host sleep status',passed:true,message:'awake · plugged in · lid open'},
  ];
  const passedCount=checks.filter(c=>c.passed).length;
  return (
    <div className="cc">
      <SubNav title="health check" onBack={onBack} right={
        <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--r-low)'}}>
          <Ic d={ICON.check} s={13}/> {passedCount}/{checks.length}
        </span>
      }/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 14px'}}>Diagnostic checks for the daemon, agent hooks, auth, policy, and local model endpoints — run from the bridge.</p>

          <div className="cc-card" style={{padding:'2px 0'}}>
            {checks.map((c,i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <span style={{flex:'none',color:c.passed?'var(--r-low)':'var(--r-med)'}}>
                  <Ic d={c.passed?ICON.check:XIC.alert} s={16}/>
                </span>
                <div className="grow" style={{minWidth:0}}>
                  <div style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)'}}>{c.name}</div>
                  <div className="s" style={{marginTop:2}}>{c.message}</div>
                </div>
                <span className="cc-chip" style={{flex:'none',color:c.passed?'var(--r-low)':'var(--r-med)',borderColor:c.passed?'var(--r-low-bd)':'var(--r-med-bd)',background:c.passed?'var(--r-low-bg)':'var(--r-med-bg)',textTransform:'uppercase',fontSize:9.5,fontWeight:600}}>
                  {c.passed?'pass':'warn'}
                </span>
              </div>
            ))}
          </div>

          {/* summary */}
          <div className="cc-card" style={{marginTop:12,padding:'14px 15px',display:'flex',alignItems:'center',gap:12,borderColor:'var(--r-low-bd)',background:'var(--r-low-bg)'}}>
            <span style={{width:36,height:36,borderRadius:2,background:'var(--r-low)',display:'flex',alignItems:'center',justifyContent:'center',color:'#09090c',flex:'none'}}>
              <Ic d={ICON.shield} s={18}/>
            </span>
            <div className="grow">
              <div style={{fontFamily:'var(--mono)',fontSize:13.5,color:'var(--ink)',fontWeight:600}}>{passedCount} of {checks.length} checks passed</div>
              <div className="s" style={{marginTop:2}}>1 warning: LM Studio unreachable</div>
            </div>
            <button className="cc-btn cc-btn--ghost" style={{flex:'none'}}><Ic d={XIC.refresh} s={15}/>Re-run</button>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--quiet cc-btn--block" style={{height:46}}><Ic d={ICON.copy} s={14}/>Copy report</button>
      </div>
    </div>
  );
}

/* ---------- 5. Audit Chain — tamper-evident audit verification + export ---------- */
function AuditChainScreen({onBack}){
  const chainValid=true;
  const entryCount=2847;
  const events=[
    {t:'09:15:22',act:'escalate',vendor:'claude',cmd:'patch session.swift',rule:'ask-on-write'},
    {t:'09:14:08',act:'auto-deny',vendor:'codex',cmd:'curl … | sh',rule:'deny-network'},
    {t:'09:12:44',act:'auto-allow',vendor:'claude',cmd:'ls -la',rule:'allow-read-only'},
    {t:'08:47:13',act:'you-allow',vendor:'claude',cmd:'npm run build',rule:'manual'},
    {t:'02:18:00',act:'auto-allow',vendor:'opencode',cmd:'swift test',rule:'allow-read-only'},
  ];
  return (
    <div className="cc">
      <SubNav title="audit log" onBack={onBack} right={<span className="cc-chip"><Ic d={ICON.clock} s={12}/>{entryCount} entries</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          {/* chain status */}
          <div className="cc-card" style={{padding:'14px 15px',borderColor:'var(--r-low-bd)',background:'var(--r-low-bg)'}}>
            <div style={{display:'flex',alignItems:'center',gap:12}}>
              <span style={{width:36,height:36,borderRadius:2,background:'var(--r-low)',display:'flex',alignItems:'center',justifyContent:'center',color:'#09090c',flex:'none'}}>
                <Ic d={ICON.shield} s={18}/>
              </span>
              <div className="grow">
                <div style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink)',fontWeight:600}}>SHA-256 chain: <span style={{color:'var(--r-low)'}}>valid</span></div>
                <div className="s" style={{marginTop:2}}>{entryCount.toLocaleString()} entries · hash-chain intact · no tampering detected</div>
              </div>
              <span className="cc-sd"><span className="d done"/>verified</span>
            </div>
            <div style={{display:'flex',gap:14,marginTop:12,paddingTop:12,borderTop:'1px solid var(--r-low-bd)'}}>
              <button className="cc-btn cc-btn--ghost" style={{flex:1}}><Ic d={XIC.refresh} s={14}/>Verify chain</button>
              <button className="cc-btn cc-btn--ghost" style={{flex:1}}><Ic d={ICON.copy} s={14}/>Export JSONL</button>
            </div>
          </div>

          {/* recent events */}
          <div className="cc-sec">recent events<span className="rule"/></div>
          <div className="cc-card" style={{padding:'2px 0'}}>
            {events.map((e,i)=>(
              <div key={i} style={{display:'flex',alignItems:'flex-start',gap:11,padding:'10px 14px',position:'relative',cursor:'pointer'}}>
                {i>0 && <span style={{position:'absolute',top:0,left:14,right:0,height:1,background:'var(--line-2)'}}/>}
                <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',paddingTop:2,width:58,flex:'none'}}>{e.t}</span>
                <span style={{flex:'none',fontFamily:'var(--mono)',fontSize:9.5,fontWeight:600,letterSpacing:'.06em',textTransform:'uppercase',
                  color:e.act==='auto-allow'?'var(--r-low)':e.act==='auto-deny'?'var(--r-crit)':e.act==='escalate'?'var(--r-med)':'var(--brand)',
                  background:e.act==='auto-allow'?'var(--r-low-bg)':e.act==='auto-deny'?'var(--r-crit-bg)':e.act==='escalate'?'var(--r-med-bg)':'var(--brand-soft)',
                  border:'1px solid '+(e.act==='auto-allow'?'var(--r-low-bd)':e.act==='auto-deny'?'var(--r-crit-bd)':e.act==='escalate'?'var(--r-med-bd)':'var(--brand)'),
                  borderRadius:3,padding:'2px 6px',width:80,textAlign:'center'}}>{e.act}</span>
                <div style={{flex:1,minWidth:0}}>
                  <div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)',whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}}><span style={{color:VENDOR[e.vendor]?.c||'var(--ink-2)'}}>{e.vendor}</span> · {e.cmd}</div>
                  <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginTop:2}}>rule: {e.rule} · hash: 7a9f…e2d1</div>
                </div>
              </div>
            ))}
          </div>
          <p className="cc-note" style={{margin:'12px 4px 0',textAlign:'center'}}>Every decision is hash-chained to the previous entry. Export the full JSONL for external verification.</p>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 6. Allow Always Scope — scope config sheet overlay ---------- */
function AllowAlwaysScopeSheet(){
  const [scope,setScope]=React.useState('this-command');
  const [timeWindow,setTimeWindow]=React.useState('until-revoke');
  const scopes=[
    ['this-command','This exact command','Match tool + input + path exactly'],
    ['this-command-in-repo','This command in repo','Match command + current repo'],
    ['path-pattern','Path pattern match','Match command + path glob (e.g. src/**/*.swift)'],
    ['all-from-agent','All actions from agent','Match any tool from this agent'],
  ];
  const windows=[
    ['until-revoke','Until revoked'],
    ['24h','24 hours'],
    ['7d','7 days'],
    ['custom','Custom…'],
  ];
  return (
    <div className="cc-sheetwrap">
      <div className="cc-scrim"/>
      <div className="cc-sheet" style={{maxHeight:'90%'}}>
        <div className="grip"/>
        <div className="sheetscroll">
          <h2 className="cc-h2" style={{marginBottom:4}}>Allow always?</h2>
          <div className="cc-note" style={{marginBottom:16}}>Create a standing rule so matching actions auto-allow in the future.</div>

          <div className="cc-sec">scope<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 0'}}>
            {scopes.map(([id,title,desc])=>(
              <div key={id} className="cc-row" onClick={()=>setScope(id)} style={{cursor:'pointer'}}>
                <div className="grow">
                  <div style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)'}}>{title}</div>
                  <div className="s" style={{whiteSpace:'normal',marginTop:1}}>{desc}</div>
                </div>
                <span style={{width:18,height:18,borderRadius:'50%',border:'2px solid '+(scope===id?'var(--brand)':'var(--ink-4)'),display:'flex',alignItems:'center',justifyContent:'center',flex:'none'}}>
                  {scope===id&&<span style={{width:8,height:8,borderRadius:'50%',background:'var(--brand)'}}/>}
                </span>
              </div>
            ))}
          </div>

          {scope==='path-pattern' && <div className="cc-card" style={{marginTop:10,padding:'12px 14px'}}>
            <div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)',marginBottom:6}}>PATH GLOB</div>
            <div style={{display:'flex',alignItems:'center',background:'var(--bg-2)',border:'1px solid var(--line)',borderRadius:'var(--r-md)',height:40,padding:'0 11px',gap:8}}>
              <input placeholder="src/**/*.swift" style={{width:'100%',background:'none',border:'none',color:'var(--ink)',fontFamily:'var(--mono)',fontSize:13,outline:'none'}}/>
            </div>
          </div>}

          {scope==='this-command-in-repo' && <div className="cc-card" style={{marginTop:10,padding:'12px 14px'}}>
            <div style={{display:'flex',alignItems:'center',gap:8}}>
              <Ic d={ICON.git} s={14}/>
              <span style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)'}}>~/repos/conduit</span>
              <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginLeft:'auto'}}>detected from CWD</span>
            </div>
          </div>}

          <div className="cc-sec">time window<span className="rule"/></div>
          <div className="cc-seg">
            {windows.map(([id,label])=>(
              <button key={id} className={timeWindow===id?'on':''} onClick={()=>setTimeWindow(id)} style={id==='custom'?{width:80}:{}}>{label}</button>
            ))}
          </div>
          {timeWindow==='custom' && <div style={{display:'flex',alignItems:'center',gap:8,marginTop:8}}>
            <div style={{display:'flex',alignItems:'center',background:'var(--bg-2)',border:'1px solid var(--line)',borderRadius:'var(--r-md)',height:40,padding:'0 11px',flex:1,gap:6}}>
              <input placeholder="30" style={{width:40,background:'none',border:'none',color:'var(--ink)',fontFamily:'var(--mono)',fontSize:14,outline:'none',textAlign:'center'}}/>
            </div>
            <span className="cc-chip">days</span>
          </div>}

          <div className="cc-card" style={{marginTop:14,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start',borderColor:'var(--r-low-bd)',background:'var(--r-low-bg)'}}>
            <span style={{color:'var(--r-low)',flex:'none',marginTop:1}}><Ic d={ICON.shield} s={16}/></span>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>A rule matching this scope + tool + input + path will be written to policy. Expired rules are skipped at match time.</span>
          </div>
        </div>
        <div className="sheetfoot">
          <div className="cc-btnrow">
            <button className="cc-btn cc-btn--quiet" style={{flex:1}}>Cancel</button>
            <button className="cc-btn cc-btn--primary" style={{flex:1.3}}><Ic d={ICON.check} s={15}/>Write rule</button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ---------- 7. Quota Guard — full per-provider quota dashboard ---------- */
function QuotaGuardScreen({onBack}){
  const providers=[
    {name:'Claude · 5-hour window',pct:62,spent:'$12.40',cap:'$20.00',tone:'#b5352a',alert:'resets 2:40 PM'},
    {name:'Claude · weekly',pct:41,spent:'$20.50',cap:'$50.00',tone:'#c2622c',alert:null},
    {name:'Codex · API credit',pct:46,spent:'$11.60',cap:'$25.00',tone:'#8a5fbf',alert:'$13.40 left'},
    {name:'OpenRouter · balance',pct:78,spent:'$78.00',cap:'$100.00',tone:'#4f63c9',alert:'$22.00 left'},
    {name:'Daily spend cap',pct:20,spent:'$4.94',cap:'$25.00',tone:'#6ac285',alert:null},
  ];
  const alerts=[
    {provider:'Claude 5h',type:'burnRateHigh',threshold:'80%',actual:'62%'},
    {provider:'Daily cap',type:'nearLimit',threshold:'85%',actual:'20%'},
  ];
  const totalSpend='$4.94';
  const burnRate='$0.86/hr';
  return (
    <div className="cc">
      <SubNav title="quota guard" onBack={onBack} right={<span className="cc-chip"><Ic d={ICON.bolt} s={12}/>today {totalSpend}</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          {/* spend overview */}
          <div className="cc-card" style={{padding:'14px 15px'}}>
            <div style={{display:'flex',alignItems:'flex-end',justifyContent:'space-between'}}>
              <div>
                <div style={{fontFamily:'var(--mono)',fontSize:28,fontWeight:700,color:'var(--ink)',lineHeight:1,letterSpacing:'-.02em'}}>{totalSpend}</div>
                <div className="cc-note" style={{marginTop:4}}>spend today · all vendors</div>
              </div>
              <div style={{textAlign:'right'}}>
                <div style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--r-med)'}}>{burnRate}</div>
                <div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)',marginTop:2}}>burn rate</div>
              </div>
            </div>
          </div>

          {/* spend alerts */}
          {alerts.length>0 && <>
            <div className="cc-sec">alerts <span className="n">· {alerts.length}</span><span className="rule"/></div>
            <div className="cc-card" style={{padding:'2px 0'}}>
              {alerts.map((a,i)=>(
                <div key={i} className="cc-row" style={{cursor:'default'}}>
                  <span style={{flex:'none',color:a.type==='nearLimit'?'var(--r-med)':'var(--r-high)'}}>
                    <Ic d={XIC.alert} s={15}/>
                  </span>
                  <div className="grow">
                    <div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{a.provider}</div>
                    <div className="s">threshold {a.threshold} · current {a.actual}</div>
                  </div>
                  <span className="cc-chip" style={{color:'var(--r-med)',borderColor:'var(--r-med-bd)'}}>warn</span>
                </div>
              ))}
            </div>
          </>}

          {/* per-provider bars */}
          <div className="cc-sec">provider quotas<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 14px 10px'}}>
            {providers.map((p,i)=>(
              <div key={i} style={{padding:'10px 0'}}>
                <div style={{display:'flex',alignItems:'baseline',justifyContent:'space-between',marginBottom:6}}>
                  <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{p.name}</span>
                  <div style={{display:'flex',gap:10}}>
                    <span style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink-2)'}}>{p.spent} / {p.cap}</span>
                    <span style={{fontFamily:'var(--mono)',fontSize:11.5,color:p.pct>80?'var(--r-crit)':p.pct>60?'var(--r-med)':'var(--ink-3)'}}>{p.pct}%</span>
                  </div>
                </div>
                <div style={{display:'flex',gap:4,height:6,borderRadius:3,overflow:'hidden',background:'var(--surface-2)'}}>
                  <div style={{width:p.pct+'%',background:p.tone}}/>
                </div>
                {p.alert && <div style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-4)',marginTop:4}}>{p.alert}</div>}
              </div>
            ))}
          </div>

          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.shield} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Quota reads are best-effort from each provider on the host. A usage read never blocks an agent from running.</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--ghost cc-btn--block" style={{height:46}}><Ic d={XIC.sliders||ICON.bell} s={14}/>Configure alert thresholds</button>
      </div>
    </div>
  );
}

/* ---------- 8. Secrets Management — list, add, revoke ---------- */
function SecretsScreen({onBack}){
  const entries=[
    {name:'STRIPE_SECRET_KEY',type:'apiKey',scope:'~/repos/conduit',used:'4× today',critical:true},
    {name:'GITHUB_TOKEN',type:'token',scope:'all repos',used:'12× today',critical:false},
    {name:'DATABASE_URL',type:'password',scope:'~/work/auth',used:'unused this week',critical:false},
  ];
  const pending=[
    {agent:'Codex',secret:'STRIPE_SECRET_KEY',reason:'run a payment test on ~/work/auth'},
  ];
  return (
    <div className="cc">
      <SubNav title="secrets" onBack={onBack} right={<span className="cc-chip"><Ic d={ICON.key} s={12}/>vault</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Credentials stored on the host. Agents request by name — the daemon injects at call time and redacts from output. You authorize every use.</p>

          {/* pending requests */}
          {pending.length>0 && <>
            <div className="cc-sec">pending requests <span className="n">· {pending.length}</span><span className="rule"/></div>
            {pending.map((p,i)=>(
              <div key={i} className="cc-card" style={{padding:'12px 14px',borderColor:'var(--r-crit-bd)',background:'var(--r-crit-bg)',marginBottom:10}}>
                <div style={{display:'flex',alignItems:'center',gap:10,marginBottom:8}}>
                  <span style={{color:'var(--r-crit)'}}><Ic d={ICON.lock} s={18}/></span>
                  <div className="grow">
                    <div style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)',fontWeight:600}}><span style={{color:VENDOR[p.agent?.toLowerCase()]?.c||'var(--ink)'}}>{p.agent}</span> wants {p.secret}</div>
                    <div className="s">{p.reason}</div>
                  </div>
                </div>
                <div className="cc-btnrow">
                  <button className="cc-btn cc-btn--danger" style={{flex:1}}><Ic d={ICON.x} s={14}/>Deny</button>
                  <button className="cc-btn cc-btn--primary" style={{flex:1.3}}><Ic d={ICON.shield} s={15}/>Authorize</button>
                </div>
              </div>
            ))}
          </>}

          {/* stored secrets */}
          <div className="cc-sec">stored secrets <span className="n">· {entries.length}</span><span className="rule"/></div>
          <div className="cc-card" style={{padding:'2px 0'}}>
            {entries.map((e,i)=>(
              <div key={i} className="cc-row" style={{cursor:'pointer'}}>
                <span style={{flex:'none',color:e.critical?'var(--r-crit)':'var(--ink-2)'}}><Ic d={ICON.lock} s={15}/></span>
                <div className="grow" style={{minWidth:0}}>
                  <div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{e.name}</div>
                  <div className="s" style={{marginTop:2}}>{e.scope} · {e.used}</div>
                </div>
                <span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-3)'}}>••••••</span>
                <button className="cc-btn cc-btn--ghost" style={{marginLeft:8,width:34,height:34,padding:0}}><Ic d={ICON.x} s={14}/></button>
              </div>
            ))}
          </div>

          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.lock} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Values stay in the host Keychain — injected at call time and redacted from output. The phone authorizes but never receives the raw secret.</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}}><Ic d={ICON.plus} s={16}/>Add a secret</button>
      </div>
    </div>
  );
}

/* ---------- 9. Host Health — full detail view ---------- */
function HostHealthScreen({onBack}){
  const health={hostname:'dev-vps',status:'healthy',isAsleep:false,isOnBattery:false,lidClosed:false,batteryPercent:null,networkReachable:true,uptime:'14d 6h',daemonVersion:'v1.0.3',apnsTokenFresh:true,hooksInstalled:true,localModelEndpoints:{ollama:true,lmStudio:false}};
  const h=health;
  return (
    <div className="cc">
      <SubNav title={`host health · ${h.hostname}`} onBack={onBack} right={
        <span className="cc-sd"><span className="d done"/>healthy</span>
      }/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          {/* status card */}
          <div className="cc-card" style={{padding:'14px 15px',borderColor:'var(--r-low-bd)',background:'var(--r-low-bg)'}}>
            <div style={{display:'flex',alignItems:'center',gap:11}}>
              <span style={{width:36,height:36,borderRadius:2,background:'var(--r-low)',display:'flex',alignItems:'center',justifyContent:'center',color:'#09090c',flex:'none'}}>
                <Ic d={ICON.shield} s={18}/>
              </span>
              <div className="grow">
                <div style={{fontFamily:'var(--mono)',fontSize:15,color:'var(--ink)',fontWeight:600}}>{h.hostname}</div>
                <div className="s" style={{marginTop:2}}>conduitd {h.daemonVersion} · up {h.uptime}</div>
              </div>
            </div>
          </div>

          {/* host stats */}
          <div className="cc-sec">hardware<span className="rule"/></div>
          <div className="cc-card" style={{padding:'2px 0'}}>
            {[
              ['Power',h.isOnBattery?'Battery · '+h.batteryPercent+'%':'Plugged in',h.isOnBattery?'var(--r-med)':'var(--r-low)'],
              ['Lid',h.lidClosed?'Closed · sleeping':'Open · awake',h.lidClosed?'var(--r-crit)':'var(--r-low)'],
              ['Network',h.networkReachable?'Reachable':'Unreachable',h.networkReachable?'var(--r-low)':'var(--r-crit)'],
              ['APNs token',h.apnsTokenFresh?'Fresh':'Stale',h.apnsTokenFresh?'var(--r-low)':'var(--r-med)'],
              ['Daemon',h.daemonVersion,'var(--ink-2)'],
              ['Hooks',h.hooksInstalled?'Claude · Codex · opencode':'Not installed',h.hooksInstalled?'var(--r-low)':'var(--r-crit)'],
            ].map(([k,v,c],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <div className="grow"><div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{k}</div></div>
                <span style={{fontFamily:'var(--mono)',fontSize:12,color:c}}>{v}</span>
              </div>
            ))}
          </div>

          {/* local model endpoints */}
          <div className="cc-sec">local model endpoints<span className="rule"/></div>
          <div className="cc-card" style={{padding:'2px 0'}}>
            {[
              ['Ollama · localhost:11434',h.localModelEndpoints.ollama],
              ['LM Studio · localhost:1234',h.localModelEndpoints.lmStudio],
            ].map(([endpoint,ok],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <div className="grow"><div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{endpoint}</div></div>
                <span className="cc-chip" style={{color:ok?'var(--r-low)':'var(--r-med)',borderColor:ok?'var(--r-low-bd)':'var(--r-med-bd)',background:ok?'var(--r-low-bg)':'var(--r-med-bg)',fontSize:9.5}}>
                  {ok?'reachable':'unreachable'}
                </span>
              </div>
            ))}
          </div>

          <p className="cc-note" style={{margin:'12px 4px 0'}}>Host health is collected by the daemon and pushed to the phone every 60 seconds. Tap a warning for details.</p>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--ghost cc-btn--block" style={{height:46}}><Ic d={XIC.refresh} s={15}/>Refresh now</button>
      </div>
    </div>
  );
}

/* ---------- 10. E2E Relay Pairing — Settings relay pairing screen ---------- */
function E2ERelayPairingScreen({onBack}){
  const state='connected';
  const code='4 8 2 9 1 7';
  return (
    <div className="cc">
      <SubNav title="relay pairing" onBack={onBack} right={
        <span className="cc-sd"><span className="d done"/>E2E</span>
      }/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 14px'}}>Pair your phone to the daemon's relay. Both dial out — no open ports, no Tailscale, works behind NAT and on cellular.</p>

          <div className="cc-card" style={{padding:'14px 15px',borderColor:'var(--r-low-bd)',background:'var(--r-low-bg)'}}>
            <div style={{display:'flex',alignItems:'center',gap:11}}>
              <span style={{width:36,height:36,borderRadius:2,background:'var(--r-low)',display:'flex',alignItems:'center',justifyContent:'center',color:'#09090c',flex:'none'}}>
                <Ic d={ICON.shield} s={18}/>
              </span>
              <div className="grow">
                <div style={{fontFamily:'var(--mono)',fontSize:15,color:'var(--ink)',fontWeight:600}}>relay: {state}</div>
                <div className="s" style={{marginTop:2}}>duplex · X25519 + ChaCha20-Poly1305</div>
              </div>
            </div>
            <div style={{display:'flex',gap:18,marginTop:12,paddingTop:12,borderTop:'1px solid var(--r-low-bd)'}}>
              <div><div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)'}}>RTT</div><div style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink)',marginTop:3}}>38 ms</div></div>
              <div><div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)'}}>UPTIME</div><div style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink)',marginTop:3}}>4d 02h</div></div>
              <div><div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)'}}>CHANNEL</div><div style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--r-low)',marginTop:3}}>blind</div></div>
            </div>
          </div>

          <div className="cc-sec">relay URL<span className="rule"/></div>
          <div style={{display:'flex',alignItems:'center',background:'var(--bg-2)',border:'1px solid var(--line)',borderRadius:'var(--r-md)',height:40,padding:'0 11px',gap:8,marginBottom:12}}>
            <span style={{fontFamily:'var(--mono)',color:'var(--brand)',fontSize:13}}>wss://</span>
            <input value="relay.conduit.dev" readOnly style={{flex:1,background:'none',border:'none',color:'var(--ink)',fontFamily:'var(--mono)',fontSize:13,outline:'none'}}/>
          </div>

          <div className="cc-sec">pairing code<span className="rule"/></div>
          {state==='connected' ? (
            <div className="cc-card" style={{padding:'14px 15px',display:'flex',alignItems:'center',gap:14}}>
              <div style={{width:72,height:72,background:'var(--bg-2)',border:'1px solid var(--line)',borderRadius:'var(--r-md)',display:'grid',gridTemplateColumns:'repeat(7,1fr)',gridTemplateRows:'repeat(7,1fr)',padding:6,gap:2,flex:'none'}}>
                {Array.from({length:49}).map((_,i)=>(<div key={i} style={{background:(ccHash('qr_pair'+i)%10<4)?'var(--ink-2)':'transparent',borderRadius:1}}/>))}
              </div>
              <div>
                <div style={{fontFamily:'var(--mono)',fontSize:10,letterSpacing:'.18em',color:'var(--ink-4)',marginBottom:5}}>PAIRING CODE</div>
                <div style={{fontFamily:'var(--mono)',fontSize:22,fontWeight:700,letterSpacing:'.14em',color:'var(--r-low)',lineHeight:1}}>{code}</div>
                <div className="cc-note" style={{marginTop:6}}>Show this on the bridge host to pair</div>
              </div>
            </div>
          ) : (
            <div style={{display:'flex',alignItems:'center',background:'var(--bg-2)',border:'1px solid var(--line)',borderRadius:'var(--r-md)',height:40,padding:'0 11px',gap:8}}>
              <input placeholder="000000" maxLength={6} style={{flex:1,background:'none',border:'none',color:'var(--ink)',fontFamily:'var(--mono)',fontSize:16,letterSpacing:'.3em',textAlign:'center',outline:'none'}}/>
            </div>
          )}

          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.lock} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Keys derive at pairing. The relay forwards ciphertext it can't read. If the relay drops, Conduit falls back to SSH automatically.</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        {state==='connected'
          ? <button className="cc-btn cc-btn--ghost cc-btn--block" style={{height:46}}><Ic d={ICON.x} s={14}/>Disconnect relay</button>
          : <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}}><Ic d={RX.relay||ICON.shield} s={16}/>Connect to relay</button>}
      </div>
    </div>
  );
}

/* ---------- 11. Worktree Board — 3-column branch supervision ---------- */
function WorktreeBoardScreen({onBack}){
  const columns=[
    {title:'Active',tone:'var(--brand)',items:[
      {repo:'conduit',branch:'feat/async-session',agent:'claude',files:7,last:'2m ago'},
      {repo:'auth',branch:'fix/oauth-timeout',agent:'codex',files:3,last:'14m ago'},
    ]},
    {title:'Review Ready',tone:'var(--r-low)',items:[
      {repo:'conduit',branch:'feat/proof-card',agent:'claude',files:12,last:'1h ago',commit:'Add ProofCardView'},
    ]},
    {title:'Idle',tone:'var(--ink-4)',items:[
      {repo:'docs',branch:'update-arch',agent:null,files:0,last:'2d ago'},
      {repo:'infra',branch:'upgrade-cache',agent:null,files:0,last:'5d ago'},
    ]},
  ];
  return (
    <div className="cc">
      <SubNav title="worktrees" onBack={onBack} right={<span className="cc-chip"><Ic d={ICON.git} s={12}/>3 repos</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Multi-branch supervision — track which worktrees have active agents, are ready for review, or are idle.</p>

          <div style={{display:'flex',gap:14,overflowX:'auto',paddingBottom:8}}>
            {columns.map(col=>(
              <div key={col.title} style={{flex:'0 0 210px'}}>
                <div style={{display:'flex',alignItems:'center',gap:8,marginBottom:10}}>
                  <span style={{width:8,height:8,borderRadius:'50%',background:col.tone,flex:'none'}}/>
                  <span style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)',fontWeight:500}}>{col.title}</span>
                  <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)',marginLeft:'auto'}}>{col.items.length}</span>
                </div>
                {col.items.map((item,i)=>(
                  <div key={i} className="cc-card" style={{padding:'12px 12px',marginBottom:6,cursor:'pointer'}}>
                    <div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)',fontWeight:500}}>{item.repo}</div>
                    <div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)',marginTop:3}}><Ic d={RX.branch||ICON.git} s={11}/> {item.branch}</div>
                    {item.agent && <div style={{display:'flex',alignItems:'center',gap:6,marginTop:7}}>
                      <PixelAvatar seed={item.agent+item.branch} size={18} color={VENDOR[item.agent]?.c}/>
                      <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:VENDOR[item.agent]?.c||'var(--ink-3)'}}>{VENDOR[item.agent]?.label||item.agent}</span>
                      {item.files>0 && <span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-4)',marginLeft:'auto'}}>+{item.files}</span>}
                    </div>}
                    <div style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-4)',marginTop:6}}>{item.last}</div>
                    {item.commit && <div style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-4)',marginTop:2}}>• {item.commit}</div>}
                  </div>
                ))}
                {col.items.length===0 && <div className="cc-card" style={{padding:'18px 12px',textAlign:'center',color:'var(--ink-4)',fontFamily:'var(--mono)',fontSize:11}}>empty</div>}
              </div>
            ))}
          </div>

          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.git} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Data from <b style={{color:'var(--ink)'}}>git worktree list</b> on each connected host. Branch-per-loop lets you review agent work independently.</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 12. Budget Sheet — set-run-budget overlay ---------- */
function BudgetSheet(){
  const [budget,setBudget]=React.useState('5.00');
  const [preset,setPreset]=React.useState('5');
  const presets=[
    ['1','$1.00','quick check'],
    ['5','$5.00','default'],
    ['10','$10.00','deep work'],
    ['25','$25.00','unlimited-ish'],
  ];
  return (
    <div className="cc-sheetwrap">
      <div className="cc-scrim"/>
      <div className="cc-sheet" style={{maxHeight:'70%'}}>
        <div className="grip"/>
        <div className="sheetscroll" style={{padding:'0 18px'}}>
          <h2 className="cc-h2" style={{marginBottom:4}}>Set budget</h2>
          <div className="cc-note" style={{marginBottom:14}}>Cap this run's spend. The bridge pauses it if the limit is hit.</div>

          <div className="cc-sec">quick pick<span className="rule"/></div>
          <div style={{display:'flex',gap:8,marginBottom:14}}>
            {presets.map(([id,label,desc])=>(
              <button key={id} className="cc-btn cc-btn--ghost" style={{flex:1,flexDirection:'column',gap:3,height:'auto',padding:'10px 6px',
                borderColor:preset===id?'var(--brand)':'var(--line)',background:preset===id?'var(--brand-soft)':'var(--surface)'}}
                onClick={()=>{setPreset(id);setBudget(id);}}>
                <span style={{fontFamily:'var(--mono)',fontSize:15,fontWeight:600,color:preset===id?'var(--brand)':'var(--ink)'}}>{label}</span>
                <span style={{fontFamily:'var(--mono)',fontSize:9,color:'var(--ink-4)'}}>{desc}</span>
              </button>
            ))}
          </div>

          <div className="cc-sec">custom<span className="rule"/></div>
          <div style={{display:'flex',alignItems:'center',background:'var(--bg-2)',border:'1px solid var(--line)',borderRadius:'var(--r-md)',height:44,padding:'0 13px',gap:8,marginBottom:4}}>
            <span style={{fontFamily:'var(--mono)',color:'var(--brand)',fontSize:15}}>$</span>
            <input value={budget} onChange={e=>{setBudget(e.target.value);setPreset(null);}}
              style={{flex:1,background:'none',border:'none',color:'var(--ink)',fontFamily:'var(--mono)',fontSize:16,fontWeight:600,outline:'none'}}
              placeholder="5.00"/>
          </div>
          <p className="cc-note" style={{margin:'4px 0 0'}}>The run is paused when spend crosses this cap. You can change it mid-run.</p>
        </div>
        <div className="sheetfoot">
          <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}}><Ic d={ICON.check} s={15}/>Set ${budget} budget</button>
        </div>
      </div>
    </div>
  );
}

/* ---------- 13. Nudge Screen — mid-run instruction injection ---------- */
function NudgeScreen({onBack}){
  const [text,setText]=React.useState('');
  const out=[
    ['$ refactor the session store','c'],
    ['Editing SessionViewModel.swift…','o'],
    ['Extracting BlockRenderer protocol','o'],
    ['› you: keep the old API as a shim','n'],
    ['Acknowledged — adding deprecation shim','w'],
  ];
  return (
    <div className="cc">
      <SubNav title="nudge" onBack={onBack} right={<span className="cc-sd"><span className="d working"/>working</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div className="cc-card" style={{padding:'12px 14px',display:'flex',alignItems:'center',gap:10}}>
            <PixelAvatar seed="claudeconduit" size={34} color={VENDOR.claude.c}/>
            <div className="grow" style={{minWidth:0}}><div style={{fontFamily:'var(--mono)',fontSize:13.5,color:'var(--ink)'}}>Claude Code · conduit</div><div className="s">Dev VPS · mid-run · $3.18 / $5.00</div></div>
          </div>

          <div className="cc-sec">live output<span className="n">· tail</span><span className="rule"/></div>
          <div className="cc-cmd" style={{display:'block',padding:0}}>
            <div className="body" style={{whiteSpace:'pre-wrap',padding:'11px 13px',fontSize:11.5,lineHeight:1.75}}>
              {out.map(([t,k],i)=>(
                <div key={i} style={{color:k==='c'?'var(--ink)':k==='n'?'var(--brand)':k==='w'?'var(--r-med)':'var(--ink-3)'}}>{t}{k==='w'&&<span className="cursor" style={{height:'.8em'}}/>}</div>
              ))}
            </div>
          </div>
          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.term} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>A nudge is injected at the agent's next safe checkpoint. It steers the run without stopping it — the agent acknowledges in the transcript.</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <div style={{display:'flex',alignItems:'center',background:'var(--bg-2)',border:'1px solid var(--line)',borderRadius:'var(--r-md)',height:46,padding:'0 13px',gap:9,marginBottom:10}}>
          <span style={{fontFamily:'var(--mono)',color:'var(--brand)',fontSize:14,flex:'none'}}>›</span>
          <input value={text} onChange={e=>setText(e.target.value)} placeholder="add a one-line instruction…"
            style={{flex:1,background:'none',border:'none',color:'var(--ink)',fontFamily:'var(--mono)',fontSize:12.5,outline:'none'}}/>
        </div>
        <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}} disabled={!text.trim()}>
          <Ic d={ICON.term} s={16}/>Send nudge
        </button>
      </div>
    </div>
  );
}

/* ---------- 14. Switch Model/Account Mid-Run ---------- */
function SwitchRunModelScreen({onBack}){
  const [model,setModel]=React.useState('sonnet');
  const [acct,setAcct]=React.useState('personal');
  return (
    <div className="cc">
      <SubNav title="switch · mid-run" onBack={onBack} right={<span className="cc-chip" style={{fontSize:9.5}}>SOON</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Repoint a working run to another model or account. The bridge swaps on the next call — the run continues.</p>

          <div className="cc-sec">model<span className="rule"/></div>
          <div className="cc-seg" style={{marginBottom:14}}>
            {['sonnet-4.6','opus-4.6','local'].map(m=>(
              <button key={m} className={model===m?'on':''} onClick={()=>setModel(m)}>{m}</button>
            ))}
          </div>

          <div className="cc-sec">account<span className="rule"/></div>
          <div className="cc-card">
            {[['personal','me@personal.dev','Max · 41% left'],['team','team@acme.io','Pro · 88% left']].map(([id,email,quota],i)=>(
              <div key={i} className="cc-row" onClick={()=>setAcct(id)} style={{cursor:'pointer'}}>
                <PixelAvatar seed={'claude'+email} size={30} color={VENDOR.claude.c}/>
                <div className="grow" style={{minWidth:0}}><div className="t" style={{fontSize:14}}>{email}</div><div className="s">{quota}</div></div>
                <span style={{width:20,height:20,borderRadius:'50%',border:'2px solid '+(acct===id?'var(--brand)':'var(--ink-4)'),display:'flex',alignItems:'center',justifyContent:'center',flex:'none'}}>
                  {acct===id&&<span style={{width:9,height:9,borderRadius:'50%',background:'var(--brand)'}}/>}
                </span>
              </div>
            ))}
          </div>

          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start',borderColor:'var(--r-med-bd)',background:'var(--r-med-bg)'}}>
            <span style={{color:'var(--r-med)',flex:'none',marginTop:1}}><Ic d={ICON.bolt} s={16}/></span>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Switching to <b style={{color:'var(--ink)'}}>opus-4.6</b> raises cost ≈ 5×. The run's budget cap still applies and pauses it if exceeded.</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <div className="cc-btnrow">
          <button className="cc-btn cc-btn--quiet" style={{flex:1}}><Ic d={ICON.x} s={14}/>Cancel</button>
          <button className="cc-btn cc-btn--primary" style={{flex:1.4}}><Ic d={RX.swap||ICON.shield} s={15}/>Switch &amp; resume</button>
        </div>
      </div>
    </div>
  );
}

/* ---------- 15. CI/PR Event Feed ---------- */
function CIEventFeedScreen({onBack}){
  const events=[
    {label:'opened PR #218',sub:'block terminal · live agents',c:'var(--r-low)',t:'5m',type:'pr'},
    {label:'CI green on #218',sub:'42 tests · 3m12s',c:'var(--r-low)',t:'1m',type:'ci'},
    {label:'CI failed on #215',sub:'SessionViewModelTests',c:'var(--r-crit)',t:'12m',type:'ci'},
    {label:'pushed feat/block-renderer',sub:'4 commits · dev-vps',c:'var(--brand)',t:'2m',type:'push'},
    {label:'branch fix/tofu-prompt',sub:'created from master',c:'var(--ink-3)',t:'1h',type:'branch'},
  ];
  return (
    <div className="cc">
      <SubNav title="ci / events" onBack={onBack} right={<span className="cc-chip"><Ic d={ICON.git} s={12}/>2 repos</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Git and CI events from your watched repos. Tap a failing check to open the run or dispatch a fix.</p>
          <div className="cc-card" style={{padding:'2px 0'}}>
            {events.map((e,i)=>(
              <div key={i} style={{display:'flex',alignItems:'flex-start',gap:11,padding:'12px 14px',position:'relative',cursor:'pointer'}}>
                {i>0 && <span style={{position:'absolute',top:0,left:14,right:0,height:1,background:'var(--line-2)'}}/>}
                <span style={{flex:'none',marginTop:1,color:e.c}}>
                  <Ic d={e.type==='pr'?ICON.git:e.type==='ci'?(e.c==='var(--r-crit)'?ICON.x:ICON.check):ICON.folder} s={15}/>
                </span>
                <div style={{flex:1,minWidth:0}}>
                  <div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{e.label}</div>
                  <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginTop:3}}>{e.sub}</div>
                </div>
                <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',flex:'none',paddingTop:1}}>{e.t}</span>
              </div>
            ))}
          </div>
          <p className="cc-note" style={{margin:'12px 4px 0',textAlign:'center'}}>Events stream from the host's git + CI hooks via the daemon.</p>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--ghost cc-btn--block" style={{height:46}}><Ic d={ICON.plus} s={15}/>Watch a repo</button>
      </div>
    </div>
  );
}

/* ---------- 16. Run Detail — two-way control surface ---------- */
function RunDetailScreen({onBack}){
  const running=true;
  return (
    <div className="cc">
      <SubNav title="run" onBack={onBack} right={<span className="cc-sd"><span className="d working"/>working</span>}/>
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
            <div style={{display:'flex',gap:4,marginTop:12,height:5,borderRadius:3,overflow:'hidden',background:'var(--surface-2)'}}>
              <div style={{width:'64%',background:'var(--brand)'}}/>
            </div>
          </div>

          <div className="cc-sec">controls<span className="rule"/></div>
          <div className="cc-btnrow" style={{gap:8}}>
            <button className="cc-btn cc-btn--quiet" style={{flex:1,flexDirection:'column',gap:5,height:'auto',padding:'12px 4px',color:'var(--r-crit)',borderColor:'var(--r-crit-bd)'}}>
              <Ic d={XIC.stop} s={17}/><span style={{fontSize:11}}>Stop</span>
            </button>
            <button className="cc-btn cc-btn--quiet" style={{flex:1,flexDirection:'column',gap:5,height:'auto',padding:'12px 4px',color:'var(--ink-2)',borderColor:'var(--line)'}}>
              <Ic d={XIC.pause} s={17}/><span style={{fontSize:11}}>Pause</span>
            </button>
            <button className="cc-btn cc-btn--quiet" style={{flex:1,flexDirection:'column',gap:5,height:'auto',padding:'12px 4px',color:'var(--ink-2)',borderColor:'var(--line)'}}>
              <Ic d={XIC.gauge} s={17}/><span style={{fontSize:11}}>Budget</span>
            </button>
          </div>
          <p className="cc-note" style={{margin:'12px 4px 0'}}><b style={{color:'var(--ink-2)'}}>Stop · pause/resume · set-budget</b> — two-way run control. The bridge applies changes at the next safe checkpoint.</p>

          <div className="cc-sec">live output<span className="n">· tail</span><span className="rule"/></div>
          <div className="cc-cmd" style={{display:'block',padding:0}}>
            <div className="body" style={{whiteSpace:'pre-wrap',padding:'11px 13px',fontSize:11.5,lineHeight:1.75}}>
              <div style={{color:'var(--ink)'}}>$ swift build</div>
              <div style={{color:'var(--ink-3)'}}>Compiling ConduitKit (38 files)</div>
              <div style={{color:'var(--ink-3)'}}>[142/318] Compiling SessionViewModel.swift</div>
              <div style={{color:'var(--ink-2)'}}>patch src/auth/session.swift</div>
              <div style={{color:'var(--r-med)'}}>● thinking<span className="cursor" style={{height:'.8em'}}/></div>
            </div>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- Export all screens ---------- */
Object.assign(window,{
  ProofCardScreen, LoopDetailScreen, PolicySimulatorScreen, DoctorScreen,
  AuditChainScreen, AllowAlwaysScopeSheet, QuotaGuardScreen,
  SecretsScreen, HostHealthScreen, E2ERelayPairingScreen,
  WorktreeBoardScreen, BudgetSheet, NudgeScreen,
  SwitchRunModelScreen, CIEventFeedScreen, RunDetailScreen,
});
