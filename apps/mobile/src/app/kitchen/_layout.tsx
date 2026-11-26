import { Tabs } from "expo-router";
import { ChartBar, ForkKnife, Scan } from "phosphor-react-native";
import { tabBarBase, tabIcon } from "@/components/tab-icon";
import { useWide } from "@/lib/layout";
import { color } from "@/lib/theme";

const icon = tabIcon;

export default function KitchenTabs() {
  const wide = useWide();
  return (
    <Tabs screenOptions={{
      headerShown: false,
      tabBarActiveTintColor: color.ink,
      tabBarInactiveTintColor: color.ink3,
      tabBarStyle: wide ? { display: "none" } : tabBarBase,
      tabBarLabelStyle: { fontSize: 11, fontWeight: "600" },
      sceneStyle: { backgroundColor: color.bg },
      animation: "shift",
    }}>
      <Tabs.Screen name="index" options={{ title: "Scan", tabBarIcon: icon(Scan) }} />
      <Tabs.Screen name="today" options={{ title: "Today", tabBarIcon: icon(ChartBar) }} />
      <Tabs.Screen name="menu" options={{ title: "Menu", tabBarIcon: icon(ForkKnife) }} />
    </Tabs>
  );
}
