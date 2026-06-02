/**
 * Animation 5: Typewriter
 * Text types out character by character on a dark background.
 * Cursor blinks after typing completes.
 * Duration: 4s @ 30fps
 */
import React from "react";
import {
  AbsoluteFill,
  interpolate,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

const BG = "#0F0F0F";
const WHITE = "#F5F5F5";
const MUTED = "#444444";

const LINES = [
  { text: "Design with intent.", delay: 0 },
  { text: "Move with purpose.", delay: 40 },
  { text: "Build what matters.", delay: 80 },
];

const CHARS_PER_FRAME = 0.5;

const TypeLine: React.FC<{
  text: string;
  delay: number;
  showCursor: boolean;
}> = ({ text, delay, showCursor }) => {
  const frame = useCurrentFrame();

  const charsToShow = Math.min(
    text.length,
    Math.max(0, Math.floor((frame - delay) * CHARS_PER_FRAME))
  );

  const visible = frame >= delay;
  const done = charsToShow >= text.length;

  const cursorOpacity =
    done
      ? frame % 30 < 18
        ? 1
        : 0
      : 1;

  if (!visible) return null;

  return (
    <div
      style={{
        fontFamily:
          '"SF Mono", "Fira Code", "Fira Mono", "Roboto Mono", monospace',
        fontSize: 22,
        fontWeight: 400,
        color: WHITE,
        letterSpacing: "0.01em",
        lineHeight: 1.6,
        display: "flex",
        alignItems: "center",
      }}
    >
      <span>{text.slice(0, charsToShow)}</span>
      {showCursor && (
        <span
          style={{
            display: "inline-block",
            width: 2,
            height: 22,
            background: WHITE,
            marginLeft: 3,
            opacity: cursorOpacity,
          }}
        />
      )}
    </div>
  );
};

export const Typewriter: React.FC = () => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();

  const exitOpacity = interpolate(
    frame,
    [durationInFrames - 18, durationInFrames - 5],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );

  const prefixOpacity = interpolate(frame, [0, 15], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        background: BG,
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        padding: "0 120px",
        gap: 4,
        opacity: exitOpacity,
      }}
    >
      <p
        style={{
          fontFamily:
            '"SF Mono", "Fira Code", "Fira Mono", monospace',
          fontSize: 11,
          color: MUTED,
          letterSpacing: "0.12em",
          textTransform: "uppercase",
          margin: "0 0 24px 0",
          opacity: prefixOpacity,
        }}
      >
        ~/manifesto
      </p>

      {LINES.map((line, i) => (
        <TypeLine
          key={i}
          text={line.text}
          delay={line.delay}
          showCursor={i === LINES.length - 1}
        />
      ))}
    </AbsoluteFill>
  );
};
