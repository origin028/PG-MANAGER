import { useEffect, useState, useSyncExternalStore } from "react";
import { API_URL, api, tokenStore } from "./api";
import { DEMO, DEMO_IMAGE } from "@/demo"; // DEMO-MODE

export type Property = { id: string; name: string; property_type?: string; city?: string };

/** The PG picked on one screen stays picked on every owner screen (Home, Residents, Rooms, Money...). */
const KEY = "origin.selectedPg";
const saved = () => { try { return globalThis.sessionStorage?.getItem(KEY) ?? null; } catch { return null; } };
let selected: string | null = saved(); // web: survives a page refresh in the same tab
const listeners = new Set<() => void>();
const selection = {
  get: () => selected,
  set: (id: string | null) => {
    selected = id;
    try { if (id) globalThis.sessionStorage?.setItem(KEY, id); } catch { /* storage may be blocked */ }
    listeners.forEach((l) => l());
  },
  subscribe: (l: () => void) => { listeners.add(l); return () => { listeners.delete(l); }; },
};

/** The owner's PGs; most screens work on one at a time and share the choice. */
export function useProperties() {
  const [props, setProps] = useState<Property[]>([]);
  const current = useSyncExternalStore(selection.subscribe, selection.get, selection.get);
  useEffect(() => {
    api<Property[] | { items: Property[] }>("/properties")
      .then((d) => {
        const list = Array.isArray(d) ? d : d.items;
        setProps(list);
        if (!selection.get() || !list.some((p) => p.id === selection.get())) selection.set(list[0]?.id ?? null);
      })
      .catch(() => setProps([]));
  }, []);
  return { props, current, setCurrent: selection.set };
}

/** Loads a protected KYC image with the bearer token and returns a data URI (works on iOS, Android, web). */
export async function loadProtectedImage(path: string): Promise<string> {
  if (DEMO) return DEMO_IMAGE; // DEMO-MODE
  const t = await tokenStore.get();
  const res = await fetch(`${API_URL}/api/v1${path}`, { headers: t ? { Authorization: `Bearer ${t.access}` } : {} });
  if (!res.ok) throw new Error("Document not available");
  const blob = await res.blob();
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result));
    r.onerror = () => reject(new Error("Could not read document"));
    r.readAsDataURL(blob);
  });
}

export const listOf = <T,>(d: T[] | { items: T[] } | null | undefined): T[] => (!d ? [] : Array.isArray(d) ? d : d.items ?? []);
