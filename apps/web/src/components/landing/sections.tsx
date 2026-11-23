import Image from "next/image";
import { ArrowRight, Bed, Broom, CookingPot, Fingerprint, IdentificationCard, SealCheck } from "@phosphor-icons/react/dist/ssr";
import { ButtonLink } from "@/components/ui/button";
import { Reveal } from "@/components/ui/reveal";

// TODO(real photos): every picsum URL below is placeholder photography. Replace with the PG's own photos.
const img = (seed: string, w: number, h: number) => `https://picsum.photos/seed/${seed}/${w}/${h}`;

export function Hero() {
  return (
    <section className="mx-auto grid max-w-7xl items-center gap-10 px-4 pt-10 pb-16 md:grid-cols-[1.05fr_1fr] md:gap-16 md:px-8 md:pt-16 md:pb-24">
      <Reveal>
        <h1 className="text-[44px] leading-[1.02] font-semibold tracking-[-0.035em] text-balance md:text-6xl lg:text-7xl">
          Your room is ready.
        </h1>
        <p className="mt-6 max-w-[42ch] text-lg leading-relaxed text-ink-2">
          Furnished co-living and women-only homes. One monthly rent covers meals, housekeeping and secure entry.
        </p>
        <div className="mt-9 flex flex-wrap gap-3">
          <ButtonLink href="#visit">Book a visit</ButtonLink>
          <ButtonLink href="#homes" variant="ghost">See the homes</ButtonLink>
        </div>
      </Reveal>
      <Reveal delay={0.1} className="relative">
        <div className="relative aspect-[4/5] overflow-hidden rounded-[28px] bg-surface-2 shadow-soft">
          <Image src={img("origin-sunlit-bedroom", 1000, 1250)} alt="A furnished bedroom with natural light" fill priority sizes="(min-width: 768px) 45vw, 100vw" className="object-cover" />
        </div>
        <div className="absolute -bottom-6 -left-6 hidden w-[42%] overflow-hidden rounded-[20px] border-4 border-bg shadow-soft md:block">
          <div className="relative aspect-square">
            <Image src={img("origin-dining-table", 600, 600)} alt="Shared dining area" fill sizes="20vw" className="object-cover" />
          </div>
        </div>
      </Reveal>
    </section>
  );
}

const homes = [
  { title: "Co-living", body: "Shared and private rooms for students and working professionals.", seed: "origin-coliving-room" },
  { title: "Women only", body: "Dedicated homes for women, with fingerprint entry at every door.", seed: "origin-women-home" },
];

export function Homes() {
  return (
    <section id="homes" className="mx-auto max-w-7xl scroll-mt-20 px-4 py-20 md:px-8 md:py-28">
      <Reveal>
        <h2 className="max-w-[18ch] text-4xl font-semibold tracking-[-0.03em] md:text-5xl">Two ways to live with us.</h2>
      </Reveal>
      <div className="mt-12 grid gap-6 md:grid-cols-2">
        {homes.map((h, i) => (
          <Reveal key={h.title} delay={i * 0.08}>
            <a href="#visit" className="group block">
              <div className="relative aspect-[5/4] overflow-hidden rounded-[var(--radius-card)] bg-surface-2">
                <Image src={img(h.seed, 1000, 800)} alt={h.title} fill sizes="(min-width: 768px) 50vw, 100vw" className="object-cover transition-transform duration-700 ease-[cubic-bezier(0.16,1,0.3,1)] group-hover:scale-[1.03]" />
              </div>
              <div className="mt-5 flex items-start justify-between gap-6">
                <div>
                  <h3 className="text-xl font-semibold tracking-tight">{h.title}</h3>
                  <p className="mt-1.5 max-w-[40ch] text-ink-2">{h.body}</p>
                </div>
                <ArrowRight size={22} className="mt-1 shrink-0 text-ink-3 transition-transform duration-300 group-hover:translate-x-1 group-hover:text-accent" />
              </div>
            </a>
          </Reveal>
        ))}
      </div>
    </section>
  );
}

export function Included() {
  return (
    <section id="included" className="scroll-mt-20 bg-surface-2/60 py-20 md:py-28">
      <div className="mx-auto max-w-7xl px-4 md:px-8">
        <Reveal>
          <p className="text-sm font-medium uppercase tracking-[0.14em] text-accent">In your rent</p>
          <h2 className="mt-3 text-4xl font-semibold tracking-[-0.03em] md:text-5xl">Everything, already sorted.</h2>
        </Reveal>
        <div className="mt-12 grid auto-rows-[minmax(220px,auto)] gap-4 md:grid-cols-3 md:gap-5">
          <Reveal className="md:col-span-2 md:row-span-2">
            <div className="relative h-full min-h-[340px] overflow-hidden rounded-[var(--radius-card)]">
              <Image src={img("origin-home-meal", 1400, 1000)} alt="A home-cooked meal" fill sizes="(min-width: 768px) 66vw, 100vw" className="object-cover" />
              <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-black/10 to-transparent" />
              <div className="absolute bottom-0 p-7 text-white md:p-9">
                <CookingPot size={28} weight="duotone" />
                <h3 className="mt-3 text-2xl font-semibold tracking-tight md:text-3xl">Home-style meals</h3>
                <p className="mt-1.5 max-w-[36ch] text-white/80">A fixed weekly menu, cooked fresh every day.</p>
              </div>
            </div>
          </Reveal>
          <Reveal delay={0.05}>
            <div className="flex h-full flex-col justify-between rounded-[var(--radius-card)] bg-accent p-7 text-accent-ink">
              <p className="text-sm opacity-80">Monthly rent</p>
              <p className="text-3xl leading-tight font-semibold tracking-tight">One rent.<br />Nothing extra.</p>
            </div>
          </Reveal>
          <Reveal delay={0.1}>
            <div className="flex h-full flex-col justify-between rounded-[var(--radius-card)] border border-line bg-surface p-7">
              <Fingerprint size={30} weight="duotone" className="text-accent" />
              <div>
                <h3 className="text-xl font-semibold tracking-tight">Fingerprint entry</h3>
                <p className="mt-1 text-ink-2">Only residents get in.</p>
              </div>
            </div>
          </Reveal>
          <Reveal className="md:col-span-3" delay={0.05}>
            <div className="grid h-full overflow-hidden rounded-[var(--radius-card)] border border-line bg-surface md:grid-cols-[1fr_1.4fr]">
              <div className="flex flex-col justify-center gap-3 p-7 md:p-10">
                <Broom size={28} weight="duotone" className="text-accent" />
                <h3 className="text-2xl font-semibold tracking-tight">Housekeeping that listens</h3>
                <p className="max-w-[38ch] text-ink-2">Raise an issue in the app. The team sees it and fixes it.</p>
              </div>
              <div className="relative min-h-[220px]">
                <Image src={img("origin-clean-room", 1200, 600)} alt="A clean, made-up room" fill sizes="(min-width: 768px) 58vw, 100vw" className="object-cover" />
              </div>
            </div>
          </Reveal>
        </div>
      </div>
    </section>
  );
}

const steps = [
  { icon: IdentificationCard, title: "Upload your ID", body: "Aadhaar and PAN from your phone. No photocopies." },
  { icon: SealCheck, title: "Get approved", body: "The owner verifies your details, usually the same day." },
  { icon: Bed, title: "Move in", body: "Your bed is assigned and your rent is in the app." },
];

export function Join() {
  return (
    <section id="join" className="mx-auto max-w-7xl scroll-mt-20 px-4 py-20 md:px-8 md:py-28">
      <Reveal>
        <h2 className="max-w-[16ch] text-4xl font-semibold tracking-[-0.03em] md:text-5xl">Join from your phone.</h2>
      </Reveal>
      <ol className="mt-14 grid gap-10 md:grid-cols-3 md:gap-8">
        {steps.map((s, i) => (
          <Reveal key={s.title} delay={i * 0.08}>
            <li className="relative">
              <span className="grid size-12 place-items-center rounded-2xl bg-accent-soft text-accent">
                <s.icon size={24} weight="duotone" />
              </span>
              {i < steps.length - 1 && <span aria-hidden className="absolute top-6 left-16 hidden h-px w-[calc(100%-4rem)] bg-line md:block" />}
              <h3 className="mt-6 text-xl font-semibold tracking-tight">{s.title}</h3>
              <p className="mt-1.5 max-w-[32ch] text-ink-2">{s.body}</p>
            </li>
          </Reveal>
        ))}
      </ol>
    </section>
  );
}

export function DepositPromise() {
  return (
    <section className="border-y border-line bg-surface">
      <Reveal className="mx-auto max-w-4xl px-4 py-24 text-center md:py-32">
        <p className="text-5xl leading-[1.05] font-semibold tracking-[-0.04em] text-balance md:text-7xl">
          Half your deposit back. <span className="text-accent">Always.</span>
        </p>
        <p className="mx-auto mt-6 max-w-[48ch] text-lg text-ink-2">
          Leave whenever you need to. 50% of your security deposit is refunded, however long you stay.
        </p>
      </Reveal>
    </section>
  );
}
