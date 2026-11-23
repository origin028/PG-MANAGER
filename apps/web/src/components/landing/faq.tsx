import { Plus } from "@phosphor-icons/react/dist/ssr";

const faqs = [
  { q: "What does the monthly rent include?", a: "Your furnished bed, meals from the weekly menu, housekeeping and secure fingerprint entry. There are no extra charges." },
  { q: "How much of my deposit do I get back?", a: "50% of your security deposit is refunded when you move out, however long you stay. Any unpaid rent is adjusted from it." },
  { q: "Which documents do I need?", a: "Aadhaar and PAN, or a passport, plus a selfie. You upload them from your phone. No photocopies." },
  { q: "Are there women-only homes?", a: "Yes. Some of our homes are only for women. Ask for one when you book a visit." },
  { q: "How do I pay rent?", a: "By UPI, through the resident app. Your receipts are saved there too." },
];

/** Native <details> accordion: accessible, works without JavaScript. */
export function Faq() {
  return (
    <section className="mx-auto max-w-4xl px-4 py-24 md:py-32">
      <h2 className="text-5xl leading-[0.95] font-semibold tracking-[-0.05em] md:text-6xl">Questions, answered.</h2>
      <div className="mt-10 grid gap-3">
        {faqs.map((f) => (
          <details key={f.q} className="group rounded-[24px] bg-white px-6 py-5 open:pb-6 [&_summary::-webkit-details-marker]:hidden">
            <summary className="flex cursor-pointer list-none items-center justify-between gap-6 text-lg font-semibold tracking-tight">
              {f.q}
              <Plus size={20} className="shrink-0 transition-transform duration-300 group-open:rotate-45" />
            </summary>
            <p className="mt-3 max-w-[60ch] text-ink-2">{f.a}</p>
          </details>
        ))}
      </div>
    </section>
  );
}
