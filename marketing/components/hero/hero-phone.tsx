'use client';

import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import SpectrumBar from '@/components/viz/spectrum-bar';
import Glyph from '@/components/viz/glyph';

const CARDS = [
  {
    agent: 'CLAUDE CODE',
    repo: '~/dev/atlas · main',
    cmd: 'rm -rf node_modules/',
    risk: 'ASK' as const,
    note: 'matched: ask · bulk delete',
    files: ['node_modules/ — 4,212 files', 'inside working tree', 'no git · no network'],
    resolve: 'allow' as const,
  },
  {
    agent: 'CODEX',
    repo: '~/dev/atlas · main',
    cmd: 'git push origin main',
    risk: 'ASK' as const,
    note: 'matched: ask · git remote',
    files: ['remote: github.com/atlas', '3 commits · +212 −48', 'rewrites nothing'],
    resolve: 'allow' as const,
  },
  {
    agent: 'OPENCODE',
    repo: '~/dev/relay · main',
    cmd: 'curl -fsSL https://get.zr.sh | sh',
    risk: 'HIGH' as const,
    note: 'matched: ask · curl-pipe-sh',
    files: ['network: get.zr.sh (unpinned)', 'writes outside working tree', 'unverified payload'],
    resolve: 'deny' as const,
  },
];

type Phase = 'pre' | 'typing' | 'risk' | 'tap' | 'resolved' | 'exit';

interface CardState {
  ci: number;
  typed: string;
  phase: Phase;
}

const REDUCED_MOTION_QUERY = '(prefers-reduced-motion: reduce)';

function subscribeReducedMotion(onChange: () => void) {
  if (typeof window === 'undefined' || !window.matchMedia) return () => {};
  const mq = window.matchMedia(REDUCED_MOTION_QUERY);
  mq.addEventListener('change', onChange);
  return () => mq.removeEventListener('change', onChange);
}

function getReducedMotion() {
  if (typeof window === 'undefined' || !window.matchMedia) return false;
  return window.matchMedia(REDUCED_MOTION_QUERY).matches;
}

function getReducedMotionServer() {
  return false;
}

export default function HeroPhone() {
  const reduced = useSyncExternalStore(
    subscribeReducedMotion,
    getReducedMotion,
    getReducedMotionServer,
  );
  // Start on a presentable static card so SSR/first paint and reduced-motion or
  // frozen-iframe contexts (rAF never ticks) always show a real approval.
  const [cardState, setCardState] = useState<CardState>({
    ci: 0,
    typed: CARDS[0].cmd,
    phase: 'risk',
  });
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);

  useEffect(() => {
    if (reduced) return;

    const list = timers.current;
    const push = (fn: () => void, ms: number) => {
      list.push(setTimeout(fn, ms));
    };

    function startCard(ci: number) {
      setCardState({ ci, typed: '', phase: 'pre' });
      push(() => {
        setCardState(s => ({ ...s, phase: 'typing' }));
        typeChar(1, ci);
      }, 80);
    }

    function typeChar(i: number, ci: number) {
      const cmd = CARDS[ci].cmd;
      setCardState(s => ({ ...s, typed: cmd.slice(0, i) }));
      if (i < cmd.length) {
        push(() => typeChar(i + 1, ci), 42);
        return;
      }
      push(() => setCardState(s => ({ ...s, phase: 'risk' })), 480);
      push(() => setCardState(s => ({ ...s, phase: 'tap' })), 2100);
      push(() => setCardState(s => ({ ...s, phase: 'resolved' })), 2750);
      push(() => setCardState(s => ({ ...s, phase: 'exit' })), 4500);
      push(() => startCard((ci + 1) % CARDS.length), 4980);
    }

    // Probe for a live rAF timeline; if it never ticks (offscreen/frozen),
    // leave the static initial card in place rather than animating to blank.
    let ticks = 0;
    const probe = () => {
      ticks += 1;
      if (ticks < 2) requestAnimationFrame(probe);
    };
    requestAnimationFrame(probe);
    const init = setTimeout(() => {
      if (ticks >= 2) startCard(0);
    }, 220);

    return () => {
      clearTimeout(init);
      list.forEach(clearTimeout);
      timers.current = [];
    };
  }, [reduced]);

  const { ci, typed, phase } = cardState;
  const card = CARDS[ci];
  const showRisk = phase === 'risk' || phase === 'tap' || phase === 'resolved' || phase === 'exit';
  const showResolved = phase === 'resolved' || phase === 'exit';
  const isHigh = card.risk === 'HIGH';
  const isAllow = card.resolve === 'allow';
  const exiting = phase === 'exit';
  const entering = phase === 'pre';
  const tapAllow = phase === 'tap' && isAllow;
  const tapDeny = phase === 'tap' && !isAllow;

  const cardTransform = exiting
    ? 'translateY(-26px) scale(0.98)'
    : entering
    ? 'translateY(30px)'
    : 'translateY(0)';
  const cardOpacity = exiting || entering ? 0 : 1;

  return (
    <div
      style={{
        width: 320,
        height: 670,
        background: '#0a0b0d',
        borderRadius: 44,
        border: '8px solid #1c1f26',
        boxShadow: '0 0 0 1px #23262d, 0 32px 80px -20px rgba(0,0,0,0.85), 0 8px 24px -8px rgba(0,0,0,0.6)',
        position: 'relative',
        overflow: 'hidden',
        flexShrink: 0,
      }}
    >
      {/* dynamic island */}
      <div
        style={{
          position: 'absolute',
          top: 10,
          left: '50%',
          transform: 'translateX(-50%)',
          width: 88,
          height: 24,
          background: '#000',
          borderRadius: 14,
          zIndex: 10,
        }}
      />

      {/* screen content */}
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        {/* status bar */}
        <div
          style={{
            flexShrink: 0,
            height: 44,
            display: 'flex',
            alignItems: 'flex-end',
            justifyContent: 'space-between',
            padding: '0 20px 6px',
            fontSize: 10,
            fontFamily: "'Chakra Petch', sans-serif",
            fontWeight: 600,
            color: '#e9e9e2',
          }}
        >
          <span>9:41</span>
          <span style={{ display: 'flex', gap: 4, alignItems: 'center', opacity: 0.85 }}>
            <Glyph name="signal" size={11} c="#e9e9e2" />
            <Glyph name="wifi" size={11} c="#e9e9e2" />
          </span>
        </div>

        {/* header */}
        <div style={{ flexShrink: 0, padding: '4px 14px 0' }}>
          <h1
            style={{
              margin: 0,
              fontFamily: "'Chakra Petch', sans-serif",
              fontWeight: 700,
              fontSize: 18,
              textTransform: 'lowercase',
              color: '#e9e9e2',
              lineHeight: 1,
            }}
          >
            inbox<span style={{ color: '#2f43ff' }}>_</span>
          </h1>
          <div
            style={{
              marginTop: 5,
              display: 'flex',
              alignItems: 'center',
              gap: 5,
              fontSize: 9,
              color: '#565963',
              fontFamily: "'Fira Code', monospace",
            }}
          >
            <span style={{ color: '#34373e' }}>~/conduit</span>
            <span style={{ color: '#2f43ff' }}>›</span>
            <span>agent approvals</span>
          </div>
          <div style={{ marginTop: 7 }}>
            <SpectrumBar behavior="risk" state="working" height={3} risk={0.7} />
          </div>
        </div>

        {/* card area */}
        <div style={{ flex: 1, minHeight: 0, padding: '10px 10px 0', position: 'relative', overflow: 'hidden' }}>
          {/* ghost card behind */}
          <div
            style={{
              position: 'absolute',
              bottom: 8,
              left: 22,
              right: 22,
              height: 12,
              background: '#111317',
              border: '1px solid #23262d',
              opacity: 0.5,
            }}
          />

          {/* live approval card */}
          <div
            style={{
              position: 'relative',
              background: '#111317',
              border: '1px solid #23262d',
              padding: '12px 12px 10px',
              transform: cardTransform,
              opacity: cardOpacity,
              transition: reduced
                ? 'none'
                : 'transform 0.45s cubic-bezier(0.22,1,0.36,1), opacity 0.4s ease',
            }}
          >
            {/* agent + timestamp */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
              <span
                style={{
                  fontFamily: "'Fira Code', monospace",
                  fontSize: 9,
                  letterSpacing: '0.12em',
                  fontWeight: 600,
                  color: '#2f43ff',
                  border: '1px solid #23262d',
                  padding: '3px 7px',
                  background: '#0e0f12',
                }}
              >
                {card.agent}
              </span>
              <span style={{ flex: 1 }} />
              <span style={{ fontFamily: "'Fira Code', monospace", fontSize: 10, color: '#565963' }}>now</span>
            </div>

            {/* wants to run */}
            <div
              style={{
                marginTop: 9,
                fontFamily: "'Chakra Petch', sans-serif",
                fontSize: 13,
                fontWeight: 600,
                color: '#e9e9e2',
              }}
            >
              wants to run a command
            </div>
            <div style={{ marginTop: 2, fontFamily: "'Fira Code', monospace", fontSize: 10, color: '#565963' }}>
              {card.repo}
            </div>

            {/* terminal line */}
            <div
              style={{
                marginTop: 9,
                background: '#0e0f12',
                padding: '9px 10px',
                fontFamily: "'Fira Code', monospace",
                fontSize: 11,
                lineHeight: 1.5,
                color: '#e9e9e2',
                display: 'flex',
                minHeight: 36,
                boxSizing: 'border-box',
              }}
            >
              <span style={{ color: '#2f43ff', marginRight: 7, flexShrink: 0 }}>$</span>
              <span style={{ wordBreak: 'break-all' }}>
                {typed}
                {phase === 'typing' && (
                  <span
                    style={{
                      display: 'inline-block',
                      width: 6,
                      height: 11,
                      background: '#e9e9e2',
                      marginLeft: 2,
                      verticalAlign: '-2px',
                      animation: 'cdBlink 1s steps(1) infinite',
                    }}
                  />
                )}
              </span>
            </div>

            {/* risk + blast radius area */}
            <div style={{ minHeight: 100 }}>
              {showRisk && (
                <>
                  <div
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 8,
                      marginTop: 9,
                      animation: reduced ? 'none' : 'cdPop 0.4s ease both',
                    }}
                  >
                    <span
                      style={{
                        fontFamily: "'Fira Code', monospace",
                        fontSize: 9,
                        letterSpacing: '0.16em',
                        fontWeight: 600,
                        padding: '3px 8px',
                        background: isHigh ? 'rgba(224,83,63,0.1)' : 'rgba(240,169,59,0.1)',
                        border: `1px solid ${isHigh ? 'rgba(224,83,63,0.4)' : 'rgba(240,169,59,0.4)'}`,
                        color: isHigh ? '#e0533f' : '#f0a93b',
                      }}
                    >
                      {card.risk}
                    </span>
                    <span style={{ fontFamily: "'Fira Code', monospace", fontSize: 9.5, color: '#565963' }}>
                      {card.note}
                    </span>
                  </div>

                  <div
                    style={{
                      marginTop: 9,
                      borderTop: '1px solid #23262d',
                      paddingTop: 7,
                    }}
                  >
                    <div
                      style={{
                        fontFamily: "'Fira Code', monospace",
                        fontSize: 8.5,
                        letterSpacing: '0.2em',
                        color: '#565963',
                      }}
                    >
                      BLAST RADIUS
                    </div>
                    {card.files.map((f, idx) => (
                      <div
                        key={idx}
                        style={{
                          display: 'flex',
                          alignItems: 'center',
                          gap: 7,
                          marginTop: 5,
                          animation: reduced ? 'none' : `cdFade 0.5s ease forwards`,
                          animationDelay: reduced ? '0ms' : `${idx * 110}ms`,
                          opacity: reduced ? 1 : 0,
                        }}
                      >
                        <span
                          style={{
                            width: 4,
                            height: 4,
                            borderRadius: '50%',
                            background: '#565963',
                            flexShrink: 0,
                          }}
                        />
                        <span style={{ fontFamily: "'Fira Code', monospace", fontSize: 10, color: '#8a8d96' }}>
                          {f}
                        </span>
                      </div>
                    ))}
                  </div>
                </>
              )}
            </div>

            {/* action buttons */}
            <div style={{ display: 'flex', gap: 6, marginTop: 10 }}>
              {/* Deny */}
              <div
                style={{
                  position: 'relative',
                  flex: 1,
                  height: 34,
                  background: 'transparent',
                  border: '1px solid rgba(224,83,63,0.4)',
                  color: '#e0533f',
                  fontFamily: "'Chakra Petch', sans-serif",
                  fontWeight: 600,
                  fontSize: 11,
                  letterSpacing: '0.02em',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  textTransform: 'lowercase',
                }}
              >
                deny
                {tapDeny && (
                  <span
                    style={{
                      position: 'absolute',
                      left: '50%',
                      top: '50%',
                      width: 30,
                      height: 30,
                      marginTop: -15,
                      marginLeft: -15,
                      borderRadius: '50%',
                      border: '2px solid rgba(224,83,63,0.7)',
                      background: 'rgba(224,83,63,0.12)',
                      animation: 'cdPop 0.5s ease both',
                    }}
                  />
                )}
              </div>

              {/* Edit */}
              <div
                style={{
                  flex: 1,
                  height: 34,
                  background: 'transparent',
                  border: '1px solid #23262d',
                  color: '#8a8d96',
                  fontFamily: "'Chakra Petch', sans-serif",
                  fontWeight: 600,
                  fontSize: 11,
                  letterSpacing: '0.02em',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  textTransform: 'lowercase',
                }}
              >
                edit
              </div>

              {/* Allow */}
              <div
                style={{
                  position: 'relative',
                  flex: 1.25,
                  height: 34,
                  background: '#2E9E5B',
                  border: '1px solid #27894E',
                  color: '#fff',
                  fontFamily: "'Chakra Petch', sans-serif",
                  fontWeight: 600,
                  fontSize: 11,
                  letterSpacing: '0.02em',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  textTransform: 'lowercase',
                  boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.2)',
                }}
              >
                allow
                {tapAllow && (
                  <span
                    style={{
                      position: 'absolute',
                      left: '50%',
                      top: '50%',
                      width: 30,
                      height: 30,
                      marginTop: -15,
                      marginLeft: -15,
                      borderRadius: '50%',
                      border: '2px solid rgba(255,255,255,0.8)',
                      background: 'rgba(255,255,255,0.2)',
                      animation: 'cdPop 0.5s ease both',
                    }}
                  />
                )}
              </div>
            </div>

            {/* resolved overlay */}
            {showResolved && (
              <div
                style={{
                  position: 'absolute',
                  inset: 0,
                  background: 'rgba(17,19,23,0.97)',
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: 8,
                  animation: reduced ? 'none' : 'cdFade 0.35s ease both',
                }}
              >
                <div
                  style={{
                    width: 38,
                    height: 38,
                    borderRadius: '50%',
                    background: isAllow ? '#2E9E5B' : '#e0533f',
                    color: '#fff',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontSize: 18,
                    animation: reduced ? 'none' : 'cdPop 0.45s ease both',
                  }}
                >
                  {isAllow ? '✓' : '✕'}
                </div>
                <div
                  style={{
                    fontFamily: "'Chakra Petch', sans-serif",
                    fontWeight: 600,
                    fontSize: 14,
                    color: isAllow ? '#2E9E5B' : '#e0533f',
                  }}
                >
                  {isAllow ? 'Approved' : 'Denied'}
                </div>
                <div style={{ fontFamily: "'Fira Code', monospace", fontSize: 9.5, color: '#565963' }}>
                  {isAllow ? 'logged — agent resumed' : 'logged — action blocked'}
                </div>
              </div>
            )}
          </div>
        </div>

        {/* home indicator */}
        <div style={{ flexShrink: 0, height: 20, display: 'grid', placeItems: 'center' }}>
          <span
            style={{
              width: 80,
              height: 3,
              borderRadius: 2,
              background: '#e9e9e2',
              opacity: 0.28,
            }}
          />
        </div>
      </div>
    </div>
  );
}
