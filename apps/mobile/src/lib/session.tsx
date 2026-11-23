import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { api, setSessionExpiredHandler, tokenStore } from "./api";

export type Role = "resident" | "owner" | "kitchen";
export type Me = { id: string; full_name: string; email?: string; phone?: string; role: { name: string; display_name?: string } };

type Session = {
  ready: boolean;
  me: Me | null;
  mode: Role | null;
  signInWithTokens: (access: string, refresh: string, clientType: string) => Promise<void>;
  signOut: () => Promise<void>;
};

const Ctx = createContext<Session | null>(null);
export const modeOf = (me: Me | null): Role | null =>
  !me ? null : me.role?.name === "RESIDENT" ? "resident" : me.role?.name === "KITCHEN" ? "kitchen" : "owner";

export function SessionProvider({ children }: { children: ReactNode }) {
  const [ready, setReady] = useState(false);
  const [me, setMe] = useState<Me | null>(null);

  const loadMe = useCallback(async () => {
    try {
      setMe(await api<Me>("/auth/me"));
    } catch {
      setMe(null);
    }
  }, []);

  useEffect(() => {
    setSessionExpiredHandler(() => setMe(null));
    (async () => {
      if (await tokenStore.get()) await loadMe();
      setReady(true);
    })();
  }, [loadMe]);

  const value = useMemo<Session>(
    () => ({
      ready,
      me,
      mode: modeOf(me),
      async signInWithTokens(access, refresh, clientType) {
        await tokenStore.set({ access, refresh, clientType });
        await loadMe();
      },
      async signOut() {
        const t = await tokenStore.get();
        if (t) await api("/auth/logout", { method: "POST", json: { refresh_token: t.refresh } }).catch(() => {});
        await tokenStore.clear();
        setMe(null);
      },
    }),
    [ready, me, loadMe],
  );
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useSession() {
  const s = useContext(Ctx);
  if (!s) throw new Error("useSession must be used inside SessionProvider");
  return s;
}
