"use client";
import Image from "next/image";
import { useRef } from "react";
import { motion, useScroll, useSpring, useTransform } from "motion/react";
import { ButtonLink } from "@/components/ui/button";
import { P, photo } from "@/lib/photos";

/**
 * Apple-style reveal: the photo starts tilted back in 3D and rises flat and full-size
 * as the visitor scrolls. Floating glass chips sit at different depths (parallax).
 */
export function Hero() {
  const stage = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({ target: stage, offset: ["start end", "center center"] });
  const p = useSpring(scrollYProgress, { stiffness: 120, damping: 30, mass: 0.4 });
  const rotateX = useTransform(p, [0, 1], [32, 0]);
  const scale = useTransform(p, [0, 1], [0.86, 1]);
  const chipA = useTransform(p, [0, 1], [80, -10]);
  const chipB = useTransform(p, [0, 1], [140, 20]);

  return (
    <section className="relative overflow-hidden pt-32 md:pt-40">
      <div className="mx-auto max-w-5xl px-4 text-center">
        <p className="reveal text-[15px] font-medium text-ink-3" data-in="">Co-living and women-only homes</p>
        <h1 className="mt-4 text-[17vw] leading-[0.9] font-semibold tracking-[-0.06em] md:text-[132px]">
          Live well.<br />Pay once.
        </h1>
        <p className="mx-auto mt-7 max-w-[34ch] text-lg text-ink-2 md:text-xl">
          Furnished rooms, home-cooked meals and secure entry. All in one monthly rent.
        </p>
        <div className="mt-9 flex items-center justify-center gap-2">
          <ButtonLink href="#visit">Book a visit</ButtonLink>
          <ButtonLink href="#story" variant="ghost">See life here</ButtonLink>
        </div>
      </div>

      <div ref={stage} className="mx-auto mt-16 max-w-6xl px-4 [perspective:1400px] md:mt-20">
        <motion.div
          style={{ rotateX, scale, transformOrigin: "50% 0%" }}
          className="motion-safe-3d relative aspect-[4/5] overflow-hidden rounded-[28px] bg-bg-2 shadow-[0_60px_120px_-40px_rgb(0_0_0/0.45)] md:aspect-[16/9] md:rounded-[40px]"
        >
          <Image src={photo(P.bed, 2000, 1125)} alt="A freshly made bed with a morning coffee" fill priority sizes="(min-width: 1152px) 1120px, 100vw" className="object-cover" />
          <motion.div style={{ y: chipA }} className="motion-safe-3d glass absolute top-6 left-6 rounded-2xl px-4 py-3 md:top-10 md:left-10">
            <p className="text-[13px] text-ink-2">Monthly rent</p>
            <p className="text-lg font-semibold tracking-tight">Nothing extra</p>
          </motion.div>
          <motion.div style={{ y: chipB }} className="motion-safe-3d glass absolute right-6 bottom-6 rounded-2xl px-4 py-3 md:right-10 md:bottom-10">
            <p className="text-[13px] text-ink-2">Entry</p>
            <p className="text-lg font-semibold tracking-tight">Fingerprint only</p>
          </motion.div>
        </motion.div>
      </div>
    </section>
  );
}
