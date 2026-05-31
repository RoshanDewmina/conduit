/**
 * Animation 2: Staggered List Entrance
 * Five rows slide in from the right with spring-staggered timing.
 * Duration: 4s @ 30fps
 */
import React from "react";
import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

const BG = "#0F0F0F";
const WHITE = "#F5F5F5";
const MUTED = "#444444";
const DIM = "#2A2A2A";

const ITEMS = [
  { label: "Typography", value: "96%" },
  { label: "Spacing", value: "88%" },
  { label: "Colour", value: "74%" },
  { label: "Motion", value: "61%" },
  { label: "Contrast", value: "50%" },
];

const BASE_DELAY = 10;
const STAGGER = 12;

const Row: React.FC<{
  label: string;
  value: string;
  delay: number;
  index: number;
}> = ({ label, value, delay, index }) => {
  const frame = useCurrentFrame();
  const { fps, width } = useVideoConfig();

  const progress = spring({
    frame: frame - delay,
    fps,
    config: { damping: 22, stiffness: 100 },
  });

  const opacity = interpolate(progress, [0, 1], [0, 1]);
  const translateX = interpolate(progress, [0, 1], [60, 0]);

  const barFill = spring({
    frame: frame - delay - 5,
    fps,
    config: { damping: 30, stiffness: 60 },
  });

  const barWidth = interpolate(barFill, [0, 1], [0, parseFloat(value)]);

  return (
    <div
      style={{
        opacity,
        transform: `translateX(${translateX}px)`,
        display: "flex",
        flexDirection: "column",
        gap: 8,
      }}
    >
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          fontFamily: "system-ui, -apple-system, sans-serif",
        }}
      >
        <span style={{ fontSize: 14, color: WHITE, letterSpacing: "0.04em" }}>
          {label}
        </span>
        <span style={{ fontSize: 14, color: MUTED, fontVariantNumeric: "tabular-nums" }}>
          {value}
        </span>
      </div>

      <div
        style={{
          height: 2,
          background: DIM,
          borderRadius: 1,
          overflow: "hidden",
        }}
      >
        <div
          style={{
            height: "100%",
            width: `${barWidth}%`,
            background: WHITE,
            borderRadius: 1,
          }}
        />
      </div>
    </div>
  );
};

export const StaggeredList: React.FC = () => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();

  const exitOpacity = interpolate(
    frame,
    [durationInFrames - 20, durationInFrames - 5],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );

  return (
    <AbsoluteFill
      style={{
        background: BG,
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        padding: "0 120px",
        gap: 32,
        opacity: exitOpacity,
      }}
    >
      <p
        style={{
          fontFamily: "system-ui, -apple-system, sans-serif",
          fontSize: 11,
          fontWeight: 400,
          color: MUTED,
          letterSpacing: "0.14em",
          textTransform: "uppercase",
          margin: 0,
        }}
      >
        Design Principles
      </p>

      <div style={{ display: "flex", flexDirection: "column", gap: 28 }}>
        {ITEMS.map((item, i) => (
          <Row
            key={item.label}
            label={item.label}
            value={item.value}
            delay={BASE_DELAY + i * STAGGER}
            index={i}
          />
        ))}
      </div>
    </AbsoluteFill>
  );
};
