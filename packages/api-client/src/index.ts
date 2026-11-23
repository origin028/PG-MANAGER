/**
 * Typed client for the PG Management API, shared by the web app and the mobile app.
 *
 * - Types come from the backend's OpenAPI spec (`npm run api:types` regenerates them).
 * - Each app supplies a TokenStore: the mobile app uses the OS keychain/keystore
 *   (expo-secure-store), the web app uses in-memory + sessionStorage.
 * - On a 401 the client refreshes once (single-flight, so parallel requests share one
 *   refresh) and retries. The backend rotates refresh tokens and treats reuse as theft,
 *   so the new refresh token is always saved before anything else runs.
 */
import createClient, { type Middleware } from "openapi-fetch";
import type { paths } from "./schema";

export type { paths } from "./schema";

export interface Tokens {
  accessToken: string;
  refreshToken: string;
}

export interface TokenStore {
  get(): Promise<Tokens | null>;
  set(tokens: Tokens): Promise<void>;
  clear(): Promise<void>;
}

export type ClientType = "admin_web" | "admin_mobile" | "resident_mobile" | "resident_web";

export interface ApiOptions {
  baseUrl: string; // e.g. https://api.example.com (no trailing /api/v1)
  tokens: TokenStore;
  clientType: ClientType;
  onSessionExpired?: () => void; // e.g. navigate to the login screen
}

/** Shape of every error body the API returns. */
export interface ApiErrorBody {
  success: false;
  error: { code: string; message: string; details?: unknown };
}

export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
    public details?: unknown,
  ) {
    super(message);
  }
}

export function createApi(opts: ApiOptions) {
  const client = createClient<paths>({ baseUrl: opts.baseUrl });
  let refreshing: Promise<boolean> | null = null;

  async function refresh(): Promise<boolean> {
    const current = await opts.tokens.get();
    if (!current) return false;
    const res = await fetch(`${opts.baseUrl}/api/v1/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: current.refreshToken, client_type: opts.clientType }),
    });
    if (!res.ok) {
      await opts.tokens.clear();
      opts.onSessionExpired?.();
      return false;
    }
    const data = (await res.json()).data;
    await opts.tokens.set({ accessToken: data.access_token, refreshToken: data.refresh_token });
    return true;
  }

  const auth: Middleware = {
    async onRequest({ request }) {
      const t = await opts.tokens.get();
      if (t) request.headers.set("Authorization", `Bearer ${t.accessToken}`);
      return request;
    },
    async onResponse({ request, response }) {
      if (response.status !== 401 || request.url.includes("/auth/")) return response;
      refreshing ??= refresh().finally(() => (refreshing = null));
      if (!(await refreshing)) return response;
      const t = await opts.tokens.get();
      const retry = request.clone();
      retry.headers.set("Authorization", `Bearer ${t!.accessToken}`);
      return fetch(retry);
    },
  };
  client.use(auth);

  /** Unwraps `{success, data}` envelopes and throws ApiError with the backend's stable code. */
  async function unwrap<T>(p: Promise<{ data?: any; error?: any; response: Response }>): Promise<T> {
    const { data, error, response } = await p;
    if (error || !response.ok) {
      const e = (error as ApiErrorBody | undefined)?.error;
      throw new ApiError(response.status, e?.code ?? "HTTP_ERROR", e?.message ?? response.statusText, e?.details);
    }
    return (data?.data ?? data) as T;
  }

  return { client, unwrap, refresh, tokens: opts.tokens };
}

export type Api = ReturnType<typeof createApi>;
