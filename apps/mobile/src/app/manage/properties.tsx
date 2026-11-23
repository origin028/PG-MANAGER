import { useState } from "react";
import { Text, View } from "react-native";
import { Buildings, Plus } from "phosphor-react-native";
import { Header, ListRow, SmallButton, digits, nice } from "@/components/kit";
import { Badge, Button, Card, Empty, ErrorBox, Field, LoadingCards, Screen, Segmented } from "@/components/ui";
import { api } from "@/lib/api";
import { color, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type P = { id: string; name: string; code?: string; city?: string; property_type?: string; is_active?: boolean };
type Form = { id?: string; name: string; code: string; property_type: string; address_line1: string; city: string; state: string; pincode: string; contact_phone: string; contact_email: string; total_floors: string };
const blank: Form = { name: "", code: "", property_type: "CO_LIVING", address_line1: "", city: "Bengaluru", state: "Karnataka", pincode: "", contact_phone: "", contact_email: "", total_floors: "3" };
const TYPES = [{ value: "CO_LIVING", label: "Co-living" }, { value: "GIRLS", label: "Women only" }, { value: "MENS", label: "Men only" }];

export default function Properties() {
  const list = useData<P[]>("/properties");
  const [f, setF] = useState<Form | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function edit(p: P) {
    setError(null);
    try {
      const d = await api<Record<string, unknown>>(`/properties/${p.id}`);
      setF({ id: p.id, name: String(d.name ?? ""), code: String(d.code ?? ""), property_type: String(d.property_type ?? "CO_LIVING"), address_line1: String(d.address_line1 ?? ""), city: String(d.city ?? ""), state: String(d.state ?? ""), pincode: String(d.pincode ?? ""), contact_phone: String(d.contact_phone ?? ""), contact_email: String(d.contact_email ?? ""), total_floors: String(d.total_floors ?? "1") });
    } catch (e) { setError((e as Error).message); }
  }
  async function save() {
    if (!f) return;
    setBusy(true); setError(null);
    const { id, ...rest } = f;
    const body = { ...rest, code: rest.code.trim().toUpperCase(), total_floors: Number(rest.total_floors || 1), contact_phone: digits(rest.contact_phone) || null, contact_email: rest.contact_email.trim() || null };
    try {
      await api(id ? `/properties/${id}` : "/properties", { method: id ? "PATCH" : "POST", json: body });
      setF(null); list.reload();
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  const set = (k: keyof Form) => (v: string) => f && setF({ ...f, [k]: v });

  return (
    <Screen onRefresh={list.reload} refreshing={list.refreshing}>
      <Header title="Properties" action={!f ? <SmallButton label="Add" icon={<Plus size={16} color={color.bg} weight="bold" />} onPress={() => setF({ ...blank })} /> : undefined} />
      {f ? (
        <Card style={{ marginBottom: space(4) }}>
          <Text style={[type.h2, { color: color.ink, marginBottom: space(4) }]}>{f.id ? "Edit property" : "New property"}</Text>
          <Field label="Name" value={f.name} onChangeText={set("name")} placeholder="Origin Grand PG" />
          <Field label="Short code" value={f.code} onChangeText={set("code")} autoCapitalize="characters" placeholder="OG-02" />
          <Text style={[type.label, { color: color.ink, marginBottom: space(2) }]}>Type</Text>
          <Segmented value={f.property_type} onChange={set("property_type")} options={TYPES} />
          <View style={{ height: space(4) }} />
          <Field label="Address" value={f.address_line1} onChangeText={set("address_line1")} />
          <Field label="City" value={f.city} onChangeText={set("city")} />
          <Field label="State" value={f.state} onChangeText={set("state")} />
          <Field label="PIN code" value={f.pincode} onChangeText={(t) => set("pincode")(digits(t).slice(0, 6))} keyboardType="number-pad" />
          <Field label="Floors" value={f.total_floors} onChangeText={(t) => set("total_floors")(digits(t))} keyboardType="number-pad" />
          <Field label="Contact mobile" value={f.contact_phone} onChangeText={set("contact_phone")} keyboardType="phone-pad" />
          <Field label="Contact email" value={f.contact_email} onChangeText={set("contact_email")} autoCapitalize="none" keyboardType="email-address" />
          {error ? <ErrorBox message={error} /> : null}
          <Button title={f.id ? "Save changes" : "Create property"} onPress={save} loading={busy} disabled={!f.name.trim() || !f.code.trim() || !f.address_line1.trim() || f.pincode.length !== 6} />
          <Button title="Cancel" variant="ghost" onPress={() => setF(null)} />
        </Card>
      ) : null}
      {list.loading ? <LoadingCards n={2} /> : list.error ? <ErrorBox message={list.error} onRetry={list.reload} /> : list.data?.length ? (
        <Card style={{ paddingVertical: space(1) }}>
          {list.data.map((p) => (
            <ListRow key={p.id} leading={<Buildings size={24} color={color.ink} weight="light" />} title={p.name} sub={[p.code, p.city, nice(p.property_type)].filter(Boolean).join(" · ")}
              right={p.is_active === false ? <Badge label="Inactive" /> : undefined} onPress={() => edit(p)} />
          ))}
        </Card>
      ) : <Empty icon={<Buildings size={44} color={color.ink} weight="light" />} title="No properties yet" />}
    </Screen>
  );
}
