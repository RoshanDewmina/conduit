/* ============================================================
   LANCER — Agent/Cloud, Git, Files/Browser screens
   ============================================================ */

/* ---------- shared local atoms (mirror cc-screens-3 patterns, not exported from there) ---------- */
const XIC = {
  stop:<rect x="7" y="7" width="10" height="10" rx="1"/>,
  refresh:<><path d="M21 12a9 9 0 1 1-3-6.7"/><path d="M21 4v5h-5"/></>,
  gauge:<><path d="M12 13l4-4"/><path d="M3.5 16a8.5 8.5 0 1 1 17 0"/></>,
  sliders:<><path d="M4 7h9M17 7h3M4 12h3M11 12h9M4 17h7M15 17h5"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="13" cy="17" r="2"/></>,
  pause:<><rect x="7" y="6" width="3.5" height="12" rx="1"/><rect x="13.5" y="6" width="3.5" height="12" rx="1"/></>,
  nudge:<><path d="M12 3v9"/><path d="M8 7l4-4 4 4"/><circle cx="12" cy="17" r="1.4"/></>,
};
function CtrlBtn({icon, label, soon, danger}){
  return <button className="cc-btn cc-btn--quiet" style={{flex:1,flexDirection:'column',gap:5,height:'auto',padding:'12px 4px',position:'relative',color:danger?'var(--r-crit)':'var(--ink-2)',borderColor:danger?'var(--r-crit-bd)':'var(--line)'}}>
    <Ic d={icon} s={17}/>
    <span style={{fontSize:11}}>{label}</span>
    {soon && <span style={{position:'absolute',top:5,right:5,fontFamily:'var(--mono)',fontSize:8,letterSpacing:'.06em',color:'var(--ink-4)',border:'1px solid var(--line)',borderRadius:2,padding:'1px 3px'}}>SOON</span>}
  </button>;
}
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
/* ---------- 1 · AgentsView — hosted agent management list ---------- */
function AgentsView({onCreate, onSelect}){
  const agents=[
    {id:'g1',vendor:'claude',name:'lancer',model:'claude-sonnet-4.6',spend:'$3.18',last:'2m ago',status:'working'},
    {id:'g2',vendor:'codex',name:'auth-svc',model:'gpt-5.1-codex',spend:'$0.74',last:'12m ago',status:'waiting'},
    {id:'g3',vendor:'claude',name:'staging-bot',model:'claude-sonnet-4.6',spend:'$1.02',last:'47m ago',status:'idle'},
    {id:'g4',vendor:'opencode',name:'pi-runner',model:'—',spend:'—',last:'2d ago',status:'offline'},
  ];
  return (
    <div className="cc">
      <SubNav title="cloud agents" right={<span className="cc-chip"><Ic d={ICON.bolt} s={12}/>Pro</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Hosted agents run on Lancer's infra — always online, always connected.</p>
          <button className="cc-btn cc-btn--primary cc-btn--block" style={{marginBottom:14}} onClick={onCreate}><Ic d={ICON.plus} s={15}/>Create agent</button>
          <div className="cc-sec">agents <span className="n">· {agents.length}</span><span className="rule"/></div>
          <div className="cc-card">
            {agents.map(a=>{
              const v=VENDOR[a.vendor]||VENDOR.claude;
              return (
                <div key={a.id} className="cc-row" onClick={()=>onSelect&&onSelect(a)}>
                  <PixelAvatar seed={a.vendor+a.name} size={34} color={v.c}/>
                  <div className="grow" style={{minWidth:0}}>
                    <div className="t" style={{fontSize:13.5}}>{v.label} <span style={{color:'var(--ink-4)',fontWeight:400,fontSize:12}}>{a.name}</span></div>
                    <div className="s" style={{marginTop:3}}>{a.model}</div>
                  </div>
                  <div style={{flex:'none',textAlign:'right'}}>
                    <span className="cc-sd"><span className={'d '+a.status}/>{a.status}</span>
                    <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginTop:3}}>{a.spend} · {a.last}</div>
                  </div>
                  <Ic d={ICON.chev} s={15} className="chev"/>
                </div>
              );
            })}
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 2 · AgentDetailView — single agent detail + run history ---------- */
function AgentDetailView({agent, onBack, onRun, onPause, onDelete}){
  const a=agent||{vendor:'claude',name:'lancer',model:'claude-sonnet-4.6',status:'working',spend:'$3.18',totalSpend:'$142.50'};
  const runs=[
    {goal:'fix login timeout',status:'done',dur:'4.2m',cost:'$0.84'},
    {goal:'refactor auth middleware',status:'working',dur:'2.1m',cost:'$0.42'},
    {goal:'update CI pipeline',status:'done',dur:'1.8m',cost:'$0.36'},
    {goal:'deploy staging',status:'failed',dur:'—',cost:'$0.12'},
  ];
  const v=VENDOR[a.vendor]||VENDOR.claude;
  return (
    <div className="cc">
      <SubNav title={v.label+' · '+a.name} onBack={onBack} right={<span className="cc-sd"><span className={'d '+a.status}/>{a.status}</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div className="cc-card" style={{padding:'14px 16px'}}>
            <div style={{display:'flex',alignItems:'center',gap:12}}>
              <PixelAvatar seed={a.vendor+a.name} size={42} color={v.c}/>
              <div className="grow">
                <div style={{fontFamily:'var(--mono)',fontSize:16,color:'var(--ink)',fontWeight:600}}>{v.label}</div>
                <div style={{display:'flex',gap:10,alignItems:'center',marginTop:4}}>
                  <span style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-3)'}}>{a.model}</span>
                  <span className="cc-chip" style={{background:'none',padding:'1px 6px',fontSize:10}}>{a.name}</span>
                </div>
              </div>
              <div style={{textAlign:'right'}}>
                <div style={{fontFamily:'var(--mono)',fontSize:20,fontWeight:700,color:'var(--ink)',letterSpacing:'-.02em'}}>{a.spend}</div>
                <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginTop:2}}>{a.totalSpend} total</div>
              </div>
            </div>
          </div>

          <div className="cc-sec">controls<span className="rule"/></div>
          <div className="cc-btnrow" style={{gap:8}}>
            <CtrlBtn icon={a.status==='working'?XIC.pause:ICON.bolt} label={a.status==='working'?'Pause':'Resume'}/>
            <CtrlBtn icon={XIC.sliders} label="Schedule"/>
            <CtrlBtn icon={ICON.x} label="Delete" danger/>
          </div>

          <div className="cc-sec">recent runs<span className="n">· {runs.length}</span><span className="rule"/></div>
          <div className="cc-card">
            {runs.map((r,i)=>(
              <div key={i} className="cc-row" onClick={()=>onRun&&onRun(r)}>
                <span style={{width:8,height:8,borderRadius:'50%',flex:'none',background:r.status==='done'?'var(--ok)':r.status==='working'?'var(--brand)':'var(--r-crit)'}}/>
                <div className="grow" style={{minWidth:0}}>
                  <div className="t" style={{fontSize:13}}>{r.goal}</div>
                </div>
                <div style={{flex:'none',textAlign:'right'}}>
                  <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>{r.dur}</span>
                  <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginTop:2}}>{r.cost}</div>
                </div>
                <Ic d={ICON.chev} s={15} className="chev"/>
              </div>
            ))}
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 3 · AgentRunDetailView — run detail with ship/diff ---------- */
function AgentRunDetailView({onBack}){
  const out=[
    ['$ claude fix login timeout','c'],
    ['Analyzing auth session module…','o'],
    ['patch src/auth/session.swift','o'],
    ['[142/318] Compiling SessionViewModel.swift','o'],
    ['Tests passed · 12s','o'],
    ['✓ exit 0','c'],
  ];
  return (
    <div className="cc">
      <SubNav title="run detail" onBack={onBack} right={<span className="cc-sd"><span className="d done"/>complete</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div className="cc-card" style={{padding:'14px 15px'}}>
            <div style={{display:'flex',alignItems:'center',gap:10}}>
              <PixelAvatar seed="claudelancer" size={38} color={VENDOR.claude.c}/>
              <div className="grow">
                <div style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink)',fontWeight:500}}>Claude Code</div>
                <div className="s" style={{marginTop:3}}>lancer · claude-sonnet-4.6</div>
              </div>
              <div style={{textAlign:'right'}}>
                <div style={{fontFamily:'var(--mono)',fontSize:15,color:'var(--ink)'}}>$0.84</div>
                <div className="cc-note" style={{marginTop:2}}>4.2m</div>
              </div>
            </div>
          </div>

          <div className="cc-sec">output<span className="n">· complete</span><span className="rule"/></div>
          <div className="cc-cmd" style={{display:'block',padding:0}}>
            <div className="body" style={{whiteSpace:'pre-wrap',padding:'11px 13px',fontSize:11.5,lineHeight:1.75}}>
              {out.map(([t,k],i)=>(
                <div key={i} style={{color:k==='c'?'var(--ink)':'var(--ink-3)'}}>{t}</div>
              ))}
            </div>
          </div>

          <div className="cc-sec">actions<span className="rule"/></div>
          <div className="cc-btnrow" style={{gap:8}}>
            <button className="cc-btn cc-btn--primary" style={{flex:1.5}}><Ic d={ICON.git} s={15}/>Ship</button>
            <button className="cc-btn cc-btn--ghost" style={{flex:1}}><Ic d={ICON.book} s={14}/>Diff</button>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 4 · AgentFilesView — agent workspace files browser ---------- */
function AgentFilesView({onBack, onFile}){
  const files=[
    {name:'src',type:'dir',size:'—',modified:'2m ago'},
    {name:'Sources',type:'dir',size:'—',modified:'5m ago'},
    {name:'Package.swift',type:'file',size:'2.4 KB',modified:'12m ago'},
    {name:'Tests',type:'dir',size:'—',modified:'1h ago'},
    {name:'README.md',type:'file',size:'1.1 KB',modified:'2h ago'},
    {name:'.gitignore',type:'file',size:'45 B',modified:'1d ago'},
  ];
  return (
    <div className="cc">
      <SubNav title="workspace files" onBack={onBack} right={<span className="cc-chip"><Ic d={ICON.folder} s={12}/>~/repos/lancer</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Browse the agent's workspace directory — read-only view of files on the host.</p>
          <div className="cc-card">
            {files.map((f,i)=>(
              <div key={i} className="cc-row" onClick={()=>f.type==='file'&&onFile&&onFile(f)} style={{cursor:f.type==='dir'?'default':'pointer'}}>
                <span style={{color:f.type==='dir'?'var(--brand)':'var(--ink-3)',flex:'none'}}>
                  {f.type==='dir'?<Ic d={ICON.folder} s={17}/>:<Ic d={ICON.file} s={17}/>}
                </span>
                <div className="grow" style={{minWidth:0}}>
                  <div className="t" style={{fontFamily:'var(--mono)',fontSize:13}}>{f.name}</div>
                </div>
                <div style={{flex:'none',textAlign:'right'}}>
                  <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>{f.size}</span>
                  <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginTop:2}}>{f.modified}</div>
                </div>
                {f.type==='file'&&<Ic d={ICON.chev} s={15} className="chev"/>}
              </div>
            ))}
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 5 · AgentWorkspaceView — agent workspace/repo view ---------- */
function AgentWorkspaceView({onBack}){
  return (
    <div className="cc">
      <SubNav title="workspace" onBack={onBack} right={<span className="cc-chip"><Ic d={ICON.git} s={12}/>lancer</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div className="cc-card" style={{padding:'14px 16px'}}>
            <div style={{display:'flex',alignItems:'center',gap:10}}>
              <span style={{width:36,height:36,borderRadius:8,background:'var(--surface-2)',border:'1px solid var(--line)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--ink-2)'}}><Ic d={ICON.git} s={18}/></span>
              <div className="grow">
                <div style={{fontFamily:'var(--mono)',fontSize:14,fontWeight:600,color:'var(--ink)'}}>lancer</div>
                <div className="s" style={{marginTop:3}}>main · 2.4k commits</div>
              </div>
              <span className="cc-sd"><span className="d done"/>clean</span>
            </div>
            <div style={{marginTop:12,paddingTop:12,borderTop:'1px solid var(--line-2)'}}>
              <div style={{display:'flex',alignItems:'center',gap:10}}>
                <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>current branch</span>
                <span style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--brand)',fontWeight:600}}>main</span>
                <span style={{marginLeft:'auto',fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)'}}>a8f3b2e</span>
              </div>
            </div>
          </div>

          <div className="cc-sec">recent commits<span className="rule"/></div>
          <div className="cc-card">
            {[['fix login timeout','2m ago','a8f3b2e'],['refactor auth middleware','15m ago','c7e91d4'],['update CI pipeline','1h ago','b2f4a81']].map(([msg,time,hash],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',width:70,flex:'none'}}>{hash}</span>
                <div className="grow"><div className="t" style={{fontSize:13}}>{msg}</div></div>
                <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>{time}</span>
              </div>
            ))}
          </div>

          <div className="cc-sec">CI<span className="rule"/></div>
          <div className="cc-card" style={{padding:'12px 14px',display:'flex',alignItems:'center',gap:10}}>
            <span style={{color:'var(--ok)'}}><Ic d={ICON.check} s={16}/></span>
            <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink-2)'}}>Last build: <b style={{color:'var(--ok)'}}>passed</b> · 2m ago</span>
            <span className="cc-chip" style={{marginLeft:'auto'}}>GitHub Actions</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 6 · AgentOrgView — org members management ---------- */
function AgentOrgView({onBack}){
  const members=[
    {name:'alice',role:'admin',status:'active',last:'now',seed:'alice'},
    {name:'bob',role:'member',status:'active',last:'5m ago',seed:'bob'},
    {name:'carol',role:'member',status:'active',last:'1h ago',seed:'carol'},
    {name:'dave',role:'member',status:'pending',last:'—',seed:'dave'},
  ];
  return (
    <div className="cc">
      <SubNav title="team" onBack={onBack} right={<span className="cc-chip"><Ic d={ICON.bolt} s={12}/>Pro</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Manage who can create agents, set policy, and view runs in your org.</p>
          <button className="cc-btn cc-btn--primary cc-btn--block" style={{marginBottom:14}}><Ic d={ICON.plus} s={15}/>Invite member</button>
          <div className="cc-sec">members <span className="n">· {members.length}</span><span className="rule"/></div>
          <div className="cc-card">
            {members.map((m,i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <PixelAvatar seed={m.seed} size={32} color={m.role==='admin'?'var(--brand)':undefined}/>
                <div className="grow" style={{minWidth:0}}>
                  <div className="t" style={{fontFamily:'var(--mono)',fontSize:13}}>{m.name}</div>
                  <div className="s" style={{marginTop:3}}>{m.role}</div>
                </div>
                <div style={{flex:'none',textAlign:'right'}}>
                  {m.status==='active'
                    ? <span className="cc-sd"><span className="d done"/>active</span>
                    : <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--r-med)',border:'1px solid var(--r-med-bd)',background:'var(--r-med-bg)',borderRadius:2,padding:'2px 7px'}}>pending</span>}
                  <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginTop:3}}>{m.last}</div>
                </div>
              </div>
            ))}
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 7 · AgentExecView — agent execution detail ---------- */
function AgentExecView({onBack}){
  return (
    <div className="cc">
      <SubNav title="execution" onBack={onBack} right={<span className="cc-sd"><span className="d done"/>complete</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div className="cc-sec">command<span className="rule"/></div>
          <div className="cc-cmd" style={{display:'block',padding:0}}>
            <div className="body" style={{padding:'11px 13px',fontSize:12,lineHeight:1.7}}>
              <div><span style={{color:'var(--ink-4)'}}>$ </span><span style={{color:'var(--ink)'}}>claude</span> fix login timeout</div>
            </div>
          </div>

          <div className="cc-sec">arguments<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 0'}}>
            {[['--model','claude-sonnet-4.6'],['--budget','$5.00'],['--timeout','30m']].map(([k,v],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default',padding:'10px 16px'}}>
                <span style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-4)',width:90,flex:'none'}}>{k}</span>
                <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{v}</span>
              </div>
            ))}
          </div>

          <div className="cc-sec">working directory<span className="rule"/></div>
          <div className="cc-card" style={{padding:'11px 14px'}}>
            <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink-2)'}}>~/repos/lancer</span>
          </div>

          <div className="cc-sec">environment<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 0'}}>
            {[['LANCER_HOST','dev-vps'],['ANTHROPIC_API_KEY','sk-…M2'],['PATH','/usr/bin:/usr/local/bin']].map(([k,v],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default',padding:'10px 16px'}}>
                <span style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-4)',width:170,flex:'none'}}>{k}</span>
                <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink-2)'}}>{v}</span>
              </div>
            ))}
          </div>

          <div className="cc-sec">output<span className="rule"/></div>
          <div className="cc-cmd" style={{display:'block',padding:0}}>
            <div className="body" style={{whiteSpace:'pre-wrap',padding:'11px 13px',fontSize:11.5,lineHeight:1.75,color:'var(--ink-3)'}}>
              <div style={{color:'var(--ink)'}}><span style={{color:'var(--brand)'}}>$ </span>claude fix login timeout</div>
              <div>Analyzing SessionViewModel.swift…</div>
              <div>Found timeout in connectToServer()</div>
              <div>Applied patch · tests pass</div>
              <div style={{color:'var(--ok)',marginTop:6}}>✓ exit 0 · 4.2m</div>
            </div>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 8 · CreateAgentSheet — create new hosted agent ---------- */
function CreateAgentSheet({onClose, onCreate}){
  const [name,setName]=React.useState('');
  const [runtime,setRuntime]=React.useState('claude');
  const [model,setModel]=React.useState('claude-sonnet-4.6');
  const [budget,setBudget]=React.useState('5.00');
  return (
    <div className="cc-sheetwrap">
      <div className="cc-scrim"/>
      <div className="cc-sheet">
        <div className="grip"/>
        <div className="sheetscroll">
          <h2 className="cc-h2" style={{marginBottom:6}}>Create cloud agent</h2>
          <div className="cc-note" style={{marginBottom:16}}>A hosted agent runs on Lancer's infrastructure — always online.</div>

          <div className="cc-sec">agent name<span className="rule"/></div>
          <CCInput value={name} onChange={setName} placeholder="my-agent" mono/>

          <div className="cc-sec">runtime<span className="rule"/></div>
          <div className="cc-seg">
            {['claude','codex','opencode'].map(r=>(<button key={r} className={runtime===r?'on':''} onClick={()=>setRuntime(r)}>{r}</button>))}
          </div>

          <div className="cc-sec">model<span className="rule"/></div>
          <div className="cc-card" style={{padding:'2px 0'}}>
            {[['claude-sonnet-4.6','Best overall'],['gpt-5.1-codex','Fast & cheap'],['opencode-v4','Open source']].map(([m,d],i)=>(
              <div key={i} className="cc-row" onClick={()=>setModel(m)}>
                <span style={{width:18,height:18,borderRadius:'50%',border:'2px solid '+(model===m?'var(--brand)':'var(--ink-4)'),display:'flex',alignItems:'center',justifyContent:'center',flex:'none'}}>{model===m&&<span style={{width:8,height:8,borderRadius:'50%',background:'var(--brand)'}}/>}</span>
                <div className="grow">
                  <div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{m}</div>
                  <div className="s">{d}</div>
                </div>
              </div>
            ))}
          </div>

          <div className="cc-sec">daily budget cap<span className="rule"/></div>
          <CCInput value={'$'+budget} onChange={v=>setBudget(v.replace('$',''))} mono prefix="$"/>

          <div className="cc-sec">host &amp; policy<span className="rule"/></div>
          <div className="cc-card" style={{padding:'11px 14px',display:'flex',alignItems:'center',gap:10,cursor:'pointer'}}>
            <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink-2)'}}>Lancer Cloud · default policy</span>
            <span style={{marginLeft:'auto'}}><Ic d={ICON.chev} s={15} className="chev"/></span>
          </div>
        </div>
        <div className="sheetfoot">
          <div className="cc-btnrow">
            <button className="cc-btn cc-btn--quiet" style={{flex:1}} onClick={onClose}>Cancel</button>
            <button className="cc-btn cc-btn--primary" style={{flex:1.4}} onClick={onCreate} disabled={!name}><Ic d={ICON.bolt} s={15}/>Create agent</button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ---------- 9 · AgentBillingSheet — agent billing/credits ---------- */
function AgentBillingSheet({onClose}){
  return (
    <div className="cc-sheetwrap">
      <div className="cc-scrim"/>
      <div className="cc-sheet">
        <div className="grip"/>
        <div className="sheetscroll">
          <h2 className="cc-h2" style={{marginBottom:6}}>Credits &amp; billing</h2>
          <div className="cc-note" style={{marginBottom:16}}>Prepaid credits power your cloud agents. Unused credits roll over.</div>

          <div className="cc-card" style={{padding:'16px 16px 14px',marginBottom:12}}>
            <div style={{display:'flex',alignItems:'flex-end',justifyContent:'space-between'}}>
              <div>
                <div style={{fontFamily:'var(--mono)',fontSize:34,fontWeight:700,color:'var(--ink)',lineHeight:1,letterSpacing:'-.02em'}}>$47.50</div>
                <div className="cc-note" style={{marginTop:5}}>credits remaining</div>
              </div>
              <div style={{textAlign:'right'}}>
                <div style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink-2)'}}>$50.00 bought</div>
                <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginTop:2}}>rolls over monthly</div>
              </div>
            </div>
            <div style={{display:'flex',gap:4,marginTop:14,height:6,borderRadius:3,overflow:'hidden',background:'var(--surface-2)'}}>
              <div style={{width:'72%',background:'var(--brand)'}}/>
            </div>
          </div>

          <div className="cc-sec">spend by agent<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 15px 10px'}}>
            <QuotaRow label="lancer" sub="$3.18 · 22%" pct={22} tone={VENDOR.claude.c}/>
            <QuotaRow label="auth-svc" sub="$0.74 · 5%" pct={5} tone={VENDOR.codex.c}/>
            <QuotaRow label="staging-bot" sub="$1.02 · 7%" pct={7} tone={VENDOR.claude.c}/>
          </div>

          <div className="cc-sec">quick top-up<span className="rule"/></div>
          <div className="cc-seg">
            {['$10','$25','$50','$100'].map(a=>(
              <button key={a} className={a==='$50'?'on':''}>{a}</button>
            ))}
          </div>
        </div>
        <div className="sheetfoot">
          <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}} onClick={onClose}><Ic d={ICON.card} s={15}/>Add credits</button>
        </div>
      </div>
    </div>
  );
}

/* ---------- 10 · EditScheduleSheet — edit agent schedule ---------- */
function EditScheduleSheet({onClose}){
  const [cron,setCron]=React.useState('0 */6 * * *');
  const [cmd,setCmd]=React.useState('claude run tests');
  const [enabled,setEnabled]=React.useState(true);
  return (
    <div className="cc-sheetwrap">
      <div className="cc-scrim"/>
      <div className="cc-sheet">
        <div className="grip"/>
        <div className="sheetscroll">
          <h2 className="cc-h2" style={{marginBottom:6}}>Edit schedule</h2>
          <div className="cc-note" style={{marginBottom:16}}>Run this agent on a recurring schedule.</div>

          <div className="cc-sec">cron expression<span className="rule"/></div>
          <CCInput value={cron} onChange={setCron} mono prefix="*"/>

          <div className="cc-sec">command<span className="rule"/></div>
          <CCInput value={cmd} onChange={setCmd} mono prefix="$"/>

          <div className="cc-sec">enabled<span className="rule"/></div>
          <div className="cc-card" style={{padding:'12px 14px',display:'flex',alignItems:'center',gap:10}}>
            <span style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)'}}>Schedule active</span>
            <span className={'cc-toggle'+(enabled?' on':'')} style={{marginLeft:'auto'}} onClick={()=>setEnabled(!enabled)}><span className="knob"/></span>
          </div>

          <div className="cc-sec">schedule info<span className="rule"/></div>
          <div className="cc-card" style={{padding:'11px 14px'}}>
            <div style={{display:'flex',justifyContent:'space-between',alignItems:'center',marginBottom:7}}>
              <span style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink-3)'}}>last run</span>
              <span style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink)'}}>2h ago</span>
            </div>
            <div style={{display:'flex',justifyContent:'space-between',alignItems:'center'}}>
              <span style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink-3)'}}>next run</span>
              <span style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink)'}}>in 4h</span>
            </div>
          </div>
        </div>
        <div className="sheetfoot">
          <div className="cc-btnrow">
            <button className="cc-btn cc-btn--quiet" style={{flex:1}} onClick={onClose}>Cancel</button>
            <button className="cc-btn cc-btn--primary" style={{flex:1.4}}><Ic d={ICON.check} s={15}/>Save schedule</button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ---------- 11 · WorktreeBoardView — Git worktree management ---------- */
function WorktreeBoardView({onBack}){
  const columns=[
    {title:'Active',color:'var(--brand)',cards:[
      {branch:'fix/login-timeout',goal:'fix login timeout',status:'working',activity:'2m ago',files:4},
      {branch:'refactor/auth',goal:'refactor auth middleware',status:'working',activity:'15m ago',files:7},
    ]},
    {title:'Stale',color:'var(--r-med)',cards:[
      {branch:'experiment/bun',goal:'try bun runtime',status:'idle',activity:'3d ago',files:12},
    ]},
    {title:'Merged',color:'var(--ok)',cards:[
      {branch:'ci/pipeline-update',goal:'update CI pipeline',status:'done',activity:'1h ago',files:3},
      {branch:'docs/api-ref',goal:'update API docs',status:'done',activity:'2d ago',files:8},
    ]},
  ];
  return (
    <div className="cc">
      <SubNav title="worktrees" onBack={onBack} right={<span className="cc-chip"><Ic d={ICON.git} s={12}/>lancer</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Drag to move worktrees between stages. Each card shows branch, goal, and changed files.</p>
          <div style={{display:'flex',gap:10,overflowX:'auto',paddingBottom:12}}>
            {columns.map((col,i)=>(
              <div key={i} style={{minWidth:200,flex:1}}>
                <div style={{display:'flex',alignItems:'center',gap:8,marginBottom:10}}>
                  <span style={{width:10,height:10,borderRadius:2,background:col.color,flex:'none'}}/>
                  <span style={{fontFamily:'var(--mono)',fontSize:11.5,fontWeight:600,color:'var(--ink-2)',textTransform:'uppercase',letterSpacing:'.12em'}}>{col.title}</span>
                  <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)'}}>{col.cards.length}</span>
                </div>
                <div style={{display:'flex',flexDirection:'column',gap:8}}>
                  {col.cards.map((card,j)=>(
                    <div key={j} className="cc-card" style={{padding:'12px 13px',cursor:'grab',borderLeft:'3px solid '+col.color}}>
                      <div style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--brand)',fontWeight:600,marginBottom:4}}>{card.branch}</div>
                      <div style={{fontSize:13,color:'var(--ink)',marginBottom:7}}>{card.goal}</div>
                      <div style={{display:'flex',alignItems:'center',gap:8}}>
                        <span className={"cc-sd"+(card.status==='working'?'':'')}><span className={'d '+card.status}/>{card.status}</span>
                        <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)'}}>{card.activity}</span>
                        <span style={{marginLeft:'auto',fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-3)'}}>{card.files} files</span>
                      </div>
                      <div style={{textAlign:'center',marginTop:8,fontFamily:'var(--mono)',fontSize:9,letterSpacing:'.08em',color:'var(--ink-4)'}}>··· drag ···</div>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 12 · RunShipSheet — git ship (commit+push+PR) ---------- */
function RunShipSheet({onClose}){
  const files=['src/auth/session.swift','Sources/SessionViewModel.swift','Tests/SessionTests.swift'];
  return (
    <div className="cc-sheetwrap">
      <div className="cc-scrim"/>
      <div className="cc-sheet">
        <div className="grip"/>
        <div className="sheetscroll">
          <h2 className="cc-h2" style={{marginBottom:6}}>Ship changes</h2>
          <div className="cc-note" style={{marginBottom:16}}>Commit, push, and open a PR for the agent's changes.</div>

          <div className="cc-sec">changed files <span className="n">· {files.length}</span><span className="rule"/></div>
          <div className="cc-card">
            {files.map((f,i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <span style={{color:'var(--r-low)',flex:'none'}}><Ic d={ICON.file} s={14}/></span>
                <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{f}</span>
                <span style={{marginLeft:'auto',fontFamily:'var(--mono)',fontSize:10.5,color:'var(--r-low)'}}>+18</span>
                <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--r-crit)'}}>−4</span>
              </div>
            ))}
          </div>

          <div className="cc-sec">commit message<span className="rule"/></div>
          <CCInput value="fix: resolve login timeout in session handler" onChange={()=>{}} multiline mono/>

          <div className="cc-sec">branch<span className="rule"/></div>
          <div className="cc-card" style={{padding:'11px 14px',display:'flex',alignItems:'center',gap:10}}>
            <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--brand)',fontWeight:600}}>fix/login-timeout</span>
            <span style={{marginLeft:'auto',fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)'}}>from main</span>
          </div>

          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',alignItems:'center',gap:10}}>
            <span className={'cc-toggle on'}><span className="knob"/></span>
            <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>Create pull request</span>
          </div>
        </div>
        <div className="sheetfoot">
          <div className="cc-btnrow">
            <button className="cc-btn cc-btn--quiet" style={{flex:1}} onClick={onClose}>Cancel</button>
            <button className="cc-btn cc-btn--primary" style={{flex:1.4}}><Ic d={ICON.git} s={15}/>Ship</button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ---------- 13 · ShipItSheet — git ship from loop detail ---------- */
function ShipItSheet({onClose}){
  const files=['src/core/AgentService.swift','src/core/SessionManager.swift'];
  return (
    <div className="cc-sheetwrap">
      <div className="cc-scrim"/>
      <div className="cc-sheet">
        <div className="grip"/>
        <div className="sheetscroll">
          <h2 className="cc-h2" style={{marginBottom:6}}>Ship from loop</h2>
          <div className="cc-card" style={{padding:'11px 14px',marginBottom:16,display:'flex',alignItems:'center',gap:10}}>
            <span style={{width:8,height:8,borderRadius:'50%',background:'var(--ok)',flex:'none'}}/>
            <div className="grow">
              <div style={{fontSize:13,color:'var(--ink)'}}>fix agent session reconnect</div>
              <div className="s">goal completed · all tests pass</div>
            </div>
          </div>

          <div className="cc-sec">changed files <span className="n">· {files.length}</span><span className="rule"/></div>
          <div className="cc-card">
            {files.map((f,i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <span style={{color:'var(--r-low)',flex:'none'}}><Ic d={ICON.file} s={14}/></span>
                <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>{f}</span>
                <span style={{marginLeft:'auto',fontFamily:'var(--mono)',fontSize:10.5,color:'var(--r-low)'}}>+32</span>
                <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--r-crit)'}}>−7</span>
              </div>
            ))}
          </div>

          <div className="cc-sec">commit message<span className="rule"/></div>
          <CCInput value="fix: reconnect agent session on timeout" onChange={()=>{}} multiline mono/>

          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',alignItems:'center',gap:10}}>
            <span className={'cc-toggle on'}><span className="knob"/></span>
            <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>Open as PR</span>
          </div>
        </div>
        <div className="sheetfoot">
          <div className="cc-btnrow">
            <button className="cc-btn cc-btn--quiet" style={{flex:1}} onClick={onClose}>Cancel</button>
            <button className="cc-btn cc-btn--primary" style={{flex:1.4}}><Ic d={ICON.git} s={15}/>Ship it</button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ---------- 14 · FilesView — SFTP file browser ---------- */
function FilesView({onBack, onFile}){
  const entries=[
    {name:'.',type:'dir',perms:'drwxr-xr-x',size:'—',date:'Jun 14'},
    {name:'..',type:'dir',perms:'drwxr-xr-x',size:'—',date:'Jun 14'},
    {name:'src',type:'dir',perms:'drwxr-xr-x',size:'—',date:'Jun 14'},
    {name:'Sources',type:'dir',perms:'drwxr-xr-x',size:'—',date:'Jun 14'},
    {name:'Package.swift',type:'file',perms:'-rw-r--r--',size:'2.4 KB',date:'Jun 14'},
    {name:'README.md',type:'file',perms:'-rw-r--r--',size:'1.1 KB',date:'Jun 13'},
  ];
  return (
    <div className="cc">
      <SubNav title="files" onBack={onBack} right={<span className="cc-chip"><Ic d={ICON.net} s={12}/>dev-vps</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div style={{display:'flex',alignItems:'center',gap:8,marginBottom:14,fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-2)',overflow:'hidden',whiteSpace:'nowrap'}}>
            <Ic d={ICON.folder} s={15}/>
            <span style={{color:'var(--brand)'}}>/</span>
            <span>home</span>
            <span style={{color:'var(--brand)'}}>/</span>
            <span>user</span>
            <span style={{color:'var(--brand)'}}>/</span>
            <span style={{color:'var(--ink)'}}>repos</span>
            <span style={{color:'var(--brand)'}}>/</span>
            <span style={{color:'var(--ink-4)'}}>lancer</span>
          </div>

          <div className="cc-card">
            {entries.map((e,i)=>(
              <div key={i} className="cc-row" onClick={()=>e.type==='file'&&onFile&&onFile(e)} style={{cursor:e.type==='file'?'pointer':'default'}}>
                <span style={{color:e.type==='dir'?'var(--brand)':'var(--ink-3)',flex:'none'}}>
                  {e.type==='dir'?<Ic d={ICON.folder} s={17}/>:<Ic d={ICON.file} s={17}/>}
                </span>
                <div className="grow" style={{minWidth:0}}>
                  <div className="t" style={{fontFamily:'var(--mono)',fontSize:13}}>{e.name}</div>
                </div>
                <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',width:70,textAlign:'right',flex:'none'}}>{e.size}</span>
                <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',width:70,textAlign:'right',flex:'none'}}>{e.date}</span>
                <span style={{fontFamily:'var(--mono)',fontSize:9.5,color:'var(--ink-4)',width:100,textAlign:'right',flex:'none'}}>{e.perms}</span>
                {e.type==='file'&&<Ic d={ICON.chev} s={14} className="chev"/>}
              </div>
            ))}
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 15 · FilePreviewView — file content preview ---------- */
function FilePreviewView({onBack}){
  const lines=[
    'import Foundation','','final class SessionViewModel: ObservableObject {','  @Published var blocks: [Block] = []','  private let bridge: PTYBridge','','  init(bridge: PTYBridge) {','    self.bridge = bridge','  }','','  func onBlockBytes(_ data: Data) {','    let timeout = 60','    let retries = 3','    bridge.feed(data, timeout: timeout)','  }','}',
  ];
  return (
    <div className="cc">
      <SubNav title="preview" onBack={onBack} right={<button className="cc-btn cc-btn--quiet" style={{height:32,minHeight:32,padding:'0 10px'}}><Ic d={ICON.copy} s={14}/>Copy</button>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div style={{display:'flex',alignItems:'center',gap:9,borderBottom:'1px solid var(--line-2)',paddingBottom:10}}>
            <Ic d={ICON.file} s={15}/>
            <div className="grow" style={{minWidth:0}}>
              <div style={{fontFamily:'var(--mono)',fontSize:13.5,color:'var(--ink)',fontWeight:600}}>SessionViewModel.swift</div>
              <div style={{display:'flex',alignItems:'center',gap:8,marginTop:2}}>
                <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)'}}>~/repos/lancer/Sources</span>
                <span className="cc-chip" style={{fontSize:9,padding:'1px 6px',background:'var(--brand-soft)',color:'var(--brand)',borderColor:'var(--brand)'}}>Swift</span>
                <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)'}}>16 lines · 482 B</span>
              </div>
            </div>
          </div>

          <div style={{fontFamily:'var(--mono)',fontSize:12,lineHeight:1.85,padding:'10px 0'}}>
            {lines.map((l,i)=>(
              <div key={i} style={{display:'flex',gap:12,padding:'0 2px'}}>
                <span style={{color:'var(--ink-4)',textAlign:'right',width:24,flex:'none',userSelect:'none'}}>{i+1}</span>
                <span style={{color:l.includes('let ')||l.includes('func ')||l.includes('class ')||l.includes('import ')?'var(--ink)':'var(--ink-2)',whiteSpace:'pre'}}>{l||' '}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 16 · PreviewSurface — WKWebView preview surface ---------- */
function PreviewSurface({onBack}){
  return (
    <div className="cc">
      <SubNav title="preview" onBack={onBack} right={<span className="cc-chip"><Ic d={ICON.net} s={12}/>localhost:8080</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div style={{display:'flex',alignItems:'center',gap:8,background:'var(--surface)',border:'1px solid var(--line)',borderRadius:'var(--r-md)',padding:'2px 12px',marginBottom:14}}>
            <Ic d={ICON.lock} s={13}/>
            <span style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-3)',flex:1,overflow:'hidden',whiteSpace:'nowrap',textOverflow:'ellipsis'}}>http://localhost:8080/agents</span>
          </div>

          <div style={{border:'1px solid var(--line)',borderRadius:'var(--r-lg)',overflow:'hidden',background:'#fff',aspectRatio:'390/720',display:'flex',flexDirection:'column',position:'relative'}}>
            <div style={{textAlign:'center',padding:'60px 20px 0'}}>
              <div style={{fontFamily:'var(--sans)',fontSize:18,fontWeight:600,color:'#111'}}>Lancer Agents</div>
              <div style={{fontFamily:'var(--sans)',fontSize:13,color:'#666',marginTop:6}}>Manage your cloud-hosted coding agents</div>
            </div>
            <div style={{margin:'24px 16px 0',border:'1px solid #e2e2e2',borderRadius:8}}>
              {[
                {name:'lancer',status:'online',model:'sonnet 4.6'},
                {name:'auth-svc',status:'online',model:'codex'},
              ].map((a,i)=>(
                <div key={i} style={{display:'flex',alignItems:'center',gap:10,padding:'12px 14px',borderBottom:i===0?'1px solid #e2e2e2':'none',fontFamily:'var(--sans)',color:'#222'}}>
                  <span style={{width:28,height:28,borderRadius:4,background:'#2f43ff',display:'flex',alignItems:'center',justifyContent:'center',color:'#fff',fontSize:12,fontWeight:700}}>{a.name[0]}</span>
                  <div style={{flex:1}}>
                    <div style={{fontSize:13,fontWeight:600}}>{a.name}</div>
                    <div style={{fontSize:11,color:'#888'}}>{a.model}</div>
                  </div>
                  <span style={{width:7,height:7,borderRadius:'50%',background:'#3fb57e',flex:'none'}}/>
                </div>
              ))}
            </div>
            <div style={{textAlign:'center',padding:'40px 20px',color:'#999',fontFamily:'var(--sans)',fontSize:12}}>WKWebView · rendered content</div>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 17 · PreviewToolbar — preview toolbar controls ---------- */
function PreviewToolbar({onBack, onPort}){
  return (
    <div className="cc">
      <SubNav title="preview toolbar" onBack={onBack}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Controls for the in-app web preview surface.</p>

          <div className="cc-sec">URL bar<span className="rule"/></div>
          <div style={{display:'flex',alignItems:'center',gap:8,background:'var(--surface)',border:'1px solid var(--line)',borderRadius:'var(--r-md)',padding:'2px 10px',height:44}}>
            <span className="cc-btn cc-btn--quiet" style={{width:32,height:32,minHeight:32,padding:0,flex:'none'}}><Ic d={ICON.chev} s={16} style={{transform:'rotate(180deg)'}}/></span>
            <span className="cc-btn cc-btn--quiet" style={{width:32,height:32,minHeight:32,padding:0,flex:'none'}}><Ic d={ICON.chev} s={16}/></span>
            <Ic d={ICON.net} s={13} style={{flex:'none'}}/>
            <input value="http://localhost:8080" readOnly style={{flex:1,background:'none',border:'none',fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-2)',outline:'none',padding:'0 6px'}}/>
            <button className="cc-btn cc-btn--quiet" style={{width:32,height:32,minHeight:32,padding:0,flex:'none'}}><Ic d={XIC.refresh} s={15}/></button>
          </div>

          <div className="cc-sec">port<span className="rule"/></div>
          <div className="cc-card" style={{padding:'11px 14px',display:'flex',alignItems:'center',gap:10,cursor:'pointer'}} onClick={onPort}>
            <span style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink)'}}>8080</span>
            <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>(dev server)</span>
            <span style={{marginLeft:'auto'}}><Ic d={ICON.chev} s={15} className="chev"/></span>
          </div>

          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',alignItems:'center',gap:10}}>
            <span className={'cc-toggle on'}><span className="knob"/></span>
            <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>Auto-refresh on file change</span>
          </div>

          <div className="cc-sec">available ports<span className="rule"/></div>
          <div className="cc-card">
            {[['8080','dev server','active'],['3000','Next.js',''],['5173','Vite','']].map(([p,l,s],i)=>(
              <div key={i} className="cc-row" style={{cursor:'pointer'}}>
                <span style={{fontFamily:'var(--mono)',fontSize:13,color:s?'var(--brand)':'var(--ink-2)',fontWeight:s?600:400}}>{p}</span>
                <span style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-3)'}}>{l}</span>
                {s&&<span style={{marginLeft:'auto'}}><span className="cc-sd"><span className="d done"/>active</span></span>}
              </div>
            ))}
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 18 · DiffView — git diff viewer ---------- */
function DiffView({onBack}){
  const hunks=[
    {file:'src/auth/session.swift',lang:'Swift',lines:[
      {n:42,type:'ctx',t:'  func connectToServer() {'},
      {n:43,type:'ctx',t:'    let timeout = 30'},
      {n:44,type:'rem',t:'-   let retries = 3'},
      {n:44,type:'add',t:'+   let retries = 5'},
      {n:45,type:'ctx',t:'    bridge.open(host, port)'},
    ]},
    {file:'Tests/SessionTests.swift',lang:'Swift',lines:[
      {n:12,type:'ctx',t:'  func testConnectTimeout() {'},
      {n:13,type:'rem',t:'-   XCTAssertEqual(3, retries)'},
      {n:13,type:'add',t:'+   XCTAssertEqual(5, retries)'},
    ]},
  ];
  return (
    <div className="cc">
      <SubNav title="diff" onBack={onBack} right={<span className="cc-chip"><Ic d={ICON.git} s={12}/>2 files</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          {hunks.map((h,i)=>(
            <div key={i} style={{marginBottom:14}}>
              <div style={{display:'flex',alignItems:'center',gap:8,marginBottom:8}}>
                <span style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink)'}}>{h.file}</span>
                <span className="cc-chip" style={{fontSize:9,padding:'1px 6px'}}>{h.lang}</span>
              </div>
              <div className="cc-cmd" style={{display:'block',padding:0}}>
                <div className="body" style={{whiteSpace:'pre',padding:'8px 0',fontSize:11.5,lineHeight:1.8,overflowX:'auto'}}>
                  {h.lines.map((l,j)=>(
                    <div key={j} style={{display:'flex',gap:10,padding:'0 13px',color:l.type==='rem'?'var(--r-crit)':l.type==='add'?'var(--r-low)':'var(--ink-2)',background:l.type==='rem'?'rgba(242,75,61,.06)':l.type==='add'?'rgba(63,181,126,.06)':'transparent'}}>
                      <span style={{width:28,textAlign:'right',flex:'none',userSelect:'none',opacity:.5}}>{l.type==='ctx'?l.n:''}</span>
                      <span style={{width:28,textAlign:'right',flex:'none',userSelect:'none',opacity:.5}}>{l.type==='add'?l.n:l.type==='rem'?l.n:''}</span>
                      <span style={{flex:1}}>{l.t}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          ))}
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 19 · LoopDetailView — loop goal→plan→CI→proof ---------- */
function LoopDetailView({onBack}){
  const stages=[
    {label:'Goal',status:'done',detail:'fix agent session reconnect',icon:ICON.check},
    {label:'Plan',status:'done',detail:'3 steps · modify timeout, retry logic, reconnect handler',icon:ICON.check},
    {label:'Execute',status:'done',detail:'4 files patched · 32 insertions, 7 deletions',icon:ICON.check},
    {label:'CI',status:'working',detail:'Build & test running…',icon:null},
    {label:'Proof',status:'waiting',detail:'Attestation after CI passes',icon:null},
  ];
  return (
    <div className="cc">
      <SubNav title="loop" onBack={onBack} right={<span className="cc-sd"><span className="d working"/>in progress</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div className="cc-card" style={{padding:'14px 16px',marginBottom:12}}>
            <div style={{display:'flex',alignItems:'center',gap:10}}>
              <PixelAvatar seed="claudelancer" size={34} color={VENDOR.claude.c}/>
              <div className="grow">
                <div style={{fontFamily:'var(--mono)',fontSize:14,fontWeight:500,color:'var(--ink)'}}>Claude Code</div>
                <div className="s">lancer · fix login timeout</div>
              </div>
              <div style={{textAlign:'right'}}>
                <div style={{fontFamily:'var(--mono)',fontSize:15,color:'var(--ink)'}}>$0.84</div>
                <div className="cc-note">elapsed</div>
              </div>
            </div>
          </div>

          <div className="cc-sec">lifecycle<span className="rule"/></div>
          <div className="cc-card" style={{padding:'6px 16px'}}>
            {stages.map((s,i)=>(
              <div key={i} style={{display:'flex',gap:14,padding:'12px 0',position:'relative'}}>
                <div style={{display:'flex',flexDirection:'column',alignItems:'center',gap:4,flex:'none',width:20}}>
                  <span style={{width:14,height:14,borderRadius:'50%',display:'flex',alignItems:'center',justifyContent:'center',background:s.status==='done'?'var(--ok)':s.status==='working'?'var(--brand)':'var(--surface-2)',border:s.status==='waiting'?'2px solid var(--ink-4)':'none',color:'#fff',flex:'none'}}>
                    {s.status==='done'?<Ic d={ICON.check} s={9}/>:s.status==='working'?<span style={{width:5,height:5,borderRadius:'50%',background:'#fff'}}/>:''}
                  </span>
                  {i<stages.length-1&&<div style={{width:1,flex:1,background:'var(--line)'}}/>}
                </div>
                <div className="grow" style={{paddingBottom:i<stages.length-1?4:0}}>
                  <div style={{fontFamily:'var(--mono)',fontSize:12,fontWeight:600,color:'var(--ink)',textTransform:'uppercase',letterSpacing:'.06em'}}>{s.label}</div>
                  <div style={{fontSize:12.5,color:'var(--ink-2)',marginTop:3}}>{s.detail}</div>
                </div>
              </div>
            ))}
          </div>

          <div className="cc-sec">CI output<span className="n">· running</span><span className="rule"/></div>
          <div className="cc-cmd" style={{display:'block',padding:0}}>
            <div className="body" style={{whiteSpace:'pre-wrap',padding:'11px 13px',fontSize:11,lineHeight:1.7,color:'var(--ink-3)'}}>
              <div style={{color:'var(--ink)'}}>$ swift test</div>
              <div>Build started · 12 targets</div>
              <div style={{color:'var(--r-med)'}}>Compiling SessionViewModel.swift…</div>
              <div style={{color:'var(--ok)'}}>Tests passed · 12.4s<span className="cursor" style={{height:'.7em'}}/></div>
            </div>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 20 · RunDetailView — run detail with budget control ---------- */
function RunDetailView({onBack}){
  const out=[
    ['$ swift build','c'],
    ['Compiling LancerKit (38 files)','o'],
    ['[142/318] Compiling SessionViewModel.swift','o'],
    ['patch src/auth/session.swift','o'],
  ];
  return (
    <div className="cc">
      <SubNav title="run" onBack={onBack} right={<span className="cc-sd"><span className="d working"/>running</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div className="cc-card" style={{padding:'14px 15px'}}>
            <div style={{display:'flex',alignItems:'center',gap:10}}>
              <PixelAvatar seed="claudelancer" size={38} color={VENDOR.claude.c}/>
              <div className="grow" style={{minWidth:0}}>
                <div style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink)',fontWeight:500}}>Claude Code</div>
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
                <div key={i} style={{color:k==='c'?'var(--ink)':'var(--ink-3)'}}>{t}<span className="cursor" style={{height:'.8em',marginLeft:4}}/></div>
              ))}
            </div>
          </div>

          <div className="cc-sec">controls<span className="rule"/></div>
          <div className="cc-btnrow" style={{gap:8}}>
            <CtrlBtn icon={XIC.stop} label="Stop" danger/>
            <CtrlBtn icon={XIC.pause} label="Pause"/>
            <CtrlBtn icon={XIC.gauge} label="Set budget"/>
            <CtrlBtn icon={XIC.nudge} label="Nudge"/>
          </div>

          <div className="cc-sec">budget<span className="rule"/></div>
          <div className="cc-card" style={{padding:'12px 14px'}}>
            <QuotaRow label="This run" sub="$3.18 · 64%" pct={64} tone="var(--brand)"/>
            <QuotaRow label="Daily cap" sub="$5.00 · 64%" pct={64} tone="var(--r-med)"/>
            <QuotaRow label="Weekly budget" sub="$25.00 · 12%" pct={12} tone="var(--ok)"/>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- 21 · QuotaGuardView — per-provider quota dashboard ---------- */
function QuotaGuardView({onBack}){
  const [alerts,setAlerts]=React.useState({claude:true,codex:true,openrouter:false});
  return (
    <div className="cc">
      <SubNav title="quota guard" onBack={onBack}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Per-provider quotas prevent surprise bills. Set spend caps, alert thresholds, and time windows for each provider.</p>

          <div className="cc-sec">claude<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 15px 10px'}}>
            <QuotaRow label="5-hour window" sub="62% used · resets 2:40" pct={62} tone="#b5352a"/>
            <QuotaRow label="Weekly" sub="41% used · resets Mon" pct={41} tone="#c2622c"/>
            <QuotaRow label="Monthly" sub="28% used · $142.50" pct={28} tone="#d09433"/>
          </div>
          <div className="cc-card" style={{marginTop:8,padding:'11px 14px',display:'flex',alignItems:'center',gap:10}}>
            <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>Alert at 80%</span>
            <span className={'cc-toggle'+(alerts.claude?' on':'')} style={{marginLeft:'auto'}} onClick={()=>setAlerts({...alerts,claude:!alerts.claude})}><span className="knob"/></span>
          </div>

          <div className="cc-sec">codex<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 15px 10px'}}>
            <QuotaRow label="API credit balance" sub="$13.40 left · $25.00 cap" pct={46} tone="#8a5fbf"/>
            <QuotaRow label="Daily" sub="22% used" pct={22} tone="#b07ad9"/>
          </div>
          <div className="cc-card" style={{marginTop:8,padding:'11px 14px',display:'flex',alignItems:'center',gap:10}}>
            <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>Alert at 70%</span>
            <span className={'cc-toggle'+(alerts.codex?' on':'')} style={{marginLeft:'auto'}} onClick={()=>setAlerts({...alerts,codex:!alerts.codex})}><span className="knob"/></span>
          </div>

          <div className="cc-sec">openrouter<span className="rule"/></div>
          <div className="cc-card" style={{padding:'4px 15px 10px'}}>
            <QuotaRow label="Prepaid balance" sub="$22.10 left" pct={78} tone="#4f63c9"/>
          </div>
          <div className="cc-card" style={{marginTop:8,padding:'11px 14px',display:'flex',alignItems:'center',gap:10}}>
            <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)'}}>Alert at 50%</span>
            <span className={'cc-toggle'+(alerts.openrouter?' on':'')} style={{marginLeft:'auto'}} onClick={()=>setAlerts({...alerts,openrouter:!alerts.openrouter})}><span className="knob"/></span>
          </div>

          <div className="cc-sec">global settings<span className="rule"/></div>
          <div className="cc-card" style={{padding:'11px 14px'}}>
            <div style={{display:'flex',justifyContent:'space-between',marginBottom:8}}>
              <span style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink-3)'}}>hard cap</span>
              <span style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink)'}}>pause agents at daily limit</span>
            </div>
            <div style={{display:'flex',justifyContent:'space-between'}}>
              <span style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink-3)'}}>notification</span>
              <span style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink)'}}>push when threshold crossed</span>
            </div>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

Object.assign(window,{
  AgentsView,AgentDetailView,AgentRunDetailView,
  AgentFilesView,AgentWorkspaceView,AgentOrgView,AgentExecView,
  CreateAgentSheet,AgentBillingSheet,EditScheduleSheet,
  WorktreeBoardView,RunShipSheet,ShipItSheet,
  FilesView,FilePreviewView,PreviewSurface,PreviewToolbar,
  DiffView,LoopDetailView,RunDetailView,QuotaGuardView,
});