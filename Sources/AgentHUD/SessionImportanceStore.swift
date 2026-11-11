import Foundation

final class SessionImportanceStore {
    private static let storageKey = "hud.importantSessions.v1"

    private let defaults: UserDefaults
    private(set) var sessionIDs: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sessionIDs = Set(
            (defaults.stringArray(forKey: Self.storageKey) ?? [])
                .filter { !$0.isEmpty }
        )
    }

    func isImportant(_ sessionID: String) -> Bool {
        sessionIDs.contains(sessionID)
    }

    @discardableResult
    func toggle(_ sessionID: String) -> Bool {
        guard !sessionID.isEmpty else {
            return false
        }

        let isNowImportant: Bool
        if sessionIDs.remove(sessionID) != nil {
            isNowImportant = false
        } else {
            sessionIDs.insert(sessionID)
            isNowImportant = true
        }
        defaults.set(sessionIDs.sorted(), forKey: Self.storageKey)
        return isNowImportant
    }
}
