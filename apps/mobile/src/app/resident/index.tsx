import { router } from "expo-router";
import { Text, View } from "react-native";
import { Bed, IdentificationCard, Megaphone, QrCode } from "phosphor-react-native";
import { Badge, Body, Button, Card, ErrorBox, H2, LoadingCards, Screen } from "@/components/ui";
import { fmtDate, greeting, todayKey } from "@/lib/dates";
import { color, rupees, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Dashboard = {
  resident_info: { full_name: string };
  stay_details: { property_name: string; room_number?: string; bed_number?: string; monthly_rent: number };
  rent_summary: { outstanding_dues: number; rent_due_date?: string; current_rent_amount: number };
};
type Menu = { menu_by_day: Record<string, { meal_type: string; dishes: string[]; start_time?: string }[]> };
type Announcement = { id: string; title: string; content: string; created_at: string };

export default function Home() {
  const dash = useData<Dashboard>("/resident/dashboard");
  const menu = useData<Menu>("/resident/food-menu");
  const news = useData<Announcement[]>("/announcements/resident");
  const pass = useData<{ enabled?: boolean }>("/resident/meal-pass");
  const portal = useData<{ kyc_status: string; kyc_submitted: boolean; days_left: number | null; kyc_notes?: string | null }>("/resident/portal");
  const reload = () => { dash.reload(); menu.reload(); news.reload(); portal.reload(); };
  const k = portal.data;
  const kycTodo = !!k && k.kyc_status !== "VERIFIED" && (!k.kyc_submitted || k.kyc_status === "REJECTED");
  const kycWaiting = !!k && k.kyc_status === "SUBMITTED";

  const d = dash.data;
  const due = d?.rent_summary.outstanding_dues ?? 0;
  const today = menu.data?.menu_by_day?.[todayKey()] ?? [];

  return (
    <Screen onRefresh={reload} refreshing={dash.refreshing}>
      <View style={{ marginTop: space(4), marginBottom: space(5) }}>
        <Body muted>{greeting()}</Body>
        <Text style={[type.h1, { color: color.ink }]}>{d ? d.resident_info.full_name.split(" ")[0] : " "}</Text>
      </View>

      {kycTodo ? (
        <Card onPress={() => router.push("/complete-kyc")} style={{ flexDirection: "row", alignItems: "center", gap: space(4), marginBottom: space(3), borderWidth: 1.5, borderColor: color.ink }}>
          <IdentificationCard size={30} color={color.ink} />
          <View style={{ flex: 1, gap: 2 }}>
            <Text style={[type.label, { color: color.ink, fontSize: 16 }]}>{k?.kyc_status === "REJECTED" ? "Send your KYC again" : "Finish your KYC"}</Text>
            <Body muted style={{ fontSize: 14 }}>
              {k?.kyc_status === "REJECTED" && k.kyc_notes ? k.kyc_notes : k?.days_left != null ? `${k.days_left} day${k.days_left === 1 ? "" : "s"} left. Your app access pauses if it isn't verified by then.` : "Add your details and ID photos. Takes about two minutes."}
            </Body>
          </View>
        </Card>
      ) : kycWaiting ? (
        <Card tone="cream" style={{ marginBottom: space(3) }}>
          <Body>Your KYC is with your PG for checking.{k?.days_left != null ? ` They have ${k.days_left} day${k.days_left === 1 ? "" : "s"} to verify it.` : ""}</Body>
        </Card>
      ) : null}

      {dash.loading ? <LoadingCards /> : dash.error ? <ErrorBox message={dash.error} onRetry={dash.reload} /> : d && (
        <>
          {!d.stay_details.room_number && due <= 0 ? (
            <Card tone="black" style={{ gap: space(2) }}>
              <Text style={[type.small, { color: "#ffffffaa" }]}>Welcome</Text>
              <Text style={{ fontSize: 30, fontWeight: "700", letterSpacing: -1, color: color.bg }}>Your bed is being arranged</Text>
              <Text style={[type.body, { color: "#ffffffaa" }]}>Your PG will assign your room and rent. You'll see it here.</Text>
            </Card>
          ) : (
          <Card tone="black" style={{ gap: space(4) }}>
            <Text style={[type.small, { color: "#ffffffaa" }]}>{due > 0 ? "Rent due" : "Rent"}</Text>
            <Text style={{ fontSize: 44, fontWeight: "700", letterSpacing: -1.5, color: color.bg }}>{due > 0 ? rupees(due) : "All paid"}</Text>
            <Text style={[type.body, { color: "#ffffffaa" }]}>
              {due > 0 ? `Due ${fmtDate(d.rent_summary.rent_due_date)}` : `Next rent ${rupees(d.rent_summary.current_rent_amount)}`}
            </Text>
            {due > 0 ? <Button title="Pay now" variant="secondary" onPress={() => router.push("/resident/pay")} /> : null}
          </Card>
          )}

          <Card style={{ marginTop: space(3), flexDirection: "row", alignItems: "center", gap: space(4) }}>
            <Bed size={30} color={color.ink} weight="light" />
            <View style={{ flex: 1 }}>
              <Text style={[type.label, { color: color.ink, fontSize: 16 }]}>{d.stay_details.property_name}</Text>
              <Body muted>{d.stay_details.room_number ? `Room ${d.stay_details.room_number} · Bed ${d.stay_details.bed_number}` : "Room not assigned yet"}</Body>
            </View>
          </Card>
        </>
      )}

      {pass.data?.enabled ? (
      <Card onPress={() => router.push("/meal-pass")} style={{ marginTop: space(3), flexDirection: "row", alignItems: "center", gap: space(4) }}>
        <QrCode size={30} color={color.ink} weight="light" />
        <View style={{ flex: 1 }}>
          <Text style={[type.label, { color: color.ink, fontSize: 16 }]}>Meal pass</Text>
          <Body muted>Show this QR at the kitchen</Body>
        </View>
      </Card>
      ) : null}

      <H2>Today's meals</H2>
      {today.length ? (
        <View style={{ gap: space(2) }}>
          {today.map((m) => (
            <Card key={m.meal_type} tone="cream" style={{ paddingVertical: space(4) }}>
              <View style={{ flexDirection: "row", justifyContent: "space-between" }}>
                <Text style={[type.label, { color: color.ink }]}>{m.meal_type.charAt(0) + m.meal_type.slice(1).toLowerCase()}</Text>
                {m.start_time ? <Body muted>{m.start_time}</Body> : null}
              </View>
              <Body style={{ marginTop: space(1) }}>{m.dishes.join(", ") || "Menu coming soon"}</Body>
            </Card>
          ))}
        </View>
      ) : <Card tone="cream"><Body muted>Today's menu hasn't been added yet.</Body></Card>}

      <H2>From the owner</H2>
      {news.data?.length ? (
        <View style={{ gap: space(2) }}>
          {news.data.slice(0, 3).map((a) => (
            <Card key={a.id} style={{ gap: space(1.5) }}>
              <View style={{ flexDirection: "row", alignItems: "center", gap: space(2) }}>
                <Megaphone size={18} color={color.ink} />
                <Text style={[type.label, { color: color.ink, flex: 1 }]} numberOfLines={1}>{a.title}</Text>
                <Badge label={fmtDate(a.created_at)} />
              </View>
              <Body>{a.content}</Body>
            </Card>
          ))}
        </View>
      ) : <Card tone="cream"><Body muted>No announcements right now.</Body></Card>}
    </Screen>
  );
}
