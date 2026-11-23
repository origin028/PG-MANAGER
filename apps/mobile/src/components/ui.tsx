/**
 * Shared UI kit. Every screen is built from these so the whole app looks and behaves the same.
 */
import * as Haptics from "expo-haptics";
import { useEffect, useState, type ReactNode } from "react";
import {
  ActivityIndicator,
  Animated,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
  type TextInputProps,
  type ViewStyle,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { color, radius, space, type } from "@/lib/theme";

export const tap = () => {
  if (Platform.OS !== "web") Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => {});
};

export function Screen({
  children,
  onRefresh,
  refreshing = false,
  scroll = true,
  padded = true,
}: {
  children: ReactNode;
  onRefresh?: () => void;
  refreshing?: boolean;
  scroll?: boolean;
  padded?: boolean;
}) {
  const body = padded ? { paddingHorizontal: space(5), paddingBottom: space(10) } : undefined;
  return (
    <SafeAreaView style={s.safe} edges={["top"]}>
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
        {scroll ? (
          <ScrollView
            contentContainerStyle={body}
            keyboardShouldPersistTaps="handled"
            showsVerticalScrollIndicator={false}
            refreshControl={onRefresh ? <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={color.ink} /> : undefined}
          >
            {children}
          </ScrollView>
        ) : (
          <View style={[{ flex: 1 }, body]}>{children}</View>
        )}
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

export function Title({ children, sub }: { children: ReactNode; sub?: ReactNode }) {
  return (
    <View style={{ marginTop: space(4), marginBottom: space(5) }}>
      <Text style={[type.h1, { color: color.ink }]}>{children}</Text>
      {sub ? <Text style={[type.body, { color: color.ink3, marginTop: space(1) }]}>{sub}</Text> : null}
    </View>
  );
}

export function H2({ children, style }: { children: ReactNode; style?: object }) {
  return <Text style={[type.h2, { color: color.ink, marginTop: space(7), marginBottom: space(3) }, style]}>{children}</Text>;
}

export function Body({ children, muted, style }: { children: ReactNode; muted?: boolean; style?: object }) {
  return <Text style={[type.body, { color: muted ? color.ink3 : color.ink2 }, style]}>{children}</Text>;
}

export function Card({ children, style, onPress, tone = "white" }: { children: ReactNode; style?: ViewStyle; onPress?: () => void; tone?: "white" | "cream" | "black" }) {
  const bg = tone === "black" ? color.ink : tone === "cream" ? color.cream : color.card;
  const inner = <View style={[s.card, { backgroundColor: bg }, style]}>{children}</View>;
  if (!onPress) return inner;
  return (
    <Pressable onPress={() => { tap(); onPress(); }} style={({ pressed }) => ({ transform: [{ scale: pressed ? 0.98 : 1 }] })}>
      {inner}
    </Pressable>
  );
}

export function Button({
  title,
  onPress,
  variant = "primary",
  loading,
  disabled,
  icon,
  style,
}: {
  title: string;
  onPress: () => void;
  variant?: "primary" | "secondary" | "ghost" | "danger";
  loading?: boolean;
  disabled?: boolean;
  icon?: ReactNode;
  style?: ViewStyle;
}) {
  const v = {
    primary: { bg: color.ink, fg: color.bg, border: color.ink },
    secondary: { bg: color.card, fg: color.ink, border: color.line },
    ghost: { bg: "transparent", fg: color.ink, border: "transparent" },
    danger: { bg: color.card, fg: color.bad, border: color.line },
  }[variant];
  const off = disabled || loading;
  return (
    <Pressable
      accessibilityRole="button"
      disabled={off}
      onPress={() => { tap(); onPress(); }}
      style={({ pressed }) => [
        s.btn,
        { backgroundColor: v.bg, borderColor: v.border, opacity: off ? 0.5 : 1, transform: [{ scale: pressed ? 0.97 : 1 }] },
        style,
      ]}
    >
      {loading ? <ActivityIndicator color={v.fg} /> : (
        <View style={{ flexDirection: "row", alignItems: "center", gap: space(2) }}>
          {icon}
          <Text style={[type.label, { color: v.fg, fontSize: 16 }]}>{title}</Text>
        </View>
      )}
    </Pressable>
  );
}

export function Field({ label, error, hint, ...p }: TextInputProps & { label: string; error?: string | null; hint?: string }) {
  return (
    <View style={{ marginBottom: space(4) }}>
      <Text style={[type.label, { color: color.ink, marginBottom: space(2) }]}>{label}</Text>
      <TextInput
        placeholderTextColor={color.ink3}
        style={[s.input, error ? { borderColor: color.bad } : null, p.multiline ? { height: 110, paddingTop: 14, textAlignVertical: "top" } : null]}
        {...p}
      />
      {error ? <Text style={[type.small, { color: color.bad, marginTop: space(1.5) }]}>{error}</Text> : hint ? <Text style={[type.small, { color: color.ink3, marginTop: space(1.5) }]}>{hint}</Text> : null}
    </View>
  );
}

const badgeTone: Record<string, [string, string]> = {
  ok: [color.okBg, color.ok],
  warn: [color.warnBg, color.warn],
  bad: [color.badBg, color.bad],
  neutral: [color.cream, color.ink2],
};
export function Badge({ label, tone = "neutral" }: { label: string; tone?: keyof typeof badgeTone }) {
  const [bg, fg] = badgeTone[tone];
  return (
    <View style={{ backgroundColor: bg, borderRadius: radius.pill, paddingHorizontal: 10, paddingVertical: 4, alignSelf: "flex-start" }}>
      <Text style={[type.small, { color: fg, fontWeight: "600" }]}>{label}</Text>
    </View>
  );
}

export function statusTone(status?: string): keyof typeof badgeTone {
  const st = (status ?? "").toUpperCase();
  if (["PAID", "ACTIVE", "RESOLVED", "CLOSED", "SUCCESS", "APPROVED", "VERIFIED", "SETTLED"].includes(st)) return "ok";
  if (["OVERDUE", "REJECTED", "FAILED", "CANCELLED"].includes(st)) return "bad";
  if (["PENDING", "PARTIALLY_PAID", "OPEN", "IN_PROGRESS", "PENDING_APPROVAL", "SUBMITTED"].includes(st)) return "warn";
  return "neutral";
}
export const pretty = (v?: string) => (v ?? "").replace(/_/g, " ").toLowerCase().replace(/^\w/, (c) => c.toUpperCase());

export function Row({ label, value }: { label: string; value: ReactNode }) {
  return (
    <View style={s.row}>
      <Text style={[type.body, { color: color.ink3 }]}>{label}</Text>
      <Text style={[type.body, { color: color.ink, fontWeight: "500", flexShrink: 1, textAlign: "right" }]}>{value}</Text>
    </View>
  );
}

export function Empty({ icon, title, body, action }: { icon?: ReactNode; title: string; body?: string; action?: ReactNode }) {
  return (
    <View style={{ alignItems: "center", paddingVertical: space(14), gap: space(2) }}>
      {icon}
      <Text style={[type.h2, { color: color.ink, textAlign: "center", marginTop: space(2) }]}>{title}</Text>
      {body ? <Text style={[type.body, { color: color.ink3, textAlign: "center", maxWidth: 280 }]}>{body}</Text> : null}
      {action ? <View style={{ marginTop: space(4) }}>{action}</View> : null}
    </View>
  );
}

export function ErrorBox({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <View style={[s.card, { backgroundColor: color.badBg, gap: space(3) }]}>
      <Text style={[type.body, { color: color.bad }]}>{message}</Text>
      {onRetry ? <Button title="Try again" variant="secondary" onPress={onRetry} /> : null}
    </View>
  );
}

/** Pulsing placeholder in the shape of the content that is loading. */
export function Skeleton({ h = 20, w = "100%", r = radius.sm, style }: { h?: number; w?: number | `${number}%`; r?: number; style?: ViewStyle }) {
  const [o] = useState(() => new Animated.Value(0.5));
  useEffect(() => {
    const loop = Animated.loop(Animated.sequence([
      Animated.timing(o, { toValue: 1, duration: 700, useNativeDriver: Platform.OS !== "web" }),
      Animated.timing(o, { toValue: 0.5, duration: 700, useNativeDriver: Platform.OS !== "web" }),
    ]));
    loop.start();
    return () => loop.stop();
  }, [o]);
  return <Animated.View style={[{ height: h, width: w, borderRadius: r, backgroundColor: color.cream, opacity: o }, style]} />;
}

export function LoadingCards({ n = 3 }: { n?: number }) {
  return (
    <View style={{ gap: space(3) }}>
      {Array.from({ length: n }, (_, i) => <Skeleton key={i} h={i === 0 ? 150 : 84} r={radius.lg} />)}
    </View>
  );
}

export function Segmented<T extends string>({ value, options, onChange }: { value: T; options: { value: T; label: string }[]; onChange: (v: T) => void }) {
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: space(2), paddingVertical: space(1) }}>
      {options.map((o) => {
        const on = o.value === value;
        return (
          <Pressable key={o.value} onPress={() => { tap(); onChange(o.value); }} style={[s.chip, on && { backgroundColor: color.ink, borderColor: color.ink }]}>
            <Text style={[type.label, { color: on ? color.bg : color.ink }]}>{o.label}</Text>
          </Pressable>
        );
      })}
    </ScrollView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: color.bg },
  card: { borderRadius: radius.lg, padding: space(5) },
  btn: { height: 54, borderRadius: radius.pill, alignItems: "center", justifyContent: "center", paddingHorizontal: space(6), borderWidth: 1 },
  input: { height: 54, borderRadius: radius.md, borderWidth: 1, borderColor: color.line, backgroundColor: color.card, paddingHorizontal: space(4), fontSize: 16, color: color.ink },
  row: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", paddingVertical: space(3), gap: space(4) },
  chip: { paddingHorizontal: space(4), height: 40, borderRadius: radius.pill, borderWidth: 1, borderColor: color.line, backgroundColor: color.card, justifyContent: "center" },
});
