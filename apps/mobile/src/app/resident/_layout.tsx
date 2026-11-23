import { Tabs } from "expo-router";
import { ChatCircleDots, ForkKnife, House, User, Wallet } from "phosphor-react-native";
import { color } from "@/lib/theme";

export default function ResidentTabs() {
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
      <Tabs.Screen name="index" options={{ title: "Home", tabBarIcon: ({ color: c, focused }) => <House size={24} color={c as string} weight={focused ? "fill" : "regular"} /> }} />
      <Tabs.Screen name="pay" options={{ title: "Rent", tabBarIcon: ({ color: c, focused }) => <Wallet size={24} color={c as string} weight={focused ? "fill" : "regular"} /> }} />
      <Tabs.Screen name="food" options={{ title: "Food", tabBarIcon: ({ color: c, focused }) => <ForkKnife size={24} color={c as string} weight={focused ? "fill" : "regular"} /> }} />
      <Tabs.Screen name="help" options={{ title: "Help", tabBarIcon: ({ color: c, focused }) => <ChatCircleDots size={24} color={c as string} weight={focused ? "fill" : "regular"} /> }} />
      <Tabs.Screen name="me" options={{ title: "Me", tabBarIcon: ({ color: c, focused }) => <User size={24} color={c as string} weight={focused ? "fill" : "regular"} /> }} />
    </Tabs>
  );
}
