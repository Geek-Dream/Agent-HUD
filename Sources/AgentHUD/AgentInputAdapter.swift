import Foundation

enum AgentInputState: String, Codable {
    case ready
    case busy
    case waitingUser
    case offline
    case unsupported
    case unavailable
}

struct AgentInputCapability: Codable {
    let enabled: Bool
    let state: AgentInputState
    let reason: String?
}

@MainActor
protocol AgentInputAdapter: AnyObject {
    var provider: AgentProvider { get }
    func canAcceptInput(for session: AgentSession) -> AgentInputCapability
    func deliver(text: String, to session: AgentSession) async -> AgentDeliveryResult
}

struct AgentDeliveryResult {
    let success: Bool
    let status: AgentDeliveryStatus
    let error: AgentDeliveryError?
}

enum AgentDeliveryStatus: String, Codable {
    case accepted
    case delivered
    case observed
    case failed
}

enum AgentDeliveryError: String, Codable {
    case sessionOffline
    case providerUnsupported
    case inputUnavailable
    case agentBusy
    case invalidMessage
    case deliveryFailed
}
