/**
 * Animation 7: Tab Switch with Sliding Indicator
 * A 3-tab nav where the active underline smoothly slides between tabs.
 * Content below fades and slides with each switch.
 * Duration: 4.5s @ 30fps
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
const CARD_BG = "#141414";
const WHITE = "#F5F5F5";
const MUTED = "#4A4A4A";
const DIM = "#1E1E1E";

const TABS = ["Overview", "Details", "Settings"];
const TAB_WIDTH = 90;
const TAB_SWITCH_FRAMES = [0, 40, 85];

const ContentBlock: React.FC<{ lines: number[]; opacity: number; translateY: number }> = ({
  lines,
  opacity,
  translateY,
}) => (
  <div
    style={{
      opacity,
      transform: `translateY(${translateY}px)`,
      display: "flex",
      flexDirection: "column",
      gap: 10,
    }}
  >
    {lines.map((w, i) => (
      <div
        key={i}
        style={{
          width: `${w}%`,
          height: 8,
          borderRadius: 4,
          background: DIM,
        }}
      />
    ))}
  </div>
);

export const TabSwitch: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();

  // Which tab is active based on frame
  const activeTab =
    frame >= TAB_SWITCH_FRAMES[2]
      ? 2
      : frame >= TAB_SWITCH_FRAMES[1]
      ? 1
      : 0;

  // Smooth indicator position
  const tab1Spring = spring({
    frame: frame - TAB_SWITCH_FRAMES[1],
    fps,
    config: { damping: 24, stiffness: 120 },
  });
  const tab2Spring = spring({
    frame: frame - TAB_SWITCH_FRAMES[2],
    fps,
    config: { damping: 24, stiffness: 120 },
  });

  const indicatorX =
    interpolate(tab1Spring, [0, 1], [0, TAB_WIDTH]) +
    interpolate(tab2Spring, [0, 1], [0, TAB_WIDTH]);

  const exitOpacity = interpolate(
    frame,
    [durationInFrames - 20, durationInFrames - 5],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );

  const wrapOpacity = interpolate(frame, [0, 12], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const CONTENT = [
    [100, 85, 72, 60],
    [90, 100, 55],
    [70, 95, 80, 40],
  ];

  return (
    <AbsoluteFill
      style={{
        background: BG,
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        padding: "0 120px",
        opacity: exitOpacity * wrapOpacity,
      }}
    >
      <div
        style={{
          background: CARD_BG,
          borderRadius: 16,
          padding: 28,
          display: "flex",
          flexDirection: "column",
          gap: 24,
        }}
      >
        {/* Tab bar */}
        <div style={{ position: "relative" }}>
          <div style={{ display: "flex" }}>
            {TABS.map((tab, i) => {
              const isActive = activeTab === i;
              return (
                <div
                  key={tab}
                  style={{
                    width: TAB_WIDTH,
                    paddingBottom: 12,
                    display: "flex",
                    justifyContent: "center",
                  }}
                >
                  <span
                    style={{
                      fontFamily: "system-ui, -apple-system, sans-serif",
                      fontSize: 13,
                      fontWeight: isActive ? 500 : 400,
                      color: isActive ? WHITE : MUTED,
                      letterSpacing: "0.02em",
                    }}
                  >
                    {tab}
                  </span>
                </div>
              );
            })}
          </div>

          {/* Bottom track */}
          <div
            style={{
              position: "absolute",
              bottom: 0,
              left: 0,
              right: 0,
              height: 1,
              background: "#222222",
            }}
          />

          {/* Sliding indicator */}
          <div
            style={{
              position: "absolute",
              bottom: 0,
              left: indicatorX,
              width: TAB_WIDTH,
              height: 2,
              background: WHITE,
              borderRadius: 1,
            }}
          />
        </div>

        {/* Content area */}
        {TABS.map((_, i) => {
          const isActive = activeTab === i;
          const switchFrame = TAB_SWITCH_FRAMES[i];
          const contentSpring = spring({
            frame: frame - switchFrame - 5,
            fps,
            config: { damping: 28, stiffness: 100 },
          });
          const contentOpacity = isActive
            ? interpolate(contentSpring, [0, 1], [0, 1])
            : 0;
          const contentY = isActive
            ? interpolate(contentSpring, [0, 1], [12, 0])
            : 0;

          return (
            <div
              key={i}
              style={{
                position: i === 0 ? "relative" : "absolute",
                opacity: contentOpacity,
                ...(i === 0 ? {} : { left: 28, right: 28, top: 76 }),
              }}
            >
              <ContentBlock
                lines={CONTENT[i]}
                opacity={1}
                translateY={contentY}
              />
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};
