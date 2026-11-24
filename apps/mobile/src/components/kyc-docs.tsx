/** ID photo picker shared by "Join a home" and "Finish your KYC". */
import { Image } from "expo-image";
import { Alert, Platform, Pressable, Text, View } from "react-native";
import { Camera, CheckCircle } from "phosphor-react-native";
import { Segmented, tap } from "@/components/ui";
import { appendFile, pickImage, type Picked } from "@/lib/upload";
import { color, radius, space, type } from "@/lib/theme";

export type DocKey = "aadhaar_front_file" | "aadhaar_back_file" | "pan_card_file" | "passport_file" | "resident_selfie_file";
export type Docs = Partial<Record<DocKey, Picked>>;
export type Method = "Aadhaar + PAN" | "Passport Only";

export const DOC_LABEL: Record<DocKey, string> = {
  aadhaar_front_file: "Aadhaar front",
  aadhaar_back_file: "Aadhaar back",
  pan_card_file: "PAN card",
  passport_file: "Passport photo page",
  resident_selfie_file: "Your selfie",
};

export const neededDocs = (m: Method): DocKey[] =>
  m === "Aadhaar + PAN" ? ["aadhaar_front_file", "aadhaar_back_file", "pan_card_file", "resident_selfie_file"] : ["passport_file", "resident_selfie_file"];

export async function appendDocs(form: FormData, method: Method, docs: Docs) {
  for (const k of neededDocs(method)) await appendFile(form, k, docs[k]!);
}

export function KycDocPicker({ method, onMethod, docs, onDocs, onError }: {
  method: Method; onMethod: (m: Method) => void; docs: Docs; onDocs: (d: Docs) => void; onError: (msg: string) => void;
}) {
  async function choose(key: DocKey) {
    const go = async (src: "camera" | "library") => {
      try {
        const p = await pickImage(src, key === "resident_selfie_file");
        if (p) onDocs({ ...docs, [key]: p });
      } catch (e) { onError((e as Error).message); }
    };
    if (Platform.OS === "web") return go("library");
    Alert.alert(DOC_LABEL[key], undefined, [
      { text: "Take photo", onPress: () => go("camera") },
      { text: "Choose from photos", onPress: () => go("library") },
      { text: "Cancel", style: "cancel" },
    ]);
  }

  return (
    <>
      <Segmented value={method} onChange={(v) => { onMethod(v); onDocs({}); }} options={[{ value: "Aadhaar + PAN", label: "Aadhaar + PAN" }, { value: "Passport Only", label: "Passport" }]} />
      <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space(3), marginTop: space(5) }}>
        {neededDocs(method).map((k) => (
          <Pressable key={k} onPress={() => { tap(); choose(k); }} accessibilityLabel={DOC_LABEL[k]}
            style={{ width: "47.5%", aspectRatio: 1.25, borderRadius: radius.md, overflow: "hidden", backgroundColor: color.card, borderWidth: 1, borderColor: docs[k] ? color.ink : color.line, borderStyle: docs[k] ? "solid" : "dashed" }}>
            {docs[k] ? (
              <>
                <Image source={docs[k]!.uri} style={{ flex: 1 }} contentFit="cover" />
                <View style={{ position: "absolute", top: 8, right: 8, backgroundColor: color.card, borderRadius: 99 }}><CheckCircle size={24} weight="fill" color={color.ok} /></View>
              </>
            ) : (
              <View style={{ flex: 1, alignItems: "center", justifyContent: "center", gap: space(2) }}>
                <Camera size={26} color={color.ink} weight="light" />
                <Text style={[type.label, { color: color.ink }]}>{DOC_LABEL[k]}</Text>
              </View>
            )}
          </Pressable>
        ))}
      </View>
    </>
  );
}
