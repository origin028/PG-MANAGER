import { Image } from "expo-image";
import { router } from "expo-router";
import { useState } from "react";
import { Pressable, Text, View } from "react-native";
import { Camera, X } from "phosphor-react-native";
import { Button, ErrorBox, Field, Screen, Segmented, tap } from "@/components/ui";
import { api } from "@/lib/api";
import { appendFile, pickImage, type Picked } from "@/lib/upload";
import { color, radius, space, type } from "@/lib/theme";

const CATS = ["CLEANING", "ELECTRICAL", "PLUMBING", "WIFI", "FOOD", "CARPENTRY", "OTHER"];

export default function NewComplaint() {
  const [category, setCategory] = useState("CLEANING");
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [photo, setPhoto] = useState<Picked | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setBusy(true); setError(null);
    try {
      let photo_path: string | undefined;
      if (photo) {
        const form = new FormData();
        await appendFile(form, "photo", photo);
        photo_path = (await api<{ photo_path: string }>("/resident/complaints/upload-photo", { method: "POST", body: form })).photo_path;
      }
      await api("/resident/complaints", { method: "POST", json: { category, title: title.trim(), description: description.trim() || title.trim(), photo_path } });
      router.back();
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  return (
    <Screen>
      <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginTop: space(4), marginBottom: space(5) }}>
        <Text style={[type.h1, { color: color.ink }]}>Report an issue</Text>
        <Pressable onPress={() => router.back()} hitSlop={12} accessibilityLabel="Close"><X size={26} color={color.ink} /></Pressable>
      </View>
      <Text style={[type.label, { color: color.ink, marginBottom: space(2) }]}>What kind of issue?</Text>
      <Segmented value={category} onChange={setCategory} options={CATS.map((c) => ({ value: c, label: c === "WIFI" ? "Wi-Fi" : c.charAt(0) + c.slice(1).toLowerCase() }))} />
      <View style={{ height: space(4) }} />
      <Field label="Short title" value={title} onChangeText={setTitle} placeholder="Bathroom tap leaking" maxLength={120} />
      <Field label="Details (optional)" value={description} onChangeText={setDescription} multiline placeholder="Where is it and since when?" />
      <Pressable onPress={async () => { tap(); try { const p = await pickImage("camera"); if (p) setPhoto(p); } catch (e) { setError((e as Error).message); } }}
        style={{ height: 150, borderRadius: radius.md, borderWidth: 1, borderStyle: photo ? "solid" : "dashed", borderColor: color.line, backgroundColor: color.card, overflow: "hidden", alignItems: "center", justifyContent: "center", marginBottom: space(4) }}>
        {photo ? <Image source={photo.uri} style={{ width: "100%", height: "100%" }} contentFit="cover" /> : (
          <View style={{ alignItems: "center", gap: space(2) }}>
            <Camera size={28} color={color.ink} weight="light" />
            <Text style={[type.label, { color: color.ink }]}>Add a photo</Text>
          </View>
        )}
      </Pressable>
      {error ? <ErrorBox message={error} /> : null}
      <Button title="Send to housekeeping" onPress={submit} loading={busy} disabled={title.trim().length < 3} style={{ marginTop: space(2) }} />
    </Screen>
  );
}
