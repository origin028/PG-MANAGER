import { Stack, useRouter, useSegments } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { useEffect } from "react";
import { ActivityIndicator, View } from "react-native";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { SessionProvider, useSession } from "@/lib/session";
import { color } from "@/lib/theme";

/** Sends people to the right place: signed-out -> welcome, resident -> resident tabs, owner -> owner tabs. */
function Gate() {
  const { ready, mode } = useSession();
  const segments = useSegments();
  const router = useRouter();

  useEffect(() => {
    if (!ready) return;
    const area = segments[0] ?? "";
    // Screens each mode may visit; anything else redirects to that mode's home.
    const allowed: Record<string, string[]> = {
      resident: ["resident", "new-complaint"],
      owner: ["owner", "approve", "announce"],
    };
    if (!mode) { if (area !== "(auth)") router.replace("/welcome"); }
    else if (!allowed[mode].includes(area)) router.replace(mode === "resident" ? "/resident" : "/owner");
  }, [ready, mode, segments, router]);

  if (!ready) {
    return (
      <View style={{ flex: 1, alignItems: "center", justifyContent: "center", backgroundColor: color.bg }}>
        <ActivityIndicator color={color.ink} />
      </View>
    );
  }
  return (
    <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: color.bg }, animation: "fade" }}>
      <Stack.Screen name="new-complaint" options={{ presentation: "modal", animation: "slide_from_bottom" }} />
      <Stack.Screen name="approve/[id]" options={{ presentation: "modal", animation: "slide_from_bottom" }} />
      <Stack.Screen name="announce" options={{ presentation: "modal", animation: "slide_from_bottom" }} />
    </Stack>
  );
}

export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <SessionProvider>
        <StatusBar style="dark" />
        <Gate />
      </SessionProvider>
    </SafeAreaProvider>
  );
}
