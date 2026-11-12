import Foundation
import Vapor

private final class LockedFixtureSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 7
    private var refreshValue = 0
    var revision: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    var refreshCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return refreshValue
    }
    func refresh() {
        lock.lock()
        value += 1
        refreshValue += 1
        lock.unlock()
    }
}

@MainActor
struct FixtureSnapshotProvider: LinkSnapshotProviding {
    private let snapshot = LockedFixtureSnapshot()
    var refreshCount: Int { snapshot.refreshCount }

    func refreshMonitoringSnapshot() async {
        snapshot.refresh()
    }

    func monitoringSnapshot() async -> LinkMonitoringSnapshot {
        let revision = snapshot.revision
        return LinkMonitoringSnapshot(
            revision: revision,
            scannedAt: Date(timeIntervalSince1970: 1_800_000_000),
            privacyMode: false,
            sessions: [
                LinkMonitoringSession(
                    id: "codex:waiting",
                    provider: "Codex",
                    status: "WaitingUser",
                    confidence: "High",
                    title: "等待手机测试",
                    projectName: "Agent-HUD",
                    currentAction: revision == 7 ? "等待确认" : "已刷新手机同步",
                    currentFiles: [],
                    startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    lastActivityAt: Date(timeIntervalSince1970: 1_800_000_000),
                    completedAt: nil,
                    isLive: true,
                    gitBranch: "main",
                    gitChangedFiles: 1,
                    gitInsertions: 2,
                    gitDeletions: 0,
                    summary: "局域网集成测试"
                )
            ]
        )
    }
}

func fixtureExpect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw NSError(domain: "AgentHUD.Link.Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

@MainActor
func runLinkServerFixture() async throws {
    guard CommandLine.arguments.count == 3 else {
        throw NSError(domain: "AgentHUD.Link.Fixture", code: 2)
    }
    let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let output = URL(fileURLWithPath: CommandLine.arguments[2])
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let server = try LinkServer(
        directory: directory,
        environment: Environment(name: "testing", arguments: ["fixture", "serve"])
    )
    let provider = FixtureSnapshotProvider()
    try await server.start(provider: provider)
    defer { server.stop() }

    let offer = try await server.createPairingOffer()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
    process.arguments = [
        "x509", "-in", directory.appendingPathComponent("certificate.pem").path,
        "-outform", "DER"
    ]
    let standardOutput = Pipe()
    process.standardOutput = standardOutput
    try process.run()
    let der = try standardOutput.fileHandleForReading.readToEnd() ?? Data()
    process.waitUntilExit()
    try fixtureExpect(process.terminationStatus == 0, "OpenSSL DER conversion failed")
    try fixtureExpect(offer.fingerprint == der.sha256Hex(), "QR fingerprint must match Android DER pinning")

    let payload: [String: Any] = [
        "offer": offer.payload,
        "code": offer.code,
        "address": "127.0.0.1",
        "port": offer.port,
        "fingerprint": offer.fingerprint,
        "expectedSessionId": try LinkDeviceStore(directory: directory).publicSessionId(rawId: "codex:waiting")
    ]
    try JSONSerialization.data(withJSONObject: payload).write(to: output, options: .atomic)
    print("FIXTURE_READY")
    fflush(stdout)

    let revokedOutput = URL(fileURLWithPath: output.path + ".revoked")
    let stopOutput = URL(fileURLWithPath: output.path + ".stop")
    let requestOutput = URL(fileURLWithPath: output.path + ".request")
    var handledRequest = 0
    while !FileManager.default.fileExists(atPath: revokedOutput.path) {
        if FileManager.default.fileExists(atPath: stopOutput.path) {
            throw NSError(domain: "AgentHUD.Link.Fixture", code: 3)
        }
        if let data = try? Data(contentsOf: requestOutput),
           let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let request = result["request"] as? Int, request > handledRequest,
           let deviceId = result["deviceIdToRevoke"] as? String {
            handledRequest = request
            if result["generateCode"] as? Bool == true {
                let codeOffer = try await server.createPairingOffer()
                let codeData = try JSONSerialization.data(withJSONObject: ["code": codeOffer.code])
                try codeData.write(to: URL(fileURLWithPath: output.path + ".code"), options: .atomic)
                try Data("ready\n".utf8).write(to: URL(fileURLWithPath: output.path + ".codeReady"), options: .atomic)
                print("FIXTURE_CODE_READY \(codeOffer.code)")
                fflush(stdout)
                continue
            } else {
                await server.revoke(deviceId: deviceId)
                let devices = await server.devicesSnapshot()
                try fixtureExpect(!devices.contains(where: { $0.id == deviceId }), "Revoked device must be absent from the store")
                try Data("revoked\n".utf8).write(to: revokedOutput, options: .atomic)
            }
            print("FIXTURE_REVOKED")
            fflush(stdout)
            break
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    while !FileManager.default.fileExists(atPath: stopOutput.path) {
        try await Task.sleep(for: .milliseconds(50))
    }
}
