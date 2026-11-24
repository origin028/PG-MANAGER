import { router, useFocusEffect } from "expo-router";
import { useCallback, useState } from "react";
import { Linking, Pressable, Text, View } from "react-native";
import { LockSimple, Phone } from "phosphor-react-native";
import { Body, Button, Card, Screen } from "@/components/ui";
import { api } from "@/lib/api";
import { useSession } from "@/lib/session";
import { color, space, type } from "@/lib/theme";

type Portal = { enabled: boolean; reason: string | null; kyc_status: string; kyc_submitted: boolean; kyc_notes?: string | null };
type Person = { name: string; role: string; phone: string };
type Contacts = { property_name: string; property_phone?: string | null; property_manager?: Person | null; staff_contacts?: Person[] };

/** Shown to a resident whose app access is off: why, what to do, who to call. */
export default function AccessPaused() {
  const { signOut } = useSession();
  const [p, setP] = useState<Portal | null>(null);
  const [c, setC] = useState<Contacts | null>(null);
  const [checking, setChecking] = useState(false);

  const load = useCallback(async () => {
    setChecking(true);
    try {
      const portal = await api<Portal>("/resident/portal");
      if (portal.enabled) { router.replace("/resident"); return; }
      setP(portal);
      setC(await api<Contacts>("/resident/property-contacts").catch(() => null));
    } catch { /* keep what we have */ } finally { setChecking(false); }
  }, []);
  useFocusEffect(useCallback(() => { load(); }, [load]));

  const kyc = p?.reason === "KYC_OVERDUE";
  const needsKyc = !!p && p.kyc_status !== "VERIFIED" && (!p.kyc_submitted || p.kyc_status === "REJECTED");
  const people = [c?.property_manager, ...(c?.staff_contacts ?? [])].filter((x): x is Person => !!x?.phone).slice(0, 3);
  const call = (n: string) => Linking.openURL(`tel:${n}`).catch(() => {});

  return (
    <Screen narrow>
      <View style={{ alignItems: "center", marginTop: space(14), gap: space(3) }}>
        <View style={{ width: 72, height: 72, borderRadius: 36, backgroundColor: color.ink, alignItems: "center", justifyContent: "center" }}>
          <LockSimple size={34} color={color.bg} weight="bold" />
        </View>
        <Text style={[type.h1, { color: color.ink, textAlign: "center" }]}>App access paused</Text>
        <Body muted style={{ textAlign: "center", maxWidth: 330 }}>
          {!p ? " " : kyc
            ? needsKyc ? "Your KYC wasn't finished in time. Add your details and ID photos; once your PG verifies them, the app opens again."
              : "Your documents are with your PG for checking. The app opens again as soon as they verify them."
            : "Your PG has paused your access to the app. Please contact them."}
        </Body>
        {p?.kyc_status === "REJECTED" && p.kyc_notes ? (
          <Card tone="cream" style={{ alignSelf: "stretch", gap: space(1) }}>
            <Text style={[type.label, { color: color.bad }]}>Your PG asked you to send it again</Text>
            <Body>{p.kyc_notes}</Body>
          </Card>
        ) : null}
      </View>

      <View style={{ gap: space(3), marginTop: space(8) }}>
        {needsKyc ? <Button title="Finish your KYC" onPress={() => router.push("/complete-kyc")} /> : null}
        <Button title="Check again" variant="secondary" onPress={load} loading={checking} />
      </View>

      {people.length || c?.property_phone ? (
        <Card style={{ marginTop: space(6), paddingVertical: space(2) }}>
          <Text style={[type.label, { color: color.ink3, marginTop: space(2), marginBottom: space(1) }]}>Contact {c?.property_name ?? "your PG"}</Text>
          {c?.property_phone ? <ContactRow name="Front desk" phone={c.property_phone} onCall={call} /> : null}
          {people.map((x) => <ContactRow key={x.phone} name={`${x.name} · ${x.role.toLowerCase().replace(/_/g, " ")}`} phone={x.phone} onCall={call} />)}
        </Card>
      ) : null}

      <Button title="Sign out" variant="ghost" onPress={signOut} style={{ marginTop: space(6) }} />
    </Screen>
  );
}

function ContactRow({ name, phone, onCall }: { name: string; phone: string; onCall: (n: string) => void }) {
  return (
    <Pressable onPress={() => onCall(phone)} style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", paddingVertical: space(3) }} accessibilityLabel={`Call ${name}`}>
      <View style={{ flexShrink: 1 }}>
        <Text style={[type.label, { color: color.ink }]}>{name}</Text>
        <Body muted style={{ fontSize: 14 }}>{phone}</Body>
      </View>
      <Phone size={22} color={color.ink} />
    </Pressable>
  );
}
