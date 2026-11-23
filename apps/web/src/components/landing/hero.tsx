"use client";
import dynamic from "next/dynamic";
import { useRef } from "react";
import { useReducedMotion, useScroll } from "motion/react";
import { CookingPot, Fingerprint, HandCoins } from "@phosphor-icons/react";
import { ButtonLink } from "@/components/ui/button";

// three.js is large: load it only in the browser, after the hero text has painted.
const RoomScene = dynamic(() => import("@/components/three/room-scene"), {
  ssr: false,
  loading: () => <div className="h-full w-full animate-pulse rounded-[40px] bg-bg-2" />,
});

const facts = [
  { icon: CookingPot, label: "Meals included" },
  { icon: Fingerprint, label: "Fingerprint entry" },
  { icon: HandCoins, label: "50% deposit back" },
];

export function Hero() {
  const stage = useRef<HTMLDivElement>(null);
  const reduce = useReducedMotion() ?? false;
  const { scrollYProgress } = useScroll({ target: stage, offset: ["start end", "end start"] });

  return (
    <section className="relative overflow-hidden pt-28 md:pt-36">
      <div className="mx-auto max-w-5xl px-4 text-center">
        <h1 className="text-[16vw] leading-[0.9] font-semibold tracking-[-0.055em] md:text-[124px]">
          Live well.<br />Pay once.
        </h1>
        <p className="mx-auto mt-6 max-w-[34ch] text-lg text-ink-2 md:text-xl">
          Furnished rooms, home-cooked meals and secure entry. One monthly rent.
        </p>
        <div className="mt-8 flex items-center justify-center gap-2">
          <ButtonLink href="#visit">Book a visit</ButtonLink>
          <ButtonLink href="#rooms" variant="outline">See the rooms</ButtonLink>
        </div>
      </div>

      <div ref={stage} className="relative mx-auto mt-6 h-[62vh] max-w-6xl md:mt-2 md:h-[78vh]">
        <RoomScene scroll={scrollYProgress} reduce={reduce} />
        <p className="pointer-events-none absolute bottom-3 left-1/2 hidden -translate-x-1/2 text-sm text-ink-3 md:block">Drag to look around</p>
      </div>

      <ul className="mx-auto mb-4 flex max-w-3xl flex-wrap items-center justify-center gap-3 px-4">
        {facts.map((f) => (
          <li key={f.label} className="flex items-center gap-2 rounded-full border border-black/10 bg-white px-4 py-2.5 text-[15px] font-medium">
            <f.icon size={20} weight="regular" /> {f.label}
          </li>
        ))}
      </ul>
    </section>
  );
}
