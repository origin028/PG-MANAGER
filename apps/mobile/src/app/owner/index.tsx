import { router } from "expo-router";
import { Text, View } from "react-native";
import { Bed, ChatCircleDots, CurrencyInr, UserCheck } from "phosphor-react-native";
import { Body, Card, ErrorBox, H2, LoadingCards, Screen } from "@/components/ui";
import { greeting } from "@/lib/dates";
import { listOf } from "@/lib/owner";
import { useSession } from "@/lib/session";
import { color, rupees, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Dash = { total_beds: number; occupied_beds: number; vacant_beds: number; occupancy_rate_percent: number; gross_collections: number; pending_rent: number; open_complaints: number; total_expenses: number; active_residents: number };

function Stat({ icon, label, value, onPress }: { icon: React.ReactNode; label: string; value: string; onPress?: () => void }) {
  return (
    <Card onPress={onPress} style={{ gap: space(5), minHeight: 128, justifyContent: "space-between" }}>
      {icon}
      <View>
        <Text style={{ fontSize: 26, fontWeight: "700", letterSpacing: -0.8, color: color.ink }}>{value}</Text>
        <Body muted>{label}</Body>
      </View>
    </Card>
  );
}

export default function Today() {
  const { me } = useSession();
  const dash = useData<Dash>("/reports/dashboard");
  const pending = useData<{ items: unknown[] } | unknown[]>("/residents/pending-approvals");
  const d = dash.data;
  const waiting = listOf(pending.data as never).length;

  return (
    <Screen onRefresh={() => { dash.reload(); pending.reload(); }} refreshing={dash.refreshing}>
      <View style={{ marginTop: space(4), marginBottom: space(5) }}>
        <Body muted>{greeting()}</Body>
        <Text style={[type.h1, { color: color.ink }]}>{me?.full_name?.split(" ")[0] ?? "Owner"}</Text>
      </View>
      {dash.loading ? <LoadingCards /> : dash.error ? <ErrorBox message={dash.error} onRetry={dash.reload} /> : d && (
        <>
          <Card tone="black" style={{ gap: space(2) }}>
            <Text style={[type.small, { color: "#ffffffaa" }]}>Beds occupied</Text>
            <Text style={{ fontSize: 48, fontWeight: "700", letterSpacing: -1.6, color: color.bg }}>
              {d.occupied_beds}<Text style={{ fontSize: 24, color: "#ffffff77" }}> / {d.total_beds}</Text>
            </Text>
            <View style={{ height: 8, borderRadius: 4, backgroundColor: "#ffffff22", overflow: "hidden", marginTop: space(2) }}>
              <View style={{ width: `${Math.min(100, d.occupancy_rate_percent)}%`, height: "100%", backgroundColor: color.bg, borderRadius: 4 }} />
            </View>
            <Text style={[type.small, { color: "#ffffffaa" }]}>{d.vacant_beds} beds free · {Math.round(d.occupancy_rate_percent)}% full</Text>
          </Card>
          <View style={{ flexDirection: "row", gap: space(3), marginTop: space(3) }}>
            <View style={{ flex: 1 }}><Stat icon={<CurrencyInr size={24} color={color.ink} />} label="Rent pending" value={rupees(d.pending_rent)} onPress={() => router.push("/owner/payments")} /></View>
            <View style={{ flex: 1 }}><Stat icon={<CurrencyInr size={24} color={color.ok} />} label="Collected" value={rupees(d.gross_collections)} /></View>
          </View>
          <View style={{ flexDirection: "row", gap: space(3), marginTop: space(3) }}>
            <View style={{ flex: 1 }}><Stat icon={<UserCheck size={24} color={color.ink} />} label="To approve" value={String(waiting)} onPress={() => router.push("/owner/approvals")} /></View>
            <View style={{ flex: 1 }}><Stat icon={<ChatCircleDots size={24} color={color.ink} />} label="Open issues" value={String(d.open_complaints)} onPress={() => router.push("/owner/complaints")} /></View>
          </View>
          <H2>Residents</H2>
          <Card style={{ flexDirection: "row", alignItems: "center", gap: space(4) }}>
            <Bed size={28} color={color.ink} weight="light" />
            <Body style={{ flex: 1 }}>{d.active_residents} people living with you right now.</Body>
          </Card>
        </>
      )}
    </Screen>
  );
}
