import CryptoKit
import Foundation
import Security

struct LinkedDevice: Codable, Hashable {
    let id: String
    var name: String
    let tokenHash: String
    let pairedAt: Date
    var lastSeenAt: Date?
}

struct IssuedDeviceToken {
    let device: LinkedDevice
    let token: String
}

struct PairingSession {
    let id: String
    let secret: String
    let code: String
    let expiresAt: Date
}

struct PairingOffer {
    let code: String
    let payload: String
    let expiresAt: Date
    let addresses: [String]
    let port: Int
    let fingerprint: String
}

struct PairCompleteRequest: Codable {
    let sessionId: String?
    let secret: String?
    let deviceName: String?
}

struct PairVerifyCodeRequest: Codable {
    let code: String?
    let deviceName: String?
}

struct PairingResult: Codable {
    let deviceId: String
    let token: String
    let instanceId: String
    let instanceName: String
    let `protocol`: Int
    let capabilities: [String]
    let fingerprint: String
    let addresses: [String]
    let port: Int
}

struct LinkMonitoringSession: Codable {
    var id: String
    let provider: String
    let status: String
    let confidence: String
    let title: String
    let projectName: String
    let currentAction: String
    let currentFiles: [String]
    let startedAt: Date
    let lastActivityAt: Date
    let completedAt: Date?
    let isLive: Bool
    let gitBranch: String?
    let gitChangedFiles: Int?
    let gitInsertions: Int?
    let gitDeletions: Int?
    let summary: String?
}

struct LinkMonitoringSnapshot {
    let revision: Int
    let scannedAt: Date?
    let privacyMode: Bool
    let sessions: [LinkMonitoringSession]
}

protocol LinkSnapshotProviding {
    func monitoringSnapshot() async -> LinkMonitoringSnapshot
}

enum LinkJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

enum LinkRandom {
    static func bytes(_ count: Int) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &output)
        guard status == errSecSuccess else {
            throw NSError(domain: "AgentHUD.Link.Random", code: Int(status))
        }
        return output
    }

    static func token(_ count: Int = 32) throws -> String {
        try Data(bytes(count)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func code() throws -> String {
        let value = try bytes(4).reduce(0) { ($0 << 8) | UInt32($1) }
        return String(format: "%06d", value % 1_000_000)
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func sha256Hex() -> String {
        SHA256.hash(data: self).map { String(format: "%02X", $0) }.joined()
    }
}

func constantTimeEqual(_ left: String?, _ right: String?) -> Bool {
    guard let left, let right else { return false }
    let a = Array(left.utf8)
    let b = Array(right.utf8)
    guard a.count == b.count else { return false }
    var difference: UInt8 = 0
    for index in a.indices {
        difference |= a[index] ^ b[index]
    }
    return difference == 0
}
