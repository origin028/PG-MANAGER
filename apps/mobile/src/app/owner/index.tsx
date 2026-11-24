import { router, useFocusEffect } from "expo-router";
import { useCallback, useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { Bell, Buildings, ChatCircleDots, CurrencyInr, IdentificationCard, LockKey, QrCode, Receipt, UserCheck, UserPlus, Wallet } from "phosphor-react-native";
import { Chip } from "@/components/charts";
import { Divider, ListRow } from "@/components/kit";
import { Badge, Body, Card, ErrorBox, H2, LoadingCards, Screen } from "@/components/ui";
import { greeting } from "@/lib/dates";
import { useWide } from "@/lib/layout";
import { useProperties } from "@/lib/owner";
import { useSession } from "@/lib/session";
import { color, radius, rupees, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Stats = {
  rooms: number; beds: number; occupied_beds: number; free_beds: number; occupancy_percent: number | null; residents: number; on_notice: number;
  collected_this_month: number; rent_due: number; open_complaints: number; signups_waiting: number; kyc_to_verify: number; access_paused: number; upi_to_confirm: number;
};
type HomeRow = Stats & { id: string; name: string; city?: string; property_type?: string };
type Overview = { homes: HomeRow[]; totals: Stats & { homes: number }; capacity: { limit: number; used: number; remaining: number } | null };
type ToDo = { key: keyof Stats; title: (n: number) => string; href: string; icon: React.ReactNode };

const kind = (t?: string) => (t === "WOMEN_ONLY" ? "Women only" : t === "MEN_ONLY" ? "Men only" : "Co-living");
const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

const TODOS: ToDo[] = [
  { key: "signups_waiting", title: (n) => `${plural(n, "new sign-up", "new sign-ups")} to approve`, href: "/manage/approvals", icon: <UserCheck size={24} color={color.ink} /> },
  { key: "kyc_to_verify", title: (n) => `${n} KYC ${n === 1 ? "is" : "are"} ready to check`, href: "/owner/residents", icon: <IdentificationCard size={24} color={color.ink} /> },
  { key: "upi_to_confirm", title: (n) => `${plural(n, "UPI payment", "UPI payments")} to confirm`, href: "/manage/confirm-payments", icon: <Wallet size={24} color={color.ink} /> },
  { key: "rent_due", title: (n) => `${rupees(n)} rent due`, href: "/owner/money", icon: <CurrencyInr size={24} color={color.ink} /> },
  { key: "open_complaints", title: (n) => `${plural(n, "open complaint", "open complaints")}`, href: "/manage/complaints", icon: <ChatCircleDots size={24} color={color.ink} /> },
  { key: "access_paused", title: (n) => `${plural(n, "resident's", "residents'")} app access paused`, href: "/owner/residents", icon: <LockKey size={24} color={color.ink} /> },
];

function Action({ icon, label, onPress }: { icon: React.ReactNode; label: string; onPress: () => void }) {
  return (
    <Card onPress={onPress} style={{ flex: 1, alignItems: "center", gap: space(2), paddingVertical: space(4), paddingHorizontal: space(2) }}>
      {icon}
      <Text style={[type.small, { color: color.ink, fontWeight: "600", textAlign: "center" }]}>{label}</Text>
    </Card>
  );
}

function Bar({ pct, dark }: { pct: number | null; dark?: boolean }) {
  return (
    <View style={{ height: 8, borderRadius: 4, backgroundColor: dark ? "#ffffff22" : color.cream, overflow: "hidden" }}>
      <View style={{ width: `${Math.min(100, pct ?? 0)}%`, height: "100%", backgroundColor: dark ? color.bg : color.ink, borderRadius: 4 }} />
    </View>
  );
}

/** One PG at a glance in "Your PGs". Tapping it focuses the whole app on that PG. */
function HomeCard({ h, onPress, width }: { h: HomeRow; onPress: () => void; width: `${number}%` }) {
  const todo = h.signups_waiting + h.kyc_to_verify + h.upi_to_confirm + h.open_complaints + h.access_paused;
  return (
    <Pressable onPress={onPress} accessibilityRole="button" accessibilityLabel={`Open ${h.name}`}
      style={({ pressed }) => ({ width, backgroundColor: color.card, borderRadius: radius.lg, padding: space(4), gap: space(3), transform: [{ scale: pressed ? 0.98 : 1 }] })}>
      <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "flex-start", gap: space(2) }}>
        <View style={{ flex: 1 }}>
          <Text style={[type.label, { color: color.ink, fontSize: 16 }]} numberOfLines={1}>{h.name}</Text>
          <Body muted style={{ fontSize: 13 }}>{kind(h.property_type)}{h.city ? ` · ${h.city}` : ""} · {h.rooms} rooms</Body>
        </View>
        {todo ? <Badge label={`${todo} to do`} tone="warn" /> : <Badge label="All good" tone="ok" />}
      </View>
      <View style={{ gap: space(1.5) }}>
        <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "baseline" }}>
          <Text style={{ fontSize: 22, fontWeight: "700", letterSpacing: -0.6, color: color.ink }}>{h.occupied_beds}<Text style={{ fontSize: 14, color: color.ink3 }}> / {h.beds} beds</Text></Text>
          <Text style={[type.label, { color: color.ink }]}>{h.occupancy_percent ?? 0}%</Text>
        </View>
        <Bar pct={h.occupancy_percent} />
      </View>
      <View style={{ flexDirection: "row", gap: space(3) }}>
        <View style={{ flex: 1 }}><Text style={[type.label, { color: color.ok }]}>{rupees(h.collected_this_month)}</Text><Body muted style={{ fontSize: 12 }}>Collected this month</Body></View>
        <View style={{ flex: 1 }}><Text style={[type.label, { color: h.rent_due ? color.bad : color.ink }]}>{rupees(h.rent_due)}</Text><Body muted style={{ fontSize: 12 }}>Rent due</Body></View>
        <View style={{ flex: 1 }}><Text style={[type.label, { color: color.ink }]}>{h.residents}</Text><Body muted style={{ fontSize: 12 }}>Residents</Body></View>
      </View>
    </Pressable>
  );
}

export default function Home() {
  const { me } = useSession();
  const wide = useWide();
  const { setCurrent } = useProperties();
  const [scope, setScope] = useState<string>("all");
  const ov = useData<Overview>("/reports/homes");
  const unread = useData<{ unread_count: number }>("/notifications/unread-count");
  const r1 = ov.reload, r2 = unread.reload;
  useFocusEffect(useCallback(() => { r1(); r2(); }, [r1, r2]));

  const homes = ov.data?.homes ?? [];
  const one = scope === "all" ? null : homes.find((h) => h.id === scope) ?? null;
  const s: Stats | null = one ?? ov.data?.totals ?? null;
  const bells = unread.data?.unread_count ?? 0;
  const focus = (id: string) => { setScope(id); setCurrent(id); };
  /** Opens a screen; if the to-do belongs to just one PG, that PG is selected first. */
  const go = (href: string, id?: string) => { if (id) setCurrent(id); router.push(href as never); };

  const todos = s ? TODOS.filter((t) => (s[t.key] as number) > 0).map((t) => {
    const places = one ? [one] : homes.filter((h) => (h[t.key] as number) > 0);
    return { ...t, n: s[t.key] as number, places };
  }) : [];

  return (
    <Screen onRefresh={() => { r1(); r2(); }} refreshing={ov.refreshing}>
      <View style={{ marginTop: space(4), marginBottom: space(4), flexDirection: "row", alignItems: "flex-start", justifyContent: "space-between" }}>
        <View>
          <Body muted>{greeting()}</Body>
          <Text style={[type.h1, { color: color.ink }]}>{me?.full_name?.split(" ")[0] ?? "Owner"}</Text>
        </View>
        <Pressable onPress={() => router.push("/manage/notifications")} hitSlop={10} accessibilityLabel={`Alerts${bells ? `, ${bells} new` : ""}`}
          style={{ width: 46, height: 46, borderRadius: 23, backgroundColor: color.card, alignItems: "center", justifyContent: "center", marginTop: space(2) }}>
          <Bell size={24} color={color.ink} weight={bells ? "fill" : "regular"} />
          {bells ? (
            <View style={{ position: "absolute", top: 4, right: 4, minWidth: 18, height: 18, borderRadius: 9, backgroundColor: color.bad, alignItems: "center", justifyContent: "center", paddingHorizontal: 4 }}>
              <Text style={{ color: "#fff", fontSize: 11, fontWeight: "700" }}>{bells > 9 ? "9+" : bells}</Text>
            </View>
          ) : null}
        </Pressable>
      </View>

      {homes.length > 1 ? (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: space(2), paddingBottom: space(4) }}>
          <Chip on={scope === "all"} onPress={() => setScope("all")}>{`All PGs (${homes.length})`}</Chip>
          {homes.map((h) => <Chip key={h.id} on={scope === h.id} onPress={() => focus(h.id)}>{h.name}</Chip>)}
        </ScrollView>
      ) : null}

      {ov.loading && !ov.data ? <LoadingCards /> : ov.error && !ov.data ? <ErrorBox message={ov.error} onRetry={ov.reload} /> : s && (
        <>
          <Card tone="black" onPress={() => go("/owner/rooms", one?.id)} style={{ gap: space(2) }}>
            <Text style={[type.small, { color: "#ffffffaa" }]}>{one ? `${one.name} · beds occupied` : homes.length > 1 ? `Beds occupied · all ${homes.length} PGs` : "Beds occupied"}</Text>
            <Text style={{ fontSize: 48, fontWeight: "700", letterSpacing: -1.6, color: color.bg }}>
              {s.occupied_beds}<Text style={{ fontSize: 24, color: "#ffffff77" }}> / {s.beds}</Text>
            </Text>
            <Bar pct={s.occupancy_percent} dark />
            <Text style={[type.small, { color: "#ffffffaa" }]}>
              {s.occupancy_percent ?? 0}% full · {s.free_beds} beds free · {s.residents} residents{s.on_notice ? ` · ${s.on_notice} on notice` : ""}
            </Text>
            {!one && ov.data?.capacity ? (
              <Text style={[type.small, { color: "#ffffff77" }]}>{ov.data.capacity.used} of {ov.data.capacity.limit} beds of capacity set up · {ov.data.capacity.remaining} more can be added</Text>
            ) : null}
          </Card>
          <View style={{ flexDirection: "row", gap: space(3), marginTop: space(3) }}>
            <Card onPress={() => go("/manage/finance", one?.id)} style={{ flex: 1, gap: space(1) }}>
              <Text style={{ fontSize: 24, fontWeight: "700", color: color.ok }}>{rupees(s.collected_this_month)}</Text>
              <Body muted>Collected this month</Body>
            </Card>
            <Card onPress={() => go("/owner/money", one?.id)} style={{ flex: 1, gap: space(1) }}>
              <Text style={{ fontSize: 24, fontWeight: "700", color: s.rent_due ? color.bad : color.ink }}>{rupees(s.rent_due)}</Text>
              <Body muted>Rent due</Body>
            </Card>
          </View>

          <H2>Needs your attention</H2>
          {todos.length ? (
            <Card style={{ paddingVertical: 0 }}>
              {todos.map((t, i) => (
                <View key={t.key}>{i ? <Divider /> : null}
                  <ListRow leading={t.icon} title={t.title(t.n)} sub={!one && homes.length > 1 ? t.places.map((p) => p.name).join(", ") : undefined}
                    onPress={() => go(t.href, one?.id ?? (t.places.length === 1 ? t.places[0].id : undefined))} />
                </View>
              ))}
            </Card>
          ) : <Card tone="cream"><Body>All caught up. Nothing needs you right now.</Body></Card>}

          {!one && homes.length > 1 ? (
            <>
              <H2>Your PGs</H2>
              <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space(3) }}>
                {homes.map((h) => <HomeCard key={h.id} h={h} onPress={() => focus(h.id)} width={wide ? "48.8%" : "100%"} />)}
              </View>
            </>
          ) : null}

          <H2>Quick actions</H2>
          <View style={{ flexDirection: "row", gap: space(2) }}>
            <Action icon={<UserPlus size={24} color={color.ink} />} label="Add resident" onPress={() => go("/manage/add-resident", one?.id)} />
            <Action icon={<QrCode size={24} color={color.ink} />} label="Join QR" onPress={() => go("/manage/join-qr", one?.id)} />
            <Action icon={<Receipt size={24} color={color.ink} />} label="Record payment" onPress={() => go("/owner/money", one?.id)} />
            <Action icon={<Buildings size={24} color={color.ink} />} label="PGs" onPress={() => router.push("/manage/properties")} />
          </View>
        </>
      )}
    </Screen>
  );
}
