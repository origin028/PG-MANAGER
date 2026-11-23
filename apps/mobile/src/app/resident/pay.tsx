import { useEffect, useEffectEvent, useRef, useState } from "react";
import { AppState, Linking, Platform, Text, View } from "react-native";
import { CheckCircle, Receipt } from "phosphor-react-native";
import { Badge, Body, Button, Card, Empty, ErrorBox, H2, LoadingCards, Row, Screen, Title, pretty, statusTone } from "@/components/ui";
import { api } from "@/lib/api";
import { fmtDate, monthName } from "@/lib/dates";
import { color, rupees, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Invoice = { id: string; invoice_number: string; billing_month: string; amount: number; outstanding_balance: number; due_date: string; status: string; can_pay: boolean };
type Payment = { id?: string; payment_number?: string; amount: number; status: string; created_at?: string; paid_at?: string };
type Upi = { payment_id: string; amount: number; payee_vpa: string; payee_name: string; upi_uri: string };

/**
 * Pay rent by UPI (unchanged backend flow): create a payment, open the resident's UPI app with the amount
 * filled in, and when they come back mark it submitted. The owner confirms receipt in their app.
 */
export default function Pay() {
  const inv = useData<Invoice[]>("/resident/invoices");
  const pays = useData<Payment[]>("/resident/payments");
  const [active, setActive] = useState<Upi | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitted, setSubmitted] = useState(false);
  const pending = useRef<Upi | null>(null);

  const onReturnFromUpi = useEffectEvent(async () => {
    const p = pending.current;
    if (!p) return;
    pending.current = null;
    await api(`/payments/upi/${p.payment_id}/return`, { method: "POST", json: {} }).catch(() => {});
    setSubmitted(true);
    inv.reload(); pays.reload();
  });

  // When the resident comes back from the UPI app, tell the backend.
  useEffect(() => {
    const sub = AppState.addEventListener("change", (state) => { if (state === "active") onReturnFromUpi(); });
    return () => sub.remove();
  }, []);

  async function pay(invoice: Invoice) {
    setBusy(invoice.id); setError(null); setSubmitted(false);
    try {
      const upi = await api<Upi>("/payments/upi/initiate", { method: "POST", json: { invoice_id: invoice.id, idempotency_key: `upi-${invoice.id}` } });
      setActive(upi);
      if (Platform.OS !== "web" && (await Linking.canOpenURL(upi.upi_uri))) {
        pending.current = upi;
        await Linking.openURL(upi.upi_uri);
      }
    } catch (e) { setError((e as Error).message); } finally { setBusy(null); }
  }

  async function markPaid() {
    if (!active) return;
    await api(`/payments/upi/${active.payment_id}/return`, { method: "POST", json: {} }).catch(() => {});
    setSubmitted(true); setActive(null);
    inv.reload(); pays.reload();
  }

  const open = (inv.data ?? []).filter((i) => i.can_pay && i.outstanding_balance > 0);

  return (
    <Screen onRefresh={() => { inv.reload(); pays.reload(); }} refreshing={inv.refreshing}>
      <Title sub="Pay by UPI. The owner confirms it, then your receipt appears here.">Rent</Title>
      {error ? <View style={{ marginBottom: space(3) }}><ErrorBox message={error} /></View> : null}

      {submitted ? (
        <Card tone="cream" style={{ flexDirection: "row", gap: space(3), alignItems: "center", marginBottom: space(3) }}>
          <CheckCircle size={28} color={color.ok} weight="fill" />
          <Body style={{ flex: 1 }}>Payment submitted. You'll see it as paid once the owner confirms.</Body>
        </Card>
      ) : null}

      {active && !submitted ? (
        <Card style={{ gap: space(3), marginBottom: space(3), borderWidth: 1, borderColor: color.ink }}>
          <Text style={[type.h2, { color: color.ink }]}>Pay {rupees(active.amount)}</Text>
          <Body>If your UPI app didn't open, pay this UPI ID from any app:</Body>
          <Row label="UPI ID" value={active.payee_vpa} />
          <Row label="Name" value={active.payee_name} />
          <Button title="I've paid" onPress={markPaid} />
        </Card>
      ) : null}

      {inv.loading ? <LoadingCards n={2} /> : inv.error ? <ErrorBox message={inv.error} onRetry={inv.reload} /> : open.length ? (
        <View style={{ gap: space(3) }}>
          {open.map((i) => (
            <Card key={i.id} style={{ gap: space(3) }}>
              <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center" }}>
                <Text style={[type.label, { color: color.ink, fontSize: 16 }]}>{monthName(i.billing_month)}</Text>
                <Badge label={pretty(i.status)} tone={statusTone(i.status)} />
              </View>
              <Text style={{ fontSize: 34, fontWeight: "700", letterSpacing: -1, color: color.ink }}>{rupees(i.outstanding_balance)}</Text>
              <Body muted>Due {fmtDate(i.due_date)}</Body>
              <Button title="Pay with UPI" onPress={() => pay(i)} loading={busy === i.id} />
            </Card>
          ))}
        </View>
      ) : (
        <Empty icon={<CheckCircle size={44} color={color.ok} weight="light" />} title="You're all paid up" body="New rent shows here at the start of each month." />
      )}

      <H2>History</H2>
      {pays.data?.length ? (
        <Card style={{ paddingVertical: space(2) }}>
          {pays.data.slice(0, 12).map((p, idx) => (
            <View key={p.id ?? idx} style={{ flexDirection: "row", alignItems: "center", gap: space(3), paddingVertical: space(3) }}>
              <Receipt size={22} color={color.ink} weight="light" />
              <View style={{ flex: 1 }}>
                <Text style={[type.label, { color: color.ink }]}>{rupees(p.amount)}</Text>
                <Body muted>{fmtDate(p.paid_at ?? p.created_at)}</Body>
              </View>
              <Badge label={pretty(p.status)} tone={statusTone(p.status)} />
            </View>
          ))}
        </Card>
      ) : <Body muted>No payments yet.</Body>}
    </Screen>
  );
}
