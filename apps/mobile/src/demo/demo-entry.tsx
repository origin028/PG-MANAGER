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
