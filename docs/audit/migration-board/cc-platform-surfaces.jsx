/* ============================================================
   CONDUIT — platform surface concepts
   Live Activity, Dynamic Island, and Apple Watch review boards.
   ============================================================ */

function PSStage({ title, subtitle, children }){
  return (
    <div style={{width:'100%',height:'100%',background:'#0b0b0e',padding:18,display:'flex',flexDirection:'column',gap:14,color:'var(--ink)',fontFamily:'var(--sans)',overflow:'hidden'}}>
      <div>
        <div style={{fontFamily:'var(--mono)',fontSize:10,letterSpacing:'.18em',textTransform:'uppercase',color:'var(--ink-4)'}}>{title}</div>
        {subtitle && <div style={{marginTop:5,fontSize:13,lineHeight:1.35,color:'var(--ink-2)'}}>{subtitle}</div>}
      </div>
      <div style={{flex:1,display:'flex',alignItems:'center',justifyContent:'center',minHeight:0}}>{children}</div>
    </div>
  );
}

function PSGlyph({ color='var(--brand)', size=32 }){
  const cells=[.55,.95,.72,.9,.66,.96,.7,.9,.56];
  return (
    <div style={{width:size,height:size,display:'grid',gridTemplateColumns:'repeat(3,1fr)',gap:Math.max(1,size*.07),flex:'none'}}>
      {cells.map((o,i)=><span key={i} style={{background:color,opacity:o,borderRadius:2}}/>)}
    </div>
  );
}

function PSCard({ children, island=false, style }){
  return <div style={{background:'#08080b',border:'1px solid rgba(255,255,255,.12)',borderRadius:island?28:2,boxShadow:'0 18px 50px rgba(0,0,0,.38)',color:'var(--ink)',...style}}>{children}</div>;
}

function PSCommand({ children, compact=false }){
  return <div style={{fontFamily:'var(--mono)',fontSize:compact?11:12,color:'var(--ink-2)',background:'var(--surface)',border:'1px solid var(--line)',borderRadius:2,padding:compact?'8px 9px':'10px 11px',whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}}>{children}</div>;
}

function PSButton({ children, variant='primary', iconOnly=false }){
  const cls = variant==='danger' ? 'cc-btn cc-btn--danger' : variant==='ghost' ? 'cc-btn cc-btn--ghost' : 'cc-btn cc-btn--primary';
  return <button className={cls} style={{height:42,minHeight:42,borderRadius:2,padding:iconOnly?0:'0 12px',fontSize:12.5,flex:1}}>{children}</button>;
}

function PSActionRow({ children, style }){
  return <div style={{display:'grid',gridTemplateColumns:`repeat(${React.Children.count(children)}, minmax(0, 1fr))`,gap:10,marginTop:12,...style}}>{children}</div>;
}

function PSChip({ children, tone='plain' }){
  const color = tone==='pending' ? 'var(--r-med)' : tone==='ok' ? 'var(--r-low)' : tone==='bad' ? 'var(--r-crit)' : 'var(--ink-2)';
  const border = tone==='pending' ? 'var(--r-med-bd)' : tone==='ok' ? 'var(--r-low-bd)' : tone==='bad' ? 'var(--r-crit-bd)' : 'var(--line)';
  return <span style={{fontFamily:'var(--mono)',fontSize:10.5,color,border:`1px solid ${border}`,borderRadius:2,padding:'3px 8px',whiteSpace:'nowrap'}}>{children}</span>;
}

function PSMetric({ label, value, tone='plain' }){
  const color = tone==='pending' ? 'var(--r-med)' : tone==='ok' ? 'var(--r-low)' : tone==='bad' ? 'var(--r-crit)' : tone==='brand' ? 'var(--brand)' : 'var(--ink)';
  return (
    <div style={{background:'var(--surface)',border:'1px solid var(--line)',borderRadius:2,padding:10,minWidth:0}}>
      <div style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-4)',letterSpacing:'.08em'}}>{label}</div>
      <div style={{fontFamily:'var(--mono)',fontSize:12,color,marginTop:3,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}}>{value}</div>
    </div>
  );
}

function PSIslandTop({ children }){
  return (
    <div style={{width:360,height:148,borderRadius:34,background:'#101014',border:'1px solid var(--line)',position:'relative',paddingTop:18,boxShadow:'inset 0 0 0 1px rgba(255,255,255,.03)'}}>
      <div style={{position:'absolute',top:9,left:'50%',transform:'translateX(-50%)',fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)'}}>9:41</div>
      <div style={{height:58,display:'flex',alignItems:'center',justifyContent:'center'}}>{children}</div>
    </div>
  );
}

function PSLockShell({ children }){
  return (
    <div style={{width:360,height:660,borderRadius:34,background:'#111115',border:'1px solid var(--line)',padding:'54px 16px 18px',position:'relative',boxShadow:'inset 0 0 0 1px rgba(255,255,255,.03)'}}>
      <div style={{position:'absolute',top:18,left:0,right:0,textAlign:'center',fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-3)'}}>9:41</div>
      <div style={{textAlign:'center',marginBottom:118}}>
        <div style={{fontSize:56,fontWeight:700,letterSpacing:0,lineHeight:1,color:'var(--ink)'}}>9:41</div>
        <div style={{fontSize:14,color:'var(--ink-3)',marginTop:6}}>Monday, June 15</div>
      </div>
      {children}
    </div>
  );
}

function PSWatchShell({ children, wide=false }){
  return (
    <div style={{width:wide?230:198,height:wide?276:242,borderRadius:46,background:'#050506',border:'1px solid rgba(255,255,255,.18)',padding:16,color:'var(--ink)',boxShadow:'0 18px 48px rgba(0,0,0,.45)',fontFamily:'var(--sans)',position:'relative'}}>
      <div style={{position:'absolute',right:-7,top:82,width:5,height:42,borderRadius:4,background:'#2a2a32'}}/>
      {children}
    </div>
  );
}

function PSIslandCompactPending(){
  return (
    <PSStage title="Dynamic Island · compact" subtitle="Count only: the strongest glance.">
      <PSIslandTop>
        <PSCard island style={{width:154,height:42,borderRadius:999,display:'flex',alignItems:'center',justifyContent:'space-between',padding:'0 12px'}}>
          <PSGlyph color="var(--r-med)" size={22}/>
          <div style={{fontFamily:'var(--mono)',fontSize:15,fontWeight:700,color:'var(--r-med)'}}>2</div>
        </PSCard>
      </PSIslandTop>
    </PSStage>
  );
}

function PSIslandCommandFirst(){
  return (
    <PSStage title="Dynamic Island · command first" subtitle="Approval is framed by the exact request.">
      <PSCard island style={{width:360,padding:16}}>
        <div style={{display:'flex',alignItems:'center',justifyContent:'space-between',gap:12}}>
          <div style={{display:'flex',alignItems:'center',gap:10,minWidth:0}}>
            <PSGlyph color="var(--r-med)" size={28}/>
            <div style={{minWidth:0}}>
              <div style={{fontFamily:'var(--mono)',fontSize:12,fontWeight:700,color:'var(--ink)'}}>Claude Code</div>
              <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',marginTop:2}}>Dev VPS · ~/conduit</div>
            </div>
          </div>
          <RiskChip level="medium"/>
        </div>
        <div style={{marginTop:12}}><PSCommand>patch src/auth/session.swift</PSCommand></div>
        <div style={{display:'grid',gridTemplateColumns:'1fr 1fr 1fr',gap:8,marginTop:10}}>
          <PSMetric label="FILES" value="1"/>
          <PSMetric label="DIFF" value="+18 / -4"/>
          <PSMetric label="WAIT" value="2m" tone="pending"/>
        </div>
        <PSActionRow>
          <PSButton variant="danger"><Ic d={ICON.x} s={14}/>Deny</PSButton>
          <PSButton><Ic d={ICON.check} s={14}/>Approve</PSButton>
        </PSActionRow>
      </PSCard>
    </PSStage>
  );
}

function PSIslandRiskRail(){
  return (
    <PSStage title="Dynamic Island · risk rail" subtitle="Severity is structural, not a floating badge.">
      <PSCard island style={{width:360,padding:0,overflow:'hidden'}}>
        <div style={{display:'grid',gridTemplateColumns:'6px 1fr'}}>
          <div style={{background:'var(--r-med)'}}/>
          <div style={{padding:15}}>
            <div style={{display:'flex',alignItems:'center',gap:11}}>
              <PSGlyph color="var(--r-med)" size={28}/>
              <div style={{flex:1,minWidth:0}}>
                <div style={{fontFamily:'var(--mono)',fontSize:14,fontWeight:700}}>Approval needed</div>
                <div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)',marginTop:2}}>Claude Code · write access</div>
              </div>
              <PSChip tone="pending">MEDIUM</PSChip>
            </div>
            <div style={{marginTop:12}}><PSCommand>patch src/auth/session.swift</PSCommand></div>
            <PSActionRow>
              <PSButton variant="danger">Deny</PSButton>
              <PSButton>Approve</PSButton>
            </PSActionRow>
          </div>
        </div>
      </PSCard>
    </PSStage>
  );
}

function PSLockMinimal(){
  return (
    <PSStage title="Lock Screen · minimal approval" subtitle="Identity, command, decision. No prose.">
      <PSLockShell>
        <PSCard style={{padding:14}}>
          <div style={{display:'flex',alignItems:'center',gap:12}}>
            <PSGlyph color="var(--r-med)" size={32}/>
            <div style={{flex:1,minWidth:0}}>
              <div style={{fontFamily:'var(--mono)',fontSize:14,fontWeight:700}}>Claude Code asks</div>
              <div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)',marginTop:2}}>Dev VPS · medium risk</div>
            </div>
          </div>
          <div style={{marginTop:12}}><PSCommand>patch src/auth/session.swift</PSCommand></div>
          <PSActionRow>
            <PSButton variant="danger"><Ic d={ICON.x} s={14}/>Deny</PSButton>
            <PSButton><Ic d={ICON.check} s={14}/>Approve</PSButton>
          </PSActionRow>
        </PSCard>
      </PSLockShell>
    </PSStage>
  );
}

function PSLockDense(){
  return (
    <PSStage title="Lock Screen · dense approval" subtitle="Adds blast radius while keeping actions balanced.">
      <PSLockShell>
        <PSCard style={{padding:14}}>
          <div style={{display:'flex',alignItems:'center',gap:12}}>
            <PSGlyph color="var(--r-med)" size={32}/>
            <div style={{flex:1,minWidth:0}}>
              <div style={{fontFamily:'var(--mono)',fontSize:14,fontWeight:700}}>Patch approval</div>
              <div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)',marginTop:2}}>Claude Code · ~/conduit</div>
            </div>
            <RiskChip level="medium"/>
          </div>
          <div style={{marginTop:12}}><PSCommand>patch src/auth/session.swift</PSCommand></div>
          <div style={{display:'grid',gridTemplateColumns:'1fr 1fr 1fr',gap:8,marginTop:10}}>
            <PSMetric label="BLAST" value="1 file"/>
            <PSMetric label="GIT" value="yes" tone="pending"/>
            <PSMetric label="RULE" value="ask"/>
          </div>
          <PSActionRow>
            <PSButton variant="danger">Deny</PSButton>
            <PSButton>Approve once</PSButton>
          </PSActionRow>
        </PSCard>
      </PSLockShell>
    </PSStage>
  );
}

function PSLockQueue(){
  return (
    <PSStage title="Lock Screen · approval queue" subtitle="Multiple decisions route to Inbox, not tiny buttons.">
      <PSLockShell>
        <PSCard style={{padding:14}}>
          <div style={{display:'flex',alignItems:'center',gap:12}}>
            <PSGlyph color="var(--r-med)" size={32}/>
            <div style={{flex:1,minWidth:0}}>
              <div style={{fontFamily:'var(--mono)',fontSize:14,fontWeight:700}}>3 approvals waiting</div>
              <div style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)',marginTop:2}}>2 hosts · highest risk critical</div>
            </div>
            <PSChip tone="pending">OPEN</PSChip>
          </div>
          <div style={{display:'flex',flexDirection:'column',gap:7,marginTop:12}}>
            {[
              ['patch src/auth/session.swift','var(--r-med)'],
              ['rm -rf build/ dist/','var(--r-high)'],
              ['curl api.stripe.com/v1/...','var(--r-crit)'],
            ].map(([cmd,color])=>(
              <div key={cmd} style={{display:'flex',alignItems:'center',gap:8,fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-2)'}}>
                <span style={{width:7,height:7,borderRadius:1,background:color,flex:'none'}}/>
                <span style={{whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}}>{cmd}</span>
              </div>
            ))}
          </div>
          <PSActionRow style={{gridTemplateColumns:'1fr'}}>
            <PSButton>Review Inbox</PSButton>
          </PSActionRow>
        </PSCard>
      </PSLockShell>
    </PSStage>
  );
}

function PSWatchMinimal(){
  return (
    <PSStage title="Watch · minimal approval" subtitle="Hard to mis-tap, no extra copy.">
      <PSWatchShell wide>
        <div style={{display:'flex',alignItems:'center',justifyContent:'space-between'}}>
          <PSGlyph color="var(--r-med)" size={30}/>
          <RiskChip level="medium"/>
        </div>
        <div style={{fontFamily:'var(--mono)',fontSize:14,fontWeight:700,marginTop:13}}>Approve patch?</div>
        <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-3)',marginTop:3}}>Claude · Dev VPS</div>
        <div style={{marginTop:12}}><PSCommand compact>session.swift</PSCommand></div>
        <PSActionRow style={{gap:8,marginTop:12}}>
          <PSButton variant="danger" iconOnly><Ic d={ICON.x} s={16}/></PSButton>
          <PSButton iconOnly><Ic d={ICON.check} s={16}/></PSButton>
        </PSActionRow>
      </PSWatchShell>
    </PSStage>
  );
}

function PSWatchRiskFirst(){
  return (
    <PSStage title="Watch · risk first" subtitle="High-risk actions slow the user down.">
      <PSWatchShell wide>
        <div style={{border:'1px solid var(--r-crit-bd)',background:'var(--r-crit-bg)',borderRadius:2,padding:10}}>
          <div style={{fontFamily:'var(--mono)',fontSize:11,fontWeight:700,color:'var(--r-crit)'}}>CRITICAL</div>
          <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-2)',marginTop:4}}>network + credentials</div>
        </div>
        <div style={{marginTop:12}}><PSCommand compact>curl api.stripe.com | sh</PSCommand></div>
        <div style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-3)',marginTop:9}}>Claude · Dev VPS</div>
        <PSActionRow style={{gap:8,marginTop:12}}>
          <PSButton variant="danger">Deny</PSButton>
          <PSButton>Review</PSButton>
        </PSActionRow>
      </PSWatchShell>
    </PSStage>
  );
}

function PSWatchQueue(){
  return (
    <PSStage title="Watch · compact queue" subtitle="A disciplined Inbox glance.">
      <PSWatchShell wide>
        <div style={{display:'flex',alignItems:'center',justifyContent:'space-between'}}>
          <div style={{fontFamily:'var(--mono)',fontSize:13,fontWeight:700}}>Approvals</div>
          <PSChip tone="pending">3</PSChip>
        </div>
        <div style={{display:'grid',gap:7,marginTop:12}}>
          {[
            ['MED','patch session.swift'],
            ['HIGH','rm -rf build/'],
            ['CRIT','curl stripe'],
          ].map(([risk,cmd],i)=>(
            <div key={cmd} style={{display:'grid',gridTemplateColumns:'34px 1fr',gap:7,alignItems:'center',borderTop:i?'1px solid var(--line-2)':'none',paddingTop:i?7:0}}>
              <span style={{fontFamily:'var(--mono)',fontSize:9,color:risk==='CRIT'?'var(--r-crit)':risk==='HIGH'?'var(--r-high)':'var(--r-med)'}}>{risk}</span>
              <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-2)',whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}}>{cmd}</span>
            </div>
          ))}
        </div>
        <PSActionRow style={{gridTemplateColumns:'1fr',marginTop:12}}>
          <PSButton>Open Inbox</PSButton>
        </PSActionRow>
      </PSWatchShell>
    </PSStage>
  );
}

function PlatformSurfacesSection(){
  return (
    <DCSection id="platform-surfaces" title="Live Activity, Dynamic Island & Watch" subtitle="Polished Conduit variants. Square internal controls, balanced actions, and fewer immature pill shapes.">
      <DCArtboard id="island-compact-pending" label="Island compact · pending count" width={396} height={230}>
        <PSIslandCompactPending/>
      </DCArtboard>
      <DCArtboard id="island-command-first" label="Island expanded · command first" width={396} height={360}>
        <PSIslandCommandFirst/>
      </DCArtboard>
      <DCArtboard id="island-risk-rail" label="Island expanded · risk rail" width={396} height={330}>
        <PSIslandRiskRail/>
      </DCArtboard>
      <DCArtboard id="live-activity-minimal" label="Lock Screen · minimal approval" width={396} height={760}>
        <PSLockMinimal/>
      </DCArtboard>
      <DCArtboard id="live-activity-dense" label="Lock Screen · dense approval" width={396} height={760}>
        <PSLockDense/>
      </DCArtboard>
      <DCArtboard id="live-activity-queue" label="Lock Screen · approval queue" width={396} height={760}>
        <PSLockQueue/>
      </DCArtboard>
      <DCArtboard id="watch-minimal" label="Watch · minimal approval" width={300} height={360}>
        <PSWatchMinimal/>
      </DCArtboard>
      <DCArtboard id="watch-risk-first" label="Watch · risk first" width={300} height={360}>
        <PSWatchRiskFirst/>
      </DCArtboard>
      <DCArtboard id="watch-queue" label="Watch · compact queue" width={300} height={360}>
        <PSWatchQueue/>
      </DCArtboard>
    </DCSection>
  );
}

Object.assign(window, { PlatformSurfacesSection });
