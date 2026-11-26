import { router, useFocusEffect } from "expo-router";
import { useCallback, useState } from "react";
import { Text, View } from "react-native";
import { Bed, Plus } from "phosphor-react-native";
import { Header, SmallButton } from "@/components/kit";
import { CountUp, ProgressBar, Reveal } from "@/components/motion";
import { Body, Card, Empty, ErrorBox, LoadingCards, Screen, Segmented, tap } from "@/components/ui";
import { useWide } from "@/lib/layout";
import { useProperties } from "@/lib/owner";
import { roomTypeLabel } from "@/lib/rooms";
import { color, radius, rupees, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Room = { id: string; room_number: string; floor_number: number; room_type: string; base_rent: number; total_beds: number; occupied_beds: number; available_beds: number; is_active: boolean };
type Floor = { floor_number: number; rooms: Room[]; total_rooms: number; total_beds: number; occupied_beds: number; available_beds: number };
type Capacity = { total_capacity: number; used_beds: number; remaining_beds: number };

function BedDots({ total, occupied }: { total: number; occupied: number }) {
  return (
    <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 5 }}>
      {Array.from({ length: total }, (_, i) => (
        <View key={i} style={{ width: 16, height: 16, borderRadius: 5, backgroundColor: i < occupied ? color.ink : color.okBg, borderWidth: 1.5, borderColor: i < occupied ? color.ink : color.ok }} />
      ))}
    </View>
  );
}

export default function RoomsTab() {
  const wide = useWide();
  const { props, current, setCurrent } = useProperties();
  const fw = useData<{ floors: Floor[] }>(current ? `/rooms/floor-wise?property_id=${current}` : null);
  const cap = useData<Capacity>("/company/bed-capacity");
  const reload = fw.reload;
  const reloadCap = cap.reload;
  useFocusEffect(useCallback(() => { reload(); reloadCap(); }, [reload, reloadCap]));

  // Archived rooms (deleted with history) are kept for records but not shown on the floor plan.
  const floors = (fw.data?.floors ?? []).map((f) => ({ ...f, rooms: f.rooms.filter((r) => r.is_active) })).filter((f) => f.rooms.length)
    .map((f) => ({ ...f, total_beds: f.rooms.reduce((a, r) => a + r.total_beds, 0), occupied_beds: f.rooms.reduce((a, r) => a + r.occupied_beds, 0), available_beds: f.rooms.reduce((a, r) => a + r.available_beds, 0) }));
  const [filter, setFilter] = useState<"all" | "free" | "full">("all");
  const shown = floors.map((f) => ({ ...f, rooms: f.rooms.filter((r) => filter === "all" || (filter === "free" ? r.available_beds > 0 : r.available_beds === 0)) })).filter((f) => f.rooms.length);
  const totals = floors.reduce((a, f) => ({ beds: a.beds + f.total_beds, occ: a.occ + f.occupied_beds }), { beds: 0, occ: 0 });

  return (
    <Screen onRefresh={() => { fw.reload(); cap.reload(); }} refreshing={fw.refreshing}>
      <Header back={false} title="Rooms" sub={floors.length ? `${totals.occ} of ${totals.beds} beds taken` : undefined}
        action={current ? <SmallButton label="Add room" icon={<Plus size={16} color={color.bg} weight="bold" />} onPress={() => router.push({ pathname: "/manage/room/new", params: { property: current } })} /> : undefined} />
      {props.length > 1 ? <View style={{ marginBottom: space(4) }}><Segmented value={current ?? ""} onChange={setCurrent} options={props.map((p) => ({ value: p.id, label: p.name }))} /></View> : null}
      {floors.length ? (
        <Reveal>
          <Card tone="black" style={{ gap: space(3), marginBottom: space(4) }}>
            <View style={{ flexDirection: "row", alignItems: "baseline", justifyContent: "space-between" }}>
              <View style={{ flexDirection: "row", alignItems: "baseline" }}>
                <CountUp value={totals.beds - totals.occ} style={{ fontSize: 40, fontWeight: "700", letterSpacing: -1.4, color: color.bg }} />
                <Text style={[type.body, { color: "#ffffffaa" }]}> beds free to fill</Text>
              </View>
              <Text style={[type.label, { color: color.bg }]}>{totals.beds ? Math.round((totals.occ / totals.beds) * 100) : 0}% full</Text>
            </View>
            <ProgressBar pct={totals.beds ? (totals.occ / totals.beds) * 100 : 0} dark />
          </Card>
        </Reveal>
      ) : null}
      {floors.length ? (
        <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", marginBottom: space(4) }}>
          <Segmented value={filter} onChange={setFilter} options={[{ value: "all", label: "All rooms" }, { value: "free", label: "Has free beds" }, { value: "full", label: "Full" }]} />
        </View>
      ) : null}
      {fw.loading ? <LoadingCards /> : fw.error ? <ErrorBox message={fw.error} onRetry={fw.reload} /> : floors.length && !shown.length ? (
        <Card tone="cream"><Body>No rooms match this filter.</Body></Card>
      ) : floors.length ? (
        shown.map((f) => (
          <View key={f.floor_number} style={{ marginBottom: space(6) }}>
            <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "baseline", marginBottom: space(3) }}>
              <Text style={[type.h2, { color: color.ink }]}>{f.floor_number === 0 ? "Ground floor" : `Floor ${f.floor_number}`}</Text>
              <Body muted>{f.available_beds} free</Body>
            </View>
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space(3) }}>
              {f.rooms.map((r, i) => (
                <Reveal key={r.id} index={i} style={{ width: wide ? 230 : "47.8%" }}>
                  <Card onPress={() => { tap(); router.push({ pathname: "/manage/room/[id]", params: { id: r.id } }); }}
                    style={{ padding: space(4), gap: space(3), opacity: r.is_active ? 1 : 0.5 }}>
                    <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center" }}>
                      <Text style={{ fontSize: 24, fontWeight: "700", letterSpacing: -0.6, color: color.ink }}>{r.room_number}</Text>
                      <View style={{ backgroundColor: r.available_beds ? color.okBg : color.cream, borderRadius: radius.pill, paddingHorizontal: 8, paddingVertical: 2 }}>
                        <Text style={[type.small, { fontWeight: "700", color: r.available_beds ? color.ok : color.ink3 }]}>{r.available_beds ? `${r.available_beds} free` : "Full"}</Text>
                      </View>
                    </View>
                    <BedDots total={r.total_beds} occupied={r.occupied_beds} />
                    <Body muted style={{ fontSize: 13 }}>{roomTypeLabel(r.room_type)} · {rupees(r.base_rent)}</Body>
                  </Card>
                </Reveal>
              ))}
            </View>
          </View>
        ))
      ) : <Empty icon={<Bed size={44} color={color.ink} weight="light" />} title="No rooms yet" body="Add your first room. Its beds are created automatically." />}
      {cap.data ? (
        <Card tone="cream" style={{ marginTop: space(2) }}>
          <Body>Bed capacity on your plan: {cap.data.used_beds} of {cap.data.total_capacity} used ({cap.data.remaining_beds} left).</Body>
        </Card>
      ) : null}
    </Screen>
  );
}
