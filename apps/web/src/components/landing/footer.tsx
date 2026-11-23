import Image from "next/image";
import { Reveal } from "@/components/ui/reveal";
import Link from "next/link";
import { Logo } from "@/components/ui/brand";
import { IMG } from "@/lib/photos";
import { VisitForm } from "./visit-form";

export function Visit() {
  return (
    <section id="visit" className="mx-auto grid max-w-6xl scroll-mt-24 items-center gap-12 px-4 py-28 md:grid-cols-[1fr_1.05fr] md:py-40">
      <div>
        <Reveal className=""><h2 className="text-5xl leading-[0.95] font-semibold tracking-[-0.05em] md:text-7xl">Come see it.</h2></Reveal>
        <p className="mt-6 max-w-[30ch] text-lg text-ink-2">Leave your number. We will call to set up a visit.</p>
      </div>
      <div className="relative overflow-hidden rounded-[36px] p-3 md:p-5">
        <Image src={IMG.common(1200, 1400)} alt="" fill sizes="(min-width: 768px) 50vw, 100vw" className="object-cover" />
        <div className="relative"><VisitForm /></div>
      </div>
    </section>
  );
}

export function Footer() {
  return (
    <footer className="border-t border-line bg-white">
      <div className="mx-auto flex max-w-6xl flex-col gap-10 px-4 py-14 md:flex-row md:items-end md:justify-between">
        <div>
          <Logo />
          <p className="mt-3 max-w-[30ch] text-ink-3">Co-living and women-only homes.</p>
        </div>
        <nav className="flex flex-wrap gap-x-8 gap-y-3 text-[15px] text-ink-2">
          <Link href="/app" className="hover:text-black">Resident login</Link>
          <Link href="/owner/login" className="hover:text-black">Owner login</Link>
          <a href="#rooms" className="hover:text-black">Rooms</a>
          <a href="#visit" className="hover:text-black">Book a visit</a>
        </nav>
      </div>
    </footer>
  );
}
