import Foundation
import Security

enum LegacyKeychain {
    static func read(id: UUID) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "local.codexaccounts.credentials",
                kSecAttrAccount as String: id.uuidString,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data else {
                throw AccountFailure("Account migration could not read Keychain (%@). Allow access and retry migration, or sign in again.", String(status))
            }
            _ = try AuthDocument.read(data)
            return data
        }.value
    }
}
