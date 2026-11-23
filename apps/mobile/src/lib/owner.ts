import { useEffect, useState } from "react";
import { API_URL, api, tokenStore } from "./api";

export type Property = { id: string; name: string };

/** The owner's properties; most screens scope to one at a time. */
export function useProperties() {
  const [props, setProps] = useState<Property[]>([]);
  const [current, setCurrent] = useState<string | null>(null);
  useEffect(() => {
    api<Property[] | { items: Property[] }>("/properties")
      .then((d) => {
        const list = Array.isArray(d) ? d : d.items;
        setProps(list);
        setCurrent((c) => c ?? list[0]?.id ?? null);
      })
      .catch(() => setProps([]));
  }, []);
  return { props, current, setCurrent };
}

/** Loads a protected KYC image with the bearer token and returns a data URI (works on iOS, Android, web). */
export async function loadProtectedImage(path: string): Promise<string> {
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
