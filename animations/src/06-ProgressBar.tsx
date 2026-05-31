/**
 * Animation 6: Progress / Loading
 * A minimal progress bar fills to 100% with a live counter.
 * A subtle shimmer sweep runs along the fill.
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
const MUTED = "#333333";
const TRACK = "#1E1E1E";

export const ProgressBar: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();

  const fillSpring = spring({
    frame: frame - 10,
    fps,
    config: { damping: 40, stiffness: 30, mass: 1.2 },
    durationInFrames: 90,
  });

  const fillPct = interpolate(fillSpring, [0, 1], [0, 100]);
  const displayPct = Math.round(fillPct);

  // Shimmer position
  const shimmerX = interpolate(fillPct, [0, 100], [-60, 100]);

  const labelOpacity = interpolate(frame, [0, 12], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const exitOpacity = interpolate(
    frame,
    [durationInFrames - 20, durationInFrames - 5],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );

  const checkOpacity = interpolate(
    fillPct,
    [96, 100],
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
        padding: "0 120px",
        gap: 20,
        opacity: exitOpacity,
      }}
    >
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          opacity: labelOpacity,
        }}
      >
        <span
          style={{
            fontFamily: "system-ui, -apple-system, sans-serif",
            fontSize: 12,
            letterSpacing: "0.10em",
            textTransform: "uppercase",
            color: MUTED,
          }}
        >
          Loading assets
        </span>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span
            style={{
              fontFamily:
                '"SF Mono", "Fira Code", monospace',
              fontSize: 13,
              color: WHITE,
              fontVariantNumeric: "tabular-nums",
            }}
          >
            {String(displayPct).padStart(3, " ")}%
          </span>
          <div
            style={{
              width: 16,
              height: 16,
              borderRadius: "50%",
              border: `2px solid ${WHITE}`,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              opacity: checkOpacity,
            }}
          >
            <div
              style={{
                width: 6,
                height: 6,
                borderRadius: "50%",
                background: WHITE,
              }}
            />
          </div>
        </div>
      </div>

      {/* Track */}
      <div
        style={{
          height: 3,
          background: TRACK,
          borderRadius: 1.5,
          overflow: "hidden",
          position: "relative",
        }}
      >
        {/* Fill */}
        <div
          style={{
            position: "absolute",
            inset: 0,
            width: `${fillPct}%`,
            background: WHITE,
            borderRadius: 1.5,
            overflow: "hidden",
          }}
        >
          {/* Shimmer */}
          <div
            style={{
              position: "absolute",
              top: 0,
              left: `${shimmerX}%`,
              width: 60,
              height: "100%",
              background:
                "linear-gradient(90deg, transparent, rgba(255,255,255,0.5), transparent)",
            }}
          />
        </div>
      </div>

      {/* Step indicators */}
      <div
        style={{
          display: "flex",
          gap: 8,
          opacity: labelOpacity,
        }}
      >
        {["Init", "Fetch", "Parse", "Render", "Done"].map((step, i) => {
          const threshold = i * 20 + 10;
          const active = fillPct >= threshold;
          return (
            <div
              key={step}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 5,
                opacity: active ? 1 : 0.25,
                transition: "opacity 0.2s",
              }}
            >
              <div
                style={{
                  width: 5,
                  height: 5,
                  borderRadius: "50%",
                  background: WHITE,
                }}
              />
              <span
                style={{
                  fontFamily: "system-ui, -apple-system, sans-serif",
                  fontSize: 11,
                  color: WHITE,
                  letterSpacing: "0.06em",
                }}
              >
                {step}
              </span>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};
