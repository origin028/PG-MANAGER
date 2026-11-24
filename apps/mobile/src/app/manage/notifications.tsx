import { router, useFocusEffect } from "expo-router";
import { useCallback } from "react";
import { Pressable, Text, View } from "react-native";
import { Bell, CurrencyInr, IdentificationCard, LockKey, UserCheck } from "phosphor-react-native";
import { Header, SmallButton } from "@/components/kit";
import { Body, Card, Empty, ErrorBox, LoadingCards, Screen } from "@/components/ui";
import { api } from "@/lib/api";
import { color, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Alert = { id: string; title: string; body: string; kind?: string | null; link?: string | null; is_read: boolean; created_at: string };

const ICON: Record<string, React.ReactNode> = {
  NEW_SIGNUP: <UserCheck size={22} color={color.ink} />,
  KYC_SUBMITTED: <IdentificationCard size={22} color={color.ink} />,
  ACCESS_PAUSED: <LockKey size={22} color={color.ink} />,
  PAYMENT: <CurrencyInr size={22} color={color.ink} />,
};

function ago(iso: string) {
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 60) return "just now";
  if (s < 3600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
  if (s < 7 * 86400) return `${Math.floor(s / 86400)} d ago`;
  return new Date(iso).toLocaleDateString("en-IN", { day: "numeric", month: "short" });
}

/** Owner's alerts: new sign-ups, KYC sent, access paused. Tap one to open the right screen. */
export default function Notifications() {
  const list = useData<Alert[]>("/notifications?limit=50");
  const reload = list.reload;
  useFocusEffect(useCallback(() => { reload(); }, [reload]));
  const items = list.data ?? [];
  const unread = items.filter((a) => !a.is_read).length;

  async function open(a: Alert) {
    if (!a.is_read) await api(`/notifications/${a.id}/read`, { method: "PATCH" }).catch(() => {});
    if (a.link) router.push(a.link as never); else reload();
  }
  async function readAll() {
    await api("/notifications/read-all", { method: "POST" }).catch(() => {});
    reload();
  }

  return (
    <Screen onRefresh={reload} refreshing={list.refreshing}>
      <Header title="Alerts" sub={unread ? `${unread} new` : "You're up to date"} action={unread ? <SmallButton label="Mark all read" onPress={() => { readAll(); }} /> : undefined} />
      {list.loading && !list.data ? <LoadingCards /> : list.error && !list.data ? <ErrorBox message={list.error} onRetry={reload} /> : items.length ? (
        <Card style={{ paddingVertical: space(1) }}>
          {items.map((a, i) => (
            <Pressable key={a.id} onPress={() => open(a)} accessibilityRole="button"
              style={({ pressed }) => ({ flexDirection: "row", gap: space(3), paddingVertical: space(3.5), borderTopWidth: i ? 1 : 0, borderTopColor: color.line, opacity: pressed ? 0.7 : 1 })}>
              <View style={{ width: 40, height: 40, borderRadius: 20, backgroundColor: a.is_read ? color.cream : color.okBg, alignItems: "center", justifyContent: "center" }}>
                {ICON[a.kind ?? ""] ?? <Bell size={22} color={color.ink} />}
              </View>
              <View style={{ flex: 1, gap: 2 }}>
                <View style={{ flexDirection: "row", justifyContent: "space-between", gap: space(2) }}>
                  <Text style={[type.label, { color: color.ink, flex: 1, fontWeight: a.is_read ? "500" : "700" }]} numberOfLines={1}>{a.title}</Text>
                  <Body muted style={{ fontSize: 12 }}>{ago(a.created_at)}</Body>
                </View>
                <Body muted={a.is_read} style={{ fontSize: 14 }}>{a.body}</Body>
              </View>
              {!a.is_read ? <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: color.bad, marginTop: 6 }} /> : null}
            </Pressable>
          ))}
        </Card>
      ) : <Empty icon={<Bell size={44} color={color.ink} weight="light" />} title="No alerts yet" body="You'll be told here (and on your phone) when someone signs up, sends their KYC, or their access pauses." />}
    </Screen>
  );
}
