import Foundation

func testLinkCertificateFingerprintAndStatusProtocol() throws {
    try expect(AgentStatus.waitingUser.protocolValue == "WaitingUser", "Waiting status must match the mobile protocol")
    try expect(AgentStatus.working.protocolValue == "Working", "Working status must match the mobile protocol")

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("AgentHUD-CertificateTests-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    let certificate = try LinkCertificate.loadOrCreate(directory: directory)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
    process.arguments = [
        "x509", "-in", certificate.certificateURL.path, "-outform", "DER"
    ]
    let standardOutput = Pipe()
    process.standardOutput = standardOutput
    try process.run()
    let der = try standardOutput.fileHandleForReading.readToEnd() ?? Data()
    process.waitUntilExit()
    try expect(process.terminationStatus == 0, "Test certificate must convert to DER")
    try expect(certificate.fingerprint == der.sha256Hex(), "Certificate fingerprint must hash DER, not PEM")
    let pemFingerprint = try Data(contentsOf: certificate.certificateURL).sha256Hex()
    try expect(
        certificate.fingerprint != pemFingerprint,
        "Certificate test must distinguish PEM and DER bytes"
    )
}

func testLinkPairing() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("AgentHUD-LinkTests-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let store = try LinkDeviceStore(directory: directory)
    let manager = LinkPairingManager(devices: store)
    let firstSession = try await manager.createSession()
    let wrongCode = firstSession.code == "000000" ? "000001" : "000000"
    for _ in 0..<5 {
        let rejected = try await manager.completeCode(code: wrongCode, deviceName: "测试手机")
        try expect(rejected == nil, "Wrong pairing code must be rejected")
    }
    let locked = try await manager.completeCode(code: firstSession.code, deviceName: "测试手机")
    try expect(locked == nil, "Pairing must be locked after five failures")

    let session = try await manager.createSession()
    let issued = try await manager.completeQr(
        sessionId: session.id,
        secret: session.secret,
        deviceName: "测试手机"
    )
    try expect(issued != nil, "Valid QR pairing should issue a device token")
    let device = issued!.device
    let token = issued!.token
    let valid = await store.validate(deviceId: device.id, token: token)
    try expect(valid, "Newly issued device token should validate")

    let reused = try await manager.completeQr(
        sessionId: session.id,
        secret: session.secret,
        deviceName: "另一台手机"
    )
    try expect(reused == nil, "QR secrets must be single use")

    let instanceId = store.instanceId
    let publicId = store.publicSessionId(rawId: "session-one")
    let reloaded = try LinkDeviceStore(directory: directory)
    try expect(reloaded.instanceId == instanceId, "Instance identity should survive reload")
    try expect(reloaded.publicSessionId(rawId: "session-one") == publicId, "Public session IDs should be stable")
    try expect(publicId.count == 32, "Public session IDs should contain 16 bytes of hex")

    let revoked = await store.revoke(deviceId: device.id)
    try expect(revoked, "Paired device should be revocable")
    let validAfterRevoke = await store.validate(deviceId: device.id, token: token)
    try expect(!validAfterRevoke, "Revoked device token must stop working")
}
