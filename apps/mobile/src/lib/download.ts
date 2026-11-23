import { Directory, File, Paths } from "expo-file-system";
import * as Sharing from "expo-sharing";
import { Platform } from "react-native";
import { API_URL, tokenStore } from "./api";

/**
 * Downloads a protected file (receipt PDF, CSV export) with the user's token.
 * Browser: saves it like any download. Phone: saves to cache and opens the share sheet
 * (Save to Files, WhatsApp, email...).
 */
export async function downloadProtected(path: string, filename: string, mimeType: string) {
  const t = await tokenStore.get();
  const headers: Record<string, string> = t ? { Authorization: `Bearer ${t.access}` } : {};
  const url = `${API_URL}/api/v1${path}`;
  if (Platform.OS === "web") {
    const res = await fetch(url, { headers });
    if (!res.ok) throw new Error("Download failed. Please try again.");
    const href = URL.createObjectURL(await res.blob());
    const a = document.createElement("a");
    a.href = href; a.download = filename; a.click();
    URL.revokeObjectURL(href);
    return;
  }
  const dir = new Directory(Paths.cache, "downloads");
  dir.create({ idempotent: true });
  const file = await File.downloadFileAsync(url, new File(dir, filename), { headers, idempotent: true });
  if (await Sharing.isAvailableAsync()) await Sharing.shareAsync(file.uri, { mimeType, dialogTitle: filename });
}
