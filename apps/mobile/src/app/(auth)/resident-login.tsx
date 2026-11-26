import { router, useLocalSearchParams } from "expo-router";
import { useState } from "react";
import { Pressable, Text } from "react-native";
import { ArrowLeft } from "phosphor-react-native";
import { Body, Button, ErrorBox, Field, Screen, Title } from "@/components/ui";
import { api } from "@/lib/api";
import { DEMO } from "@/demo"; // DEMO-MODE
import { DemoHint } from "@/demo/demo-entry"; // DEMO-MODE
import { useSession } from "@/lib/session";
import { color, space, type } from "@/lib/theme";

/** Resident sign-in: mobile number -> 6-digit code sent to the registered email -> in. */
export default function ResidentLogin() {
  const { signInWithTokens } = useSession();
  const { mode } = useLocalSearchParams<{ mode?: string }>();
  const [phone, setPhone] = useState("");
  const [otp, setOtp] = useState("");
  const [step, setStep] = useState<"phone" | "otp" | "password">(mode === "password" ? "password" : "phone");
  const [password, setPassword] = useState("");
  const [sentTo, setSentTo] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const digits = phone.replace(/\D/g, "").slice(-10);
  const isEmail = phone.includes("@");
  const identifier = isEmail ? phone.trim().toLowerCase() : digits;

  async function requestCode() {
    setBusy(true); setError(null);
    try {
      const d = await api<{ email_masked?: string }>("/auth/resident/login/otp/request", { method: "POST", json: { phone: digits }, auth: false });
      setSentTo(d.email_masked ?? "your email");
      setStep("otp");
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  async function passwordLogin() {
    setBusy(true); setError(null);
    try {
      const d = await api<{ access_token: string; refresh_token: string }>("/auth/login", { method: "POST", json: { identifier, password, client_type: "resident_mobile" }, auth: false });
      await signInWithTokens(d.access_token, d.refresh_token, "resident_mobile");
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  async function verify() {
    setBusy(true); setError(null);
    try {
      const d = await api<{ access_token: string; refresh_token: string }>("/auth/resident/login/otp/verify", { method: "POST", json: { phone: digits, otp }, auth: false });
      await signInWithTokens(d.access_token, d.refresh_token, "resident_mobile");
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  return (
    <Screen narrow>
      <Pressable onPress={() => (step === "otp" ? setStep("phone") : router.back())} hitSlop={12} style={{ marginTop: space(3) }} accessibilityLabel="Back">
        <ArrowLeft size={24} color={color.ink} />
      </Pressable>
      {step === "phone" ? (
        <>
          <Title sub="We'll send a 6-digit code to the email on your account.">Welcome back</Title>
          {DEMO && <DemoHint login="0000000000" password="0000000000" onUse={() => { setPhone("0000000000"); setPassword("0000000000"); setStep("password"); }} />}{/* DEMO-MODE */}
          <Field label="Mobile number" value={phone} onChangeText={setPhone} keyboardType="phone-pad" autoComplete="tel" textContentType="telephoneNumber" maxLength={14} autoFocus />
          {error ? <ErrorBox message={error} /> : null}
          <Button title="Send code" onPress={requestCode} loading={busy} disabled={digits.length !== 10} style={{ marginTop: space(2) }} />
          <Pressable onPress={() => { setError(null); setStep("password"); }} style={{ marginTop: space(5), alignSelf: "center" }}>
            <Text style={[type.label, { color: color.ink }]}>Use password instead</Text>
          </Pressable>
        </>
      ) : step === "password" ? (
        <>
          <Title sub="Sign in with your mobile number or email and your password.">Welcome back</Title>
          {DEMO && <DemoHint login="0000000000" password="0000000000" onUse={() => { setPhone("0000000000"); setPassword("0000000000"); setStep("password"); }} />}{/* DEMO-MODE */}
          <Field label="Mobile or email" value={phone} onChangeText={setPhone} autoCapitalize="none" keyboardType="email-address" autoComplete="username" textContentType="username" maxLength={120} />
          <Field label="Password" value={password} onChangeText={setPassword} secureTextEntry autoComplete="password" textContentType="password" onSubmitEditing={passwordLogin} />
          {error ? <ErrorBox message={error} /> : null}
          <Button title="Sign in" onPress={passwordLogin} loading={busy} disabled={(!isEmail && digits.length !== 10) || password.length < 4} style={{ marginTop: space(2) }} />
          <Pressable onPress={() => router.push(isEmail ? { pathname: "/set-password", params: { email: identifier } } : "/set-password")} style={{ marginTop: space(5), alignSelf: "center" }}>
            <Text style={[type.label, { color: color.ink }]}>Set or forgot password?</Text>
          </Pressable>
          <Pressable onPress={() => { setError(null); setStep("phone"); }} style={{ marginTop: space(5), alignSelf: "center" }}>
            <Text style={[type.label, { color: color.ink }]}>Use a code instead</Text>
          </Pressable>
        </>
      ) : (
        <>
          <Title sub={`Enter the code we sent to ${sentTo}.`}>Check your email</Title>
          <Field label="6-digit code" value={otp} onChangeText={(t) => setOtp(t.replace(/\D/g, "").slice(0, 6))} keyboardType="number-pad" autoComplete="one-time-code" textContentType="oneTimeCode" autoFocus style={{ letterSpacing: 8, fontSize: 22 } as never} />
          {error ? <ErrorBox message={error} /> : null}
          <Button title="Sign in" onPress={verify} loading={busy} disabled={otp.length !== 6} style={{ marginTop: space(2) }} />
          <Pressable onPress={requestCode} style={{ marginTop: space(5), alignSelf: "center" }}>
            <Text style={[type.label, { color: color.ink }]}>Send a new code</Text>
          </Pressable>
        </>
      )}
      <Body muted style={{ marginTop: space(8), textAlign: "center" }}>
        Added by your PG? Check your email for a code, then tap &quot;Set or forgot password&quot;. Joining a new PG? Choose &quot;Join a home&quot; on the first screen.
      </Body>
    </Screen>
  );
}
