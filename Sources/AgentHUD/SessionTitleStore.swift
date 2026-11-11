import Foundation

final class SessionTitleStore {
    private static let storageKey = "hud.sessionTitles.v1"

    private let defaults: UserDefaults
    private(set) var titles: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        titles = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
    }

    func title(for sessionID: String) -> String? {
        titles[sessionID]
    }

    @discardableResult
    func setCustomTitle(_ value: String, for sessionID: String) -> String? {
        let normalized = value
            .replacingOccurrences(of: "\u{0000}", with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            removeCustomTitle(for: sessionID)
            return nil
        }

        let title = String(normalized.prefix(72))
        titles[sessionID] = title
        persist()
        return title
    }

    func removeCustomTitle(for sessionID: String) {
        guard titles.removeValue(forKey: sessionID) != nil else {
            return
        }
        persist()
    }

    private func persist() {
        defaults.set(titles, forKey: Self.storageKey)
    }
}
