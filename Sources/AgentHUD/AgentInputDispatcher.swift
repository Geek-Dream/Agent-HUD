import Foundation

@MainActor
final class AgentInputDispatcher {
    private let registry: AgentRuntimeRegistry
    private let deliveryStore: DeliveryStore
    private let adapters: [AgentProvider: [any AgentInputAdapter]]
    private let maxTextLength = 4000
    private var inFlight: Set<String> = []

    init(
        registry: AgentRuntimeRegistry,
        deliveryStore: DeliveryStore,
        adapters: [any AgentInputAdapter]
    ) {
        self.registry = registry
        self.deliveryStore = deliveryStore
        self.adapters = Dictionary(grouping: adapters, by: \.provider)
            .mapValues { $0 }
    }

    func capability(for session: AgentSession) -> AgentInputCapability {
        guard session.isLive else {
            return AgentInputCapability(
                enabled: false,
                state: .offline,
                reason: "会话或进程已经离线。"
            )
        }
        guard let adapters = adapters(for: session.provider),
              !adapters.isEmpty else {
            return AgentInputCapability(
                enabled: false,
                state: .unsupported,
                reason: "当前 Provider 或版本不支持输入。"
            )
        }
        let capabilities = adapters.map { $0.canAcceptInput(for: session) }
        if let ready = capabilities.first(where: { $0.state == .ready }) {
            return ready
        }
        if let waiting = capabilities.first(where: { $0.state == .waitingUser }) {
            return waiting
        }
        return capabilities.first ?? AgentInputCapability(
            enabled: false,
            state: .unavailable,
            reason: "输入通道暂时不可用。"
        )
    }

    func dispatch(
        clientMessageId: String,
        text: String,
        to session: AgentSession,
        publicSessionId: String
    ) -> (deliveryId: String, status: AgentDeliveryStatus, error: AgentDeliveryError?) {
        if let existing = deliveryStore.find(clientMessageId: clientMessageId) {
            return existing
        }

        let deliveryId = deliveryStore.create(
            clientMessageId: clientMessageId,
            sessionPublicId: publicSessionId,
            text: text
        )

        guard validate(text: text) else {
            deliveryStore.update(deliveryId: deliveryId, status: .failed, error: .invalidMessage)
            return (deliveryId, .failed, .invalidMessage)
        }

        let capability = self.capability(for: session)
        guard capability.enabled else {
            let error: AgentDeliveryError = capability.state == .offline
                ? .sessionOffline
                : (capability.state == .unsupported ? .providerUnsupported : .inputUnavailable)
            deliveryStore.update(deliveryId: deliveryId, status: .failed, error: error)
            return (deliveryId, .failed, error)
        }

        guard inFlight.insert(session.id).inserted else {
            deliveryStore.update(deliveryId: deliveryId, status: .failed, error: .agentBusy)
            return (deliveryId, .failed, .agentBusy)
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.inFlight.remove(session.id) }
            await self.performDelivery(
                deliveryId: deliveryId,
                text: text,
                session: session
            )
        }

        return (deliveryId, .accepted, nil)
    }

    func status(deliveryId: String) -> (status: AgentDeliveryStatus, error: AgentDeliveryError?)? {
        deliveryStore.find(deliveryId: deliveryId).map { ($0.status, $0.error) }
    }

    private func performDelivery(
        deliveryId: String,
        text: String,
        session: AgentSession
    ) async {
        guard let adapters = adapters(for: session.provider) else {
            deliveryStore.update(deliveryId: deliveryId, status: .failed, error: .providerUnsupported)
            return
        }

        for adapter in adapters {
            let result = await adapter.deliver(text: text, to: session)
            if result.success {
                deliveryStore.update(
                    deliveryId: deliveryId,
                    status: result.status == .delivered ? .delivered : .accepted
                )
                return
            }
        }

        deliveryStore.update(
            deliveryId: deliveryId,
            status: .failed,
            error: .deliveryFailed
        )
    }

    private func adapters(for provider: AgentProvider) -> [any AgentInputAdapter]? {
        adapters[provider]
    }

    private func validate(text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxTextLength
    }
}
