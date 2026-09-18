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
            throw AccountFailure("无法创建私有文件。")
        }
        let handle = try FileHandle(forWritingTo: stage)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        guard rename(stage.path, destination.path) == 0 else {
            throw AccountFailure("无法保存文件：\(destination.lastPathComponent)，系统错误 \(errno)。")
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
        AccountFailure("钥匙串操作失败（\(status)）。请确认 macOS 钥匙串已经解锁并允许访问。")
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
            throw AccountFailure("账号管理应用已经在运行。请从菜单栏打开现有窗口。")
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
            throw AccountFailure("账号记录的格式无法识别，请检查 accounts.json。")
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
            throw AccountFailure("Codex 凭据路径需要是普通文件。")
        }
        let data = try Data(contentsOf: liveAuth)
        _ = try AuthDocument.read(data)
        return data
    }

    public func install(_ data: Data, replacing expected: Data?) throws {
        _ = try AuthDocument.read(data)
        guard try readLive() == expected else {
            throw AccountFailure("Codex 当前账号在切换期间发生变化，请刷新账号列表后重新切换。")
        }
        try PrivateFiles.createDirectory(liveAuth.deletingLastPathComponent())
        try PrivateFiles.write(data, to: liveAuth)
        guard try Data(contentsOf: liveAuth) == data else {
            throw AccountFailure("账号文件写入后的核验失败。")
        }
    }
}
