import { router, useLocalSearchParams } from "expo-router";
import { useEffect, useState } from "react";
import { Pressable, Text, View } from "react-native";
import { ArrowLeft, CheckCircle } from "phosphor-react-native";
import { Body, Button, ErrorBox, Field, Screen, Title } from "@/components/ui";
import { api } from "@/lib/api";
import { color, space, type } from "@/lib/theme";

/**
 * One screen for both: a new resident setting their first password (code from the welcome email)
 * and anyone who forgot their password. Email -> 6-digit code -> new password.
 */
export default function SetPassword() {
  const params = useLocalSearchParams<{ email?: string }>();
  const [email, setEmail] = useState(params.email ?? "");
  const [step, setStep] = useState<"email" | "code" | "done">("email");
  const [code, setCode] = useState("");
  const [pw, setPw] = useState("");
  const [pw2, setPw2] = useState("");
  const [wait, setWait] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (wait <= 0) return;
    const t = setTimeout(() => setWait((w) => w - 1), 1000);
    return () => clearTimeout(t);
  }, [wait]);

  const cleanEmail = email.trim().toLowerCase();
  const emailOk = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail);
  const rules = [
    { ok: pw.length >= 8, label: "At least 8 characters" },
    { ok: /[A-Za-z]/.test(pw) && /\d/.test(pw), label: "A letter and a number" },
    { ok: pw.length > 0 && pw === pw2, label: "Both passwords match" },
  ];

  async function sendCode() {
    setBusy(true); setError(null);
    try {
      await api("/auth/change-password/request-otp", { method: "POST", json: { email: cleanEmail }, auth: false });
      setStep("code"); setWait(60);
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  async function save() {
    setBusy(true); setError(null);
    try {
      await api("/auth/change-password/reset-with-otp", { method: "POST", json: { email: cleanEmail, otp: code, new_password: pw }, auth: false });
      setStep("done");
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  return (
    <Screen narrow>
      <Pressable onPress={() => (step === "code" ? setStep("email") : router.back())} hitSlop={12} style={{ marginTop: space(3) }} accessibilityLabel="Back">
        <ArrowLeft size={24} color={color.ink} />
      </Pressable>

      {step === "email" ? (
        <>
          <Title sub="New here and got a welcome email? Or forgot your password? Start with your email.">Set your password</Title>
          <Field label="Email" value={email} onChangeText={setEmail} autoCapitalize="none" keyboardType="email-address" autoComplete="email" textContentType="username" autoFocus />
          {error ? <ErrorBox message={error} /> : null}
          <Button title="Email me a code" onPress={sendCode} loading={busy} disabled={!emailOk} style={{ marginTop: space(2) }} />
          <Pressable onPress={() => { setError(null); setStep("code"); }} disabled={!emailOk} style={{ marginTop: space(5), alignSelf: "center", opacity: emailOk ? 1 : 0.4 }}>
            <Text style={[type.label, { color: color.ink }]}>I already have a code</Text>
          </Pressable>
        </>
      ) : step === "code" ? (
        <>
          <Title sub={`Enter the 6-digit code sent to ${cleanEmail}, then choose your password.`}>Check your email</Title>
          <Field label="6-digit code" value={code} onChangeText={(t) => setCode(t.replace(/\D/g, "").slice(0, 6))} keyboardType="number-pad" autoComplete="one-time-code" textContentType="oneTimeCode" autoFocus style={{ letterSpacing: 8, fontSize: 22 } as never} />
          <Field label="New password" value={pw} onChangeText={setPw} secureTextEntry autoComplete="new-password" textContentType="newPassword" />
          <Field label="Type it again" value={pw2} onChangeText={setPw2} secureTextEntry autoComplete="new-password" textContentType="newPassword" onSubmitEditing={save} />
          <View style={{ gap: space(1.5), marginBottom: space(4) }}>
            {rules.map((r) => (
              <View key={r.label} style={{ flexDirection: "row", alignItems: "center", gap: space(2) }}>
                <CheckCircle size={18} weight={r.ok ? "fill" : "regular"} color={r.ok ? color.ok : color.ink3} />
                <Body muted={!r.ok} style={{ fontSize: 14 }}>{r.label}</Body>
              </View>
            ))}
          </View>
          {error ? <ErrorBox message={error} /> : null}
          <Button title="Set password" onPress={save} loading={busy} disabled={code.length !== 6 || !rules.every((r) => r.ok)} style={{ marginTop: space(2) }} />
          <Pressable onPress={sendCode} disabled={wait > 0 || busy} style={{ marginTop: space(5), alignSelf: "center", opacity: wait > 0 ? 0.4 : 1 }}>
            <Text style={[type.label, { color: color.ink }]}>{wait > 0 ? `Send a new code in ${wait}s` : "Send a new code"}</Text>
          </Pressable>
          <Body muted style={{ marginTop: space(6), textAlign: "center", fontSize: 13 }}>No email? Check spam, or ask your PG to check the email address on your account.</Body>
        </>
      ) : (
        <View style={{ alignItems: "center", gap: space(3), marginTop: space(12) }}>
          <CheckCircle size={64} weight="fill" color={color.ok} />
          <Text style={[type.h1, { color: color.ink, textAlign: "center" }]}>Password set</Text>
          <Body muted style={{ textAlign: "center" }}>Sign in with your email or mobile number and your new password.</Body>
          <Button title="Sign in" onPress={() => router.replace("/resident-login?mode=password")} style={{ alignSelf: "stretch", marginTop: space(4) }} />
          <Button title="I'm the owner or staff" variant="ghost" onPress={() => router.replace("/owner-login")} style={{ alignSelf: "stretch" }} />
        </View>
      )}
    </Screen>
  );
}
