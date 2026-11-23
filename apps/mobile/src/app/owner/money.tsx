import { router, useFocusEffect } from "expo-router";
import { useCallback, useState } from "react";
import { Pressable, Text, View } from "react-native";
import { ChartLineUp, Plus, Trash, Wallet } from "phosphor-react-native";
import { Divider, Header, ListRow, SmallButton, confirmAction, digits, nice } from "@/components/kit";
import { Badge, Body, Button, Card, Empty, ErrorBox, Field, H2, LoadingCards, Row, Screen, Segmented, statusTone } from "@/components/ui";
import { api } from "@/lib/api";
import { fmtDate, monthName } from "@/lib/dates";
import { listOf, useProperties } from "@/lib/owner";
import { color, rupees, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Report = { gross_collections: number; total_expenses: number; net_operating_profit: number; pending_rent: number; expenses_by_category: Record<string, number> };
type Expense = { id: string; title: string; category: string; amount: number; date: string };
type Invoice = { id: string; invoice_number: string; billing_month: string; invoice_type: string; amount: number; paid_amount: number; due_date: string; status: string; resident_id: string; resident_name?: string; room_number?: string };
type Res = { id: string; full_name: string; room_number?: string };
const CATS = ["GROCERIES", "SALARIES", "UTILITIES", "MAINTENANCE", "SUPPLIES", "OTHER"];
const OPEN = ["PENDING", "PARTIALLY_PAID", "OVERDUE"];
const today = () => new Date().toISOString().slice(0, 10);

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
        <Text style={{ fontSize: 44, fontWeight: "700", letterSpacing: -1.5, color: color.bg }}>{rupees(r.net_operating_profit)}</Text>
        <Text style={[type.small, { color: "#ffffffaa" }]}>{rupees(r.gross_collections)} collected · {rupees(r.total_expenses)} spent</Text>
      </Card>
      <Card style={{ marginTop: space(3), paddingVertical: space(2) }}>
        <Row label="Collected" value={rupees(r.gross_collections)} /><Divider />
        <Row label="Spent" value={rupees(r.total_expenses)} /><Divider />
        <Row label="Rent still pending" value={rupees(r.pending_rent)} />
      </Card>
      {cats.length ? (
        <>
          <H2>Where money went</H2>
          <Card style={{ gap: space(4) }}>
            {cats.map(([k, v]) => (
              <View key={k} style={{ gap: space(1.5) }}>
                <View style={{ flexDirection: "row", justifyContent: "space-between" }}><Text style={[type.label, { color: color.ink }]}>{nice(k)}</Text><Body>{rupees(v)}</Body></View>
                <View style={{ height: 6, borderRadius: 3, width: `${(v / max) * 100}%`, backgroundColor: color.ink }} />
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
  const [notice, setNotice] = useState<string | null>(null);

  const dues = (inv.data ?? []).filter((i) => OPEN.includes(i.status)).sort((a, b) => a.due_date.localeCompare(b.due_date));
  const total = dues.reduce((s, i) => s + (i.amount - i.paid_amount), 0);

  async function collect(i: Invoice) {
    setBusy(true); setError(null);
    try {
      const r = await api<{ receipt_number: string; remaining_balance: number }>("/payments/collect", {
        method: "POST", json: { resident_id: i.resident_id, invoice_id: i.id, property_id: propertyId, collect_amount: Number(pay.amount).toFixed(2), payment_mode: pay.mode, transaction_reference: pay.ref.trim() || null },
      });
      setOpen(null); setNotice(`Recorded. Receipt ${r.receipt_number}${r.remaining_balance > 0 ? `, ${rupees(r.remaining_balance)} still due` : ""}.`); inv.reload();
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  async function createBill() {
    if (!bill) return;
    setBusy(true); setError(null);
    try {
      await api("/invoices", { method: "POST", json: { property_id: propertyId, resident_id: bill.resident, invoice_type: bill.type, amount: Number(bill.amount), due_date: bill.due, billing_month: bill.due.slice(0, 7), notes: bill.notes.trim() || null } });
      setBill(null); setNotice("Bill created. The resident sees it in their app."); inv.reload();
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  return (
    <>
      <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginBottom: space(3) }}>
        <Body>{dues.length} unpaid · {rupees(total)}</Body>
        <SmallButton label="New bill" tone="light" icon={<Plus size={16} color={color.ink} />} onPress={() => setBill({ resident: "", type: "MAINTENANCE", amount: "", due: today(), notes: "" })} />
      </View>
      {notice ? <Card tone="cream" style={{ marginBottom: space(3) }}><Body>{notice}</Body></Card> : null}
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
          {dues.map((i) => {
            const bal = i.amount - i.paid_amount;
            return (
              <Card key={i.id} style={{ gap: space(2) }}>
                <View style={{ flexDirection: "row", justifyContent: "space-between", gap: space(3) }}>
                  <View style={{ flex: 1 }}>
                    <Text style={[type.label, { color: color.ink, fontSize: 16 }]}>{i.resident_name ?? "Resident"}{i.room_number ? ` · ${i.room_number}` : ""}</Text>
                    <Body muted>{nice(i.invoice_type)} · {monthName(i.billing_month)} · due {fmtDate(i.due_date)}</Body>
                  </View>
                  <Badge label={nice(i.status)} tone={statusTone(i.status)} />
                </View>
                <Text style={{ fontSize: 24, fontWeight: "700", color: color.ink }}>{rupees(bal)}</Text>
                {open === i.id ? (
                  <>
                    <Field label="Amount received (₹)" value={pay.amount} onChangeText={(t) => setPay({ ...pay, amount: digits(t) })} keyboardType="number-pad" />
                    <Segmented value={pay.mode} onChange={(v) => setPay({ ...pay, mode: v })} options={[{ value: "CASH", label: "Cash" }, { value: "UPI", label: "UPI" }, { value: "BANK_TRANSFER", label: "Bank" }]} />
                    <View style={{ height: space(3) }} />
                    {pay.mode !== "CASH" ? <Field label="Reference / UTR" value={pay.ref} onChangeText={(t) => setPay({ ...pay, ref: t })} autoCapitalize="characters" /> : null}
                    <Button title="Save payment" onPress={() => collect(i)} loading={busy} disabled={Number(pay.amount) <= 0 || Number(pay.amount) > bal || (pay.mode !== "CASH" && pay.ref.trim().length < 4)} />
                  </>
                ) : <Button title="Record payment" variant="secondary" onPress={() => { setOpen(i.id); setPay({ amount: String(bal), mode: "CASH", ref: "" }); setError(null); }} />}
              </Card>
            );
          })}
        </View>
      ) : <Empty icon={<Wallet size={44} color={color.ok} weight="light" />} title="No dues" body="Everyone is paid up." />}
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
    try { await api("/expenses", { method: "POST", json: { property_id: propertyId, title: f.title.trim(), amount: Number(f.amount).toFixed(2), category: f.category, method: f.method, date: today() } }); setF(null); exp.reload(); }
    catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  const remove = (e: Expense) => confirmAction("Delete expense?", `${e.title} · ${rupees(e.amount)}`, "Delete", async () => { try { await api(`/expenses/${e.id}`, { method: "DELETE" }); exp.reload(); } catch (x) { setError((x as Error).message); } });
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
  const [tab, setTab] = useState<"overview" | "dues" | "expenses">("overview");
  const [key, setKey] = useState(0);
  useFocusEffect(useCallback(() => { setKey((k) => k + 1); }, []));
  return (
    <Screen onRefresh={() => setKey((k) => k + 1)}>
      <Header back={false} title="Money" />
      <View style={{ flexDirection: "row", gap: space(3), marginBottom: space(4) }}>
        <Card onPress={() => router.push("/manage/confirm-payments")} style={{ flex: 1, gap: space(2) }}><Wallet size={22} color={color.ink} /><Text style={[type.label, { color: color.ink }]}>Confirm UPI</Text></Card>
        <Card onPress={() => router.push("/manage/reports")} style={{ flex: 1, gap: space(2) }}><ChartLineUp size={22} color={color.ink} /><Text style={[type.label, { color: color.ink }]}>Reports</Text></Card>
      </View>
      {props.length > 1 ? <View style={{ marginBottom: space(3) }}><Segmented value={current ?? ""} onChange={setCurrent} options={props.map((p) => ({ value: p.id, label: p.name }))} /></View> : null}
      <Segmented value={tab} onChange={setTab} options={[{ value: "overview", label: "Overview" }, { value: "dues", label: "Dues" }, { value: "expenses", label: "Expenses" }]} />
      <View style={{ height: space(4) }} key={`spacer-${key}`} />
      {tab === "overview" ? <Overview key={key} /> : !current ? <LoadingCards /> : tab === "dues" ? <Dues key={key} propertyId={current} /> : <Expenses key={key} propertyId={current} />}
    </Screen>
  );
}
