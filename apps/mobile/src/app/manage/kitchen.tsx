import { useState } from "react";
import { Switch, Text, View } from "react-native";
import { CookingPot, Plus } from "phosphor-react-native";
import { Header, ListRow, SmallButton, confirmAction, digits } from "@/components/kit";
import { Badge, Body, Button, Card, ErrorBox, Field, H2, LoadingCards, Screen } from "@/components/ui";
import { api } from "@/lib/api";
import { color, space, type } from "@/lib/theme";
import { useData } from "@/lib/use-data";

type Staff = { id: string; name: string; username: string; phone: string; is_active: boolean };
type Settings = { enabled: boolean; staff: Staff[] };

/** Owner switch for the optional kitchen module, plus kitchen app logins. */
export default function KitchenSettings() {
  const s = useData<Settings>("/kitchen/settings");
  const [add, setAdd] = useState<{ full_name: string; username: string; phone: string; password: string } | null>(null);
  const [reset, setReset] = useState<{ id: string; password: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  async function run(fn: () => Promise<unknown>, done?: string) {
    setBusy(true); setError(null); setNotice(null);
    try { await fn(); s.reload(); if (done) setNotice(done); } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  const toggle = (on: boolean) => on
    ? run(() => api("/kitchen/settings", { method: "PUT", json: { enabled: true } }), "Kitchen is on. Residents now see a meal pass.")
    : confirmAction("Turn the kitchen off?", "Meal passes disappear for residents and kitchen logins stop working until you turn it back on.", "Turn off", () => run(() => api("/kitchen/settings", { method: "PUT", json: { enabled: false } }), "Kitchen is off."));
  const create = () => add && run(async () => { await api("/kitchen/staff", { method: "POST", json: { ...add, phone: digits(add.phone).slice(-10) } }); setAdd(null); }, "Kitchen login created. Share the username and password with them.");
  const setActive = (st: Staff, on: boolean) => run(() => api(`/kitchen/staff/${st.id}`, { method: "PATCH", json: { is_active: on } }));
  const savePassword = () => reset && run(async () => { await api(`/kitchen/staff/${reset.id}`, { method: "PATCH", json: { password: reset.password } }); setReset(null); }, "Password changed. They were signed out everywhere.");

  const d = s.data;
  return (
    <Screen onRefresh={s.reload} refreshing={s.refreshing}>
      <Header title="Kitchen & meal passes" />
      {notice ? <Card tone="cream" style={{ marginBottom: space(3) }}><Body>{notice}</Body></Card> : null}
      {error ? <View style={{ marginBottom: space(3) }}><ErrorBox message={error} /></View> : null}
      {s.loading ? <LoadingCards n={2} /> : d && (
        <>
          <Card style={{ flexDirection: "row", alignItems: "center", gap: space(4) }}>
            <CookingPot size={30} color={color.ink} weight="light" />
            <View style={{ flex: 1 }}>
              <Text style={[type.label, { color: color.ink, fontSize: 16 }]}>Kitchen module</Text>
              <Body muted>{d.enabled ? "On: residents show a QR at meals" : "Off: you manage the menu yourself"}</Body>
            </View>
            <Switch value={d.enabled} onValueChange={toggle} disabled={busy} trackColor={{ true: color.ink, false: color.line }} thumbColor="#ffffff" />
          </Card>
          <Body muted style={{ marginTop: space(3) }}>
            When on, each resident gets a meal pass that changes every minute. Kitchen staff scan it, and each resident can eat each meal once. This stops outsiders taking food.
          </Body>

          {d.enabled ? (
            <>
              <H2>Kitchen logins</H2>
              {add ? (
                <Card style={{ marginBottom: space(3) }}>
                  <Field label="Name" value={add.full_name} onChangeText={(t) => setAdd({ ...add, full_name: t })} />
                  <Field label="Username" value={add.username} onChangeText={(t) => setAdd({ ...add, username: t.replace(/\s/g, "").toLowerCase() })} autoCapitalize="none" hint="They sign in with this or their mobile." />
                  <Field label="Mobile" value={add.phone} onChangeText={(t) => setAdd({ ...add, phone: t })} keyboardType="phone-pad" />
                  <Field label="Password" value={add.password} onChangeText={(t) => setAdd({ ...add, password: t })} hint="At least 6 characters." />
                  <Button title="Create login" onPress={create} loading={busy} disabled={add.full_name.trim().length < 2 || add.username.length < 3 || digits(add.phone).length < 10 || add.password.length < 6} />
                  <Button title="Cancel" variant="ghost" onPress={() => setAdd(null)} />
                </Card>
              ) : <SmallButton label="Add kitchen login" icon={<Plus size={16} color={color.bg} weight="bold" />} onPress={() => setAdd({ full_name: "", username: "", phone: "", password: "" })} />}
              <View style={{ height: space(3) }} />
              {d.staff.length ? (
                <Card style={{ paddingVertical: space(1) }}>
                  {d.staff.map((st) => (
                    <View key={st.id}>
                      <ListRow title={st.name} sub={`${st.username} · ${st.phone}`} right={<Badge label={st.is_active ? "Active" : "Disabled"} tone={st.is_active ? "ok" : "neutral"} />} />
                      {reset?.id === st.id ? (
                        <View style={{ paddingBottom: space(3) }}>
                          <Field label="New password" value={reset.password} onChangeText={(t) => setReset({ ...reset, password: t })} />
                          <Button title="Save password" onPress={savePassword} loading={busy} disabled={reset.password.length < 6} />
                        </View>
                      ) : (
                        <View style={{ flexDirection: "row", gap: space(2), paddingBottom: space(3) }}>
                          <SmallButton label="Reset password" tone="light" onPress={() => setReset({ id: st.id, password: "" })} />
                          <SmallButton label={st.is_active ? "Disable" : "Enable"} tone={st.is_active ? "danger" : "light"} onPress={() => setActive(st, !st.is_active)} />
                        </View>
                      )}
                    </View>
                  ))}
                </Card>
              ) : <Body muted>No kitchen logins yet.</Body>}
            </>
          ) : null}
        </>
      )}
    </Screen>
  );
}
