import * as ImagePicker from "expo-image-picker";
import { Platform } from "react-native";

export type Picked = { uri: string; name: string; type: string };

/** Opens the camera (or library) and returns a compressed JPEG ready for upload. */
export async function pickImage(source: "camera" | "library", front = false): Promise<Picked | null> {
  const opts: ImagePicker.ImagePickerOptions = { mediaTypes: ["images"], quality: 0.7, allowsEditing: false, cameraType: front ? ImagePicker.CameraType.front : ImagePicker.CameraType.back };
  if (source === "camera" && Platform.OS !== "web") {
    const perm = await ImagePicker.requestCameraPermissionsAsync();
    if (!perm.granted) throw new Error("Camera permission is needed. You can also choose from your photos.");
  }
  const res = source === "camera" && Platform.OS !== "web" ? await ImagePicker.launchCameraAsync(opts) : await ImagePicker.launchImageLibraryAsync(opts);
  if (res.canceled || !res.assets?.[0]) return null;
  const a = res.assets[0];
  const isPng = (a.mimeType ?? "").includes("png");
  return { uri: a.uri, name: a.fileName ?? `photo.${isPng ? "png" : "jpg"}`, type: a.mimeType ?? (isPng ? "image/png" : "image/jpeg") };
}

/** Appends a picked file to FormData on native (uri object) and web (Blob). */
export async function appendFile(form: FormData, field: string, f: Picked) {
  const ext = f.type.includes("png") ? "png" : f.type.includes("pdf") ? "pdf" : "jpg";
  const name = `${field}.${ext}`;
  if (Platform.OS === "web") {
    const blob = await (await fetch(f.uri)).blob();
    form.append(field, blob, name);
  } else {
    form.append(field, { uri: f.uri, name, type: f.type } as unknown as Blob);
  }
}
