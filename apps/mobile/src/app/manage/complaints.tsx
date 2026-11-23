import { useFocusEffect } from "expo-router";
import { useCallback, useState } from "react";
import { Text, View } from "react-native";
import { Wrench } from "phosphor-react-native";
import { Badge, Body, Button, Card, Empty, ErrorBox, Field, LoadingCards, Screen, Segmented, pretty, statusTone } from "@/components/ui";
import { Header } from "@/components/kit";
import { api } from "@/lib/api";
import { fmtDate } from "@/lib/dates";
import { listOf } from "@/lib/owner";
import { color, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type StaffM = { id: string; name: string; role: string; is_active: boolean };
type Complaint = { assigned_staff_name?: string; id: string; title: string; description?: string; category: string; status: string; priority?: string; created_at: string; resident_name?: string; room_number?: string };
const OPEN = ["OPEN", "IN_PROGRESS", "ASSIGNED", "PENDING"];

export default function Issues() {
  const { data, error, loading, refreshing, reload } = useData<Complaint[]>("/complaints?page_size=100");
  useFocusEffect(useCallback(() => { reload(); }, [reload]));
  const [tab, setTab] = useState<"open" | "done">("open");
  const [open, setOpen] = useState<string | null>(null);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const staff = useData<StaffM[]>("/staff");
  const [assigning, setAssigning] = useState<string | null>(null);

  async function assign(c: Complaint, staffId: string) {
    setBusy(true); setErr(null);
    try { await api(`/complaints/${c.id}/assign`, { method: "POST", json: { assigned_staff_id: staffId } }); setAssigning(null); reload(); }
    catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  }

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
      <Header title="Complaints" sub="Issues residents raised in the app." />
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
              {c.assigned_staff_name ? <Body>Assigned to {c.assigned_staff_name}</Body> : null}
              {tab === "open" && assigning === c.id ? (
                (staff.data ?? []).filter((s) => s.is_active).length ? (
                  <Segmented value="" onChange={(v) => assign(c, v)} options={(staff.data ?? []).filter((s) => s.is_active).map((s) => ({ value: s.id, label: `${s.name} · ${pretty(s.role)}` }))} />
                ) : <Body muted>Add staff in More › Staff first.</Body>
              ) : null}
              {tab === "open" && assigning !== c.id && open !== c.id ? <Button title={c.assigned_staff_name ? "Reassign" : "Assign to staff"} variant="ghost" onPress={() => setAssigning(c.id)} /> : null}
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
