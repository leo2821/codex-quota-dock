import AppKit
import Foundation

@MainActor
public final class AccountService {
    public let storage: AccountStorage
    public let installation: CodexInstallation
    public private(set) var registry: Registry
    public private(set) var activeID: UUID?
    private var loginClient: CodexClient?
    private var loginID: String?

    public init(storage: AccountStorage, installation: CodexInstallation) throws {
        self.storage = storage
        self.installation = installation
        registry = try storage.load()
    }

    public func identify(_ data: Data) async throws -> AccountInfo {
        _ = try AuthDocument.read(data)
        return try await session(auth: data) { client in try await client.readAccount() }
    }

    @discardableResult
    public func importCredential(_ data: Data, label: String) async throws -> UUID {
        let document = try AuthDocument.read(data)
        let info = try await identify(data)
        return try saveCredential(data, document: document, info: info, label: label)
    }

    @discardableResult
    public func synchronizeCurrent(importIfMissing: Bool = true) async throws -> UUID? {
        guard let data = try storage.readLive() else { activeID = nil; return nil }
        let document = try AuthDocument.read(data)
        let info = try await identify(data)
        let identity = document.accountID + "|" + (info.email?.lowercased() ?? "")
        if let index = registry.profiles.firstIndex(where: { $0.identity == identity }) {
            let id = registry.profiles[index].id
            try storage.vault.save(data, id: id)
            registry.profiles[index].plan = info.planType
            activeID = id
            try storage.save(registry)
        } else if importIfMissing {
            activeID = try saveCredential(data, document: document, info: info, label: "")
        } else { activeID = nil }
        return activeID
    }

    public func refresh(_ id: UUID) async throws {
        guard let index = registry.profiles.firstIndex(where: { $0.id == id }) else {
            throw AccountFailure("Account not found.")
        }
        let profile = registry.profiles[index]
        do {
            let data = try storage.vault.read(id: id)
            let document = try AuthDocument.read(data)
            guard document.accountID == profile.accountID else { throw AccountFailure("Saved credentials do not match the account record.") }
            let snapshot = try await session { client in
                try await client.useExternalTokens(document, plan: profile.plan)
                return try await client.readLimits()
            }
            registry.profiles[index].usage = snapshot
            registry.profiles[index].lastError = nil
            registry.profiles[index].localizedError = nil
            if let plan = snapshot.response.mainBucket?.planType { registry.profiles[index].plan = plan }
            try storage.save(registry)
        } catch {
            registry.profiles[index].lastError = error.localizedDescription
            registry.profiles[index].localizedError = error as? AccountFailure
            try storage.save(registry)
            throw error
        }
    }

    public func updateCredential(_ id: UUID) async throws {
        guard id != activeID else { throw AccountFailure("Codex manages the current account's sign-in. Refresh the account details.") }
        guard let profile = registry.profiles.first(where: { $0.id == id }) else { throw AccountFailure("Account not found.") }
        let original = try storage.vault.read(id: id)
        let updated: Data = try await session(auth: original) { client in
            _ = try await client.request("account/read", params: ["refreshToken": true])
            let info = try await client.readAccount()
            let data = try Data(contentsOf: client.home.appendingPathComponent("auth.json"))
            let document = try AuthDocument.read(data)
            guard document.accountID == profile.accountID, info.email == profile.email else {
                throw AccountFailure("The renewed account identity does not match the saved record.")
            }
            try self.storage.vault.save(data, id: id)
            return data
        }
        _ = try AuthDocument.read(updated)
        try await refresh(id)
    }

    public func beginLogin(openURL: (URL) -> Void) async throws -> UUID {
        guard loginClient == nil else { throw AccountFailure("Another account is signing in.") }
        let home = try storage.makeSession()
        let client = try CodexClient(installation: installation, home: home)
        loginClient = client
        do {
            try await client.initialize()
            let start = try await client.startLogin()
            loginID = start.loginId
            guard let url = URL(string: start.authUrl), url.scheme == "https",
                  let host = url.host, ["auth.openai.com", "auth0.openai.com", "chatgpt.com"].contains(host) else {
                throw AccountFailure("Codex returned an unrecognized sign-in address.")
            }
            openURL(url)
            try await client.waitForLogin(id: start.loginId)
            let info = try await client.readAccount()
            let data = try Data(contentsOf: home.appendingPathComponent("auth.json"))
            let document = try AuthDocument.read(data)
            let id = try saveCredential(data, document: document, info: info, label: "")
            try await client.stop()
            try FileManager.default.removeItem(at: home)
            loginClient = nil
            loginID = nil
            return id
        } catch {
            try await client.stop()
            try FileManager.default.removeItem(at: home)
            loginClient = nil
            loginID = nil
            throw error
        }
    }

    public func cancelLogin() async throws {
        guard let client = loginClient, let id = loginID else { return }
        try await client.cancelLogin(id: id)
    }

    public func rename(_ id: UUID, label: String) throws {
        let clean = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 60 else { throw AccountFailure("Account names must contain 1 to 60 characters.") }
        guard let index = registry.profiles.firstIndex(where: { $0.id == id }) else { throw AccountFailure("Account not found.") }
        registry.profiles[index].label = clean
        try storage.save(registry)
    }

    public func remove(_ id: UUID) throws {
        guard id != activeID else { throw AccountFailure("Switch to another account before removing the current account.") }
        guard registry.profiles.contains(where: { $0.id == id }) else { throw AccountFailure("Account not found.") }
        try storage.vault.remove(id: id)
        registry.profiles.removeAll { $0.id == id }
        try storage.save(registry)
    }

    public func updatePreferences(_ preferences: Preferences) throws {
        guard [0, 60, 120, 300, 900].contains(preferences.refreshSeconds) else {
            throw AccountFailure("Choose a supported refresh interval.")
        }
        registry.preferences = preferences
        try storage.save(registry)
    }

    public func switchAccount(_ id: UUID) async throws {
        _ = try await synchronizeCurrent()
        guard id != activeID else { return }
        guard let target = registry.profiles.first(where: { $0.id == id }) else { throw AccountFailure("Account not found.") }
        let targetData = try storage.vault.read(id: id)
        let targetInfo = try await identify(targetData)
        let targetDocument = try AuthDocument.read(targetData)
        guard targetDocument.accountID == target.accountID, targetInfo.email == target.email else {
            throw AccountFailure("Credentials do not match the account record. Sign in again.")
        }
        try await refresh(id)
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: installation.bundleID)
        for application in applications {
            guard application.terminate() else { throw AccountFailure("Codex cannot quit right now. Finish the current task and try again.") }
        }
        let deadline = Date().addingTimeInterval(15)
        while applications.contains(where: { !$0.isTerminated }) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard applications.allSatisfy(\.isTerminated) else {
            throw AccountFailure("Codex is still running. Quit Codex normally and try again.")
        }
        _ = try await synchronizeCurrent()
        let outgoing = try storage.readLive()
        try storage.install(targetData, replacing: outgoing)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let application = try await NSWorkspace.shared.openApplication(at: installation.application, configuration: configuration)
        guard application.bundleIdentifier == installation.bundleID, !application.isTerminated else {
            throw AccountFailure("The account was saved, but Codex did not start. Open the Codex app.")
        }
        guard let current = try storage.readLive() else { throw AccountFailure("The account file is missing after switching.") }
        let verifiedInfo = try await identify(current)
        guard try AuthDocument.read(current).accountID == target.accountID, verifiedInfo.email == target.email else {
            throw AccountFailure("Account verification failed after Codex started. Sign in to the target account again.")
        }
        activeID = id
    }

    private func saveCredential(_ data: Data, document: AuthDocument, info: AccountInfo, label: String) throws -> UUID {
        let identity = document.accountID + "|" + (info.email?.lowercased() ?? "")
        if let index = registry.profiles.firstIndex(where: { $0.identity == identity }) {
            let id = registry.profiles[index].id
            try storage.vault.save(data, id: id)
            registry.profiles[index].plan = info.planType
            registry.profiles[index].lastError = nil
            registry.profiles[index].localizedError = nil
            try storage.save(registry)
            return id
        }
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = Profile(label: cleanLabel.isEmpty ? (info.email ?? "ChatGPT") : cleanLabel,
                              accountID: document.accountID, info: info)
        try storage.vault.save(data, id: profile.id)
        registry.profiles.append(profile)
        try storage.save(registry)
        return profile.id
    }

    private func session<T>(auth: Data? = nil, operation: (CodexClient) async throws -> T) async throws -> T {
        let home = try storage.makeSession()
        if let auth { try PrivateFiles.write(auth, to: home.appendingPathComponent("auth.json")) }
        let client = try CodexClient(installation: installation, home: home)
        do {
            try await client.initialize()
            let result = try await operation(client)
            try await client.stop()
            try FileManager.default.removeItem(at: home)
            return result
        } catch {
            try await client.stop()
            try FileManager.default.removeItem(at: home)
            throw error
        }
    }
}
