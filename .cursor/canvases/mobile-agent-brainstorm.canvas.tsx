/**
 * Mobile Agent Mission Control — brainstorm wireframes
 * Open in Cursor: Canvas panel → mobile-agent-brainstorm
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
  Text,
  computeDAGLayout,
  mergeStyle,
  useCanvasState,
  useHostTheme,
} from 'cursor/canvas';

/* ── phone chrome tokens (fixed light — like a screenshot) ── */
const PHONE = {
  w: 260,
  h: 560,
  bg: '#fbfbfa',
  ink: '#171717',
  muted: '#6f6f6f',
  line: '#ececea',
  accent: '#158bc0',
  ok: '#12966b',
  warn: '#d18b2b',
  danger: '#c92457',
  surface: '#ffffff',
};

const TAB_BAR = ['Home', 'Workspaces', 'Settings'];

function PhoneFrame({
  label,
  children,
  badge,
}: {
  label: string;
  children: JSX.Element;
  badge?: string;
}) {
  return (
    <Stack gap={8} style={{ alignItems: 'center', flex: '0 0 auto' }}>
      <Text tone="secondary" style={{ fontSize: 11, fontFamily: 'ui-monospace, monospace', letterSpacing: '0.04em' }}>
        {label}
      </Text>
      <div
        style={{
          width: PHONE.w,
          height: PHONE.h,
          borderRadius: 36,
          border: '1px solid #dedede',
          background: PHONE.bg,
          boxShadow: '0 18px 44px rgba(20,20,18,.16)',
          overflow: 'hidden',
          position: 'relative',
          color: PHONE.ink,
          fontFamily: '-apple-system, BlinkMacSystemFont, system-ui, sans-serif',
        }}
      >
        <div style={{ padding: '16px 20px 0', display: 'flex', justifyContent: 'space-between', fontSize: 12, fontWeight: 700 }}>
          <span>9:41</span>
          <span style={{ opacity: 0.5 }}>●●●</span>
        </div>
        {badge && (
          <div
            style={{
              position: 'absolute',
              top: 48,
              right: 12,
              fontSize: 10,
              fontWeight: 700,
              padding: '3px 8px',
              borderRadius: 999,
              background: 'rgba(21,139,192,.12)',
              color: PHONE.accent,
            }}
          >
            {badge}
          </div>
        )}
        {children}
      </div>
    </Stack>
  );
}

function TabBar({ active }: { active: number }) {
  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        bottom: 0,
        height: 72,
        borderTop: `1px solid ${PHONE.line}`,
        background: 'rgba(255,255,255,.95)',
        display: 'flex',
        justifyContent: 'space-around',
        alignItems: 'center',
        paddingBottom: 8,
        fontSize: 10,
        fontWeight: 600,
      }}
    >
      {TAB_BAR.map((t, i) => (
        <span key={t} style={{ color: i === active ? PHONE.accent : PHONE.muted }}>
          {t}
        </span>
      ))}
    </div>
  );
}

function LedgerRow({
  dot,
  title,
  meta,
  trailing,
}: {
  dot?: 'active' | 'warn' | 'idle';
  title: string;
  meta: string;
  trailing?: string;
}) {
  const dotColor = dot === 'active' ? PHONE.accent : dot === 'warn' ? PHONE.warn : '#d7d7d5';
  return (
    <div
      style={{
        display: 'grid',
        gridTemplateColumns: '12px 1fr auto',
        gap: 8,
        alignItems: 'start',
        paddingBottom: 10,
        marginBottom: 8,
        borderBottom: `1px solid ${PHONE.line}`,
      }}
    >
      <div style={{ width: 8, height: 8, borderRadius: '50%', background: dotColor, marginTop: 6 }} />
      <div>
        <div style={{ fontSize: 14, fontWeight: 600, marginBottom: 2 }}>{title}</div>
        <div style={{ fontSize: 11, color: PHONE.muted }}>{meta}</div>
      </div>
      {trailing && <div style={{ fontSize: 11, color: PHONE.muted, paddingTop: 14 }}>{trailing}</div>}
    </div>
  );
}

function Composer({ placeholder = 'Plan, ask, build…' }: { placeholder?: string }) {
  return (
    <div
      style={{
        position: 'absolute',
        left: 12,
        right: 12,
        bottom: 80,
        height: 46,
        borderRadius: 24,
        border: '1px solid #d8d8d5',
        background: 'rgba(255,255,255,.95)',
        display: 'flex',
        alignItems: 'center',
        gap: 8,
        padding: '0 10px',
        boxShadow: '0 8px 24px rgba(0,0,0,.08)',
      }}
    >
      <div style={{ width: 30, height: 30, borderRadius: '50%', background: '#ededeb', display: 'grid', placeItems: 'center', fontSize: 16 }}>+</div>
      <span style={{ flex: 1, color: '#a7a7a4', fontSize: 14 }}>{placeholder}</span>
      <div style={{ width: 30, height: 30, borderRadius: '50%', background: '#ededeb', display: 'grid', placeItems: 'center', fontSize: 14 }}>🎤</div>
    </div>
  );
}

function Chip({ children, accent }: { children: string; accent?: boolean }) {
  return (
    <span
      style={{
        display: 'inline-block',
        fontSize: 10,
        fontWeight: 600,
        padding: '4px 8px',
        borderRadius: 999,
        marginRight: 4,
        marginBottom: 4,
        border: `1px solid ${accent ? PHONE.accent : '#d8d8d5'}`,
        background: accent ? 'rgba(21,139,192,.1)' : '#fff',
        color: accent ? PHONE.accent : PHONE.muted,
      }}
    >
      {children}
    </span>
  );
}

function ArtifactCard({ title, body, tone }: { title: string; body: string; tone?: 'ok' | 'warn' | 'info' }) {
  const border = tone === 'ok' ? PHONE.ok : tone === 'warn' ? PHONE.warn : PHONE.line;
  return (
    <div style={{ border: `1px solid ${border}`, borderRadius: 12, padding: '10px 12px', marginBottom: 8, background: '#fff' }}>
      <div style={{ fontSize: 11, fontWeight: 700, marginBottom: 4, color: tone === 'ok' ? PHONE.ok : tone === 'warn' ? PHONE.warn : PHONE.ink }}>{title}</div>
      <div style={{ fontSize: 11, color: PHONE.muted, lineHeight: 1.35 }}>{body}</div>
    </div>
  );
}

/* ── screen wireframes ── */

function ScreenHomeDigest() {
  return (
    <PhoneFrame label="A · Away Digest (Home)" badge="CORE">
      <div style={{ padding: '8px 18px 0', fontSize: 20, fontWeight: 760 }}>conduit</div>
      <div style={{ padding: '0 18px', height: 360, overflow: 'hidden' }}>
        <div style={{ fontSize: 12, color: PHONE.muted, margin: '12px 0 8px' }}>Needs you</div>
        <LedgerRow dot="warn" title="Approval waiting" meta="High risk · patch · hermes-box" trailing="Review" />
        <div style={{ fontSize: 12, color: PHONE.muted, margin: '12px 0 8px' }}>Running</div>
        <LedgerRow dot="active" title="Fix auth redirect bug" meta="Claude · Mac mini · 4m ago" trailing="+42 -3" />
        <div style={{ fontSize: 12, color: PHONE.muted, margin: '12px 0 8px' }}>Done since you left</div>
        <LedgerRow dot="idle" title="Dependency audit" meta="✓ Proof ready · 3/3 checks" trailing="Ship" />
      </div>
      <Composer />
      <TabBar active={0} />
    </PhoneFrame>
  );
}

function ScreenLaunchContract() {
  return (
    <PhoneFrame label="B · Launch Contract" badge="DELEGATE">
      <div style={{ padding: '12px 16px 0', fontSize: 16, fontWeight: 700 }}>New mission</div>
      <div style={{ padding: '8px 16px 0' }}>
        <div style={{ fontSize: 13, color: PHONE.muted, marginBottom: 8, minHeight: 48, border: `1px dashed ${PHONE.line}`, borderRadius: 10, padding: 10 }}>
          Fix the login redirect loop on staging…
        </div>
        <div style={{ marginBottom: 10 }}>
          <Chip accent>conduit</Chip>
          <Chip accent>Mac mini</Chip>
          <Chip>Claude</Chip>
          <Chip>Implement</Chip>
        </div>
        <div style={{ fontSize: 11, color: PHONE.muted, marginBottom: 4 }}>Proof expected</div>
        <div style={{ marginBottom: 10 }}>
          <Chip accent>Tests pass</Chip>
          <Chip>Visual diff</Chip>
        </div>
        <div style={{ fontSize: 11, color: PHONE.muted, marginBottom: 4 }}>Interrupt me for</div>
        <Chip accent>Writes only</Chip>
        <Chip>Budget: 30 min</Chip>
      </div>
      <div style={{ position: 'absolute', left: 16, right: 16, bottom: 88 }}>
        <div style={{ height: 40, borderRadius: 20, background: PHONE.accent, color: '#fff', display: 'grid', placeItems: 'center', fontWeight: 700, fontSize: 14 }}>
          Dispatch →
        </div>
      </div>
      <TabBar active={0} />
    </PhoneFrame>
  );
}

function ScreenWorkThread() {
  return (
    <PhoneFrame label="C · Work Thread (activity log)" badge="NOT CHAT">
      <div style={{ padding: '10px 16px', borderBottom: `1px solid ${PHONE.line}`, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <div style={{ fontSize: 15, fontWeight: 700 }}>Fix auth redirect</div>
          <div style={{ fontSize: 11, color: PHONE.ok }}>● Running on Mac mini</div>
        </div>
        <span style={{ fontSize: 11, color: PHONE.danger, fontWeight: 700 }}>Stop</span>
      </div>
      <div style={{ padding: '10px 16px 90px', height: 400, overflow: 'hidden' }}>
        <ArtifactCard title="🔧 Read src/auth/redirect.ts" body="Examining redirect handler" />
        <ArtifactCard title="✏️ Edit redirect.ts" body="Added staging URL allowlist" tone="info" />
        <ArtifactCard title="▶ Run tests" body="auth.test.ts — 12 passed" tone="ok" />
        <ArtifactCard title="📸 Visual diff" body="Login screen — pending review" tone="warn" />
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginTop: 8 }}>
          <Chip accent>Re-run tests</Chip>
          <Chip>Open PR</Chip>
          <Chip>Ask for changes</Chip>
        </div>
      </div>
      <Composer placeholder="Follow up…" />
      <TabBar active={1} />
    </PhoneFrame>
  );
}

function ScreenQuestionCard() {
  return (
    <PhoneFrame label="D · Question Card" badge="STRUCTURED">
      <div style={{ padding: '10px 16px', fontSize: 15, fontWeight: 700 }}>Fix auth redirect</div>
      <div style={{ padding: '0 16px' }}>
        <div style={{ border: `2px solid ${PHONE.warn}`, borderRadius: 14, padding: 14, background: 'rgba(209,139,43,.08)', marginTop: 8 }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: PHONE.warn, marginBottom: 6 }}>AGENT NEEDS YOU · Medium risk</div>
          <div style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, lineHeight: 1.35 }}>
            Staging uses a different OAuth client ID. Which should I use?
          </div>
          {['Use staging client (recommended)', 'Use prod client', 'Skip OAuth fix'].map((opt, i) => (
            <div
              key={opt}
              style={{
                padding: '10px 12px',
                borderRadius: 10,
                border: `1px solid ${i === 0 ? PHONE.accent : PHONE.line}`,
                background: i === 0 ? 'rgba(21,139,192,.08)' : '#fff',
                marginBottom: 6,
                fontSize: 13,
                fontWeight: i === 0 ? 600 : 400,
              }}
            >
              {opt}
            </div>
          ))}
          <div style={{ fontSize: 11, color: PHONE.muted, marginTop: 8, textAlign: 'center' }}>or type more detail…</div>
        </div>
      </div>
      <TabBar active={1} />
    </PhoneFrame>
  );
}

function ScreenProofSuite() {
  return (
    <PhoneFrame label="E · Proof Suite" badge="VERIFY">
      <div style={{ padding: '10px 16px', fontSize: 15, fontWeight: 700 }}>Proof rollup</div>
      <div style={{ padding: '0 16px' }}>
        <div style={{ borderRadius: 12, border: `1px solid ${PHONE.line}`, padding: 12, marginBottom: 10, background: '#fff' }}>
          <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 4 }}>3 of 4 checks passed</div>
          <div style={{ height: 6, borderRadius: 3, background: PHONE.line, overflow: 'hidden' }}>
            <div style={{ width: '75%', height: '100%', background: PHONE.ok }} />
          </div>
        </div>
        <ArtifactCard title="✓ Unit tests" body="12/12 passed · 2.1s" tone="ok" />
        <ArtifactCard title="✓ Lint" body="No issues" tone="ok" />
        <ArtifactCard title="✓ Build" body="iOS sim build succeeded" tone="ok" />
        <ArtifactCard title="⚠ Visual diff" body="Login button shifted 2px — tap to review" tone="warn" />
      </div>
      <div style={{ position: 'absolute', left: 16, right: 16, bottom: 88, opacity: 0.45 }}>
        <div style={{ height: 40, borderRadius: 20, background: '#999', color: '#fff', display: 'grid', placeItems: 'center', fontWeight: 700, fontSize: 13 }}>
          Mark Ready (blocked)
        </div>
      </div>
      <TabBar active={1} />
    </PhoneFrame>
  );
}

function ScreenApproval() {
  return (
    <PhoneFrame label="F · Review / Approve" badge="GOVERN">
      <div style={{ padding: '10px 16px 0', fontSize: 14, fontWeight: 700 }}>Approve file write</div>
      <div style={{ padding: '4px 16px', fontSize: 11, color: PHONE.danger, fontWeight: 700 }}>HIGH RISK · Face ID required</div>
      <div style={{ padding: '8px 16px', fontSize: 11, color: PHONE.muted }}>Blast radius: 1 file in src/auth/</div>
      <div style={{ margin: '0 16px', borderRadius: 10, border: `1px solid ${PHONE.line}`, background: '#1e1e1e', color: '#d4d4d4', fontFamily: 'ui-monospace, monospace', fontSize: 10, padding: 10, lineHeight: 1.5, maxHeight: 180, overflow: 'hidden' }}>
        <div><span style={{ color: '#f97583' }}>-</span> redirectUrl = prodClient</div>
        <div><span style={{ color: '#7ee787' }}>+</span> redirectUrl = stagingClient</div>
        <div style={{ color: '#6f6f6f' }}>  if env === 'staging'</div>
      </div>
      <div style={{ position: 'absolute', left: 16, right: 16, bottom: 88, display: 'flex', gap: 8 }}>
        <div style={{ flex: 1, height: 40, borderRadius: 20, border: `1px solid ${PHONE.line}`, display: 'grid', placeItems: 'center', fontWeight: 600, fontSize: 13 }}>Deny</div>
        <div style={{ flex: 1, height: 40, borderRadius: 20, background: PHONE.accent, color: '#fff', display: 'grid', placeItems: 'center', fontWeight: 700, fontSize: 13 }}>🔒 Approve</div>
      </div>
      <TabBar active={0} />
    </PhoneFrame>
  );
}

function ScreenAwayStatus() {
  return (
    <PhoneFrame label="G · Lock screen / Away" badge="STEP AWAY">
      <div style={{ padding: '60px 20px 0', textAlign: 'center' }}>
        <div style={{ fontSize: 48, fontWeight: 200, letterSpacing: -2 }}>9:41</div>
        <div style={{ fontSize: 13, color: PHONE.muted, marginTop: 4 }}>Tuesday, July 7</div>
      </div>
      <div style={{ margin: '24px 16px', borderRadius: 16, background: 'rgba(255,255,255,.9)', border: `1px solid ${PHONE.line}`, padding: 14, boxShadow: '0 8px 24px rgba(0,0,0,.06)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
          <span style={{ fontSize: 12, fontWeight: 700 }}>LANCER</span>
          <span style={{ fontSize: 11, color: PHONE.ok, fontWeight: 700 }}>● LIVE</span>
        </div>
        <div style={{ fontSize: 14, fontWeight: 600, marginBottom: 4 }}>Fix auth redirect — still running</div>
        <div style={{ fontSize: 11, color: PHONE.muted }}>Mac mini · Claude · 4m · tests passing</div>
        <div style={{ marginTop: 10, height: 4, borderRadius: 2, background: PHONE.line }}>
          <div style={{ width: '65%', height: '100%', background: PHONE.accent, borderRadius: 2 }} />
        </div>
      </div>
      <div style={{ margin: '0 16px', borderRadius: 14, border: `1px solid ${PHONE.warn}`, background: 'rgba(209,139,43,.1)', padding: 12 }}>
        <div style={{ fontSize: 12, fontWeight: 700, color: PHONE.warn }}>1 approval waiting</div>
        <div style={{ fontSize: 11, color: PHONE.muted }}>Tap to review · high risk write</div>
      </div>
    </PhoneFrame>
  );
}

function ScreenShip() {
  return (
    <PhoneFrame label="H · Ship from phone" badge="CLOSE LOOP">
      <div style={{ padding: '10px 16px', fontSize: 15, fontWeight: 700 }}>Ready to ship</div>
      <div style={{ padding: '0 16px' }}>
        <ArtifactCard title="PR #142 opened" body="fix/auth-redirect-staging · +42 -3" tone="ok" />
        <ArtifactCard title="All proof checks passed" body="Tests · lint · visual diff" tone="ok" />
        <div style={{ fontSize: 11, color: PHONE.muted, margin: '12px 0 6px' }}>Return-to-desk recap</div>
        <div style={{ fontSize: 12, lineHeight: 1.45, color: PHONE.ink, border: `1px solid ${PHONE.line}`, borderRadius: 10, padding: 10, background: '#fff' }}>
          Changed OAuth client for staging. All tests pass. PR ready — nothing blocked.
        </div>
      </div>
      <div style={{ position: 'absolute', left: 16, right: 16, bottom: 88 }}>
        <div style={{ height: 40, borderRadius: 20, background: PHONE.ok, color: '#fff', display: 'grid', placeItems: 'center', fontWeight: 700, fontSize: 14 }}>
          Merge PR →
        </div>
      </div>
      <TabBar active={1} />
    </PhoneFrame>
  );
}

function ScreenVoiceCamera() {
  return (
    <PhoneFrame label="I · Phone-native input" badge="MOBILE-ONLY">
      <div style={{ padding: '10px 16px', fontSize: 15, fontWeight: 700 }}>Attach context</div>
      <div style={{ padding: '0 16px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, marginBottom: 12 }}>
          {[
            { icon: '📷', label: 'Screenshot' },
            { icon: '🎥', label: 'Screen record' },
            { icon: '🎤', label: 'Voice note' },
            { icon: '📎', label: 'Share link' },
          ].map((item) => (
            <div key={item.label} style={{ border: `1px solid ${PHONE.line}`, borderRadius: 12, padding: '14px 10px', textAlign: 'center', background: '#fff' }}>
              <div style={{ fontSize: 22, marginBottom: 4 }}>{item.icon}</div>
              <div style={{ fontSize: 11, fontWeight: 600 }}>{item.label}</div>
            </div>
          ))}
        </div>
        <div style={{ border: `1px solid ${PHONE.line}`, borderRadius: 12, padding: 10, background: '#fff' }}>
          <div style={{ fontSize: 11, color: PHONE.muted, marginBottom: 6 }}>Screenshot annotated</div>
          <div style={{ height: 80, borderRadius: 8, background: 'linear-gradient(135deg,#e8e8e6,#f5f5f3)', position: 'relative' }}>
            <div style={{ position: 'absolute', top: 24, left: 40, width: 60, height: 40, border: `2px solid ${PHONE.danger}`, borderRadius: 6 }} />
            <div style={{ position: 'absolute', top: 68, left: 30, fontSize: 9, color: PHONE.danger, fontWeight: 700 }}>button misaligned</div>
          </div>
        </div>
      </div>
      <TabBar active={0} />
    </PhoneFrame>
  );
}

/* ── user journey DAG ── */
const FLOW = computeDAGLayout({
  nodes: [
    { id: 'Home' },
    { id: 'Launch' },
    { id: 'Running' },
    { id: 'Question' },
    { id: 'Proof' },
    { id: 'Approve' },
    { id: 'Ship' },
  ],
  edges: [
    { from: 'Home', to: 'Launch' },
    { from: 'Launch', to: 'Running' },
    { from: 'Running', to: 'Question' },
    { from: 'Running', to: 'Proof' },
    { from: 'Question', to: 'Running' },
    { from: 'Proof', to: 'Approve' },
    { from: 'Approve', to: 'Ship' },
    { from: 'Ship', to: 'Home' },
  ],
  direction: 'horizontal',
  nodeWidth: 72,
  nodeHeight: 28,
  rankGap: 28,
  nodeGap: 10,
});

function FlowDiagram() {
  const theme = useHostTheme();
  return (
    <div style={{ position: 'relative', width: FLOW.width, height: FLOW.height, margin: '0 auto' }}>
      <svg width={FLOW.width} height={FLOW.height} style={{ position: 'absolute', inset: 0 }}>
        {FLOW.edges.map((e, i) =>
          e.isBackEdge ? (
            <path key={i} d={e.path} fill="none" stroke={theme.accent} strokeWidth={1.5} strokeDasharray="4 3" opacity={0.6} />
          ) : (
            <path key={i} d={e.path} fill="none" stroke={theme.border} strokeWidth={1.5} />
          ),
        )}
      </svg>
      {FLOW.nodes.map((n) => (
        <div
          key={n.id}
          style={{
            position: 'absolute',
            left: n.x,
            top: n.y,
            width: n.width,
            height: n.height,
            borderRadius: 8,
            border: `1px solid ${theme.border}`,
            background: theme.surface,
            display: 'grid',
            placeItems: 'center',
            fontSize: 10,
            fontWeight: 700,
          }}
        >
          {n.id}
        </div>
      ))}
    </div>
  );
}

/* ── main canvas ── */

export default function MobileAgentBrainstormCanvas() {
  const [section, setSection] = useCanvasState<'all' | 'core' | 'govern' | 'mobile'>('brainstorm.section', 'all');
  const theme = useHostTheme();

  const showCore = section === 'all' || section === 'core';
  const showGovern = section === 'all' || section === 'govern';
  const showMobile = section === 'all' || section === 'mobile';

  const phoneStripStyle = {
    display: 'flex',
    gap: 20,
    overflowX: 'auto',
    padding: '8px 4px 16px',
    alignItems: 'flex-start',
  };

  return (
    <Stack gap={20}>
      <div>
        <H1>Mobile Agent Mission Control</H1>
        <Text tone="secondary">
          Brainstorm wireframes — agents run on your machine, phone steers & approves. Not a phone IDE.
        </Text>
        <Row gap={8} style={{ marginTop: 12, flexWrap: 'wrap' }}>
          {(['all', 'core', 'govern', 'mobile'] as const).map((key) => (
            <Button key={key} variant={section === key ? 'filled' : 'outline'} onClick={() => setSection(key)}>
              {key === 'all' ? 'All screens' : key === 'core' ? 'Core loop' : key === 'govern' ? 'Governance' : 'Mobile-only'}
            </Button>
          ))}
        </Row>
      </div>

      <Grid columns={4} gap={12}>
        <Stat value={3} label="App roots" tone="info" />
        <Stat value={9} label="Wireframe screens" tone="neutral" />
        <Stat value="Host" label="Agent runs on" tone="success" />
        <Stat value="Phone" label="You steer from" tone="warning" />
      </Grid>

      <Callout tone="info" title="Product thesis">
        Delegate with a Launch Contract → step away (session survives on host) → get interrupted only for questions & approvals → verify with Proof Suite → ship from phone.
      </Callout>

      <Card>
        <CardHeader>End-to-end flow</CardHeader>
        <CardBody>
          <FlowDiagram />
          <Text tone="tertiary" style={{ marginTop: 12, fontSize: 12, textAlign: 'center' }}>
            Dashed edge = loop back (follow-up, re-run). Phone disconnects anytime — host keeps running.
          </Text>
        </CardBody>
      </Card>

      {showCore && (
        <CollapsibleSection title="Core loop — Home, Launch, Work Thread" defaultOpen>
          <div style={phoneStripStyle}>
            <ScreenHomeDigest />
            <ScreenLaunchContract />
            <ScreenWorkThread />
            <ScreenQuestionCard />
            <ScreenProofSuite />
          </div>
        </CollapsibleSection>
      )}

      {showGovern && (
        <CollapsibleSection title="Governance & ship — trust + close the loop" defaultOpen>
          <div style={phoneStripStyle}>
            <ScreenApproval />
            <ScreenProofSuite />
            <ScreenShip />
          </div>
          <Divider />
          <BarChart
            title="Where competitors converge vs Lancer wedge"
            categories={['Approvals', 'Proof', 'Policy engine', 'Audit log', 'Cross-vendor']}
            series={[
              { name: 'Market parity', data: [85, 70, 20, 15, 30], tone: 'neutral' },
              { name: 'Lancer depth', data: [90, 75, 95, 90, 85], tone: 'info' },
            ]}
            height={180}
          />
        </CollapsibleSection>
      )}

      {showMobile && (
        <CollapsibleSection title="Mobile-native affordances" defaultOpen>
          <div style={phoneStripStyle}>
            <ScreenAwayStatus />
            <ScreenVoiceCamera />
          </div>
        </CollapsibleSection>
      )}

      <Card>
        <CardHeader>3-root information architecture</CardHeader>
        <CardBody>
          <Grid columns={3} gap={12}>
            {[
              { root: 'Home', desc: 'Away Digest — needs you, running, done. Composer to launch.', screens: 'A, B' },
              { root: 'Workspaces', desc: 'Repo-first threads, work log, proof, ship actions.', screens: 'C–H' },
              { root: 'Settings', desc: 'Policy, audit, machines, notifications, billing.', screens: '—' },
            ].map((r) => (
              <div key={r.root} style={mergeStyle({ border: `1px solid ${theme.border}`, borderRadius: 12, padding: 14, background: theme.surface })}>
                <H3>{r.root}</H3>
                <Text tone="secondary" style={{ fontSize: 13 }}>{r.desc}</Text>
                <Pill tone="neutral" style={{ marginTop: 8 }}>Screens {r.screens}</Pill>
              </div>
            ))}
          </Grid>
        </CardBody>
      </Card>

      <Card>
        <CardHeader>What to avoid</CardHeader>
        <CardBody>
          <Stack gap={8}>
            <Callout tone="warning" title="Not a phone IDE">No full terminal, no typing code on screen. Agents do the implementation.</Callout>
            <Callout tone="warning" title="Not chat bubbles">Work Thread = structured artifacts (tool calls, diffs, proof), not iMessage.</Callout>
            <Callout tone="warning" title="Not per-agent noise">One Away Status on lock screen, not a Live Activity per agent.</Callout>
          </Stack>
        </CardBody>
      </Card>

      <Text tone="tertiary" style={{ fontSize: 12 }}>
        Based on Lancer Away Mode brainstorm · 2026-07-07 · Open this file in Cursor Canvas to interact with filters
      </Text>
      <Spacer size={24} />
    </Stack>
  );
}
