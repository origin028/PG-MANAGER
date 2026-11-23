import { Tabs } from "expo-router";
import { ChartBar, ForkKnife, Scan } from "phosphor-react-native";
import { color } from "@/lib/theme";

function icon(I: typeof Scan) {
  function TabIcon({ color: c, focused }: { color: unknown; focused: boolean }) {
    return <I size={24} color={c as string} weight={focused ? "fill" : "regular"} />;
  }
  return TabIcon;
}

export default function KitchenTabs() {
  return (
    <Tabs screenOptions={{
      headerShown: false,
      tabBarActiveTintColor: color.ink,
      tabBarInactiveTintColor: color.ink3,
      tabBarStyle: { backgroundColor: color.card, borderTopColor: color.line, height: 84, paddingTop: 8 },
      tabBarLabelStyle: { fontSize: 11, fontWeight: "600" },
      sceneStyle: { backgroundColor: color.bg },
    }}>
      <Tabs.Screen name="index" options={{ title: "Scan", tabBarIcon: icon(Scan) }} />
      <Tabs.Screen name="today" options={{ title: "Today", tabBarIcon: icon(ChartBar) }} />
      <Tabs.Screen name="menu" options={{ title: "Menu", tabBarIcon: icon(ForkKnife) }} />
    </Tabs>
  );
}
