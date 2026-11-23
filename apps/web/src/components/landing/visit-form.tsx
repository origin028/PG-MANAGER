"use client";
import { useEffect, useState, type FormEvent } from "react";
import { CheckCircle } from "@phosphor-icons/react";
import { Button } from "@/components/ui/button";
import { API_URL } from "@/lib/config";

type Home = { id: string; name: string };
type State = { kind: "idle" } | { kind: "sending" } | { kind: "done" } | { kind: "error"; message: string };

const field =
  "h-12 w-full rounded-xl border border-line bg-surface px-4 text-[15px] text-ink placeholder:text-ink-3 transition-colors focus:border-accent focus:outline-none";

export function VisitForm() {
  const [homes, setHomes] = useState<Home[] | null>(null);
  const [state, setState] = useState<State>({ kind: "idle" });

  useEffect(() => {
    fetch(`${API_URL}/api/v1/auth/resident/properties`)
      .then((r) => r.json())
      .then((j) => setHomes(j.data ?? []))
      .catch(() => setHomes([]));
  }, []);

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const f = new FormData(e.currentTarget);
    setState({ kind: "sending" });
    try {
      const res = await fetch(`${API_URL}/api/v1/public/enquiries`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(Object.fromEntries(f)),
      });
      const j = await res.json();
      if (!res.ok) {
        const details = j?.error?.details;
        const msg = Array.isArray(details) && details.length ? String(details[0]).split(": ").pop() : j?.error?.message;
        throw new Error(msg || "Something went wrong. Please try again.");
      }
      setState({ kind: "done" });
    } catch (err) {
      setState({ kind: "error", message: err instanceof Error ? err.message : "Something went wrong." });
    }
  }

  if (state.kind === "done") {
    return (
      <div className="flex min-h-[340px] flex-col items-start justify-center gap-4 rounded-[var(--radius-card)] border border-line bg-surface p-8">
        <CheckCircle size={36} weight="duotone" className="text-accent" />
        <p className="text-2xl font-semibold tracking-tight">Thanks. We will call you shortly.</p>
        <p className="text-ink-2">Usually within a few hours, between 9am and 8pm.</p>
      </div>
    );
  }

  return (
    <form onSubmit={submit} className="grid gap-5 rounded-[var(--radius-card)] border border-line bg-surface p-6 shadow-soft md:p-8">
      <div className="grid gap-2">
        <label htmlFor="name" className="text-sm font-medium">Your name</label>
        <input id="name" name="name" required minLength={2} autoComplete="name" className={field} />
      </div>
      <div className="grid gap-2">
        <label htmlFor="phone" className="text-sm font-medium">Mobile number</label>
        <input id="phone" name="phone" required inputMode="tel" autoComplete="tel" className={field} />
      </div>
      <div className="grid gap-2">
        <label htmlFor="property_id" className="text-sm font-medium">Home</label>
        <select id="property_id" name="property_id" required disabled={!homes?.length} className={`${field} appearance-none`} defaultValue="">
          <option value="" disabled>{homes === null ? "Loading homes..." : homes.length ? "Choose a home" : "No homes available right now"}</option>
          {homes?.map((h) => <option key={h.id} value={h.id}>{h.name}</option>)}
        </select>
      </div>
      {/* Honeypot for bots. Hidden from people and screen readers. */}
      <input name="website" tabIndex={-1} autoComplete="off" aria-hidden className="hidden" />
      {state.kind === "error" && <p role="alert" className="text-sm text-red-700 dark:text-red-400">{state.message}</p>}
      <Button type="submit" disabled={state.kind === "sending"} className="mt-1 w-full">
        {state.kind === "sending" ? "Sending..." : "Book a visit"}
      </Button>
    </form>
  );
}
