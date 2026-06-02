/**
 * Animation 4: Card Reveal
 * A dark card scales up from below and its inner content fades in sequentially.
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
const CARD_BG = "#1A1A1A";
const WHITE = "#F5F5F5";
const MUTED = "#555555";
const ACCENT = "#E8E8E8";

const FadeIn: React.FC<{
  children: React.ReactNode;
  delay: number;
  fromY?: number;
}> = ({ children, delay, fromY = 16 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const p = spring({
    frame: frame - delay,
    fps,
    config: { damping: 30, stiffness: 100 },
  });

  return (
    <div
      style={{
        opacity: interpolate(p, [0, 1], [0, 1]),
        transform: `translateY(${interpolate(p, [0, 1], [fromY, 0])}px)`,
      }}
    >
      {children}
    </div>
  );
};

export const CardReveal: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();

  const cardSpring = spring({
    frame,
    fps,
    config: { damping: 20, stiffness: 70 },
  });

  const scale = interpolate(cardSpring, [0, 1], [0.82, 1]);
  const opacity = interpolate(cardSpring, [0, 0.4], [0, 1], {
    extrapolateRight: "clamp",
  });

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
        alignItems: "center",
        justifyContent: "center",
        opacity: exitOpacity,
      }}
    >
      <div
        style={{
          width: 320,
          background: CARD_BG,
          borderRadius: 20,
          padding: 28,
          opacity,
          transform: `scale(${scale})`,
          display: "flex",
          flexDirection: "column",
          gap: 20,
        }}
      >
        {/* Avatar row */}
        <FadeIn delay={8}>
          <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
            <div
              style={{
                width: 40,
                height: 40,
                borderRadius: 12,
                background: "#2E2E2E",
              }}
            />
            <div style={{ display: "flex", flexDirection: "column", gap: 5 }}>
              <div
                style={{ width: 90, height: 8, borderRadius: 4, background: ACCENT }}
              />
              <div
                style={{ width: 60, height: 6, borderRadius: 3, background: MUTED }}
              />
            </div>
          </div>
        </FadeIn>

        {/* Divider */}
        <FadeIn delay={16}>
          <div style={{ height: 1, background: "#2A2A2A" }} />
        </FadeIn>

        {/* Content lines */}
        <FadeIn delay={20}>
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            <div style={{ width: "100%", height: 7, borderRadius: 3.5, background: "#2E2E2E" }} />
            <div style={{ width: "85%", height: 7, borderRadius: 3.5, background: "#2E2E2E" }} />
            <div style={{ width: "70%", height: 7, borderRadius: 3.5, background: "#2A2A2A" }} />
          </div>
        </FadeIn>

        {/* Stat row */}
        <FadeIn delay={28}>
          <div style={{ display: "flex", gap: 12 }}>
            {["24", "8.2k", "99%"].map((val, i) => (
              <div
                key={i}
                style={{
                  flex: 1,
                  background: "#242424",
                  borderRadius: 10,
                  padding: "10px 0",
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  gap: 4,
                }}
              >
                <span
                  style={{
                    fontFamily: "system-ui, -apple-system, sans-serif",
                    fontSize: 16,
                    fontWeight: 500,
                    color: WHITE,
                  }}
                >
                  {val}
                </span>
                <div style={{ width: 28, height: 5, borderRadius: 2.5, background: MUTED }} />
              </div>
            ))}
          </div>
        </FadeIn>

        {/* CTA button */}
        <FadeIn delay={38}>
          <div
            style={{
              background: WHITE,
              borderRadius: 10,
              padding: "12px 0",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <span
              style={{
                fontFamily: "system-ui, -apple-system, sans-serif",
                fontSize: 13,
                fontWeight: 600,
                color: BG,
                letterSpacing: "0.04em",
                textTransform: "uppercase",
              }}
            >
              Connect
            </span>
          </div>
        </FadeIn>
      </div>
    </AbsoluteFill>
  );
};
