import { router, useFocusEffect } from "expo-router";
import { useCallback } from "react";
import { Text, View } from "react-native";
import { Plus, Wrench } from "phosphor-react-native";
import { Badge, Body, Button, Card, Empty, ErrorBox, LoadingCards, Screen, Title, pretty, statusTone } from "@/components/ui";
import { fmtDate } from "@/lib/dates";
import { color, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Complaint = { id: string; title: string; category: string; status: string; created_at: string; resolution_notes?: string };

export default function Help() {
  const { data, error, loading, refreshing, reload } = useData<Complaint[]>("/resident/complaints");
  useFocusEffect(useCallback(() => { reload(); }, [reload]));

  return (
    <Screen onRefresh={reload} refreshing={refreshing}>
      <Title sub="Something broken or not clean? Tell us and track it here.">Help</Title>
      <Button title="Report an issue" icon={<Plus size={18} color={color.bg} weight="bold" />} onPress={() => router.push("/new-complaint")} />
      <View style={{ height: space(5) }} />
      {loading ? <LoadingCards n={2} /> : error ? <ErrorBox message={error} onRetry={reload} /> : data?.length ? (
        <View style={{ gap: space(3) }}>
          {data.map((c) => (
            <Card key={c.id} style={{ gap: space(2) }}>
              <View style={{ flexDirection: "row", justifyContent: "space-between", gap: space(3) }}>
                <Text style={[type.label, { color: color.ink, fontSize: 16, flex: 1 }]}>{c.title}</Text>
                <Badge label={pretty(c.status)} tone={statusTone(c.status)} />
              </View>
              <Body muted>{pretty(c.category)} · {fmtDate(c.created_at)}</Body>
              {c.resolution_notes ? <Body>{c.resolution_notes}</Body> : null}
            </Card>
          ))}
        </View>
      ) : <Empty icon={<Wrench size={44} color={color.ink} weight="light" />} title="No issues reported" body="Everything working? Great." />}
    </Screen>
  );
}
