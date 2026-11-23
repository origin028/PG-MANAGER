import Link from "next/link";
import { Logo } from "@/components/ui/brand";
import { ButtonLink } from "@/components/ui/button";

const links = [
  { href: "#homes", label: "Homes" },
  { href: "#included", label: "What's included" },
  { href: "#join", label: "Joining" },
];

export function Nav() {
  return (
    <header className="sticky top-0 z-30 border-b border-line/60 bg-bg/80 backdrop-blur-xl">
      <nav className="mx-auto flex h-16 max-w-7xl items-center justify-between px-4 md:px-8">
        <Link href="/" aria-label="Origin Living home"><Logo /></Link>
        <ul className="hidden items-center gap-8 text-[15px] text-ink-2 md:flex">
          {links.map((l) => (
            <li key={l.href}><a href={l.href} className="transition-colors hover:text-ink">{l.label}</a></li>
          ))}
        </ul>
        <div className="flex items-center gap-3">
          <Link href="/app" className="hidden text-[15px] text-ink-2 transition-colors hover:text-ink sm:block">Resident login</Link>
          <ButtonLink href="#visit" className="h-10 px-4">Book a visit</ButtonLink>
        </div>
      </nav>
    </header>
  );
}
