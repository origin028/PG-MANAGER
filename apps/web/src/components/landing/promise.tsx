"use client";
import { useEffect, useRef } from "react";
import { animate, useInView, useMotionValue, useTransform, motion } from "motion/react";

/** The deposit promise, with the number counting up when it comes into view. */
export function DepositPromise() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { once: true, amount: 0.5 });
  const n = useMotionValue(0);
  const text = useTransform(n, (v) => `${Math.round(v)}%`);

  useEffect(() => {
    if (!inView) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const c = animate(n, 50, { duration: reduce ? 0 : 1.6, ease: [0.16, 1, 0.3, 1] });
    return () => c.stop();
  }, [inView, n]);

  return (
    <section className="px-3 py-3 md:px-6">
      <div ref={ref} className="mx-auto max-w-7xl rounded-[44px] bg-bg-2 px-4 py-28 text-center md:py-40">
        <motion.p className="text-[34vw] leading-[0.8] font-semibold tracking-[-0.07em] tabular-nums md:text-[300px]">{text}</motion.p>
        <p className="mx-auto mt-10 max-w-[22ch] text-3xl leading-tight font-semibold tracking-[-0.03em] md:text-5xl">
          of your deposit comes back. Always.
        </p>
        <p className="mx-auto mt-6 max-w-[40ch] text-lg text-ink-2">However long you stay. No conditions, no fine print.</p>
      </div>
    </section>
  );
}
