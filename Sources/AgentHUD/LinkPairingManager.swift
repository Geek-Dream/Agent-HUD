import Foundation

actor LinkPairingManager {
    private let devices: LinkDeviceStore
    private var current: PairingSession?
    private var attempts = 0
    private let maximumAttempts = 5

    init(devices: LinkDeviceStore) {
        self.devices = devices
    }

    func createSession() throws -> PairingSession {
        let session = PairingSession(
            id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            secret: try LinkRandom.token(),
            code: try LinkRandom.code(),
            expiresAt: Date().addingTimeInterval(120)
        )
        current = session
        attempts = 0
        return session
    }

    func completeQr(sessionId: String?, secret: String?, deviceName: String?) async throws -> IssuedDeviceToken? {
        guard let current,
              constantTimeEqual(current.id, sessionId),
              constantTimeEqual(current.secret, secret) else {
            registerFailure()
            return nil
        }
        guard current.expiresAt > Date(), attempts < maximumAttempts else {
            self.current = nil
            return nil
        }
        let issued = try await devices.issueToken(deviceName: deviceName)
        self.current = nil
        attempts = 0
        return issued
    }

    func completeCode(code: String?, deviceName: String?) async throws -> IssuedDeviceToken? {
        let normalized = (code ?? "").filter(\.isNumber)
        guard let current, constantTimeEqual(current.code, normalized) else {
            registerFailure()
            return nil
        }
        guard current.expiresAt > Date(), attempts < maximumAttempts else {
            self.current = nil
            return nil
        }
        let issued = try await devices.issueToken(deviceName: deviceName)
        self.current = nil
        attempts = 0
        return issued
    }

    private func registerFailure() {
        attempts += 1
        if attempts >= maximumAttempts {
            current = nil
        }
    }
}
