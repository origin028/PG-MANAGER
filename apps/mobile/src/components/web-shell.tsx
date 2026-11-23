import { router, usePathname } from "expo-router";
import type { ReactNode } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import {
  Bed, Buildings, ChartBar, ChartLineUp, ChatCircleDots, CookingPot, Fingerprint, ForkKnife, Gear, House, IdentificationBadge,
  Megaphone, QrCode, SignOut, User, UserPlus, Users, Wallet,
} from "phosphor-react-native";
import { confirmAction } from "@/components/kit";
import { useSession, type Role } from "@/lib/session";
import { color, radius, space, type } from "@/lib/theme";

type Item = { href: string; label: string; icon: typeof House; match?: string[] };
const OWNER: { group?: string; items: Item[] }[] = [
  { items: [
    { href: "/owner", label: "Home", icon: House },
    { href: "/owner/residents", label: "Residents", icon: Users, match: ["/manage/resident", "/manage/add-resident", "/manage/approvals", "/approve"] },
    { href: "/owner/rooms", label: "Rooms & beds", icon: Bed, match: ["/manage/room"] },
    { href: "/owner/money", label: "Money", icon: Wallet, match: ["/manage/confirm-payments"] },
  ] },
  { group: "Your PG", items: [
    { href: "/manage/properties", label: "Properties", icon: Buildings },
    { href: "/manage/staff", label: "Staff", icon: IdentificationBadge },
    { href: "/manage/menu", label: "Food menu", icon: ForkKnife },
  ] },
  { group: "Day to day", items: [
    { href: "/manage/complaints", label: "Complaints", icon: ChatCircleDots },
    { href: "/manage/announcements", label: "Announcements", icon: Megaphone },
    { href: "/manage/leads", label: "Leads", icon: UserPlus },
    { href: "/manage/attendance", label: "Attendance", icon: Fingerprint },
  ] },
  { group: "Business", items: [
    { href: "/manage/finance", label: "Finance", icon: ChartBar },
    { href: "/manage/reports", label: "Reports", icon: ChartLineUp },
    { href: "/manage/kitchen", label: "Kitchen & meal passes", icon: CookingPot },
    { href: "/manage/settings", label: "Settings", icon: Gear },
  ] },
];
const RESIDENT: { group?: string; items: Item[] }[] = [
  { items: [
    { href: "/resident", label: "Home", icon: House },
    { href: "/resident/pay", label: "Rent", icon: Wallet },
    { href: "/resident/food", label: "Food", icon: ForkKnife, match: ["/meal-pass"] },
    { href: "/resident/help", label: "Help", icon: ChatCircleDots, match: ["/new-complaint"] },
    { href: "/resident/me", label: "Me", icon: User },
  ] },
];
const KITCHEN: { group?: string; items: Item[] }[] = [
  { items: [
    { href: "/kitchen", label: "Scan", icon: QrCode },
    { href: "/kitchen/today", label: "Today", icon: ChartLineUp },
    { href: "/kitchen/menu", label: "Menu", icon: ForkKnife },
  ] },
];

function isActive(path: string, it: Item) {
  const roots = ["/owner", "/resident", "/kitchen"];
  const exact = roots.includes(it.href) ? path === it.href : path === it.href || path.startsWith(`${it.href}/`);
  return exact || (it.match ?? []).some((m) => path === m || path.startsWith(`${m}/`));
}

/** Desktop sidebar + content area. Used only on wide browser windows. */
export function WebShell({ mode, children }: { mode: Role; children: ReactNode }) {
  const path = usePathname();
  const { me, signOut } = useSession();
  const nav = mode === "owner" ? OWNER : mode === "kitchen" ? KITCHEN : RESIDENT;
  const role = mode === "owner" ? "Owner" : mode === "kitchen" ? "Kitchen" : "Resident";

  return (
    <View style={{ flex: 1, flexDirection: "row", backgroundColor: color.bg }}>
      <View style={{ width: 264, backgroundColor: color.card, borderRightWidth: 1, borderRightColor: color.line }}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: space(2.5), paddingHorizontal: space(6), paddingTop: space(7), paddingBottom: space(6) }}>
          <View style={{ width: 30, height: 30, borderRadius: 9, backgroundColor: color.ink, alignItems: "center", justifyContent: "flex-end" }}>
            <View style={{ width: 12, height: 16, borderTopLeftRadius: 6, borderTopRightRadius: 6, backgroundColor: color.bg }} />
          </View>
          <View>
            <Text style={[type.label, { fontSize: 16, color: color.ink }]}>Origin Living</Text>
            <Text style={[type.small, { color: color.ink3 }]}>{role}</Text>
          </View>
        </View>
        <ScrollView contentContainerStyle={{ paddingHorizontal: space(3), paddingBottom: space(6) }}>
          {nav.map((g, gi) => (
            <View key={gi} style={{ marginBottom: space(4) }}>
              {g.group ? <Text style={[type.small, { color: color.ink3, fontWeight: "600", paddingHorizontal: space(3), marginBottom: space(1.5) }]}>{g.group}</Text> : null}
              {g.items.map((it) => {
                const on = isActive(path, it);
                const Icon = it.icon;
                return (
                  <Pressable key={it.href} onPress={() => router.push(it.href as never)} accessibilityRole="link"
                    style={(state) => ({ flexDirection: "row", alignItems: "center", gap: space(3), height: 42, paddingHorizontal: space(3), borderRadius: radius.sm, backgroundColor: on ? color.ink : (state as { hovered?: boolean }).hovered ? color.cream : "transparent" })}>
                    <Icon size={20} color={on ? color.bg : color.ink} weight={on ? "fill" : "regular"} />
                    <Text style={[type.label, { color: on ? color.bg : color.ink, fontWeight: on ? "600" : "500" }]}>{it.label}</Text>
                  </Pressable>
                );
              })}
            </View>
          ))}
        </ScrollView>
        <View style={{ borderTopWidth: 1, borderTopColor: color.line, padding: space(4), flexDirection: "row", alignItems: "center", gap: space(3) }}>
          <View style={{ width: 36, height: 36, borderRadius: 18, backgroundColor: color.cream, alignItems: "center", justifyContent: "center" }}>
            <Text style={[type.label, { color: color.ink }]}>{(me?.full_name ?? "?").split(" ").map((w) => w[0]).slice(0, 2).join("").toUpperCase()}</Text>
          </View>
          <View style={{ flex: 1 }}>
            <Text style={[type.label, { color: color.ink }]} numberOfLines={1}>{me?.full_name}</Text>
            <Text style={[type.small, { color: color.ink3 }]} numberOfLines={1}>{me?.email ?? me?.phone}</Text>
          </View>
          <Pressable onPress={() => confirmAction("Sign out?", "", "Sign out", signOut)} hitSlop={8} accessibilityLabel="Sign out">
            <SignOut size={20} color={color.ink2} />
          </Pressable>
        </View>
      </View>
      <View style={{ flex: 1 }}>{children}</View>
    </View>
  );
}
