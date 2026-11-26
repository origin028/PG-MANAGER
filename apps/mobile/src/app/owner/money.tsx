import { router, useFocusEffect, useLocalSearchParams } from "expo-router";
import { useCallback, useState } from "react";
import { Linking, Platform, Pressable, Text, View } from "react-native";
import { ChartLineUp, FilePdf, Phone, Plus, Trash, Wallet, WhatsappLogo } from "phosphor-react-native";
import { Header, ListRow, SmallButton, confirmAction, digits, nice } from "@/components/kit";
import { CountUp, IconTile, ProgressBar, Reveal, toast } from "@/components/motion";
import { Badge, Body, Button, Card, Empty, ErrorBox, Field, H2, LoadingCards, Screen, Segmented, statusTone } from "@/components/ui";
import { api } from "@/lib/api";
import { downloadProtected } from "@/lib/download";
import { fmtDate, monthName } from "@/lib/dates";
import { listOf, useProperties } from "@/lib/owner";
import { color, rupees, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Report = { gross_collections: number; total_expenses: number; net_operating_profit: number; pending_rent: number; expenses_by_category: Record<string, number> };
type Expense = { id: string; title: string; category: string; amount: number; date: string };
type Invoice = { id: string; invoice_number: string; billing_month: string; invoice_type: string; amount: number; paid_amount: number; due_date: string; status: string; resident_id: string; resident_name?: string; room_number?: string };
type Res = { id: string; full_name: string; room_number?: string; phone?: string };
const CATS = ["GROCERIES", "SALARIES", "UTILITIES", "MAINTENANCE", "SUPPLIES", "OTHER"];
const OPEN = ["PENDING", "PARTIALLY_PAID", "OVERDUE"];
const today = () => new Date().toISOString().slice(0, 10);

/** Opens WhatsApp with a polite, pre-filled rent reminder to the resident. */
function remind(phone: string, name: string, amount: number, due: string, month: string) {
  const n = phone.replace(/\D/g, "").slice(-10);
  const text = `Hi ${name.split(" ")[0]}, a friendly reminder that ${rupees(amount)} for ${month} was due on ${fmtDate(due)}. You can pay by UPI from the Origin Living app. Thank you!`;
  const url = `https://wa.me/91${n}?text=${encodeURIComponent(text)}`;
  if (Platform.OS === "web") globalThis.open?.(url, "_blank");
  else Linking.openURL(url).catch(() => toast("Couldn't open WhatsApp", "error"));
}
const call = (phone: string) => Linking.openURL(`tel:${phone.replace(/\D/g, "").slice(-10)}`).catch(() => {});

function Overview() {
  const rep = useData<Report>("/reports/financial");
  const r = rep.data;
  const cats = Object.entries(r?.expenses_by_category ?? {}).sort((a, b) => b[1] - a[1]);
  const max = Math.max(1, ...cats.map(([, v]) => v));
  if (rep.loading) return <LoadingCards />;
  if (rep.error || !r) return <ErrorBox message={rep.error ?? "No data"} onRetry={rep.reload} />;
  return (
    <>
      <Card tone="black" style={{ gap: space(1) }}>
        <Text style={[type.small, { color: "#ffffffaa" }]}>{r.net_operating_profit < 0 ? "Loss" : "Profit"}</Text>
        <CountUp value={r.net_operating_profit} format={rupees} style={{ fontSize: 44, fontWeight: "700", letterSpacing: -1.5, color: r.net_operating_profit < 0 ? "#ff8a80" : color.bg }} />
        <Text style={[type.small, { color: "#ffffffaa" }]}>{rupees(r.gross_collections)} collected · {rupees(r.total_expenses)} spent</Text>
      </Card>
      <View style={{ flexDirection: "row", gap: space(3), marginTop: space(3) }}>
        {([["Collected", r.gross_collections, "green", Wallet], ["Spent", r.total_expenses, "rose", Trash], ["Pending", r.pending_rent, "amber", ChartLineUp]] as const).map(([label, v, tone, I], i) => (
          <Reveal key={label} index={i + 1} style={{ flex: 1 }}>
            <Card style={{ padding: space(3.5), gap: space(2) }}>
              <IconTile icon={I} tone={tone} size={34} />
              <CountUp value={v} format={rupees} style={[type.label, { color: color.ink, fontSize: 16 }]} />
              <Body muted style={{ fontSize: 12 }}>{label}</Body>
            </Card>
          </Reveal>
        ))}
      </View>
      {cats.length ? (
        <>
          <H2>Where money went</H2>
          <Card style={{ gap: space(4) }}>
            {cats.map(([k, v]) => (
              <View key={k} style={{ gap: space(1.5) }}>
                <View style={{ flexDirection: "row", justifyContent: "space-between" }}><Text style={[type.label, { color: color.ink }]}>{nice(k)}</Text><Body>{rupees(v)}</Body></View>
                <ProgressBar pct={(v / max) * 100} />
              </View>
            ))}
          </Card>
        </>
      ) : null}
    </>
  );
}

function Dues({ propertyId }: { propertyId: string }) {
  const inv = useData<Invoice[]>(`/invoices?property_id=${propertyId}`);
  const res = useData<{ items: Res[] }>("/residents?status=ACTIVE&page_size=100");
  const [open, setOpen] = useState<string | null>(null);
  const [pay, setPay] = useState({ amount: "", mode: "CASH", ref: "" });
  const [bill, setBill] = useState<null | { resident: string; type: string; amount: string; due: string; notes: string }>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const phoneOf = new Map(listOf<Res>(res.data as never).map((r) => [r.id, r.phone ?? ""]));

  const dues = (inv.data ?? []).filter((i) => OPEN.includes(i.status)).sort((a, b) => a.due_date.localeCompare(b.due_date));
  const total = dues.reduce((s, i) => s + (i.amount - i.paid_amount), 0);

  async function collect(i: Invoice) {
    setBusy(true); setError(null);
    try {
      const r = await api<{ receipt_number: string; remaining_balance: number }>("/payments/collect", {
        method: "POST", json: { resident_id: i.resident_id, invoice_id: i.id, property_id: propertyId, collect_amount: Number(pay.amount).toFixed(2), payment_mode: pay.mode, transaction_reference: pay.ref.trim() || null },
      });
      setOpen(null); toast(`Payment saved · receipt ${r.receipt_number}${r.remaining_balance > 0 ? ` · ${rupees(r.remaining_balance)} still due` : ""}`); inv.reload();
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  async function createBill() {
    if (!bill) return;
    setBusy(true); setError(null);
    try {
      await api("/invoices", { method: "POST", json: { property_id: propertyId, resident_id: bill.resident, invoice_type: bill.type, amount: Number(bill.amount), due_date: bill.due, billing_month: bill.due.slice(0, 7), notes: bill.notes.trim() || null } });
      setBill(null); toast("Bill created. The resident sees it in their app."); inv.reload();
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  return (
    <>
      <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginBottom: space(3) }}>
        <Body>{dues.length} unpaid · {rupees(total)}</Body>
        <SmallButton label="New bill" tone="light" icon={<Plus size={16} color={color.ink} />} onPress={() => setBill({ resident: "", type: "MAINTENANCE", amount: "", due: today(), notes: "" })} />
      </View>
      {error ? <View style={{ marginBottom: space(3) }}><ErrorBox message={error} /></View> : null}
      {bill ? (
        <Card style={{ marginBottom: space(3) }}>
          <Text style={[type.label, { color: color.ink, marginBottom: space(2) }]}>Who</Text>
          <Segmented value={bill.resident} onChange={(v) => setBill({ ...bill, resident: v })} options={listOf<Res>(res.data as never).map((r) => ({ value: r.id, label: r.full_name.split(" ")[0] + (r.room_number ? ` · ${r.room_number}` : "") }))} />
          <View style={{ height: space(3) }} />
          <Segmented value={bill.type} onChange={(v) => setBill({ ...bill, type: v })} options={["RENT", "MAINTENANCE", "ELECTRICITY", "PENALTY"].map((t) => ({ value: t, label: nice(t) }))} />
          <View style={{ height: space(3) }} />
          <Field label="Amount (₹)" value={bill.amount} onChangeText={(t) => setBill({ ...bill, amount: digits(t) })} keyboardType="number-pad" />
          <Field label="Due date" value={bill.due} onChangeText={(t) => setBill({ ...bill, due: t })} placeholder="YYYY-MM-DD" />
          <Field label="Note (optional)" value={bill.notes} onChangeText={(t) => setBill({ ...bill, notes: t })} placeholder="Broken chair replaced" />
          <Button title="Create bill" onPress={createBill} loading={busy} disabled={!bill.resident || Number(bill.amount) <= 0 || !/^\d{4}-\d{2}-\d{2}$/.test(bill.due)} />
          <Button title="Cancel" variant="ghost" onPress={() => setBill(null)} />
        </Card>
      ) : null}
      {inv.loading ? <LoadingCards /> : inv.error ? <ErrorBox message={inv.error} onRetry={inv.reload} /> : dues.length ? (
        <View style={{ gap: space(3) }}>
          {dues.map((i, idx) => {
            const bal = i.amount - i.paid_amount;
            const phone = phoneOf.get(i.resident_id);
            const late = Math.round((Date.parse(today()) - Date.parse(i.due_date.slice(0, 10))) / 86_400_000);
            return (
              <Reveal key={i.id} index={idx}>
              <Card style={{ gap: space(2) }}>
                <View style={{ flexDirection: "row", justifyContent: "space-between", gap: space(3) }}>
                  <View style={{ flex: 1 }}>
                    <Text style={[type.label, { color: color.ink, fontSize: 16 }]}>{i.resident_name ?? "Resident"}{i.room_number ? ` · ${i.room_number}` : ""}</Text>
                    <Body muted>{nice(i.invoice_type)} · {monthName(i.billing_month)} · due {fmtDate(i.due_date)}</Body>
                  </View>
                  <Badge label={nice(i.status)} tone={statusTone(i.status)} />
                </View>
                <View style={{ flexDirection: "row", alignItems: "baseline", gap: space(2) }}>
                  <Text style={{ fontSize: 24, fontWeight: "700", color: color.ink }}>{rupees(bal)}</Text>
                  {late > 0 ? <Text style={[type.small, { color: color.bad, fontWeight: "700" }]}>{late} day{late === 1 ? "" : "s"} late</Text> : null}
                </View>
                {open === i.id ? (
                  <>
                    <Field label="Amount received (₹)" value={pay.amount} onChangeText={(t) => setPay({ ...pay, amount: digits(t) })} keyboardType="number-pad" />
                    <Segmented value={pay.mode} onChange={(v) => setPay({ ...pay, mode: v })} options={[{ value: "CASH", label: "Cash" }, { value: "UPI", label: "UPI" }, { value: "BANK_TRANSFER", label: "Bank" }]} />
                    <View style={{ height: space(3) }} />
                    {pay.mode !== "CASH" ? <Field label="Reference / UTR" value={pay.ref} onChangeText={(t) => setPay({ ...pay, ref: t })} autoCapitalize="characters" /> : null}
                    <Button title="Save payment" onPress={() => collect(i)} loading={busy} disabled={Number(pay.amount) <= 0 || Number(pay.amount) > bal || (pay.mode !== "CASH" && pay.ref.trim().length < 4)} />
                  </>
                ) : (
                  <View style={{ flexDirection: "row", gap: space(2) }}>
                    <Button title="Record payment" variant="secondary" onPress={() => { setOpen(i.id); setPay({ amount: String(bal), mode: "CASH", ref: "" }); setError(null); }} style={{ flex: 1 }} />
                    {phone ? (
                      <>
                        <Pressable onPress={() => remind(phone, i.resident_name ?? "there", bal, i.due_date, monthName(i.billing_month))} accessibilityLabel="Send WhatsApp reminder"
                          style={({ pressed }) => ({ width: 54, height: 54, borderRadius: 27, backgroundColor: "#e3f7ea", alignItems: "center", justifyContent: "center", transform: [{ scale: pressed ? 0.92 : 1 }] })}>
                          <WhatsappLogo size={24} color="#1a8d4a" weight="fill" />
                        </Pressable>
                        <Pressable onPress={() => call(phone)} accessibilityLabel="Call resident"
                          style={({ pressed }) => ({ width: 54, height: 54, borderRadius: 27, backgroundColor: color.cream, alignItems: "center", justifyContent: "center", transform: [{ scale: pressed ? 0.92 : 1 }] })}>
                          <Phone size={22} color={color.ink} weight="fill" />
                        </Pressable>
                      </>
                    ) : null}
                  </View>
                )}
              </Card>
              </Reveal>
            );
          })}
        </View>
      ) : <Empty icon={<Wallet size={44} color={color.ok} weight="light" />} title="No dues" body="Everyone is paid up." />}
    </>
  );
}

type Hist = { id: string; resident_name?: string; invoice_number?: string; billing_month?: string; amount: number; payment_mode: string; status: string; paid_at?: string; created_at: string; receipt_id?: string | null; receipt_number?: string | null };

function History() {
  const h = useData<Hist[]>("/payments/history");
  const [q, setQ] = useState("ALL");
  const [error, setError] = useState<string | null>(null);
  const rows = (h.data ?? []).filter((p) => q === "ALL" || p.payment_mode === q);
  const receipt = (p: Hist) => downloadProtected(`/receipts/${p.receipt_id}/pdf`, `${p.receipt_number ?? "receipt"}.pdf`, "application/pdf").catch((e) => setError((e as Error).message));
  return (
    <>
      <Segmented value={q} onChange={setQ} options={[{ value: "ALL", label: "All" }, { value: "UPI", label: "UPI" }, { value: "CASH", label: "Cash" }, { value: "BANK_TRANSFER", label: "Bank" }]} />
      <View style={{ height: space(3) }} />
      {error ? <ErrorBox message={error} /> : null}
      {h.loading ? <LoadingCards /> : rows.length ? (
        <Card style={{ paddingVertical: space(1) }}>
          {rows.map((p) => (
            <ListRow key={p.id} title={`${rupees(p.amount)} · ${p.resident_name ?? "Resident"}`}
              sub={`${nice(p.payment_mode)} · ${fmtDate(p.paid_at ?? p.created_at)}${p.billing_month ? ` · ${monthName(p.billing_month)}` : ""}`}
              right={
                <View style={{ flexDirection: "row", alignItems: "center", gap: space(3) }}>
                  <Badge label={nice(p.status)} tone={statusTone(p.status)} />
                  {p.receipt_id ? <Pressable onPress={() => receipt(p)} hitSlop={10} accessibilityLabel="Download receipt"><FilePdf size={22} color={color.ink} /></Pressable> : null}
                </View>} />
          ))}
        </Card>
      ) : <Body muted>No payments yet.</Body>}
    </>
  );
}

function Expenses({ propertyId }: { propertyId: string }) {
  const exp = useData<{ expenses: Expense[] }>("/expenses");
  const [f, setF] = useState<null | { title: string; amount: string; category: string; method: string }>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function add() {
    if (!f) return;
    setBusy(true); setError(null);
    try { await api("/expenses", { method: "POST", json: { property_id: propertyId, title: f.title.trim(), amount: Number(f.amount).toFixed(2), category: f.category, method: f.method, date: today() } }); setF(null); toast("Expense saved"); exp.reload(); }
    catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  const remove = (e: Expense) => confirmAction("Delete expense?", `${e.title} · ${rupees(e.amount)}`, "Delete", async () => { try { await api(`/expenses/${e.id}`, { method: "DELETE" }); toast("Expense deleted"); exp.reload(); } catch (x) { setError((x as Error).message); } });
  return (
    <>
      {f ? (
        <Card style={{ marginBottom: space(3) }}>
          <Field label="What for" value={f.title} onChangeText={(t) => setF({ ...f, title: t })} placeholder="Vegetables for the week" />
          <Field label="Amount (₹)" value={f.amount} onChangeText={(t) => setF({ ...f, amount: digits(t) })} keyboardType="number-pad" />
          <Segmented value={f.category} onChange={(v) => setF({ ...f, category: v })} options={CATS.map((c) => ({ value: c, label: nice(c) }))} />
          <View style={{ height: space(3) }} />
          <Segmented value={f.method} onChange={(v) => setF({ ...f, method: v })} options={[{ value: "UPI", label: "UPI" }, { value: "CASH", label: "Cash" }, { value: "BANK_TRANSFER", label: "Bank" }]} />
          <View style={{ height: space(4) }} />
          {error ? <ErrorBox message={error} /> : null}
          <Button title="Save expense" onPress={add} loading={busy} disabled={f.title.trim().length < 2 || Number(f.amount) <= 0} />
          <Button title="Cancel" variant="ghost" onPress={() => setF(null)} />
        </Card>
      ) : <Button title="Add expense" variant="secondary" icon={<Plus size={18} color={color.ink} />} onPress={() => setF({ title: "", amount: "", category: "GROCERIES", method: "UPI" })} style={{ marginBottom: space(3) }} />}
      {exp.loading ? <LoadingCards n={2} /> : exp.data?.expenses?.length ? (
        <Card style={{ paddingVertical: space(1) }}>
          {exp.data.expenses.map((e) => (
            <ListRow key={e.id} title={e.title} sub={`${nice(e.category)} · ${fmtDate(e.date)}`} right={
              <View style={{ flexDirection: "row", alignItems: "center", gap: space(3) }}>
                <Text style={[type.label, { color: color.ink }]}>{rupees(e.amount)}</Text>
                <Pressable onPress={() => remove(e)} hitSlop={10} accessibilityLabel="Delete expense"><Trash size={18} color={color.ink3} /></Pressable>
              </View>} />
          ))}
        </Card>
      ) : <Body muted>No expenses recorded yet.</Body>}
    </>
  );
}

export default function MoneyTab() {
  const { props, current, setCurrent } = useProperties();
  type Tab = "overview" | "dues" | "history" | "expenses";
  const params = useLocalSearchParams<{ tab?: Tab }>();
  const valid = (t?: string): t is Tab => !!t && ["overview", "dues", "history", "expenses"].includes(t);
  const [tab, setTab] = useState<Tab>(valid(params.tab) ? params.tab : "overview");
  // Deep links like /owner/money?tab=dues (from the home screen) open the right section.
  const [seenParam, setSeenParam] = useState(params.tab);
  if (params.tab !== seenParam) { setSeenParam(params.tab); if (valid(params.tab)) setTab(params.tab); }
  const [key, setKey] = useState(0);
  useFocusEffect(useCallback(() => { setKey((k) => k + 1); }, []));
  return (
    <Screen onRefresh={() => setKey((k) => k + 1)}>
      <Header back={false} title="Money" />
      <View style={{ flexDirection: "row", gap: space(3), marginBottom: space(4) }}>
        <Card onPress={() => router.push("/manage/confirm-payments")} style={{ flex: 1, flexDirection: "row", alignItems: "center", gap: space(3), padding: space(4) }}><IconTile icon={Wallet} tone="green" size={38} /><Text style={[type.label, { color: color.ink }]}>Confirm UPI</Text></Card>
        <Card onPress={() => router.push("/manage/finance")} style={{ flex: 1, flexDirection: "row", alignItems: "center", gap: space(3), padding: space(4) }}><IconTile icon={ChartLineUp} tone="blue" size={38} /><Text style={[type.label, { color: color.ink }]}>Finance</Text></Card>
      </View>
      {props.length > 1 ? <View style={{ marginBottom: space(3) }}><Segmented value={current ?? ""} onChange={setCurrent} options={props.map((p) => ({ value: p.id, label: p.name }))} /></View> : null}
      <Segmented value={tab} onChange={setTab} options={[{ value: "overview", label: "Overview" }, { value: "dues", label: "Dues" }, { value: "history", label: "History" }, { value: "expenses", label: "Expenses" }]} />
      <View style={{ height: space(4) }} key={`spacer-${key}`} />
      {tab === "overview" ? <Overview key={key} /> : tab === "history" ? <History key={key} /> : !current ? <LoadingCards /> : tab === "dues" ? <Dues key={key} propertyId={current} /> : <Expenses key={key} propertyId={current} />}
    </Screen>
  );
}
