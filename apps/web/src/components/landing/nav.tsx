import Link from "next/link";
import { Logo } from "@/components/ui/brand";

const links = [
  { href: "#story", label: "Life here" },
  { href: "#food", label: "Food" },
  { href: "#rooms", label: "Rooms" },
  { href: "#included", label: "Included" },
  { href: "#join", label: "Joining" },
];

/** Floating frosted-glass pill, Apple-style. */
export function Nav() {
  return (
    <header className="fixed inset-x-0 top-3 z-40 px-3">
      <nav className="glass mx-auto flex h-14 max-w-5xl items-center justify-between rounded-full pr-2 pl-5">
        <Link href="/" aria-label="Origin Living home"><Logo /></Link>
        <ul className="hidden items-center gap-7 text-[14px] text-ink-2 md:flex">
          {links.map((l) => (
            <li key={l.href}><a href={l.href} className="transition-colors hover:text-black">{l.label}</a></li>
          ))}
        </ul>
        <a href="#visit" className="inline-flex h-10 items-center rounded-full bg-black px-5 text-[14px] font-medium text-[#faf7f0] transition-transform active:scale-[0.97]">
          Book a visit
        </a>
      </nav>
    </header>
  );
}
