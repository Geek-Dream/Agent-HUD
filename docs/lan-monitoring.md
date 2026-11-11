# AgentHUD LAN Monitoring Protocol

Version: **1**  
Scope: **read-only monitoring over a private LAN**

This document is the compatibility contract for the Windows, Flutter, and future macOS implementations. Do not add control operations to version 1; `capabilities` currently contains only `monitor`.

## Transport

- HTTPS with a per-installation self-signed certificate.
- Clients pin the hex-encoded SHA-256 certificate fingerprint.
- The Windows service listens on a dynamically assigned port on LAN interfaces.
- `addresses` in pairing responses contains IPv4 addresses without a URL scheme. Clients construct `https://ADDRESS:PORT`.
- REST JSON uses camelCase property names and ISO-8601 timestamps.
- The first mobile implementation polls every 3–5 seconds. A later version may add sequenced WebSocket events without changing the REST snapshot format.

## Pairing

A pairing session lasts two minutes, allows at most five failures, and is invalidated after one success. Creating a new session invalidates the previous one.

### QR payload

The QR image contains a JSON object:

```json
{
  "v": 1,
  "instanceId": "windows-instance-id",
  "instanceName": "WL-PC",
  "addresses": ["192.168.1.5"],
  "port": 61051,
  "fingerprint": "UPPERCASE_SHA256_HEX",
  "sessionId": "one-time-session-id",
  "secret": "one-time-128-bit-or-stronger-secret",
  "expiresAt": "2026-11-12T01:00:00+08:00"
}
```

The QR secret is single-use and is never a long-lived device token.

Complete pairing:

```http
POST /v1/pair/complete
Content-Type: application/json

{
  "sessionId": "one-time-session-id",
  "secret": "one-time-secret",
  "deviceName": "Pixel 9"
}
```

### Verification-code pairing

The Windows dialog also displays a six-digit code. Mobile clients may accept separators such as `123-456`; the server ignores non-digits.

```http
POST /v1/pair/verify-code
Content-Type: application/json

{
  "code": "123456",
  "deviceName": "iPhone"
}
```

### Pairing response

```json
{
  "deviceId": "device-id",
  "token": "new-long-lived-device-token",
  "instanceId": "windows-instance-id",
  "instanceName": "WL-PC",
  "protocol": 1,
  "capabilities": ["monitor"],
  "fingerprint": "UPPERCASE_SHA256_HEX",
  "addresses": ["192.168.1.5"],
  "port": 61051
}
```

Store the token only in Windows Credential Manager, iOS Keychain, or Android Keystore. The Windows server stores only a SHA-256 token hash. Do not log tokens or QR payloads.

## Authentication

All non-pairing endpoints require:

```http
Authorization: Bearer DEVICE_ID.TOKEN
```

Invalid, expired, revoked, or missing credentials return `401` with:

```json
{ "error": "unauthorized" }
```

## Status

```http
GET /v1/status
```

Response fields:

- `protocol`: protocol version, currently `1`
- `instanceId`, `instanceName`
- `capabilities`: currently `["monitor"]`
- `revision`: monotonically increasing snapshot revision
- `scannedAt`: last local log scan, nullable
- `serverTime`
- `privacyMode`
- `fingerprint`, `addresses`, `port`

## Session list

```http
GET /v1/sessions?status=Working&provider=Codex&limit=50
```

Filters are optional and case-insensitive. `limit` is clamped to 1–100.

Response:

```json
{
  "revision": 42,
  "scannedAt": "2026-11-12T01:00:00+08:00",
  "sessions": [
    {
      "id": "hmac-derived-public-id",
      "provider": "Codex",
      "status": "Working",
      "confidence": "High",
      "title": "Example task",
      "projectName": "ProjectAlias",
      "currentAction": "Running tests",
      "currentFiles": ["Program.cs"],
      "startedAt": "2026-11-12T00:00:00+08:00",
      "lastActivityAt": "2026-11-12T01:00:00+08:00",
      "completedAt": null,
      "isLive": true,
      "gitBranch": "main",
      "gitChangedFiles": 1,
      "gitInsertions": 2,
      "gitDeletions": 0,
      "summary": "Latest run summary"
    }
  ]
}
```

## Session detail

```http
GET /v1/sessions/{id}
```

Returns the same object as the list item or `404` with `session_not_found`.

## Privacy contract

The service never returns `ProjectPath`, `SourcePath`, `LatestUserPrompt`, raw JSONL, images, or credentials.

When Windows privacy mode is enabled:

- Titles and project names are replaced with privacy placeholders.
- Current files, Git metadata, and summaries are omitted.
- Status, counts, and timestamps may still be returned.

## Compatibility requirements for macOS

The macOS implementation must provide the same JSON contract, pairing state machine, token hashing, public session-ID derivation, and privacy behavior. It should reuse the Swift session model as an input adapter rather than changing mobile DTOs.

Mobile clients must not depend on Windows-specific file formats, certificate stores, or device names. Protocol additions require a new `protocol` version or backward-compatible optional fields.
