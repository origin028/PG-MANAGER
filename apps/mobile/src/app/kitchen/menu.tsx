import { useState } from "react";
import { Text, View } from "react-native";
import { CheckCircle } from "phosphor-react-native";
import { Body, Button, Card, ErrorBox, Field, LoadingCards, Screen, Segmented, Title } from "@/components/ui";
import { api } from "@/lib/api";
import { todayKey } from "@/lib/dates";
import { useProperties } from "@/lib/owner";
import { color, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Item = { id: string; day_of_week: string; meal_type: string; dishes: string[]; start_time?: string; end_time?: string };
const DAYS = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"];
const MEALS = ["BREAKFAST", "LUNCH", "DINNER"];
const nice = (m: string) => m.charAt(0) + m.slice(1).toLowerCase();

function MealEditor({ propertyId, day, meal, item, onSaved }: { propertyId: string; day: string; meal: string; item?: Item; onSaved: () => void }) {
  const [dishes, setDishes] = useState((item?.dishes ?? []).join("\n"));
  const [start, setStart] = useState(item?.start_time ?? "");
  const [end, setEnd] = useState(item?.end_time ?? "");
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    setBusy(true); setError(null); setSaved(false);
    const body = { dishes: dishes.split("\n").map((d) => d.trim()).filter(Boolean), start_time: start.trim() || null, end_time: end.trim() || null };
    try {
      if (item) await api(`/food-menus/${item.id}`, { method: "PATCH", json: body });
      else await api("/food-menus", { method: "POST", json: { ...body, property_id: propertyId, day_of_week: day, meal_type: meal } });
      setSaved(true); onSaved();
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  return (
    <Card style={{ gap: space(1) }}>
      <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginBottom: space(3) }}>
        <Text style={[type.h2, { color: color.ink }]}>{nice(meal)}</Text>
        {saved ? <CheckCircle size={22} color={color.ok} weight="fill" /> : null}
      </View>
      <Field label="Dishes (one per line)" value={dishes} onChangeText={(t) => { setDishes(t); setSaved(false); }} multiline placeholder={"Rice\nDal\nRoti"} />
      <View style={{ flexDirection: "row", gap: space(3) }}>
        <View style={{ flex: 1 }}><Field label="From" value={start} onChangeText={setStart} placeholder="07:30 AM" /></View>
        <View style={{ flex: 1 }}><Field label="To" value={end} onChangeText={setEnd} placeholder="09:30 AM" /></View>
      </View>
      {error ? <ErrorBox message={error} /> : null}
      <Button title={item ? "Save changes" : "Add to menu"} variant="secondary" onPress={save} loading={busy} disabled={!dishes.trim()} />
    </Card>
  );
}

/** Kitchen edits the fixed weekly menu. Residents see changes immediately. Timings also define when passes scan. */
export default function KitchenMenu() {
  const { props, current, setCurrent } = useProperties();
  const [day, setDay] = useState<string>(todayKey());
  const { data, error, loading, reload } = useData<Item[]>(current ? `/food-menus?property_id=${current}` : null);

  const items = (Array.isArray(data) ? data : []).filter((i) => i.day_of_week === day);

  return (
    <Screen onRefresh={reload}>
      <Title sub="Changes show up in residents' apps right away.">Weekly menu</Title>
      {props.length > 1 ? <View style={{ marginBottom: space(3) }}><Segmented value={current ?? ""} onChange={setCurrent} options={props.map((p) => ({ value: p.id, label: p.name }))} /></View> : null}
      <Segmented value={day} onChange={setDay} options={DAYS.map((d) => ({ value: d, label: d === todayKey() ? "Today" : nice(d).slice(0, 3) }))} />
      <View style={{ height: space(4) }} />
      {loading ? <LoadingCards /> : error ? <ErrorBox message={error} onRetry={reload} /> : current ? (
        <View style={{ gap: space(3) }}>
          {MEALS.map((m) => { const it = items.find((i) => i.meal_type === m); return <MealEditor key={`${day}-${m}-${it?.id ?? "new"}-${(it?.dishes ?? []).join("|")}-${it?.start_time ?? ""}-${it?.end_time ?? ""}`} propertyId={current} day={day} meal={m} item={it} onSaved={reload} />; })}
        </View>
      ) : <Body muted>No home assigned.</Body>}
    </Screen>
  );
}
