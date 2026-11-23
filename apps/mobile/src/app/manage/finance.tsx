import { useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { ArrowRight, CaretLeft, CaretRight } from "phosphor-react-native";
import { AreaChart, Chip, Donut, FlowBars, Ring, compact, useTween, type Unit } from "@/components/charts";
import { Header } from "@/components/kit";
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
type Point = Pick<Month, "month" | "collected" | "spent" | "profit" | "margin_percent" | "residents" | "joined" | "left" | "occupancy_percent" | "collection_rate_percent" | "unpaid_now">;
type Delta = { change: number | null; percent: number | null };
type Report = { current: Month; previous: Month; change: Record<string, Delta>; trend: Point[] };

const ym = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
const label = (m: string, short = false) => new Date(`${m}-01T00:00:00`).toLocaleDateString("en-IN", short ? { month: "short" } : { month: "long", year: "numeric" });
const shift = (m: string, by: number) => { const d = new Date(`${m}-01T00:00:00`); d.setMonth(d.getMonth() + by); return ym(d); };
const pct = (v: number | null | undefined) => (v === null || v === undefined ? "–" : `${v}%`);

/** The metrics the main chart can show. `good` says whether a rise is good news. */
const METRICS: { key: keyof Point; title: string; unit: Unit; good: boolean }[] = [
  { key: "profit", title: "Profit", unit: "money", good: true },
  { key: "collected", title: "Collected", unit: "money", good: true },
  { key: "spent", title: "Spent", unit: "money", good: false },
  { key: "residents", title: "Residents", unit: "count", good: true },
  { key: "occupancy_percent", title: "Occupancy", unit: "percent", good: true },
  { key: "collection_rate_percent", title: "Rent collected %", unit: "percent", good: true },
  { key: "unpaid_now", title: "Unpaid", unit: "money", good: false },
];

const fmt = (v: number | null, unit: Unit) => (v === null ? "–" : unit === "money" ? rupees(v) : unit === "percent" ? `${v}%` : String(v));

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

function Kpi({ title, value, d, upIsGood, unit, vs, hint, width }: { title: string; value: string; d?: Delta; upIsGood?: boolean; unit?: "money" | "count" | "points"; vs: string; hint?: string; width: `${number}%` }) {
  return (
    <View style={{ width, backgroundColor: color.card, borderRadius: radius.lg, padding: space(4), gap: space(1.5) }}>
      <Body muted style={{ fontSize: 14 }}>{title}</Body>
      <Text style={{ fontSize: 24, fontWeight: "700", letterSpacing: -0.8, color: color.ink }}>{value}</Text>
      <DeltaChip d={d} upIsGood={upIsGood} unit={unit} vs={vs} />
      {hint ? <Body muted style={{ fontSize: 12 }}>{hint}</Body> : null}
    </View>
  );
}

export default function Finance() {
  const wide = useWide();
  const { props, setCurrent } = useProperties();
  const thisMonth = ym(new Date());
  const [month, setMonth] = useState(thisMonth);
  const [range, setRange] = useState<6 | 12>(6);
  const [scope, setScope] = useState<string>("all");
  const [metric, setMetric] = useState<keyof Point>("profit");
  const [focus, setFocus] = useState<string | null>(null);
  const [hover, setHover] = useState<string | null>(null);
  const { data, error, loading, refreshing, reload } = useData<Report>(
    `/reports/finance?month=${month}&months=${range}${scope !== "all" ? `&property_id=${scope}` : ""}`,
  );
  const progress = useTween(`${data?.current.month}-${range}-${scope}-${metric}-${data ? 1 : 0}`);
  const ringsIn = useTween(`${data?.current.month}-${scope}-${data ? 1 : 0}`, 900);

  const c = data?.current, ch = data?.change ?? {};
  const vs = data ? label(data.previous.month, true) : "last month";
  const trend = data?.trend ?? [];
  const m = METRICS.find((x) => x.key === metric) ?? METRICS[0];
  const picked = hover ?? focus;
  const focusMonth = picked && trend.some((t) => t.month === picked) ? picked : c?.month ?? month;
  const fi = trend.findIndex((t) => t.month === focusMonth);
  const fv = fi >= 0 ? (trend[fi][m.key] as number | null) : null;
  const pv = fi > 0 ? (trend[fi - 1][m.key] as number | null) : null;
  const diff = fv !== null && pv !== null ? fv - pv : null;
  const w = wide ? "23.9%" : "47.5%";
  const goMonth = (v: string) => { setFocus(null); setHover(null); setMonth(v); };

  return (
    <Screen onRefresh={reload} refreshing={refreshing}>
      <Header title="Finance" sub="Every month compared with the month before." />

      {/* Controls */}
      <View style={{ flexDirection: wide ? "row" : "column", gap: space(3), marginBottom: space(4), alignItems: wide ? "center" : "stretch" }}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: space(2), backgroundColor: color.card, borderRadius: radius.pill, padding: space(1), alignSelf: "flex-start" }}>
          <Pressable onPress={() => goMonth(shift(month, -1))} hitSlop={8} accessibilityLabel="Previous month" style={{ padding: space(2) }}><CaretLeft size={18} color={color.ink} /></Pressable>
          <Text style={[type.label, { color: color.ink, minWidth: 140, textAlign: "center" }]}>{label(month)}</Text>
          <Pressable onPress={() => month < thisMonth && goMonth(shift(month, 1))} hitSlop={8} accessibilityLabel="Next month" style={{ padding: space(2), opacity: month < thisMonth ? 1 : 0.3 }}><CaretRight size={18} color={color.ink} /></Pressable>
        </View>
        <View style={{ flexDirection: "row", gap: space(2) }}>
          <Chip on={range === 6} onPress={() => setRange(6)}>6 months</Chip>
          <Chip on={range === 12} onPress={() => setRange(12)}>12 months</Chip>
        </View>
        {props.length > 1 ? <Segmented value={scope} onChange={(v) => { setScope(v); if (v !== "all") setCurrent(v); }} options={[{ value: "all", label: "All homes" }, ...props.map((p) => ({ value: p.id, label: p.name }))]} /> : null}
      </View>

      {loading && !data ? <LoadingCards /> : error && !data ? <ErrorBox message={error} onRetry={reload} /> : c && data && (
        <>
          {/* 1. Main interactive chart */}
          <Card style={{ gap: space(4), padding: wide ? space(6) : space(4) }}>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: space(2) }} style={{ marginHorizontal: wide ? 0 : -space(4) }}>
              {!wide ? <View style={{ width: space(2) }} /> : null}
              {METRICS.map((x) => <Chip key={x.key} on={metric === x.key} onPress={() => setMetric(x.key)}>{x.title}</Chip>)}
              {!wide ? <View style={{ width: space(2) }} /> : null}
            </ScrollView>
            <View style={{ gap: 2 }}>
              <Text style={[type.small, { color: color.ink3 }]}>{m.title} · {label(focusMonth)}{focusMonth === thisMonth ? " so far" : ""}</Text>
              <Text style={{ fontSize: wide ? 44 : 38, fontWeight: "700", letterSpacing: -1.5, color: m.key === "profit" && (fv ?? 0) < 0 ? color.bad : color.ink }}>{fmt(fv, m.unit)}</Text>
              {diff !== null && fi > 0 ? (
                <Text style={[type.label, { color: diff === 0 ? color.ink3 : (diff > 0) === m.good ? color.ok : color.bad }]}>
                  {diff === 0 ? "Same as" : diff > 0 ? "▲" : "▼"} {diff === 0 ? "" : `${m.unit === "percent" ? `${Math.abs(diff).toFixed(1)} pts` : m.unit === "money" ? rupees(Math.abs(diff)) : Math.abs(diff)} vs `}{label(trend[fi - 1].month, true)}
                </Text>
              ) : <Text style={[type.small, { color: color.ink3 }]}>Tap a month on the chart to compare it.</Text>}
            </View>
            <AreaChart
              points={trend.map((t) => ({ key: t.month, label: label(t.month, true), value: t[m.key] as number | null }))}
              unit={m.unit} focus={focusMonth} onFocus={setFocus} onHover={setHover} progress={progress} height={wide ? 260 : 220}
              tone={m.key === "spent" || m.key === "unpaid_now" ? "#55514a" : color.ink}
            />
            {focusMonth !== c.month && !hover ? (
              <Pressable onPress={() => goMonth(focusMonth)} style={{ flexDirection: "row", alignItems: "center", gap: space(2), alignSelf: "flex-start", backgroundColor: color.ink, borderRadius: radius.pill, paddingHorizontal: space(4), height: 40 }}>
                <Text style={[type.label, { color: color.bg }]}>Open {label(focusMonth)} in full</Text>
                <ArrowRight size={16} color={color.bg} />
              </Pressable>
            ) : null}
          </Card>

          {/* 2. Rings: the three health numbers */}
          <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space(3), marginTop: space(3) }}>
            <Card style={{ flex: 1, minWidth: wide ? 0 : "47%", alignItems: "center", paddingVertical: space(5) }}>
              <Ring value={c.collection_rate_percent} progress={ringsIn} label="Rent collected" sub={`${compact(c.billed_paid, "money")} of ${compact(c.billed, "money")}`} />
            </Card>
            <Card style={{ flex: 1, minWidth: wide ? 0 : "47%", alignItems: "center", paddingVertical: space(5) }}>
              <Ring value={c.occupancy_percent} progress={ringsIn} label="Beds filled" sub={`${c.residents} of ${c.beds} beds`} />
            </Card>
            <Card style={{ flex: 1, minWidth: wide ? 0 : "100%", alignItems: "center", paddingVertical: space(5) }}>
              <Ring value={c.margin_percent} progress={ringsIn} label={c.profit < 0 ? "Loss margin" : "Profit margin"} sub={`${rupees(c.profit)} ${c.profit < 0 ? "loss" : "profit"}`} />
            </Card>
          </View>

          {/* 3. Where money came from / went */}
          <View style={{ flexDirection: wide ? "row" : "column", gap: space(3), marginTop: space(3) }}>
            <Card style={{ flex: 1, gap: space(3) }}>
              <Text style={[type.h2, { color: color.ink, fontSize: 18 }]}>Where money came from</Text>
              <Donut parts={c.collected_by_mode} prev={data.previous.collected_by_mode} progress={ringsIn} vs={vs} empty="No payments this month yet." />
            </Card>
            <Card style={{ flex: 1, gap: space(3) }}>
              <Text style={[type.h2, { color: color.ink, fontSize: 18 }]}>Where money went</Text>
              <Donut parts={c.spent_by_category} prev={data.previous.spent_by_category} progress={ringsIn} vs={vs} empty="No expenses this month yet." />
            </Card>
          </View>

          {/* 4. Residents joining and leaving */}
          <Card style={{ marginTop: space(3), gap: space(3) }}>
            <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "flex-end", gap: space(2) }}>
              <View style={{ flexShrink: 1 }}>
                <Text style={[type.h2, { color: color.ink, fontSize: 18 }]}>Residents joining and leaving</Text>
                <Body muted style={{ fontSize: 13 }}>Green joined, red moved out. Tap a month.</Body>
              </View>
              {(() => {
                const t = trend.find((x) => x.month === focusMonth);
                return t ? <Text style={[type.label, { color: color.ink }]}>{label(t.month, true)}: {t.joined - t.left >= 0 ? "+" : ""}{t.joined - t.left}</Text> : null;
              })()}
            </View>
            <FlowBars items={trend.map((t) => ({ key: t.month, label: label(t.month, true), up: t.joined, down: t.left }))} focus={focusMonth} onFocus={setFocus} onHover={setHover} progress={progress} />
          </Card>

          {/* 5. Every number vs last month */}
          <H2>{label(c.month)} vs {label(data.previous.month, true)}</H2>
          <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space(3) }}>
            <Kpi width={w} title="Collected" value={rupees(c.collected)} d={ch.collected} vs={vs} hint={`${c.payment_count} payments`} />
            <Kpi width={w} title="Spent" value={rupees(c.spent)} d={ch.spent} upIsGood={false} vs={vs} />
            <Kpi width={w} title="Profit" value={rupees(c.profit)} d={ch.profit} vs={vs} />
            <Kpi width={w} title="Profit margin" value={pct(c.margin_percent)} d={ch.margin_percent} unit="points" vs={vs} />
            <Kpi width={w} title="Rent collection rate" value={pct(c.collection_rate_percent)} d={ch.collection_rate_percent} unit="points" vs={vs} hint={`${rupees(c.billed_paid)} of ${rupees(c.billed)} billed`} />
            <Kpi width={w} title="Still unpaid" value={rupees(c.unpaid_now)} d={ch.unpaid_now} upIsGood={false} vs={vs} hint="Bills up to this month" />
            <Kpi width={w} title="Residents" value={String(c.residents)} d={ch.residents} unit="count" vs={vs} hint={c.is_current ? "Living here today" : "At month end"} />
            <Kpi width={w} title="Net growth" value={`${c.net_growth > 0 ? "+" : ""}${c.net_growth}`} d={ch.net_growth} unit="count" vs={vs} hint={`${c.joined} joined · ${c.left} left`} />
            <Kpi width={w} title="Occupancy" value={pct(c.occupancy_percent)} d={ch.occupancy_percent} unit="points" vs={vs} hint={`${c.residents} of ${c.beds} beds`} />
            <Kpi width={w} title="Revenue per resident" value={c.revenue_per_resident !== null ? rupees(c.revenue_per_resident) : "–"} d={ch.revenue_per_resident} vs={vs} />
            <Kpi width={w} title="Deposits received" value={rupees(c.deposits_received)} d={ch.deposits_received} vs={vs} hint={c.deposits_refunded ? `${rupees(c.deposits_refunded)} refunded` : undefined} />
          </View>
          <Body muted style={{ marginTop: space(5), fontSize: 13 }}>
            Collected counts payments received in the month. Rent collected % is how much of that month&apos;s rent bills has been paid. Residents are counted at month end ({c.is_current ? "today for this month" : "or today"}).
          </Body>
        </>
      )}
    </Screen>
  );
}
