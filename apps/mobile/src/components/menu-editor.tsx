import { useState } from "react";
import { Text, View } from "react-native";
import { Camera, CheckCircle } from "phosphor-react-native";
import { MealPhoto } from "@/components/meal-photo";
import { Body, Button, Card, ErrorBox, Field, LoadingCards, Segmented } from "@/components/ui";
import { api } from "@/lib/api";
import { todayKey } from "@/lib/dates";
import { appendFile, pickImage } from "@/lib/upload";
import { color, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Item = { id: string; day_of_week: string; meal_type: string; dishes: string[]; start_time?: string; end_time?: string; has_image?: boolean };
const DAYS = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"];
const MEALS = ["BREAKFAST", "LUNCH", "DINNER"];
const nice = (m: string) => m.charAt(0) + m.slice(1).toLowerCase();

function MealEditor({ propertyId, day, meal, item, onSaved }: { propertyId: string; day: string; meal: string; item?: Item; onSaved: () => void }) {
  const [dishes, setDishes] = useState((item?.dishes ?? []).join("\n"));
  const [start, setStart] = useState(item?.start_time ?? "");
  const [end, setEnd] = useState(item?.end_time ?? "");
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);
  const [photoV, setPhotoV] = useState(0);
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

  async function photo() {
    if (!item) return;
    setError(null);
    try {
      const p = await pickImage("library");
      if (!p) return;
      setBusy(true);
      const form = new FormData();
      await appendFile(form, "photo", p);
      await api(`/food-menus/${item.id}/image`, { method: "POST", body: form });
      setPhotoV((v) => v + 1); onSaved();
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  return (
    <Card style={{ gap: space(1) }}>
      <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginBottom: space(3) }}>
        <Text style={[type.h2, { color: color.ink }]}>{nice(meal)}</Text>
        {saved ? <CheckCircle size={22} color={color.ok} weight="fill" /> : null}
      </View>
      {item?.has_image || photoV ? <View style={{ marginBottom: space(3) }}><MealPhoto menuId={item!.id} version={photoV} /></View> : null}
      <Field label="Dishes (one per line)" value={dishes} onChangeText={(t) => { setDishes(t); setSaved(false); }} multiline placeholder={"Rice\nDal\nRoti"} />
      <View style={{ flexDirection: "row", gap: space(3) }}>
        <View style={{ flex: 1 }}><Field label="From" value={start} onChangeText={setStart} placeholder="07:30 AM" /></View>
        <View style={{ flex: 1 }}><Field label="To" value={end} onChangeText={setEnd} placeholder="09:30 AM" /></View>
      </View>
      {error ? <ErrorBox message={error} /> : null}
      <View style={{ flexDirection: "row", gap: space(2) }}>
        <Button title={item ? "Save" : "Add to menu"} variant="secondary" onPress={save} loading={busy} disabled={!dishes.trim()} style={{ flex: 1 }} />
        {item ? <Button title="Photo" variant="secondary" icon={<Camera size={18} color={color.ink} />} onPress={photo} style={{ flex: 1 }} /> : null}
      </View>
    </Card>
  );
}

/** Weekly menu editor used by both the owner and the kitchen. Timings also define when meal passes scan. */
export function MenuEditor({ propertyId }: { propertyId: string }) {
  const [day, setDay] = useState<string>(todayKey());
  const { data, error, loading, reload } = useData<Item[]>(`/food-menus?property_id=${propertyId}`);
  const items = (Array.isArray(data) ? data : []).filter((i) => i.day_of_week === day);
  return (
    <>
      <Segmented value={day} onChange={setDay} options={DAYS.map((d) => ({ value: d, label: d === todayKey() ? "Today" : nice(d).slice(0, 3) }))} />
      <View style={{ height: space(4) }} />
      {loading ? <LoadingCards /> : error ? <ErrorBox message={error} onRetry={reload} /> : (
        <View style={{ gap: space(3) }}>
          {MEALS.map((m) => {
            const it = items.find((i) => i.meal_type === m);
            return <MealEditor key={`${day}-${m}-${it?.id ?? "new"}-${(it?.dishes ?? []).join("|")}-${it?.start_time ?? ""}-${it?.end_time ?? ""}-${it?.has_image ? 1 : 0}`} propertyId={propertyId} day={day} meal={m} item={it} onSaved={reload} />;
          })}
          <Body muted>Photos are optional. Residents see them on their Food tab.</Body>
        </View>
      )}
    </>
  );
}
