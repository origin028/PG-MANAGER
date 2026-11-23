import { router, useLocalSearchParams } from "expo-router";
import { useState } from "react";
import { Text, View } from "react-native";
import { Bed, Trash } from "phosphor-react-native";
import { Header, ListRow, confirmAction, digits } from "@/components/kit";
import { Badge, Body, Button, Card, ErrorBox, Field, H2, LoadingCards, Screen, Segmented } from "@/components/ui";
import { api } from "@/lib/api";
import { listOf } from "@/lib/owner";
import { ROOM_TYPES, roomTypeLabel } from "@/lib/rooms";
import { color, rupees, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type RoomD = { id: string; property_id: string; room_number: string; floor_number: number; room_type: string; base_monthly_rent?: number; base_rent?: number; deposit_amount?: number; is_active: boolean };
type BedS = { id: string; bed_number: string; status: string; monthly_rent?: number };
type Res = { id: string; full_name: string; room_number?: string; bed_number?: string };

export default function RoomDetail() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const room = useData<RoomD>(`/rooms/${id}`);
  const beds = useData<BedS[]>(`/beds/rooms/${id}/beds`);
  const res = useData<{ items: Res[] }>(`/residents?status=ACTIVE&page_size=100`);
  const [panel, setPanel] = useState<null | "edit" | "add">(null);
  const [f, setF] = useState({ room_number: "", floor_number: "", room_type: "", rent: "", deposit: "" });
  const [addCount, setAddCount] = useState("1");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const reload = () => { room.reload(); beds.reload(); res.reload(); };
  const r = room.data;
  const rent = r?.base_monthly_rent ?? r?.base_rent ?? 0;
  const who = (bedNo: string) => listOf<Res>(res.data as never).find((x) => x.room_number === r?.room_number && x.bed_number === bedNo);

  async function run(fn: () => Promise<unknown>) {
    setBusy(true); setError(null);
    try { await fn(); setPanel(null); reload(); } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  const openEdit = () => {
    if (!r) return;
    setF({ room_number: r.room_number, floor_number: String(r.floor_number), room_type: r.room_type, rent: String(rent), deposit: String(r.deposit_amount ?? 0) });
    setPanel(panel === "edit" ? null : "edit");
  };
  const saveRoom = () => run(() => api(`/rooms/${id}`, { method: "PATCH", json: { room_number: f.room_number.trim(), floor_number: Number(f.floor_number), room_type: f.room_type, base_monthly_rent: Number(f.rent), deposit_amount: Number(f.deposit || 0) } }));
  const addBeds = () => run(() => api(`/rooms/${id}`, { method: "PATCH", json: { add_beds: Number(addCount) } }));
  const removeBed = (b: BedS) => confirmAction(`Remove bed ${b.bed_number}?`, "This bed will no longer be available for residents.", "Remove", () => run(() => api(`/beds/${b.id}`, { method: "DELETE" })));
  const deleteRoom = () => confirmAction(`Delete room ${r?.room_number}?`, "Only possible when nobody lives in it. Rooms with past residents are archived instead.", "Delete", () =>
    run(async () => { await api(`/rooms/${id}`, { method: "DELETE" }); router.back(); }));

  const list = beds.data ?? [];
  return (
    <Screen onRefresh={reload} refreshing={room.refreshing}>
      <Header title={r ? `Room ${r.room_number}` : "Room"} sub={r ? `${r.floor_number === 0 ? "Ground floor" : `Floor ${r.floor_number}`} · ${roomTypeLabel(r.room_type)} · ${rupees(rent)} per bed` : undefined}
        action={r && !r.is_active ? <Badge label="Archived" /> : undefined} />
      {error ? <View style={{ marginBottom: space(3) }}><ErrorBox message={error} /></View> : null}
      {room.loading ? <LoadingCards /> : r && (
        <>
          <View style={{ flexDirection: "row", gap: space(2) }}>
            <Button title="Edit room" variant="secondary" onPress={openEdit} style={{ flex: 1 }} />
            <Button title="Add beds" variant="secondary" onPress={() => setPanel(panel === "add" ? null : "add")} style={{ flex: 1 }} />
          </View>
          {panel === "edit" ? (
            <Card style={{ marginTop: space(3) }}>
              <Field label="Room number" value={f.room_number} onChangeText={(t) => setF({ ...f, room_number: t })} />
              <Field label="Floor" value={f.floor_number} onChangeText={(t) => setF({ ...f, floor_number: digits(t) })} keyboardType="number-pad" />
              <Text style={[type.label, { color: color.ink, marginBottom: space(2) }]}>Sharing</Text>
              <Segmented value={f.room_type} onChange={(v) => setF({ ...f, room_type: v })} options={ROOM_TYPES.map((t) => ({ value: t.value, label: t.label }))} />
              <View style={{ height: space(4) }} />
              <Field label="Rent per bed (₹)" value={f.rent} onChangeText={(t) => setF({ ...f, rent: digits(t) })} keyboardType="number-pad" hint="New residents get this rent. Current residents keep theirs (change it on their page)." />
              <Field label="Deposit per bed (₹)" value={f.deposit} onChangeText={(t) => setF({ ...f, deposit: digits(t) })} keyboardType="number-pad" />
              <Button title="Save room" onPress={saveRoom} loading={busy} disabled={!f.room_number.trim() || Number(f.rent) <= 0} />
            </Card>
          ) : null}
          {panel === "add" ? (
            <Card style={{ marginTop: space(3) }}>
              <Field label="How many beds to add?" value={addCount} onChangeText={(t) => setAddCount(digits(t).slice(0, 1))} keyboardType="number-pad" hint="Each new bed gets this room's rent." />
              <Button title={`Add ${addCount || 0} ${Number(addCount) === 1 ? "bed" : "beds"}`} onPress={addBeds} loading={busy} disabled={Number(addCount) < 1} />
            </Card>
          ) : null}

          <H2>Beds</H2>
          {list.length ? (
            <Card style={{ paddingVertical: space(1) }}>
              {list.map((b) => {
                const occupant = who(b.bed_number);
                return (
                  <ListRow key={b.id} leading={<Bed size={24} color={color.ink} weight={occupant ? "fill" : "light"} />}
                    title={`Bed ${b.bed_number}`} sub={occupant ? occupant.full_name : b.status === "AVAILABLE" ? `Free · ${rupees(b.monthly_rent ?? rent)}` : b.status.toLowerCase()}
                    onPress={occupant ? () => router.push({ pathname: "/manage/resident/[id]", params: { id: occupant.id } }) : undefined}
                    right={!occupant && b.status !== "OCCUPIED" ? <Button title="" variant="ghost" icon={<Trash size={20} color={color.bad} />} onPress={() => removeBed(b)} style={{ height: 40, paddingHorizontal: 8 }} /> : undefined} />
                );
              })}
            </Card>
          ) : <Body muted>No beds in this room.</Body>}
          <Button title="Delete room" variant="danger" onPress={deleteRoom} style={{ marginTop: space(8) }} />
        </>
      )}
    </Screen>
  );
}
