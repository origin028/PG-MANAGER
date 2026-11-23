import { Alert, Platform, Text, View } from "react-native";
import { HandCoins } from "phosphor-react-native";
import { Body, Button, Card, H2, LoadingCards, Row, Screen, Title } from "@/components/ui";
import { fmtDate } from "@/lib/dates";
import { useSession } from "@/lib/session";
import { color, rupees, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Profile = {
  full_name: string; phone: string; email: string; occupation?: string;
  emergency_contact_name?: string; emergency_contact_phone?: string;
  stay_details: { property_name: string; property_address?: string; room_number?: string; bed_number?: string; check_in_date?: string; monthly_rent: number };
};
type Deposit = { deposit_held: number; refund_percent: number; refund_on_exit: number };

export default function Me() {
  const { signOut } = useSession();
  const p = useData<Profile>("/resident/profile");
  const dep = useData<Deposit>("/resident/deposit");

  const confirmOut = () => {
    if (Platform.OS === "web") return signOut();
    Alert.alert("Sign out?", undefined, [{ text: "Cancel", style: "cancel" }, { text: "Sign out", style: "destructive", onPress: signOut }]);
  };

  return (
    <Screen onRefresh={() => { p.reload(); dep.reload(); }} refreshing={p.refreshing}>
      <Title>{p.data?.full_name ?? "Me"}</Title>
      {p.loading ? <LoadingCards n={2} /> : p.data && (
        <>
          <Card style={{ paddingVertical: space(2) }}>
            <Row label="Home" value={p.data.stay_details.property_name} />
            <Row label="Room / bed" value={`${p.data.stay_details.room_number ?? "-"} / ${p.data.stay_details.bed_number ?? "-"}`} />
            <Row label="Monthly rent" value={rupees(p.data.stay_details.monthly_rent)} />
            <Row label="Living here since" value={fmtDate(p.data.stay_details.check_in_date)} />
          </Card>

          {dep.data ? (
            <Card tone="cream" style={{ marginTop: space(3), gap: space(2) }}>
              <View style={{ flexDirection: "row", alignItems: "center", gap: space(2) }}>
                <HandCoins size={22} color={color.ink} />
                <Text style={[type.label, { color: color.ink }]}>Security deposit</Text>
              </View>
              <Text style={{ fontSize: 30, fontWeight: "700", letterSpacing: -1, color: color.ink }}>{rupees(dep.data.deposit_held)}</Text>
              <Body>You get {rupees(dep.data.refund_on_exit)} back when you move out ({dep.data.refund_percent}%), however long you stay.</Body>
            </Card>
          ) : null}

          <H2>Contact</H2>
          <Card style={{ paddingVertical: space(2) }}>
            <Row label="Mobile" value={p.data.phone} />
            <Row label="Email" value={p.data.email} />
            {p.data.emergency_contact_name ? <Row label="Emergency" value={`${p.data.emergency_contact_name} ${p.data.emergency_contact_phone ?? ""}`} /> : null}
          </Card>
        </>
      )}
      <Button title="Sign out" variant="danger" onPress={confirmOut} style={{ marginTop: space(8) }} />
      <Body muted style={{ textAlign: "center", marginTop: space(4) }}>Origin Living</Body>
    </Screen>
  );
}
