import { router } from "expo-router";
import { useEffect, useState } from "react";
import { Pressable, Text, View } from "react-native";
import QRCode from "react-native-qrcode-svg";
import { CheckCircle, Clock, X } from "phosphor-react-native";
import { Body, ErrorBox, Screen, Skeleton } from "@/components/ui";
import { api } from "@/lib/api";
import { color, radius, space, type } from "@/lib/theme";

type Pass = { meal: string | null; token?: string; expires_in?: number; served_at?: string | null; next?: { meal: string; starts_at: string } | null };
const nice = (m?: string | null) => (m ? m.charAt(0) + m.slice(1).toLowerCase() : "");
const clock = (iso: string) => new Date(iso).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit" });

/**
 * Resident meal pass. The QR is signed by the server, valid only for the meal being served now,
 * and refreshed every minute, so a screenshot shared with someone else stops working.
 */
export default function MealPass() {
  const [pass, setPass] = useState<Pass | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [left, setLeft] = useState(0);

  useEffect(() => {
    let alive = true;
    let timer: ReturnType<typeof setTimeout>;
    const load = () => {
      api<Pass>("/resident/meal-pass")
        .then((p) => {
          if (!alive) return;
          setPass(p); setError(null); setLeft(p.expires_in ?? 0);
          // Refresh 30s before expiry; if no meal now, check again in a minute.
          timer = setTimeout(load, p.token ? Math.max(10, (p.expires_in ?? 90) - 30) * 1000 : 60_000);
        })
        .catch((e) => { if (alive) { setError((e as Error).message); timer = setTimeout(load, 15_000); } });
    };
    load();
    const tick = setInterval(() => setLeft((s) => Math.max(0, s - 1)), 1000);
    return () => { alive = false; clearTimeout(timer); clearInterval(tick); };
  }, []);

  return (
    <Screen>
      <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginTop: space(4) }}>
        <Text style={[type.h1, { color: color.ink }]}>Meal pass</Text>
        <Pressable onPress={() => router.back()} hitSlop={12} accessibilityLabel="Close"><X size={26} color={color.ink} /></Pressable>
      </View>
      {error ? <View style={{ marginTop: space(5) }}><ErrorBox message={error} /></View> : null}
      {!pass ? (
        <View style={{ alignItems: "center", marginTop: space(10) }}><Skeleton w={260} h={260} r={radius.lg} /></View>
      ) : pass.meal && pass.token ? (
        <View style={{ alignItems: "center", marginTop: space(8), gap: space(5) }}>
          <Text style={[type.hero, { color: color.ink }]}>{nice(pass.meal)}</Text>
          {pass.served_at ? (
            <View style={{ alignItems: "center", gap: space(3), paddingVertical: space(10) }}>
              <CheckCircle size={72} color={color.ok} weight="fill" />
              <Text style={[type.h2, { color: color.ink }]}>Served at {clock(pass.served_at)}</Text>
              <Body muted>Enjoy your meal.</Body>
            </View>
          ) : (
            <>
              <View style={{ padding: space(5), backgroundColor: "#ffffff", borderRadius: radius.lg, shadowColor: "#000", shadowOpacity: 0.08, shadowRadius: 20, shadowOffset: { width: 0, height: 8 } }}>
                <QRCode value={pass.token} size={250} color="#000000" backgroundColor="#ffffff" ecl="M" />
              </View>
              <Body muted style={{ textAlign: "center" }}>Show this to the kitchen. It refreshes automatically{left ? ` (${left}s)` : ""}.</Body>
            </>
          )}
        </View>
      ) : (
        <View style={{ alignItems: "center", marginTop: space(16), gap: space(3) }}>
          <Clock size={56} color={color.ink} weight="light" />
          <Text style={[type.h2, { color: color.ink }]}>No meal being served</Text>
          <Body muted style={{ textAlign: "center" }}>{pass.next ? `${nice(pass.next.meal)} starts at ${clock(pass.next.starts_at)}.` : "Kitchen is closed for today."}</Body>
        </View>
      )}
    </Screen>
  );
}
