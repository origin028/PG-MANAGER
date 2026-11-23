import { Alert, Platform, Text, View } from "react-native";
import { SignOut } from "phosphor-react-native";
import { Body, Button, Card, ErrorBox, H2, LoadingCards, Screen, Segmented, Title } from "@/components/ui";
import { useProperties } from "@/lib/owner";
import { useSession } from "@/lib/session";
import { color, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Today = { current_meal: string | null; next_meal: string | null; residents: number; served: Record<string, number>; recent: { name: string; room?: string; meal: string; served_at: string }[] };
const nice = (m?: string | null) => (m ? m.charAt(0) + m.slice(1).toLowerCase() : "");

export default function KitchenToday() {
  const { signOut, me } = useSession();
  const { props, current, setCurrent } = useProperties();
  const { data, error, loading, refreshing, reload } = useData<Today>(current ? `/kitchen/today?property_id=${current}` : null);
  const out = () => (Platform.OS === "web" ? signOut() : Alert.alert("Sign out?", undefined, [{ text: "Cancel", style: "cancel" }, { text: "Sign out", style: "destructive", onPress: signOut }]));

  return (
    <Screen onRefresh={reload} refreshing={refreshing}>
      <Title sub={me?.full_name}>Today in the kitchen</Title>
      {props.length > 1 ? <View style={{ marginBottom: space(4) }}><Segmented value={current ?? ""} onChange={setCurrent} options={props.map((p) => ({ value: p.id, label: p.name }))} /></View> : null}
      {loading ? <LoadingCards /> : error ? <ErrorBox message={error} onRetry={reload} /> : data && (
        <>
          <Card tone="black" style={{ gap: space(1) }}>
            <Text style={[type.small, { color: "#ffffffaa" }]}>{data.current_meal ? "Serving now" : "Next up"}</Text>
            <Text style={{ fontSize: 40, fontWeight: "700", letterSpacing: -1.4, color: color.bg }}>{nice(data.current_meal ?? data.next_meal) || "Closed"}</Text>
            {data.current_meal ? (
              <Text style={[type.body, { color: "#ffffffaa" }]}>{data.served[data.current_meal] ?? 0} of {data.residents} residents served</Text>
            ) : null}
          </Card>
          <View style={{ flexDirection: "row", gap: space(3), marginTop: space(3) }}>
            {["BREAKFAST", "LUNCH", "DINNER"].map((m) => (
              <Card key={m} style={{ flex: 1, paddingHorizontal: space(4) }}>
                <Text style={{ fontSize: 26, fontWeight: "700", color: color.ink }}>{data.served[m] ?? 0}</Text>
                <Body muted>{nice(m)}</Body>
              </Card>
            ))}
          </View>
          <H2>Recently served</H2>
          {data.recent.length ? (
            <Card style={{ paddingVertical: space(1) }}>
              {data.recent.map((r, i) => (
                <View key={i} style={{ flexDirection: "row", alignItems: "center", paddingVertical: space(3), gap: space(3) }}>
                  <View style={{ flex: 1 }}>
                    <Text style={[type.label, { color: color.ink }]}>{r.name}</Text>
                    <Body muted>{nice(r.meal)}{r.room ? ` · Room ${r.room}` : ""}</Body>
                  </View>
                  <Body muted>{new Date(r.served_at).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit" })}</Body>
                </View>
              ))}
            </Card>
          ) : <Body muted>No one served yet today.</Body>}
        </>
      )}
      <Button title="Sign out" variant="danger" icon={<SignOut size={18} color={color.bad} />} onPress={out} style={{ marginTop: space(8) }} />
    </Screen>
  );
}
