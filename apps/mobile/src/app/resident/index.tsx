import { router, useFocusEffect } from "expo-router";
import { useCallback } from "react";
import { Text, View } from "react-native";
import { Bed, BowlFood, ChatCircleDots, ClockCountdown, Coffee, CookingPot, ForkKnife, IdentificationCard, Megaphone, Moon, QrCode, Sun, Wallet } from "phosphor-react-native";
import { Initials } from "@/components/kit";
import { ActionGrid, CountUp, IconTile, Reveal, Springy } from "@/components/motion";
import { Body, Button, Card, ErrorBox, H2, LoadingCards, Screen, tap } from "@/components/ui";
import { fmtDate, greeting, todayKey } from "@/lib/dates";
import { mealName, mealNow } from "@/lib/meals";
import { color, radius, rupees, space, type, type Tint } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Dashboard = {
  resident_info: { full_name: string };
  stay_details: { property_name: string; room_number?: string; bed_number?: string; monthly_rent: number };
  rent_summary: { outstanding_dues: number; rent_due_date?: string; current_rent_amount: number };
};
type Meal = { meal_type: string; dishes: string[]; start_time?: string; end_time?: string };
type Menu = { menu_by_day: Record<string, Meal[]> };
type Announcement = { id: string; title: string; content: string; created_at: string };

const MEAL_ICON: Record<string, [typeof Sun, Tint]> = { BREAKFAST: [Coffee, "amber"], LUNCH: [Sun, "green"], SNACKS: [CookingPot, "rose"], DINNER: [Moon, "violet"] };

/** Whole days from today to a YYYY-MM-DD date (negative = past). */
function daysUntil(d?: string) {
  if (!d) return null;
  const a = new Date(); a.setHours(0, 0, 0, 0);
  const b = new Date(`${d.slice(0, 10)}T00:00:00`);
  return Math.round((b.getTime() - a.getTime()) / 86_400_000);
}
const dueText = (n: number | null) =>
  n === null ? null : n < 0 ? `${-n} day${n === -1 ? "" : "s"} late` : n === 0 ? "Due today" : n === 1 ? "Due tomorrow" : `Due in ${n} days`;

export default function Home() {
  const dash = useData<Dashboard>("/resident/dashboard");
  const menu = useData<Menu>("/resident/food-menu");
  const news = useData<Announcement[]>("/announcements/resident");
  const pass = useData<{ enabled?: boolean }>("/resident/meal-pass");
  const portal = useData<{ kyc_status: string; kyc_submitted: boolean; days_left: number | null; kyc_notes?: string | null }>("/resident/portal");
  const reload = () => { dash.reload(); menu.reload(); news.reload(); portal.reload(); };
  const rd = dash.reload, rp = portal.reload;
  useFocusEffect(useCallback(() => { rd(); rp(); }, [rd, rp]));
  const k = portal.data;
  const kycTodo = !!k && k.kyc_status !== "VERIFIED" && (!k.kyc_submitted || k.kyc_status === "REJECTED");
  const kycWaiting = !!k && k.kyc_status === "SUBMITTED";

  const d = dash.data;
  const due = d?.rent_summary.outstanding_dues ?? 0;
  const days = daysUntil(d?.rent_summary.rent_due_date);
  const today = menu.data?.menu_by_day?.[todayKey()] ?? [];
  const { now, next } = mealNow(today);
  const spot = now ?? next;
  const name = d?.resident_info.full_name ?? "";

  const actions = [
    { icon: Wallet, label: "Pay rent", tone: "green" as Tint, onPress: () => router.push("/resident/pay"), badge: due > 0 ? 1 : undefined },
    ...(pass.data?.enabled ? [{ icon: QrCode, label: "Meal pass", tone: "blue" as Tint, onPress: () => router.push("/meal-pass") }] : []),
    { icon: ChatCircleDots, label: "Report issue", tone: "rose" as Tint, onPress: () => router.push("/new-complaint") },
    { icon: ForkKnife, label: "Food menu", tone: "amber" as Tint, onPress: () => router.push("/resident/food") },
  ];

  return (
    <Screen onRefresh={reload} refreshing={dash.refreshing}>
      <Reveal>
        <View style={{ marginTop: space(4), marginBottom: space(5), flexDirection: "row", alignItems: "center", justifyContent: "space-between" }}>
          <View style={{ flex: 1 }}>
            <Body muted>{greeting()}</Body>
            <Text style={[type.h1, { color: color.ink }]}>{name ? name.split(" ")[0] : " "}</Text>
          </View>
          {name ? <Springy onPress={() => { tap(); router.push("/resident/me"); }} accessibilityLabel="My profile" scaleTo={0.9}><Initials name={name} size={48} /></Springy> : null}
        </View>
      </Reveal>

      {kycTodo ? (
        <Reveal>
          <Card onPress={() => router.push("/complete-kyc")} style={{ flexDirection: "row", alignItems: "center", gap: space(4), marginBottom: space(3), borderWidth: 1.5, borderColor: color.warn }}>
            <IconTile icon={IdentificationCard} tone="amber" />
            <View style={{ flex: 1, gap: 2 }}>
              <Text style={[type.label, { color: color.ink, fontSize: 16 }]}>{k?.kyc_status === "REJECTED" ? "Send your KYC again" : "Finish your KYC"}</Text>
              <Body muted style={{ fontSize: 14 }}>
                {k?.kyc_status === "REJECTED" && k.kyc_notes ? k.kyc_notes : k?.days_left != null ? `${k.days_left} day${k.days_left === 1 ? "" : "s"} left. Your app access pauses if it isn't verified by then.` : "Add your details and ID photos. Takes about two minutes."}
              </Body>
            </View>
          </Card>
        </Reveal>
      ) : kycWaiting ? (
        <Card tone="cream" style={{ marginBottom: space(3), flexDirection: "row", alignItems: "center", gap: space(3) }}>
          <IconTile icon={ClockCountdown} tone="blue" size={38} />
          <Body style={{ flex: 1 }}>Your KYC is with your PG for checking.{k?.days_left != null ? ` They have ${k.days_left} day${k.days_left === 1 ? "" : "s"} to verify it.` : ""}</Body>
        </Card>
      ) : null}

      {dash.loading ? <LoadingCards /> : dash.error ? <ErrorBox message={dash.error} onRetry={dash.reload} /> : d && (
        <>
          <Reveal index={1}>
            {!d.stay_details.room_number && due <= 0 ? (
              <Card tone="black" style={{ gap: space(2) }}>
                <Text style={[type.small, { color: "#ffffffaa" }]}>Welcome</Text>
                <Text style={{ fontSize: 30, fontWeight: "700", letterSpacing: -1, color: color.bg }}>Your bed is being arranged</Text>
                <Text style={[type.body, { color: "#ffffffaa" }]}>Your PG will assign your room and rent. You'll see it here.</Text>
              </Card>
            ) : (
              <Card tone="black" style={{ gap: space(3) }}>
                <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center" }}>
                  <Text style={[type.small, { color: "#ffffffaa" }]}>{due > 0 ? "Rent due" : "Rent"}</Text>
                  {due > 0 && days !== null ? (
                    <View style={{ backgroundColor: days < 0 ? "#ff5a4f33" : "#ffffff1a", borderRadius: radius.pill, paddingHorizontal: 10, paddingVertical: 4 }}>
                      <Text style={[type.small, { color: days < 0 ? "#ff9b93" : color.bg, fontWeight: "700" }]}>{dueText(days)}</Text>
                    </View>
                  ) : due <= 0 ? (
                    <View style={{ backgroundColor: "#7be0a833", borderRadius: radius.pill, paddingHorizontal: 10, paddingVertical: 4 }}>
                      <Text style={[type.small, { color: "#7be0a8", fontWeight: "700" }]}>Paid up</Text>
                    </View>
                  ) : null}
                </View>
                {due > 0
                  ? <CountUp value={due} format={rupees} style={{ fontSize: 46, fontWeight: "700", letterSpacing: -1.6, color: color.bg }} />
                  : <Text style={{ fontSize: 40, fontWeight: "700", letterSpacing: -1.4, color: color.bg }}>All paid ✓</Text>}
                <Text style={[type.body, { color: "#ffffffaa" }]}>
                  {due > 0 ? `Due ${fmtDate(d.rent_summary.rent_due_date)}` : `Next rent ${rupees(d.rent_summary.current_rent_amount)}`}
                </Text>
                {due > 0 ? <Button title="Pay now with UPI" variant="secondary" onPress={() => router.push("/resident/pay")} /> : null}
              </Card>
            )}
          </Reveal>

          <Reveal index={2}>
            <Card style={{ marginTop: space(3), flexDirection: "row", alignItems: "center", gap: space(4) }}>
              <IconTile icon={Bed} tone="teal" />
              <View style={{ flex: 1 }}>
                <Text style={[type.label, { color: color.ink, fontSize: 16 }]}>{d.stay_details.property_name}</Text>
                <Body muted>{d.stay_details.room_number ? `Room ${d.stay_details.room_number} · Bed ${d.stay_details.bed_number}` : "Room not assigned yet"}</Body>
              </View>
            </Card>
          </Reveal>
        </>
      )}

      <Reveal index={3} style={{ marginTop: space(5) }}>
        <ActionGrid items={actions} columns={actions.length} />
      </Reveal>

      <H2>Food today</H2>
      {spot ? (
        <Reveal index={4}>
          <Card onPress={() => router.push("/resident/food")} style={{ gap: space(3), backgroundColor: tintBg(spot.meal_type) }}>
            <View style={{ flexDirection: "row", alignItems: "center", gap: space(3) }}>
              <IconTile icon={(MEAL_ICON[spot.meal_type] ?? [BowlFood])[0]} tone={(MEAL_ICON[spot.meal_type] ?? [BowlFood, "sand"])[1]} />
              <View style={{ flex: 1 }}>
                <Text style={[type.small, { color: color.ink3, fontWeight: "700", letterSpacing: 0.4 }]}>{spot === now ? "NOW SERVING" : "UP NEXT"}</Text>
                <Text style={[type.h2, { color: color.ink }]}>{mealName(spot.meal_type)}</Text>
                {spot.start_time ? <Body muted style={{ fontSize: 14 }}>{spot.start_time}{spot.end_time ? ` – ${spot.end_time}` : ""}</Body> : null}
              </View>
            </View>
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space(2) }}>
              {(spot.dishes.length ? spot.dishes : ["Menu coming soon"]).map((x) => (
                <View key={x} style={{ backgroundColor: "#ffffffcc", borderRadius: radius.pill, paddingHorizontal: 12, paddingVertical: 6 }}>
                  <Text style={[type.small, { color: color.ink, fontWeight: "600" }]}>{x}</Text>
                </View>
              ))}
            </View>
          </Card>
        </Reveal>
      ) : (
        <Card tone="cream"><Body muted>{today.length ? "That's all the meals for today. See tomorrow's menu in Food." : "Today's menu hasn't been added yet."}</Body></Card>
      )}

      <H2>From the owner</H2>
      {news.data?.length ? (
        <View style={{ gap: space(2) }}>
          {news.data.slice(0, 3).map((a, i) => (
            <Reveal key={a.id} index={5 + i}>
              <Card style={{ flexDirection: "row", gap: space(3) }}>
                <IconTile icon={Megaphone} tone="blue" size={38} />
                <View style={{ flex: 1, gap: space(1) }}>
                  <View style={{ flexDirection: "row", alignItems: "center", gap: space(2) }}>
                    <Text style={[type.label, { color: color.ink, flex: 1 }]} numberOfLines={1}>{a.title}</Text>
                    <Text style={[type.small, { color: color.ink3 }]}>{fmtDate(a.created_at)}</Text>
                  </View>
                  <Body>{a.content}</Body>
                </View>
              </Card>
            </Reveal>
          ))}
        </View>
      ) : <Card tone="cream"><Body muted>No announcements right now.</Body></Card>}
    </Screen>
  );
}

function tintBg(meal: string) {
  return { BREAKFAST: "#fdf4e3", LUNCH: "#eaf6ef", SNACKS: "#fcecea", DINNER: "#f1ecfb" }[meal] ?? color.cream;
}
