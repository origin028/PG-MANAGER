import * as LocalAuthentication from "expo-local-authentication";
import { Tabs } from "expo-router";
import { useCallback, useEffect, useState } from "react";
import { AppState, Platform, Text, View } from "react-native";
import { Bed, DotsThreeOutline, House, LockSimple, Users, Wallet } from "phosphor-react-native";
import { tabBarBase, tabIcon } from "@/components/tab-icon";
import { Button } from "@/components/ui";
import { api } from "@/lib/api";
import { useWide } from "@/lib/layout";
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

const icon = tabIcon;

/** Small counts for the tab bar badges; refreshed every minute and when the app comes back. */
function useTabCounts() {
  const [n, setN] = useState({ signups: 0 });
  useEffect(() => {
    let alive = true;
    const load = () => api<{ items?: unknown[] } | unknown[]>("/residents/pending-approvals")
      .then((d) => { if (alive) setN({ signups: (Array.isArray(d) ? d : d.items ?? []).length }); }).catch(() => {});
    load();
    const t = setInterval(load, 60_000);
    const sub = AppState.addEventListener("change", (st) => { if (st === "active") load(); });
    return () => { alive = false; clearInterval(t); sub.remove(); };
  }, []);
  return n;
}

export default function OwnerTabs() {
  const { locked, unlock } = useBiometricLock();
  const wide = useWide();
  const counts = useTabCounts();
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
        tabBarStyle: wide ? { display: "none" } : tabBarBase,
        tabBarBadgeStyle: { backgroundColor: color.bad, fontSize: 10, fontWeight: "700" },
        tabBarLabelStyle: { fontSize: 11, fontWeight: "600" },
        sceneStyle: { backgroundColor: color.bg },
        animation: "shift",
      }}
    >
      <Tabs.Screen name="index" options={{ title: "Home", tabBarIcon: icon(House) }} />
      <Tabs.Screen name="residents" options={{ title: "Residents", tabBarIcon: icon(Users), tabBarBadge: counts.signups || undefined }} />
      <Tabs.Screen name="rooms" options={{ title: "Rooms", tabBarIcon: icon(Bed) }} />
      <Tabs.Screen name="money" options={{ title: "Money", tabBarIcon: icon(Wallet) }} />
      <Tabs.Screen name="more" options={{ title: "More", tabBarIcon: icon(DotsThreeOutline) }} />
    </Tabs>
  );
}
