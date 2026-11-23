/** Origin Living mark: a simple geometric "doorway" (single geometric shape, not an illustration). */
export function Logo({ className = "" }: { className?: string }) {
  return (
    <span className={`inline-flex items-center gap-2.5 ${className}`}>
      <span aria-hidden className="relative grid size-7 place-items-end overflow-hidden rounded-[9px] bg-black">
        <span className="mx-auto h-4 w-3 rounded-t-full bg-[#faf7f0]" />
      </span>
      <span className="text-[17px] font-semibold tracking-tight">Origin Living</span>
    </span>
  );
}
