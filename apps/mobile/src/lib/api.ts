/**
 * API client for the PG backend. Mirrors packages/api-client semantics:
 * bearer auth, single-flight refresh with rotation, `{success,data}` unwrapping, stable error codes.
 * Tokens live in the OS keychain/keystore (expo-secure-store); on web, in sessionStorage.
 */
import { Platform } from "react-native";
import * as SecureStore from "expo-secure-store";

export const API_URL = (process.env.EXPO_PUBLIC_API_URL ?? "http://localhost:8000").replace(/\/$/, "");

export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string, public details?: unknown) {
    super(message);
  }
}

type Tokens = { access: string; refresh: string; clientType: string };
const KEY = "origin.tokens";

const store = {
  async get(): Promise<Tokens | null> {
    const raw = Platform.OS === "web" ? globalThis.sessionStorage?.getItem(KEY) : await SecureStore.getItemAsync(KEY);
    return raw ? (JSON.parse(raw) as Tokens) : null;
  },
  async set(t: Tokens) {
    const raw = JSON.stringify(t);
    if (Platform.OS === "web") globalThis.sessionStorage?.setItem(KEY, raw);
    else await SecureStore.setItemAsync(KEY, raw);
  },
  async clear() {
    if (Platform.OS === "web") globalThis.sessionStorage?.removeItem(KEY);
    else await SecureStore.deleteItemAsync(KEY);
  },
};
export const tokenStore = store;

let onExpired: (() => void) | null = null;
export const setSessionExpiredHandler = (fn: () => void) => { onExpired = fn; };

let refreshing: Promise<boolean> | null = null;
async function refresh(): Promise<boolean> {
  const t = await store.get();
  if (!t) return false;
  const res = await fetch(`${API_URL}/api/v1/auth/refresh`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refresh_token: t.refresh, client_type: t.clientType }),
  }).catch(() => null);
  if (!res?.ok) {
    await store.clear();
    onExpired?.();
    return false;
  }
  const d = (await res.json()).data;
  await store.set({ access: d.access_token, refresh: d.refresh_token, clientType: t.clientType });
  return true;
}

/** Set by the app shell: called when the server says this resident's app access is off. */
export const onPortalOff: { current: null | (() => void) } = { current: null };

function messageFrom(body: any, status: number): ApiError {
  const e = body?.error;
  const detail = Array.isArray(e?.details) && e.details.length ? String(e.details[0]).split(": ").pop() : undefined;
  return new ApiError(status, e?.code ?? "HTTP_ERROR", detail || e?.message || "Something went wrong. Please try again.", e?.details);
}

export async function api<T = any>(path: string, init: RequestInit & { json?: unknown; auth?: boolean } = {}): Promise<T> {
  const { json, auth = true, ...rest } = init;
  const send = async () => {
    const headers = new Headers(rest.headers);
    if (json !== undefined) headers.set("Content-Type", "application/json");
    if (auth) {
      const t = await store.get();
      if (t) headers.set("Authorization", `Bearer ${t.access}`);
    }
    return fetch(`${API_URL}/api/v1${path}`, { ...rest, headers, body: json !== undefined ? JSON.stringify(json) : rest.body });
  };
  let res: Response;
  try {
    res = await send();
    if (res.status === 401 && auth && !path.startsWith("/auth/")) {
      refreshing ??= refresh().finally(() => (refreshing = null));
      if (await refreshing) res = await send();
    }
  } catch {
    throw new ApiError(0, "NETWORK", "Can't reach the server. Check your internet connection.");
  }
  const body = await res.json().catch(() => null);
  if (!res.ok || body?.success === false) {
    if (body?.error?.code === "PORTAL_OFF") onPortalOff.current?.();
    throw messageFrom(body, res.status);
  }
  return (body && "data" in body ? body.data : body) as T;
}
