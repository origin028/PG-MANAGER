import Image from "next/image";
import { Reveal } from "@/components/ui/reveal";
import { IMG } from "@/lib/photos";

/** Photo bento: five real moments, five cells. */
const cells = [
  { src: IMG.roomWhite(1400, 1400), alt: "A bright furnished bedroom", label: "Your room", cls: "md:col-span-2 md:row-span-2" },
  { src: IMG.thali(800, 600), alt: "An Indian thali", label: "Home food", cls: "" },
  { src: IMG.friends(800, 600), alt: "Residents laughing together", label: "Good people", cls: "" },
  { src: IMG.common(800, 600), alt: "A bright common lounge", label: "Common lounge", cls: "" },
  { src: IMG.building(800, 600), alt: "The residential building", label: "Safe building", cls: "" },
];

export function Mosaic() {
  return (
    <section className="mx-auto max-w-6xl px-4 py-24 md:py-32">
      <Reveal>
        <h2 className="max-w-[16ch] text-5xl leading-[0.95] font-semibold tracking-[-0.05em] md:text-7xl">Real homes. Real people.</h2>
      </Reveal>
      <div className="mt-12 grid auto-rows-[220px] grid-cols-2 gap-3 md:auto-rows-[260px] md:grid-cols-4 md:gap-4">
        {cells.map((c, i) => (
          <Reveal key={c.label} delay={i * 0.06} className={`${i === 0 ? "col-span-2 row-span-2" : ""} ${c.cls}`}>
            <figure className="group relative h-full overflow-hidden rounded-[28px] bg-bg-2">
              <Image src={c.src} alt={c.alt} fill sizes={i === 0 ? "(min-width: 768px) 50vw, 100vw" : "(min-width: 768px) 25vw, 50vw"} className="object-cover transition-transform duration-[1200ms] ease-[cubic-bezier(0.16,1,0.3,1)] group-hover:scale-[1.05]" />
              <figcaption className="glass absolute bottom-3 left-3 rounded-full px-3.5 py-1.5 text-[14px] font-medium">{c.label}</figcaption>
            </figure>
          </Reveal>
        ))}
      </div>
    </section>
  );
}
