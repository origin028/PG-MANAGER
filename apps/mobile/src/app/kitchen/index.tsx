import { CameraView, useCameraPermissions } from "expo-camera";
import * as Haptics from "expo-haptics";
import { useRef, useState } from "react";
import { Platform, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { CheckCircle, Prohibit, Scan as ScanIcon } from "phosphor-react-native";
import { Body, Button } from "@/components/ui";
import { api } from "@/lib/api";
import { color, radius, space, type } from "@/lib/theme";

type Result = { ok: boolean; status: string; message: string; meal?: string | null; resident?: { name?: string; room?: string; bed?: string } | null };

/** Kitchen scanner: point at a resident's meal pass; green means serve, red shows why not. */
export default function KitchenScan() {
  const [permission, requestPermission] = useCameraPermissions();
  const [result, setResult] = useState<Result | null>(null);
  const busy = useRef(false);
  const lastToken = useRef<string>("");

  async function onScan(data: string) {
    if (busy.current || result || data === lastToken.current) return;
    busy.current = true;
    lastToken.current = data;
    try {
      const r = await api<Result>("/kitchen/scan", { method: "POST", json: { token: data } });
      setResult(r);
      if (Platform.OS !== "web") Haptics.notificationAsync(r.ok ? Haptics.NotificationFeedbackType.Success : Haptics.NotificationFeedbackType.Error).catch(() => {});
    } catch (e) {
      setResult({ ok: false, status: "ERROR", message: (e as Error).message });
    } finally {
      busy.current = false;
      setTimeout(() => { setResult(null); lastToken.current = ""; }, 2600);
    }
  }

  if (!permission) return <View style={{ flex: 1, backgroundColor: color.ink }} />;
  if (!permission.granted) {
    return (
      <SafeAreaView style={{ flex: 1, backgroundColor: color.bg, alignItems: "center", justifyContent: "center", padding: space(8), gap: space(4) }}>
        <ScanIcon size={52} color={color.ink} weight="light" />
        <Text style={[type.h2, { color: color.ink, textAlign: "center" }]}>Allow the camera to scan meal passes</Text>
        <Button title="Allow camera" onPress={requestPermission} style={{ alignSelf: "stretch" }} />
      </SafeAreaView>
    );
  }

  return (
    <View style={{ flex: 1, backgroundColor: "#000" }}>
      <CameraView style={StyleSheet.absoluteFill} facing="back" barcodeScannerSettings={{ barcodeTypes: ["qr"] }} onBarcodeScanned={({ data }) => onScan(data)} />
      <SafeAreaView style={{ flex: 1, justifyContent: "space-between", padding: space(5) }} pointerEvents="box-none">
        <View style={{ alignSelf: "center", backgroundColor: "rgba(0,0,0,0.55)", borderRadius: radius.pill, paddingHorizontal: space(4), paddingVertical: space(2) }}>
          <Text style={[type.label, { color: "#fff" }]}>Scan a resident's meal pass</Text>
        </View>
        <View style={{ alignSelf: "center", width: 250, height: 250, borderRadius: radius.lg, borderWidth: 3, borderColor: "rgba(255,255,255,0.9)" }} />
        <View style={{ height: 40 }} />
      </SafeAreaView>
      {result ? (
        <View style={[StyleSheet.absoluteFill, { backgroundColor: result.ok ? color.ok : color.bad, alignItems: "center", justifyContent: "center", padding: space(8), gap: space(3) }]}>
          {result.ok ? <CheckCircle size={96} color="#fff" weight="fill" /> : <Prohibit size={96} color="#fff" weight="bold" />}
          <Text style={{ fontSize: 34, fontWeight: "800", color: "#fff", textAlign: "center", letterSpacing: -0.8 }}>{result.ok ? "Serve" : "Don't serve"}</Text>
          {result.resident?.name ? <Text style={[type.h2, { color: "#fff", textAlign: "center" }]}>{result.resident.name}</Text> : null}
          {result.resident?.room ? <Body style={{ color: "#ffffffdd" }}>Room {result.resident.room}{result.resident.bed ? ` · Bed ${result.resident.bed}` : ""}</Body> : null}
          <Body style={{ color: "#ffffffee", textAlign: "center", marginTop: space(2) }}>{result.message}</Body>
        </View>
      ) : null}
    </View>
  );
}
