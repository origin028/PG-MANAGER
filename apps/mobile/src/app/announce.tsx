import { router } from "expo-router";
import { useState } from "react";
import { Pressable, Text, View } from "react-native";
import { X } from "phosphor-react-native";
import { Body, Button, ErrorBox, Field, Screen, Segmented } from "@/components/ui";
import { api } from "@/lib/api";
import { useProperties } from "@/lib/owner";
import { color, space, type } from "@/lib/theme";

export default function Announce() {
  const { props } = useProperties();
  const [target, setTarget] = useState<string>("all");
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function send() {
    setBusy(true); setError(null);
    try {
      await api("/announcements", { method: "POST", json: { title: title.trim(), content: content.trim(), property_id: target === "all" ? null : target } });
      router.back();
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  return (
    <Screen>
      <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginTop: space(4), marginBottom: space(5) }}>
        <Text style={[type.h1, { color: color.ink }]}>Announcement</Text>
        <Pressable onPress={() => router.back()} hitSlop={12} accessibilityLabel="Close"><X size={26} color={color.ink} /></Pressable>
      </View>
      <Text style={[type.label, { color: color.ink, marginBottom: space(2) }]}>Send to</Text>
      <Segmented value={target} onChange={setTarget} options={[{ value: "all", label: "All homes" }, ...props.map((p) => ({ value: p.id, label: p.name }))]} />
      <View style={{ height: space(4) }} />
      <Field label="Title" value={title} onChangeText={setTitle} placeholder="Water supply off on Sunday" maxLength={200} />
      <Field label="Message" value={content} onChangeText={setContent} multiline placeholder="From 10am to 1pm for tank cleaning." />
      <Body muted style={{ marginBottom: space(4) }}>Residents see this on their home screen.</Body>
      {error ? <ErrorBox message={error} /> : null}
      <Button title="Send to residents" onPress={send} loading={busy} disabled={title.trim().length < 3 || content.trim().length < 3} />
    </Screen>
  );
}
