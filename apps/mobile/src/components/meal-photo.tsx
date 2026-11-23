import { Image } from "expo-image";
import { useEffect, useState } from "react";
import { loadProtectedImage } from "@/lib/owner";
import { color, radius } from "@/lib/theme";

/** A meal's photo (served only to people in that home). `version` forces a reload after upload. */
export function MealPhoto({ menuId, height = 170, version = 0 }: { menuId: string; height?: number; version?: number }) {
  const [uri, setUri] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    loadProtectedImage(`/food-menus/${menuId}/image`).then((u) => alive && setUri(u)).catch(() => alive && setUri(null));
    return () => { alive = false; };
  }, [menuId, version]);
  if (!uri) return null;
  return <Image source={uri} style={{ width: "100%", height, borderRadius: radius.md, backgroundColor: color.cream }} contentFit="cover" transition={250} />;
}
