import Image from "next/image";
import { Bed, IdentificationCard, SealCheck } from "@phosphor-icons/react/dist/ssr";
import { Reveal } from "@/components/ui/reveal";
import { IMG } from "@/lib/photos";

const steps = [
  { icon: IdentificationCard, title: "Upload your ID", line: "Aadhaar and PAN, from your phone." },
  { icon: SealCheck, title: "Get approved", line: "Verified by the owner, fast." },
  { icon: Bed, title: "Move in", line: "Your bed and rent, in the app." },
];

export function Join() {
  return (
    <section id="join" className="relative scroll-mt-10 overflow-hidden">
      <Image src={IMG.living(2000, 1200)} alt="" fill sizes="100vw" className="object-cover" />
      <div className="absolute inset-0 bg-white/35" />
      <div className="relative mx-auto max-w-6xl px-4 py-28 md:py-40">
        <Reveal className=""><h2 className="max-w-[12ch] text-5xl leading-[0.95] font-semibold tracking-[-0.05em] md:text-7xl">No paperwork. Just your phone.</h2></Reveal>
        <ol className="mt-14 grid gap-4 md:grid-cols-3 md:gap-5">
          {steps.map((s, i) => (
            <Reveal key={s.title} delay={i * 0.1}>
              <li className="glass flex h-full flex-col gap-10 rounded-[28px] p-7">
                <s.icon size={30} weight="light" />
                <div>
                  <h3 className="text-2xl font-semibold tracking-tight">{s.title}</h3>
                  <p className="mt-1 text-ink-2">{s.line}</p>
                </div>
              </li>
            </Reveal>
          ))}
        </ol>
      </div>
    </section>
  );
}
