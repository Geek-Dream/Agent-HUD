import Foundation
import NIOSSL
import Vapor

@MainActor
final class LinkServer {
    private static let capabilities = [
        "monitor", "refresh", "revision", "write", "prompt", "images"
    ]

    private let devices: LinkDeviceStore
    private let pairing: LinkPairingManager
    private let certificate: LinkCertificate
    private let environment: Environment
    private var application: Application?
    private var ipv6Application: Application?
    private var snapshotProvider: LinkSnapshotProviding?

    private(set) var port = 0
    private(set) var lastError: String?

    init(directory: URL? = nil, environment: Environment = .production) throws {
        let root = try directory ?? LinkDeviceStore.defaultDirectory()
        self.environment = environment
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
                let app = try makeApplication(port: candidate, hostname: "0.0.0.0")
                configureRoutes(app)
                try app.start()
                application = app
                let ipv6App = try makeApplication(port: candidate, hostname: "::")
                configureRoutes(ipv6App)
                do {
                    try ipv6App.start()
                    ipv6Application = ipv6App
                } catch {
                    ipv6App.shutdown()
                }
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
        ipv6Application?.shutdown()
        ipv6Application = nil
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
            ipv6Addresses: LinkNetwork.ipv6Addresses(),
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

    private func makeApplication(port: Int, hostname: String) throws -> Application {
        let app = Application(environment)
        app.logger.logLevel = .critical
        app.http.server.configuration.hostname = hostname
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
                capabilities: Self.capabilities,
                revision: snapshot.revision,
                scannedAt: snapshot.scannedAt,
                serverTime: Date(),
                privacyMode: snapshot.privacyMode,
                fingerprint: self.fingerprint,
                addresses: LinkNetwork.localIPv4Addresses(),
                ipv6Addresses: LinkNetwork.ipv6Addresses(),
                port: self.port
            )
            return Self.json(response, status: .ok)
        }

        app.post("v1", "refresh") { request async throws -> Response in
            guard await self.authorized(request) else {
                return Self.json(LinkErrorResponse(error: "unauthorized"), status: .unauthorized)
            }
            await self.snapshotProvider?.refreshMonitoringSnapshot()
            let snapshot = await self.snapshot()
            return Self.json(
                LinkSessionsResponse(
                    revision: snapshot.revision,
                    scannedAt: snapshot.scannedAt,
                    sessions: []
                ),
                status: .ok
            )
        }

        app.get("v1", "sessions") { request async throws -> Response in
            guard await self.authorized(request) else {
                return Self.json(LinkErrorResponse(error: "unauthorized"), status: .unauthorized)
            }
            let snapshot = await self.snapshot()
            let status = request.query[String.self, at: "status"]
            let provider = request.query[String.self, at: "provider"]
            let limit = min(max(request.query[Int.self, at: "limit"] ?? 50, 1), 100)
            let sessions = snapshot.sessions.filter { session in
                (status == nil || session.status.caseInsensitiveCompare(status!) == .orderedSame)
                    && (provider == nil || session.provider.caseInsensitiveCompare(provider!) == .orderedSame)
            }
            let publicSessions = await self.publicSessions(sessions.prefix(limit))
            let etag = try Self.etag(publicSessions)
            if request.headers.first(name: .ifNoneMatch) == etag {
                return Response(status: .notModified, headers: ["ETag": etag])
            }
            return Self.json(
                LinkSessionsResponse(
                    revision: snapshot.revision,
                    scannedAt: snapshot.scannedAt,
                    sessions: publicSessions
                ),
                status: .ok,
                headers: ["ETag": etag]
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

        app.post("v1", "sessions", ":id", "title") { request async throws -> Response in
            guard await self.authorized(request) else {
                return Self.json(LinkErrorResponse(error: "unauthorized"), status: .unauthorized)
            }
            guard let id = request.parameters.get("id") else {
                return Self.json(LinkErrorResponse(error: "session_not_found"), status: .notFound)
            }
            let input = try request.content.decode(LinkTitleRequest.self)
            let normalized = input.title?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard normalized.count <= 72 else {
                return Self.json(LinkErrorResponse(error: "title_too_long"), status: .badRequest)
            }
            let snapshot = await self.snapshot()
            guard let session = await self.session(matchingPublicID: id, in: snapshot) else {
                return Self.json(LinkErrorResponse(error: "session_not_found"), status: .notFound)
            }
            guard let provider = self.snapshotProvider,
                  await provider.setSessionTitle(
                    sessionID: session.id,
                    title: normalized.isEmpty ? nil : normalized
                  ) else {
                return Self.json(LinkErrorResponse(error: "unsupported"), status: .notImplemented)
            }
            let updated = await self.snapshot()
            guard let result = updated.sessions.first(where: { $0.id == session.id }) else {
                return Self.json(LinkErrorResponse(error: "session_not_found"), status: .notFound)
            }
            return Self.json(
                LinkTitleResponse(
                    id: id,
                    title: result.title,
                    titleSource: result.titleSource,
                    hasCustomTitle: result.hasCustomTitle
                ),
                status: .ok
            )
        }

        app.post("v1", "sessions", ":id", "important") { request async throws -> Response in
            guard await self.authorized(request) else {
                return Self.json(LinkErrorResponse(error: "unauthorized"), status: .unauthorized)
            }
            guard let id = request.parameters.get("id") else {
                return Self.json(LinkErrorResponse(error: "session_not_found"), status: .notFound)
            }
            let input = try request.content.decode(LinkImportantRequest.self)
            let snapshot = await self.snapshot()
            guard let session = await self.session(matchingPublicID: id, in: snapshot) else {
                return Self.json(LinkErrorResponse(error: "session_not_found"), status: .notFound)
            }
            guard let provider = self.snapshotProvider,
                  await provider.setSessionImportant(
                    sessionID: session.id,
                    important: input.important
                  ) else {
                return Self.json(LinkErrorResponse(error: "unsupported"), status: .notImplemented)
            }
            let updated = await self.snapshot()
            let isImportant = updated.sessions
                .first(where: { $0.id == session.id })?
                .isImportant ?? input.important
            return Self.json(
                LinkImportantResponse(id: id, isImportant: isImportant),
                status: .ok
            )
        }

        app.get("v1", "sessions", ":id", "images", ":index") { request async throws -> Response in
            guard await self.authorized(request) else {
                return Self.json(LinkErrorResponse(error: "unauthorized"), status: .unauthorized)
            }
            guard let id = request.parameters.get("id"),
                  let indexText = request.parameters.get("index"),
                  let index = Int(indexText), index >= 0 else {
                return Self.json(LinkErrorResponse(error: "image_not_found"), status: .notFound)
            }
            let snapshot = await self.snapshot()
            guard let session = await self.session(matchingPublicID: id, in: snapshot) else {
                return Self.json(LinkErrorResponse(error: "session_not_found"), status: .notFound)
            }
            guard let payload = await self.snapshotProvider?.promptImage(
                sessionID: session.id,
                index: index
            ) else {
                return Self.json(LinkErrorResponse(error: "image_not_found"), status: .notFound)
            }
            var headers = HTTPHeaders()
            headers.replaceOrAdd(name: .contentType, value: payload.contentType)
            headers.replaceOrAdd(name: .cacheControl, value: "private, max-age=300")
            return Response(
                status: .ok,
                headers: headers,
                body: .init(data: payload.data)
            )
        }
    }

    private func session(
        matchingPublicID id: String,
        in snapshot: LinkMonitoringSnapshot
    ) async -> LinkMonitoringSession? {
        for session in snapshot.sessions {
            let publicId = await devices.publicSessionId(rawId: session.id)
            if publicId.caseInsensitiveCompare(id) == .orderedSame {
                return session
            }
        }
        return nil
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
            capabilities: Self.capabilities,
            fingerprint: fingerprint,
            addresses: LinkNetwork.localIPv4Addresses(),
            ipv6Addresses: LinkNetwork.ipv6Addresses(),
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

    private static func etag<T: Encodable>(_ value: T) throws -> String {
        let data = try LinkJSON.encoder().encode(value)
        return "\"\(data.sha256Hex())\""
    }

    private static func json<T: Encodable>(_ value: T, status: HTTPResponseStatus, headers: [String: String] = [:]) -> Response {
        do {
            let data = try LinkJSON.encoder().encode(value)
            var headers = headers
            headers["Content-Type"] = "application/json; charset=utf-8"
            return Response(
                status: status,
                headers: HTTPHeaders(headers.map { ($0.key, $0.value) }),
                body: .init(data: data)
            )
        } catch {
            return Response(status: .internalServerError)
        }
    }
}
