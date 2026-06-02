/**
 * Animation 3: Shape Morph
 * A white dot expands and morphs through circle → pill → card → circle.
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
const MUTED = "#555555";

export const MorphShape: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Phase 1: dot → circle (0-25)
  const expand = spring({
    frame,
    fps,
    config: { damping: 18, stiffness: 80 },
    durationInFrames: 25,
  });

  // Phase 2: circle → pill (30-55)
  const pillProgress = spring({
    frame: frame - 30,
    fps,
    config: { damping: 22, stiffness: 90 },
    durationInFrames: 25,
  });

  // Phase 3: pill → card (60-85)
  const cardProgress = spring({
    frame: frame - 60,
    fps,
    config: { damping: 22, stiffness: 90 },
    durationInFrames: 25,
  });

  // Phase 4: card → dissolve (95-115)
  const dissolve = spring({
    frame: frame - 95,
    fps,
    config: { damping: 25, stiffness: 100 },
    durationInFrames: 20,
  });

  const size = interpolate(expand, [0, 1], [6, 120]);
  const width = interpolate(pillProgress, [0, 1], [size, 260]);
  const height = interpolate(cardProgress, [0, 1], [size, 160]);
  const borderRadius = interpolate(pillProgress, [0, 1], [size / 2, 60]);
  const cardRadius = interpolate(cardProgress, [0, 1], [borderRadius, 16]);

  const textOpacity = interpolate(cardProgress, [0.5, 1], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const opacity = interpolate(dissolve, [0, 1], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const dotOpacity = interpolate(dissolve, [0, 0.3], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        background: BG,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <div style={{ position: "relative", display: "flex", alignItems: "center", justifyContent: "center" }}>
        <div
          style={{
            width,
            height: Math.min(width, height),
            background: WHITE,
            borderRadius: cardRadius,
            opacity,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            flexDirection: "column",
            gap: 8,
            overflow: "hidden",
          }}
        >
          <div
            style={{
              opacity: textOpacity,
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: 8,
            }}
          >
            <div
              style={{
                width: 32,
                height: 32,
                borderRadius: 8,
                background: BG,
              }}
            />
            <div
              style={{
                width: 80,
                height: 6,
                borderRadius: 3,
                background: MUTED,
              }}
            />
            <div
              style={{
                width: 56,
                height: 6,
                borderRadius: 3,
                background: "#2A2A2A",
              }}
            />
          </div>
        </div>

        {/* Respawn dot */}
        <div
          style={{
            position: "absolute",
            width: 6,
            height: 6,
            borderRadius: "50%",
            background: WHITE,
            opacity: dotOpacity,
          }}
        />
      </div>
    </AbsoluteFill>
  );
};
