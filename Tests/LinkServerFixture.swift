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
    var dispatcher: AgentInputDispatcher?
    var conversationSession: AgentSession?

    func refreshMonitoringSnapshot() async {
        snapshot.refresh()
    }

    func sendMessage(
        sessionID: String,
        clientMessageId: String,
        text: String
    ) async -> (deliveryId: String, status: AgentDeliveryStatus, error: AgentDeliveryError?) {
        guard let dispatcher, let conversationSession else {
            return ("", .failed, .providerUnsupported)
        }
        return dispatcher.dispatch(
            clientMessageId: clientMessageId,
            text: text,
            to: conversationSession,
            publicSessionId: sessionID
        )
    }

    func deliveryStatus(deliveryId: String) async -> (status: AgentDeliveryStatus, error: AgentDeliveryError?)? {
        dispatcher?.status(deliveryId: deliveryId)
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
    var provider = FixtureSnapshotProvider()
    let environment = ProcessInfo.processInfo.environment
    let conversationThread = environment["HUD_E2E_THREAD_ID"]
    let conversationRollout = environment["HUD_E2E_ROLLOUT"]
    if let conversationThread, let conversationRollout {
        provider.dispatcher = AgentInputDispatcher(
            registry: AgentRuntimeRegistry(),
            deliveryStore: DeliveryStore(),
            adapters: [CodexInputAdapter()]
        )
        provider.conversationSession = AgentSession(
            id: "codex:\(conversationThread)",
            provider: .codex,
            providerSessionID: conversationThread,
            projectName: "hud-link-e2e",
            projectPath: "/tmp/hud-link-e2e/work",
            title: "联调测试",
            titleSource: .automatic,
            status: .idle,
            confidence: .high,
            currentAction: "等待输入",
            currentFiles: [],
            startedAt: Date(),
            lastActivityAt: Date(),
            completedAt: nil,
            runs: [],
            latestUserPrompt: nil,
            sourcePath: conversationRollout,
            isLive: true,
            git: nil
        )
    }
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
        "ipv6Address": "::1",
        "port": offer.port,
        "fingerprint": offer.fingerprint,
        "conversation": conversationThread != nil,
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
        // 请求文件由测试端先截断再写入，轮询可能正好读到空文件；不能因此 fatal。
        if let data = try? Data(contentsOf: requestOutput), !data.isEmpty,
           let object = try? JSONSerialization.jsonObject(with: data),
           let result = object as? [String: Any],
           let request = result["request"] as? Int, request > handledRequest {
            handledRequest = request
            if result["enableConversation"] as? Bool == true,
               let deviceId = result["deviceId"] as? String {
                await server.setConversationEnabled(deviceId: deviceId, enabled: true)
                try Data("ready\n".utf8).write(
                    to: URL(fileURLWithPath: output.path + ".conversationReady"),
                    options: .atomic
                )
                print("FIXTURE_CONVERSATION_READY")
                fflush(stdout)
                continue
            }
            guard let deviceId = result["deviceIdToRevoke"] as? String else {
                try await Task.sleep(for: .milliseconds(50))
                continue
            }
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
