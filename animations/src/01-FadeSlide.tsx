/**
 * Animation 1: Fade + Slide Up
 * A headline and subtitle emerge from below with a soft fade.
 * Duration: 3s @ 30fps
 */
import React from "react";
import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
  Easing,
} from "remotion";

const BG = "#0F0F0F";
const WHITE = "#F5F5F5";
const MUTED = "#777777";

const SlideUp: React.FC<{
  children: React.ReactNode;
  delay: number;
  style?: React.CSSProperties;
}> = ({ children, delay, style }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const progress = spring({
    frame: frame - delay,
    fps,
    config: { damping: 28, stiffness: 90, mass: 1 },
  });

  const opacity = interpolate(progress, [0, 1], [0, 1]);
  const translateY = interpolate(progress, [0, 1], [40, 0]);

  return (
    <div
      style={{
        opacity,
        transform: `translateY(${translateY}px)`,
        ...style,
      }}
    >
      {children}
    </div>
  );
};

export const FadeSlide: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();

  const exitProgress = interpolate(
    frame,
    [durationInFrames - 20, durationInFrames - 5],
    [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );

  return (
    <AbsoluteFill
      style={{
        background: BG,
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        alignItems: "center",
        gap: 16,
        opacity: 1 - exitProgress,
      }}
    >
      <SlideUp delay={0}>
        <div
          style={{
            width: 40,
            height: 2,
            background: WHITE,
            marginBottom: 24,
          }}
        />
      </SlideUp>

      <SlideUp delay={6}>
        <p
          style={{
            fontFamily: "system-ui, -apple-system, sans-serif",
            fontSize: 48,
            fontWeight: 300,
            color: WHITE,
            letterSpacing: "-0.02em",
            margin: 0,
            textAlign: "center",
          }}
        >
          Less is more.
        </p>
      </SlideUp>

      <SlideUp delay={14}>
        <p
          style={{
            fontFamily: "system-ui, -apple-system, sans-serif",
            fontSize: 16,
            fontWeight: 400,
            color: MUTED,
            letterSpacing: "0.08em",
            textTransform: "uppercase",
            margin: 0,
            textAlign: "center",
          }}
        >
          Minimalistic UI · Motion Design
        </p>
      </SlideUp>
    </AbsoluteFill>
  );
};
