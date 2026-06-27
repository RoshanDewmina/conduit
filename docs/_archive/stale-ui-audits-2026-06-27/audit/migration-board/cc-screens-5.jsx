/* ============================================================
   LANCER — ALL settings sub-pages (board coverage sweep)
   • Terminal customisation  • Relay pairing / E2E
   • Trust & privacy          • Premium comparison
   • Billing overview         • Provider keys (expanded)
   • Shortcut bar editor      • Snippet editor
   • iCloud sync status       • Policy YAML editor
   • Secrets vault            • Audit trail
   • Health check (Doctor)    • SSH key management (expanded)
   ============================================================ */

/* ---------- Terminal customization ---------- */
function TerminalSettingsView(){
  return (
    <div className="cc">
      <SubNav title="terminal"/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Customise your block terminal — shell, colours, font size and auto-connect behaviour.</p>

          <div className="cc-sec">default shell<span className="rule"/></div>
          <div className="cc-seg">
            <button className="on">bash</button>
            <button>zsh</button>
            <button>fish</button>
          </div>

          <div className="cc-sec">colour scheme<span className="rule"/></div>
          <div className="cc-card">
            {[['Dark+,','the block-terminal default'],['Solarized Dark','soft amber & blue'],['Nord','arctic, pastel-friendly'],['Dracula','deep purple & pink'],['Gruvbox','retro warm']].map(([l,s],i)=>(
              <div key={i} className="cc-row" style={{cursor:'pointer'}}>
                <span style={{width:16,height:16,borderRadius:3,background:i===0?'var(--brand)':'var(--surface-3)',border:'1px solid var(--line)',flex:'none',display:'flex',alignItems:'center',justifyContent:'center'}}>{i===0&&<Ic d={ICON.check} s={11}/>}</span>
                <div className="grow"><div className="t" style={{fontSize:14}}>{l}</div><div className="s">{s}</div></div>
              </div>
            ))}
          </div>

          <div className="cc-sec">font size<span className="rule"/></div>
          <div className="cc-card" style={{padding:'12px 16px'}}>
            <div style={{display:'flex',alignItems:'center',gap:12}}>
              <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)',flex:'none'}}>A</span>
              <div style={{flex:1,height:6,borderRadius:3,background:'var(--surface-2)',position:'relative'}}>
                <div style={{width:'58%',height:'100%',background:'var(--brand)',borderRadius:3}}/>
                <span style={{position:'absolute',left:'58%',top:-5,width:16,height:16,borderRadius:'50%',background:'var(--brand)',marginLeft:-8}}/>
              </div>
              <span style={{fontFamily:'var(--mono)',fontSize:15,color:'var(--ink-2)',flex:'none'}}>A</span>
            </div>
            <div style={{display:'flex',justifyContent:'space-between',marginTop:7,fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)'}}>
              <span>12</span>
              <span style={{color:'var(--ink-2)'}}>14</span>
              <span>16</span>
              <span>18</span>
              <span>20</span>
            </div>
          </div>

          <div className="cc-sec">behaviour<span className="rule"/></div>
          <div className="cc-card">
            <div className="cc-row" style={{cursor:'pointer'}}>
              <div className="grow"><div className="t" style={{fontSize:14}}>Auto-connect on launch</div><div className="s">reopen the last session automatically</div></div>
              <span className="cc-toggle on"><span className="knob"/></span>
            </div>
            <div className="cc-row" style={{cursor:'pointer'}}>
              <div className="grow"><div className="t" style={{fontSize:14}}>Show timestamps</div><div className="s">prepend [HH:MM:SS] to every line</div></div>
              <span className="cc-toggle"><span className="knob"/></span>
            </div>
          </div>

          <button className="cc-btn cc-btn--ghost cc-btn--block" style={{marginTop:14}}><Ic d={ICON.refresh} s={14}/>Reset to defaults</button>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- Relay pairing & E2E ---------- */
function E2ERelayPairingView(){
  return (
    <div className="cc">
      <SubNav title="relay &amp; e2e"/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <StatusHeader state="ok" label="relay paired" detail="lancer-relay-01.us-east"/>

          <div className="cc-sec">connection<span className="rule"/></div>
          <div className="cc-card">
            <div className="cc-row" style={{cursor:'default'}}>
              <span style={{width:30,height:30,borderRadius:2,background:'var(--surface-2)',border:'1px solid var(--line)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--ink-2)',flex:'none'}}><Ic d={ICON.net} s={15}/></span>
              <div className="grow"><div className="t" style={{fontSize:14}}>Relay URL</div><div className="s">wss://relay.conduit.dev/edge/abc123</div></div>
              <Ic d={ICON.copy} s={14}/>
            </div>
            <div className="cc-row" style={{cursor:'default'}}>
              <span style={{width:30,height:30,borderRadius:2,background:'var(--surface-2)',border:'1px solid var(--line)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--r-low)',flex:'none'}}><Ic d={ICON.lock} s={15}/></span>
              <div className="grow"><div className="t" style={{fontSize:14}}>End-to-end encryption</div><div className="s">X25519 + ChaCha20-Poly1305</div></div>
              <span className="cc-chip" style={{color:'var(--r-low)',borderColor:'var(--r-low-bd)'}}>active</span>
            </div>
          </div>

          <div className="cc-sec">pair a device<span className="rule"/></div>
          <div className="cc-card" style={{padding:'18px 16px',display:'flex',flexDirection:'column',alignItems:'center'}}>
            <div style={{width:120,height:120,borderRadius:10,background:'var(--surface)',border:'1px solid var(--line)',display:'grid',gridTemplateColumns:'repeat(9,1fr)',gridTemplateRows:'repeat(9,1fr)',padding:10,gap:2}}>
              {Array.from({length:81}).map((_,i)=>(<div key={i} style={{background:(ccHash('pair'+i)%10<4)?'var(--ink)':'transparent',borderRadius:1}}/>))}
            </div>
            <p className="cc-note" style={{margin:'14px 0 0',textAlign:'center'}}>Scan this code with a new device to<br/>pair it to your relay channel.</p>
          </div>

          <button className="cc-btn cc-btn--danger cc-btn--block" style={{marginTop:14}}><Ic d={ICON.x} s={15}/>Disconnect relay</button>
          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.shield} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>The relay never sees your keys or policy data. Push notifications and out-of-network approvals use this channel end-to-end encrypted.</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- Trust & privacy ---------- */
function TrustPrivacyView(){
  const rows=[
    ['Policy rules','Local only','never leaves'],
    ['Provider API keys','Local keychain','never leaves'],
    ['SSH host keys','Local keychain','never leaves'],
    ['Command output','Local only','never leaves'],
    ['Audit log','Local only','never leaves'],
    ['Decision approvals','Encrypted relay','push notification'],
    ['Snippets & presets','iCloud encrypted','Apple cloud'],
    ['Premium account','Stripe API','payment processor'],
  ];
  return (
    <div className="cc">
      <SubNav title="trust &amp; privacy"/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div style={{display:'flex',alignItems:'center',justifyContent:'center',marginBottom:16}}>
            <span style={{width:54,height:54,borderRadius:14,background:'var(--brand-soft)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--brand)'}}><svg width={26} height={26} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"><path d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z"/><path d="M9 12l2 2 4-4"/></svg></span>
          </div>
          <p className="cc-lead" style={{margin:'0 0 12px',textAlign:'center'}}>Your data stays on your host. Lancer's relay only carries what you approve — end-to-end encrypted.</p>

          <div className="cc-sec">data path trace<span className="rule"/></div>
          <div className="cc-card" style={{padding:0}}>
            <div style={{display:'flex',padding:'10px 14px',borderBottom:'1px solid var(--line-2)',fontFamily:'var(--mono)',fontSize:10.5,letterSpacing:'.1em',textTransform:'uppercase',color:'var(--ink-4)'}}>
              <span style={{flex:1.2}}>Feature</span>
              <span style={{flex:1,textAlign:'center'}}>Stored</span>
              <span style={{flex:1,textAlign:'right'}}>Destination</span>
            </div>
            {rows.map(([feat,store,dest],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default',padding:'11px 14px'}}>
                <span style={{fontFamily:'var(--mono)',fontSize:12.5,color:'var(--ink)',flex:1.2}}>{feat}</span>
                <span style={{flex:1,display:'flex',justifyContent:'center'}}>
                  {store==='Local only'&&<span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--r-low)',background:'var(--r-low-bg)',border:'1px solid var(--r-low-bd)',borderRadius:2,padding:'2px 7px'}}>local</span>}
                  {store==='Encrypted relay'&&<span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--brand)',background:'var(--brand-soft)',border:'1px solid var(--brand)',borderRadius:2,padding:'2px 7px'}}>relay e2e</span>}
                  {store==='Local keychain'&&<span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--r-low)',background:'var(--r-low-bg)',border:'1px solid var(--r-low-bd)',borderRadius:2,padding:'2px 7px'}}>keychain</span>}
                  {store==='iCloud encrypted'&&<span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--r-med)',background:'var(--r-med-bg)',border:'1px solid var(--r-med-bd)',borderRadius:2,padding:'2px 7px'}}>cloud</span>}
                  {store==='Stripe API'&&<span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--r-med)',background:'var(--r-med-bg)',border:'1px solid var(--r-med-bd)',borderRadius:2,padding:'2px 7px'}}>stripe</span>}
                </span>
                <span style={{fontFamily:'var(--mono)',fontSize:11,color:'var(--ink-3)',flex:1,textAlign:'right'}}>{dest}</span>
              </div>
            ))}
          </div>

          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.shield} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Lancer has no telemetry, no analytics, and no cloud storage of your commands or code. The bridge is open source and independently auditable.</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- Premium plan comparison ---------- */
function PremiumComparisonView(){
  const plans=[
    ['BYO-host agents','free','pro'],
    ['Number of hosts','1','unlimited'],
    ['Basic policy rules','free','pro'],
    ['Cloud-hosted agents','—','pro'],
    ['Multi-host fleet routing','—','pro'],
    ['Team org & shared inbox','—','pro'],
    ['Priority relay','—','pro'],
    ['Audit export (JSON/CSV)','—','pro'],
    ['Email support','—','pro'],
  ];
  return (
    <div className="cc">
      <SubNav title="compare plans" right={<span className="cc-chip"><Ic d={ICON.bolt} s={12}/>Pro</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <Spectrum/>
          <h2 className="cc-h2" style={{margin:'14px 0 4px'}}>Free · Pro</h2>
          <p className="cc-lead" style={{margin:'0 0 14px'}}>BYO-host is always free. Pro unlocks hosted execution and team features.</p>

          <div className="cc-card" style={{padding:0}}>
            <div style={{display:'flex',padding:'12px 14px',borderBottom:'1px solid var(--line-2)',fontFamily:'var(--mono)',fontSize:10.5,letterSpacing:'.1em',textTransform:'uppercase'}}>
              <span style={{flex:1.6}}>Feature</span>
              <span style={{flex:1,textAlign:'center'}}>Free</span>
              <span style={{flex:1,textAlign:'center'}}>Pro</span>
            </div>
            {plans.map(([feat,free,pro],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default',padding:'11px 14px'}}>
                <span style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink)',flex:1.6}}>{feat}</span>
                <span style={{flex:1,display:'flex',justifyContent:'center',color:free==='—'?'var(--ink-4)':'var(--r-low)'}}>
                  {free==='free'?<Ic d={ICON.check} s={14}/>:free==='—'?<span style={{color:'var(--ink-4)'}}>—</span>:<span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--r-low)'}}>{free}</span>}
                </span>
                <span style={{flex:1,display:'flex',justifyContent:'center',color:'var(--r-low)'}}>
                  {pro==='pro'?<Ic d={ICON.check} s={14}/>:<span style={{fontFamily:'var(--mono)',fontSize:10.5}}>{pro}</span>}
                </span>
              </div>
            ))}
          </div>

          <p className="cc-note" style={{margin:'12px 4px 0',textAlign:'center'}}>All plans include E2E encryption, local-first policy, and the full audit trail.</p>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <button className="cc-btn cc-btn--primary cc-btn--block" style={{height:52}}><Ic d={ICON.bolt} s={16}/>Upgrade to Pro</button>
      </div>
    </div>
  );
}

/* ---------- Billing overview ---------- */
function BillingView(){
  const invoices=[
    ['May 15, 2026','$8.00','paid'],
    ['Apr 15, 2026','$8.00','paid'],
    ['Mar 15, 2026','$8.00','paid'],
    ['Feb 15, 2026','$8.00','paid'],
  ];
  return (
    <div className="cc">
      <SubNav title="billing" right={<span className="cc-chip"><Ic d={ICON.bolt} s={12}/>Pro</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <div className="cc-card" style={{padding:'16px 16px 14px'}}>
            <div style={{display:'flex',alignItems:'flex-end',justifyContent:'space-between'}}>
              <div>
                <div className="cc-note" style={{marginBottom:4}}>current plan</div>
                <div style={{display:'flex',alignItems:'center',gap:8}}>
                  <span style={{fontFamily:'var(--mono)',fontSize:22,fontWeight:700,color:'var(--ink)'}}>Lancer Pro</span>
                  <span className="cc-chip" style={{color:'var(--r-low)',borderColor:'var(--r-low-bd)'}}>$8/mo</span>
                </div>
              </div>
              <span className="cc-sd"><span className="d done"/>active</span>
            </div>
            <div style={{marginTop:14,paddingTop:14,borderTop:'1px solid var(--line-2)',display:'flex',justifyContent:'space-between'}}>
              <div><div className="cc-note">next billing</div><div style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink-2)',marginTop:3}}>Jun 15, 2026</div></div>
              <div style={{textAlign:'right'}}><div className="cc-note">payment method</div><div style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink-2)',marginTop:3}}>Visa ····4242</div></div>
            </div>
          </div>

          <div className="cc-sec">invoice history<span className="rule"/></div>
          <div className="cc-card">
            {invoices.map(([date,amt,status],i)=>(
              <div key={i} className="cc-row" style={{cursor:'pointer'}}>
                <div className="grow">
                  <div className="t" style={{fontSize:14}}>{date}</div>
                  <div className="s" style={{fontFamily:'var(--mono)',fontSize:11}}>{amt}</div>
                </div>
                <span className="cc-sd"><span className="d done"/>{status}</span>
                <Ic d={ICON.chev} s={15}/>
              </div>
            ))}
          </div>

          <button className="cc-btn cc-btn--ghost cc-btn--block" style={{marginTop:14}}><Ic d={ICON.card} s={15}/>Manage subscription</button>
          <p className="cc-note" style={{textAlign:'center',margin:'12px 4px 0'}}>Invoices go to your Apple ID on file. Past payments are always downloadable.</p>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- Provider keys (expanded multi-vendor) ---------- */
function ProviderKeysView(){
  return (
    <div className="cc">
      <SubNav title="provider keys"/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Add the providers your agents use. Keys live in the Keychain and go straight to the provider — Lancer's relay never sees them.</p>
          <div className="cc-card">
            <KeyRow vendor="claude" accent={VENDOR.claude.c} label="Anthropic" sub="sk-ant-…M2 · Claude Code" state="ok"/>
            <KeyRow vendor="codex" accent={VENDOR.codex.c} label="OpenAI" sub="sk-…9f · GPT-5.1 Codex" state="ok"/>
            <KeyRow vendor="openrouter" accent="#56b3c2" label="OpenRouter" sub="one key, many models · balance $22.10" state="add"/>
            <KeyRow vendor="opencode" accent={VENDOR.opencode.c} label="Ollama / llama.cpp" sub="self-hosted models · local only" state="local"/>
            <KeyRow vendor="google" accent="#4f8cff" label="Google Gemini" sub="API key · Gemini 2.5 Pro" state="add"/>
            <KeyRow vendor="azure" accent="#0078d4" label="Azure OpenAI" sub="endpoint + key · gpt-4o" state="add"/>
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

/* ---------- Shortcut bar editor ---------- */
function ShortcutBarEditor(){
  const shortcuts=[
    ['git status','git status','on'],
    ['Git Pull','git pull --rebase','on'],
    ['Build','swift build','on'],
    ['Test','swift test --filter','on'],
    ['Deploy','cap production deploy',''],
    ['Docker ps','docker ps -a',''],
    ['Tail logs','tail -f /var/log/syslog',''],
  ];
  return (
    <div className="cc">
      <SubNav title="shortcuts"/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Customise the shortcut bar at the bottom of your terminal session. Drag to reorder, toggle to hide.</p>
          <div className="cc-card">
            {shortcuts.map(([name,cmd,on],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <span style={{color:'var(--ink-4)',cursor:'grab',display:'flex',flex:'none'}}>
                  <svg width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8}><circle cx="10" cy="6" r="1.4"/><circle cx="14" cy="6" r="1.4"/><circle cx="10" cy="12" r="1.4"/><circle cx="14" cy="12" r="1.4"/><circle cx="10" cy="18" r="1.4"/><circle cx="14" cy="18" r="1.4"/></svg>
                </span>
                <div className="grow" style={{minWidth:0}}>
                  <div className="t" style={{fontSize:14}}>{name}</div>
                  <div className="s" style={{fontFamily:'var(--mono)'}}>{cmd}</div>
                </div>
                <span className={'cc-toggle'+(on==='on'?' on':'')}><span className="knob"/></span>
              </div>
            ))}
          </div>
          <button className="cc-btn cc-btn--ghost cc-btn--block" style={{marginTop:14}}><Ic d={ICON.plus} s={15}/>Add shortcut</button>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- Snippet editor ---------- */
function SnippetEditorView(){
  return (
    <div className="cc">
      <SubNav title="edit snippet"/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Save reusable command snippets for quick execution in any terminal session.</p>

          <div className="cc-sec">name<span className="rule"/></div>
          <CCInput value="Deploy to production" onChange={()=>{}} placeholder="Snippet name"/>

          <div className="cc-sec">command<span className="rule"/></div>
          <CCInput value="cap production deploy\nBRANCH=main" onChange={()=>{}} multiline mono placeholder="$ your command"/>

          <div className="cc-sec">arguments <span className="n">· optional</span><span className="rule"/></div>
          <div className="cc-card">
            {[['branch','main'],['env','production']].map(([arg,val],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <span style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink-3)',width:60,flex:'none'}}>{arg}</span>
                <span style={{fontFamily:'var(--mono)',fontSize:12,color:'var(--ink)'}}>{val}</span>
                <span style={{marginLeft:'auto',color:'var(--r-crit)',cursor:'pointer',flex:'none'}}><Ic d={ICON.x} s={14}/></span>
              </div>
            ))}
            <div className="cc-row" style={{cursor:'pointer',color:'var(--brand)'}}>
              <Ic d={ICON.plus} s={14}/>
              <span style={{fontFamily:'var(--mono)',fontSize:12}}>Add argument</span>
            </div>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <div className="cc-btnrow">
          <button className="cc-btn cc-btn--quiet" style={{flex:1}}>Cancel</button>
          <button className="cc-btn cc-btn--primary" style={{flex:1.4}}><Ic d={ICON.check} s={15}/>Save</button>
        </div>
      </div>
    </div>
  );
}

/* ---------- iCloud sync status ---------- */
function SyncStatusView(){
  const types=[
    ['Settings & preferences',true],
    ['Host connections',true],
    ['SSH keys',true],
    ['Policy rules',true],
    ['Snippets & presets',true],
    ['Audit log',false],
    ['Provider API keys',false],
  ];
  return (
    <div className="cc">
      <SubNav title="sync"/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <StatusHeader state="ok" label="iCloud sync" detail="enabled"/>

          <div className="cc-sec">status<span className="rule"/></div>
          <div className="cc-card" style={{padding:'12px 16px'}}>
            <div style={{display:'flex',alignItems:'center',justifyContent:'space-between'}}>
              <div>
                <div style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink)'}}>Last synced</div>
                <div className="s" style={{marginTop:2}}>Just now</div>
              </div>
              <div style={{textAlign:'right'}}>
                <div style={{fontFamily:'var(--mono)',fontSize:14,color:'var(--ink)'}}>3 devices</div>
                <div className="s" style={{marginTop:2}}>iPhone · Mac · iPad</div>
              </div>
            </div>
            <div style={{marginTop:14,paddingTop:14,borderTop:'1px solid var(--line-2)',display:'flex',alignItems:'center',justifyContent:'space-between'}}>
              <span style={{fontFamily:'var(--mono)',fontSize:13,color:'var(--ink-2)'}}>Sync data</span>
              <span className="cc-toggle on"><span className="knob"/></span>
            </div>
          </div>

          <div className="cc-sec">synced data types<span className="rule"/></div>
          <div className="cc-card">
            {types.map(([label,on],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <span style={{color:on?'var(--r-low)':'var(--ink-4)'}}><Ic d={ICON.check} s={14}/></span>
                <div className="grow"><div className="t" style={{fontSize:14}}>{label}</div></div>
                {!on&&<span className="cc-note">not synced</span>}
              </div>
            ))}
          </div>

          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.lock} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Data is encrypted end-to-end by iCloud. Provider API keys and the audit log are never uploaded.</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- Policy YAML editor with bridge reload ---------- */
function PolicyEditorView(){
  const yaml=[
    ['default: ask','k'],
    ['rules:','k'],
    ['  - match: {tool: read}      effect: allow','a'],
    ['  - match: {tool: write, path: "*.{ts,swift,go}"}','a'],
    ['    effect: allow','a'],
    ['  - match: {tool: delete}    effect: ask','m'],
    ['  - match: {tool: network}   effect: ask','m'],
    ['  - match: {path: ".env"}    effect: deny','d'],
    ['  - match: {tool: command, input: "rm -rf /"}','d'],
    ['    effect: deny','d'],
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
                <div key={i} style={{color:k==='k'?'var(--ink-2)':k==='a'?'var(--r-low)':k==='m'?'var(--r-med)':'var(--r-crit)'}}>{t}</div>
              ))}
            </div>
          </div>
          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.shield} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Validated on save. The bridge reloads in place — running agents pick up new rules on their next decision call.</span>
          </div>
          <p className="cc-note" style={{margin:'10px 4px 0'}}>Editing is enabled only while the bridge is connected.</p>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <div className="cc-foot">
        <div className="cc-btnrow">
          <button className="cc-btn cc-btn--quiet" style={{flex:1}}>Discard</button>
          <button className="cc-btn cc-btn--primary" style={{flex:1.5}}><Ic d={ICON.refresh} s={15}/>Save &amp; reload bridge</button>
        </div>
      </div>
    </div>
  );
}

/* ---------- Extended XIC icons --------- */
const XIC5 = {
  refresh:<><path d="M21 12a9 9 0 1 1-3-6.7"/><path d="M21 4v5h-5"/></>,
  sliders:<><path d="M4 7h9M17 7h3M4 12h3M11 12h9M4 17h7M15 17h5"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="13" cy="17" r="2"/></>,
};

/* ---------- Secrets vault + pending requests ---------- */
function SecretsView(){
  const secrets=[
    ['GITHUB_TOKEN','env','global','ok'],
    ['ANTHROPIC_API_KEY','env','claude agent','ok'],
    ['OPENAI_API_KEY','env','codex agent','ok'],
    ['deploy-cert.pem','file','ci-runner','ok'],
    ['MASTER_DB_URL','env','global','warn'],
  ];
  const pending=[
    ['claude agent','read GITHUB_TOKEN'],
    ['codex agent','read deploy-cert.pem'],
  ];
  return (
    <div className="cc">
      <SubNav title="secrets"/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Stored secrets are available to agents by policy. Pending requests show what agents are asking for.</p>

          <div className="cc-sec">stored secrets <span className="n">· {secrets.length}</span><span className="rule"/></div>
          <div className="cc-card">
            {secrets.map(([name,type,scope,status],i)=>(
              <div key={i} className="cc-row" style={{cursor:'pointer'}}>
                <span style={{color:'var(--ink-3)',flex:'none'}}><Ic d={ICON.lock} s={14}/></span>
                <div className="grow" style={{minWidth:0}}>
                  <div className="t" style={{fontSize:14,fontFamily:'var(--mono)'}}>{name}</div>
                  <div className="s" style={{display:'flex',gap:6}}>
                    <span style={{fontFamily:'var(--mono)',fontSize:10,color:'var(--ink-4)'}}>{type}</span>
                    <span style={{color:'var(--ink-4)'}}>·</span>
                    <span>{scope}</span>
                  </div>
                </div>
                <span className="cc-sd"><span className={'d '+(status==='warn'?'waiting':'done')}/></span>
              </div>
            ))}
          </div>

          {pending.length>0&&<>
            <div className="cc-sec">pending requests <span className="n">· {pending.length}</span><span className="rule"/></div>
            <div className="cc-card">
              {pending.map(([agent,action],i)=>(
                <div key={i} className="cc-row" style={{cursor:'default'}}>
                  <PixelAvatar seed={agent} size={26} color={VENDOR.claude.c}/>
                  <div className="grow">
                    <div className="t" style={{fontSize:14}}><b style={{fontFamily:'var(--mono)',fontWeight:500}}>{agent}</b> wants to {action}</div>
                  </div>
                  <button className="cc-btn cc-btn--quiet" style={{height:32,minHeight:32,padding:'0 10px',fontSize:11}}>review</button>
                </div>
              ))}
            </div>
          </>}

          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.shield} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Secrets are redacted from command output automatically. Agents must match a policy rule to access them.</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
      <button className="cc-fab"><Ic d={ICON.plus} s={22}/></button>
    </div>
  );
}

/* ---------- Audit trail ---------- */
function AuditView(){
  const groups=[
    {label:'Today',rows:[
      {t:'09:15',act:'escalate',vendor:'claude',cmd:'patch session.swift',rule:'ask-on-write',hash:true},
      {t:'09:14',act:'auto-deny',vendor:'codex',cmd:'curl … | sh',rule:'deny-network',hash:true},
      {t:'09:12',act:'auto-allow',vendor:'claude',cmd:'ls -la',rule:'allow-read-only',hash:true},
      {t:'08:47',act:'you-allow',vendor:'claude',cmd:'npm run build',rule:'manual',hash:false},
      {t:'08:30',act:'dispatch',vendor:'claude',cmd:'"run the nightly test suite"',rule:'schedule',hash:true},
    ]},
    {label:'Yesterday',rows:[
      {t:'23:18',act:'auto-allow',vendor:'claude',cmd:'swift test',rule:'allow-read-only',hash:true},
      {t:'22:03',act:'auto-deny',vendor:'opencode',cmd:'rm -rf /',rule:'deny-destructive',hash:true},
      {t:'20:55',act:'you-allow',vendor:'codex',cmd:'patch src/auth/oauth.swift',rule:'manual',hash:true},
    ]},
    {label:'This Week',rows:[
      {t:'Mon 14:22',act:'auto-deny',vendor:'claude',cmd:'curl api.stripe.com | sh',rule:'deny-network',hash:false},
      {t:'Sun 09:10',act:'escalate',vendor:'codex',cmd:'delete prod db row',rule:'ask-on-delete',hash:true},
    ]},
  ];
  return (
    <div className="cc">
      <SubNav title="audit" right={<span className="cc-chip"><Ic d={ICON.lock} s={12}/>tamper-evident</span>}/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Every decision is recorded in a tamper-evident chain. Verify integrity at any time.</p>

          {groups.map((g,gi)=>(
            <div key={gi}>
              <div className="cc-sec">{g.label}<span className="rule"/></div>
              <div className="cc-card">
                {g.rows.map((r,i)=>(
                  <div key={i} className="cc-row" style={{cursor:'default'}}>
                    <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-4)',width:42,flex:'none'}}>{r.t}</span>
                    <span className={'cc-sd '+(r.hash?'':'')} style={{gap:4}}>
                      <span className="d" style={{width:6,height:6,borderRadius:'50%',background:r.hash?'var(--r-low)':'var(--r-med)'}}/>
                    </span>
                    <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:'var(--ink-3)',width:60,flex:'none',textTransform:'uppercase',letterSpacing:'.04em'}}>{r.act}</span>
                    <PixelAvatar seed={r.vendor+r.cmd} size={18} color={VENDOR[r.vendor]?.c||'var(--ink-4)'}/>
                    <div className="grow" style={{minWidth:0}}>
                      <span style={{fontFamily:'var(--mono)',fontSize:11.5,color:'var(--ink)'}}>{r.cmd}</span>
                    </div>
                    <span style={{fontFamily:'var(--mono)',fontSize:9.5,color:'var(--ink-4)',border:'1px solid var(--line)',borderRadius:2,padding:'1px 5px',flex:'none'}}>{r.rule}</span>
                  </div>
                ))}
              </div>
            </div>
          ))}

          <button className="cc-btn cc-btn--ghost cc-btn--block" style={{marginTop:14}}><Ic d={ICON.shield} s={15}/>Verify chain integrity</button>
          <p className="cc-note" style={{textAlign:'center',margin:'12px 4px 0'}}>The hash chain is anchored to your device's Secure Enclave. Any tampering is detected immediately.</p>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- Doctor / health check ---------- */
function DoctorView(){
  const checks=[
    ['Daemon version','lancerd v1.0.2','ok'],
    ['Hook installed','shell-integration hook active','ok'],
    ['API keys configured','Anthropic, OpenAI, OpenRouter','ok'],
    ['Policy valid','9 rules · valid YAML','ok'],
    ['Host reachable','dev-vps · ping 4ms','ok'],
    ['Relay connected','wss://relay.conduit.dev','ok'],
    ['iCloud sync','last sync just now','ok'],
    ['Disk space','12 GB free','warn'],
    ['Latest version','v1.1.1 available','warn'],
  ];
  return (
    <div className="cc">
      <SubNav title="doctor"/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Run diagnostics to verify your Lancer setup is healthy. Any failures are highlighted for investigation.</p>
          <div className="cc-card">
            {checks.map(([check,detail,status],i)=>(
              <div key={i} className="cc-row" style={{cursor:'default'}}>
                <span className="cc-sd" style={{gap:6}}>
                  <span className={'d '+(status==='ok'?'done':status==='warn'?'waiting':'error')}/>
                </span>
                <div className="grow" style={{minWidth:0}}>
                  <div className="t" style={{fontSize:14}}>{check}</div>
                  <div className="s" style={{whiteSpace:'normal'}}>{detail}</div>
                </div>
                <span style={{fontFamily:'var(--mono)',fontSize:10.5,color:status==='ok'?'var(--r-low)':'var(--r-med)'}}>{status==='ok'?'pass':status}</span>
              </div>
            ))}
          </div>

          <button className="cc-btn cc-btn--primary cc-btn--block" style={{marginTop:14,height:52}}><Ic d={XIC5.refresh} s={16}/>Run all checks</button>
          <div className="cc-card" style={{marginTop:12,padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
            <Ic d={ICON.shield} s={16}/>
            <span style={{fontSize:12.5,color:'var(--ink-2)',lineHeight:1.5}}>Checks run locally on your device and the connected bridge. Nothing is sent to a remote server.</span>
          </div>
        </div>
        <div className="cc-bottompad"/>
      </div>
    </div>
  );
}

/* ---------- SSH key management (expanded) ---------- */
function KeysView(){
  const keys=[
    {name:'lancer-dev',fp:'SHA256:k7Hf3…Lm2',host:'dev-vps',used:'used 2h ago'},
    {name:'ci-runner',fp:'SHA256:9aQ2x…pR8',host:'staging',used:'used Jun 11'},
    {name:'personal-mac',fp:'SHA256:bx4Ff…Zw1',host:'MacBook Pro',used:'used 3d ago'},
    {name:'backup-gateway',fp:'SHA256:q3ZvW…Dt9',host:'gateway-01',used:'never'},
    {name:'pi-cluster',fp:'SHA256:mN7cB…Gk4',host:'Raspberry Pi 5',used:'used 2h ago'},
  ];
  return (
    <div className="cc">
      <SubNav title="ssh keys"/>
      <div className="cc-scroll">
        <div className="cc-pad" style={{paddingTop:10}}>
          <p className="cc-lead" style={{margin:'0 0 12px'}}>Keys for reaching your hosts over SSH — the advanced path. Generated on-device and held in the Keychain; the private key never leaves this phone.</p>
          <div className="cc-card">
            {keys.map((k,i)=>(
              <SshKeyRow key={i} name={k.name} fp={k.fp} used={k.used} host={k.host}/>
            ))}
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

Object.assign(window,{
  TerminalSettingsView,E2ERelayPairingView,TrustPrivacyView,PremiumComparisonView,
  BillingView,ProviderKeysView,ShortcutBarEditor,SnippetEditorView,
  SyncStatusView,PolicyEditorView,SecretsView,AuditView,DoctorView,KeysView,
});
