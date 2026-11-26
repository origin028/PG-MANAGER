/** DEMO MODE: one-tap sign-in as each role on the welcome screen. Deleted with the src/demo folder. */
import { Text, View } from "react-native";
import { Button } from "@/components/ui";
import { useSession } from "@/lib/session";
import { color, radius, space, type } from "@/lib/theme";
import { demoToken } from "./index";

export function DemoEntry() {
  const { signInWithTokens } = useSession();
  const go = (role: "owner" | "resident" | "kitchen") => {
    const t = demoToken(role);
    return signInWithTokens(t.access_token, t.refresh_token, role === "resident" ? "resident_mobile" : "admin_mobile");
  };
  return (
    <View style={{ gap: space(2.5), padding: space(4), borderRadius: radius.lg, backgroundColor: color.cream }}>
      <Text style={[type.label, { color: color.ink }]}>Try the demo</Text>
      <Text style={[type.small, { color: color.ink3 }]}>Sample PGs and residents. Nothing you change is saved.</Text>
      <View style={{ flexDirection: "row", gap: space(2) }}>
        <Button title="Owner" onPress={() => go("owner")} style={{ flex: 1 }} />
        <Button title="Resident" variant="secondary" onPress={() => go("resident")} style={{ flex: 1 }} />
        <Button title="Kitchen" variant="secondary" onPress={() => go("kitchen")} style={{ flex: 1 }} />
      </View>
    </View>
  );
}

/** DEMO MODE: shows the demo login on the sign-in screens and fills it in with one tap. */
export function DemoHint({ login, password, onUse }: { login: string; password: string; onUse: () => void }) {
  return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: space(3), padding: space(3.5), borderRadius: radius.md, backgroundColor: color.cream, marginBottom: space(4) }}>
      <View style={{ flex: 1 }}>
        <Text style={[type.label, { color: color.ink }]}>Demo login</Text>
        <Text style={[type.small, { color: color.ink3 }]}>{login} / {password}</Text>
      </View>
      <Button title="Use it" variant="secondary" onPress={onUse} />
    </View>
  );
}
