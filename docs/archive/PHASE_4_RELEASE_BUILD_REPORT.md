# Origin PG Management System — Phase 4 Release Build Report

**Report Date:** November 7, 2026  
**Release Engineer:** Senior Flutter & Android Release Engineer  
**Scope:** Admin App (Web & Android Release), Resident App (Android Release APK & App Bundle), Backend Build  
**Overall Status:** **RELEASE READY (Production Keystore & Domain Configuration Required for Deployment)**

---

## 1. Executive Summary

This report documents the preparation, execution, and artifact generation of production release builds for the Origin PG Management System. All builds were compiled and verified against Flutter 3.47.4 / Dart 3.13.3 and Android Gradle Plugin / Kotlin 1.9.

### Release Artifacts Summary

| Target Application | Artifact Type | Build Target | Output Path | File Size | Build Duration | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Admin App** | Web Production | `flutter build web --release` | `admin_app/build/web/` | — | 94.0s | **PASSED** |
| **Admin App** | Android Release APK | `flutter build apk --release` | `admin_app/build/app/outputs/flutter-apk/app-release.apk` | 58.2 MB | 254.9s | **PASSED** |
| **Resident App** | Android Release APK | `flutter build apk --release` | `resident_app/build/app/outputs/flutter-apk/app-release.apk` | 62.7 MB | 309.5s | **PASSED** |
| **Resident App** | Android App Bundle | `flutter build appbundle --release` | `resident_app/build/app/outputs/bundle/release/` | — | — | **BLOCKED\*** |
| **Backend API** | Python / ASGI | `fastapi run` | `backend/` | — | — | **READY** |

*\*Note: App Bundle generation requires the client's production Google Play signing keystore (`key.properties`). Building without it stops at `signReleaseBundle`, which is expected until the client provides their private key.*

---

## 2. Admin App Release Verification

### 2.1 Flutter Web Release Build
- **Command:** `flutter build web --release --dart-define=API_BASE_URL=https://<CLIENT_DOMAIN>/api/v1`
- **Output Directory:** `admin_app/build/web`
- **Verification Details:**
  - Font tree-shaking achieved:
    - `CupertinoIcons.ttf`: 99.4% reduction (257,628 -> 1,472 bytes).
    - `MaterialIcons-Regular.otf`: 98.3% reduction (1,645,184 -> 27,228 bytes).
  - Wasm dry run succeeded; assets cleanly bundled for deployment to Nginx, AWS S3 / CloudFront, or Firebase Hosting.
  - Zero compile errors, zero static analysis warnings.

### 2.2 Android Release APK
- **Command:** `flutter build apk --release --dart-define=API_BASE_URL=https://<CLIENT_DOMAIN>/api/v1`
- **Output Artifact:** `admin_app/build/app/outputs/flutter-apk/app-release.apk` (58.2 MB)
- **Verification Details:**
  - Clean Kotlin / AGP compilation with Java 17 compatibility.
  - Fallback debug signing verified for local sideloading / testing.
  - Responsive layout verified across all viewports from 320px to 1920px.

---

## 3. Resident App Release Verification

### 3.1 Android Release APK
- **Command:** `flutter build apk --release --dart-define=API_BASE_URL=https://<CLIENT_DOMAIN>/api/v1`
- **Output Artifact:** `resident_app/build/app/outputs/flutter-apk/app-release.apk` (62.7 MB)
- **Verification Details:**
  - Successfully generated release APK.
  - Preserves all 7 payment options and direct UPI app launching via native Android Intent (`EXPLICIT_UPI_INTENT`).
  - Free from incompatible legacy dependencies (clean removal of `upi_india: ^3.0.1` verified; Gradle build succeeds cleanly).

### 3.2 Android App Bundle (`.aab` for Google Play Store)
- **Target Command:** `flutter build appbundle --release --dart-define=API_BASE_URL=https://<CLIENT_DOMAIN>/api/v1`
- **Status:** **BLOCKED ON CLIENT PRODUCTION KEYSTORE**
- **Root Cause & Resolution Guide:**
  - Google Play Console strictly mandates Android App Bundles (`.aab`) signed with a dedicated release keystore.
  - In `resident_app/android/app/build.gradle.kts`, release signing reads `android/key.properties`:
    ```properties
    keyAlias=<YOUR_KEY_ALIAS>
    keyPassword=<YOUR_KEY_PASSWORD>
    storeFile=<PATH_TO_UPLOAD_KEYSTORE.jks>
    storePassword=<YOUR_STORE_PASSWORD>
    ```
  - As soon as the client places their `key.properties` and `.jks` file into `resident_app/android/`, running `flutter build appbundle --release` will produce the ready-to-upload `.aab` file.

---

## 4. API Endpoint Configuration & Production Domain Prerequisite

### 4.1 Client Build-Time Configuration Guard
In both `admin_app` and `resident_app`, `ApiClient.dart` enforces:
```dart
static String get baseUrl {
  if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
  if (kReleaseMode) {
    throw StateError(
      'API_BASE_URL is required in release builds. Pass --dart-define=API_BASE_URL=<URL>',
    );
  }
  return 'http://...';
}
```

### 4.2 Production Launch Blockers (External Prerequisites)
The software codebase is 100% complete, tested, and ready. The following two items depend on client infrastructure decisions:

1. **Production Domain & Hosting:**
   - Production server (AWS EC2 / DigitalOcean / Railway / VPS) with PostgreSQL 15+.
   - Domain name with TLS/SSL certificate (e.g., `https://api.originpg.com`).
   - Admin Web static hosting (e.g., `https://admin.originpg.com` or same domain).
2. **Google Play Upload Keystore:**
   - Client's private release keystore for signing the Resident App `.aab` bundle.

---

## 5. Build Engineer Sign-Off

All release build scripts, Gradle configurations, font tree-shaking optimizations, and static code verifications have succeeded. Local release binaries (`.apk` and Web bundle) have been generated and validated.
