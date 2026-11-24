import { router } from "expo-router";
import { useEffect, useState } from "react";
import { Pressable, Text, View } from "react-native";
import { ArrowLeft, CheckCircle, Clock } from "phosphor-react-native";
import { KycDocPicker, appendDocs, neededDocs, type Docs, type Method } from "@/components/kyc-docs";
import { Badge, Body, Button, Card, ErrorBox, Field, LoadingCards, Screen, Segmented, Title } from "@/components/ui";
import { api } from "@/lib/api";
import { color, space, type } from "@/lib/theme";

type Kyc = {
  full_name: string; phone: string; email?: string; date_of_birth: string; gender: string; occupation: string;
  emergency_contact_name: string; emergency_contact_phone: string; house_flat_no: string; street: string; landmark: string;
  city: string; state: string; pincode: string; kyc_status: string; kyc_submitted: boolean; kyc_notes?: string | null;
  days_left: number | null; enabled: boolean;
};
const STEPS = ["About you", "Address", "ID photos"] as const;

/** A resident the owner added finishes their own details and KYC here. */
export default function CompleteKyc() {
  const [k, setK] = useState<Kyc | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [step, setStep] = useState(0);
  const [method, setMethod] = useState<Method>("Aadhaar + PAN");
  const [docs, setDocs] = useState<Docs>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  useEffect(() => {
    api<Kyc>("/resident/kyc").then(setK).catch((e) => setLoadError((e as Error).message));
  }, []);

  const set = (key: keyof Kyc) => (v: string) => setK((p) => (p ? { ...p, [key]: v } : p));
  const valid = k ? [
    /^\d{4}-\d{2}-\d{2}$/.test(k.date_of_birth) && !!k.gender && k.occupation.trim().length > 1 && k.emergency_contact_name.trim().length > 1 && k.emergency_contact_phone.replace(/\D/g, "").length >= 10,
    !!k.house_flat_no.trim() && !!k.street.trim() && !!k.city.trim() && !!k.state.trim() && /^\d{6}$/.test(k.pincode),
    neededDocs(method).every((d) => docs[d]),
  ] : [false, false, false];

  async function submit() {
    if (!k) return;
    setBusy(true); setError(null);
    try {
      const form = new FormData();
      const fields = { date_of_birth: k.date_of_birth, gender: k.gender, occupation: k.occupation, emergency_contact_name: k.emergency_contact_name,
        emergency_contact_phone: k.emergency_contact_phone.replace(/\D/g, "").slice(-10), house_flat_no: k.house_flat_no, street: k.street,
        landmark: k.landmark, city: k.city, state: k.state, pincode: k.pincode, verification_method: method };
      Object.entries(fields).forEach(([key, v]) => form.append(key, v));
      await appendDocs(form, method, docs);
      await api("/resident/kyc", { method: "POST", body: form });
      setDone(true);
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  const back = () => (step > 0 && !done ? setStep(step - 1) : router.canGoBack() ? router.back() : router.replace("/resident"));

  if (done || k?.kyc_status === "VERIFIED") {
    const verified = k?.kyc_status === "VERIFIED";
    return (
      <Screen narrow>
        <View style={{ alignItems: "center", marginTop: space(20), gap: space(3) }}>
          {verified ? <CheckCircle size={64} weight="fill" color={color.ok} /> : <Clock size={56} color={color.ink} weight="light" />}
          <Text style={[type.h1, { color: color.ink, textAlign: "center" }]}>{verified ? "KYC verified" : "Sent for checking"}</Text>
          <Body muted style={{ textAlign: "center", maxWidth: 320 }}>
            {verified ? "Your documents are verified. Nothing else to do." : "Your PG will now check your documents. Once they verify them, you're all set."}
          </Body>
          <Button title="Done" onPress={() => router.replace("/resident")} style={{ alignSelf: "stretch", marginTop: space(6) }} />
        </View>
      </Screen>
    );
  }

  return (
    <Screen narrow>
      <Pressable onPress={back} hitSlop={12} style={{ marginTop: space(3) }} accessibilityLabel="Back">
        <ArrowLeft size={24} color={color.ink} />
      </Pressable>
      {loadError ? <View style={{ marginTop: space(6) }}><ErrorBox message={loadError} /></View> : !k ? <View style={{ marginTop: space(6) }}><LoadingCards /></View> : (
        <>
          <View style={{ flexDirection: "row", gap: 6, marginTop: space(5) }}>
            {STEPS.map((s, i) => <View key={s} style={{ flex: 1, height: 4, borderRadius: 2, backgroundColor: i <= step ? color.ink : color.line }} />)}
          </View>
          {k.kyc_status === "REJECTED" && k.kyc_notes ? (
            <Card tone="cream" style={{ marginTop: space(4), gap: space(1) }}>
              <Text style={[type.label, { color: color.bad }]}>Your PG asked you to send it again</Text>
              <Body>{k.kyc_notes}</Body>
            </Card>
          ) : null}
          {k.days_left !== null ? (
            <View style={{ marginTop: space(4) }}>
              <Badge label={k.days_left > 0 ? `${k.days_left} day${k.days_left === 1 ? "" : "s"} left to finish` : "Deadline passed"} tone={k.days_left > 2 ? "neutral" : "warn"} />
            </View>
          ) : null}

          {step === 0 && (
            <>
              <Title sub={`Hi ${k.full_name.split(" ")[0]}. Your PG added you; finish your details to keep using the app.`}>About you</Title>
              <Field label="Date of birth" value={k.date_of_birth} onChangeText={set("date_of_birth")} placeholder="YYYY-MM-DD" keyboardType="numbers-and-punctuation" maxLength={10} />
              <Text style={[type.label, { color: color.ink, marginBottom: space(2) }]}>Gender</Text>
              <Segmented value={k.gender} onChange={set("gender")} options={[{ value: "Female", label: "Female" }, { value: "Male", label: "Male" }, { value: "Other", label: "Other" }]} />
              <View style={{ height: space(4) }} />
              <Field label="Occupation" value={k.occupation} onChangeText={set("occupation")} placeholder="Student, software engineer..." />
              <Field label="Emergency contact name" value={k.emergency_contact_name} onChangeText={set("emergency_contact_name")} />
              <Field label="Emergency contact mobile" value={k.emergency_contact_phone} onChangeText={set("emergency_contact_phone")} keyboardType="phone-pad" />
              <Button title="Continue" onPress={() => setStep(1)} disabled={!valid[0]} />
            </>
          )}
          {step === 1 && (
            <>
              <Title sub="Your permanent home address.">Address</Title>
              <Field label="House / flat no." value={k.house_flat_no} onChangeText={set("house_flat_no")} />
              <Field label="Street" value={k.street} onChangeText={set("street")} />
              <Field label="Landmark (optional)" value={k.landmark} onChangeText={set("landmark")} />
              <Field label="City" value={k.city} onChangeText={set("city")} />
              <Field label="State" value={k.state} onChangeText={set("state")} />
              <Field label="PIN code" value={k.pincode} onChangeText={(t) => set("pincode")(t.replace(/\D/g, "").slice(0, 6))} keyboardType="number-pad" />
              <Button title="Continue" onPress={() => setStep(2)} disabled={!valid[1]} />
            </>
          )}
          {step === 2 && (
            <>
              <Title sub="Clear photos, all four corners visible. Stored encrypted; only your PG can see them.">Your ID</Title>
              <KycDocPicker method={method} onMethod={setMethod} docs={docs} onDocs={setDocs} onError={setError} />
              {error ? <View style={{ marginTop: space(4) }}><ErrorBox message={error} /></View> : null}
              <Button title="Send for checking" onPress={submit} loading={busy} disabled={!valid[2]} style={{ marginTop: space(6) }} />
            </>
          )}
        </>
      )}
    </Screen>
  );
}
