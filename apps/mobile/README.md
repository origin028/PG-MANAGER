# Origin Living app (iOS, Android, web)

One Expo app with two modes, chosen by who signs in:

- **Resident**: OTP login, online KYC signup, rent by UPI, weekly food menu, report issues, deposit and stay details.
- **Owner**: Face ID lock, today's numbers, approvals with KYC review, confirm UPI payments (UTR), resolve issues, attendance, announcements.

## Run it on your Mac

```bash
cd apps/mobile
npm install
EXPO_PUBLIC_API_URL=http://<your-Mac-LAN-IP>:8000 npx expo start
```

- **On your phone**: install *Expo Go*, scan the QR code (phone and Mac on the same Wi-Fi).
- **iPhone simulator**: install Xcode from the App Store, then press `i`.
- **Browser**: press `w`.

The API must be running (`make dev` from the repo root). For phone testing, start it with `--host 0.0.0.0`.
In development, OTP codes are printed in the API log instead of being emailed.

## Build for release

```bash
npx eas-cli@latest build -p android --profile preview   # installable APK
npx eas-cli@latest build -p ios                          # needs an Apple Developer account
```

Set `EXPO_PUBLIC_API_URL` to the production API and `EXPO_PUBLIC_WEB_URL` to the web dashboard before building.
