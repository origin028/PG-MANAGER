import { router } from "expo-router";
import { useState } from "react";
import { Switch, Text, View } from "react-native";
import { EnvelopeSimple, IdentificationCard, LockKey } from "phosphor-react-native";
import { BedPicker, type FreeBed } from "@/components/bed-picker";
import { Header, digits } from "@/components/kit";
import { Body, Button, Card, ErrorBox, Field, Screen, Segmented } from "@/components/ui";
import { api } from "@/lib/api";
import { useProperties } from "@/lib/owner";
import { color, rupees, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

/**
 * Owner adds a new resident with just name, mobile and email.
 * The resident gets an email, sets a password and fills in everything else (details + KYC) themselves.
 * Bed and rent can be set now or later.
 */
export default function AddResident() {
  const { props, current, setCurrent } = useProperties();
  const company = useData<{ kyc_deadline_days?: number }>("/settings/company");
  const days = company.data?.kyc_deadline_days ?? 7;
  const [f, setF] = useState({ full_name: "", phone: "", email: "", monthly_rent: "", security_deposit: "" });
  const [withBed, setWithBed] = useState(false);
  const [bed, setBed] = useState<FreeBed | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const set = (k: keyof typeof f) => (v: string) => setF({ ...f, [k]: v });

  async function submit() {
    if (!current) return;
    setBusy(true); setError(null);
    try {
      const res = await api<{ id?: string; resident_id?: string; invite_sent?: boolean | null }>("/residents/onboard", {
        method: "POST",
        json: {
          full_name: f.full_name.trim(), phone: digits(f.phone).slice(-10), email: f.email.trim().toLowerCase(), property_id: current,
          check_in_date: new Date().toISOString().slice(0, 10),
          ...(withBed && bed ? { room_id: bed.room_id, bed_id: bed.id, monthly_rent: Number(f.monthly_rent), security_deposit: Number(f.security_deposit || 0) } : {}),
        },
      });
      const id = res.id ?? res.resident_id;
      if (id && withBed && Number(f.security_deposit) > 0) await api(`/residents/${id}/deposit`, { method: "POST", json: { amount: Number(f.security_deposit).toFixed(2), note: "Deposit received at joining" } }).catch(() => {});
      if (id) router.replace({ pathname: "/manage/resident/[id]", params: { id, invite: res.invite_sent ? "sent" : "failed" } }); else router.back();
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  const emailOk = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(f.email.trim());
  const ok = f.full_name.trim().length > 1 && digits(f.phone).length >= 10 && emailOk && (!withBed || (!!bed && Number(f.monthly_rent) > 0));

  return (
    <Screen>
      <Header title="Add resident" sub="Just three details. They fill in the rest themselves." />
      {props.length > 1 ? <View style={{ marginBottom: space(4) }}><Segmented value={current ?? ""} onChange={(v) => { setCurrent(v); setBed(null); }} options={props.map((p) => ({ value: p.id, label: p.name }))} /></View> : null}
      <Card>
        <Field label="Full name" value={f.full_name} onChangeText={set("full_name")} autoComplete="name" />
        <Field label="Mobile" value={f.phone} onChangeText={set("phone")} keyboardType="phone-pad" />
        <Field label="Email" value={f.email} onChangeText={set("email")} autoCapitalize="none" keyboardType="email-address" error={f.email.trim() && !emailOk ? "Check the email address." : null} />
      </Card>

      <Card tone="cream" style={{ marginTop: space(3), gap: space(3) }}>
        <Text style={[type.label, { color: color.ink }]}>What happens next</Text>
        {[
          [<EnvelopeSimple key="e" size={20} color={color.ink} />, "They get an email with a code to set their own password."],
          [<IdentificationCard key="i" size={20} color={color.ink} />, `They add their details, address and ID photos in the app. They have ${days} days.`],
          [<LockKey key="l" size={20} color={color.ink} />, `If you haven't verified their KYC within ${days} days, their app access pauses automatically. You can switch it back on any time.`],
        ].map(([icon, text], i) => (
          <View key={i} style={{ flexDirection: "row", gap: space(3), alignItems: "flex-start" }}>
            {icon}
            <Body style={{ flex: 1, fontSize: 14 }}>{text as string}</Body>
          </View>
        ))}
      </Card>

      <Card style={{ marginTop: space(3), gap: space(3) }}>
        <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: space(3) }}>
          <View style={{ flex: 1 }}>
            <Text style={[type.label, { color: color.ink }]}>Assign a bed now</Text>
            <Body muted style={{ fontSize: 13 }}>Optional. You can do it later from their page. Rent bills start once they have a bed.</Body>
          </View>
          <Switch value={withBed} onValueChange={setWithBed} trackColor={{ true: color.ink, false: color.line }} thumbColor={color.card} accessibilityLabel="Assign a bed now" />
        </View>
        {withBed ? (
          <>
            <BedPicker propertyId={current} value={bed?.id ?? ""} onChange={(b) => { setBed(b); if (b.monthly_rent) setF((p) => ({ ...p, monthly_rent: String(b.monthly_rent) })); }} />
            <Field label="Monthly rent (₹)" value={f.monthly_rent} onChangeText={(t) => set("monthly_rent")(digits(t))} keyboardType="number-pad" />
            <Field label="Deposit received (₹)" value={f.security_deposit} onChangeText={(t) => set("security_deposit")(digits(t))} keyboardType="number-pad" hint={Number(f.security_deposit) > 0 ? `${rupees(Number(f.security_deposit) / 2)} comes back when they leave.` : undefined} />
          </>
        ) : null}
      </Card>

      {error ? <View style={{ marginTop: space(3) }}><ErrorBox message={error} /></View> : null}
      <Button title="Add and send invite" onPress={submit} loading={busy} disabled={!ok} style={{ marginTop: space(5) }} />
    </Screen>
  );
}
