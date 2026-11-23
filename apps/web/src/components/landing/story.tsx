"use client";
import Image from "next/image";
import { Reveal } from "@/components/ui/reveal";
import { useEffect, useRef, useState } from "react";
import { IMG } from "@/lib/photos";

const chapters = [
  { time: "7:00", title: "Wake up in a bright, clean room.", img: IMG.roomHotel, alt: "A neat, bright bedroom" },
  { time: "8:30", title: "Breakfast is already on.", img: IMG.thali, alt: "A home-style Indian thali" },
  { time: "18:00", title: "Study with friends downstairs.", img: IMG.studying, alt: "Residents studying together" },
  { time: "21:00", title: "Your fingerprint opens the door.", img: IMG.lock, alt: "A secure door lock" },
  { time: "23:00", title: "Sleep easy.", img: IMG.roomGrey, alt: "A calm bedroom at night" },
];

/**
 * Scroll story. Desktop: the photo stays pinned while chapters scroll past, crossfading
 * to each chapter's photo. Mobile: each chapter carries its own photo inline.
 */
export function Story() {
  const [active, setActive] = useState(0);
  const refs = useRef<(HTMLDivElement | null)[]>([]);

  useEffect(() => {
    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) if (e.isIntersecting) setActive(Number((e.target as HTMLElement).dataset.i));
      },
      { rootMargin: "-45% 0px -45% 0px" },
    );
    refs.current.forEach((el) => el && io.observe(el));
    return () => io.disconnect();
  }, []);

  return (
    <section id="story" className="relative mt-28 scroll-mt-10 md:mt-40">
      <div className="mx-auto max-w-6xl px-4">
        <Reveal className=""><h2 className="max-w-[14ch] text-5xl leading-[0.95] font-semibold tracking-[-0.05em] md:text-7xl">A day at Origin.</h2></Reveal>
      </div>
      <div className="mx-auto mt-12 grid max-w-6xl gap-10 px-4 md:grid-cols-2 md:gap-16">
        <div className="sticky top-24 hidden h-[78vh] overflow-hidden rounded-[32px] bg-bg-2 md:block">
          {chapters.map((c, i) => (
            <Image
              key={c.time}
              src={c.img(1100, 1400)}
              alt={c.alt}
              fill
              sizes="50vw"
              className={`object-cover transition-[opacity,transform] duration-[900ms] ease-[cubic-bezier(0.16,1,0.3,1)] ${i === active ? "scale-100 opacity-100" : "scale-[1.06] opacity-0"}`}
            />
          ))}
          <div className="glass absolute bottom-5 left-5 rounded-full px-4 py-2 font-mono text-sm tabular-nums">{chapters[active].time}</div>
        </div>
        <div>
          {chapters.map((c, i) => (
            <div
              key={c.title}
              ref={(el) => { refs.current[i] = el; }}
              data-i={i}
              className="flex flex-col justify-center py-6 md:min-h-[78vh] md:py-0"
            >
              <div className="relative mb-6 aspect-[4/5] overflow-hidden rounded-[28px] md:hidden">
                <Image src={c.img(800, 1000)} alt={c.alt} fill sizes="100vw" className="object-cover" />
              </div>
              <p className="font-mono text-sm text-ink-3 tabular-nums">{c.time}</p>
              <p className={`mt-3 text-4xl leading-[1.02] font-semibold tracking-[-0.04em] transition-colors duration-500 md:text-6xl ${i === active ? "text-black" : "md:text-black/20"}`}>
                {c.title}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
