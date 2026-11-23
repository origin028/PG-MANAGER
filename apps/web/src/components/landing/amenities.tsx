import Image from "next/image";
import { Armchair, Broom, ChatCircleDots, CookingPot, Fingerprint, IdentificationCard, Receipt, ShieldCheck } from "@phosphor-icons/react/dist/ssr";
import { Reveal } from "@/components/ui/reveal";
import { IMG } from "@/lib/photos";

const tiles = [
  { icon: Armchair, title: "Fully furnished", line: "Bed, wardrobe and study desk." },
  { icon: CookingPot, title: "Meals included", line: "Fixed weekly menu." },
  { icon: Broom, title: "Housekeeping", line: "Rooms kept clean." },
  { icon: Fingerprint, title: "Fingerprint entry", line: "Only residents get in." },
  { icon: ChatCircleDots, title: "Complaints in the app", line: "Tracked until fixed." },
  { icon: Receipt, title: "Rent and receipts", line: "Pay and download in the app." },
  { icon: IdentificationCard, title: "Online KYC", line: "No photocopies." },
  { icon: ShieldCheck, title: "Women-only homes", line: "Dedicated properties." },
];

/** Dense amenities wall: two photo tiles anchor eight icon tiles. */
export function Amenities() {
  return (
    <section id="included" className="scroll-mt-10 bg-white py-24 md:py-32">
      <div className="mx-auto max-w-6xl px-4">
        <Reveal>
          <h2 className="max-w-[14ch] text-5xl leading-[0.95] font-semibold tracking-[-0.05em] md:text-7xl">Everything is included.</h2>
        </Reveal>
        <div className="mt-12 grid grid-cols-2 gap-3 md:grid-cols-4 md:gap-4">
          <Reveal className="col-span-2 row-span-2">
            <div className="relative h-full min-h-[320px] overflow-hidden rounded-[28px]">
              <Image src={IMG.cleaning(1200, 1000)} alt="Housekeeping cleaning a room" fill sizes="(min-width: 768px) 50vw, 100vw" className="object-cover" />
              <div className="glass absolute inset-x-4 bottom-4 rounded-2xl p-5">
                <p className="text-2xl font-semibold tracking-tight">One rent. Nothing extra.</p>
                <p className="mt-1 text-ink-2">No hidden charges, ever.</p>
              </div>
            </div>
          </Reveal>
          {tiles.map((t, i) => (
            <Reveal key={t.title} delay={(i % 4) * 0.05}>
              <div className="flex h-full min-h-[150px] flex-col justify-between rounded-[24px] bg-bg p-5 transition-colors hover:bg-bg-2">
                <t.icon size={28} weight="regular" />
                <div className="mt-6">
                  <h3 className="text-[17px] font-semibold tracking-tight">{t.title}</h3>
                  <p className="mt-0.5 text-[14px] text-ink-3">{t.line}</p>
                </div>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
