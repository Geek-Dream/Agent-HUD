import Foundation
import Security

protocol AISecretStoring {
    func apiKey() -> String?
    func saveAPIKey(_ value: String) throws
    func deleteAPIKey() throws
}

enum AISecretStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String?
            return message ?? "Keychain 操作失败（\(status)）"
        }
    }
}

final class KeychainAISecretStore: AISecretStoring {
    static let service = "com.agenthud.ai"
    static let account = "openai-compatible-api-key"
    static let environmentKey = "AGENTHUD_AI_API_KEY"

    private let service: String
    private let account: String
    private let environment: [String: String]

    init(
        service: String = KeychainAISecretStore.service,
        account: String = KeychainAISecretStore.account,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.service = service
        self.account = account
        self.environment = environment
    }

    func apiKey() -> String? {
        if let key = keychainAPIKey(), !key.isEmpty {
            return key
        }
        return environment[Self.environmentKey].flatMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        }
    }

    func saveAPIKey(_ value: String) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw AISecretStoreError.keychain(errSecParam)
        }

        let data = Data(normalized.utf8)
        let query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AISecretStoreError.keychain(updateStatus)
        }

        var addQuery = query
        for (key, value) in attributes {
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AISecretStoreError.keychain(addStatus)
        }
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AISecretStoreError.keychain(status)
        }
    }

    private func keychainAPIKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
