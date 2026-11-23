import { useState } from "react";
import { Text, View } from "react-native";
import { CheckCircle } from "phosphor-react-native";
import { Badge, Body, Button, Card, Empty, ErrorBox, Field, LoadingCards, Screen, Segmented, pretty, statusTone } from "@/components/ui";
import { api } from "@/lib/api";
import { fmtDate } from "@/lib/dates";
import { listOf, useProperties } from "@/lib/owner";
import { Header } from "@/components/kit";
import { color, rupees, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Payment = { id: string; payment_number?: string; amount: number; status: string; payment_mode?: string; resident_name?: string; invoice_number?: string; transaction_ref?: string; created_at?: string; is_settled?: boolean };
const DONE = ["SUCCESS", "SETTLED", "PAID", "COMPLETED", "FAILED", "CANCELLED", "REFUNDED"];

/** Direct UPI has no automatic bank confirmation: the owner checks their bank app and confirms with the UTR. */
export default function Payments() {
  const { props, current, setCurrent } = useProperties();
  const { data, error, loading, refreshing, reload } = useData<{ items: Payment[] }>(current ? `/payments?property_id=${current}&page_size=100` : null);
  const [open, setOpen] = useState<string | null>(null);
  const [utr, setUtr] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const all = listOf<Payment>(data as never);
  const toConfirm = all.filter((p) => !p.is_settled && !DONE.includes((p.status ?? "").toUpperCase()));
  const recent = all.filter((p) => !toConfirm.includes(p)).slice(0, 15);

  async function confirm(p: Payment) {
    setBusy(true); setErr(null);
    try {
      await api(`/payments/upi/${p.id}/admin-settle`, { method: "POST", json: { bank_reference: utr.trim(), notes: "Confirmed in owner app" } });
      setOpen(null); setUtr(""); reload();
    } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  }

  return (
    <Screen onRefresh={reload} refreshing={refreshing}>
      <Header title="Confirm UPI payments" sub="Check your bank app, then confirm each payment with its UTR number." />
      {props.length > 1 ? <View style={{ marginBottom: space(4) }}><Segmented value={current ?? ""} onChange={setCurrent} options={props.map((p) => ({ value: p.id, label: p.name }))} /></View> : null}
      {loading && current ? <LoadingCards n={2} /> : error ? <ErrorBox message={error} onRetry={reload} /> : (
        <>
          {toConfirm.length ? (
            <View style={{ gap: space(3) }}>
              {toConfirm.map((p) => (
                <Card key={p.id} style={{ gap: space(3) }}>
                  <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center" }}>
                    <Text style={{ fontSize: 26, fontWeight: "700", letterSpacing: -0.8, color: color.ink }}>{rupees(p.amount)}</Text>
                    <Badge label={pretty(p.status)} tone="warn" />
                  </View>
                  <Body>{p.resident_name ?? "Resident"}{p.invoice_number ? ` · ${p.invoice_number}` : ""}</Body>
                  <Body muted>{fmtDate(p.created_at)}{p.transaction_ref ? ` · Ref ${p.transaction_ref}` : ""}</Body>
                  {open === p.id ? (
                    <>
                      <Field label="UTR / bank reference" value={utr} onChangeText={setUtr} autoCapitalize="characters" placeholder="From your bank app" />
                      {err ? <ErrorBox message={err} /> : null}
                      <Button title="Confirm received" onPress={() => confirm(p)} loading={busy} disabled={utr.trim().length < 4} />
                    </>
                  ) : <Button title="Confirm payment" variant="secondary" onPress={() => { setOpen(p.id); setUtr(""); setErr(null); }} />}
                </Card>
              ))}
            </View>
          ) : <Empty icon={<CheckCircle size={44} color={color.ok} weight="light" />} title="Nothing to confirm" body="Payments residents make in the app show up here." />}
          {recent.length ? (
            <>
              <Text style={[type.h2, { color: color.ink, marginTop: space(8), marginBottom: space(3) }]}>Recent</Text>
              <Card style={{ paddingVertical: space(1) }}>
                {recent.map((p) => (
                  <View key={p.id} style={{ flexDirection: "row", alignItems: "center", paddingVertical: space(3), gap: space(3) }}>
                    <View style={{ flex: 1 }}>
                      <Text style={[type.label, { color: color.ink }]}>{rupees(p.amount)}</Text>
                      <Body muted>{p.resident_name ?? ""} {fmtDate(p.created_at)}</Body>
                    </View>
                    <Badge label={pretty(p.status)} tone={statusTone(p.status)} />
                  </View>
                ))}
              </Card>
            </>
          ) : null}
        </>
      )}
    </Screen>
  );
}
