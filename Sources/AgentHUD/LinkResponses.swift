import Foundation

struct LinkPairingPayload: Codable {
    let v: Int
    let instanceId: String
    let instanceName: String
    let addresses: [String]
    let ipv6Addresses: [String]?
    let port: Int
    let fingerprint: String
    let sessionId: String
    let secret: String
    let expiresAt: Date
}

struct LinkStatusResponse: Codable {
    let `protocol`: Int
    let instanceId: String
    let instanceName: String
    let capabilities: [String]
    let revision: Int
    let scannedAt: Date?
    let serverTime: Date
    let privacyMode: Bool
    let fingerprint: String
    let addresses: [String]
    let ipv6Addresses: [String]?
    let port: Int
}

struct LinkSessionsResponse: Codable {
    let revision: Int
    let scannedAt: Date?
    let sessions: [LinkMonitoringSession]
}

struct LinkTitleRequest: Codable {
    let title: String?
}

struct LinkImportantRequest: Codable {
    let important: Bool
}

struct LinkTitleResponse: Codable {
    let id: String
    let title: String
    let titleSource: String
    let hasCustomTitle: Bool
}

struct LinkImportantResponse: Codable {
    let id: String
    let isImportant: Bool
}

struct LinkErrorResponse: Codable {
    let error: String
}
