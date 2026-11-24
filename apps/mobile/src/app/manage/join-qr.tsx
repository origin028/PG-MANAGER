import { useState } from "react";
import { Platform, Share, Text, View } from "react-native";
import QRCode from "react-native-qrcode-svg";
import { Copy, Printer, ShareNetwork } from "phosphor-react-native";
import { Header } from "@/components/kit";
import { Body, Button, Card, Screen, Segmented } from "@/components/ui";
import { APP_URL } from "@/lib/api";
import { useProperties } from "@/lib/owner";
import { color, radius, space, type } from "@/lib/theme";

/** A poster for each PG: new residents scan it, sign up and send their KYC; the owner gets an alert. */
export default function JoinQr() {
  const { props, current, setCurrent } = useProperties();
  const home = props.find((p) => p.id === current);
  const link = current ? `${APP_URL}/join?home=${current}` : "";
  const [copied, setCopied] = useState(false);

  async function share() {
    if (Platform.OS === "web" && typeof navigator !== "undefined" && navigator.clipboard) {
      await navigator.clipboard.writeText(link).catch(() => {});
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } else {
      Share.share({ message: `Join ${home?.name ?? "our PG"} on Origin Living: ${link}` }).catch(() => {});
    }
  }

  return (
    <Screen>
      <Header title="Join QR code" sub="Print it and stick it at the front desk. New residents scan, sign up and send their KYC. You get an alert." />
      {props.length > 1 ? <View style={{ marginBottom: space(4) }}><Segmented value={current ?? ""} onChange={setCurrent} options={props.map((p) => ({ value: p.id, label: p.name }))} /></View> : null}

      {current ? (
        <View nativeID="join-poster" style={{ backgroundColor: color.card, borderRadius: radius.lg, padding: space(8), alignItems: "center", gap: space(4), alignSelf: "center", width: "100%", maxWidth: 460 }}>
          <Text style={[type.small, { color: color.ink3, letterSpacing: 1.5, textTransform: "uppercase" }]}>Origin Living</Text>
          <Text style={{ fontSize: 34, fontWeight: "700", letterSpacing: -1.2, color: color.ink, textAlign: "center" }}>{home?.name ?? "Our PG"}</Text>
          <Body muted style={{ textAlign: "center" }}>Scan to join. Fill in your details and ID in two minutes, no paperwork.</Body>
          <View style={{ padding: space(4), backgroundColor: "#ffffff", borderRadius: radius.md, borderWidth: 1, borderColor: color.line }}>
            <QRCode value={link} size={240} color="#000000" backgroundColor="#ffffff" ecl="M" />
          </View>
          <View style={{ gap: space(1), alignItems: "center" }}>
            {["Scan with your phone camera", "Fill in your details and ID photos", "Verify your email and wait for approval"].map((t, i) => (
              <Body key={t} style={{ fontSize: 14 }}>{i + 1}. {t}</Body>
            ))}
          </View>
        </View>
      ) : null}

      <Card tone="cream" style={{ marginTop: space(4), gap: space(1) }}>
        <Text style={[type.label, { color: color.ink }]}>Link in the QR</Text>
        <Body style={{ fontSize: 13 }}>{link}</Body>
      </Card>
      <View style={{ flexDirection: "row", gap: space(3), marginTop: space(4) }}>
        {Platform.OS === "web" ? (
          <Button title="Print poster" icon={<Printer size={20} color={color.bg} />} onPress={() => window.print()} style={{ flex: 1 }} />
        ) : null}
        <Button title={copied ? "Link copied" : Platform.OS === "web" ? "Copy link" : "Share link"} variant="secondary"
          icon={Platform.OS === "web" ? <Copy size={20} color={color.ink} /> : <ShareNetwork size={20} color={color.ink} />} onPress={share} style={{ flex: 1 }} />
      </View>
      <Body muted style={{ marginTop: space(4), fontSize: 13, textAlign: "center" }}>Each PG has its own code, so sign-ups land in the right PG.</Body>
    </Screen>
  );
}
