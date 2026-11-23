import { useEffect, useState } from "react";
import { View } from "react-native";
import { SignOut } from "phosphor-react-native";
import { Header, confirmAction, digits } from "@/components/kit";
import { Body, Button, Card, ErrorBox, Field, H2, Screen } from "@/components/ui";
import { api } from "@/lib/api";
import { useSession } from "@/lib/session";
import { color, space } from "@/lib/theme";

type Company = { name: string; email?: string; phone?: string; address?: string; tax_id?: string };

export default function Settings() {
  const { me, signOut } = useSession();
  const [c, setC] = useState<Company | null>(null);
  const [pw, setPw] = useState({ current_password: "", new_password: "" });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => { api<Company>("/settings/company").then(setC).catch((e) => setError((e as Error).message)); }, []);

  async function run(fn: () => Promise<unknown>, done: string) {
    setBusy(true); setError(null); setNotice(null);
    try { await fn(); setNotice(done); } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  const saveCompany = () => c && run(() => api("/settings/company", { method: "PATCH", json: { ...c, phone: c.phone ? digits(c.phone) : null } }), "Company details saved.");
  const savePw = () => run(async () => { await api("/auth/change-password", { method: "POST", json: pw }); setPw({ current_password: "", new_password: "" }); }, "Password changed.");

  return (
    <Screen>
      <Header title="Settings" sub={me?.email} />
      {notice ? <Card tone="cream" style={{ marginBottom: space(3) }}><Body>{notice}</Body></Card> : null}
      {error ? <View style={{ marginBottom: space(3) }}><ErrorBox message={error} /></View> : null}
      <H2 style={{ marginTop: 0 }}>Company</H2>
      {c ? (
        <Card>
          <Field label="Business name" value={c.name} onChangeText={(t) => setC({ ...c, name: t })} />
          <Field label="Email" value={c.email ?? ""} onChangeText={(t) => setC({ ...c, email: t })} autoCapitalize="none" keyboardType="email-address" />
          <Field label="Phone" value={c.phone ?? ""} onChangeText={(t) => setC({ ...c, phone: t })} keyboardType="phone-pad" />
          <Field label="Address" value={c.address ?? ""} onChangeText={(t) => setC({ ...c, address: t })} multiline />
          <Field label="GSTIN (optional)" value={c.tax_id ?? ""} onChangeText={(t) => setC({ ...c, tax_id: t.toUpperCase() })} autoCapitalize="characters" />
          <Button title="Save company details" onPress={saveCompany} loading={busy} disabled={!c.name?.trim()} />
        </Card>
      ) : null}
      <H2>Change password</H2>
      <Card>
        <Field label="Current password" value={pw.current_password} onChangeText={(t) => setPw({ ...pw, current_password: t })} secureTextEntry />
        <Field label="New password" value={pw.new_password} onChangeText={(t) => setPw({ ...pw, new_password: t })} secureTextEntry hint="At least 6 characters." />
        <Button title="Change password" onPress={savePw} loading={busy} disabled={!pw.current_password || pw.new_password.length < 6} />
      </Card>
      <Button title="Sign out" variant="danger" icon={<SignOut size={18} color={color.bad} />} onPress={() => confirmAction("Sign out?", "", "Sign out", signOut)} style={{ marginTop: space(8) }} />
    </Screen>
  );
}
