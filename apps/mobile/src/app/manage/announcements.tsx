import { useState } from "react";
import { Pressable, Text, View } from "react-native";
import { Megaphone, Plus } from "phosphor-react-native";
import { Header, SmallButton, confirmAction } from "@/components/kit";
import { Badge, Body, Button, Card, Empty, ErrorBox, Field, LoadingCards, Screen, Segmented } from "@/components/ui";
import { api } from "@/lib/api";
import { fmtDate } from "@/lib/dates";
import { useProperties } from "@/lib/owner";
import { color, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type A = { id: string; title: string; content: string; is_active: boolean; property_id?: string | null; property_name?: string | null; created_at: string };
type Form = { id?: string; title: string; content: string; target: string };

export default function Announcements() {
  const { props } = useProperties();
  const list = useData<A[]>("/announcements");
  const [f, setF] = useState<Form | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function run(fn: () => Promise<unknown>) {
    setBusy(true); setError(null);
    try { await fn(); setF(null); list.reload(); } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  const save = () => f && run(() => api(f.id ? `/announcements/${f.id}` : "/announcements", { method: f.id ? "PUT" : "POST", json: { title: f.title.trim(), content: f.content.trim(), property_id: f.target === "all" ? null : f.target, is_active: true } }));
  const toggle = (a: A) => run(() => api(`/announcements/${a.id}/status`, { method: "PATCH", json: { is_active: !a.is_active } }));
  const remove = (a: A) => confirmAction("Delete announcement?", a.title, "Delete", () => run(() => api(`/announcements/${a.id}`, { method: "DELETE" })));

  return (
    <Screen onRefresh={list.reload} refreshing={list.refreshing}>
      <Header title="Announcements" sub="Shown on residents' home screen." action={!f ? <SmallButton label="New" icon={<Plus size={16} color={color.bg} weight="bold" />} onPress={() => setF({ title: "", content: "", target: "all" })} /> : undefined} />
      {error ? <View style={{ marginBottom: space(3) }}><ErrorBox message={error} /></View> : null}
      {f ? (
        <Card style={{ marginBottom: space(4) }}>
          <Text style={[type.label, { color: color.ink, marginBottom: space(2) }]}>Send to</Text>
          <Segmented value={f.target} onChange={(v) => setF({ ...f, target: v })} options={[{ value: "all", label: "All homes" }, ...props.map((p) => ({ value: p.id, label: p.name }))]} />
          <View style={{ height: space(4) }} />
          <Field label="Title" value={f.title} onChangeText={(t) => setF({ ...f, title: t })} placeholder="Water supply off on Sunday" />
          <Field label="Message" value={f.content} onChangeText={(t) => setF({ ...f, content: t })} multiline />
          <Button title={f.id ? "Save" : "Post"} onPress={save} loading={busy} disabled={f.title.trim().length < 3 || f.content.trim().length < 3} />
          <Button title="Cancel" variant="ghost" onPress={() => setF(null)} />
        </Card>
      ) : null}
      {list.loading ? <LoadingCards n={2} /> : list.data?.length ? (
        <View style={{ gap: space(3) }}>
          {list.data.map((a) => (
            <Card key={a.id} style={{ gap: space(2), opacity: a.is_active ? 1 : 0.6 }}>
              <View style={{ flexDirection: "row", justifyContent: "space-between", gap: space(3) }}>
                <Text style={[type.label, { color: color.ink, fontSize: 16, flex: 1 }]}>{a.title}</Text>
                <Badge label={a.is_active ? "Live" : "Paused"} tone={a.is_active ? "ok" : "neutral"} />
              </View>
              <Body>{a.content}</Body>
              <Body muted>{a.property_name ?? "All homes"} · {fmtDate(a.created_at)}</Body>
              <View style={{ flexDirection: "row", gap: space(5), marginTop: space(2) }}>
                <Pressable onPress={() => setF({ id: a.id, title: a.title, content: a.content, target: a.property_id ?? "all" })}><Text style={[type.label, { color: color.ink }]}>Edit</Text></Pressable>
                <Pressable onPress={() => toggle(a)}><Text style={[type.label, { color: color.ink }]}>{a.is_active ? "Pause" : "Resume"}</Text></Pressable>
                <Pressable onPress={() => remove(a)}><Text style={[type.label, { color: color.bad }]}>Delete</Text></Pressable>
              </View>
            </Card>
          ))}
        </View>
      ) : <Empty icon={<Megaphone size={44} color={color.ink} weight="light" />} title="No announcements" />}
    </Screen>
  );
}
