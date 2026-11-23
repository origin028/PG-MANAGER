import { useState } from "react";
import { Pressable, Text, View } from "react-native";
import { CaretLeft, CaretRight } from "phosphor-react-native";
import { Header, nice } from "@/components/kit";
import { Body, Card, ErrorBox, H2, LoadingCards, Screen, Segmented } from "@/components/ui";
import { useWide } from "@/lib/layout";
import { useProperties } from "@/lib/owner";
import { color, radius, rupees, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Month = {
  month: string; is_current: boolean; collected: number; collected_by_mode: Record<string, number>; payment_count: number;
  spent: number; spent_by_category: Record<string, number>; profit: number; margin_percent: number | null; billed: number; billed_paid: number;
  collection_rate_percent: number | null; unpaid_now: number; residents: number; joined: number; left: number; net_growth: number;
  beds: number; occupancy_percent: number | null; revenue_per_resident: number | null; deposits_received: number; deposits_refunded: number;
};
type Delta = { change: number | null; percent: number | null };
type Report = { current: Month; previous: Month; change: Record<string, Delta>; trend: { month: string; collected: number; spent: number; profit: number; residents: number }[] };

const ym = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
const label = (m: string, short = false) => new Date(`${m}-01T00:00:00`).toLocaleDateString("en-IN", short ? { month: "short" } : { month: "long", year: "numeric" });
const shift = (m: string, by: number) => { const d = new Date(`${m}-01T00:00:00`); d.setMonth(d.getMonth() + by); return ym(d); };
const pct = (v: number | null | undefined) => (v === null || v === undefined ? "–" : `${v}%`);

/** ▲/▼ chip. `upIsGood` decides colour: more profit is good, more spending is not. */
function DeltaChip({ d, upIsGood = true, unit = "money", vs }: { d?: Delta; upIsGood?: boolean; unit?: "money" | "count" | "points"; vs: string }) {
  if (!d || d.change === null) return <Body muted style={{ fontSize: 13 }}>No data for {vs}</Body>;
  if (d.change === 0) return <Body muted style={{ fontSize: 13 }}>Same as {vs}</Body>;
  const up = d.change > 0;
  const good = up === upIsGood;
  const amount = unit === "money" ? rupees(Math.abs(d.change)) : unit === "points" ? `${Math.abs(d.change).toFixed(1)} pts` : String(Math.abs(d.change));
  return (
    <Text style={[type.small, { color: good ? color.ok : color.bad, fontWeight: "600" }]}>
      {up ? "▲" : "▼"} {amount}{d.percent !== null && unit !== "points" ? ` (${Math.abs(d.percent)}%)` : ""} <Text style={{ color: color.ink3, fontWeight: "400" }}>vs {vs}</Text>
    </Text>
  );
}

function Kpi({ title, value, d, upIsGood, unit, vs, hint, width }: { title: string; value: string; d?: Delta; upIsGood?: boolean; unit?: "money" | "count" | "points"; vs: string; hint?: string; width: `${number}%` | number }) {
  return (
    <View style={{ width, backgroundColor: color.card, borderRadius: radius.lg, padding: space(4), gap: space(1.5) }}>
      <Body muted style={{ fontSize: 14 }}>{title}</Body>
      <Text style={{ fontSize: 26, fontWeight: "700", letterSpacing: -0.8, color: color.ink }}>{value}</Text>
      <DeltaChip d={d} upIsGood={upIsGood} unit={unit} vs={vs} />
      {hint ? <Body muted style={{ fontSize: 12 }}>{hint}</Body> : null}
    </View>
  );
}

function TrendChart({ trend, selected }: { trend: Report["trend"]; selected: string }) {
  const max = Math.max(1, ...trend.flatMap((t) => [t.collected, t.spent]));
  const H = 160;
  return (
    <Card style={{ gap: space(4) }}>
      <View style={{ flexDirection: "row", gap: space(4) }}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}><View style={{ width: 12, height: 12, borderRadius: 3, backgroundColor: color.ink }} /><Body muted style={{ fontSize: 13 }}>Collected</Body></View>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}><View style={{ width: 12, height: 12, borderRadius: 3, backgroundColor: color.line }} /><Body muted style={{ fontSize: 13 }}>Spent</Body></View>
      </View>
      <View style={{ flexDirection: "row", alignItems: "flex-end", height: H, gap: space(2) }}>
        {trend.map((t) => (
          <View key={t.month} style={{ flex: 1, flexDirection: "row", alignItems: "flex-end", justifyContent: "center", gap: 4, height: H }} accessibilityLabel={`${label(t.month)}: collected ${rupees(t.collected)}, spent ${rupees(t.spent)}`}>
            <View style={{ width: "34%", height: Math.max(2, (t.collected / max) * H), backgroundColor: color.ink, borderRadius: 5, opacity: t.month === selected ? 1 : 0.55 }} />
            <View style={{ width: "34%", height: Math.max(2, (t.spent / max) * H), backgroundColor: color.line, borderRadius: 5 }} />
          </View>
        ))}
      </View>
      <View style={{ flexDirection: "row", gap: space(2) }}>
        {trend.map((t) => (
          <View key={t.month} style={{ flex: 1, alignItems: "center" }}>
            <Text style={[type.small, { color: color.ink, fontWeight: t.month === selected ? "700" : "500" }]}>{label(t.month, true)}</Text>
            <Text style={[type.small, { color: t.profit < 0 ? color.bad : color.ok, fontSize: 11 }]}>{t.profit < 0 ? "-" : "+"}{rupees(Math.abs(t.profit)).replace("₹", "₹")}</Text>
          </View>
        ))}
      </View>
    </Card>
  );
}

function Breakdown({ title, cur, prev, vs }: { title: string; cur: Record<string, number>; prev: Record<string, number>; vs: string }) {
  const keys = Array.from(new Set([...Object.keys(cur), ...Object.keys(prev)])).sort((a, b) => (cur[b] ?? 0) - (cur[a] ?? 0));
  const max = Math.max(1, ...keys.map((k) => Math.max(cur[k] ?? 0, prev[k] ?? 0)));
  if (!keys.length) return <Card><Body muted>Nothing recorded.</Body></Card>;
  return (
    <Card style={{ gap: space(4) }}>
      <Text style={[type.label, { color: color.ink }]}>{title}</Text>
      {keys.map((k) => {
        const c = cur[k] ?? 0, p = prev[k] ?? 0;
        return (
          <View key={k} style={{ gap: 6 }}>
            <View style={{ flexDirection: "row", justifyContent: "space-between" }}>
              <Text style={[type.label, { color: color.ink }]}>{nice(k)}</Text>
              <Body>{rupees(c)} <Text style={{ color: color.ink3, fontSize: 13 }}>· {vs} {rupees(p)}</Text></Body>
            </View>
            <View style={{ height: 6, borderRadius: 3, width: `${(c / max) * 100}%`, backgroundColor: color.ink }} />
            <View style={{ height: 4, borderRadius: 2, width: `${(p / max) * 100}%`, backgroundColor: color.line }} />
          </View>
        );
      })}
    </Card>
  );
}

export default function Finance() {
  const wide = useWide();
  const { props, setCurrent } = useProperties();
  const [month, setMonth] = useState(ym(new Date()));
  const [scope, setScope] = useState<string>("all");
  const q = `/reports/finance?month=${month}${scope !== "all" ? `&property_id=${scope}` : ""}`;
  const { data, error, loading, refreshing, reload } = useData<Report>(q);
  const thisMonth = ym(new Date());
  const vs = data ? label(data.previous.month, true) : "last month";
  const c = data?.current, ch = data?.change ?? {};
  const w = wide ? "23.9%" : "47.5%"; // two (phone) or four (desktop) per row, including the gaps

  return (
    <Screen onRefresh={reload} refreshing={refreshing}>
      <Header title="Finance" sub="Each month compared with the month before." />
      <View style={{ flexDirection: wide ? "row" : "column", gap: space(3), marginBottom: space(4), alignItems: wide ? "center" : "stretch" }}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: space(2), backgroundColor: color.card, borderRadius: radius.pill, padding: space(1), alignSelf: "flex-start" }}>
          <Pressable onPress={() => setMonth(shift(month, -1))} hitSlop={8} accessibilityLabel="Previous month" style={{ padding: space(2) }}><CaretLeft size={18} color={color.ink} /></Pressable>
          <Text style={[type.label, { color: color.ink, minWidth: 150, textAlign: "center" }]}>{label(month)}</Text>
          <Pressable onPress={() => month < thisMonth && setMonth(shift(month, 1))} hitSlop={8} accessibilityLabel="Next month" style={{ padding: space(2), opacity: month < thisMonth ? 1 : 0.3 }}><CaretRight size={18} color={color.ink} /></Pressable>
        </View>
        {props.length > 1 ? <Segmented value={scope} onChange={(v) => { setScope(v); if (v !== "all") setCurrent(v); }} options={[{ value: "all", label: "All homes" }, ...props.map((p) => ({ value: p.id, label: p.name }))]} /> : null}
      </View>

      {loading ? <LoadingCards /> : error ? <ErrorBox message={error} onRetry={reload} /> : c && data && (
        <>
          <Card tone="black" style={{ gap: space(2) }}>
            <Text style={[type.small, { color: "#ffffffaa" }]}>{c.profit < 0 ? "Loss" : "Profit"} · {label(c.month)}{c.is_current ? " so far" : ""}</Text>
            <Text style={{ fontSize: 48, fontWeight: "700", letterSpacing: -1.6, color: color.bg }}>{rupees(c.profit)}</Text>
            <Text style={[type.body, { color: "#ffffffcc" }]}>{rupees(c.collected)} collected − {rupees(c.spent)} spent{c.margin_percent !== null ? ` · ${c.margin_percent}% margin` : ""}</Text>
            {ch.profit?.change !== null && ch.profit?.change !== undefined ? (
              <Text style={[type.label, { color: ch.profit.change >= 0 ? "#7ee2a8" : "#ff9b92" }]}>
                {ch.profit.change >= 0 ? "▲" : "▼"} {rupees(Math.abs(ch.profit.change))}{ch.profit.percent !== null ? ` (${Math.abs(ch.profit.percent)}%)` : ""} vs {vs} ({rupees(data.previous.profit)})
              </Text>
            ) : null}
          </Card>

          <H2>Key numbers</H2>
          <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space(3) }}>
            <Kpi width={w} title="Collected" value={rupees(c.collected)} d={ch.collected} vs={vs} hint={`${c.payment_count} payments`} />
            <Kpi width={w} title="Spent" value={rupees(c.spent)} d={ch.spent} upIsGood={false} vs={vs} />
            <Kpi width={w} title="Profit margin" value={pct(c.margin_percent)} d={ch.margin_percent} unit="points" vs={vs} />
            <Kpi width={w} title="Rent collection rate" value={pct(c.collection_rate_percent)} d={ch.collection_rate_percent} unit="points" vs={vs} hint={`${rupees(c.billed_paid)} of ${rupees(c.billed)} billed`} />
            <Kpi width={w} title="Still unpaid" value={rupees(c.unpaid_now)} d={ch.unpaid_now} upIsGood={false} vs={vs} hint="Bills up to this month" />
            <Kpi width={w} title="Residents" value={String(c.residents)} d={ch.residents} unit="count" vs={vs} hint={c.is_current ? "Living here today" : "At month end"} />
            <Kpi width={w} title="Net growth" value={`${c.net_growth > 0 ? "+" : ""}${c.net_growth}`} d={ch.net_growth} unit="count" vs={vs} hint={`${c.joined} joined · ${c.left} left`} />
            <Kpi width={w} title="Occupancy" value={pct(c.occupancy_percent)} d={ch.occupancy_percent} unit="points" vs={vs} hint={`${c.residents} of ${c.beds} beds`} />
            <Kpi width={w} title="Revenue per resident" value={c.revenue_per_resident !== null ? rupees(c.revenue_per_resident) : "–"} d={ch.revenue_per_resident} vs={vs} />
            <Kpi width={w} title="Deposits received" value={rupees(c.deposits_received)} d={ch.deposits_received} vs={vs} hint={c.deposits_refunded ? `${rupees(c.deposits_refunded)} refunded` : undefined} />
          </View>

          <H2>Last 6 months</H2>
          <TrendChart trend={data.trend} selected={c.month} />

          <View style={{ flexDirection: wide ? "row" : "column", gap: space(3), marginTop: space(7) }}>
            <View style={{ flex: 1 }}><Breakdown title="Where money came from" cur={c.collected_by_mode} prev={data.previous.collected_by_mode} vs={vs} /></View>
            <View style={{ flex: 1 }}><Breakdown title="Where money went" cur={c.spent_by_category} prev={data.previous.spent_by_category} vs={vs} /></View>
          </View>

          <H2>Residents month by month</H2>
          <Card style={{ flexDirection: "row", gap: space(2), alignItems: "flex-end", height: 150 }}>
            {(() => {
              const maxR = Math.max(1, ...data.trend.map((t) => t.residents));
              return data.trend.map((t) => (
                <View key={t.month} style={{ flex: 1, alignItems: "center", gap: 6 }}>
                  <Text style={[type.small, { color: color.ink, fontWeight: "600" }]}>{t.residents}</Text>
                  <View style={{ width: "50%", height: Math.max(3, (t.residents / maxR) * 80), backgroundColor: t.month === c.month ? color.ink : color.line, borderRadius: 5 }} />
                  <Text style={[type.small, { color: color.ink3 }]}>{label(t.month, true)}</Text>
                </View>
              ));
            })()}
          </Card>
          <Body muted style={{ marginTop: space(5), fontSize: 13 }}>
            Collected counts payments received in the month. Collection rate is how much of that month's rent bills has been paid. Residents are counted at month end ({c.is_current ? "today for this month" : "or today"}).
          </Body>
        </>
      )}
    </Screen>
  );
}
