# AgentHUD Mobile

Flutter Android/iOS client for the read-only AgentHUD LAN protocol. The protocol contract lives in `docs/lan-monitoring.md`.

## Android download

`.github/workflows/android-apk.yml` generates a test-signed APK on every main/feature-branch push and on version tags.

- Open **Actions → Android APK → a successful build → AgentHUD-Android** to download the APK as an Actions artifact.
- Version-tagged builds also attach `app-release.apk` to the matching GitHub Release.
- The APK is intended for local testing. Android may require allowing installation from unknown sources. A public production release still needs a dedicated signing keystore.

iOS is distributed separately through TestFlight; GitHub does not provide an unsigned, directly installable IPA.

## Implemented

- QR pairing with one-time secrets and expiry checks
- IP + port + six-digit verification-code pairing
- Certificate fingerprint pinning after pairing
- Device tokens stored with `flutter_secure_storage`
- Device list and local token removal
- Session list, status/provider filters, detail view
- Four-second polling with manual refresh and pull-to-refresh
- Privacy-mode indicator

Not yet implemented: mDNS discovery, WebSocket events, background push, and any control operation.

## Generate platform projects

Flutter, Dart, and Android SDK are not installed on the current development machine. After installing Flutter 3.24 or newer:

```bash
cd mobile
flutter create . --platforms=android,ios
flutter pub get
flutter test
```

`flutter create` generates the standard Android and iOS runners without replacing the protocol code in `lib/`.

## Android permissions

Add to `android/app/src/main/AndroidManifest.xml` inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
```

Keep cleartext traffic disabled. The app uses HTTPS with certificate fingerprint pinning.

Run on a real device:

```bash
flutter run
```

## iOS permissions

Add to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>用于扫描 AgentHUD 配对二维码</string>
<key>NSLocalNetworkUsageDescription</key>
<string>用于连接同一局域网内的 AgentHUD 电脑</string>
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

Use a real device to validate camera pairing and Local Network permission. iOS may suspend LAN connections in the background; the current app refreshes when it returns to the foreground.

## First connection

1. Open `手机关联` in Windows AgentHUD.
2. Allow the service only on a **private** Windows firewall profile.
3. Scan the QR code, or enter the displayed IP, dynamic port, and six-digit code.
4. Confirm that sessions appear within five seconds.

If pairing fails, check Wi-Fi client isolation, VPN interfaces, firewall rules, and whether the phone and computer are on the same LAN.
