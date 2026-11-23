import { router, useFocusEffect } from "expo-router";
import { useCallback } from "react";
import { Text, View } from "react-native";
import { CaretRight, UserCheck } from "phosphor-react-native";
import { Body, Card, Empty, ErrorBox, LoadingCards, Screen } from "@/components/ui";
import { fmtDate } from "@/lib/dates";
import { listOf } from "@/lib/owner";
import { Header } from "@/components/kit";
import { color, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

export type Pending = { resident_id: string; property_id: string; full_name: string; phone: string; email: string; property_name: string; occupation?: string; registered_at: string; date_of_birth?: string; emergency_contact?: string; verification_method?: string; city?: string; state?: string };

export default function Approvals() {
  const { data, error, loading, refreshing, reload } = useData<{ items: Pending[] }>("/residents/pending-approvals");
  useFocusEffect(useCallback(() => { reload(); }, [reload]));
  const items = listOf<Pending>(data as never);

  return (
    <Screen onRefresh={reload} refreshing={refreshing}>
      <Header title="Approvals" sub="New residents who signed up online." />
      {loading ? <LoadingCards n={2} /> : error ? <ErrorBox message={error} onRetry={reload} /> : items.length ? (
        <View style={{ gap: space(3) }}>
          {items.map((p) => (
            <Card key={p.resident_id} onPress={() => router.push({ pathname: "/approve/[id]", params: { id: p.resident_id, data: JSON.stringify(p) } })} style={{ flexDirection: "row", alignItems: "center", gap: space(4) }}>
              <View style={{ width: 46, height: 46, borderRadius: 23, backgroundColor: color.cream, alignItems: "center", justifyContent: "center" }}>
                <Text style={[type.label, { color: color.ink, fontSize: 17 }]}>{p.full_name.split(" ").map((w) => w[0]).slice(0, 2).join("")}</Text>
              </View>
              <View style={{ flex: 1 }}>
                <Text style={[type.label, { color: color.ink, fontSize: 16 }]}>{p.full_name}</Text>
                <Body muted>{p.property_name} · {fmtDate(p.registered_at)}</Body>
              </View>
              <CaretRight size={20} color={color.ink3} />
            </Card>
          ))}
        </View>
      ) : <Empty icon={<UserCheck size={44} color={color.ink} weight="light" />} title="No one waiting" body="New sign-ups from the app appear here." />}
    </Screen>
  );
}
