import { router, useLocalSearchParams } from "expo-router";
import { useEffect, useState } from "react";
import { Pressable, Text, View } from "react-native";
import { ArrowLeft, Clock } from "phosphor-react-native";
import { KycDocPicker, appendDocs, neededDocs, type Docs, type Method } from "@/components/kyc-docs";
import { Body, Button, ErrorBox, Field, Screen, Segmented, Title } from "@/components/ui";
import { api } from "@/lib/api";
import { color, space, type } from "@/lib/theme";

type Home = { id: string; name: string; city?: string };

const STEPS = ["About you", "Address", "Documents", "Verify"] as const;

export default function Join() {
  const { home } = useLocalSearchParams<{ home?: string }>();
  const [step, setStep] = useState(0);
  const [later, setLater] = useState(false);
  const [homes, setHomes] = useState<Home[]>([]);
  const [f, setF] = useState({
    full_name: "", date_of_birth: "", gender: "Female", occupation: "", primary_phone: "", email: "", emergency_contact: "",
    house_flat_no: "", street: "", landmark: "", city: "", state: "", pincode: "", property_id: "",
  });
  const [method, setMethod] = useState<Method>("Aadhaar + PAN");
  const [docs, setDocs] = useState<Docs>({});
  const [otp, setOtp] = useState("");
  const [sentTo, setSentTo] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  useEffect(() => {
    api<Home[]>("/auth/resident/properties", { auth: false }).then((h) => {
      setHomes(h);
      const fromQr = home && h.some((x) => x.id === home) ? home : null;
      if (fromQr || h.length === 1) setF((p) => ({ ...p, property_id: fromQr ?? h[0].id }));
    }).catch(() => setHomes([]));
  }, [home]);

  const set = (k: keyof typeof f) => (v: string) => setF((p) => ({ ...p, [k]: v }));
  const needed = neededDocs(method);

  const valid = [
    f.full_name.trim().length > 1 && /^\d{4}-\d{2}-\d{2}$/.test(f.date_of_birth) && f.primary_phone.replace(/\D/g, "").length >= 10 && /\S+@\S+\.\S+/.test(f.email) && f.emergency_contact.trim().length > 3 && f.occupation.trim().length > 1,
    !!f.house_flat_no && !!f.street && !!f.city && !!f.state && /^\d{6}$/.test(f.pincode) && !!f.property_id,
    needed.every((k) => docs[k]),
  ];

  async function submit(skipDocs = false) {
    setBusy(true); setError(null); setLater(skipDocs);
    try {
      const form = new FormData();
      Object.entries({ ...f, primary_phone: f.primary_phone.replace(/\D/g, "").slice(-10), verification_method: skipDocs ? "LATER" : method }).forEach(([k, v]) => form.append(k, v));
      if (!skipDocs) await appendDocs(form, method, docs);
      const d = await api<{ email_masked?: string }>("/auth/resident/register/otp/request", { method: "POST", body: form, auth: false });
      setSentTo(d.email_masked ?? f.email);
      setStep(3);
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  async function verify() {
    setBusy(true); setError(null);
    try {
      await api("/auth/resident/register/otp/verify", { method: "POST", json: { phone: f.primary_phone.replace(/\D/g, "").slice(-10), otp }, auth: false });
      setDone(true);
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  if (done) {
    return (
      <Screen narrow>
        <View style={{ alignItems: "center", marginTop: space(20), gap: space(3) }}>
          <Clock size={56} color={color.ink} weight="light" />
          <Text style={[type.h1, { color: color.ink, textAlign: "center" }]}>You're in the queue</Text>
          <Body muted style={{ textAlign: "center", maxWidth: 300 }}>
            {later ? "The owner will approve you and assign your bed. After that, sign in and add your ID photos under 'Finish your KYC'." : "The owner will check your documents and assign your bed. You can sign in as soon as you're approved."}
          </Body>
          <Button title="Back to start" variant="secondary" onPress={() => router.replace("/welcome")} style={{ marginTop: space(6), alignSelf: "stretch" }} />
        </View>
      </Screen>
    );
  }

  return (
    <Screen narrow>
      <Pressable onPress={() => (step > 0 && step < 3 ? setStep(step - 1) : router.back())} hitSlop={12} style={{ marginTop: space(3) }} accessibilityLabel="Back">
        <ArrowLeft size={24} color={color.ink} />
      </Pressable>
      <View style={{ flexDirection: "row", gap: 6, marginTop: space(5) }}>
        {STEPS.map((s, i) => <View key={s} style={{ flex: 1, height: 4, borderRadius: 2, backgroundColor: i <= step ? color.ink : color.line }} />)}
      </View>

      {step === 0 && (
        <>
          <Title sub="Takes about two minutes. No photocopies needed.">Join Origin Living</Title>
          <Field label="Full name" value={f.full_name} onChangeText={set("full_name")} autoComplete="name" textContentType="name" />
          <Field label="Date of birth" value={f.date_of_birth} onChangeText={set("date_of_birth")} placeholder="YYYY-MM-DD" keyboardType="numbers-and-punctuation" maxLength={10} />
          <Text style={[type.label, { color: color.ink, marginBottom: space(2) }]}>Gender</Text>
          <Segmented value={f.gender} onChange={set("gender")} options={[{ value: "Female", label: "Female" }, { value: "Male", label: "Male" }, { value: "Other", label: "Other" }]} />
          <View style={{ height: space(4) }} />
          <Field label="Occupation" value={f.occupation} onChangeText={set("occupation")} placeholder="Student, software engineer..." />
          <Field label="Mobile number" value={f.primary_phone} onChangeText={set("primary_phone")} keyboardType="phone-pad" autoComplete="tel" />
          <Field label="Email" value={f.email} onChangeText={set("email")} keyboardType="email-address" autoCapitalize="none" autoComplete="email" hint="We'll send your verification code here." />
          <Field label="Emergency contact" value={f.emergency_contact} onChangeText={set("emergency_contact")} placeholder="Name and mobile number" />
          <Button title="Continue" onPress={() => setStep(1)} disabled={!valid[0]} />
        </>
      )}

      {step === 1 && (
        <>
          <Title sub="Your permanent home address.">Address</Title>
          <Field label="House / flat no." value={f.house_flat_no} onChangeText={set("house_flat_no")} />
          <Field label="Street" value={f.street} onChangeText={set("street")} />
          <Field label="Landmark (optional)" value={f.landmark} onChangeText={set("landmark")} />
          <Field label="City" value={f.city} onChangeText={set("city")} />
          <Field label="State" value={f.state} onChangeText={set("state")} />
          <Field label="PIN code" value={f.pincode} onChangeText={(t) => set("pincode")(t.replace(/\D/g, "").slice(0, 6))} keyboardType="number-pad" />
          {home && f.property_id === home ? (
            <Body muted style={{ marginBottom: space(2) }}>Joining <Text style={{ fontWeight: "700", color: color.ink }}>{homes.find((h) => h.id === home)?.name}</Text></Body>
          ) : <Text style={[type.label, { color: color.ink, marginBottom: space(2) }]}>Which home are you joining?</Text>}
          {home && f.property_id === home ? null : homes.length ? (
            <Segmented value={f.property_id} onChange={set("property_id")} options={homes.map((h) => ({ value: h.id, label: h.name }))} />
          ) : <Body muted>No homes are open for joining right now.</Body>}
          <Button title="Continue" onPress={() => setStep(2)} disabled={!valid[1]} style={{ marginTop: space(6) }} />
        </>
      )}

      {step === 2 && (
        <>
          <Title sub="Clear photos, all four corners visible. Stored encrypted; only the owner can see them.">Your ID</Title>
          <KycDocPicker method={method} onMethod={setMethod} docs={docs} onDocs={setDocs} onError={setError} />
          {error ? <View style={{ marginTop: space(4) }}><ErrorBox message={error} /></View> : null}
          <Button title="Submit and verify email" onPress={() => submit(false)} loading={busy && !later} disabled={!valid[2] || busy} style={{ marginTop: space(6) }} />
          <Pressable onPress={() => submit(true)} disabled={busy} style={{ marginTop: space(5), alignSelf: "center", opacity: busy ? 0.4 : 1 }} accessibilityRole="button">
            <Text style={[type.label, { color: color.ink }]}>{busy && later ? "Sending..." : "Add ID photos later"}</Text>
          </Pressable>
          <Body muted style={{ marginTop: space(2), textAlign: "center", fontSize: 13 }}>You can finish your KYC in the app after approval. You'll have a few days to do it.</Body>
        </>
      )}

      {step === 3 && (
        <>
          <Title sub={`Enter the 6-digit code we sent to ${sentTo}.`}>Verify your email</Title>
          <Field label="6-digit code" value={otp} onChangeText={(t) => setOtp(t.replace(/\D/g, "").slice(0, 6))} keyboardType="number-pad" autoComplete="one-time-code" textContentType="oneTimeCode" autoFocus />
          {error ? <ErrorBox message={error} /> : null}
          <Button title="Finish" onPress={verify} loading={busy} disabled={otp.length !== 6} style={{ marginTop: space(2) }} />
        </>
      )}
    </Screen>
  );
}
