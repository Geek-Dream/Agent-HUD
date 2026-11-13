import Foundation

@MainActor
final class AgentRuntimeRegistry {
    private var bindings: [String: AgentInputBinding] = [:]

    func register(sessionID: String, adapter: any AgentInputAdapter, windowIdentifier: String? = nil) {
        bindings[sessionID] = AgentInputBinding(
            sessionID: sessionID,
            adapter: adapter,
            windowIdentifier: windowIdentifier
        )
    }

    func binding(for sessionID: String) -> AgentInputBinding? {
        bindings[sessionID]
    }

    func unregister(sessionID: String) {
        bindings.removeValue(forKey: sessionID)
    }

    func adaptersFor(provider: AgentProvider) -> [any AgentInputAdapter] {
        bindings.values
            .filter { $0.adapter.provider == provider }
            .map { $0.adapter }
    }
}

struct AgentInputBinding {
    let sessionID: String
    let adapter: any AgentInputAdapter
    let windowIdentifier: String?
}
