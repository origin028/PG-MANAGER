import { router } from "expo-router";
import { Pressable, Text, View } from "react-native";
import { ArrowLeft, Users } from "phosphor-react-native";
import { Badge, Body, Card, Empty, ErrorBox, LoadingCards, Screen, pretty, statusTone } from "@/components/ui";
import { fmtDate } from "@/lib/dates";
import { listOf } from "@/lib/owner";
import { color, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type R = { id: string; full_name: string; phone: string; room_number?: string; bed_number?: string; check_in_date?: string; kyc_status?: string; status: string };

export default function Residents() {
  const { data, error, loading, refreshing, reload } = useData<{ items: R[] }>("/residents?status=ACTIVE&page_size=100");
  const items = listOf<R>(data as never);
  return (
    <Screen onRefresh={reload} refreshing={refreshing}>
      <Pressable onPress={() => router.back()} hitSlop={12} style={{ marginTop: space(3) }} accessibilityLabel="Back"><ArrowLeft size={24} color={color.ink} /></Pressable>
      <Text style={[type.h1, { color: color.ink, marginTop: space(4), marginBottom: space(5) }]}>Residents</Text>
      {loading ? <LoadingCards n={3} /> : error ? <ErrorBox message={error} onRetry={reload} /> : items.length ? (
        <View style={{ gap: space(3) }}>
          {items.map((r) => (
            <Card key={r.id} style={{ gap: space(1.5) }}>
              <View style={{ flexDirection: "row", justifyContent: "space-between", gap: space(3) }}>
                <Text style={[type.label, { color: color.ink, fontSize: 16, flex: 1 }]}>{r.full_name}</Text>
                <Badge label={`KYC ${pretty(r.kyc_status ?? "pending").toLowerCase()}`} tone={statusTone(r.kyc_status)} />
              </View>
              <Body muted>Room {r.room_number ?? "-"} · Bed {r.bed_number ?? "-"} · since {fmtDate(r.check_in_date)}</Body>
              <Body>{r.phone}</Body>
            </Card>
          ))}
        </View>
      ) : <Empty icon={<Users size={44} color={color.ink} weight="light" />} title="No residents yet" />}
    </Screen>
  );
}
