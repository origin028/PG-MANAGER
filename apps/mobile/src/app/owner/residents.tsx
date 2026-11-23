import { router, useFocusEffect } from "expo-router";
import { useCallback, useMemo, useState } from "react";
import { TextInput, View } from "react-native";
import { MagnifyingGlass, Plus, UserCheck, Users } from "phosphor-react-native";
import { Header, Initials, ListRow, SmallButton, nice } from "@/components/kit";
import { Badge, Body, Card, Empty, ErrorBox, LoadingCards, Screen, Segmented, statusTone } from "@/components/ui";
import { listOf } from "@/lib/owner";
import { color, radius, space } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type R = { id: string; full_name: string; phone: string; room_number?: string; bed_number?: string; status: string; kyc_status?: string };

export default function ResidentsTab() {
  const [status, setStatus] = useState("ACTIVE");
  const [q, setQ] = useState("");
  const list = useData<{ items: R[] }>(`/residents?status=${status}&page_size=100`);
  const pending = useData<{ items: unknown[] }>("/residents/pending-approvals");
  const reloadList = list.reload;
  const reloadPending = pending.reload;
  useFocusEffect(useCallback(() => { reloadList(); reloadPending(); }, [reloadList, reloadPending]));

  const items = useMemo(() => {
    const all = listOf<R>(list.data as never);
    const t = q.trim().toLowerCase();
    return t ? all.filter((r) => r.full_name.toLowerCase().includes(t) || r.phone.includes(t) || (r.room_number ?? "").includes(t)) : all;
  }, [list.data, q]);
  const waiting = listOf(pending.data as never).length;

  return (
    <Screen onRefresh={() => { list.reload(); pending.reload(); }} refreshing={list.refreshing}>
      <Header back={false} title="Residents" action={<SmallButton label="Add" icon={<Plus size={16} color={color.bg} weight="bold" />} onPress={() => router.push("/manage/add-resident")} />} />
      {waiting ? (
        <Card tone="black" onPress={() => router.push("/manage/approvals")} style={{ flexDirection: "row", alignItems: "center", gap: space(3), marginBottom: space(4) }}>
          <UserCheck size={26} color={color.bg} />
          <Body style={{ color: color.bg, flex: 1 }}>{waiting} new {waiting === 1 ? "sign-up" : "sign-ups"} waiting for approval</Body>
        </Card>
      ) : null}
      <View style={{ flexDirection: "row", alignItems: "center", gap: space(2), backgroundColor: color.card, borderRadius: radius.md, borderWidth: 1, borderColor: color.line, paddingHorizontal: space(4), height: 50, marginBottom: space(3) }}>
        <MagnifyingGlass size={18} color={color.ink3} />
        <TextInput value={q} onChangeText={setQ} placeholder="Search name, phone or room" placeholderTextColor={color.ink3} style={{ flex: 1, fontSize: 16, color: color.ink }} />
      </View>
      <Segmented value={status} onChange={setStatus} options={[{ value: "ACTIVE", label: "Living here" }, { value: "NOTICE_PERIOD", label: "On notice" }, { value: "CHECKED_OUT", label: "Moved out" }]} />
      <View style={{ height: space(3) }} />
      {list.loading ? <LoadingCards /> : list.error ? <ErrorBox message={list.error} onRetry={list.reload} /> : items.length ? (
        <Card style={{ paddingVertical: space(1) }}>
          {items.map((r) => (
            <ListRow key={r.id} leading={<Initials name={r.full_name} />} title={r.full_name}
              sub={`${r.room_number ? `Room ${r.room_number} · Bed ${r.bed_number}` : "No bed"} · ${r.phone}`}
              right={r.kyc_status && r.kyc_status !== "VERIFIED" ? <Badge label={`KYC ${nice(r.kyc_status).toLowerCase()}`} tone={statusTone(r.kyc_status)} /> : undefined}
              onPress={() => router.push({ pathname: "/manage/resident/[id]", params: { id: r.id } })} />
          ))}
        </Card>
      ) : <Empty icon={<Users size={44} color={color.ink} weight="light" />} title={q ? "No matches" : "No residents here"} />}
    </Screen>
  );
}
