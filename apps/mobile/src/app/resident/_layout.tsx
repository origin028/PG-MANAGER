import { Tabs } from "expo-router";
import { ChatCircleDots, ForkKnife, House, User, Wallet } from "phosphor-react-native";
import { tabBarBase, tabIcon } from "@/components/tab-icon";
import { useWide } from "@/lib/layout";
import { color } from "@/lib/theme";

export default function ResidentTabs() {
  const wide = useWide();
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: color.ink,
        tabBarInactiveTintColor: color.ink3,
        tabBarStyle: wide ? { display: "none" } : tabBarBase,
        tabBarLabelStyle: { fontSize: 11, fontWeight: "600" },
        sceneStyle: { backgroundColor: color.bg },
        animation: "shift",
      }}
    >
      <Tabs.Screen name="index" options={{ title: "Home", tabBarIcon: tabIcon(House) }} />
      <Tabs.Screen name="pay" options={{ title: "Rent", tabBarIcon: tabIcon(Wallet) }} />
      <Tabs.Screen name="food" options={{ title: "Food", tabBarIcon: tabIcon(ForkKnife) }} />
      <Tabs.Screen name="help" options={{ title: "Help", tabBarIcon: tabIcon(ChatCircleDots) }} />
      <Tabs.Screen name="me" options={{ title: "Me", tabBarIcon: tabIcon(User) }} />
    </Tabs>
  );
}
