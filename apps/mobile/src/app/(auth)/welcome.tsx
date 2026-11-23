import { Image } from "expo-image";
import { router } from "expo-router";
import { Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Button } from "@/components/ui";
import { color, radius, space, type } from "@/lib/theme";

const HERO = "https://images.unsplash.com/photo-1617325247661-675ab4b64ae2?w=1200&h=1500&fit=crop&auto=format&q=75";

export default function Welcome() {
  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: color.bg }}>
      <View style={{ flex: 1, padding: space(5), gap: space(5) }}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: space(2.5) }}>
          <View style={{ width: 30, height: 30, borderRadius: 9, backgroundColor: color.ink, alignItems: "center", justifyContent: "flex-end" }}>
            <View style={{ width: 12, height: 16, borderTopLeftRadius: 6, borderTopRightRadius: 6, backgroundColor: color.bg }} />
          </View>
          <Text style={[type.label, { fontSize: 17, color: color.ink }]}>Origin Living</Text>
        </View>
        <View style={{ flex: 1, borderRadius: radius.lg + 8, overflow: "hidden", backgroundColor: color.cream }}>
          <Image source={HERO} style={{ flex: 1 }} contentFit="cover" transition={400} accessibilityLabel="A bright, furnished bedroom" />
        </View>
        <View>
          <Text style={[type.hero, { color: color.ink }]}>Live well.{"\n"}Pay once.</Text>
          <Text style={[type.body, { color: color.ink3, marginTop: space(2) }]}>Your rent, meals, complaints and room, in one app.</Text>
        </View>
        <View style={{ gap: space(3) }}>
          <Button title="I live here" onPress={() => router.push("/resident-login")} />
          <Button title="Join a home" variant="secondary" onPress={() => router.push("/join")} />
          <Button title="Owner login" variant="ghost" onPress={() => router.push("/owner-login")} />
        </View>
      </View>
    </SafeAreaView>
  );
}
