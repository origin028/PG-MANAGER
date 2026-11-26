import { useEffect, useState, type ComponentType } from "react";
import { Animated, Platform, View } from "react-native";
import { color } from "@/lib/theme";

type IconC = ComponentType<{ size?: number; color?: string; weight?: "regular" | "fill" }>;

/** Tab bar icon that pops when selected and sits on a soft pill. */
export function tabIcon(I: IconC) {
  function TabIcon({ color: c, focused }: { color: unknown; focused: boolean }) {
    const [v] = useState(() => new Animated.Value(focused ? 1 : 0));
    useEffect(() => {
      Animated.spring(v, { toValue: focused ? 1 : 0, useNativeDriver: Platform.OS !== "web", speed: 18, bounciness: 14 }).start();
    }, [focused, v]);
    return (
      <View style={{ alignItems: "center", justifyContent: "center", width: 56, height: 30 }}>
        <Animated.View style={{ position: "absolute", width: 56, height: 30, borderRadius: 15, backgroundColor: color.cream, opacity: v, transform: [{ scaleX: v.interpolate({ inputRange: [0, 1], outputRange: [0.5, 1] }) }] }} />
        <Animated.View style={{ transform: [{ scale: v.interpolate({ inputRange: [0, 1], outputRange: [1, 1.12] }) }] }}>
          <I size={23} color={c as string} weight={focused ? "fill" : "regular"} />
        </Animated.View>
      </View>
    );
  }
  return TabIcon;
}

export const tabBarBase = { backgroundColor: color.card, borderTopColor: color.line, height: 84, paddingTop: 8 } as const;
