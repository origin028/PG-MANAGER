import { router } from "expo-router";
import { useState } from "react";
import { Text, View } from "react-native";
import { ForkKnife, QrCode } from "phosphor-react-native";
import { MealPhoto } from "@/components/meal-photo";
import { Reveal } from "@/components/motion";
import { Body, Button, Card, Empty, ErrorBox, LoadingCards, Screen, Segmented, Title } from "@/components/ui";
import { todayKey } from "@/lib/dates";
import { mealNow } from "@/lib/meals";
import { color, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Meal = { id: string; meal_type: string; dishes: string[]; start_time?: string; end_time?: string; has_image?: boolean };
type Menu = { menu_by_day: Record<string, Meal[]> };
const ORDER = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"];
const MEAL_ORDER = ["BREAKFAST", "LUNCH", "SNACKS", "DINNER"];

export default function Food() {
  const { data, error, loading, refreshing, reload } = useData<Menu>("/resident/food-menu");
  const [day, setDay] = useState<string>(todayKey());
  const pass = useData<{ enabled?: boolean }>("/resident/meal-pass");
  const meals = [...(data?.menu_by_day?.[day] ?? [])].sort((a, b) => MEAL_ORDER.indexOf(a.meal_type) - MEAL_ORDER.indexOf(b.meal_type));
  const live = day === todayKey() ? mealNow(meals) : { now: null, next: null };

  return (
    <Screen onRefresh={reload} refreshing={refreshing}>
      <Title sub="The fixed weekly menu for your home.">This week's food</Title>
      {pass.data?.enabled ? <Button title="Show my meal pass" icon={<QrCode size={20} color={color.bg} />} onPress={() => router.push("/meal-pass")} style={{ marginBottom: space(5) }} /> : null}
      <Segmented value={day} onChange={setDay} options={ORDER.map((d) => ({ value: d, label: d === todayKey() ? "Today" : d.slice(0, 3).charAt(0) + d.slice(1, 3).toLowerCase() }))} />
      <View style={{ height: space(4) }} />
      {loading ? <LoadingCards /> : error ? <ErrorBox message={error} onRetry={reload} /> : meals.length ? (
        <View key={day} style={{ gap: space(3) }}>
          {meals.map((m, i) => (
            <Reveal key={m.meal_type} index={i}>
            <Card style={{ gap: space(2), ...(m === live.now ? { borderWidth: 2, borderColor: color.ok } : m === live.next ? { borderWidth: 1.5, borderColor: color.ink } : {}) }}>
              {m === live.now || m === live.next ? (
                <View style={{ alignSelf: "flex-start", flexDirection: "row", alignItems: "center", gap: 6, backgroundColor: m === live.now ? color.okBg : color.cream, borderRadius: 999, paddingHorizontal: 10, paddingVertical: 4 }}>
                  {m === live.now ? <View style={{ width: 7, height: 7, borderRadius: 4, backgroundColor: color.ok }} /> : null}
                  <Text style={[type.small, { fontWeight: "700", color: m === live.now ? color.ok : color.ink }]}>{m === live.now ? "Serving now" : "Up next"}</Text>
                </View>
              ) : null}
              {m.has_image ? <MealPhoto menuId={m.id} height={180} /> : null}
              <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "baseline" }}>
                <Text style={[type.h2, { color: color.ink }]}>{m.meal_type.charAt(0) + m.meal_type.slice(1).toLowerCase()}</Text>
                {m.start_time ? <Body muted>{m.start_time}{m.end_time ? ` - ${m.end_time}` : ""}</Body> : null}
              </View>
              <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space(2) }}>
                {m.dishes.map((d) => (
                  <View key={d} style={{ backgroundColor: color.cream, borderRadius: 999, paddingHorizontal: 12, paddingVertical: 6 }}>
                    <Text style={[type.small, { color: color.ink, fontWeight: "600" }]}>{d}</Text>
                  </View>
                ))}
              </View>
            </Card>
            </Reveal>
          ))}
        </View>
      ) : <Empty icon={<ForkKnife size={44} color={color.ink} weight="light" />} title="No menu for this day yet" body="The owner adds the weekly menu. Check back soon." />}
    </Screen>
  );
}
