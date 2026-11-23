import { useState } from "react";
import { Text, View } from "react-native";
import { IdentificationBadge, Plus } from "phosphor-react-native";
import { Header, ListRow, SmallButton, confirmAction, digits, nice } from "@/components/kit";
import { Badge, Body, Button, Card, Empty, ErrorBox, Field, LoadingCards, Screen, Segmented } from "@/components/ui";
import { api } from "@/lib/api";
import { useProperties } from "@/lib/owner";
import { color, rupees, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type S = { id: string; name: string; role: string; phone: string; email?: string; salary: number; joining_date?: string; is_active: boolean; property_id?: string; property_name?: string };
type Form = { id?: string; name: string; role: string; phone: string; salary: string; joining_date: string; property_id: string };
const ROLES = ["WARDEN", "COOK", "HOUSEKEEPING", "SECURITY", "MAINTENANCE", "MANAGER"];

/** Staff register (people on payroll). Kitchen app logins are managed separately in Kitchen & meal passes. */
export default function Staff() {
  const { props, current } = useProperties();
  const all = useData<S[]>("/staff");
  const list = { ...all, data: all.data?.filter((s) => s.is_active) ?? null };
  const [f, setF] = useState<Form | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    if (!f) return;
    setBusy(true); setError(null);
    const { id, ...rest } = f;
    const body = { ...rest, phone: digits(rest.phone).slice(-10), salary: Number(rest.salary || 0), joining_date: rest.joining_date || null, property_id: rest.property_id || current };
    try { await api(id ? `/staff/${id}` : "/staff", { method: id ? "PATCH" : "POST", json: body }); setF(null); list.reload(); }
    catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  const remove = (s: S) => confirmAction(`Remove ${s.name}?`, "They will be removed from your staff list.", "Remove", async () => {
    try { await api(`/staff/${s.id}`, { method: "DELETE" }); setF(null); list.reload(); } catch (e) { setError((e as Error).message); }
  });
  const set = (k: keyof Form) => (v: string) => f && setF({ ...f, [k]: v });
  const total = (list.data ?? []).filter((s) => s.is_active).reduce((a, s) => a + Number(s.salary || 0), 0);

  return (
    <Screen onRefresh={list.reload} refreshing={list.refreshing}>
      <Header title="Staff" sub={list.data?.length ? `Monthly salaries ${rupees(total)}` : undefined}
        action={!f ? <SmallButton label="Add" icon={<Plus size={16} color={color.bg} weight="bold" />} onPress={() => setF({ name: "", role: "HOUSEKEEPING", phone: "", salary: "", joining_date: new Date().toISOString().slice(0, 10), property_id: current ?? "" })} /> : undefined} />
      {f ? (
        <Card style={{ marginBottom: space(4) }}>
          <Text style={[type.h2, { color: color.ink, marginBottom: space(4) }]}>{f.id ? "Edit staff" : "New staff member"}</Text>
          <Field label="Name" value={f.name} onChangeText={set("name")} />
          <Text style={[type.label, { color: color.ink, marginBottom: space(2) }]}>Role</Text>
          <Segmented value={f.role} onChange={set("role")} options={ROLES.map((r) => ({ value: r, label: nice(r) }))} />
          <View style={{ height: space(4) }} />
          <Field label="Mobile" value={f.phone} onChangeText={set("phone")} keyboardType="phone-pad" />
          <Field label="Monthly salary (₹)" value={f.salary} onChangeText={(t) => set("salary")(digits(t))} keyboardType="number-pad" />
          <Field label="Joining date" value={f.joining_date} onChangeText={set("joining_date")} placeholder="YYYY-MM-DD" />
          {props.length > 1 ? <Segmented value={f.property_id} onChange={set("property_id")} options={props.map((p) => ({ value: p.id, label: p.name }))} /> : null}
          {error ? <ErrorBox message={error} /> : null}
          <Button title={f.id ? "Save" : "Add staff"} onPress={save} loading={busy} disabled={f.name.trim().length < 2 || digits(f.phone).length < 10} />
          {f.id ? <Button title="Remove from staff" variant="danger" onPress={() => remove(list.data!.find((s) => s.id === f.id)!)} style={{ marginTop: space(2) }} /> : null}
          <Button title="Cancel" variant="ghost" onPress={() => setF(null)} />
        </Card>
      ) : null}
      {list.loading ? <LoadingCards n={2} /> : list.error ? <ErrorBox message={list.error} onRetry={list.reload} /> : list.data?.length ? (
        <Card style={{ paddingVertical: space(1) }}>
          {list.data.map((s) => (
            <ListRow key={s.id} leading={<IdentificationBadge size={24} color={color.ink} weight="light" />} title={s.name} sub={`${nice(s.role)} · ${s.phone} · ${rupees(s.salary)}/mo`}
              right={!s.is_active ? <Badge label="Inactive" /> : undefined}
              onPress={() => setF({ id: s.id, name: s.name, role: s.role, phone: s.phone, salary: String(s.salary ?? ""), joining_date: s.joining_date ?? "", property_id: s.property_id ?? current ?? "" })} />
          ))}
        </Card>
      ) : <Empty icon={<IdentificationBadge size={44} color={color.ink} weight="light" />} title="No staff added" body="Add your cook, warden and housekeeping team." />}
      <Body muted style={{ marginTop: space(4) }}>Kitchen app logins are set up in More › Kitchen & meal passes.</Body>
    </Screen>
  );
}
