import { useFocusEffect } from "expo-router";
import { useCallback, useState } from "react";
import { Text, View } from "react-native";
import { Wrench } from "phosphor-react-native";
import { Badge, Body, Button, Card, Empty, ErrorBox, Field, LoadingCards, Screen, Segmented, Title, pretty, statusTone } from "@/components/ui";
import { api } from "@/lib/api";
import { fmtDate } from "@/lib/dates";
import { listOf } from "@/lib/owner";
import { color, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Complaint = { id: string; title: string; description?: string; category: string; status: string; priority?: string; created_at: string; resident_name?: string; room_number?: string };
const OPEN = ["OPEN", "IN_PROGRESS", "ASSIGNED", "PENDING"];

export default function Issues() {
  const { data, error, loading, refreshing, reload } = useData<Complaint[]>("/complaints?page_size=100");
  useFocusEffect(useCallback(() => { reload(); }, [reload]));
  const [tab, setTab] = useState<"open" | "done">("open");
  const [open, setOpen] = useState<string | null>(null);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const all = listOf<Complaint>(data as never);
  const shown = all.filter((c) => (tab === "open") === OPEN.includes((c.status ?? "").toUpperCase()));

  async function resolve(c: Complaint) {
    setBusy(true); setErr(null);
    try {
      await api(`/complaints/${c.id}/resolve`, { method: "POST", json: { resolution_notes: note.trim(), status: "RESOLVED" } });
      setOpen(null); setNote(""); reload();
    } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  }

  return (
    <Screen onRefresh={reload} refreshing={refreshing}>
      <Title sub="Issues residents raised in the app.">Issues</Title>
      <Segmented value={tab} onChange={setTab} options={[{ value: "open", label: "Open" }, { value: "done", label: "Resolved" }]} />
      <View style={{ height: space(4) }} />
      {loading ? <LoadingCards n={2} /> : error ? <ErrorBox message={error} onRetry={reload} /> : shown.length ? (
        <View style={{ gap: space(3) }}>
          {shown.map((c) => (
            <Card key={c.id} style={{ gap: space(2) }}>
              <View style={{ flexDirection: "row", justifyContent: "space-between", gap: space(3) }}>
                <Text style={[type.label, { color: color.ink, fontSize: 16, flex: 1 }]}>{c.title}</Text>
                <Badge label={pretty(c.status)} tone={statusTone(c.status)} />
              </View>
              {c.description && c.description !== c.title ? <Body>{c.description}</Body> : null}
              <Body muted>{pretty(c.category)}{c.resident_name ? ` · ${c.resident_name}` : ""}{c.room_number ? ` · Room ${c.room_number}` : ""} · {fmtDate(c.created_at)}</Body>
              {tab === "open" ? (open === c.id ? (
                <>
                  <Field label="What was done?" value={note} onChangeText={setNote} placeholder="Tap replaced" />
                  {err ? <ErrorBox message={err} /> : null}
                  <Button title="Mark resolved" onPress={() => resolve(c)} loading={busy} disabled={note.trim().length < 3} />
                </>
              ) : <Button title="Resolve" variant="secondary" onPress={() => { setOpen(c.id); setNote(""); setErr(null); }} />) : null}
            </Card>
          ))}
        </View>
      ) : <Empty icon={<Wrench size={44} color={color.ink} weight="light" />} title={tab === "open" ? "No open issues" : "Nothing resolved yet"} />}
    </Screen>
  );
}
