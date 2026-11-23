import Link from "next/link";
import type { ComponentProps } from "react";

const base =
  "inline-flex h-12 items-center justify-center gap-2 whitespace-nowrap rounded-full px-6 text-[15px] font-medium transition-[transform,background-color,color] duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] active:scale-[0.97] disabled:opacity-50";
const variants = {
  primary: "bg-black text-[#faf7f0] hover:bg-[#1c1b19]",
  ghost: "text-black underline-offset-4 hover:underline",
  outline: "border border-black/15 bg-white/60 text-black hover:bg-white",
};
type Variant = keyof typeof variants;

export function ButtonLink({ variant = "primary", className = "", ...p }: ComponentProps<typeof Link> & { variant?: Variant }) {
  return <Link {...p} className={`${base} ${variants[variant]} ${className}`} />;
}

export function Button({ variant = "primary", className = "", ...p }: ComponentProps<"button"> & { variant?: Variant }) {
  return <button {...p} className={`${base} ${variants[variant]} ${className}`} />;
}
