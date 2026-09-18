import CryptoKit
import Darwin
import Foundation
import Security

public enum PrivateFiles {
    public static func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    public static func write(_ data: Data, to destination: URL) throws {
        let stage = destination.deletingLastPathComponent().appendingPathComponent(".write-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: stage.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw AccountFailure("Unable to create a private file.")
        }
        let handle = try FileHandle(forWritingTo: stage)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        guard rename(stage.path, destination.path) == 0 else {
            throw AccountFailure("Unable to save %@ (system error %@).", destination.lastPathComponent, String(errno))
        }
    }

    public static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public final class CredentialVault {
    private let service: String
    public init(service: String = "local.codexaccounts.credentials") { self.service = service }
    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }
    public func save(_ data: Data, id: UUID) throws {
        _ = try AuthDocument.read(data)
        let status = SecItemUpdate(query(id) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query(id)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let inserted = SecItemAdd(attributes as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw failure(inserted) }
        } else if status != errSecSuccess { throw failure(status) }
    }
    public func read(id: UUID) throws -> Data {
        var attributes = query(id)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw failure(status) }
        return data
    }
    public func remove(id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
    private func failure(_ status: OSStatus) -> AccountFailure {
        AccountFailure("Keychain operation failed (%@). Unlock the macOS Keychain and allow access.", String(status))
    }
}

public final class AccountStorage {
    public let root: URL
    public let runtime: URL
    public let liveAuth: URL
    public let vault: CredentialVault
    private let registryURL: URL
    private var lockDescriptor: Int32 = -1

    public init(root: URL, liveAuth: URL, vault: CredentialVault = CredentialVault()) throws {
        self.root = root
        self.liveAuth = liveAuth
        self.vault = vault
        runtime = root.appendingPathComponent("runtime", isDirectory: true)
        registryURL = root.appendingPathComponent("accounts.json")
        try PrivateFiles.createDirectory(root)
        let lock = root.appendingPathComponent("application.lock")
        lockDescriptor = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lockDescriptor >= 0, flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw AccountFailure("The account manager is already running. Open its window from the menu bar.")
        }
        try PrivateFiles.createDirectory(runtime)
    }

    deinit {
        if lockDescriptor >= 0 { flock(lockDescriptor, LOCK_UN); close(lockDescriptor) }
    }

    public func load() throws -> Registry {
        guard FileManager.default.fileExists(atPath: registryURL.path) else { return Registry() }
        let registry = try JSONDecoder().decode(Registry.self, from: Data(contentsOf: registryURL))
        guard registry.version == 1,
              Set(registry.profiles.map(\.id)).count == registry.profiles.count,
              Set(registry.profiles.map(\.identity)).count == registry.profiles.count else {
            throw AccountFailure("Unrecognized account records. Check accounts.json.")
        }
        return registry
    }

    public func save(_ registry: Registry) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try PrivateFiles.write(encoder.encode(registry), to: registryURL)
    }

    public func makeSession() throws -> URL {
        let url = runtime.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try PrivateFiles.createDirectory(url)
        return url
    }

    public func readLive() throws -> Data? {
        guard FileManager.default.fileExists(atPath: liveAuth.path) else { return nil }
        let values = try liveAuth.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else {
            throw AccountFailure("The Codex credentials path must be a regular file.")
        }
        let data = try Data(contentsOf: liveAuth)
        _ = try AuthDocument.read(data)
        return data
    }

    public func install(_ data: Data, replacing expected: Data?) throws {
        _ = try AuthDocument.read(data)
        guard try readLive() == expected else {
            throw AccountFailure("The current Codex account changed during switching. Refresh the account list and try again.")
        }
        try PrivateFiles.createDirectory(liveAuth.deletingLastPathComponent())
        try PrivateFiles.write(data, to: liveAuth)
        guard try Data(contentsOf: liveAuth) == data else {
            throw AccountFailure("Account file verification failed after saving.")
        }
    }
}
