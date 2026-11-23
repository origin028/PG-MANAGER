import { Stack, usePathname, useRouter } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { useEffect } from "react";
import { ActivityIndicator, View } from "react-native";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { WebShell } from "@/components/web-shell";
import { useWide } from "@/lib/layout";
import { SessionProvider, useSession } from "@/lib/session";
import { color } from "@/lib/theme";

/** Sends people to the right place: signed-out -> welcome, resident -> resident tabs, owner -> owner tabs. */
function Gate() {
  const { ready, mode } = useSession();
  const wide = useWide();
  const pathname = usePathname();
  const router = useRouter();

  useEffect(() => {
    if (!ready) return;
    // Paths each mode may visit; anything else redirects to that mode's home.
    const allowed: Record<string, string[]> = {
      signedOut: ["/welcome", "/resident-login", "/owner-login", "/join"],
      resident: ["/resident", "/new-complaint", "/meal-pass"],
      kitchen: ["/kitchen"],
      owner: ["/owner", "/approve", "/manage"],
    };
    const ok = (list: string[]) => list.some((p) => pathname === p || pathname.startsWith(`${p}/`));
    if (!mode) { if (!ok(allowed.signedOut)) router.replace("/welcome"); }
    else if (!ok(allowed[mode])) router.replace(mode === "resident" ? "/resident" : mode === "kitchen" ? "/kitchen" : "/owner");
  }, [ready, mode, pathname, router]);

  if (!ready) {
    return (
      <View style={{ flex: 1, alignItems: "center", justifyContent: "center", backgroundColor: color.bg }}>
        <ActivityIndicator color={color.ink} />
      </View>
    );
  }
  const stack = (
    <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: color.bg }, animation: "fade" }}>
      <Stack.Screen name="new-complaint" options={{ presentation: "modal", animation: "slide_from_bottom" }} />
      <Stack.Screen name="approve/[id]" options={{ presentation: "modal", animation: "slide_from_bottom" }} />
      <Stack.Screen name="meal-pass" options={{ presentation: "modal", animation: "slide_from_bottom" }} />

    </Stack>
  );
  // Desktop browsers get a sidebar dashboard; phones keep the app layout.
  return wide && mode ? <WebShell mode={mode}>{stack}</WebShell> : stack;
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
