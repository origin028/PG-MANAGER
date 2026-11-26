/**
 * DEMO MODE: the whole app runs in the browser on sample data, with no backend.
 *
 * On:  build with EXPO_PUBLIC_DEMO=1 (set on Vercel while the backend is not hosted).
 * Off: remove that variable and rebuild. Nothing else changes.
 * Remove for good: delete the src/demo/ folder, then delete every line marked `DEMO-MODE`
 *   (`grep -rn "DEMO-MODE" src`). See src/demo/README.md.
 *
 * data.json holds real API responses recorded from the local demo database
 * (EXPO_PUBLIC_DEMO_RECORD=1, then window.__demoDump()). Changes made in the demo
 * (approve, resolve, record payment...) live in memory until the page is reloaded.
 */
type Role = "owner" | "resident" | "kitchen";
type Fixtures = Record<Role, Record<string, unknown>>;

export const DEMO = process.env.EXPO_PUBLIC_DEMO === "1";
const RECORD = process.env.EXPO_PUBLIC_DEMO_RECORD === "1";

const roleOfMe = (me: any): Role =>
  me?.role?.name === "RESIDENT" ? "resident" : me?.role?.name === "KITCHEN" ? "kitchen" : "owner";

/* ---------------- recording (development only) ---------------- */

export function recordResponse(path: string, method: string, data: unknown) {
  if (!RECORD || method !== "GET") return;
  // Saved in localStorage so recording survives page loads while walking through every screen.
  const ls = globalThis.localStorage;
  if (path === "/auth/me") ls.setItem("demoRec.role", roleOfMe(data));
  const role = ls.getItem("demoRec.role");
  if (role) ls.setItem(`demoRec:${role}:${path}`, JSON.stringify(data));
  (globalThis as any).__demoDump ??= () => {
    const out: Fixtures = { owner: {}, resident: {}, kitchen: {} };
    for (let i = 0; i < ls.length; i++) {
      const k = ls.key(i)!;
      const m = k.match(/^demoRec:(owner|resident|kitchen):(.*)$/);
      if (m) out[m[1] as Role][m[2]] = JSON.parse(ls.getItem(k)!);
    }
    return out;
  };
}

/* ---------------- serving ---------------- */

let db: Fixtures | null = null;
const load = (): Fixtures => (db ??= JSON.parse(JSON.stringify(require("./data.json"))) as Fixtures);

export const demoToken = (role: Role) => ({ access_token: `demo:${role}`, refresh_token: `demo:${role}`, token_type: "bearer" });
const roleFromToken = (t?: string | null): Role => (t?.split(":")[1] as Role) || "owner";

const wait = () => new Promise((r) => setTimeout(r, 120 + Math.random() * 200));
const newId = () => `demo-${Math.random().toString(16).slice(2, 10)}-${Date.now().toString(16)}`;
const isId = (s: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-|^demo-/i.test(s);

/** Visit every object anywhere in the sample data. */
function walk(node: unknown, fn: (o: any, parent: any[] | null, idx: number) => void, parent: any[] | null = null, idx = -1) {
  if (Array.isArray(node)) { for (let i = node.length - 1; i >= 0; i--) walk(node[i], fn, node, i); return; }
  if (node && typeof node === "object") {
    fn(node, parent, idx);
    for (const v of Object.values(node)) if (v && typeof v === "object") walk(v, fn);
  }
}
const eachWithId = (id: string, fn: (o: any, parent: any[] | null, idx: number) => void) =>
  walk(load(), (o, p, i) => { if (o.id === id || o.resident_id === id || o.payment_id === id) fn(o, p, i); });

/** Status an action endpoint moves a record to: POST /residents/{id}/approve -> ACTIVE, etc. */
const ACTION: Record<string, Record<string, unknown>> = {
  approve: { status: "ACTIVE", approval_status: "APPROVED" },
  reject: { status: "REJECTED", approval_status: "REJECTED" },
  resolve: { status: "RESOLVED" },
  assign: { status: "IN_PROGRESS" },
  checkout: { status: "CHECKED_OUT" },
  verify: { kyc_status: "VERIFIED" },
  read: { is_read: true, read: true },
  "admin-settle": { status: "SUCCESS" },
};
/** Lists an item leaves once acted on (e.g. an approved sign-up is no longer pending). */
const DROP_FROM_LIST: Record<string, string[]> = {
  approve: ["/residents/pending-approvals"],
  reject: ["/residents/pending-approvals"],
  "admin-settle": ["/payments/upi/pending"],
};

const ROLES: Role[] = ["owner", "resident", "kitchen"];

function find(role: Role, path: string) {
  const all = load();
  const base = path.split("?")[0];
  const order = [role, ...ROLES.filter((r) => r !== role)];
  for (const r of order) if (path in all[r]) return all[r][path];
  for (const r of order) {
    const key = Object.keys(all[r]).find((k) => k.split("?")[0] === base);
    if (key) return all[r][key];
  }
  // Detail page not recorded (e.g. a record created during the demo): find it by id.
  const id = base.split("/").find(isId);
  if (id) { let hit: unknown; eachWithId(id, (o) => { hit ??= o; }); if (hit) return hit; }
  return [];
}

function create(path: string, body: Record<string, unknown>) {
  const all = load();
  const item = { id: newId(), status: "ACTIVE", created_at: new Date().toISOString(), ...body };
  for (const r of Object.values(all))
    for (const [k, v] of Object.entries(r)) {
      if (k.split("?")[0] !== path) continue;
      if (Array.isArray(v)) v.unshift(item);
      else if (v && Array.isArray((v as any).items)) (v as any).items.unshift(item);
    }
  return item;
}

function dropFromLists(paths: string[], id: string) {
  const all = load();
  for (const r of Object.values(all))
    for (const key of Object.keys(r)) {
      if (!paths.includes(key.split("?")[0])) continue;
      const v = r[key] as any;
      const list: any[] | undefined = Array.isArray(v) ? v : v?.items;
      if (list) for (let i = list.length - 1; i >= 0; i--) if (list[i]?.id === id || list[i]?.resident_id === id) list.splice(i, 1);
    }
}

function mutate(method: string, path: string, body: any) {
  const base = path.split("?")[0];
  const parts = base.split("/").filter(Boolean);
  const id = parts.find(isId);
  const action = parts[parts.length - 1];

  if (base.startsWith("/auth/")) {
    if (base === "/auth/login") {
      const who = String(body?.identifier ?? "").toLowerCase();
      return demoToken(String(body?.client_type ?? "").startsWith("resident") ? "resident" : who.startsWith("kitchen") ? "kitchen" : "owner");
    }
    if (base.endsWith("/otp/verify")) return demoToken("resident");
    if (base.endsWith("/otp/request")) return { email_masked: "d***@example.com", sent: true };
    return { success: true };
  }

  if (base === "/payments/collect") {
    const inv = String(body?.invoice_id ?? "");
    eachWithId(inv, (o) => { o.status = "PAID"; o.balance_due = 0; o.amount_due = 0; o.outstanding_amount = 0; });
    walk(load(), (o, p, i) => { if (p && o.invoice_id === inv && o.id !== inv) p.splice(i, 1); });
    return { receipt_number: `RCPT-DEMO-${Date.now().toString().slice(-6)}`, remaining_balance: 0 };
  }
  if (base === "/payments/upi/initiate") {
    return { payment_id: newId(), upi_uri: "upi://pay?pa=demo@upi&pn=Origin%20Living&am=0", payee_vpa: "demo@upi", payee_name: "Origin Living", status: "PENDING" };
  }
  if (base === "/kitchen/scan") return { ok: true, status: "SERVED", resident_name: "Demo Resident", meal: "Lunch", message: "Meal served" };
  if (base === "/residents/onboard") return { ...create("/residents", { ...body, status: "ACTIVE" }), invite_sent: true };

  if (method === "DELETE" && id) { eachWithId(id, (_o, p, i) => { if (p) p.splice(i, 1); }); return { success: true }; }
  if ((method === "PATCH" || method === "PUT") && id) {
    let out: any = {};
    eachWithId(id, (o) => { Object.assign(o, body ?? {}); out = o; });
    return out;
  }
  if (method === "POST" && id && action !== id) {
    const changes = { ...(ACTION[action] ?? {}), ...(action === "access" ? { portal_enabled: body?.enabled } : {}) };
    let out: any = {};
    eachWithId(id, (o) => { Object.assign(o, changes); out = o; });
    if (DROP_FROM_LIST[action]) dropFromLists(DROP_FROM_LIST[action], id);
    if (action === "checkout") return { deposit_refund_amount: 5000, net_payable_by_resident: 0 };
    return { ...out, kyc_days_left: 7 };
  }
  if (method === "POST" && body && typeof body === "object") return create(base, body);
  return { success: true, id: newId() };
}

export async function demoApi(path: string, method: string, json: unknown, accessToken?: string | null) {
  await wait();
  if (method === "GET") return JSON.parse(JSON.stringify(find(roleFromToken(accessToken), path)));
  return mutate(method, path, json);
}

/** Stand-in for protected images (KYC documents, meal photos) in the demo. */
export const DEMO_IMAGE =
  "data:image/svg+xml;utf8," +
  encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="600" height="380"><rect width="600" height="380" rx="24" fill="#f3ede1"/><text x="300" y="200" font-family="Arial" font-size="28" text-anchor="middle" fill="#6b6359">Sample document (demo)</text></svg>`,
  );
