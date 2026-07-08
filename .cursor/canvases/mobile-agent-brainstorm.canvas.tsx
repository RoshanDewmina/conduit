/**
 * Mobile Agent Mission Control — FULL brainstorm compilation
 * Sessions: Cursor brainstorm · Fable ideas · deep spec · competitors · iOS 27 · lfg VPS
 * Open in Cursor Canvas panel
 */
import {
  BarChart,
  Button,
  Callout,
  Card,
  CardBody,
  CardHeader,
  CollapsibleSection,
  Divider,
  Grid,
  H1,
  H3,
  Pill,
  Row,
  Spacer,
  Stack,
  Stat,
  Table,
  Text,
  TodoListCard,
  computeDAGLayout,
  mergeStyle,
  useCanvasState,
  useHostTheme,
  type TodoItem,
} from 'cursor/canvas';

const PHONE = { w: 255, h: 540, bg: '#fbfbfa', ink: '#171717', muted: '#6f6f6f', line: '#ececea', accent: '#158bc0', ok: '#12966b', warn: '#d18b2b', danger: '#c92457' };
type Section = 'overview' | 'wireframes' | 'specs' | 'personas' | 'steals' | 'wild' | 'mvp';

function PhoneFrame({ label, children, badge }: { label: string; children: JSX.Element; badge?: string }) {
  return (
    <Stack gap={8} style={{ alignItems: 'center', flex: '0 0 auto' }}>
      <Text tone="secondary" style={{ fontSize: 10, fontFamily: 'ui-monospace, monospace', maxWidth: PHONE.w, textAlign: 'center' }}>{label}</Text>
      <div style={{ width: PHONE.w, height: PHONE.h, borderRadius: 34, border: '1px solid #dedede', background: PHONE.bg, boxShadow: '0 16px 40px rgba(20,20,18,.14)', overflow: 'hidden', position: 'relative', color: PHONE.ink, fontFamily: '-apple-system, system-ui, sans-serif' }}>
        <div style={{ padding: '14px 18px 0', display: 'flex', justifyContent: 'space-between', fontSize: 11, fontWeight: 700 }}><span>9:41</span><span style={{ opacity: 0.45 }}>●●●</span></div>
        {badge && <div style={{ position: 'absolute', top: 44, right: 10, fontSize: 9, fontWeight: 700, padding: '2px 7px', borderRadius: 999, background: 'rgba(21,139,192,.12)', color: PHONE.accent }}>{badge}</div>}
        {children}
      </div>
    </Stack>
  );
}

function TabBar({ active }: { active: number }) {
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 68, borderTop: `1px solid ${PHONE.line}`, background: 'rgba(255,255,255,.96)', display: 'flex', justifyContent: 'space-around', alignItems: 'center', paddingBottom: 6, fontSize: 9, fontWeight: 600 }}>
      {['Home', 'Workspaces', 'Settings'].map((t, i) => <span key={t} style={{ color: i === active ? PHONE.accent : PHONE.muted }}>{t}</span>)}
    </div>
  );
}

function Chip({ children, accent }: { children: string; accent?: boolean }) {
  return <span style={{ display: 'inline-block', fontSize: 9, fontWeight: 600, padding: '3px 7px', borderRadius: 999, marginRight: 3, marginBottom: 3, border: `1px solid ${accent ? PHONE.accent : '#d8d8d5'}`, background: accent ? 'rgba(21,139,192,.1)' : '#fff', color: accent ? PHONE.accent : PHONE.muted }}>{children}</span>;
}

function ArtifactCard({ title, body, tone }: { title: string; body: string; tone?: 'ok' | 'warn' | 'info' }) {
  const border = tone === 'ok' ? PHONE.ok : tone === 'warn' ? PHONE.warn : PHONE.line;
  return (
    <div style={{ border: `1px solid ${border}`, borderRadius: 10, padding: '8px 10px', marginBottom: 6, background: '#fff' }}>
      <div style={{ fontSize: 10, fontWeight: 700, marginBottom: 2, color: tone === 'ok' ? PHONE.ok : tone === 'warn' ? PHONE.warn : PHONE.ink }}>{title}</div>
      <div style={{ fontSize: 10, color: PHONE.muted, lineHeight: 1.3 }}>{body}</div>
    </div>
  );
}

const strip = { display: 'flex', gap: 16, overflowX: 'auto', padding: '8px 4px 16px', alignItems: 'flex-start' } as const;

function WfHomeDigest() {
  return (
    <PhoneFrame label="01 · Away Digest" badge="HOME">
      <div style={{ padding: '6px 16px 0', fontSize: 18, fontWeight: 760 }}>Mission control</div>
      <div style={{ padding: '0 16px', height: 340 }}>
        <div style={{ fontSize: 11, color: PHONE.muted, margin: '10px 0 6px' }}>Needs you</div>
        <ArtifactCard title="⚠ Approval · 3 files" body="High risk · VPS" tone="warn" />
        <div style={{ fontSize: 11, color: PHONE.muted, margin: '10px 0 6px' }}>Running</div>
        <ArtifactCard title="● Fix auth redirect" body="Claude · 4m · +42 −3" />
        <div style={{ fontSize: 11, color: PHONE.muted, margin: '10px 0 6px' }}>Done</div>
        <ArtifactCard title="✓ Dependency audit" body="Proof ready · 3/3" tone="ok" />
      </div>
      <div style={{ position: 'absolute', left: 12, right: 12, bottom: 76, height: 42, borderRadius: 22, border: '1px solid #d8d8d5', background: '#fff', display: 'flex', alignItems: 'center', padding: '0 10px', fontSize: 13, color: '#a7a7a4' }}>Plan, ask, build…</div>
      <TabBar active={0} />
    </PhoneFrame>
  );
}

function WfLaunchContract() {
  return (
    <PhoneFrame label="02 · Launch + Plan gate" badge="MVP">
      <div style={{ padding: '10px 16px 0', fontSize: 15, fontWeight: 700 }}>New mission</div>
      <div style={{ padding: '6px 16px' }}>
        <div style={{ fontSize: 12, border: `1px dashed ${PHONE.line}`, borderRadius: 8, padding: 8, marginBottom: 8 }}>Fix flaky auth test…</div>
        <Chip accent>repo</Chip><Chip accent>host</Chip><Chip>Claude</Chip><Chip accent>Plan first</Chip>
        <ArtifactCard title="📋 Plan (approve before code)" body="Scope: auth.test.ts · Risk: low" tone="info" />
      </div>
      <div style={{ position: 'absolute', left: 14, right: 14, bottom: 80, height: 36, borderRadius: 18, background: PHONE.accent, color: '#fff', display: 'grid', placeItems: 'center', fontWeight: 700, fontSize: 13 }}>Approve plan → dispatch</div>
      <TabBar active={0} />
    </PhoneFrame>
  );
}

function WfArtifactStream() {
  return (
    <PhoneFrame label="03 · Artifact stream (#1)" badge="FOUNDATION">
      <div style={{ padding: '8px 16px', borderBottom: `1px solid ${PHONE.line}`, fontSize: 14, fontWeight: 700 }}>Fix auth <span style={{ color: PHONE.ok, fontSize: 10 }}>● running</span></div>
      <div style={{ padding: '8px 16px 72px' }}>
        <ArtifactCard title="📋 Plan" body="Fix timeout in auth.test.ts" tone="info" />
        <ArtifactCard title="✏️ Files" body="2 changed" />
        <ArtifactCard title="▶ Tests" body="11/12 · 1 failing" tone="warn" />
        <ArtifactCard title="❓ Question" body="Mock Redis or container?" tone="warn" />
        <ArtifactCard title="✓ Done" body="All green" tone="ok" />
      </div>
      <TabBar active={1} />
    </PhoneFrame>
  );
}

function WfQuestionCard() {
  return (
    <PhoneFrame label="04 · Question card" badge="TAP">
      <div style={{ padding: '10px 16px' }}>
        <div style={{ border: `2px solid ${PHONE.warn}`, borderRadius: 12, padding: 12, background: 'rgba(209,139,43,.08)' }}>
          <div style={{ fontSize: 10, fontWeight: 700, color: PHONE.warn }}>NEEDS YOU</div>
          <div style={{ fontSize: 13, fontWeight: 600, margin: '8px 0' }}>REST or GraphQL?</div>
          {['REST (recommended)', 'GraphQL', 'At desk'].map((o, i) => (
            <div key={o} style={{ padding: '8px 10px', borderRadius: 8, border: `1px solid ${i === 0 ? PHONE.accent : PHONE.line}`, marginBottom: 4, fontSize: 12 }}>{o}</div>
          ))}
        </div>
      </div>
      <TabBar active={1} />
    </PhoneFrame>
  );
}

function WfLockApprove() {
  return (
    <PhoneFrame label="05 · Live Activity + lock approve (#2)" badge="iOS">
      <div style={{ padding: '50px 16px 0', textAlign: 'center' }}>
        <div style={{ fontSize: 42, fontWeight: 200 }}>9:41</div>
        <div style={{ margin: '16px 0', borderRadius: 14, border: `1px solid ${PHONE.warn}`, padding: 12, background: 'rgba(255,255,255,.95)', textAlign: 'left' }}>
          <div style={{ fontSize: 10, fontWeight: 700, color: PHONE.warn }}>NEEDS YOU · Write tier</div>
          <div style={{ fontSize: 13, fontWeight: 600, margin: '6px 0' }}>Modify 3 files in /src/auth</div>
          <div style={{ display: 'flex', gap: 6, marginTop: 10 }}>
            <div style={{ flex: 1, height: 32, borderRadius: 16, border: `1px solid ${PHONE.line}`, display: 'grid', placeItems: 'center', fontSize: 11 }}>Deny</div>
            <div style={{ flex: 1, height: 32, borderRadius: 16, background: PHONE.accent, color: '#fff', display: 'grid', placeItems: 'center', fontSize: 11, fontWeight: 700 }}>🔒 Approve</div>
          </div>
        </div>
        <div style={{ fontSize: 10, color: PHONE.muted }}>Island: running → needs you</div>
      </div>
    </PhoneFrame>
  );
}

function WfProofVideo() {
  return (
    <PhoneFrame label="06 · Proof video + annotate (#3)" badge="DEMO">
      <div style={{ padding: '8px 16px', fontSize: 14, fontWeight: 700 }}>Proof · checkout</div>
      <div style={{ margin: '0 16px', height: 110, borderRadius: 10, background: '#e0e0dd', position: 'relative' }}>
        <div style={{ position: 'absolute', bottom: 8, left: 8, right: 8, height: 4, borderRadius: 2, background: 'rgba(0,0,0,.12)' }}>
          <div style={{ width: '40%', height: '100%', background: PHONE.accent, borderRadius: 2 }} />
        </div>
        <div style={{ position: 'absolute', top: 36, left: 48, width: 48, height: 28, border: `2px solid ${PHONE.danger}`, borderRadius: 4 }} />
      </div>
      <div style={{ padding: '8px 16px' }}>
        <div style={{ height: 26, borderRadius: 13, border: `1px solid ${PHONE.line}`, padding: '0 10px', fontSize: 11, color: PHONE.muted, display: 'flex', alignItems: 'center' }}>🔍 search "submit"</div>
        <div style={{ fontSize: 10, color: PHONE.muted, marginTop: 6 }}>🎤 feedback → {`{ts, region, note}`}</div>
      </div>
      <div style={{ position: 'absolute', left: 14, right: 14, bottom: 76, height: 34, borderRadius: 17, background: PHONE.accent, color: '#fff', display: 'grid', placeItems: 'center', fontSize: 12, fontWeight: 700 }}>Send feedback</div>
      <TabBar active={1} />
    </PhoneFrame>
  );
}

function WfCheckpoint() {
  return (
    <PhoneFrame label="07 · Checkpoint + burn (#6)" badge="TRUST">
      <div style={{ padding: '8px 16px', fontSize: 14, fontWeight: 700 }}>Session</div>
      <div style={{ padding: '0 16px' }}>
        <ArtifactCard title="📋 Plan" body="Checkpoint 1" />
        <div style={{ fontSize: 9, color: PHONE.accent, margin: '4px 0' }}>⬤ tap to revert here</div>
        <ArtifactCard title="✏️ Bad edit" body="Revert 4 changes?" tone="warn" />
      </div>
      <div style={{ position: 'absolute', left: 14, right: 14, bottom: 76, height: 34, borderRadius: 17, border: `2px solid ${PHONE.danger}`, color: PHONE.danger, display: 'grid', placeItems: 'center', fontSize: 11, fontWeight: 700 }}>🔥 Burn all</div>
      <TabBar active={1} />
    </PhoneFrame>
  );
}

function WfRecapPacket() {
  return (
    <PhoneFrame label="08 · Recap packet (#7)" badge="RE-ENTRY">
      <div style={{ padding: '10px 16px', fontSize: 15, fontWeight: 700 }}>Recap</div>
      <div style={{ padding: '0 16px', fontSize: 12, lineHeight: 1.5 }}>
        <div style={{ fontWeight: 700 }}>Changed</div><div style={{ color: PHONE.muted, marginBottom: 8 }}>OAuth staging · +42 −3</div>
        <div style={{ fontWeight: 700 }}>Proven</div><div style={{ color: PHONE.ok, marginBottom: 8 }}>12/12 tests · video</div>
        <div style={{ fontWeight: 700 }}>Open</div><div style={{ color: PHONE.warn }}>1 PR comment</div>
      </div>
      <TabBar active={1} />
    </PhoneFrame>
  );
}

function WfProofRollup() {
  return (
    <PhoneFrame label="09 · Proof rollup" badge="GATE">
      <div style={{ padding: '10px 16px', fontSize: 14, fontWeight: 700 }}>3 of 4 passed</div>
      <div style={{ padding: '0 16px' }}>
        <ArtifactCard title="✓ Tests" body="12/12" tone="ok" />
        <ArtifactCard title="⚠ Visual" body="review" tone="warn" />
      </div>
      <div style={{ position: 'absolute', left: 14, right: 14, bottom: 76, height: 34, borderRadius: 17, background: '#999', color: '#fff', display: 'grid', placeItems: 'center', fontSize: 12, opacity: 0.5 }}>Mark ready (blocked)</div>
      <TabBar active={1} />
    </PhoneFrame>
  );
}

function WfVPSSetup() {
  return (
    <PhoneFrame label="10 · VPS pair (lfg floor)" badge="SETUP">
      <div style={{ padding: '16px', textAlign: 'center' }}>
        <div style={{ fontSize: 14, fontWeight: 700 }}>Pair host</div>
        <div style={{ width: 110, height: 110, margin: '12px auto', border: `1px solid ${PHONE.line}`, borderRadius: 8, display: 'grid', placeItems: 'center', fontSize: 10, color: PHONE.muted }}>QR</div>
        <div style={{ fontSize: 10, color: PHONE.muted }}>curl | bash · tailscale serve · tmux</div>
        <div style={{ marginTop: 10, fontSize: 10, color: PHONE.accent }}>Beat lfg: push + artifacts + Live Activity</div>
      </div>
      <TabBar active={2} />
    </PhoneFrame>
  );
}

function WfTestBench() {
  return (
    <PhoneFrame label="11 · Test bench (DEFER #4)" badge="POST">
      <div style={{ margin: '8px 16px', height: 300, borderRadius: 10, border: `1px solid ${PHONE.line}`, background: '#fff' }} />
      <div style={{ fontSize: 10, color: PHONE.muted, textAlign: 'center' }}>Shake → annotate → bug report</div>
      <TabBar active={1} />
    </PhoneFrame>
  );
}

function WfBranchTaste() {
  return (
    <PhoneFrame label="12 · Branch tasting (DEFER W4)" badge="WILD">
      <div style={{ padding: '10px 16px', fontSize: 14, fontWeight: 700 }}>Pick winner</div>
      <div style={{ padding: '0 16px', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
        {['REST', 'GraphQL'].map((b) => (
          <div key={b} style={{ border: `1px solid ${PHONE.line}`, borderRadius: 10, padding: 8, fontSize: 10 }}>
            <div style={{ fontWeight: 700 }}>{b}</div>
            <div style={{ height: 36, background: '#e8e8e6', borderRadius: 4, margin: '4px 0' }} />
            <div style={{ color: PHONE.ok }}>✓ 12 tests</div>
          </div>
        ))}
      </div>
      <TabBar active={1} />
    </PhoneFrame>
  );
}

const TOP7 = [
  { n: 1, name: 'Artifact stream', mvp: '5 card types from host events', risk: 'CLI parser drift' },
  { n: 2, name: 'Live Activity + lock approve', mvp: 'Fleet state + Face ID tiers', risk: 'Approval fatigue' },
  { n: 3, name: 'Proof video + annotate', mvp: 'Playwright + search + feedback object', risk: 'Big build; web only' },
  { n: 4, name: 'Test bench + shake', mvp: 'CUT — open URL is free', risk: 'Thin vs Safari' },
  { n: 5, name: 'Speculative queue', mvp: 'CUT — queue in question cards', risk: 'Cost blowups' },
  { n: 6, name: 'Checkpoint + burn', mvp: 'Git snapshot + kill all', risk: 'Worktree only' },
  { n: 7, name: 'Recap packet', mvp: '4 sections; Handoff later', risk: 'Underwhelm' },
];

const PERSONA_ROWS = [
  ['Feature', 'Solo', 'Team', 'VPS'],
  ['1 Artifact stream', '1', '2', '1'],
  ['2 Lock approve', '2', '4', '2'],
  ['3 Proof annotate', '4', '1', '3'],
  ['6 Checkpoint', '3', '3', '4'],
  ['7 Recap', '5', '5', '5'],
  ['4 Test bench', '6', '6', '6'],
  ['5 Speculative', '7', '7', '7'],
];

const STEALS = [
  { s: 'Conductor', ok: 'Workspace=PR · Plan mode · Checks tab', no: 'Desktop UI' },
  { s: 'Claude RC', ok: 'QR · push modes · metadata', no: 'Chat mirror' },
  { s: 'Codex', ok: 'Decision console · stream · Face ID', no: 'Computer Use V1' },
  { s: 'Cursor iOS', ok: 'Inbox · lock taxonomy', no: 'Single vendor' },
  { s: 'Omnara', ok: 'Voice · preview · worktrees', no: 'Weak governance' },
  { s: 'lfg', ok: 'curl · tailscale · tmux · multi-CLI', no: 'Re-ship PWA' },
  { s: 'iOS 27', ok: 'Siri · Annotations · on-device summary', no: 'Gimmick APIs' },
];

const WILD = ['Agent parliament', 'Speculative branches (W3)', 'Branch tasting (W4)', 'Phone test device (W1)', 'On-call 2am card', 'Audio morning briefing', 'Commute offline queue', 'Two-key deploy', 'Proof → regression', 'Whiteboard-to-plan'];
const REJECTS = ['Phone terminal', 'Chat bubbles', 'Agent mood', 'Per-agent spam', 'AR viz', 'Streaks', 'Mobile editing', 'Geofence dispatch', 'Fleet kanban'];

const MVP_ITEMS: TodoItem[] = [
  { id: '1', content: 'Ship: Artifact stream', status: 'in_progress' },
  { id: '2', content: 'Ship: Live Activity + lock approve', status: 'pending' },
  { id: '3', content: 'Ship: Checkpoint + burn', status: 'pending' },
  { id: '4', content: 'Ship: Recap packet', status: 'pending' },
  { id: '5', content: 'Fast-follow: Proof video + annotate', status: 'pending' },
  { id: 'c1', content: 'Cut: Speculative queue', status: 'cancelled' },
  { id: 'c2', content: 'Cut: Test bench (defer)', status: 'cancelled' },
];

const FLOW = computeDAGLayout({
  nodes: [{ id: 'Digest' }, { id: 'Launch' }, { id: 'Stream' }, { id: 'Proof' }, { id: 'Approve' }, { id: 'Ship' }],
  edges: [{ from: 'Digest', to: 'Launch' }, { from: 'Launch', to: 'Stream' }, { from: 'Stream', to: 'Proof' }, { from: 'Stream', to: 'Approve' }, { from: 'Proof', to: 'Ship' }, { from: 'Approve', to: 'Stream' }, { from: 'Ship', to: 'Digest' }],
  direction: 'horizontal', nodeWidth: 64, nodeHeight: 26, rankGap: 22, nodeGap: 8,
});

function FlowDiagram() {
  const theme = useHostTheme();
  return (
    <div style={{ position: 'relative', width: FLOW.width, height: FLOW.height, margin: '0 auto' }}>
      <svg width={FLOW.width} height={FLOW.height} style={{ position: 'absolute', inset: 0 }}>
        {FLOW.edges.map((e, i) => <path key={i} d={e.path} fill="none" stroke={e.isBackEdge ? theme.accent : theme.border} strokeWidth={1.5} strokeDasharray={e.isBackEdge ? '4 3' : undefined} />)}
      </svg>
      {FLOW.nodes.map((n) => <div key={n.id} style={{ position: 'absolute', left: n.x, top: n.y, width: n.width, height: n.height, borderRadius: 6, border: `1px solid ${theme.border}`, background: theme.surface, display: 'grid', placeItems: 'center', fontSize: 9, fontWeight: 700 }}>{n.id}</div>)}
    </div>
  );
}

const SECTIONS: { key: Section; label: string }[] = [
  { key: 'overview', label: 'Overview' }, { key: 'wireframes', label: 'Wireframes' }, { key: 'specs', label: 'Top 7' },
  { key: 'personas', label: 'Personas' }, { key: 'steals', label: 'Steals' }, { key: 'wild', label: 'Wild' }, { key: 'mvp', label: 'MVP' },
];

export default function MobileAgentBrainstormCanvas() {
  const [section, setSection] = useCanvasState<Section>('mc.section', 'overview');
  const theme = useHostTheme();
  const show = (s: Section) => section === 'overview' || section === s;

  return (
    <Stack gap={16}>
      <div>
        <H1>Mobile Agent Mission Control</H1>
        <Text tone="secondary">Full compilation · Cursor + Fable brainstorms · 2026-07-07</Text>
        <Row gap={6} style={{ marginTop: 10, flexWrap: 'wrap' }}>
          {SECTIONS.map(({ key, label }) => <Button key={key} variant={section === key ? 'filled' : 'outline'} onClick={() => setSection(key)}>{label}</Button>)}
        </Row>
      </div>

      {show('overview') && (
        <>
          <Callout tone="info" title="Principle">Phone = judgment instrument, not smaller IDE. Convert reading code into making a call.</Callout>
          <Callout tone="success" title="MVP pitch">Agent keeps working · lock-screen permission · undo from pocket · recap when back.</Callout>
          <Grid columns={4} gap={10}>
            <Stat value={12} label="Wireframes" tone="info" />
            <Stat value={7} label="Top features" tone="neutral" />
            <Stat value={3} label="Personas" tone="success" />
            <Stat value="lfg" label="VPS floor" tone="warning" />
          </Grid>
          <Card><CardHeader>Flow</CardHeader><CardBody><FlowDiagram /></CardBody></Card>
          <Card>
            <CardHeader>lfg floor — beat, don't re-ship</CardHeader>
            <CardBody>
              <Text tone="secondary" style={{ fontSize: 13 }}>curl → loopback → tailscale serve → tmux → PWA. We win with: APNs push, Live Activity, artifact cards, proof annotate, lock approve.</Text>
            </CardBody>
          </Card>
        </>
      )}

      {show('wireframes') && (
        <CollapsibleSection title="12 wireframes (scroll →)" defaultOpen>
          <div style={strip}>
            <WfHomeDigest /><WfLaunchContract /><WfArtifactStream /><WfQuestionCard />
            <WfLockApprove /><WfProofVideo /><WfCheckpoint /><WfRecapPacket />
            <WfProofRollup /><WfVPSSetup /><WfTestBench /><WfBranchTaste />
          </div>
        </CollapsibleSection>
      )}

      {show('specs') && (
        <Card>
          <CardHeader>Fable top 7 specs</CardHeader>
          <CardBody>
            <Stack gap={8}>
              {TOP7.map((s) => (
                <div key={s.n} style={mergeStyle({ border: `1px solid ${theme.border}`, borderRadius: 10, padding: 10, background: theme.surface })}>
                  <Pill tone="info">#{s.n} {s.name}</Pill>
                  <Text tone="secondary" style={{ fontSize: 12, marginTop: 4 }}>MVP: {s.mvp}</Text>
                  <Text tone="secondary" style={{ fontSize: 12 }}>Risk: {s.risk}</Text>
                </div>
              ))}
            </Stack>
          </CardBody>
        </Card>
      )}

      {show('personas') && (
        <>
          <Grid columns={3} gap={10}>
            {[
              { p: 'Solo', t: 'Stream · Lock approve · Checkpoint', pay: '$10/mo relay' },
              { p: 'Team', t: 'Proof annotate · Stream · Recap', pay: 'Per-seat audit' },
              { p: 'VPS', t: 'Stream · Lock · Proof video', pay: 'Open daemon + relay' },
            ].map((x) => (
              <div key={x.p} style={mergeStyle({ border: `1px solid ${theme.border}`, borderRadius: 10, padding: 12, background: theme.surface })}>
                <H3>{x.p}</H3>
                <Text tone="secondary" style={{ fontSize: 12 }}>{x.t}</Text>
                <Text tone="secondary" style={{ fontSize: 12 }}>{x.pay}</Text>
              </div>
            ))}
          </Grid>
          <Card><CardHeader>Rank by persona</CardHeader><CardBody><Table headers={PERSONA_ROWS[0]} rows={PERSONA_ROWS.slice(1)} /></CardBody></Card>
        </>
      )}

      {show('steals') && (
        <Card>
          <CardHeader>Competitor steals</CardHeader>
          <CardBody>
            {STEALS.map((x) => (
              <div key={x.s} style={{ marginBottom: 8, fontSize: 12 }}>
                <Pill tone="info">{x.s}</Pill> <Text tone="secondary">+ {x.ok} · − {x.no}</Text>
              </div>
            ))}
            <Divider />
            <BarChart title="Wedge vs parity" categories={['Approve', 'Proof', 'Policy', 'Audit', 'iOS']} series={[{ name: 'Market', data: [85, 70, 25, 15, 40], tone: 'neutral' }, { name: 'Us', data: [90, 85, 95, 90, 95], tone: 'info' }]} height={150} />
          </CardBody>
        </Card>
      )}

      {show('wild') && (
        <>
          <Card><CardHeader>Wild but useful</CardHeader><CardBody><Grid columns={2} gap={6}>{WILD.map((w) => <Pill key={w} tone="neutral">{w}</Pill>)}</Grid></CardBody></Card>
          <Card><CardHeader>Reject list</CardHeader><CardBody>{REJECTS.map((r) => <Text key={r} tone="secondary" style={{ fontSize: 12, display: 'block' }}>✕ {r}</Text>)}</CardBody></Card>
          <Callout tone="warning" title="Gold standard">Scrubbable proof video · annotate feedback · artifact stream · recurring tasks · Live Activity · weekly use only</Callout>
        </>
      )}

      {show('mvp') && (
        <>
          <Callout tone="success" title="MVP = #1+#2+#6+#7 → fast-follow #3">Cut #4 (open URL free) and #5 (queue in question cards).</Callout>
          <TodoListCard title="MVP checklist" items={MVP_ITEMS} />
          <Card>
            <CardHeader>Earlier themes (still valid)</CardHeader>
            <CardBody>
              <Text tone="secondary" style={{ fontSize: 12, lineHeight: 1.6 }}>
                Away Digest · Launch Contract · Question Cards · Proof Suite · Governance · Voice/camera · Share sheet · Repo Playbook · Flight Recorder · Cross-vendor verify · Emergency stop · 3-root IA
              </Text>
            </CardBody>
          </Card>
          <Card>
            <CardHeader>iOS 27 fast-follow</CardHeader>
            <CardBody>
              <Text tone="secondary" style={{ fontSize: 12, lineHeight: 1.6 }}>
                Siri + View Annotations · IndexedEntity/Spotlight · LongRunningIntent · on-device diff summary · Widget · Watch · StandBy · AppIntentsTesting
              </Text>
            </CardBody>
          </Card>
        </>
      )}

      <Text tone="tertiary" style={{ fontSize: 11 }}>.cursor/canvases/mobile-agent-brainstorm.canvas.tsx</Text>
      <Spacer size={16} />
    </Stack>
  );
}
