import { router } from "expo-router";
import { useState } from "react";
import { Pressable, Text, View } from "react-native";
import { ArrowLeft, Plus } from "phosphor-react-native";
import { Body, Button, Card, ErrorBox, Field, H2, LoadingCards, Row, Screen, Segmented } from "@/components/ui";
import { api } from "@/lib/api";
import { fmtDate } from "@/lib/dates";
import { useProperties } from "@/lib/owner";
import { color, rupees, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Report = { gross_collections: number; total_expenses: number; net_operating_profit: number; pending_rent: number; expenses_by_category: Record<string, number>; collections_by_mode: Record<string, number> };
type Expense = { id: string; title: string; category: string; amount: number; date: string; method?: string };
const CATS = ["GROCERIES", "SALARIES", "UTILITIES", "MAINTENANCE", "SUPPLIES", "OTHER"];
const nice = (s: string) => s.charAt(0) + s.slice(1).toLowerCase();

export default function Money() {
  const { props, current } = useProperties();
  const rep = useData<Report>("/reports/financial");
  const exp = useData<{ expenses: Expense[] }>("/expenses");
  const [adding, setAdding] = useState(false);
  const [f, setF] = useState({ title: "", amount: "", category: "GROCERIES", method: "UPI" });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function add() {
    if (!current) return;
    setBusy(true); setError(null);
    try {
      await api("/expenses", { method: "POST", json: { property_id: current, title: f.title.trim(), amount: Number(f.amount).toFixed(2), category: f.category, method: f.method, date: new Date().toISOString().slice(0, 10) } });
      setAdding(false); setF({ title: "", amount: "", category: "GROCERIES", method: "UPI" });
      rep.reload(); exp.reload();
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  const r = rep.data;
  const cats = Object.entries(r?.expenses_by_category ?? {}).sort((a, b) => b[1] - a[1]);
  const maxCat = Math.max(1, ...cats.map(([, v]) => v));

  return (
    <Screen onRefresh={() => { rep.reload(); exp.reload(); }} refreshing={rep.refreshing}>
      <Pressable onPress={() => router.back()} hitSlop={12} style={{ marginTop: space(3) }} accessibilityLabel="Back"><ArrowLeft size={24} color={color.ink} /></Pressable>
      <Text style={[type.h1, { color: color.ink, marginTop: space(4), marginBottom: space(5) }]}>Money</Text>
      {rep.loading ? <LoadingCards /> : rep.error ? <ErrorBox message={rep.error} onRetry={rep.reload} /> : r && (
        <>
          <Card tone="black" style={{ gap: space(1) }}>
            <Text style={[type.small, { color: "#ffffffaa" }]}>{r.net_operating_profit < 0 ? "Loss" : "Profit"}</Text>
            <Text style={{ fontSize: 44, fontWeight: "700", letterSpacing: -1.5, color: color.bg }}>{rupees(r.net_operating_profit)}</Text>
            <Text style={[type.small, { color: "#ffffffaa" }]}>{rupees(r.gross_collections)} collected · {rupees(r.total_expenses)} spent</Text>
          </Card>
          <Card style={{ marginTop: space(3), paddingVertical: space(2) }}>
            <Row label="Collected" value={rupees(r.gross_collections)} />
            <Row label="Spent" value={rupees(r.total_expenses)} />
            <Row label="Rent still pending" value={rupees(r.pending_rent)} />
          </Card>
          {cats.length ? (
            <>
              <H2>Where money went</H2>
              <Card style={{ gap: space(4) }}>
                {cats.map(([k, v]) => (
                  <View key={k} style={{ gap: space(1.5) }}>
                    <View style={{ flexDirection: "row", justifyContent: "space-between" }}>
                      <Text style={[type.label, { color: color.ink }]}>{nice(k)}</Text>
                      <Body>{rupees(v)}</Body>
                    </View>
                    <View style={{ height: 6, borderRadius: 3, width: `${(v / maxCat) * 100}%`, backgroundColor: color.ink }} />
                  </View>
                ))}
              </Card>
            </>
          ) : null}
        </>
      )}

      <H2>Expenses</H2>
      {adding ? (
        <Card style={{ marginBottom: space(3) }}>
          {props.length > 1 ? <Body muted style={{ marginBottom: space(3) }}>For {props.find((p) => p.id === current)?.name}</Body> : null}
          <Field label="What for" value={f.title} onChangeText={(t) => setF({ ...f, title: t })} placeholder="Vegetables for the week" />
          <Field label="Amount (₹)" value={f.amount} onChangeText={(t) => setF({ ...f, amount: t.replace(/\D/g, "") })} keyboardType="number-pad" />
          <Text style={[type.label, { color: color.ink, marginBottom: space(2) }]}>Category</Text>
          <Segmented value={f.category} onChange={(v) => setF({ ...f, category: v })} options={CATS.map((c) => ({ value: c, label: nice(c) }))} />
          <View style={{ height: space(3) }} />
          <Segmented value={f.method} onChange={(v) => setF({ ...f, method: v })} options={[{ value: "UPI", label: "UPI" }, { value: "CASH", label: "Cash" }, { value: "BANK_TRANSFER", label: "Bank" }]} />
          <View style={{ height: space(4) }} />
          {error ? <ErrorBox message={error} /> : null}
          <Button title="Save expense" onPress={add} loading={busy} disabled={f.title.trim().length < 2 || Number(f.amount) <= 0} />
          <Button title="Cancel" variant="ghost" onPress={() => setAdding(false)} />
        </Card>
      ) : <Button title="Add expense" variant="secondary" icon={<Plus size={18} color={color.ink} />} onPress={() => setAdding(true)} style={{ marginBottom: space(3) }} />}
      {exp.data?.expenses?.length ? (
        <Card style={{ paddingVertical: space(1) }}>
          {exp.data.expenses.slice(0, 30).map((e) => (
            <View key={e.id} style={{ flexDirection: "row", alignItems: "center", paddingVertical: space(3), gap: space(3) }}>
              <View style={{ flex: 1 }}>
                <Text style={[type.label, { color: color.ink }]}>{e.title}</Text>
                <Body muted>{nice(e.category)} · {fmtDate(e.date)}</Body>
              </View>
              <Text style={[type.label, { color: color.ink }]}>{rupees(e.amount)}</Text>
            </View>
          ))}
        </Card>
      ) : <Body muted>No expenses recorded yet.</Body>}
    </Screen>
  );
}
