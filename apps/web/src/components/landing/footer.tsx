import Image from "next/image";
import Link from "next/link";
import { Logo } from "@/components/ui/brand";
import { Reveal } from "@/components/ui/reveal";
import { VisitForm } from "./visit-form";

export function Visit() {
  return (
    <section id="visit" className="mx-auto grid max-w-7xl scroll-mt-20 items-stretch gap-10 px-4 py-20 md:grid-cols-2 md:gap-14 md:px-8 md:py-28">
      <Reveal className="flex flex-col">
        <h2 className="text-4xl font-semibold tracking-[-0.03em] md:text-5xl">See it in person.</h2>
        <p className="mt-4 max-w-[38ch] text-lg text-ink-2">Leave your number and we will set up a visit at a time that suits you.</p>
        <div className="relative mt-10 hidden min-h-[300px] flex-1 overflow-hidden rounded-[var(--radius-card)] md:block">
          {/* TODO(real photos): replace with the PG's entrance or common area */}
          <Image src="https://picsum.photos/seed/origin-entrance/900/700" alt="The entrance of an Origin Living home" fill sizes="45vw" className="object-cover" />
        </div>
      </Reveal>
      <Reveal delay={0.08}><VisitForm /></Reveal>
    </section>
  );
}

export function Footer() {
  return (
    <footer className="border-t border-line">
      <div className="mx-auto flex max-w-7xl flex-col gap-8 px-4 py-12 md:flex-row md:items-center md:justify-between md:px-8">
        <Logo />
        <nav className="flex flex-wrap gap-x-8 gap-y-3 text-[15px] text-ink-2">
          <Link href="/app" className="hover:text-ink">Resident login</Link>
          <Link href="/owner/login" className="hover:text-ink">Owner login</Link>
          <a href="#homes" className="hover:text-ink">Homes</a>
        </nav>
        <p className="text-sm text-ink-3">© Origin Living</p>
      </div>
    </footer>
  );
}
