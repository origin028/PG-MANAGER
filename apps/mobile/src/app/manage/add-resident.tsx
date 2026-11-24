import { router } from "expo-router";
import { useState } from "react";
import { Text, View } from "react-native";
import { BedPicker, type FreeBed } from "@/components/bed-picker";
import { Header, digits } from "@/components/kit";
import { Body, Button, Card, ErrorBox, Field, Screen, Segmented } from "@/components/ui";
import { api } from "@/lib/api";
import { useProperties } from "@/lib/owner";
import { color, rupees, space, type } from "@/lib/theme";

/** Owner adds a walk-in resident. With an email, they get a code to set their own password and then sign in with email or mobile. */
export default function AddResident() {
  const { props, current, setCurrent } = useProperties();
  const [f, setF] = useState({ full_name: "", phone: "", email: "", occupation: "", gender: "Male", emergency_contact_name: "", emergency_contact_phone: "", city: "", monthly_rent: "", security_deposit: "" });
  const [bed, setBed] = useState<FreeBed | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const set = (k: keyof typeof f) => (v: string) => setF({ ...f, [k]: v });

  async function submit() {
    if (!current || !bed) return;
    setBusy(true); setError(null);
    try {
      const res = await api<{ id?: string; resident_id?: string; invite_sent?: boolean | null }>("/residents/onboard", {
        method: "POST",
        json: {
          ...f, phone: digits(f.phone).slice(-10), emergency_contact_phone: digits(f.emergency_contact_phone).slice(-10) || null,
          email: f.email.trim() || null, property_id: current, room_id: bed.room_id, bed_id: bed.id,
          monthly_rent: Number(f.monthly_rent), security_deposit: Number(f.security_deposit || 0), check_in_date: new Date().toISOString().slice(0, 10),
        },
      });
      const id = res.id ?? res.resident_id;
      if (id && Number(f.security_deposit) > 0) await api(`/residents/${id}/deposit`, { method: "POST", json: { amount: Number(f.security_deposit).toFixed(2), note: "Deposit received at joining" } }).catch(() => {});
      const invite = res.invite_sent ? "sent" : f.email.trim() ? "failed" : "none";
      if (id) router.replace({ pathname: "/manage/resident/[id]", params: { id, invite } }); else router.back();
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  const ok = f.full_name.trim().length > 1 && digits(f.phone).length >= 10 && !!bed && Number(f.monthly_rent) > 0;
  return (
    <Screen>
      <Header title="Add resident" sub="For someone joining in person. They can upload KYC later from the app." />
      {props.length > 1 ? <View style={{ marginBottom: space(4) }}><Segmented value={current ?? ""} onChange={(v) => { setCurrent(v); setBed(null); }} options={props.map((p) => ({ value: p.id, label: p.name }))} /></View> : null}
      <Card>
        <Field label="Full name" value={f.full_name} onChangeText={set("full_name")} />
        <Field label="Mobile" value={f.phone} onChangeText={set("phone")} keyboardType="phone-pad" />
        <Field label="Email" value={f.email} onChangeText={set("email")} autoCapitalize="none" keyboardType="email-address"
          hint={f.email.trim() ? "We'll email them a code to set their own password. They then sign in with this email or their mobile." : "Needed for their login: we email them a code to set their own password. You can add it later too."} />
        <Text style={[type.label, { color: color.ink, marginBottom: space(2) }]}>Gender</Text>
        <Segmented value={f.gender} onChange={set("gender")} options={[{ value: "Male", label: "Male" }, { value: "Female", label: "Female" }, { value: "Other", label: "Other" }]} />
        <View style={{ height: space(4) }} />
        <Field label="Occupation" value={f.occupation} onChangeText={set("occupation")} />
        <Field label="Home city" value={f.city} onChangeText={set("city")} />
        <Field label="Emergency contact name" value={f.emergency_contact_name} onChangeText={set("emergency_contact_name")} />
        <Field label="Emergency contact mobile" value={f.emergency_contact_phone} onChangeText={set("emergency_contact_phone")} keyboardType="phone-pad" />
      </Card>
      <Text style={[type.h2, { color: color.ink, marginTop: space(6), marginBottom: space(3) }]}>Bed and rent</Text>
      <Card style={{ gap: space(3) }}>
        <BedPicker propertyId={current} value={bed?.id ?? ""} onChange={(b) => { setBed(b); if (b.monthly_rent) setF((p) => ({ ...p, monthly_rent: String(b.monthly_rent) })); }} />
        <Field label="Monthly rent (₹)" value={f.monthly_rent} onChangeText={(t) => set("monthly_rent")(digits(t))} keyboardType="number-pad" />
        <Field label="Deposit received (₹)" value={f.security_deposit} onChangeText={(t) => set("security_deposit")(digits(t))} keyboardType="number-pad" hint={Number(f.security_deposit) > 0 ? `${rupees(Number(f.security_deposit) / 2)} comes back when they leave.` : undefined} />
      </Card>
      {error ? <View style={{ marginTop: space(3) }}><ErrorBox message={error} /></View> : null}
      <Button title="Add resident" onPress={submit} loading={busy} disabled={!ok} style={{ marginTop: space(5) }} />
      <Body muted style={{ textAlign: "center", marginTop: space(3) }}>Their first rent bill is created with the next monthly run.</Body>
    </Screen>
  );
}
