'use client';

import { useEffect, useRef } from 'react';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

// "Running smoothly" palette — the famicom spectrum (lib/lancer-core.jsx),
// luminance-evened so every hue reads, with the alarm-red pulled out and
// reserved for the glitch so a calm warm moment never looks like an error.
const CALM: [number, number, number][] = [
  [235, 120, 60], // orange
  [240, 150, 55], // amber
  [242, 196, 90], // gold
  [225, 140, 190], // pink
  [150, 105, 225], // purple
  [110, 130, 240], // blue
];
const ERR: [number, number, number] = [226, 52, 46]; // the red glitch
const CELL = 22;
const GAP = 2;

const clamp = (v: number, lo = 0, hi = 1) => Math.max(lo, Math.min(hi, v));
function mix(
  a: [number, number, number],
  b: [number, number, number],
  k: number,
): [number, number, number] {
  return [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k];
}
// smooth ping-pong across the calm palette — no hard wrap seam
function calmColor(p: number): [number, number, number] {
  const n = CALM.length;
  const tri = 1 - Math.abs((((p % 2) + 2) % 2) - 1);
  const f = tri * (n - 1);
  const i = Math.floor(f);
  return mix(CALM[i], CALM[Math.min(n - 1, i + 1)], f - i);
}

export default function HeroBackdrop() {
  const wrapRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const wrap = wrapRef.current;
    const cv = canvasRef.current;
    if (!wrap || !cv) return;
    const ctx = cv.getContext('2d')!;
    const reduced =
      typeof window !== 'undefined' &&
      window.matchMedia &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    const dpr = Math.min(2, window.devicePixelRatio || 1);
    let W = 0;
    let H = 0;
    let cols = 0;
    let rows = 0;

    const resize = () => {
      const r = wrap.getBoundingClientRect();
      W = Math.max(1, r.width);
      H = Math.max(1, r.height);
      cv.width = W * dpr;
      cv.height = H * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      cols = Math.ceil(W / CELL);
      rows = Math.ceil(H / CELL);
    };
    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(wrap);

    // brightest in the upper-centre, fades down + to the edges
    const field = (cx: number, cy: number) => {
      const nx = (cx - W / 2) / (W * 0.6);
      const ny = (cy - H * 0.34) / (H * 0.6);
      return clamp(1 - Math.sqrt(nx * nx + ny * ny));
    };

    const SPOT = 190;

    if (reduced) {
      ctx.clearRect(0, 0, W, H);
      for (let j = 0; j < rows; j++) {
        for (let i = 0; i < cols; i++) {
          const cx = i * CELL;
          const cy = j * CELL;
          const m = field(cx, cy);
          if (m <= 0.02) continue;
          const rgb = calmColor(i * 0.02 + j * 0.014);
          ctx.fillStyle = `rgba(${rgb[0] | 0},${rgb[1] | 0},${rgb[2] | 0},${0.2 * m})`;
          ctx.fillRect(cx + GAP / 2, cy + GAP / 2, CELL - GAP, CELL - GAP);
        }
      }
      return () => ro.disconnect();
    }

    // pointer (GSAP-smoothed) for the interactive spotlight + parallax
    const pointer = { x: -9999, y: -9999, par: 0 };
    const qx = gsap.quickTo(pointer, 'x', { duration: 0.6, ease: 'power3' });
    const qy = gsap.quickTo(pointer, 'y', { duration: 0.6, ease: 'power3' });
    const onMove = (e: PointerEvent) => {
      const r = wrap.getBoundingClientRect();
      qx(e.clientX - r.left);
      qy(e.clientY - r.top);
      pointer.par = ((e.clientX - r.left) / W - 0.5) * 18;
    };
    window.addEventListener('pointermove', onMove, { passive: true });

    // GSAP-driven red-glitch envelope, scheduled to recur "from time to time"
    const glitch = { v: 0 };
    let glitchTl: gsap.core.Timeline | null = null;
    const scheduleGlitch = () => {
      glitchTl = gsap.timeline({
        delay: 5.5 + Math.random() * 8,
        onComplete: scheduleGlitch,
      });
      glitchTl
        .to(glitch, { v: 1, duration: 0.06, ease: 'power2.in' })
        .to(glitch, { v: 0.5, duration: 0.2, ease: 'steps(10)' })
        .to(glitch, { v: 1, duration: 0.08 })
        .to(glitch, { v: 0, duration: 0.42, ease: 'power2.out' });
      gsap.fromTo(
        wrap,
        { x: -4 },
        { x: 0, duration: 0.5, ease: 'elastic.out(1, 0.3)', delay: glitchTl.delay() },
      );
    };
    scheduleGlitch();

    const t0 = performance.now();
    let raf = 0;
    const draw = (now: number) => {
      const t = (now - t0) / 1000;
      const g = glitch.v;
      ctx.clearRect(0, 0, W, H);
      const shake = g > 0 ? (Math.random() - 0.5) * 7 * g : 0;
      const par = pointer.par;

      for (let j = 0; j < rows; j++) {
        const cy = j * CELL;
        for (let i = 0; i < cols; i++) {
          const cx = i * CELL;
          const m = field(cx, cy);
          if (m <= 0.02) continue;

          const wave = 0.5 + 0.5 * Math.sin(t * 0.5 + i * 0.16 + j * 0.12);
          let bright = (0.13 + 0.1 * wave) * m;

          const dx = cx - pointer.x;
          const dy = cy - pointer.y;
          bright += 0.5 * Math.exp(-(dx * dx + dy * dy) / (SPOT * SPOT));

          let rgb = calmColor(i * 0.02 + j * 0.014 + t * 0.05);
          let ox = par * (0.4 + 0.6 * m);

          if (g > 0) {
            const slice = 0.5 + 0.5 * Math.sin(j * 1.9 + Math.floor(t * 22) * 1.3);
            if (slice > 1 - 0.7 * g) ox += (Math.random() - 0.5) * 36 * g;
            rgb = mix(rgb, ERR, g * (0.72 + 0.28 * slice));
            bright = bright * (1 - 0.4 * g) + g * 0.34 * (0.5 + 0.5 * Math.sin(i * 7.3 + j * 3.1 + t * 45));
            if (Math.random() < 0.06 * g) continue; // dropouts
          }

          const a = clamp(bright, 0, 0.78);
          if (a < 0.012) continue;
          ctx.fillStyle = `rgba(${rgb[0] | 0},${rgb[1] | 0},${rgb[2] | 0},${a})`;
          ctx.fillRect(cx + GAP / 2 + ox + shake, cy + GAP / 2, CELL - GAP, CELL - GAP);
        }
      }

      if (g > 0.01) {
        // unmistakable error flash + a couple of bright scan bands
        ctx.fillStyle = `rgba(224,42,38,${0.07 * g})`;
        ctx.fillRect(0, 0, W, H);
        ctx.fillStyle = `rgba(255,90,80,${0.16 * g})`;
        for (let k = 0; k < 2; k++) {
          const by = (Math.sin(t * 30 + k * 2.1) * 0.5 + 0.5) * H;
          ctx.fillRect(0, by, W, 2);
        }
      }
      raf = requestAnimationFrame(draw);
    };
    raf = requestAnimationFrame(draw);

    // smooth intro
    gsap.fromTo(cv, { opacity: 0 }, { opacity: 1, duration: 1.3, ease: 'power2.out' });

    // GSAP ScrollTrigger — fade + drift the backdrop out as you leave the hero
    gsap.registerPlugin(ScrollTrigger);
    const fade = gsap.to(wrap, {
      opacity: 0,
      y: -70,
      ease: 'none',
      scrollTrigger: {
        trigger: wrap,
        start: 'top top',
        end: 'bottom top',
        scrub: 0.4,
      },
    });

    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      window.removeEventListener('pointermove', onMove);
      glitchTl?.kill();
      fade.scrollTrigger?.kill();
      fade.kill();
      gsap.killTweensOf([glitch, pointer, cv, wrap]);
    };
  }, []);

  return (
    <div
      ref={wrapRef}
      aria-hidden
      className="absolute top-0 left-0 right-0 z-0 pointer-events-none overflow-hidden"
      style={{
        height: '100vh',
        maskImage: 'linear-gradient(to bottom, #000 58%, transparent 100%)',
        WebkitMaskImage: 'linear-gradient(to bottom, #000 58%, transparent 100%)',
      }}
    >
      <canvas
        ref={canvasRef}
        className="block h-full w-full"
        style={{ filter: 'blur(0.7px)' }}
      />
      <div
        className="absolute inset-0"
        style={{
          background:
            'radial-gradient(ellipse 60% 46% at 50% 40%, rgba(10,11,13,0.72) 0%, rgba(10,11,13,0.25) 45%, transparent 70%)',
        }}
      />
    </div>
  );
}
