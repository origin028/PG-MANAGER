import { useState } from "react";
import { Platform, Share, View } from "react-native";
import { Export } from "phosphor-react-native";
import { Divider, Header } from "@/components/kit";
import { Body, Button, Card, ErrorBox, H2, LoadingCards, Row, Screen, Segmented } from "@/components/ui";
import { API_URL, tokenStore } from "@/lib/api";
import { useProperties } from "@/lib/owner";
import { color, rupees, space } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Occ = { total_beds: number; occupied_beds: number; available_beds: number; occupancy_rate_percent: number };
type Fin = { gross_collections: number; total_expenses: number; net_operating_profit: number; pending_rent: number; collections_by_mode: Record<string, number>; payment_count: number; expense_count: number };

async function exportCsv(path: string, filename: string) {
  const t = await tokenStore.get();
  const res = await fetch(`${API_URL}/api/v1${path}`, { headers: t ? { Authorization: `Bearer ${t.access}` } : {} });
  if (!res.ok) throw new Error("Export failed.");
  const text = await res.text();
  if (Platform.OS === "web") {
    const url = URL.createObjectURL(new Blob([text], { type: "text/csv" }));
    const a = document.createElement("a");
    a.href = url; a.download = filename; a.click();
    URL.revokeObjectURL(url);
  } else {
    await Share.share({ title: filename, message: text });
  }
}

export default function Reports() {
  const { props, current, setCurrent } = useProperties();
  const occ = useData<Occ>(current ? `/reports/occupancy?property_id=${current}` : null);
  const fin = useData<Fin>("/reports/financial");
  const [error, setError] = useState<string | null>(null);
  const run = (p: string, f: string) => exportCsv(p, f).catch((e) => setError((e as Error).message));

  return (
    <Screen onRefresh={() => { occ.reload(); fin.reload(); }} refreshing={fin.refreshing}>
      <Header title="Reports" />
      {props.length > 1 ? <View style={{ marginBottom: space(3) }}><Segmented value={current ?? ""} onChange={setCurrent} options={props.map((p) => ({ value: p.id, label: p.name }))} /></View> : null}
      {error ? <ErrorBox message={error} /> : null}
      <H2 style={{ marginTop: 0 }}>Occupancy</H2>
      {occ.loading ? <LoadingCards n={1} /> : occ.data ? (
        <Card style={{ paddingVertical: space(2) }}>
          <Row label="Beds" value={String(occ.data.total_beds)} /><Divider />
          <Row label="Occupied" value={String(occ.data.occupied_beds)} /><Divider />
          <Row label="Free" value={String(occ.data.available_beds)} /><Divider />
          <Row label="Occupancy" value={`${Math.round(occ.data.occupancy_rate_percent)}%`} />
        </Card>
      ) : null}
      <H2>Money</H2>
      {fin.loading ? <LoadingCards n={1} /> : fin.data ? (
        <Card style={{ paddingVertical: space(2) }}>
          <Row label="Collected" value={rupees(fin.data.gross_collections)} /><Divider />
          {Object.entries(fin.data.collections_by_mode ?? {}).map(([m, v]) => <Row key={m} label={`   by ${m.toLowerCase().replace("_", " ")}`} value={rupees(v)} />)}
          <Row label="Spent" value={rupees(fin.data.total_expenses)} /><Divider />
          <Row label="Profit" value={rupees(fin.data.net_operating_profit)} /><Divider />
          <Row label="Rent pending" value={rupees(fin.data.pending_rent)} />
        </Card>
      ) : null}
      <H2>Export to Excel</H2>
      <Body muted style={{ marginBottom: space(3) }}>CSV files open in Excel and Google Sheets.</Body>
      <View style={{ gap: space(2) }}>
        <Button title="Payments (CSV)" variant="secondary" icon={<Export size={18} color={color.ink} />} onPress={() => run(`/reports/payments/export${current ? `?property_id=${current}` : ""}`, "payments.csv")} />
        {current ? <Button title="Occupancy (CSV)" variant="secondary" icon={<Export size={18} color={color.ink} />} onPress={() => run(`/reports/occupancy/export?property_id=${current}`, "occupancy.csv")} /> : null}
      </View>
    </Screen>
  );
}
