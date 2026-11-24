/**
 * Phone alerts for owners (new sign-ups, KYC sent, access paused).
 * Registers this phone with the API so the server can send Expo push notifications, and opens the
 * right screen when an alert is tapped. Silently does nothing on the web, on simulators, when the
 * owner says no, or before the app is linked to an Expo (EAS) project.
 */
import Constants from "expo-constants";
import * as Device from "expo-device";
import * as Notifications from "expo-notifications";
import { AndroidImportance } from "expo-notifications";
import { router } from "expo-router";
import { Platform } from "react-native";
import { api } from "./api";

let registered = false;

export async function registerOwnerPhone(): Promise<void> {
  if (registered || Platform.OS === "web" || !Device.isDevice) return;
  try {
    Notifications.setNotificationHandler({
      handleNotification: async () => ({ shouldShowBanner: true, shouldShowList: true, shouldPlaySound: true, shouldSetBadge: true }),
    });
    if (Platform.OS === "android") {
      await Notifications.setNotificationChannelAsync("alerts", { name: "Alerts", importance: AndroidImportance.HIGH });
    }
    const current = await Notifications.getPermissionsAsync();
    const granted = current.granted || (await Notifications.requestPermissionsAsync()).granted;
    if (!granted) return;
    const projectId = Constants.expoConfig?.extra?.eas?.projectId ?? Constants.easConfig?.projectId;
    if (!projectId) return; // set up once the Expo/EAS project exists (see docs/DEPLOY.md)
    const { data: token } = await Notifications.getExpoPushTokenAsync({ projectId });
    await api("/notifications/device-token", { method: "POST", json: { device_token: token, platform: Platform.OS, device_name: Device.deviceName ?? undefined } });
    Notifications.addNotificationResponseReceivedListener((r) => {
      const link = r.notification.request.content.data?.link;
      if (typeof link === "string" && link.startsWith("/")) router.push(link as never);
    });
    registered = true;
  } catch {
    // Alerts still appear in the in-app inbox (bell) even without push.
  }
}
