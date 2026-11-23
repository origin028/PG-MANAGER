"use client";
import Image from "next/image";
import { Reveal } from "@/components/ui/reveal";
import { useEffect, useRef, useState } from "react";
import { motion, useScroll, useTransform } from "motion/react";
import { IMG } from "@/lib/photos";

const items = [
  { title: "Cooked fresh, daily", line: "Home-style meals, included in your rent.", img: IMG.thali },
  { title: "A fixed weekly menu", line: "You always know what is for dinner.", img: IMG.paneer },
  { title: "Check it in the app", line: "This week's menu, one tap away.", img: IMG.curry },
  { title: "Eat together", line: "Shared meals, new friends.", img: IMG.friends },
];

/**
 * Desktop: vertical scroll pans the strip horizontally while the section is pinned.
 * Mobile and reduced motion: a native swipeable row (no scroll hijack).
 */
export function Food() {
  const wrap = useRef<HTMLElement>(null);
  const track = useRef<HTMLDivElement>(null);
  const [distance, setDistance] = useState(0);

  useEffect(() => {
    const desktop = window.matchMedia("(min-width: 768px) and (prefers-reduced-motion: no-preference)");
    const measure = () => setDistance(desktop.matches && track.current ? track.current.scrollWidth - window.innerWidth : 0);
    measure();
    window.addEventListener("resize", measure);
    desktop.addEventListener("change", measure);
    return () => { window.removeEventListener("resize", measure); desktop.removeEventListener("change", measure); };
  }, []);

  const { scrollYProgress } = useScroll({ target: wrap, offset: ["start start", "end end"] });
  const x = useTransform(scrollYProgress, (v) => -v * distance);

  return (
    <section id="food" ref={wrap} className="relative scroll-mt-10 bg-white" style={{ height: distance ? `calc(100dvh + ${distance}px)` : undefined }}>
      <div className={distance ? "sticky top-0 flex h-[100dvh] flex-col justify-center overflow-hidden" : "py-24"}>
        <Reveal className="mx-auto w-full max-w-6xl px-4"><h2 className="text-5xl leading-[0.95] font-semibold tracking-[-0.05em] md:text-7xl">
          Food that tastes like home.
        </h2></Reveal>
        <motion.div
          ref={track}
          style={{ x }}
          className={`mt-12 flex gap-5 px-4 md:gap-7 md:px-[max(1rem,calc((100vw-72rem)/2+1rem))] ${distance ? "" : "snap-x snap-mandatory overflow-x-auto pb-4"}`}
        >
          {items.map((it) => (
            <article key={it.title} className="relative h-[58vh] max-h-[560px] min-h-[380px] w-[78vw] shrink-0 snap-start overflow-hidden rounded-[32px] md:w-[30rem]">
              <Image src={it.img(900, 1100)} alt={it.title} fill sizes="(min-width: 768px) 30rem, 80vw" className="object-cover" />
              <div className="glass absolute inset-x-4 bottom-4 rounded-2xl p-5">
                <h3 className="text-2xl font-semibold tracking-tight">{it.title}</h3>
                <p className="mt-1 text-[15px] text-ink-2">{it.line}</p>
              </div>
            </article>
          ))}
        </motion.div>
      </div>
    </section>
  );
}
