/**
 * Animation 8: Button States + Ripple
 * A button cycles through idle → hover (scale) → press → ripple → reset.
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

// Timeline keyframes
const HOVER_START = 15;
const PRESS_START = 40;
const RIPPLE_START = 50;
const RESET_START = 90;

const Ripple: React.FC<{ delay: number; size: number; opacity: number }> = ({
  delay,
  size,
  opacity: baseOpacity,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const p = spring({
    frame: frame - delay,
    fps,
    config: { damping: 40, stiffness: 50 },
    durationInFrames: 40,
  });

  const scale = interpolate(p, [0, 1], [0, 1]);
  const opacity = interpolate(p, [0, 0.3, 1], [0, baseOpacity, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <div
      style={{
        position: "absolute",
        width: size,
        height: size,
        borderRadius: "50%",
        border: `1.5px solid ${WHITE}`,
        transform: `scale(${scale})`,
        opacity,
        pointerEvents: "none",
      }}
    />
  );
};

export const ButtonPulse: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();

  // Hover: subtle scale up
  const hoverSpring = spring({
    frame: frame - HOVER_START,
    fps,
    config: { damping: 20, stiffness: 150 },
  });
  const unhoverSpring = spring({
    frame: frame - RESET_START,
    fps,
    config: { damping: 20, stiffness: 150 },
  });

  const hoverScale =
    interpolate(hoverSpring, [0, 1], [1, 1.06]) -
    interpolate(unhoverSpring, [0, 1], [0, 0.06]);

  // Press: scale down
  const pressSpring = spring({
    frame: frame - PRESS_START,
    fps,
    config: { damping: 30, stiffness: 300 },
    durationInFrames: 10,
  });
  const unpressSpring = spring({
    frame: frame - RIPPLE_START,
    fps,
    config: { damping: 22, stiffness: 150 },
    durationInFrames: 15,
  });

  const pressScale =
    interpolate(pressSpring, [0, 1], [0, -0.08]) +
    interpolate(unpressSpring, [0, 1], [0, 0.08]);

  const scale = hoverScale + pressScale;

  // Background invert on press
  const invertProgress = spring({
    frame: frame - PRESS_START,
    fps,
    config: { damping: 30, stiffness: 300 },
    durationInFrames: 8,
  });
  const uninvertProgress = spring({
    frame: frame - RIPPLE_START,
    fps,
    config: { damping: 30, stiffness: 200 },
    durationInFrames: 12,
  });

  const bgBrightness =
    interpolate(invertProgress, [0, 1], [0, 255]) -
    interpolate(uninvertProgress, [0, 1], [0, 255]);
  const bgAlpha = Math.max(0, Math.min(1, bgBrightness / 255));

  const labelOpacity = interpolate(frame, [0, 14], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const exitOpacity = interpolate(
    frame,
    [durationInFrames - 18, durationInFrames - 5],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );

  const hintOpacity = interpolate(frame, [0, 14, HOVER_START - 2], [0, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        background: BG,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: 32,
        opacity: exitOpacity,
      }}
    >
      <p
        style={{
          fontFamily: "system-ui, -apple-system, sans-serif",
          fontSize: 11,
          letterSpacing: "0.12em",
          textTransform: "uppercase",
          color: MUTED,
          margin: 0,
          opacity: hintOpacity,
        }}
      >
        Hover · Press · Release
      </p>

      {/* Button */}
      <div
        style={{
          position: "relative",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          transform: `scale(${scale})`,
          opacity: labelOpacity,
        }}
      >
        {/* Ripple rings */}
        <Ripple delay={RIPPLE_START} size={200} opacity={0.6} />
        <Ripple delay={RIPPLE_START + 8} size={280} opacity={0.3} />
        <Ripple delay={RIPPLE_START + 16} size={340} opacity={0.15} />

        {/* Button body */}
        <div
          style={{
            width: 160,
            height: 48,
            borderRadius: 12,
            border: `1.5px solid ${WHITE}`,
            background: `rgba(245,245,245,${bgAlpha})`,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <span
            style={{
              fontFamily: "system-ui, -apple-system, sans-serif",
              fontSize: 14,
              fontWeight: 500,
              letterSpacing: "0.06em",
              color: bgAlpha > 0.5 ? BG : WHITE,
            }}
          >
            Get Started
          </span>
        </div>
      </div>

      {/* Cursor dot */}
      <div
        style={{
          width: 8,
          height: 8,
          borderRadius: "50%",
          background: WHITE,
          opacity: interpolate(frame, [0, 14], [0, 0.5], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          }),
        }}
      />
    </AbsoluteFill>
  );
};
