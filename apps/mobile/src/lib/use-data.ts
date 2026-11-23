import { useCallback, useEffect, useState } from "react";
import { api } from "./api";

/** Minimal fetch hook: loading / error / refresh, keeps the last good data while refreshing. */
export function useData<T>(path: string | null) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [nonce, setNonce] = useState(0);

  useEffect(() => {
    if (!path) return;
    let alive = true;
    api<T>(path)
      .then((d) => { if (alive) { setData(d); setError(null); } })
      .catch((e) => { if (alive) setError(e instanceof Error ? e.message : "Something went wrong."); })
      .finally(() => { if (alive) { setLoading(false); setRefreshing(false); } });
    return () => { alive = false; };
  }, [path, nonce]);

  const reload = useCallback(() => { setRefreshing(true); setNonce((n) => n + 1); }, []);
  return { data, error, loading: loading && !!path, refreshing, reload };
}
