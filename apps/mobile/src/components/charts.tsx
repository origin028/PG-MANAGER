/**
 * Small, dependency-free charts drawn with react-native-svg (works on iOS, Android and web).
 * Every chart animates in when its data changes and lets the user tap (or hover on web) a point.
 */
import { useEffect, useState, type ReactNode } from "react";
import { Pressable, Text, View, type LayoutChangeEvent } from "react-native";
import Svg, { Circle, Defs, Line, LinearGradient, Path, Stop } from "react-native-svg";
import { color, space, type } from "@/lib/theme";

/** 0 → 1 ease-out, restarted whenever `key` changes. */
export function useTween(key: string, ms = 750) {
  const [p, setP] = useState(0);
  useEffect(() => {
    let raf = 0;
    const start = Date.now();
    const step = () => {
      const t = Math.min(1, (Date.now() - start) / ms);
      setP(1 - Math.pow(1 - t, 3));
      if (t < 1) raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [key, ms]);
  return p;
}

export type Unit = "money" | "count" | "percent";

export const compact = (v: number, unit: Unit) => {
  if (unit === "percent") return `${Math.round(v)}%`;
  if (unit === "count") return String(Math.round(v));
  const a = Math.abs(v), sign = v < 0 ? "-" : "";
  if (a >= 100000) return `${sign}₹${(a / 100000).toFixed(a >= 1000000 ? 0 : 1)}L`;
  if (a >= 1000) return `${sign}₹${(a / 1000).toFixed(a >= 10000 ? 0 : 1)}k`;
  return `${sign}₹${Math.round(a)}`;
};

function useWidth(): [number, (e: LayoutChangeEvent) => void] {
  const [w, setW] = useState(0);
  return [w, (e) => setW(Math.round(e.nativeEvent.layout.width))];
}

/** Smooth area chart with a zero line (for losses), gridlines, and tappable months. */
export function AreaChart({
  points, unit, focus, onFocus, onHover, progress, height = 210, tone = color.ink,
}: {
  points: { key: string; label: string; value: number | null }[];
  unit: Unit; focus: string; onFocus: (key: string) => void; onHover?: (key: string | null) => void; progress: number; height?: number; tone?: string;
}) {
  const [w, onLayout] = useWidth();
  const padL = 44, padR = 12, padT = 16, padB = 28;
  const vals = points.map((p) => p.value ?? 0);
  let max = Math.max(0, ...vals), min = Math.min(0, ...vals);
  if (max === min) max = min + 1;
  const span = max - min; max += span * 0.12; if (min < 0) min -= span * 0.12;
  const iw = Math.max(1, w - padL - padR), ih = height - padT - padB;
  const y = (v: number) => padT + ((max - v) / (max - min)) * ih;
  const zero = y(0);
  const step = points.length > 1 ? iw / (points.length - 1) : 0;
  const xy = points.map((p, i) => ({ x: padL + i * step, y: zero + (y(p.value ?? 0) - zero) * progress }));
  let line = "";
  xy.forEach((p, i) => {
    if (i === 0) { line = `M${p.x},${p.y}`; return; }
    const a = xy[i - 1], mx = (a.x + p.x) / 2;
    line += ` C${mx},${a.y} ${mx},${p.y} ${p.x},${p.y}`;
  });
  const area = xy.length ? `${line} L${xy[xy.length - 1].x},${zero} L${xy[0].x},${zero} Z` : "";
  const grid = [max, (max + min) / 2, min].map((v) => ({ v, y: y(v) }));
  const fi = Math.max(0, points.findIndex((p) => p.key === focus));

  return (
    <View onLayout={onLayout} style={{ height }}>
      {w > 0 ? (
        <>
          <Svg width={w} height={height}>
            <Defs>
              <LinearGradient id="fill" x1="0" y1="0" x2="0" y2="1">
                <Stop offset="0" stopColor={tone} stopOpacity={0.16} />
                <Stop offset="1" stopColor={tone} stopOpacity={0} />
              </LinearGradient>
            </Defs>
            {grid.map((g, i) => <Line key={i} x1={padL} x2={w - padR} y1={g.y} y2={g.y} stroke={color.line} strokeWidth={1} strokeDasharray="3 5" />)}
            {min < 0 ? <Line x1={padL} x2={w - padR} y1={zero} y2={zero} stroke={color.ink3} strokeWidth={1} /> : null}
            <Path d={area} fill="url(#fill)" />
            <Path d={line} stroke={tone} strokeWidth={2.5} fill="none" strokeLinecap="round" />
            {xy[fi] ? <Line x1={xy[fi].x} x2={xy[fi].x} y1={padT} y2={height - padB} stroke={color.ink3} strokeWidth={1} strokeDasharray="2 4" /> : null}
            {xy.map((p, i) => (
              <Circle key={points[i].key} cx={p.x} cy={p.y} r={i === fi ? 6.5 : 3.5} fill={i === fi ? tone : color.card} stroke={tone} strokeWidth={2} />
            ))}
          </Svg>
          {grid.map((g, i) => (
            <Text key={i} style={[type.small, { position: "absolute", left: 0, top: g.y - 9, width: padL - 6, textAlign: "right", fontSize: 11, color: color.ink3 }]}>{compact(g.v, unit)}</Text>
          ))}
          {points.map((p, i) => (
            <Pressable
              key={p.key}
              onPress={() => onFocus(p.key)}
              onHoverIn={() => onHover?.(p.key)}
              onHoverOut={() => onHover?.(null)}
              accessibilityRole="button"
              accessibilityLabel={`${p.label}: ${p.value === null ? "no data" : compact(p.value, unit)}`}
              style={{ position: "absolute", top: 0, bottom: 0, left: padL + i * step - Math.max(step, 24) / 2, width: Math.max(step, 24), justifyContent: "flex-end", alignItems: "center" }}
            >
              <Text style={[type.small, { fontSize: 11, color: i === fi ? color.ink : color.ink3, fontWeight: i === fi ? "700" : "500" }]}>
                {step >= 34 || i === fi || (points.length - 1 - i) % 2 === 0 ? p.label : " "}
              </Text>
            </Pressable>
          ))}
        </>
      ) : null}
    </View>
  );
}

/** Progress ring for a percentage, with the number in the middle. */
export function Ring({ value, label, sub, progress, size = 116, tone }: { value: number | null; label: string; sub?: string; progress: number; size?: number; tone?: string }) {
  const stroke = 11, r = (size - stroke) / 2, c = 2 * Math.PI * r;
  const v = Math.max(0, Math.min(100, Math.abs(value ?? 0)));
  const col = tone ?? (value !== null && value < 0 ? color.bad : color.ink);
  return (
    <View style={{ alignItems: "center", gap: space(2) }}>
      <View style={{ width: size, height: size, alignItems: "center", justifyContent: "center" }}>
        <Svg width={size} height={size} style={{ position: "absolute" }}>
          <Circle cx={size / 2} cy={size / 2} r={r} stroke={color.cream} strokeWidth={stroke} fill="none" />
          <Circle
            cx={size / 2} cy={size / 2} r={r} stroke={col} strokeWidth={stroke} fill="none" strokeLinecap="round"
            strokeDasharray={`${c} ${c}`} strokeDashoffset={c * (1 - (v / 100) * progress)}
            transform={`rotate(-90 ${size / 2} ${size / 2})`}
          />
        </Svg>
        <Text style={{ fontSize: 24, fontWeight: "700", letterSpacing: -0.8, color: col }}>{value === null ? "–" : `${Math.round(value * progress)}%`}</Text>
      </View>
      <Text style={[type.label, { color: color.ink, textAlign: "center" }]}>{label}</Text>
      {sub ? <Text style={[type.small, { color: color.ink3, textAlign: "center" }]}>{sub}</Text> : null}
    </View>
  );
}

const SHADES = ["#000000", "#55514a", "#8f897e", "#bdb5a6", "#ddd5c5", "#ece6da"];

/** Donut split with a legend; each legend row also shows the change from last month. */
export function Donut({ parts, prev, progress, vs, empty }: { parts: Record<string, number>; prev: Record<string, number>; progress: number; vs: string; empty: string }) {
  const [focus, setFocus] = useState<string | null>(null);
  const entries = Object.entries(parts).filter(([, v]) => v > 0).sort((a, b) => b[1] - a[1]);
  const total = entries.reduce((s, [, v]) => s + v, 0);
  const size = 150, stroke = 22, r = (size - stroke) / 2, c = 2 * Math.PI * r;
  if (!total) return <Text style={[type.body, { color: color.ink3, paddingVertical: space(6) }]}>{empty}</Text>;
  const shown = focus ? entries.find(([k]) => k === focus) : null;
  const starts = entries.reduce<number[]>((acc, [, v], i) => [...acc, i === 0 ? 0 : acc[i - 1] + entries[i - 1][1] / total * c], []);
  return (
    <View style={{ gap: space(4) }}>
      <View style={{ alignItems: "center" }}>
        <View style={{ width: size, height: size, alignItems: "center", justifyContent: "center" }}>
          <Svg width={size} height={size} style={{ position: "absolute" }}>
            <Circle cx={size / 2} cy={size / 2} r={r} stroke={color.cream} strokeWidth={stroke} fill="none" />
            {entries.map(([k, v], i) => (
              <Circle
                key={k} cx={size / 2} cy={size / 2} r={r} fill="none"
                stroke={SHADES[i % SHADES.length]} strokeWidth={focus === k ? stroke + 6 : stroke}
                strokeDasharray={`${Math.max(0, (v / total) * c * progress - 1.5)} ${c}`} strokeDashoffset={-starts[i] * progress}
                transform={`rotate(-90 ${size / 2} ${size / 2})`}
              />
            ))}
          </Svg>
          <Text style={[type.small, { color: color.ink3 }]}>{shown ? niceKey(shown[0]) : "Total"}</Text>
          <Text style={{ fontSize: 18, fontWeight: "700", color: color.ink }}>{compact(shown ? shown[1] : total, "money")}</Text>
          {shown ? <Text style={[type.small, { color: color.ink3 }]}>{Math.round((shown[1] / total) * 100)}%</Text> : null}
        </View>
      </View>
      <View style={{ gap: space(1) }}>
        {entries.map(([k, v], i) => {
          const d = v - (prev[k] ?? 0);
          return (
            <Pressable key={k} onPress={() => setFocus(focus === k ? null : k)} onHoverIn={() => setFocus(k)} onHoverOut={() => setFocus(null)}
              style={{ flexDirection: "row", alignItems: "center", gap: space(2), paddingVertical: 6, paddingHorizontal: 6, borderRadius: 10, backgroundColor: focus === k ? color.cream : "transparent" }}>
              <View style={{ width: 10, height: 10, borderRadius: 3, backgroundColor: SHADES[i % SHADES.length], borderWidth: i >= 4 ? 1 : 0, borderColor: color.line }} />
              <Text style={[type.label, { color: color.ink, flex: 1 }]} numberOfLines={1}>{niceKey(k)}</Text>
              <Text style={[type.small, { color: color.ink, fontWeight: "600" }]}>{compact(v, "money")}</Text>
              <Text style={[type.small, { width: 78, textAlign: "right", color: color.ink3 }]}>{d === 0 ? `same as ${vs}` : `${d > 0 ? "▲" : "▼"} ${compact(Math.abs(d), "money")}`}</Text>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}

/** Joined (up, green) vs moved out (down, red) per month. */
export function FlowBars({ items, focus, onFocus, onHover, progress }: { items: { key: string; label: string; up: number; down: number }[]; focus: string; onFocus: (k: string) => void; onHover?: (k: string | null) => void; progress: number }) {
  const max = Math.max(1, ...items.flatMap((i) => [i.up, i.down]));
  const H = 56;
  return (
    <View style={{ flexDirection: "row", gap: space(1) }}>
      {items.map((it) => {
        const on = it.key === focus;
        return (
          <Pressable key={it.key} onPress={() => onFocus(it.key)} onHoverIn={() => onHover?.(it.key)} onHoverOut={() => onHover?.(null)} style={{ flex: 1, alignItems: "center" }}
            accessibilityLabel={`${it.label}: ${it.up} joined, ${it.down} left`}>
            <Text style={[type.small, { fontSize: 11, color: color.ok, fontWeight: "600", height: 16 }]}>{it.up ? `+${it.up}` : ""}</Text>
            <View style={{ height: H, justifyContent: "flex-end" }}>
              <View style={{ width: 14, height: Math.max(it.up ? 4 : 0, (it.up / max) * H * progress), backgroundColor: on ? color.ok : "#9fd1b6", borderTopLeftRadius: 5, borderTopRightRadius: 5 }} />
            </View>
            <View style={{ height: 1.5, alignSelf: "stretch", backgroundColor: on ? color.ink : color.line }} />
            <View style={{ height: H }}>
              <View style={{ width: 14, height: Math.max(it.down ? 4 : 0, (it.down / max) * H * progress), backgroundColor: on ? color.bad : "#eab3ad", borderBottomLeftRadius: 5, borderBottomRightRadius: 5 }} />
            </View>
            <Text style={[type.small, { fontSize: 11, color: color.bad, fontWeight: "600", height: 16 }]}>{it.down ? `-${it.down}` : ""}</Text>
            <Text style={[type.small, { fontSize: 11, color: on ? color.ink : color.ink3, fontWeight: on ? "700" : "500" }]}>{items.length <= 8 || on || (items.length - 1 - items.indexOf(it)) % 2 === 0 ? it.label : " "}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

export function Chip({ on, onPress, children }: { on: boolean; onPress: () => void; children: ReactNode }) {
  return (
    <Pressable onPress={onPress} accessibilityRole="button" accessibilityState={{ selected: on }}
      style={{ paddingHorizontal: 14, height: 34, borderRadius: 999, justifyContent: "center", backgroundColor: on ? color.ink : color.cream }}>
      <Text style={[type.label, { fontSize: 13, color: on ? color.bg : color.ink }]}>{children}</Text>
    </Pressable>
  );
}

export const niceKey = (k: string) => {
  const s = k.replace(/_/g, " ").toLowerCase().replace(/^\w/, (c) => c.toUpperCase());
  return s.replace(/\bupi\b/i, "UPI");
};
