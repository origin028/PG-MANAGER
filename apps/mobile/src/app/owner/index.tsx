import { router, useFocusEffect } from "expo-router";
import { useCallback, useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import {
  Bed, Bell, Buildings, ChatCircleDots, CurrencyInr, DoorOpen, HourglassMedium, IdentificationCard, LockKey, Megaphone,
  QrCode, Receipt, TrendUp, UserCheck, UserPlus, Users, Wallet, WarningCircle,
} from "phosphor-react-native";
import { Chip } from "@/components/charts";
import { Divider } from "@/components/kit";
import { ActionGrid, CountPill, CountUp, Fab, IconTile, ProgressBar, Reveal, Sheet, Springy } from "@/components/motion";
import { Badge, Body, Card, ErrorBox, H2, LoadingCards, Screen, tap } from "@/components/ui";
import { greeting } from "@/lib/dates";
import { useWide } from "@/lib/layout";
import { useProperties } from "@/lib/owner";
import { useSession } from "@/lib/session";
import { color, radius, rupees, shadow, space, type, type Tint } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Stats = {
  rooms: number; beds: number; occupied_beds: number; free_beds: number; occupancy_percent: number | null; residents: number; on_notice: number;
  collected_this_month: number; rent_due: number; open_complaints: number; signups_waiting: number; kyc_to_verify: number; access_paused: number; upi_to_confirm: number;
};
type HomeRow = Stats & { id: string; name: string; city?: string; property_type?: string };
type Overview = { homes: HomeRow[]; totals: Stats & { homes: number }; capacity: { limit: number; used: number; remaining: number } | null };
type IconC = typeof Bell;
type ToDo = { key: keyof Stats; title: (n: number) => string; href: string; icon: IconC; tone: Tint };

const kind = (t?: string) => (t === "WOMEN_ONLY" ? "Women only" : t === "MEN_ONLY" ? "Men only" : "Co-living");
const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

const TODOS: ToDo[] = [
  { key: "signups_waiting", title: (n) => `${plural(n, "new sign-up", "new sign-ups")} to approve`, href: "/manage/approvals", icon: UserCheck, tone: "violet" },
  { key: "upi_to_confirm", title: (n) => `${plural(n, "UPI payment", "UPI payments")} to confirm`, href: "/manage/confirm-payments", icon: Wallet, tone: "green" },
  { key: "kyc_to_verify", title: (n) => `${n} KYC ${n === 1 ? "is" : "are"} ready to check`, href: "/owner/residents", icon: IdentificationCard, tone: "blue" },
  { key: "rent_due", title: (n) => `${rupees(n)} rent due`, href: "/owner/money?tab=dues", icon: CurrencyInr, tone: "amber" },
  { key: "open_complaints", title: (n) => `${plural(n, "open complaint", "open complaints")}`, href: "/manage/complaints", icon: ChatCircleDots, tone: "rose" },
  { key: "access_paused", title: (n) => `${plural(n, "resident's", "residents'")} app access paused`, href: "/owner/residents", icon: LockKey, tone: "sand" },
];

function MiniStat({ icon: I, value, label }: { icon: IconC; value: number; label: string }) {
  return (
    <View style={{ flex: 1, gap: 2 }}>
      <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
        <I size={16} color="#ffffffaa" weight="fill" />
        <CountUp value={value} style={{ fontSize: 20, fontWeight: "700", color: color.bg }} />
      </View>
      <Text style={[type.small, { color: "#ffffff88" }]}>{label}</Text>
    </View>
  );
}

/** One PG at a glance in "Your PGs". Tapping it focuses the whole app on that PG. */
function HomeCard({ h, onPress, width }: { h: HomeRow; onPress: () => void; width: number | `${number}%` }) {
  const todo = h.signups_waiting + h.kyc_to_verify + h.upi_to_confirm + h.open_complaints + h.access_paused;
  return (
    <Springy onPress={() => { tap(); onPress(); }} accessibilityLabel={`Open ${h.name}`} scaleTo={0.97}
      style={[{ width, backgroundColor: color.card, borderRadius: radius.lg, padding: space(4), gap: space(3) }, shadow]}>
      <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "flex-start", gap: space(2) }}>
        <IconTile icon={Buildings} tone="sand" size={38} />
        {todo ? <Badge label={`${todo} to do`} tone="warn" /> : <Badge label="All good" tone="ok" />}
      </View>
      <View>
        <Text style={[type.label, { color: color.ink, fontSize: 16 }]} numberOfLines={1}>{h.name}</Text>
        <Body muted style={{ fontSize: 13 }} >{kind(h.property_type)}{h.city ? ` · ${h.city}` : ""} · {h.rooms} rooms</Body>
      </View>
      <View style={{ gap: space(1.5) }}>
        <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "baseline" }}>
          <Text style={{ fontSize: 22, fontWeight: "700", letterSpacing: -0.6, color: color.ink }}>{h.occupied_beds}<Text style={{ fontSize: 14, color: color.ink3 }}> / {h.beds} beds</Text></Text>
          <Text style={[type.label, { color: color.ink }]}>{Math.round(h.occupancy_percent ?? 0)}%</Text>
        </View>
        <ProgressBar pct={h.occupancy_percent} />
      </View>
      <View style={{ flexDirection: "row", gap: space(3) }}>
        <View style={{ flex: 1 }}><Text style={[type.label, { color: color.ok }]}>{rupees(h.collected_this_month)}</Text><Body muted style={{ fontSize: 12 }}>Collected</Body></View>
        <View style={{ flex: 1 }}><Text style={[type.label, { color: h.rent_due ? color.bad : color.ink }]}>{rupees(h.rent_due)}</Text><Body muted style={{ fontSize: 12 }}>Rent due</Body></View>
      </View>
    </Springy>
  );
}

export default function Home() {
  const { me } = useSession();
  const wide = useWide();
  const { setCurrent } = useProperties();
  const [scope, setScope] = useState<string>("all");
  const [sheet, setSheet] = useState(false);
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
  const go = (href: string, id?: string) => { setSheet(false); if (id) setCurrent(id); router.push(href as never); };

  const todos = s ? TODOS.filter((t) => (s[t.key] as number) > 0).map((t) => {
    const places = one ? [one] : homes.filter((h) => (h[t.key] as number) > 0);
    return { ...t, n: s[t.key] as number, places };
  }) : [];
  const billed = s ? s.collected_this_month + s.rent_due : 0;
  const collectedPct = billed ? Math.round((s!.collected_this_month / billed) * 100) : 0;

  const quick = [
    { icon: UserPlus, label: "Add resident", tone: "violet" as Tint, onPress: () => go("/manage/add-resident", one?.id) },
    { icon: Receipt, label: "Record payment", tone: "green" as Tint, onPress: () => go("/owner/money?tab=dues", one?.id) },
    { icon: QrCode, label: "Join QR", tone: "blue" as Tint, onPress: () => go("/manage/join-qr", one?.id) },
    { icon: Megaphone, label: "Notice", tone: "amber" as Tint, onPress: () => go("/manage/announcements", one?.id) },
  ];
  const more = [
    ...quick,
    { icon: Bed, label: "Add room", tone: "teal" as Tint, onPress: () => go("/owner/rooms", one?.id) },
    { icon: TrendUp, label: "Add expense", tone: "rose" as Tint, onPress: () => go("/owner/money?tab=expenses", one?.id) },
    { icon: ChatCircleDots, label: "Complaints", tone: "sand" as Tint, onPress: () => go("/manage/complaints", one?.id) },
    { icon: UserCheck, label: "Approvals", tone: "violet" as Tint, onPress: () => go("/manage/approvals", one?.id), badge: s?.signups_waiting },
    { icon: Buildings, label: "Your PGs", tone: "sand" as Tint, onPress: () => go("/manage/properties") },
  ];

  return (
    <Screen onRefresh={() => { r1(); r2(); }} refreshing={ov.refreshing}
      overlay={wide ? null : (
        <>
          <Fab onPress={() => setSheet(true)} />
          <Sheet open={sheet} onClose={() => setSheet(false)} title="Quick actions"><ActionGrid items={more} /></Sheet>
        </>
      )}>
      <Reveal>
        <View style={{ marginTop: space(4), marginBottom: space(4), flexDirection: "row", alignItems: "flex-start", justifyContent: "space-between" }}>
          <View>
            <Body muted>{greeting()}</Body>
            <Text style={[type.h1, { color: color.ink }]}>{me?.full_name?.split(" ")[0] ?? "Owner"}</Text>
          </View>
          <Springy onPress={() => { tap(); router.push("/manage/notifications"); }} accessibilityLabel={`Alerts${bells ? `, ${bells} new` : ""}`} scaleTo={0.9}
            style={[{ width: 46, height: 46, borderRadius: 23, backgroundColor: color.card, alignItems: "center", justifyContent: "center", marginTop: space(2) }, shadow]}>
            <Bell size={24} color={color.ink} weight={bells ? "fill" : "regular"} />
            {bells ? (
              <View style={{ position: "absolute", top: 4, right: 4, minWidth: 18, height: 18, borderRadius: 9, backgroundColor: color.bad, alignItems: "center", justifyContent: "center", paddingHorizontal: 4 }}>
                <Text style={{ color: "#fff", fontSize: 11, fontWeight: "700" }}>{bells > 9 ? "9+" : bells}</Text>
              </View>
            ) : null}
          </Springy>
        </View>
      </Reveal>

      {homes.length > 1 ? (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: space(2), paddingBottom: space(4) }}>
          <Chip on={scope === "all"} onPress={() => { tap(); setScope("all"); }}>{`All PGs (${homes.length})`}</Chip>
          {homes.map((h) => <Chip key={h.id} on={scope === h.id} onPress={() => { tap(); focus(h.id); }}>{h.name}</Chip>)}
        </ScrollView>
      ) : null}

      {ov.loading && !ov.data ? <LoadingCards /> : ov.error && !ov.data ? <ErrorBox message={ov.error} onRetry={ov.reload} /> : s && (
        <View key={scope}>
          <Reveal index={0}>
            <Card tone="black" onPress={() => go("/owner/rooms", one?.id)} style={{ gap: space(3) }}>
              <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center" }}>
                <Text style={[type.small, { color: "#ffffffaa" }]}>{one ? one.name : homes.length > 1 ? `All ${homes.length} PGs` : "Occupancy"}</Text>
                <View style={{ backgroundColor: "#ffffff1a", borderRadius: radius.pill, paddingHorizontal: 10, paddingVertical: 3 }}>
                  <CountUp value={s.occupancy_percent ?? 0} format={(n) => `${Math.round(n)}% full`} style={[type.small, { color: color.bg, fontWeight: "700" }]} />
                </View>
              </View>
              <View style={{ flexDirection: "row", alignItems: "baseline" }}>
                <CountUp value={s.occupied_beds} style={{ fontSize: 52, fontWeight: "700", letterSpacing: -2, color: color.bg }} />
                <Text style={{ fontSize: 24, fontWeight: "600", color: "#ffffff66" }}> / {s.beds} beds</Text>
              </View>
              <ProgressBar pct={s.occupancy_percent} dark />
              <View style={{ flexDirection: "row", marginTop: space(1) }}>
                <MiniStat icon={DoorOpen} value={s.free_beds} label="Beds free" />
                <MiniStat icon={Users} value={s.residents} label="Residents" />
                <MiniStat icon={HourglassMedium} value={s.on_notice} label="On notice" />
              </View>
            </Card>
          </Reveal>

          <Reveal index={1}>
            <Card onPress={() => go("/owner/money?tab=dues", one?.id)} style={{ marginTop: space(3), gap: space(3) }}>
              <View style={{ flexDirection: "row", gap: space(3) }}>
                <View style={{ flex: 1, gap: space(1) }}>
                  <Text style={[type.small, { color: color.ink3, fontWeight: "600" }]}>Collected this month</Text>
                  <CountUp value={s.collected_this_month} format={rupees} style={{ fontSize: 24, fontWeight: "700", letterSpacing: -0.6, color: color.ok }} />
                </View>
                <View style={{ width: 1, backgroundColor: color.line }} />
                <View style={{ flex: 1, gap: space(1) }}>
                  <Text style={[type.small, { color: color.ink3, fontWeight: "600" }]}>Still due</Text>
                  <CountUp value={s.rent_due} format={rupees} style={{ fontSize: 24, fontWeight: "700", letterSpacing: -0.6, color: s.rent_due ? color.bad : color.ink }} />
                </View>
              </View>
              <ProgressBar pct={collectedPct} tone={color.ok} />
              <Body muted style={{ fontSize: 13 }}>{billed ? `${collectedPct}% of this month's rent collected · tap to see who owes` : "No rent billed yet this month"}</Body>
            </Card>
          </Reveal>

          <Reveal index={2} style={{ marginTop: space(6) }}>
            <ActionGrid items={quick} columns={4} />
          </Reveal>

          <H2>Needs your attention</H2>
          {todos.length ? (
            <Reveal index={3}>
              <Card style={{ paddingVertical: space(1) }}>
                {todos.map((t, i) => (
                  <View key={t.key}>{i ? <Divider /> : null}
                    <Pressable accessibilityRole="button" onPress={() => { tap(); go(t.href, one?.id ?? (t.places.length === 1 ? t.places[0].id : undefined)); }}
                      style={({ pressed }) => ({ flexDirection: "row", alignItems: "center", gap: space(3), paddingVertical: space(3), opacity: pressed ? 0.6 : 1 })}>
                      <IconTile icon={t.icon} tone={t.tone} size={40} />
                      <View style={{ flex: 1 }}>
                        <Text style={[type.label, { color: color.ink, fontSize: 15 }]}>{t.title(t.n)}</Text>
                        {!one && homes.length > 1 ? <Text style={[type.small, { color: color.ink3, marginTop: 2 }]} numberOfLines={1}>{t.places.length > 2 ? `${t.places.length} PGs · ${t.places.map((p) => p.name).join(", ")}` : t.places.map((p) => p.name).join(", ")}</Text> : null}
                      </View>
                      {t.key !== "rent_due" ? <CountPill n={t.n} tone={t.tone} /> : <WarningCircle size={20} color={color.warn} weight="fill" />}
                    </Pressable>
                  </View>
                ))}
              </Card>
            </Reveal>
          ) : (
            <Reveal index={3}>
              <Card tone="cream" style={{ flexDirection: "row", alignItems: "center", gap: space(3) }}>
                <IconTile icon={UserCheck} tone="green" size={40} />
                <Body style={{ flex: 1 }}>All caught up. Nothing needs you right now.</Body>
              </Card>
            </Reveal>
          )}

          {!one && homes.length > 1 ? (
            <>
              <H2>Your PGs</H2>
              {wide ? (
                <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space(3) }}>
                  {homes.map((h, i) => <Reveal key={h.id} index={i} style={{ width: "48.8%" }}><HomeCard h={h} onPress={() => focus(h.id)} width="100%" /></Reveal>)}
                </View>
              ) : (
                <ScrollView horizontal showsHorizontalScrollIndicator={false} snapToInterval={292} decelerationRate="fast"
                  style={{ marginHorizontal: -space(5) }} contentContainerStyle={{ gap: space(3), paddingHorizontal: space(5), paddingBottom: space(3) }}>
                  {homes.map((h, i) => <Reveal key={h.id} index={i}><HomeCard h={h} onPress={() => focus(h.id)} width={280} /></Reveal>)}
                </ScrollView>
              )}
            </>
          ) : null}
          <View style={{ height: space(16) }} />
        </View>
      )}
    </Screen>
  );
}
