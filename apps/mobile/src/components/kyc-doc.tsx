import { Image } from "expo-image";
import { useEffect, useState } from "react";
import { View } from "react-native";
import { Body, Skeleton } from "@/components/ui";
import { loadProtectedImage } from "@/lib/owner";
import { color, radius, space } from "@/lib/theme";

/** One KYC document, fetched with the owner's token and decrypted server-side. Hidden if not uploaded. */
export function KycDoc({ residentId, doc, label, onMissing }: { residentId: string; doc: string; label: string; onMissing: () => void }) {
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

