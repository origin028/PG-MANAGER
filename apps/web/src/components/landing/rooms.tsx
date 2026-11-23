"use client";
import Image from "next/image";
import { Reveal } from "@/components/ui/reveal";
import { motion, useMotionValue, useSpring, useTransform } from "motion/react";
import type { PointerEvent } from "react";
import { ArrowRight } from "@phosphor-icons/react";
import { P, photo } from "@/lib/photos";

const rooms = [
  { title: "Co-living", line: "Students and working professionals.", img: P.desk },
  { title: "Women only", line: "Dedicated homes, women residents only.", img: P.dining },
];

/** A card that tilts in 3D toward the pointer. The glass label floats above it (translateZ). */
function TiltCard({ title, line, img }: (typeof rooms)[number]) {
  const mx = useMotionValue(0);
  const my = useMotionValue(0);
  const rx = useSpring(useTransform(my, [-0.5, 0.5], [9, -9]), { stiffness: 160, damping: 18 });
  const ry = useSpring(useTransform(mx, [-0.5, 0.5], [-11, 11]), { stiffness: 160, damping: 18 });
  const glareX = useTransform(mx, [-0.5, 0.5], ["0%", "100%"]);

  function move(e: PointerEvent<HTMLDivElement>) {
    if (e.pointerType !== "mouse") return;
    const r = e.currentTarget.getBoundingClientRect();
    mx.set((e.clientX - r.left) / r.width - 0.5);
    my.set((e.clientY - r.top) / r.height - 0.5);
  }
  function leave() { mx.set(0); my.set(0); }

  return (
    <div className="[perspective:1200px]" onPointerMove={move} onPointerLeave={leave}>
      <motion.a
        href="#visit"
        style={{ rotateX: rx, rotateY: ry, transformStyle: "preserve-3d" }}
        className="motion-safe-3d group relative block aspect-[4/5] rounded-[32px] shadow-[0_40px_80px_-30px_rgb(0_0_0/0.4)]"
      >
        <div className="absolute inset-0 overflow-hidden rounded-[32px]">
          <Image src={photo(img, 1000, 1250)} alt={title} fill sizes="(min-width: 768px) 50vw, 100vw" className="object-cover" />
          <motion.div
            aria-hidden
            style={{ left: glareX }}
            className="pointer-events-none absolute -top-1/2 h-[200%] w-1/3 -translate-x-1/2 rotate-12 bg-white/20 opacity-0 blur-2xl transition-opacity duration-500 group-hover:opacity-100"
          />
        </div>
        <div style={{ transform: "translateZ(60px)" }} className="glass absolute inset-x-5 bottom-5 flex items-end justify-between rounded-2xl p-5">
          <div>
            <h3 className="text-2xl font-semibold tracking-tight">{title}</h3>
            <p className="mt-1 text-[15px] text-ink-2">{line}</p>
          </div>
          <span className="grid size-10 shrink-0 place-items-center rounded-full bg-black text-[#faf7f0] transition-transform group-hover:translate-x-1" aria-hidden><ArrowRight size={18} weight="bold" /></span>
        </div>
      </motion.a>
    </div>
  );
}

export function Rooms() {
  return (
    <section id="rooms" className="mx-auto max-w-6xl scroll-mt-10 px-4 py-28 md:py-40">
      <Reveal className=""><h2 className="max-w-[14ch] text-5xl leading-[0.95] font-semibold tracking-[-0.05em] md:text-7xl">Pick your kind of home.</h2></Reveal>
      <div className="mt-14 grid gap-8 md:grid-cols-2 md:gap-10">
        {rooms.map((r) => <TiltCard key={r.title} {...r} />)}
      </div>
    </section>
  );
}
