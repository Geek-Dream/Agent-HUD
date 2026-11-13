import Foundation

@MainActor
final class DeliveryStore {
    private struct Record: Codable {
        let deliveryId: String
        let clientMessageId: String
        let sessionPublicId: String
        let textHash: String
        let status: AgentDeliveryStatus
        let error: AgentDeliveryError?
        let createdAt: Date
        let updatedAt: Date
    }

    private var records: [String: Record] = [:]
    private var clientToDelivery: [String: String] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 300) {
        self.ttl = ttl
    }

    func find(clientMessageId: String) -> (deliveryId: String, status: AgentDeliveryStatus, error: AgentDeliveryError?)? {
        cleanup()
        guard let deliveryId = clientToDelivery[clientMessageId],
              let record = records[deliveryId] else {
            return nil
        }
        return (record.deliveryId, record.status, record.error)
    }

    func find(deliveryId: String) -> (clientMessageId: String, status: AgentDeliveryStatus, error: AgentDeliveryError?)? {
        cleanup()
        guard let record = records[deliveryId] else {
            return nil
        }
        return (record.clientMessageId, record.status, record.error)
    }

    func create(
        clientMessageId: String,
        sessionPublicId: String,
        text: String
    ) -> String {
        cleanup()
        if let existing = clientToDelivery[clientMessageId],
           let record = records[existing] {
            return record.deliveryId
        }
        let deliveryId = deliveryId()
        let now = Date()
        let record = Record(
            deliveryId: deliveryId,
            clientMessageId: clientMessageId,
            sessionPublicId: sessionPublicId,
            textHash: textHash(text),
            status: .accepted,
            error: nil,
            createdAt: now,
            updatedAt: now
        )
        records[deliveryId] = record
        clientToDelivery[clientMessageId] = deliveryId
        return deliveryId
    }

    func update(
        deliveryId: String,
        status: AgentDeliveryStatus,
        error: AgentDeliveryError? = nil
    ) {
        guard var record = records[deliveryId] else { return }
        record = Record(
            deliveryId: record.deliveryId,
            clientMessageId: record.clientMessageId,
            sessionPublicId: record.sessionPublicId,
            textHash: record.textHash,
            status: status,
            error: error,
            createdAt: record.createdAt,
            updatedAt: Date()
        )
        records[deliveryId] = record
    }

    private func cleanup() {
        let cutoff = Date().addingTimeInterval(-ttl)
        for (deliveryId, record) in records where record.updatedAt < cutoff {
            records.removeValue(forKey: deliveryId)
            clientToDelivery.removeValue(forKey: record.clientMessageId)
        }
    }

    private func deliveryId() -> String {
        Data((try? LinkRandom.bytes(16)) ?? []).base64URLEncodedString()
    }

    private func textHash(_ text: String) -> String {
        Data(text.utf8).sha256Hex()
    }
}
