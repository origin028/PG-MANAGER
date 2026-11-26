/**
 * Motion + feedback kit: entrance animations, count-up numbers, springy press, icon tiles,
 * toasts, a bottom sheet and a floating action button. Built on React Native's Animated so it
 * works the same on iOS, Android and the web build, with no extra native dependencies.
 */
import * as Haptics from "expo-haptics";
import { useEffect, useRef, useState, useSyncExternalStore, type ComponentType, type ReactNode } from "react";
import { AccessibilityInfo, Animated, Easing, Modal, Platform, Pressable, StyleSheet, Text, View, type StyleProp, type ViewStyle } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { CheckCircle, Plus, WarningCircle, X } from "phosphor-react-native";
import { color, radius, shadow, space, tint, type, type Tint } from "@/lib/theme";

const ND = Platform.OS !== "web"; // native driver isn't available on web

/** Respect the system "reduce motion" setting. */
let reduceMotion = false;
AccessibilityInfo.isReduceMotionEnabled?.().then((v) => { reduceMotion = v; }).catch(() => {});

export const buzz = (kind: "success" | "warning" | "select" = "select") => {
  if (Platform.OS === "web") return;
  if (kind === "select") Haptics.selectionAsync().catch(() => {});
  else Haptics.notificationAsync(kind === "success" ? Haptics.NotificationFeedbackType.Success : Haptics.NotificationFeedbackType.Warning).catch(() => {});
};

/** Fades and slides its children in. Give each item in a list a growing `index` for a stagger. */
export function Reveal({ children, index = 0, style, from = 16 }: { children: ReactNode; index?: number; style?: StyleProp<ViewStyle>; from?: number }) {
  const [v] = useState(() => new Animated.Value(reduceMotion ? 1 : 0));
  useEffect(() => {
    if (reduceMotion) return;
    const a = Animated.timing(v, { toValue: 1, duration: 420, delay: Math.min(index, 10) * 55, easing: Easing.out(Easing.cubic), useNativeDriver: ND });
    a.start();
    return () => a.stop();
  }, [v, index]);
  return (
    <Animated.View style={[style, { opacity: v, transform: [{ translateY: v.interpolate({ inputRange: [0, 1], outputRange: [from, 0] }) }] }]}>
      {children}
    </Animated.View>
  );
}

/** A number that counts up to its value (and re-animates when the value changes). */
export function CountUp({ value, format = (n) => String(Math.round(n)), style, ms = 900 }: { value: number; format?: (n: number) => string; style?: StyleProp<object>; ms?: number }) {
  const [shown, setShown] = useState(reduceMotion ? value : 0);
  const from = useRef(0);
  useEffect(() => {
    if (reduceMotion) return;
    const start = Date.now(), a = from.current, b = value;
    let raf = 0;
    const step = () => {
      const t = Math.min(1, (Date.now() - start) / ms);
      const e = 1 - Math.pow(1 - t, 3);
      setShown(a + (b - a) * e);
      if (t < 1) raf = requestAnimationFrame(step);
      else from.current = b;
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [value, ms]);
  return <Text style={style as never}>{format(reduceMotion ? value : shown)}</Text>;
}

/** Pressable that springs down when touched and back when released. */
export function Springy({ children, onPress, onLongPress, style, scaleTo = 0.96, disabled, accessibilityLabel, accessibilityRole = "button" }: {
  children: ReactNode; onPress?: () => void; onLongPress?: () => void; style?: StyleProp<ViewStyle>; scaleTo?: number; disabled?: boolean;
  accessibilityLabel?: string; accessibilityRole?: "button" | "link" | "tab";
}) {
  const [s] = useState(() => new Animated.Value(1));
  const to = (n: number) => Animated.spring(s, { toValue: n, useNativeDriver: ND, speed: 40, bounciness: n === 1 ? 10 : 0 }).start();
  // Layout props go on the outer touchable so the item still sizes/places correctly inside rows.
  const { flex, width, alignSelf, margin, marginTop, marginBottom, marginLeft, marginRight, marginHorizontal, marginVertical, ...inner } = (StyleSheet.flatten(style) ?? {}) as ViewStyle;
  const outer: ViewStyle = { flex, width, alignSelf, margin, marginTop, marginBottom, marginLeft, marginRight, marginHorizontal, marginVertical };
  return (
    <Pressable onPress={onPress} onLongPress={onLongPress} disabled={disabled} onPressIn={() => to(scaleTo)} onPressOut={() => to(1)}
      accessibilityRole={accessibilityRole} accessibilityLabel={accessibilityLabel} accessibilityState={{ disabled: !!disabled }} style={outer}>
      <Animated.View style={[inner, flex != null ? { flexGrow: 1 } : null, { transform: [{ scale: s }] }]}>{children}</Animated.View>
    </Pressable>
  );
}

type IconC = ComponentType<{ size?: number; color?: string; weight?: "thin" | "light" | "regular" | "bold" | "fill" | "duotone" }>;

/** Rounded square with a soft colour and an icon in the matching strong colour. */
export function IconTile({ icon: I, tone = "sand", size = 44 }: { icon: IconC; tone?: Tint; size?: number }) {
  const [bg, fg] = tint[tone];
  return (
    <View style={{ width: size, height: size, borderRadius: size * 0.32, backgroundColor: bg, alignItems: "center", justifyContent: "center" }}>
      <I size={size * 0.52} color={fg} weight="duotone" />
    </View>
  );
}

/** Small pill with a number, e.g. "3". */
export function CountPill({ n, tone = "rose" }: { n: number | string; tone?: Tint }) {
  const [bg, fg] = tint[tone];
  return (
    <View style={{ minWidth: 26, height: 26, borderRadius: 13, paddingHorizontal: 8, backgroundColor: bg, alignItems: "center", justifyContent: "center" }}>
      <Text style={{ fontSize: 13, fontWeight: "700", color: fg }}>{n}</Text>
    </View>
  );
}

/* ---------------- Toasts ---------------- */

type ToastMsg = { id: number; text: string; kind: "success" | "error" | "info" };
let toasts: ToastMsg[] = [];
const toastListeners = new Set<() => void>();
const emit = () => toastListeners.forEach((l) => l());

/** Show a short message at the top of the screen. Call from anywhere. */
export function toast(text: string, kind: ToastMsg["kind"] = "success") {
  const id = Date.now() + Math.random();
  toasts = [...toasts.slice(-2), { id, text, kind }];
  emit();
  buzz(kind === "error" ? "warning" : "success");
  setTimeout(() => { toasts = toasts.filter((t) => t.id !== id); emit(); }, 3200);
}

function ToastItem({ t }: { t: ToastMsg }) {
  const [v] = useState(() => new Animated.Value(0));
  useEffect(() => { Animated.spring(v, { toValue: 1, useNativeDriver: ND, speed: 14, bounciness: 8 }).start(); }, [v]);
  const Icon = t.kind === "error" ? WarningCircle : CheckCircle;
  const fg = t.kind === "error" ? "#ff8a80" : t.kind === "success" ? "#7be0a8" : color.bg;
  return (
    <Animated.View style={[shadow, {
      flexDirection: "row", alignItems: "center", gap: space(3), backgroundColor: color.ink, borderRadius: radius.md,
      paddingVertical: space(3.5), paddingHorizontal: space(4), maxWidth: 520, width: "100%", alignSelf: "center",
      opacity: v, transform: [{ translateY: v.interpolate({ inputRange: [0, 1], outputRange: [-30, 0] }) }, { scale: v.interpolate({ inputRange: [0, 1], outputRange: [0.95, 1] }) }],
    }]}>
      <Icon size={22} color={fg} weight="fill" />
      <Text style={[type.label, { color: color.bg, flex: 1, fontWeight: "500" }]}>{t.text}</Text>
    </Animated.View>
  );
}

/** Mount once near the root. */
export function ToastHost() {
  const list = useSyncExternalStore((l) => { toastListeners.add(l); return () => { toastListeners.delete(l); }; }, () => toasts, () => toasts);
  const insets = useSafeAreaInsets();
  if (!list.length) return null;
  return (
    <View pointerEvents="none" style={{ position: "absolute", top: insets.top + space(2), left: space(4), right: space(4), gap: space(2), zIndex: 1000 }}>
      {list.map((t) => <ToastItem key={t.id} t={t} />)}
    </View>
  );
}

/* ---------------- Bottom sheet ---------------- */

export function Sheet({ open, onClose, title, children }: { open: boolean; onClose: () => void; title?: string; children: ReactNode }) {
  const [v] = useState(() => new Animated.Value(0));
  const [mounted, setMounted] = useState(open);
  const insets = useSafeAreaInsets();
  if (open && !mounted) setMounted(true);
  useEffect(() => {
    if (open) {
      Animated.spring(v, { toValue: 1, useNativeDriver: ND, speed: 16, bounciness: 4 }).start();
    } else {
      Animated.timing(v, { toValue: 0, duration: 180, useNativeDriver: ND }).start(() => setMounted(false));
    }
  }, [open, v]);
  if (!mounted) return null;
  return (
    <Modal transparent visible onRequestClose={onClose} animationType="none" statusBarTranslucent>
      <Animated.View style={{ flex: 1, backgroundColor: "#00000066", opacity: v }}>
        <Pressable style={{ flex: 1 }} onPress={onClose} accessibilityLabel="Close" />
      </Animated.View>
      <Animated.View style={{
        position: "absolute", left: 0, right: 0, bottom: 0, alignItems: "center",
        transform: [{ translateY: v.interpolate({ inputRange: [0, 1], outputRange: [500, 0] }) }],
      }}>
        <View style={{ width: "100%", maxWidth: 560, backgroundColor: color.bg, borderTopLeftRadius: 28, borderTopRightRadius: 28, paddingHorizontal: space(5), paddingTop: space(3), paddingBottom: insets.bottom + space(6) }}>
          <View style={{ alignSelf: "center", width: 40, height: 5, borderRadius: 3, backgroundColor: color.line, marginBottom: space(4) }} />
          {title ? (
            <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", marginBottom: space(4) }}>
              <Text style={[type.h2, { color: color.ink }]}>{title}</Text>
              <Pressable onPress={onClose} hitSlop={10} accessibilityLabel="Close" style={{ width: 34, height: 34, borderRadius: 17, backgroundColor: color.cream, alignItems: "center", justifyContent: "center" }}>
                <X size={18} color={color.ink} weight="bold" />
              </Pressable>
            </View>
          ) : null}
          {children}
        </View>
      </Animated.View>
    </Modal>
  );
}

/** Grid of big tappable tiles, used inside a Sheet or on a home screen. */
export function ActionGrid({ items, columns = 3 }: { items: { icon: IconC; label: string; tone: Tint; onPress: () => void; badge?: number }[]; columns?: number }) {
  const w = `${(100 - (columns - 1) * 3) / columns}%` as `${number}%`;
  const compact = columns >= 4;
  return (
    <View style={{ flexDirection: "row", flexWrap: "wrap", columnGap: "3%" as never, rowGap: space(2.5) }}>
      {items.map((it, i) => (
        <Reveal key={it.label} index={i} from={10} style={{ width: w }}>
          <Springy onPress={() => { buzz(); it.onPress(); }} accessibilityLabel={it.label}
            style={[{ backgroundColor: color.card, borderRadius: radius.lg, paddingVertical: space(compact ? 3 : 4), paddingHorizontal: space(1), alignItems: "center", gap: space(2), minHeight: compact ? 104 : 118 }, shadow]}>
            <View>
              <IconTile icon={it.icon} tone={it.tone} size={compact ? 42 : 46} />
              {it.badge ? (
                <View style={{ position: "absolute", top: -6, right: -8, minWidth: 20, height: 20, borderRadius: 10, backgroundColor: color.bad, alignItems: "center", justifyContent: "center", paddingHorizontal: 5, borderWidth: 2, borderColor: color.card }}>
                  <Text style={{ color: "#fff", fontSize: 10, fontWeight: "800" }}>{it.badge > 9 ? "9+" : it.badge}</Text>
                </View>
              ) : null}
            </View>
            <Text style={[type.small, { color: color.ink, fontWeight: "600", textAlign: "center", fontSize: compact ? 12 : 13, lineHeight: compact ? 15 : 17 }]} numberOfLines={2}>{it.label}</Text>
          </Springy>
        </Reveal>
      ))}
    </View>
  );
}

/** Floating round "+" button in the bottom-right corner, above the tab bar. */
export function Fab({ onPress, label = "Quick actions" }: { onPress: () => void; label?: string }) {
  const [v] = useState(() => new Animated.Value(0));
  useEffect(() => { Animated.spring(v, { toValue: 1, delay: 350, useNativeDriver: ND, speed: 10, bounciness: 12 }).start(); }, [v]);
  return (
    <Animated.View style={{ position: "absolute", right: space(5), bottom: space(5), transform: [{ scale: v }] }}>
      <Springy onPress={() => { buzz(); onPress(); }} accessibilityLabel={label} scaleTo={0.9}
        style={[{ width: 60, height: 60, borderRadius: 30, backgroundColor: color.ink, alignItems: "center", justifyContent: "center" }, shadow, { shadowOpacity: 0.25 }]}>
        <Plus size={28} color={color.bg} weight="bold" />
      </Springy>
    </Animated.View>
  );
}

/** Thin animated progress bar. */
export function ProgressBar({ pct, dark, tone }: { pct: number | null; dark?: boolean; tone?: string }) {
  const [v] = useState(() => new Animated.Value(0));
  useEffect(() => {
    Animated.timing(v, { toValue: Math.max(0, Math.min(100, pct ?? 0)), duration: reduceMotion ? 0 : 900, easing: Easing.out(Easing.cubic), useNativeDriver: false }).start();
  }, [pct, v]);
  return (
    <View style={{ height: 8, borderRadius: 4, backgroundColor: dark ? "#ffffff22" : color.cream, overflow: "hidden" }}>
      <Animated.View style={{ width: v.interpolate({ inputRange: [0, 100], outputRange: ["0%", "100%"] }), height: "100%", backgroundColor: tone ?? (dark ? color.bg : color.ink), borderRadius: 4 }} />
    </View>
  );
}
