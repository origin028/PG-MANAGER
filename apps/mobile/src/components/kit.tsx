/**
 * Building blocks for the owner console: page header with back/action, list rows, sections,
 * confirm dialogs and choice pickers. Keeps every management screen consistent and short.
 */
import { router } from "expo-router";
import type { ReactNode } from "react";
import { Alert, Platform, Pressable, Text, View } from "react-native";
import { ArrowLeft, CaretRight } from "phosphor-react-native";
import { Body, tap } from "@/components/ui";
import { color, radius, space, tint, type } from "@/lib/theme";

export function Header({ title, sub, action, back = true }: { title: string; sub?: string; action?: ReactNode; back?: boolean }) {
  return (
    <View style={{ marginTop: space(3), marginBottom: space(5) }}>
      {back ? (
        <Pressable onPress={() => (router.canGoBack() ? router.back() : router.replace("/owner"))} hitSlop={12} accessibilityLabel="Back" style={{ marginBottom: space(3) }}>
          <ArrowLeft size={24} color={color.ink} />
        </Pressable>
      ) : null}
      <View style={{ flexDirection: "row", alignItems: "flex-end", justifyContent: "space-between", gap: space(3) }}>
        <View style={{ flex: 1 }}>
          <Text style={[type.h1, { color: color.ink }]}>{title}</Text>
          {sub ? <Body muted style={{ marginTop: space(1) }}>{sub}</Body> : null}
        </View>
        {action}
      </View>
    </View>
  );
}

export function SmallButton({ label, onPress, tone = "dark", icon }: { label: string; onPress: () => void; tone?: "dark" | "light" | "danger"; icon?: ReactNode }) {
  const bg = tone === "dark" ? color.ink : color.card;
  const fg = tone === "dark" ? color.bg : tone === "danger" ? color.bad : color.ink;
  return (
    <Pressable onPress={() => { tap(); onPress(); }} style={({ pressed }) => ({ flexDirection: "row", alignItems: "center", gap: 6, height: 40, paddingHorizontal: space(4), borderRadius: radius.pill, backgroundColor: bg, borderWidth: 1, borderColor: tone === "dark" ? color.ink : color.line, transform: [{ scale: pressed ? 0.97 : 1 }] })}>
      {icon}
      <Text style={[type.label, { color: fg }]}>{label}</Text>
    </Pressable>
  );
}

export function ListRow({ title, sub, right, onPress, leading }: { title: string; sub?: string; right?: ReactNode; onPress?: () => void; leading?: ReactNode }) {
  const body = (
    <View style={{ flexDirection: "row", alignItems: "center", gap: space(3), paddingVertical: space(3.5) }}>
      {leading}
      <View style={{ flex: 1 }}>
        <Text style={[type.label, { color: color.ink, fontSize: 16 }]} numberOfLines={1}>{title}</Text>
        {sub ? <Body muted style={{ marginTop: 2 }}>{sub}</Body> : null}
      </View>
      {right}
      {onPress ? <CaretRight size={18} color={color.ink3} /> : null}
    </View>
  );
  return onPress ? <Pressable onPress={() => { tap(); onPress(); }}>{body}</Pressable> : body;
}

export function Divider() {
  return <View style={{ height: 1, backgroundColor: color.line }} />;
}

const AVATAR_TONES = ["violet", "blue", "teal", "green", "amber", "rose"] as const;
/** Round avatar with initials; each name always gets the same soft colour. */
export function Initials({ name, size = 42 }: { name: string; size?: number }) {
  const h = [...name].reduce((a, c) => (a * 31 + c.charCodeAt(0)) >>> 0, 7);
  const [bg, fg] = tint[AVATAR_TONES[h % AVATAR_TONES.length]];
  return (
    <View style={{ width: size, height: size, borderRadius: size / 2, backgroundColor: bg, alignItems: "center", justifyContent: "center" }}>
      <Text style={[type.label, { color: fg, fontWeight: "700" }]}>{name.split(" ").filter(Boolean).map((w) => w[0]).slice(0, 2).join("").toUpperCase()}</Text>
    </View>
  );
}

/** Native confirm on iOS/Android, window.confirm on web. */
export function confirmAction(title: string, message: string, confirmLabel: string, onConfirm: () => void, destructive = true) {
  if (Platform.OS === "web") {
    if (globalThis.confirm?.(`${title}\n\n${message}`)) onConfirm();
    return;
  }
  Alert.alert(title, message, [{ text: "Cancel", style: "cancel" }, { text: confirmLabel, style: destructive ? "destructive" : "default", onPress: onConfirm }]);
}

const ACRONYMS: Record<string, string> = { UPI: "UPI", KYC: "KYC", PAN: "PAN", CASH: "Cash", BANK_TRANSFER: "Bank transfer" };
export const nice = (s?: string | null) => ACRONYMS[s ?? ""] ?? (s ?? "").replace(/_/g, " ").toLowerCase().replace(/^\w/, (c) => c.toUpperCase());
export const digits = (s: string) => s.replace(/\D/g, "");
