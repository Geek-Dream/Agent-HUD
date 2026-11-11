# macOS LAN monitoring implementation

The Swift implementation uses the same protocol as Windows (`docs/lan-monitoring.md`).

## Components

- `LinkModels.swift`: protocol DTOs, secure random values, constant-time comparisons
- `LinkDeviceStore.swift`: persistent instance identity, per-device token hashes, public session IDs
- `LinkPairingManager.swift`: two-minute, five-attempt, single-use pairing sessions
- `LinkCertificate.swift`: self-signed PEM certificate generation through `/usr/bin/openssl`
- `LinkServer.swift`: Vapor HTTPS routes and NIOSSL certificate configuration
- `LinkSettingsWindow.swift`: QR pairing dialog and device revocation
- `HUDViewModel.swift`: privacy-filtered monitoring snapshot adapter

## Build and test on macOS

macOS 14+ and a Swift 5.10+ toolchain are required. The current development host is Windows, so these steps have not been executed here.

```bash
swift package resolve
swift build
./scripts/test.sh
```

`Package.swift` adds Vapor and NIOSSL. SwiftPM downloads them during the first build.

The first launch generates a self-signed certificate with the system OpenSSL/LibreSSL tool and stores the private key with owner-only file permissions in the per-user Application Support directory. A production follow-up should move private-key storage into Keychain.

The menu-bar menu includes `手机关联…`, which opens the QR and device-management window.

## Compatibility notes

- REST routes, pairing payloads, token format, session DTOs, and privacy behavior match Windows.
- The macOS service tries ports 47653–47662 rather than the Windows dynamic port.
- The mobile app reads the actual port from the pairing response; no fixed port is required.
- `Tests/LinkTests.swift` adds pairing, token revocation, and identity-persistence coverage to the existing smoke-test executable.
