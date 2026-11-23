import { useState } from "react";
import { Text, View } from "react-native";
import { ForkKnife } from "phosphor-react-native";
import { Body, Card, Empty, ErrorBox, LoadingCards, Screen, Segmented, Title } from "@/components/ui";
import { todayKey } from "@/lib/dates";
import { color, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Meal = { meal_type: string; dishes: string[]; start_time?: string; end_time?: string };
type Menu = { menu_by_day: Record<string, Meal[]> };
const ORDER = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"];
const MEAL_ORDER = ["BREAKFAST", "LUNCH", "SNACKS", "DINNER"];

export default function Food() {
  const { data, error, loading, refreshing, reload } = useData<Menu>("/resident/food-menu");
  const [day, setDay] = useState<string>(todayKey());
  const meals = [...(data?.menu_by_day?.[day] ?? [])].sort((a, b) => MEAL_ORDER.indexOf(a.meal_type) - MEAL_ORDER.indexOf(b.meal_type));

  return (
    <Screen onRefresh={reload} refreshing={refreshing}>
      <Title sub="The fixed weekly menu for your home.">This week's food</Title>
      <Segmented value={day} onChange={setDay} options={ORDER.map((d) => ({ value: d, label: d === todayKey() ? "Today" : d.slice(0, 3).charAt(0) + d.slice(1, 3).toLowerCase() }))} />
      <View style={{ height: space(4) }} />
      {loading ? <LoadingCards /> : error ? <ErrorBox message={error} onRetry={reload} /> : meals.length ? (
        <View style={{ gap: space(3) }}>
          {meals.map((m) => (
            <Card key={m.meal_type} style={{ gap: space(2) }}>
              <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "baseline" }}>
                <Text style={[type.h2, { color: color.ink }]}>{m.meal_type.charAt(0) + m.meal_type.slice(1).toLowerCase()}</Text>
                {m.start_time ? <Body muted>{m.start_time}{m.end_time ? ` - ${m.end_time}` : ""}</Body> : null}
              </View>
              {m.dishes.map((d) => <Body key={d}>{d}</Body>)}
            </Card>
          ))}
        </View>
      ) : <Empty icon={<ForkKnife size={44} color={color.ink} weight="light" />} title="No menu for this day yet" body="The owner adds the weekly menu. Check back soon." />}
    </Screen>
  );
}
