import { router } from "expo-router";
import { View } from "react-native";
import { Bell, Buildings, ChartBar, ChartLineUp, ChatCircleDots, CookingPot, Fingerprint, ForkKnife, Gear, IdentificationBadge, Megaphone, QrCode, UserPlus } from "phosphor-react-native";
import { Divider, Header, ListRow } from "@/components/kit";
import { Card, H2, Screen } from "@/components/ui";
import { color } from "@/lib/theme";

const ICON = { size: 24, color: color.ink, weight: "light" as const };
const groups: { title: string; items: { icon: React.ReactNode; title: string; sub: string; href: string }[] }[] = [
  { title: "Your PGs", items: [
    { icon: <Buildings {...ICON} />, title: "Your PGs", sub: "All PGs, addresses, contacts", href: "/manage/properties" },
    { icon: <QrCode {...ICON} />, title: "Join QR code", sub: "Poster for new residents to sign up", href: "/manage/join-qr" },
    { icon: <Bell {...ICON} />, title: "Alerts", sub: "Sign-ups, KYC sent, access paused", href: "/manage/notifications" },
    { icon: <IdentificationBadge {...ICON} />, title: "Staff", sub: "Wardens, cooks, housekeeping", href: "/manage/staff" },
    { icon: <ForkKnife {...ICON} />, title: "Food menu", sub: "Weekly menu, timings, photos", href: "/manage/menu" },
  ] },
  { title: "Day to day", items: [
    { icon: <ChatCircleDots {...ICON} />, title: "Complaints", sub: "Assign and resolve issues", href: "/manage/complaints" },
    { icon: <Megaphone {...ICON} />, title: "Announcements", sub: "Notices to residents", href: "/manage/announcements" },
    { icon: <UserPlus {...ICON} />, title: "Leads", sub: "Website enquiries and visits", href: "/manage/leads" },
    { icon: <Fingerprint {...ICON} />, title: "Attendance", sub: "Who is in and out today", href: "/manage/attendance" },
  ] },
  { title: "Business", items: [
    { icon: <ChartBar {...ICON} />, title: "Finance", sub: "This month vs last month, 6-month trend", href: "/manage/finance" },
    { icon: <ChartLineUp {...ICON} />, title: "Reports", sub: "Occupancy, collections, exports", href: "/manage/reports" },
    { icon: <CookingPot {...ICON} />, title: "Kitchen & meal passes", sub: "Turn on, kitchen logins", href: "/manage/kitchen" },
    { icon: <Gear {...ICON} />, title: "Settings", sub: "Company details, password, sign out", href: "/manage/settings" },
  ] },
];

export default function More() {
  return (
    <Screen>
      <Header back={false} title="More" />
      {groups.map((g) => (
        <View key={g.title}>
          <H2 style={{ marginTop: 0 }}>{g.title}</H2>
          <Card style={{ paddingVertical: 0, marginBottom: 24 }}>
            {g.items.map((it, i) => (
              <View key={it.title}>
                {i ? <Divider /> : null}
                <ListRow leading={it.icon} title={it.title} sub={it.sub} onPress={() => router.push(it.href as never)} />
              </View>
            ))}
          </Card>
        </View>
      ))}
    </Screen>
  );
}
