import Foundation
import Security

enum KeychainStore {
    static let service = "com.cari.walkietalkie"

    static func set(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw WalkieError.injectionBlocked("Keychain write failed with status \(addStatus)")
        }
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return value
    }
}

enum APIKeyResolver {
    static let openAIAccount = "openai_api_key"

    static func resolveOpenAIKey(envVar: String) -> String? {
        if let key = KeychainStore.get(account: openAIAccount), !key.isEmpty {
            return key
        }
        if let key = ProcessInfo.processInfo.environment[envVar], !key.isEmpty {
            return key
        }
        return nil
    }
}
