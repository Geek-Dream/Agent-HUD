import Foundation

final class SessionImportanceStore {
    private static let storageKey = "hud.importantSessions.v1"
    private static let orderStorageKey = "hud.importantSessionOrder.v2"

    private let defaults: UserDefaults
    private(set) var sessionIDs: Set<String>
    private(set) var orderedSessionIDs: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sessionIDs = []
        orderedSessionIDs = []
        reload()
        save()
    }

    func reload() {
        let storedIDs = (defaults.stringArray(forKey: Self.storageKey) ?? []).filter { !$0.isEmpty }
        sessionIDs = Set(storedIDs)
        let storedOrder = defaults.stringArray(forKey: Self.orderStorageKey) ?? storedIDs.sorted()
        var seen = Set<String>()
        let previousOrder = orderedSessionIDs
        orderedSessionIDs = storedOrder.filter { storedIDs.contains($0) && seen.insert($0).inserted }
        orderedSessionIDs += storedIDs.sorted().filter { seen.insert($0).inserted }
        if previousOrder != orderedSessionIDs {
            save()
        }
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
            orderedSessionIDs.removeAll { $0 == sessionID }
            isNowImportant = false
        } else {
            sessionIDs.insert(sessionID)
            orderedSessionIDs.append(sessionID)
            isNowImportant = true
        }
        save()
        return isNowImportant
    }

    /// Moves immediately while dragging over another starred row. The same
    /// persisted order is used by every provider and status filter.
    @discardableResult
    func move(sessionID: String, before targetID: String) -> Bool {
        guard sessionID != targetID,
              sessionIDs.contains(sessionID),
              sessionIDs.contains(targetID),
              let targetIndex = orderedSessionIDs.firstIndex(of: targetID) else {
            return false
        }
        orderedSessionIDs.removeAll { $0 == sessionID }
        let insertionIndex = orderedSessionIDs.firstIndex(of: targetID) ?? min(targetIndex, orderedSessionIDs.count)
        orderedSessionIDs.insert(sessionID, at: insertionIndex)
        save()
        return true
    }

    private func save() {
        defaults.set(orderedSessionIDs, forKey: Self.storageKey)
        defaults.set(orderedSessionIDs, forKey: Self.orderStorageKey)
    }
}
