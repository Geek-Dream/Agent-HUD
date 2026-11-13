import CryptoKit
import Foundation

actor LinkDeviceStore {
    private struct Identity: Codable {
        let id: String
        let name: String
        let key: String
    }

    let instanceId: String
    let instanceName: String
    private let instanceKey: Data
    private let devicesURL: URL
    private var devices: [String: LinkedDevice] = [:]

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        devicesURL = directory.appendingPathComponent("devices.json")
        let identityURL = directory.appendingPathComponent("identity.json")
        let identity = try Self.loadIdentity(from: identityURL)
        instanceId = identity.id
        instanceName = identity.name
        guard let key = Data(base64Encoded: identity.key) else {
            throw NSError(domain: "AgentHUD.Link.Identity", code: 1)
        }
        instanceKey = key
        devices = try Self.loadDevices(from: devicesURL)
    }

    static func defaultDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("AgentHUD/link", isDirectory: true)
    }

    var allDevices: [LinkedDevice] {
        devices.values.sorted {
            ($0.lastSeenAt ?? $0.pairedAt) > ($1.lastSeenAt ?? $1.pairedAt)
        }
    }

    func issueToken(deviceName: String?) throws -> IssuedDeviceToken {
        let id = try LinkRandom.token(12)
        let token = try LinkRandom.token()
        let normalized = Self.normalizedName(deviceName)
        let device = LinkedDevice(
            id: id,
            name: normalized,
            tokenHash: Self.hash(token: token),
            pairedAt: Date(),
            lastSeenAt: nil
        )
        devices[id] = device
        try save()
        return IssuedDeviceToken(device: device, token: token)
    }

    func validate(deviceId: String, token: String) -> Bool {
        guard let device = devices[deviceId],
              constantTimeEqual(device.tokenHash, Self.hash(token: token)) else {
            return false
        }
        if device.lastSeenAt == nil || Date().timeIntervalSince(device.lastSeenAt!) > 60 {
            devices[deviceId]?.lastSeenAt = Date()
            try? save()
        }
        return true
    }

    func device(deviceId: String) -> LinkedDevice? {
        devices[deviceId]
    }

    func setConversationEnabled(deviceId: String, enabled: Bool) -> Bool {
        guard devices[deviceId] != nil else { return false }
        devices[deviceId]?.conversationEnabled = enabled
        try? save()
        return true
    }

    @discardableResult
    func revoke(deviceId: String) -> Bool {
        guard devices.removeValue(forKey: deviceId) != nil else {
            return false
        }
        try? save()
        return true
    }

    nonisolated func publicSessionId(rawId: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(rawId.utf8),
            using: SymmetricKey(data: instanceKey)
        )
        return Data(mac).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func hash(token: String) -> String {
        Data(token.utf8).sha256Hex()
    }

    private static func normalizedName(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed?.isEmpty == false ? trimmed! : "手机"
        return String(name.prefix(80))
    }

    private static func loadIdentity(from url: URL) throws -> Identity {
        if let data = try? Data(contentsOf: url),
           let identity = try? JSONDecoder().decode(Identity.self, from: data) {
            return identity
        }
        let identity = Identity(
            id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            name: Host.current().name ?? "Mac",
            key: Data(try LinkRandom.bytes(32)).base64EncodedString()
        )
        try JSONEncoder().encode(identity).write(to: url, options: .atomic)
        return identity
    }

    private static func loadDevices(from url: URL) throws -> [String: LinkedDevice] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let values = try JSONDecoder().decode([LinkedDevice].self, from: data)
        return Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
    }

    private func save() throws {
        let values = devices.values.sorted { $0.pairedAt < $1.pairedAt }
        try JSONEncoder().encode(values).write(to: devicesURL, options: .atomic)
    }
}
