import { router, useFocusEffect } from "expo-router";
import { useCallback } from "react";
import { Text, View } from "react-native";
import { ChatCircleDots, CurrencyInr, Megaphone, Receipt, UserCheck, UserPlus, Wallet } from "phosphor-react-native";
import { Divider, ListRow } from "@/components/kit";
import { Body, Card, ErrorBox, H2, LoadingCards, Screen } from "@/components/ui";
import { greeting } from "@/lib/dates";
import { listOf, useProperties } from "@/lib/owner";
import { useSession } from "@/lib/session";
import { color, rupees, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Dash = { total_beds: number; occupied_beds: number; vacant_beds: number; occupancy_rate_percent: number; gross_collections: number; pending_rent: number; open_complaints: number; active_residents: number };
type Pay = { status: string; is_settled?: boolean };
const DONE = ["SUCCESS", "SETTLED", "PAID", "COMPLETED", "FAILED", "CANCELLED", "REFUNDED"];

function Action({ icon, label, onPress }: { icon: React.ReactNode; label: string; onPress: () => void }) {
  return (
    <Card onPress={onPress} style={{ flex: 1, alignItems: "center", gap: space(2), paddingVertical: space(4), paddingHorizontal: space(2) }}>
      {icon}
      <Text style={[type.small, { color: color.ink, fontWeight: "600", textAlign: "center" }]}>{label}</Text>
    </Card>
  );
}

export default function Home() {
  const { me } = useSession();
  const { current } = useProperties();
  const dash = useData<Dash>("/reports/dashboard");
  const pending = useData<{ items: unknown[] }>("/residents/pending-approvals");
  const pays = useData<{ items: Pay[] }>(current ? `/payments?property_id=${current}&page_size=100` : null);
  const r1 = dash.reload, r2 = pending.reload, r3 = pays.reload;
  useFocusEffect(useCallback(() => { r1(); r2(); r3(); }, [r1, r2, r3]));

  const d = dash.data;
  const waiting = listOf(pending.data as never).length;
  const toConfirm = listOf<Pay>(pays.data as never).filter((p) => !p.is_settled && !DONE.includes((p.status ?? "").toUpperCase())).length;
  const attention = [
    waiting ? { icon: <UserCheck size={24} color={color.ink} />, title: `${waiting} new ${waiting === 1 ? "sign-up" : "sign-ups"} to approve`, href: "/manage/approvals" } : null,
    toConfirm ? { icon: <Wallet size={24} color={color.ink} />, title: `${toConfirm} UPI ${toConfirm === 1 ? "payment" : "payments"} to confirm`, href: "/manage/confirm-payments" } : null,
    d && d.pending_rent > 0 ? { icon: <CurrencyInr size={24} color={color.ink} />, title: `${rupees(d.pending_rent)} rent due`, href: "/owner/money" } : null,
    d && d.open_complaints ? { icon: <ChatCircleDots size={24} color={color.ink} />, title: `${d.open_complaints} open ${d.open_complaints === 1 ? "complaint" : "complaints"}`, href: "/manage/complaints" } : null,
  ].filter(Boolean) as { icon: React.ReactNode; title: string; href: string }[];

  return (
    <Screen onRefresh={() => { r1(); r2(); r3(); }} refreshing={dash.refreshing}>
      <View style={{ marginTop: space(4), marginBottom: space(5) }}>
        <Body muted>{greeting()}</Body>
        <Text style={[type.h1, { color: color.ink }]}>{me?.full_name?.split(" ")[0] ?? "Owner"}</Text>
      </View>
      {dash.loading ? <LoadingCards /> : dash.error ? <ErrorBox message={dash.error} onRetry={dash.reload} /> : d && (
        <>
          <Card tone="black" onPress={() => router.push("/owner/rooms")} style={{ gap: space(2) }}>
            <Text style={[type.small, { color: "#ffffffaa" }]}>Beds occupied</Text>
            <Text style={{ fontSize: 48, fontWeight: "700", letterSpacing: -1.6, color: color.bg }}>
              {d.occupied_beds}<Text style={{ fontSize: 24, color: "#ffffff77" }}> / {d.total_beds}</Text>
            </Text>
            <View style={{ height: 8, borderRadius: 4, backgroundColor: "#ffffff22", overflow: "hidden", marginTop: space(2) }}>
              <View style={{ width: `${Math.min(100, d.occupancy_rate_percent)}%`, height: "100%", backgroundColor: color.bg, borderRadius: 4 }} />
            </View>
            <Text style={[type.small, { color: "#ffffffaa" }]}>{d.vacant_beds} beds free · {d.active_residents} residents</Text>
          </Card>
          <View style={{ flexDirection: "row", gap: space(3), marginTop: space(3) }}>
            <Card onPress={() => router.push("/owner/money")} style={{ flex: 1, gap: space(1) }}>
              <Text style={{ fontSize: 24, fontWeight: "700", color: color.ok }}>{rupees(d.gross_collections)}</Text>
              <Body muted>Collected</Body>
            </Card>
            <Card onPress={() => router.push("/owner/money")} style={{ flex: 1, gap: space(1) }}>
              <Text style={{ fontSize: 24, fontWeight: "700", color: color.ink }}>{rupees(d.pending_rent)}</Text>
              <Body muted>Rent due</Body>
            </Card>
          </View>

          <H2>Needs your attention</H2>
          {attention.length ? (
            <Card style={{ paddingVertical: 0 }}>
              {attention.map((a, i) => (
                <View key={a.title}>{i ? <Divider /> : null}<ListRow leading={a.icon} title={a.title} onPress={() => router.push(a.href as never)} /></View>
              ))}
            </Card>
          ) : <Card tone="cream"><Body>All caught up. Nothing needs you right now.</Body></Card>}

          <H2>Quick actions</H2>
          <View style={{ flexDirection: "row", gap: space(2) }}>
            <Action icon={<UserPlus size={24} color={color.ink} />} label="Add resident" onPress={() => router.push("/manage/add-resident")} />
            <Action icon={<Receipt size={24} color={color.ink} />} label="Record payment" onPress={() => router.push("/owner/money")} />
            <Action icon={<Megaphone size={24} color={color.ink} />} label="Announce" onPress={() => router.push("/manage/announcements")} />
          </View>
        </>
      )}
    </Screen>
  );
}
