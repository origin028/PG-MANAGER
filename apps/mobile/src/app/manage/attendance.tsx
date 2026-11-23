import { Text, View } from "react-native";
import { Fingerprint } from "phosphor-react-native";
import { Header } from "@/components/kit";
import { Badge, Body, Card, Empty, LoadingCards, Screen, Segmented } from "@/components/ui";
import { useProperties } from "@/lib/owner";
import { color, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Attendance = { currently_in: number; currently_out: number; punches: { resident_name?: string; device_user_id: string; direction: string; punched_at: string }[] };

export default function AttendanceScreen() {
  const { props, current, setCurrent } = useProperties();
  const att = useData<Attendance>(current ? `/attendance?property_id=${current}` : null);
  return (
    <Screen onRefresh={att.reload} refreshing={att.refreshing}>
      <Header title="Attendance" sub="From the fingerprint machine, today." />
      {props.length > 1 ? <View style={{ marginBottom: space(3) }}><Segmented value={current ?? ""} onChange={setCurrent} options={props.map((p) => ({ value: p.id, label: p.name }))} /></View> : null}
      {att.loading ? <LoadingCards n={2} /> : att.data && att.data.punches.length ? (
        <>
          <View style={{ flexDirection: "row", gap: space(3) }}>
            <Card style={{ flex: 1 }}><Text style={{ fontSize: 30, fontWeight: "700", color: color.ink }}>{att.data.currently_in}</Text><Body muted>Inside</Body></Card>
            <Card style={{ flex: 1 }}><Text style={{ fontSize: 30, fontWeight: "700", color: color.ink }}>{att.data.currently_out}</Text><Body muted>Out</Body></Card>
          </View>
          <Card style={{ marginTop: space(3), paddingVertical: space(1) }}>
            {[...att.data.punches].reverse().map((p, i) => (
              <View key={i} style={{ flexDirection: "row", alignItems: "center", paddingVertical: space(3), gap: space(3) }}>
                <Text style={[type.body, { color: color.ink, flex: 1 }]}>{p.resident_name ?? `Fingerprint #${p.device_user_id}`}</Text>
                <Body muted>{new Date(p.punched_at).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit" })}</Body>
                <Badge label={p.direction === "IN" ? "In" : "Out"} tone={p.direction === "IN" ? "ok" : "neutral"} />
              </View>
            ))}
          </Card>
        </>
      ) : <Card tone="cream"><Empty icon={<Fingerprint size={40} color={color.ink} weight="light" />} title="No entries yet today" body="Once the fingerprint machine is connected, entries and exits appear here." /></Card>}
    </Screen>
  );
}
