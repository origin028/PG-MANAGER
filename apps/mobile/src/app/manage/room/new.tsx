import { router, useLocalSearchParams } from "expo-router";
import { useState } from "react";
import { Text, View } from "react-native";
import { Header, digits } from "@/components/kit";
import { Body, Button, Card, ErrorBox, Field, Screen, Segmented } from "@/components/ui";
import { api } from "@/lib/api";
import { ROOM_TYPES } from "@/lib/rooms";
import { color, space, type } from "@/lib/theme";

/** New room: choosing the sharing type creates that many beds, each at the room's rent. */
export default function NewRoom() {
  const { property } = useLocalSearchParams<{ property: string }>();
  const [f, setF] = useState({ room_number: "", floor_number: "1", room_type: "DOUBLE_SHARING", rent: "", deposit: "" });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const beds = ROOM_TYPES.find((t) => t.value === f.room_type)?.beds ?? 2;

  async function save() {
    setBusy(true); setError(null);
    try {
      const room = await api<{ id: string }>("/rooms", {
        method: "POST",
        json: { property_id: property, room_number: f.room_number.trim(), floor_number: Number(f.floor_number || 0), room_type: f.room_type,
          base_monthly_rent: Number(f.rent), deposit_amount: Number(f.deposit || 0), auto_create_beds: true, bed_count: beds },
      });
      router.replace({ pathname: "/manage/room/[id]", params: { id: room.id } });
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  return (
    <Screen>
      <Header title="Add room" />
      <Card>
        <Field label="Room number" value={f.room_number} onChangeText={(t) => setF({ ...f, room_number: t })} placeholder="203" />
        <Field label="Floor" value={f.floor_number} onChangeText={(t) => setF({ ...f, floor_number: digits(t) })} keyboardType="number-pad" hint="0 for ground floor." />
        <Text style={[type.label, { color: color.ink, marginBottom: space(2) }]}>Sharing</Text>
        <Segmented value={f.room_type} onChange={(v) => setF({ ...f, room_type: v })} options={ROOM_TYPES.map((t) => ({ value: t.value, label: t.label }))} />
        <View style={{ height: space(4) }} />
        <Field label="Rent per bed (₹ / month)" value={f.rent} onChangeText={(t) => setF({ ...f, rent: digits(t) })} keyboardType="number-pad" />
        <Field label="Deposit per bed (₹)" value={f.deposit} onChangeText={(t) => setF({ ...f, deposit: digits(t) })} keyboardType="number-pad" />
        <Body muted>{beds} {beds === 1 ? "bed" : "beds"} will be created. You can add or remove beds later.</Body>
      </Card>
      {error ? <View style={{ marginTop: space(3) }}><ErrorBox message={error} /></View> : null}
      <Button title="Create room" onPress={save} loading={busy} disabled={!f.room_number.trim() || Number(f.rent) <= 0} style={{ marginTop: space(5) }} />
    </Screen>
  );
}
