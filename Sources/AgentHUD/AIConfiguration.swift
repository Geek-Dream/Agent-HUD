import Foundation

struct AIConfiguration: Equatable {
    static let defaultEndpoint = "https://cch.qcode.top:8443/v1"
    static let defaultModel = "kimi-k3.1-pro"

    private static let enabledKey = "ai.title.enabled"
    private static let endpointKey = "ai.title.endpoint"
    private static let modelKey = "ai.title.model"
    private static let supportsVisionKey = "ai.title.supportsVision"

    var enabled: Bool
    var endpoint: String
    var model: String
    var supportsVision: Bool

    init(
        enabled: Bool = false,
        endpoint: String = Self.defaultEndpoint,
        model: String = Self.defaultModel,
        supportsVision: Bool = true
    ) {
        self.enabled = enabled
        self.endpoint = endpoint
        self.model = model
        self.supportsVision = supportsVision
    }

    static func load(defaults: UserDefaults = .standard) -> AIConfiguration {
        let endpoint = defaults.string(forKey: endpointKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let model = defaults.string(forKey: modelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return AIConfiguration(
            enabled: defaults.bool(forKey: enabledKey),
            endpoint: endpoint.flatMap { $0.isEmpty ? nil : $0 } ?? defaultEndpoint,
            model: model.flatMap { $0.isEmpty ? nil : $0 } ?? defaultModel,
            supportsVision: defaults.object(forKey: supportsVisionKey) as? Bool ?? true
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Self.enabledKey)
        defaults.set(endpoint, forKey: Self.endpointKey)
        defaults.set(model, forKey: Self.modelKey)
        defaults.set(supportsVision, forKey: Self.supportsVisionKey)
    }

    var chatCompletionsURL: URL? {
        var normalized = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        guard var components = URLComponents(string: normalized),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host != nil else {
            return nil
        }

        if !components.path.lowercased().hasSuffix("/chat/completions") {
            components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = "/" + components.path
            if components.path != "/" {
                components.path += "/chat/completions"
            } else {
                components.path = "/chat/completions"
            }
        }
        return components.url
    }

    var isUsable: Bool {
        enabled
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && chatCompletionsURL != nil
    }
}
