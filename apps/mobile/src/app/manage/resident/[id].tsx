import { router, useLocalSearchParams } from "expo-router";
import { useCallback, useState } from "react";
import { ScrollView, Switch, Text, View } from "react-native";
import { BedPicker, type FreeBed } from "@/components/bed-picker";
import { Divider, Header, confirmAction, digits, nice } from "@/components/kit";
import { Badge, Body, Button, Card, ErrorBox, Field, H2, LoadingCards, Row, Screen, Segmented, statusTone } from "@/components/ui";
import { KycDoc } from "@/components/kyc-doc";
import { api } from "@/lib/api";
import { fmtDate } from "@/lib/dates";
import { color, rupees, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Detail = {
  id: string; full_name: string; phone: string; email?: string; property_id: string; property_name?: string;
  room_number?: string; bed_number?: string; check_in_date?: string; monthly_rent: number; status: string; kyc_status?: string;
  occupation?: string; emergency_contact_name?: string; emergency_contact_phone?: string; date_of_birth?: string; gender?: string;
  portal_enabled: boolean; portal_reason?: string | null; kyc_days_left?: number | null; kyc_submitted?: boolean; address?: string;
};
type Deposit = { deposit_held: string; refund_if_moving_out_today: string; retained_by_policy: string; entries: { type: string; amount: string; note?: string; at: string }[] };
type Panel = null | "edit" | "move" | "deposit" | "checkout" | "reject";
const DOCS = [["aadhaar_front", "Aadhaar front"], ["aadhaar_back", "Aadhaar back"], ["pan_card", "PAN"], ["passport", "Passport"], ["resident_selfie", "Selfie"]] as const;

export default function ResidentDetail() {
  const { id, invite } = useLocalSearchParams<{ id: string; invite?: string }>();
  const r = useData<Detail>(`/residents/${id}`);
  const dep = useData<Deposit>(`/residents/${id}/deposit`);
  const [panel, setPanel] = useState<Panel>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(
    invite === "sent" ? "Resident added. We emailed them a code to set their password; they'll fill in their details and KYC themselves." :
    invite === "failed" ? "Resident added, but the login email could not be sent. Use \"Send login invite\" below." :
    invite === "none" ? "Resident added. Add their email (Edit) and send a login invite so they can sign in." : null,
  );
  const [form, setForm] = useState({ full_name: "", phone: "", email: "", monthly_rent: "", occupation: "", emergency_contact_name: "", emergency_contact_phone: "" });
  const [bed, setBed] = useState<FreeBed | null>(null);
  const [amount, setAmount] = useState("");
  const [damage, setDamage] = useState("");
  const [reason, setReason] = useState("");
  const [missingDocs, setMissingDocs] = useState(0);
  const onMissing = useCallback(() => setMissingDocs((m) => m + 1), []);
  const refresh = () => { r.reload(); dep.reload(); };

  const open = (p: Panel) => {
    setError(null); setNotice(null);
    if (p === "edit" && r.data) {
      const d = r.data;
      setForm({ full_name: d.full_name, phone: d.phone, email: d.email ?? "", monthly_rent: String(d.monthly_rent ?? ""), occupation: d.occupation ?? "", emergency_contact_name: d.emergency_contact_name ?? "", emergency_contact_phone: d.emergency_contact_phone ?? "" });
    }
    setPanel(panel === p ? null : p);
  };

  async function run(fn: () => Promise<unknown>, done: string) {
    setBusy(true); setError(null);
    try { await fn(); setPanel(null); setNotice(done); refresh(); } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  const save = () => run(() => api(`/residents/${id}`, { method: "PATCH", json: { ...form, phone: digits(form.phone).slice(-10), monthly_rent: Number(form.monthly_rent) } }), "Details saved.");
  const move = () => bed && run(() => api(`/residents/${id}`, { method: "PATCH", json: { room_id: bed.room_id, bed_id: bed.id, ...(bed.monthly_rent ? { monthly_rent: bed.monthly_rent } : {}) } }), `Moved to Room ${bed.room_number} · ${bed.bed_number}.`);
  const addDeposit = () => run(() => api(`/residents/${id}/deposit`, { method: "POST", json: { amount: Number(amount).toFixed(2) } }), "Deposit recorded.");
  const verify = () => run(() => api(`/residents/${id}/kyc/verify`, { method: "POST", json: {} }), "KYC verified.");
  const reject = () => run(() => api(`/residents/${id}/kyc/reject`, { method: "POST", json: { notes: reason.trim() } }), "KYC rejected.");
  const invite_ = () => run(() => api(`/residents/${id}/send-invite`, { method: "POST" }), `Login invite sent to ${r.data?.email}. The code works for 48 hours.`);
  const setAccess = (on: boolean) => run(async () => {
    const res = await api<{ kyc_days_left?: number | null }>(`/residents/${id}/access`, { method: "POST", json: { enabled: on } });
    return res;
  }, on ? "App access turned on." : "App access turned off. They can still sign in to see why and contact you.");

  async function checkout(force = false) {
    setBusy(true); setError(null);
    try {
      const res = await api<{ deposit_refund_amount: number; net_payable_by_resident: number }>(`/residents/${id}/checkout`, { method: "POST", json: { damage_charges: Number(damage || 0), force_checkout: force } });
      setPanel(null);
      setNotice(`Checked out. Refund ${rupees(res.deposit_refund_amount)}${res.net_payable_by_resident ? `, still owes ${rupees(res.net_payable_by_resident)}` : ""}. Bed is free.`);
      refresh();
    } catch (e) {
      const msg = (e as Error).message;
      if (!force && /exceeding/i.test(msg)) confirmAction("Dues are more than the refund", `${msg}\n\nCheck out anyway and record the balance as owed?`, "Check out anyway", () => checkout(true));
      else setError(msg);
    } finally { setBusy(false); }
  }

  const d = r.data;
  const active = d?.status === "ACTIVE" || d?.status === "NOTICE_PERIOD";

  return (
    <Screen onRefresh={refresh} refreshing={r.refreshing}>
      <Header title={d?.full_name ?? "Resident"} sub={d ? `${d.property_name ?? ""}` : undefined} action={d ? <Badge label={nice(d.status)} tone={statusTone(d.status)} /> : undefined} />
      {notice ? <Card tone="cream" style={{ marginBottom: space(3) }}><Body>{notice}</Body></Card> : null}
      {error ? <View style={{ marginBottom: space(3) }}><ErrorBox message={error} /></View> : null}
      {r.loading ? <LoadingCards /> : r.error ? <ErrorBox message={r.error} onRetry={r.reload} /> : d && (
        <>
          <Card style={{ paddingVertical: space(2) }}>
            <Row label="Room / bed" value={d.room_number ? `${d.room_number} / ${d.bed_number}` : "Not assigned"} />
            <Divider />
            <Row label="Monthly rent" value={d.room_number || d.monthly_rent ? rupees(d.monthly_rent) : "Set when you assign a bed"} />
            <Divider />
            <Row label="Living here since" value={fmtDate(d.check_in_date)} />
          </Card>
          {active ? (
            <View style={{ flexDirection: "row", gap: space(2), marginTop: space(3) }}>
              <Button title="Edit" variant="secondary" onPress={() => open("edit")} style={{ flex: 1, paddingHorizontal: 0 }} />
              <Button title={d.room_number ? "Move bed" : "Assign bed"} variant="secondary" onPress={() => open("move")} style={{ flex: 1, paddingHorizontal: 0 }} />
              <Button title="Check out" variant="danger" onPress={() => open("checkout")} style={{ flex: 1, paddingHorizontal: 0 }} />
            </View>
          ) : null}

          {panel === "edit" ? (
            <Card style={{ marginTop: space(3) }}>
              <Field label="Full name" value={form.full_name} onChangeText={(t) => setForm({ ...form, full_name: t })} />
              <Field label="Mobile" value={form.phone} onChangeText={(t) => setForm({ ...form, phone: t })} keyboardType="phone-pad" />
              <Field label="Email" value={form.email} onChangeText={(t) => setForm({ ...form, email: t })} autoCapitalize="none" keyboardType="email-address" />
              <Field label="Monthly rent (₹)" value={form.monthly_rent} onChangeText={(t) => setForm({ ...form, monthly_rent: digits(t) })} keyboardType="number-pad" hint="Applies from the next rent bill." />
              <Field label="Occupation" value={form.occupation} onChangeText={(t) => setForm({ ...form, occupation: t })} />
              <Field label="Emergency contact name" value={form.emergency_contact_name} onChangeText={(t) => setForm({ ...form, emergency_contact_name: t })} />
              <Field label="Emergency contact mobile" value={form.emergency_contact_phone} onChangeText={(t) => setForm({ ...form, emergency_contact_phone: t })} keyboardType="phone-pad" />
              <Button title="Save" onPress={save} loading={busy} disabled={form.full_name.trim().length < 2 || digits(form.phone).length < 10} />
            </Card>
          ) : null}

          {panel === "move" ? (
            <Card style={{ marginTop: space(3), gap: space(3) }}>
              <Text style={[type.label, { color: color.ink }]}>{d.room_number ? "Move to a free bed" : "Pick a bed (rent bills start from the next monthly run)"}</Text>
              <BedPicker propertyId={d.property_id} value={bed?.id ?? ""} onChange={setBed} />
              {bed?.monthly_rent ? <Body muted>Rent will change to {rupees(bed.monthly_rent)} (that bed's rent).</Body> : null}
              <Button title="Move resident" onPress={move} loading={busy} disabled={!bed} />
            </Card>
          ) : null}

          {panel === "checkout" ? (
            <Card style={{ marginTop: space(3), gap: space(2) }}>
              <Text style={[type.label, { color: color.ink }]}>Check out {d.full_name.split(" ")[0]}</Text>
              <Body muted>They get {dep.data ? rupees(Number(dep.data.refund_if_moving_out_today)) : "50% of the deposit"} back, minus unpaid rent and any damage. Their bed becomes free and their login stops working.</Body>
              <View style={{ height: space(2) }} />
              <Field label="Damage charges (₹, optional)" value={damage} onChangeText={(t) => setDamage(digits(t))} keyboardType="number-pad" />
              <Button title="Confirm check-out" variant="danger" onPress={() => confirmAction("Check out?", `${d.full_name} will be moved out today.`, "Check out", () => checkout(false))} loading={busy} />
            </Card>
          ) : null}

          <H2>Security deposit</H2>
          <Card style={{ gap: space(2) }}>
            <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "baseline" }}>
              <Text style={{ fontSize: 30, fontWeight: "700", letterSpacing: -1, color: color.ink }}>{rupees(Number(dep.data?.deposit_held ?? 0))}</Text>
              <Body muted>held</Body>
            </View>
            <Body>Refund if they leave today: <Text style={{ fontWeight: "700" }}>{rupees(Number(dep.data?.refund_if_moving_out_today ?? 0))}</Text></Body>
            {dep.data?.entries?.length ? (
              <View style={{ marginTop: space(2) }}>
                {dep.data.entries.map((e, i) => <Row key={i} label={`${nice(e.type.replace("DEPOSIT_", ""))} · ${fmtDate(e.at)}`} value={rupees(Number(e.amount))} />)}
              </View>
            ) : null}
            {active ? (panel === "deposit" ? (
              <>
                <Field label="Amount received (₹)" value={amount} onChangeText={(t) => setAmount(digits(t))} keyboardType="number-pad" />
                <Button title="Record deposit" onPress={addDeposit} loading={busy} disabled={Number(amount) <= 0} />
              </>
            ) : <Button title="Record deposit received" variant="secondary" onPress={() => open("deposit")} />) : null}
          </Card>

          <H2>ID documents</H2>
          <View style={{ flexDirection: "row", alignItems: "center", gap: space(2), marginBottom: space(3), flexWrap: "wrap" }}>
            <Body>KYC status</Body>
            <Badge label={d.kyc_status === "SUBMITTED" ? "Ready to check" : nice(d.kyc_status ?? "PENDING")} tone={statusTone(d.kyc_status)} />
            {d.kyc_days_left != null ? <Badge label={d.kyc_days_left > 0 ? `${d.kyc_days_left} day${d.kyc_days_left === 1 ? "" : "s"} left` : "Deadline passed"} tone={d.kyc_days_left <= 2 ? (d.kyc_days_left > 0 ? "warn" : "bad") : "neutral"} /> : null}
          </View>
          {d.kyc_status === "PENDING" && !d.kyc_submitted ? <Body muted style={{ marginBottom: space(3), fontSize: 14 }}>Waiting for {d.full_name.split(" ")[0]} to add their details and ID photos in the app.</Body> : null}
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: space(3) }}>
            {DOCS.map(([doc, label]) => <KycDoc key={doc} residentId={d.id} doc={doc} label={label} onMissing={onMissing} />)}
          </ScrollView>
          {missingDocs === DOCS.length ? <Body muted>No documents uploaded for this resident.</Body> : null}
          {d.kyc_status !== "VERIFIED" ? (
            <View style={{ gap: space(2), marginTop: space(3) }}>
              <Segmented value={panel === "reject" ? "reject" : "verify"} onChange={(v) => setPanel(v === "reject" ? "reject" : null)} options={[{ value: "verify", label: "Verify" }, { value: "reject", label: "Reject" }]} />
              {panel === "reject" ? (
                <>
                  <Field label="Reason" value={reason} onChangeText={setReason} placeholder="PAN photo is blurry" />
                  <Button title="Reject documents" variant="danger" onPress={reject} loading={busy} disabled={reason.trim().length < 3} />
                </>
              ) : <Button title="Mark KYC verified" onPress={verify} loading={busy} />}
            </View>
          ) : null}

          <H2>Contact</H2>
          <Card style={{ paddingVertical: space(2) }}>
            <Row label="Mobile" value={d.phone} />
            {d.email ? <Row label="Email" value={d.email} /> : null}
            {d.occupation ? <Row label="Occupation" value={d.occupation} /> : null}
            {d.emergency_contact_name ? <Row label="Emergency" value={`${d.emergency_contact_name} ${d.emergency_contact_phone ?? ""}`} /> : null}
            {d.date_of_birth ? <Row label="Born" value={fmtDate(d.date_of_birth)} /> : null}
          </Card>
          {active ? (
            <Card style={{ marginTop: space(3), gap: space(3) }}>
              <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: space(3) }}>
                <View style={{ flex: 1, gap: 2 }}>
                  <Text style={[type.label, { color: color.ink, fontSize: 16 }]}>App access</Text>
                  <Body muted style={{ fontSize: 14 }}>
                    {d.portal_enabled
                      ? d.kyc_days_left != null ? `On. KYC must be verified within ${d.kyc_days_left} day${d.kyc_days_left === 1 ? "" : "s"}, or access pauses automatically.` : "On."
                      : d.portal_reason === "KYC_OVERDUE" ? "Paused automatically: KYC wasn't verified in time." : "Paused by you."}
                  </Body>
                </View>
                <Switch value={d.portal_enabled} onValueChange={setAccess} disabled={busy} trackColor={{ true: color.ok, false: color.line }} thumbColor={color.card} accessibilityLabel="App access" />
              </View>
              {!d.portal_enabled && d.portal_reason === "KYC_OVERDUE" ? <Body muted style={{ fontSize: 13 }}>Turning it on gives them a fresh deadline. Verifying their KYC also turns it back on.</Body> : null}
              <Divider />
              <Body muted style={{ fontSize: 14 }}>
                {d.email ? `Sign-in: ${d.email} or ${d.phone}. Send a code if they haven't set a password or forgot it.` : "Add their email (Edit) so they can set a password and sign in."}
              </Body>
              {d.email ? <Button title="Send login invite" variant="secondary" onPress={invite_} loading={busy} /> : null}
            </Card>
          ) : null}
          <Button title="Back to residents" variant="ghost" onPress={() => router.back()} style={{ marginTop: space(6) }} />
        </>
      )}
    </Screen>
  );
}
