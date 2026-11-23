import { Image } from "expo-image";
import { router } from "expo-router";
import { Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Button } from "@/components/ui";
import { useWide } from "@/lib/layout";
import { color, radius, space, type } from "@/lib/theme";

const HERO = "https://images.unsplash.com/photo-1617325247661-675ab4b64ae2?w=1400&h=1600&fit=crop&auto=format&q=75";

function Brand() {
  return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: space(2.5) }}>
      <View style={{ width: 30, height: 30, borderRadius: 9, backgroundColor: color.ink, alignItems: "center", justifyContent: "flex-end" }}>
        <View style={{ width: 12, height: 16, borderTopLeftRadius: 6, borderTopRightRadius: 6, backgroundColor: color.bg }} />
      </View>
      <Text style={[type.label, { fontSize: 17, color: color.ink }]}>Origin Living</Text>
    </View>
  );
}

function Actions() {
  return (
    <View style={{ gap: space(3) }}>
      <Button title="I live here" onPress={() => router.push("/resident-login")} />
      <Button title="Join a home" variant="secondary" onPress={() => router.push("/join")} />
      <Button title="Owner or kitchen login" variant="ghost" onPress={() => router.push("/owner-login")} />
    </View>
  );
}

export default function Welcome() {
  const wide = useWide();
  if (wide) {
    // Desktop: photo on the left, sign-in choices on the right.
    return (
      <View style={{ flex: 1, flexDirection: "row", backgroundColor: color.bg }}>
        <View style={{ flex: 1.1, padding: space(6) }}>
          <View style={{ flex: 1, borderRadius: radius.lg + 12, overflow: "hidden", backgroundColor: color.cream }}>
            <Image source={HERO} style={{ flex: 1 }} contentFit="cover" transition={400} accessibilityLabel="A bright, furnished bedroom" />
          </View>
        </View>
        <View style={{ flex: 1, justifyContent: "center", paddingHorizontal: space(16) }}>
          <View style={{ maxWidth: 440, width: "100%", gap: space(8) }}>
            <Brand />
            <View>
              <Text style={{ fontSize: 64, lineHeight: 64, fontWeight: "700", letterSpacing: -2.6, color: color.ink }}>Live well.{"\n"}Pay once.</Text>
              <Text style={[type.body, { color: color.ink3, marginTop: space(4), fontSize: 18, lineHeight: 26 }]}>Your rent, meals, complaints and room. Owners run the whole PG from here too.</Text>
            </View>
            <Actions />
          </View>
        </View>
      </View>
    );
  }
  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: color.bg }}>
      <View style={{ flex: 1, padding: space(5), gap: space(5) }}>
        <Brand />
        <View style={{ flex: 1, borderRadius: radius.lg + 8, overflow: "hidden", backgroundColor: color.cream }}>
          <Image source={HERO} style={{ flex: 1 }} contentFit="cover" transition={400} accessibilityLabel="A bright, furnished bedroom" />
        </View>
        <View>
          <Text style={[type.hero, { color: color.ink }]}>Live well.{"\n"}Pay once.</Text>
          <Text style={[type.body, { color: color.ink3, marginTop: space(2) }]}>Your rent, meals, complaints and room, in one app.</Text>
        </View>
        <Actions />
      </View>
    </SafeAreaView>
  );
}
