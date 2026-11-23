import { Platform, useWindowDimensions } from "react-native";

/** Desktop browser layout: sidebar navigation and wider content. Phones and tablets keep the app layout. */
export function useWide() {
  const { width } = useWindowDimensions();
  return Platform.OS === "web" && width >= 1024;
}
export const CONTENT_MAX = 1120;
