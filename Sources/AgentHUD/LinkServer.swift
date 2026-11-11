import Foundation
import NIOSSL
import Vapor

@MainActor
final class LinkServer {
    private let devices: LinkDeviceStore
    private let pairing: LinkPairingManager
    private let certificate: LinkCertificate
    private var application: Application?
    private var snapshotProvider: LinkSnapshotProviding?

    private(set) var port = 0
    private(set) var lastError: String?

    init(directory: URL? = nil) throws {
        let root = try directory ?? LinkDeviceStore.defaultDirectory()
        devices = try LinkDeviceStore(directory: root)
        pairing = LinkPairingManager(devices: devices)
        certificate = try LinkCertificate.loadOrCreate(directory: root)
    }

    var fingerprint: String { certificate.fingerprint }
    var isRunning: Bool { application != nil }

    func start(provider: LinkSnapshotProviding) async throws {
        guard application == nil else { return }
        snapshotProvider = provider
        var lastError: Error?
        for candidate in 47653..<47663 {
            do {
                let app = try makeApplication(port: candidate)
                configureRoutes(app)
                try app.start()
                application = app
                port = candidate
                self.lastError = nil
                return
            } catch {
                lastError = error
            }
        }
        self.lastError = lastError?.localizedDescription
        throw lastError ?? NSError(domain: "AgentHUD.Link.Server", code: 1)
    }

    func stop() {
        application?.shutdown()
        application = nil
    }

    func createPairingOffer() async throws -> PairingOffer {
        guard isRunning else {
            throw NSError(
                domain: "AgentHUD.Link.Server",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "局域网服务尚未启动，请稍后重试。"]
            )
        }
        let session = try await pairing.createSession()
        let addresses = LinkNetwork.localIPv4Addresses()
        let payload = LinkPairingPayload(
            v: 1,
            instanceId: devices.instanceId,
            instanceName: devices.instanceName,
            addresses: addresses,
            port: port,
            fingerprint: fingerprint,
            sessionId: session.id,
            secret: session.secret,
            expiresAt: session.expiresAt
        )
        let data = try LinkJSON.encoder().encode(payload)
        return PairingOffer(
            code: session.code,
            payload: String(decoding: data, as: UTF8.self),
            expiresAt: session.expiresAt,
            addresses: addresses,
            port: port,
            fingerprint: fingerprint
        )
    }

    func devicesSnapshot() async -> [LinkedDevice] {
        await devices.allDevices
    }

    func revoke(deviceId: String) async {
        await devices.revoke(deviceId: deviceId)
    }

    private func makeApplication(port: Int) throws -> Application {
        let app = Application(.production)
        app.logger.logLevel = .critical
        app.http.server.configuration.hostname = "0.0.0.0"
        app.http.server.configuration.port = port
        let certificate = try NIOSSLCertificate(file: self.certificate.certificateURL.path, format: .pem)
        let privateKey = try NIOSSLPrivateKey(file: self.certificate.privateKeyURL.path, format: .pem)
        app.http.server.configuration.tlsConfiguration = .makeServerConfiguration(
            certificateChain: [.certificate(certificate)],
            privateKey: .privateKey(privateKey)
        )
        return app
    }

    private func configureRoutes(_ app: Application) {
        app.post("v1", "pair", "complete") { request async throws -> Response in
            let input = try request.content.decode(PairCompleteRequest.self)
            guard let issued = try await self.pairing.completeQr(
                sessionId: input.sessionId,
                secret: input.secret,
                deviceName: input.deviceName
            ) else {
                return Self.json(LinkErrorResponse(error: "pairing_failed"), status: .unauthorized)
            }
            return Self.json(self.result(issued), status: .ok)
        }

        app.post("v1", "pair", "verify-code") { request async throws -> Response in
            let input = try request.content.decode(PairVerifyCodeRequest.self)
            guard let issued = try await self.pairing.completeCode(
                code: input.code,
                deviceName: input.deviceName
            ) else {
                return Self.json(LinkErrorResponse(error: "pairing_failed"), status: .unauthorized)
            }
            return Self.json(self.result(issued), status: .ok)
        }

        app.get("v1", "status") { request async throws -> Response in
            guard await self.authorized(request) else {
                return Self.json(LinkErrorResponse(error: "unauthorized"), status: .unauthorized)
            }
            let snapshot = await self.snapshot()
            let response = LinkStatusResponse(
                `protocol`: 1,
                instanceId: self.devices.instanceId,
                instanceName: self.devices.instanceName,
                capabilities: ["monitor"],
                revision: snapshot.revision,
                scannedAt: snapshot.scannedAt,
                serverTime: Date(),
                privacyMode: snapshot.privacyMode,
                fingerprint: self.fingerprint,
                addresses: LinkNetwork.localIPv4Addresses(),
                port: self.port
            )
            return Self.json(response, status: .ok)
        }

        app.get("v1", "sessions") { request async throws -> Response in
            guard await self.authorized(request) else {
                return Self.json(LinkErrorResponse(error: "unauthorized"), status: .unauthorized)
            }
            let snapshot = await self.snapshot()
            let status = request.query[String.self, "status"]
            let provider = request.query[String.self, "provider"]
            let limit = min(max(request.query[Int.self, "limit"] ?? 50, 1), 100)
            let sessions = snapshot.sessions.filter { session in
                (status == nil || session.status.caseInsensitiveCompare(status!) == .orderedSame)
                    && (provider == nil || session.provider.caseInsensitiveCompare(provider!) == .orderedSame)
            }
            let publicSessions = await self.publicSessions(sessions.prefix(limit))
            return Self.json(
                LinkSessionsResponse(
                    revision: snapshot.revision,
                    scannedAt: snapshot.scannedAt,
                    sessions: publicSessions
                ),
                status: .ok
            )
        }

        app.get("v1", "sessions", ":id") { request async throws -> Response in
            guard await self.authorized(request) else {
                return Self.json(LinkErrorResponse(error: "unauthorized"), status: .unauthorized)
            }
            guard let id = request.parameters.get("id") else {
                return Self.json(LinkErrorResponse(error: "session_not_found"), status: .notFound)
            }
            let snapshot = await self.snapshot()
            for session in snapshot.sessions {
                let publicId = await self.devices.publicSessionId(rawId: session.id)
                if publicId.caseInsensitiveCompare(id) == .orderedSame {
                    var publicSession = session
                    publicSession.id = publicId
                    return Self.json(publicSession, status: .ok)
                }
            }
            return Self.json(LinkErrorResponse(error: "session_not_found"), status: .notFound)
        }
    }

    private func snapshot() async -> LinkMonitoringSnapshot {
        await snapshotProvider?.monitoringSnapshot()
            ?? LinkMonitoringSnapshot(revision: 0, scannedAt: nil, privacyMode: false, sessions: [])
    }

    private func result(_ issued: IssuedDeviceToken) -> PairingResult {
        PairingResult(
            deviceId: issued.device.id,
            token: issued.token,
            instanceId: devices.instanceId,
            instanceName: devices.instanceName,
            `protocol`: 1,
            capabilities: ["monitor"],
            fingerprint: fingerprint,
            addresses: LinkNetwork.localIPv4Addresses(),
            port: port
        )
    }

    private func publicSessions(_ sessions: some Sequence<LinkMonitoringSession>) async -> [LinkMonitoringSession] {
        var output: [LinkMonitoringSession] = []
        for session in sessions {
            var copy = session
            copy.id = await devices.publicSessionId(rawId: session.id)
            output.append(copy)
        }
        return output
    }

    private func authorized(_ request: Request) async -> Bool {
        guard let header = request.headers.bearerAuthorization else { return false }
        let credential = header.token
        guard let separator = credential.firstIndex(of: ".") else { return false }
        let deviceId = String(credential[..<separator])
        let token = String(credential[credential.index(after: separator)...])
        return await devices.validate(deviceId: deviceId, token: token)
    }

    private static func json<T: Encodable>(_ value: T, status: HTTPResponseStatus) -> Response {
        do {
            let data = try LinkJSON.encoder().encode(value)
            return Response(
                status: status,
                headers: ["Content-Type": "application/json; charset=utf-8"],
                body: .init(data: data)
            )
        } catch {
            return Response(status: .internalServerError)
        }
    }
}
