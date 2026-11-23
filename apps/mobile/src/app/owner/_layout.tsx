import * as LocalAuthentication from "expo-local-authentication";
import { Tabs } from "expo-router";
import { useCallback, useEffect, useState } from "react";
import { AppState, Platform, Text, View } from "react-native";
import { ChatCircleDots, DotsThreeOutline, House, LockSimple, UserCheck, Wallet } from "phosphor-react-native";
import { Button } from "@/components/ui";
import { color, space, type } from "@/lib/theme";

/** Face ID / fingerprint lock: the owner's phone holds every resident's data. Re-locks after backgrounding. */
async function authenticate(): Promise<boolean> {
  const available = (await LocalAuthentication.hasHardwareAsync()) && (await LocalAuthentication.isEnrolledAsync());
  if (!available) return true; // no biometrics on this phone: the signed-in session is the protection
  return (await LocalAuthentication.authenticateAsync({ promptMessage: "Unlock Origin Living" })).success;
}

function useBiometricLock() {
  const [locked, setLocked] = useState(Platform.OS !== "web");
  const unlock = useCallback(() => {
    authenticate().then((ok) => { if (ok) setLocked(false); });
  }, []);
  useEffect(() => {
    if (Platform.OS === "web") return;
    let alive = true;
    authenticate().then((ok) => { if (alive && ok) setLocked(false); });
    const sub = AppState.addEventListener("change", (st) => { if (st === "background") setLocked(true); });
    return () => { alive = false; sub.remove(); };
  }, []);
  return { locked, unlock };
}

function icon(I: typeof House) {
  function TabIcon({ color: c, focused }: { color: unknown; focused: boolean }) {
    return <I size={24} color={c as string} weight={focused ? "fill" : "regular"} />;
  }
  return TabIcon;
}

export default function OwnerTabs() {
  const { locked, unlock } = useBiometricLock();
  if (locked) {
    return (
      <View style={{ flex: 1, alignItems: "center", justifyContent: "center", gap: space(4), backgroundColor: color.bg, padding: space(8) }}>
        <LockSimple size={48} color={color.ink} weight="light" />
        <Text style={[type.h2, { color: color.ink }]}>Locked</Text>
        <Button title="Unlock" onPress={unlock} style={{ alignSelf: "stretch" }} />
      </View>
    );
  }
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: color.ink,
        tabBarInactiveTintColor: color.ink3,
        tabBarStyle: { backgroundColor: color.card, borderTopColor: color.line, height: 84, paddingTop: 8 },
        tabBarLabelStyle: { fontSize: 11, fontWeight: "600" },
        sceneStyle: { backgroundColor: color.bg },
      }}
    >
      <Tabs.Screen name="index" options={{ title: "Today", tabBarIcon: icon(House) }} />
      <Tabs.Screen name="approvals" options={{ title: "Approvals", tabBarIcon: icon(UserCheck) }} />
      <Tabs.Screen name="payments" options={{ title: "Payments", tabBarIcon: icon(Wallet) }} />
      <Tabs.Screen name="complaints" options={{ title: "Issues", tabBarIcon: icon(ChatCircleDots) }} />
      <Tabs.Screen name="more" options={{ title: "More", tabBarIcon: icon(DotsThreeOutline) }} />
    </Tabs>
  );
}
