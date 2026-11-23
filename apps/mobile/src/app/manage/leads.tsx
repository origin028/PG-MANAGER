import { router } from "expo-router";
import { useState } from "react";
import { Linking, Pressable, Text, View } from "react-native";
import { Phone, Plus, UserPlus } from "phosphor-react-native";
import { BedPicker, type FreeBed } from "@/components/bed-picker";
import { Header, SmallButton, confirmAction, digits, nice } from "@/components/kit";
import { Badge, Body, Button, Card, Empty, ErrorBox, Field, LoadingCards, Screen, Segmented, statusTone } from "@/components/ui";
import { api } from "@/lib/api";
import { fmtDate } from "@/lib/dates";
import { useProperties } from "@/lib/owner";
import { color, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type L = { id: string; name: string; phone: string; status: string; source?: string; requirement?: string; created_at: string; property_id: string };
const STAGES = ["NEW", "CONTACTED", "VISIT_SCHEDULED", "BOOKED", "LOST"];

export default function Leads() {
  const { current } = useProperties();
  const list = useData<L[]>("/leads");
  const [stage, setStage] = useState("OPEN");
  const [convert, setConvert] = useState<{ lead: L; bed: FreeBed | null; rent: string; deposit: string } | null>(null);
  const [add, setAdd] = useState<{ name: string; phone: string; requirement: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function run(fn: () => Promise<unknown>) {
    setBusy(true); setError(null);
    try { await fn(); list.reload(); } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  const setStatus = (l: L, s: string) => run(() => api(`/leads/${l.id}`, { method: "PATCH", json: { status: s } }));
  const doConvert = () => convert?.bed && run(async () => {
    const r = await api<{ resident_id?: string }>(`/leads/${convert.lead.id}/convert`, { method: "POST", json: { room_id: convert.bed!.room_id, bed_id: convert.bed!.id, monthly_rent: Number(convert.rent), security_deposit: Number(convert.deposit || 0) } });
    setConvert(null);
    if (r.resident_id) router.push({ pathname: "/manage/resident/[id]", params: { id: r.resident_id } });
  });
  const create = () => add && current && run(async () => { await api("/leads", { method: "POST", json: { property_id: current, name: add.name.trim(), phone: digits(add.phone).slice(-10), requirement: add.requirement.trim() || null, source: "WALK_IN" } }); setAdd(null); });

  const items = (list.data ?? []).filter((l) => stage === "OPEN" ? !["BOOKED", "LOST"].includes(l.status) : l.status === stage);

  return (
    <Screen onRefresh={list.reload} refreshing={list.refreshing}>
      <Header title="Leads" sub="People who asked about a room." action={!add ? <SmallButton label="Add" icon={<Plus size={16} color={color.bg} weight="bold" />} onPress={() => setAdd({ name: "", phone: "", requirement: "" })} /> : undefined} />
      {error ? <View style={{ marginBottom: space(3) }}><ErrorBox message={error} /></View> : null}
      {add ? (
        <Card style={{ marginBottom: space(4) }}>
          <Field label="Name" value={add.name} onChangeText={(t) => setAdd({ ...add, name: t })} />
          <Field label="Mobile" value={add.phone} onChangeText={(t) => setAdd({ ...add, phone: t })} keyboardType="phone-pad" />
          <Field label="Looking for" value={add.requirement} onChangeText={(t) => setAdd({ ...add, requirement: t })} placeholder="Double sharing from 1st" />
          <Button title="Save lead" onPress={create} loading={busy} disabled={add.name.trim().length < 2 || digits(add.phone).length < 10} />
          <Button title="Cancel" variant="ghost" onPress={() => setAdd(null)} />
        </Card>
      ) : null}
      <Segmented value={stage} onChange={setStage} options={[{ value: "OPEN", label: "Open" }, { value: "BOOKED", label: "Booked" }, { value: "LOST", label: "Lost" }]} />
      <View style={{ height: space(3) }} />
      {list.loading ? <LoadingCards n={2} /> : items.length ? (
        <View style={{ gap: space(3) }}>
          {items.map((l) => (
            <Card key={l.id} style={{ gap: space(2) }}>
              <View style={{ flexDirection: "row", justifyContent: "space-between", gap: space(3) }}>
                <Text style={[type.label, { color: color.ink, fontSize: 16, flex: 1 }]}>{l.name}</Text>
                <Badge label={nice(l.status)} tone={statusTone(l.status === "BOOKED" ? "ACTIVE" : l.status === "LOST" ? "REJECTED" : "PENDING")} />
              </View>
              {l.requirement ? <Body>{l.requirement}</Body> : null}
              <Body muted>{nice(l.source ?? "")} · {fmtDate(l.created_at)}</Body>
              <View style={{ flexDirection: "row", gap: space(2), marginTop: space(1) }}>
                <SmallButton label="Call" tone="light" icon={<Phone size={16} color={color.ink} />} onPress={() => Linking.openURL(`tel:${l.phone}`)} />
                {!["BOOKED", "LOST"].includes(l.status) ? <SmallButton label="Make resident" onPress={() => setConvert({ lead: l, bed: null, rent: "", deposit: "" })} /> : null}
              </View>
              {!["BOOKED", "LOST"].includes(l.status) ? (
                <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space(4), marginTop: space(1) }}>
                  {STAGES.filter((s) => s !== l.status && s !== "BOOKED").map((s) => (
                    <Pressable key={s} onPress={() => (s === "LOST" ? confirmAction("Mark as lost?", l.name, "Mark lost", () => setStatus(l, s)) : setStatus(l, s))}>
                      <Text style={[type.label, { color: s === "LOST" ? color.bad : color.ink2 }]}>{nice(s)}</Text>
                    </Pressable>
                  ))}
                </View>
              ) : null}
              {convert?.lead.id === l.id ? (
                <View style={{ gap: space(3), marginTop: space(2) }}>
                  <BedPicker propertyId={l.property_id} value={convert.bed?.id ?? ""} onChange={(b) => setConvert({ ...convert, bed: b, rent: b.monthly_rent ? String(b.monthly_rent) : convert.rent })} />
                  <Field label="Monthly rent (₹)" value={convert.rent} onChangeText={(t) => setConvert({ ...convert, rent: digits(t) })} keyboardType="number-pad" />
                  <Field label="Deposit (₹)" value={convert.deposit} onChangeText={(t) => setConvert({ ...convert, deposit: digits(t) })} keyboardType="number-pad" />
                  <Button title="Create resident" onPress={doConvert} loading={busy} disabled={!convert.bed || Number(convert.rent) <= 0} />
                </View>
              ) : null}
            </Card>
          ))}
        </View>
      ) : <Empty icon={<UserPlus size={44} color={color.ink} weight="light" />} title="No leads here" body="Enquiries from your website appear here." />}
    </Screen>
  );
}
