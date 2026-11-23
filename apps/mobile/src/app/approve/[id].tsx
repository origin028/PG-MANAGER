import { Image } from "expo-image";
import { router, useLocalSearchParams } from "expo-router";
import { useCallback, useEffect, useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { X } from "phosphor-react-native";
import { Body, Button, Card, ErrorBox, Field, H2, Row, Screen, Segmented, Skeleton } from "@/components/ui";
import type { Pending } from "@/app/owner/approvals";
import { api } from "@/lib/api";
import { fmtDate } from "@/lib/dates";
import { loadProtectedImage } from "@/lib/owner";
import { color, radius, rupees, space, type } from "@/lib/theme";

type Bed = { id: string; room_id: string; room_number?: string; bed_number: string; monthly_rent?: number };
const DOCS = [
  ["aadhaar_front", "Aadhaar front"], ["aadhaar_back", "Aadhaar back"], ["pan_card", "PAN"], ["passport", "Passport"], ["resident_selfie", "Selfie"],
] as const;

function KycDoc({ residentId, doc, label, onMissing }: { residentId: string; doc: string; label: string; onMissing: () => void }) {
  const [uri, setUri] = useState<string | null | undefined>(undefined);
  useEffect(() => {
    loadProtectedImage(`/residents/${residentId}/kyc-document/${doc}`).then(setUri).catch(() => { setUri(null); onMissing(); });
  }, [residentId, doc, onMissing]);
  if (uri === null) return null; // not provided for this verification method
  return (
    <View style={{ width: 220, gap: space(2) }}>
      {uri ? <Image source={uri} style={{ width: 220, height: 150, borderRadius: radius.md, backgroundColor: color.cream }} contentFit="cover" /> : <Skeleton w={220} h={150} r={radius.md} />}
      <Body muted>{label}</Body>
    </View>
  );
}

export default function Approve() {
  const { id, data } = useLocalSearchParams<{ id: string; data?: string }>();
  const p = data ? (JSON.parse(data) as Pending) : null;
  const [beds, setBeds] = useState<Bed[] | null>(null);
  const [bedId, setBedId] = useState<string>("");
  const [rent, setRent] = useState("");
  const [deposit, setDeposit] = useState("");
  const [reason, setReason] = useState("");
  const [mode, setMode] = useState<"approve" | "reject">("approve");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [missing, setMissing] = useState(0);
  const onMissing = useCallback(() => setMissing((m) => m + 1), []);

  useEffect(() => {
    if (!p?.property_id) return;
    api<Bed[]>(`/beds?property_id=${p.property_id}&status=AVAILABLE`).then(setBeds).catch(() => setBeds([]));
  }, [p?.property_id]);

  const bed = beds?.find((b) => b.id === bedId);
  const chooseBed = (id: string) => {
    setBedId(id);
    const b = beds?.find((x) => x.id === id);
    if (b?.monthly_rent) setRent(String(b.monthly_rent));
  };

  async function approve() {
    if (!bed) return;
    setBusy(true); setError(null);
    try {
      await api(`/residents/${id}/approve`, { method: "POST", json: { room_id: bed.room_id, bed_id: bed.id, monthly_rent: Number(rent) } });
      if (Number(deposit) > 0) await api(`/residents/${id}/deposit`, { method: "POST", json: { amount: Number(deposit).toFixed(2), note: "Deposit received at joining" } });
      router.back();
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  async function reject() {
    setBusy(true); setError(null);
    try {
      await api(`/residents/${id}/reject`, { method: "POST", json: { reason: reason.trim() } });
      router.back();
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  return (
    <Screen>
      <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginTop: space(4) }}>
        <Text style={[type.h1, { color: color.ink, flex: 1 }]} numberOfLines={1}>{p?.full_name ?? "Resident"}</Text>
        <Pressable onPress={() => router.back()} hitSlop={12} accessibilityLabel="Close"><X size={26} color={color.ink} /></Pressable>
      </View>
      {p ? (
        <Card style={{ paddingVertical: space(2), marginTop: space(4) }}>
          <Row label="Mobile" value={p.phone} />
          <Row label="Email" value={p.email} />
          {p.occupation ? <Row label="Occupation" value={p.occupation} /> : null}
          {p.date_of_birth ? <Row label="Born" value={fmtDate(p.date_of_birth)} /> : null}
          {p.emergency_contact ? <Row label="Emergency" value={p.emergency_contact} /> : null}
          <Row label="Home" value={p.property_name} />
        </Card>
      ) : null}

      <H2>Documents</H2>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: space(3) }}>
        {DOCS.map(([doc, label]) => <KycDoc key={doc} residentId={id} doc={doc} label={label} onMissing={onMissing} />)}
      </ScrollView>
      {missing === DOCS.length ? <Body muted>No documents uploaded. Ask the resident to sign up again from the app.</Body> : null}

      <View style={{ marginTop: space(7) }}>
        <Segmented value={mode} onChange={setMode} options={[{ value: "approve", label: "Approve" }, { value: "reject", label: "Reject" }]} />
      </View>

      {mode === "approve" ? (
        <>
          <H2>Assign a bed</H2>
          {beds === null ? <Skeleton h={40} /> : beds.length ? (
            <Segmented value={bedId} onChange={chooseBed} options={beds.map((b) => ({ value: b.id, label: `Room ${b.room_number ?? "?"} · ${b.bed_number}` }))} />
          ) : <Body muted>No free beds in this home. Free a bed first.</Body>}
          <View style={{ height: space(4) }} />
          <Field label="Monthly rent (₹)" value={rent} onChangeText={(t) => setRent(t.replace(/\D/g, ""))} keyboardType="number-pad" />
          <Field label="Deposit received (₹)" value={deposit} onChangeText={(t) => setDeposit(t.replace(/\D/g, ""))} keyboardType="number-pad" hint={Number(deposit) > 0 ? `They get ${rupees(Number(deposit) / 2)} back when they leave.` : "Leave empty if not collected yet."} />
          {error ? <ErrorBox message={error} /> : null}
          <Button title="Approve and assign bed" onPress={approve} loading={busy} disabled={!bed || Number(rent) <= 0} style={{ marginTop: space(2) }} />
        </>
      ) : (
        <>
          <View style={{ height: space(4) }} />
          <Field label="Reason (sent to the applicant)" value={reason} onChangeText={setReason} multiline placeholder="e.g. Aadhaar photo is not readable" />
          {error ? <ErrorBox message={error} /> : null}
          <Button title="Reject application" variant="danger" onPress={reject} loading={busy} disabled={reason.trim().length < 5} />
        </>
      )}
    </Screen>
  );
}
