import CryptoKit
import Darwin
import Foundation

public enum PrivateFiles {
    public static func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isDirectory == true else {
            throw AccountFailure("The account data directory must be a regular directory.")
        }
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
    public let root: URL

    public init(root: URL) throws {
        self.root = root
        try PrivateFiles.createDirectory(root)
    }

    public func fileURL(id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent("auth.json")
    }

    public func save(_ data: Data, id: UUID) throws {
        _ = try AuthDocument.read(data)
        try PrivateFiles.createDirectory(root)
        let url = fileURL(id: id)
        try PrivateFiles.createDirectory(url.deletingLastPathComponent())
        try PrivateFiles.write(data, to: url)
        guard try read(id: id) == data else {
            throw AccountFailure("Account file verification failed after saving.")
        }
    }

    public func read(id: UUID) throws -> Data {
        let url = fileURL(id: id)
        for directory in [root, url.deletingLastPathComponent()] {
            guard FileManager.default.fileExists(atPath: directory.path) else {
                throw AccountFailure("The saved auth.json is missing. Sign in to this account again.")
            }
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isDirectory == true else {
                throw AccountFailure("The account data directory must be a regular directory.")
            }
        }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            if errno == ENOENT {
                throw AccountFailure("The saved auth.json is missing. Sign in to this account again.")
            }
            throw AccountFailure("Unable to open the saved auth.json (system error %@).", String(errno))
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0,
              attributes.st_mode & S_IFMT == S_IFREG,
              attributes.st_uid == geteuid(), attributes.st_mode & 0o777 == 0o600 else {
            throw AccountFailure("The saved auth.json must be a regular file owned by this macOS user with permissions 0600.")
        }
        let data = try handle.readToEnd() ?? Data()
        try handle.close()
        _ = try AuthDocument.read(data)
        return data
    }

    public func remove(id: UUID) throws {
        let url = fileURL(id: id)
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else { return }
        for directory in [root, url.deletingLastPathComponent()] {
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isDirectory == true else {
                throw AccountFailure("The account data directory must be a regular directory.")
            }
        }
        guard unlink(url.path) == 0 || errno == ENOENT else {
            throw AccountFailure("Unable to remove the saved auth.json (system error %@).", String(errno))
        }
        guard rmdir(url.deletingLastPathComponent().path) == 0 else {
            throw AccountFailure("Unable to remove the account directory (system error %@).", String(errno))
        }
    }
}

public final class AccountStorage {
    public let root: URL
    public let runtime: URL
    public let liveAuth: URL
    public let vault: CredentialVault
    private let registryURL: URL
    private var lockDescriptor: Int32 = -1

    public init(root: URL, liveAuth: URL) throws {
        self.root = root
        self.liveAuth = liveAuth
        runtime = root.appendingPathComponent("runtime", isDirectory: true)
        registryURL = root.appendingPathComponent("accounts.json")
        try PrivateFiles.createDirectory(root)
        let lock = root.appendingPathComponent("application.lock")
        let descriptor = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            throw AccountFailure("Unable to open the account data lock (system error %@).", String(errno))
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw AccountFailure("The account manager is already running. Open its window from the menu bar.")
        }
        do {
            vault = try CredentialVault(root: root.appendingPathComponent("credentials", isDirectory: true))
            try PrivateFiles.createDirectory(runtime)
        } catch {
            flock(descriptor, LOCK_UN)
            close(descriptor)
            throw error
        }
        lockDescriptor = descriptor
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
