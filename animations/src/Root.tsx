import React from "react";
import { Composition } from "remotion";
import { FadeSlide } from "./01-FadeSlide";
import { StaggeredList } from "./02-StaggeredList";
import { MorphShape } from "./03-MorphShape";
import { CardReveal } from "./04-CardReveal";
import { Typewriter } from "./05-Typewriter";
import { ProgressBar } from "./06-ProgressBar";
import { TabSwitch } from "./07-TabSwitch";
import { ButtonPulse } from "./08-ButtonPulse";

const W = 800;
const H = 800;
const FPS = 30;

export const RemotionRoot: React.FC = () => (
  <>
    <Composition
      id="FadeSlide"
      component={FadeSlide}
      durationInFrames={90}
      fps={FPS}
      width={W}
      height={H}
    />
    <Composition
      id="StaggeredList"
      component={StaggeredList}
      durationInFrames={120}
      fps={FPS}
      width={W}
      height={H}
    />
    <Composition
      id="MorphShape"
      component={MorphShape}
      durationInFrames={130}
      fps={FPS}
      width={W}
      height={H}
    />
    <Composition
      id="CardReveal"
      component={CardReveal}
      durationInFrames={120}
      fps={FPS}
      width={W}
      height={H}
    />
    <Composition
      id="Typewriter"
      component={Typewriter}
      durationInFrames={135}
      fps={FPS}
      width={W}
      height={H}
    />
    <Composition
      id="ProgressBar"
      component={ProgressBar}
      durationInFrames={120}
      fps={FPS}
      width={W}
      height={H}
    />
    <Composition
      id="TabSwitch"
      component={TabSwitch}
      durationInFrames={135}
      fps={FPS}
      width={W}
      height={H}
    />
    <Composition
      id="ButtonPulse"
      component={ButtonPulse}
      durationInFrames={120}
      fps={FPS}
      width={W}
      height={H}
    />
  </>
);
