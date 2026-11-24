import { router } from "expo-router";
import { useState } from "react";
import { Pressable, Text } from "react-native";
import { ArrowLeft } from "phosphor-react-native";
import { Button, ErrorBox, Field, Screen, Title } from "@/components/ui";
import { api } from "@/lib/api";
import { useSession } from "@/lib/session";
import { color, space, type } from "@/lib/theme";

export default function OwnerLogin() {
  const { signInWithTokens } = useSession();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setBusy(true); setError(null);
    try {
      const d = await api<{ access_token: string; refresh_token: string }>("/auth/login", {
        method: "POST", auth: false,
        json: { identifier: email.trim(), password, client_type: "admin_mobile" },
      });
      await signInWithTokens(d.access_token, d.refresh_token, "admin_mobile");
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  return (
    <Screen narrow>
      <Pressable onPress={() => router.back()} hitSlop={12} style={{ marginTop: space(3) }} accessibilityLabel="Back">
        <ArrowLeft size={24} color={color.ink} />
      </Pressable>
      <Title sub="Owners and kitchen staff sign in here.">Staff login</Title>
      <Field label="Email or mobile" value={email} onChangeText={setEmail} autoCapitalize="none" keyboardType="email-address" autoComplete="email" textContentType="username" />
      <Field label="Password" value={password} onChangeText={setPassword} secureTextEntry autoComplete="password" textContentType="password" onSubmitEditing={submit} />
      {error ? <ErrorBox message={error} /> : null}
      <Button title="Sign in" onPress={submit} loading={busy} disabled={!email || password.length < 4} style={{ marginTop: space(2) }} />
      <Pressable onPress={() => router.push(email.includes("@") ? { pathname: "/set-password", params: { email: email.trim() } } : "/set-password")} style={{ marginTop: space(5), alignSelf: "center" }}>
        <Text style={[type.label, { color: color.ink }]}>Forgot password?</Text>
      </Pressable>
    </Screen>
  );
}
