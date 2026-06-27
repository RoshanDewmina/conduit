/* ============================================================
   LANCER — core screens: Inbox, ApprovalSheet, Fleet, Activity
   ============================================================ */

/* ---------- refined approval card ---------- */
function ApprovalCard({a, onApprove, onDeny, onOpen}){
  return (
    <div className="cc-card" style={{padding:16}}>
      <div style={{display:'flex',alignItems:'center',gap:10,marginBottom:12}}>
        <VendorMark vendor={a.vendor}/>
        <span style={{marginLeft:'auto',fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)'}}>{a.time}</span>
        <RiskChip level={a.level}/>
      </div>
      <div onClick={onOpen} style={{cursor:'pointer'}}>
        <div style={{fontSize:14.5,color:'var(--ink)',lineHeight:1.4,marginBottom:9}}>
          wants to <b style={{fontWeight:600}}>{a.verb}</b>
        </div>
        <CommandBlock cmd={a.cmd} level={a.level}/>
        <div className="cc-chiprow" style={{marginTop:10}}>
          <span className="cc-chip"><Ic d={ICON.folder} s={12}/>{a.cwd}</span>
          {a.diff && <span className="cc-chip"><span style={{color:'var(--r-low)'}}>+18</span><span style={{color:'var(--r-crit)'}}>−4</span></span>}
          <BlastChips files={a.blast.files} git={a.blast.git} net={a.blast.net} creds={a.blast.creds}/>
        </div>
      </div>
      {/* primary decision — opposed ends, full targets */}
      <div className="cc-btnrow" style={{marginTop:14}}>
        <button className="cc-btn cc-btn--danger" onClick={onDeny}><Ic d={ICON.x} s={15}/>Deny</button>
        <button className="cc-btn cc-btn--primary" onClick={onApprove}><Ic d={ICON.check} s={15}/>Approve</button>
      </div>
      {/* secondary — demoted, separated from one-tap row */}
      <div style={{display:'flex',gap:18,justifyContent:'center',marginTop:12}}>
        <button className="cc-linklike" onClick={onOpen} style={ccLink}><Ic d={ICON.edit} s={13}/>Edit &amp; run</button>
        <span style={{width:1,background:'var(--line)'}}/>
        <button className="cc-linklike" onClick={onOpen} style={ccLink}>Allow always…</button>
      </div>
    </div>
  );
}
const ccLink={background:'none',border:'none',color:'var(--ink-2)',fontFamily:'var(--mono)',fontSize:12,cursor:'pointer',display:'inline-flex',alignItems:'center',gap:6,padding:'4px 2px',whiteSpace:'nowrap'};

function InboxScreen({approvals, onApprove, onDeny, onOpen}){
  return (
    <div className="cc-scroll">
      <StatusHeader state="ok" label="bridge connected" detail="policy: balanced" spend="$4.94"/>
      <PromptHeader title="inbox" crumb={<b>agent approvals</b>} right={approvals.length?`${approvals.length} pending`:'clear'}/>
      <div className="cc-pad">
        {approvals.length===0 ? (
          <div className="cc-empty" style={{marginTop:40}}>
            <div className="glyph"><Ic d={ICON.check} s={24}/></div>
            <h3>nothing needs you</h3>
            <p>Your agents are running under policy. You'll be tapped only when a decision is genuinely ambiguous.</p>
          </div>
        ) : (<>
          <div className="cc-sec">pending <span className="n">· {approvals.length}</span><span className="rule"/></div>
          {approvals.map(a=>(
            <div key={a.id} style={{marginBottom:12}}>
              <ApprovalCard a={a} onApprove={()=>onApprove(a)} onDeny={()=>onDeny(a)} onOpen={()=>onOpen(a)}/>
            </div>
          ))}
          <p className="cc-note" style={{margin:'4px 4px 0'}}>“Allow always” writes a standing rule for this exact tool, input &amp; path. Manage rules in Settings → Policy.</p>

          <div className="cc-sec">decided <span className="n">· today</span><span className="rule"/></div>
          <div className="cc-card">
            {DECIDED.map((d,i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <PixelAvatar seed={d.vendor} size={28} color={VENDOR[d.vendor].c}/>
                <div className="grow">
                  <div className="s" style={{color:'var(--ink-2)'}}>$ {d.cmd}</div>
                </div>
                <span className="cc-risk" data-r={d.decision==='allowed'?'low':'low'} style={{background:'var(--surface-2)',border:'1px solid var(--line)',color:'var(--ink-3)'}}>{d.decision}</span>
                <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)',marginLeft:8}}>{d.time}</span>
              </div>
            ))}
          </div>
        </>)}
      </div>
      <div className="cc-bottompad"/>
    </div>
  );
}

/* ---------- decision sheet (full detail, all 4 actions) ---------- */
function ApprovalSheet({a, onClose, onDecide}){
  if(!a) return null;
  const crit=a.level==='critical';
  return (
    <div className="cc-sheetwrap">
      <div className="cc-scrim" onClick={onClose}/>
      <div className="cc-sheet">
        <div className="grip"/>
        <div className="sheetscroll">
          <div style={{display:'flex',alignItems:'center',gap:10,margin:'8px 0 16px'}}>
            <VendorMark vendor={a.vendor} size={26}/>
            <span style={{marginLeft:'auto'}}><RiskChip level={a.level}/></span>
          </div>
          <h2 className="cc-h2" style={{marginBottom:6}}>Wants to {a.verb}</h2>
          <div className="cc-note" style={{marginBottom:14}}>on <b style={{color:'var(--ink-2)'}}>{a.cwd}</b> · {a.host||'Dev VPS'}</div>
          <CommandBlock cmd={a.cmd} level={a.level}/>
          {a.diff && <div style={{marginTop:8,fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-3)'}}><span style={{color:'var(--r-low)'}}>+18</span> &nbsp;<span style={{color:'var(--r-crit)'}}>−4</span> &nbsp;lines</div>}

          <div className="cc-sec">blast radius<span className="rule"/></div>
          <BlastChips files={a.blast.files} git={a.blast.git} net={a.blast.net} creds={a.blast.creds}/>

          <div className="cc-sec">why this asks you<span className="rule"/></div>
          <div className="cc-card" style={{padding:'13px 14px'}}>
            <div style={{fontSize:13.5,color:'var(--ink-2)',lineHeight:1.55}}>Your policy escalates this because rule <b className="cc-mono" style={{color:'var(--ink)',fontSize:12}}>{a.rule}</b> says <b style={{color:'var(--ink)'}}>ask</b> for <b style={{color:'var(--ink)'}}>{a.kind}</b> actions at <b style={{color:'var(--ink)'}}>{a.level}</b> risk.</div>
          </div>

          {crit && <div className="cc-card" style={{marginTop:12,padding:'12px 14px',borderColor:'var(--r-crit-bd)',background:'var(--r-crit-bg)'}}>
            <div style={{display:'flex',gap:9,alignItems:'center',color:'var(--r-crit)'}}><Ic d={ICON.shield} s={16}/><span style={{fontFamily:'var(--mono)',fontSize:12,fontWeight:600}}>Face ID required to approve</span></div>
          </div>}
        </div>
        <div className="sheetfoot">
          <div className="cc-btnrow" style={{marginBottom:10}}>
            <button className="cc-btn cc-btn--danger" onClick={()=>onDecide(a,'deny')}><Ic d={ICON.x} s={15}/>Deny</button>
            <button className="cc-btn cc-btn--primary" onClick={()=>onDecide(a,'approve')}><Ic d={crit?ICON.lock:ICON.check} s={15}/>{crit?'Approve':'Approve once'}</button>
          </div>
          <div className="cc-btnrow">
            <button className="cc-btn cc-btn--quiet" style={{flex:1}} onClick={()=>onDecide(a,'edit')}><Ic d={ICON.edit} s={14}/>Edit &amp; run</button>
            <button className="cc-btn cc-btn--quiet" style={{flex:1}} onClick={()=>onDecide(a,'always')}>Allow always</button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ---------- Fleet ---------- */
const STATUS_LABEL={working:'working',waiting:'waiting',idle:'idle',offline:'offline',error:'error',done:'done'};
function AgentRow({a, onOpen}){
  const v=VENDOR[a.vendor];
  return (
    <div className="cc-row" onClick={onOpen}>
      <PixelAvatar seed={a.vendor+a.name} size={38} color={v.c}/>
      <div className="grow" style={{minWidth:0}}>
        <div style={{display:'flex',alignItems:'baseline',gap:7,whiteSpace:'nowrap',overflow:'hidden'}}>
          <span style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink)',fontWeight:500}}>{v.label}</span>
          <span style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink-4)'}}>{a.name}</span>
        </div>
        <div className="s" style={{marginTop:3}}>{a.host} · {a.model}</div>
      </div>
      <div style={{flex:'none',width:84,display:'flex',flexDirection:'column',alignItems:'flex-end',gap:5}}>
        <span className="cc-sd"><span className={'d '+a.status}/>{STATUS_LABEL[a.status]}</span>
        {a.spend!=='—'?<span style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-2)'}}>{a.spend}</span>:<span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)'}}>no login</span>}
      </div>
    </div>
  );
}
function FleetScreen({agents, onOpenAgent, onAddHost}){
  const waiting=agents.filter(a=>a.status==='waiting').length;
  return (
    <div className="cc-scroll">
      <StatusHeader state="ok" label="bridge connected" detail="3 hosts" spend="$4.94"/>
      <PromptHeader title="fleet" crumb={<b>agents &amp; spend</b>} right={`${agents.length} agents`}/>
      <div className="cc-pad">
        {/* cross-vendor spend — the killer glance, real values */}
        <div className="cc-card" style={{padding:'16px 16px 14px',marginTop:4}}>
          <div style={{display:'flex',alignItems:'flex-end',justifyContent:'space-between'}}>
            <div>
              <div style={{fontFamily:'var(--mono)',fontSize:34,fontWeight:700,color:'var(--ink)',lineHeight:1,letterSpacing:'-.02em'}}>$4.94</div>
              <div className="cc-note" style={{marginTop:5}}>spend today · across all vendors</div>
            </div>
            <div style={{textAlign:'right'}}>
              <div style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-2)'}}>7 runs</div>
              <div style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-3)',marginTop:3}}>1 / 3 concurrent</div>
            </div>
          </div>
          <div style={{display:'flex',gap:4,marginTop:14,height:6,borderRadius:3,overflow:'hidden',background:'var(--surface-2)'}}>
            <div style={{width:'85%',background:'#d97757'}}/>
            <div style={{width:'15%',background:'#9b9ca6'}}/>
          </div>
          <div style={{display:'flex',gap:16,marginTop:9}}>
            <span className="cc-chip" style={{border:'none',background:'none',padding:0,color:'var(--ink-3)'}}><span style={{width:8,height:8,borderRadius:2,background:'#d97757'}}/>Claude $4.20</span>
            <span className="cc-chip" style={{border:'none',background:'none',padding:0,color:'var(--ink-3)'}}><span style={{width:8,height:8,borderRadius:2,background:'#9b9ca6'}}/>Codex $0.74</span>
            <span style={{marginLeft:'auto',fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)'}}>$25 cap</span>
          </div>
        </div>

        {waiting>0 && <div className="cc-card" style={{marginTop:12,padding:'12px 14px',borderColor:'var(--r-med-bd)',background:'var(--r-med-bg)',cursor:'pointer'}} onClick={()=>onOpenAgent(agents.find(a=>a.status==='waiting'))}>
          <div style={{display:'flex',alignItems:'center',gap:10}}>
            <span className="cc-sd"><span className="d waiting"/></span>
            <span style={{fontSize:13.5,color:'var(--ink)'}}><b style={{fontFamily:'var(--mono)',fontSize:13}}>Codex</b> is waiting for your decision</span>
            <Ic d={ICON.chev} s={16}/>
          </div>
        </div>}

        <div className="cc-sec">agents <span className="n">· {agents.length}</span><span className="rule"/></div>
        <div className="cc-card">
          {agents.map(a=>(<AgentRow key={a.id} a={a} onOpen={()=>onOpenAgent(a)}/>))}
        </div>
        <button className="cc-btn cc-btn--ghost cc-btn--block" style={{marginTop:14}} onClick={onAddHost}><Ic d={ICON.plus} s={16}/>Add a host</button>
      </div>
      <div className="cc-bottompad"/>
    </div>
  );
}

/* ---------- Activity ---------- */
const ACT={
  'auto-allow':{c:'var(--r-low)',bg:'var(--r-low-bg)',bd:'var(--r-low-bd)',label:'auto-allow'},
  'auto-deny':{c:'var(--r-crit)',bg:'var(--r-crit-bg)',bd:'var(--r-crit-bd)',label:'auto-deny'},
  'escalate':{c:'var(--r-med)',bg:'var(--r-med-bg)',bd:'var(--r-med-bd)',label:'escalate'},
  'you-allow':{c:'var(--brand)',bg:'var(--brand-soft)',bd:'var(--brand)',label:'you allowed'},
  'dispatch':{c:'var(--ink-2)',bg:'var(--surface-2)',bd:'var(--line)',label:'dispatch'},
};
function ActivityScreen(){
  return (
    <div className="cc-scroll">
      <StatusHeader state="ok" label="bridge connected" detail="recording audit"/>
      <PromptHeader title="activity" crumb={<b>while you were away</b>}/>
      <div className="cc-pad">
        {AUDIT.map((g,gi)=>(
          <div key={gi}>
            <div className="cc-sec">{g.group}<span className="rule"/></div>
            <div className="cc-card" style={{padding:'2px 0'}}>
              {g.rows.map((r,i)=>{const m=ACT[r.act];return (
                <div key={i} style={{display:'flex',alignItems:'flex-start',gap:11,padding:'11px 14px',position:'relative'}}>
                  {i>0 && <span style={{position:'absolute',top:0,left:14,right:0,height:1,background:'var(--line-2)'}}/>}
                  <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-4)',paddingTop:3,width:34,flex:'none'}}>{r.t}</span>
                  <span style={{flex:'none',marginTop:1,fontFamily:'var(--mono)',fontSize:9.5,fontWeight:600,letterSpacing:'.06em',textTransform:'uppercase',color:m.c,background:m.bg,border:'1px solid '+m.bd,borderRadius:3,padding:'2px 6px',width:80,textAlign:'center'}}>{m.label}</span>
                  <div style={{flex:1,minWidth:0}}>
                    <div style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)',whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}}><span style={{color:VENDOR[r.vendor].c}}>{r.vendor}</span> · {r.cmd}</div>
                    <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginTop:3}}>rule: {r.rule}</div>
                  </div>
                </div>
              );})}
            </div>
          </div>
        ))}
        <p className="cc-note" style={{margin:'16px 4px 0',textAlign:'center'}}>Every autonomous decision is recorded. Disagree with one? Tap to tighten or loosen its rule.</p>
      </div>
      <div className="cc-bottompad"/>
    </div>
  );
}

Object.assign(window,{ApprovalCard,InboxScreen,ApprovalSheet,FleetScreen,AgentRow,ActivityScreen});
