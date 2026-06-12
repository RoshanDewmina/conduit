'use client';

import { useRef, useEffect } from 'react';

type DotState = 'idle' | 'connecting' | 'thinking' | 'working' | 'error' | 'done';

const SPEC_RGB: [number, number, number][] = [
  [200, 66, 59], [226, 102, 44], [240, 146, 46], [242, 193, 78],
  [199, 123, 166], [126, 79, 181], [84, 96, 200],
];
const RGB: Record<string, [number, number, number]> = {
  blue: [47, 67, 255], green: [54, 194, 107], red: [224, 83, 63],
  grey: [86, 89, 99],
};
const mix = (a: [number, number, number], b: [number, number, number], t: number): [number, number, number] =>
  [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const clamp = (v: number, lo = 0, hi = 1) => Math.max(lo, Math.min(hi, v));
const rgba = (c: [number, number, number], a: number) =>
  `rgba(${c[0] | 0},${c[1] | 0},${c[2] | 0},${a})`;

function dmField(
  state: DotState,
  x: number,
  y: number,
  t: number,
  cols: number,
  rows: number,
): { b: number; rgb: [number, number, number] } {
  switch (state) {
    case 'idle':
      return { b: 0.07 + 0.05 * Math.sin(t * 0.85 + x * 0.5 + y * 0.42), rgb: RGB.grey };
    case 'connecting': {
      const span = cols + 8, pos = ((t * 0.62) % 1) * span - 4, d = Math.abs(x - pos);
      const tail = x < pos ? clamp(1 - (pos - x) / 6) * 0.35 : 0;
      return { b: clamp(Math.max(1 - d / 2.2, tail) * 0.95, 0.05, 1), rgb: RGB.blue };
    }
    case 'thinking': {
      const nn = (Math.sin(x * 1.27 + t * 1.9) * Math.sin(y * 1.63 - t * 1.35) * 0.5 + 0.5);
      const b = 0.1 + 0.82 * Math.pow(nn, 2.6);
      let rgb = mix(RGB.blue, SPEC_RGB[5], clamp(y / Math.max(1, rows - 1))) as [number, number, number];
      const pop = Math.sin(x * 5.1 + y * 3.3 + t * 0.6);
      if (b > 0.62 && pop > 0.8) rgb = SPEC_RGB[(x * 3 + y) % 7];
      return { b, rgb };
    }
    case 'working': {
      const prog = (t * 0.34) % 1.18;
      const frac = cols <= 1 ? 0 : x / (cols - 1);
      const idx = Math.min(6, Math.floor(frac * 7));
      if (frac <= prog) {
        const edge = Math.max(0, 1 - (prog - frac) * 5);
        return { b: clamp(0.42 + 0.55 * edge + 0.08 * Math.sin(t * 5 + x * 0.6), 0.12, 1), rgb: SPEC_RGB[idx] };
      }
      return { b: 0.06, rgb: RGB.grey };
    }
    case 'error': {
      const flash = Math.sin(t * 6.5) > 0.35 ? 1 : 0.22;
      const jit = (Math.sin(x * 4.2 + y * 2.7 + Math.floor(t * 11)) * 0.5 + 0.5);
      return { b: clamp((0.14 + 0.78 * Math.pow(jit, 1.4)) * flash, 0.04, 1), rgb: RGB.red };
    }
    case 'done': {
      const cx = (cols - 1) / 2, cy = (rows - 1) / 2;
      const dist = Math.hypot((x - cx) / cols, (y - cy) / rows) * 2.2;
      const wave = clamp((t * 0.9) - dist * 1.4);
      return { b: clamp(wave * (0.5 + 0.35 * Math.sin(t * 1.2 + x * 0.3 + y * 0.25)) + 0.06, 0.04, 1), rgb: RGB.green };
    }
    default:
      return { b: 0.08, rgb: RGB.grey };
  }
}

export default function DotMatrix({
  state = 'idle',
  cols = 40,
  rows = 16,
  cell = 11,
  dot = 4.2,
  shape = 'round',
  speed = 1,
  glow = true,
  className,
  style = {},
}: {
  state?: DotState;
  cols?: number;
  rows?: number;
  cell?: number;
  dot?: number;
  shape?: 'round' | 'square';
  speed?: number;
  glow?: boolean;
  className?: string;
  style?: React.CSSProperties;
}) {
  const ref = useRef<HTMLCanvasElement>(null);
  const start = useRef(0);
  const stateRef = useRef(state);

  useEffect(() => {
    stateRef.current = state;
    start.current = performance.now();
  }, [state]);

  useEffect(() => {
    const cv = ref.current;
    if (!cv) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const W = cols * cell, H = rows * cell;
    cv.width = W * dpr;
    cv.height = H * dpr;
    cv.style.width = W + 'px';
    cv.style.height = H + 'px';
    const ctx = cv.getContext('2d')!;
    ctx.scale(dpr, dpr);
    let raf: number;

    const loop = (now: number) => {
      const t = ((now - start.current) / 1000) * speed;
      const st = stateRef.current;
      ctx.clearRect(0, 0, W, H);
      for (let y = 0; y < rows; y++) {
        for (let x = 0; x < cols; x++) {
          const { b, rgb } = dmField(st, x, y, t, cols, rows);
          const a = clamp(b);
          if (a < 0.04) continue;
          const px = x * cell + cell / 2, py = y * cell + cell / 2;
          ctx.fillStyle = rgba(rgb, a);
          if (glow && a > 0.55) { ctx.shadowColor = rgba(rgb, 0.9); ctx.shadowBlur = dot * 1.5; }
          else ctx.shadowBlur = 0;
          const sz = dot * (0.6 + 0.4 * a);
          if (shape === 'square') {
            ctx.fillRect(px - sz / 2, py - sz / 2, sz, sz);
          } else {
            ctx.beginPath();
            ctx.arc(px, py, sz / 2, 0, 6.2832);
            ctx.fill();
          }
        }
      }
      ctx.shadowBlur = 0;
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [cols, rows, cell, dot, shape, speed, glow]);

  return <canvas ref={ref} className={className} style={{ display: 'block', ...style }} />;
}
