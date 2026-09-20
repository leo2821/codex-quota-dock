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

    public func identify(_ data: Data) throws -> AccountInfo {
        try AuthDocument.read(data).accountInfo()
    }

    @discardableResult
    public func importCredential(_ data: Data, label: String) async throws -> UUID {
        let document = try AuthDocument.read(data)
        let info = try document.accountInfo()
        let usage = try await queryLimits(document, plan: info.planType)
        let id = try saveCredential(data, document: document, info: info, label: label)
        let index = registry.profiles.firstIndex { $0.id == id }!
        registry.profiles[index].usage = usage
        try storage.save(registry)
        return id
    }

    @discardableResult
    public func synchronizeCurrent(importIfMissing: Bool = true) throws -> UUID? {
        activeID = nil
        guard let data = try storage.readLive() else { activeID = nil; return nil }
        let document = try AuthDocument.read(data)
        let info = try document.accountInfo()
        let identity = document.accountID + "|" + (info.email?.lowercased() ?? "")
        if let index = registry.profiles.firstIndex(where: { $0.identity == identity }) {
            let id = registry.profiles[index].id
            try storage.vault.save(data, id: id)
            registry.profiles[index].credentialStorage = .localFile
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
            guard profile.credentialStorage == .localFile else {
                throw AccountFailure("Migrate this saved account or sign in again to create its local auth.json.")
            }
            let data = try storage.vault.read(id: id)
            let document = try AuthDocument.read(data)
            guard document.accountID == profile.accountID else { throw AccountFailure("Saved credentials do not match the account record.") }
            let info = try document.accountInfo()
            guard info.email?.lowercased() == profile.email?.lowercased() else {
                throw AccountFailure("Saved credentials do not match the account record.")
            }
            let snapshot = try await queryLimits(document, plan: profile.plan)
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

    public func synchronizeForRefresh() -> AccountFailure? {
        do { _ = try synchronizeCurrent(); return nil }
        catch {
            return error as? AccountFailure
                ?? AccountFailure("Unable to read the current Codex account: %@", error.localizedDescription)
        }
    }

    public func refreshAll(progress: (UUID) -> Void = { _ in }) async -> AccountRefreshReport {
        let currentAccountError = synchronizeForRefresh()
        var failures: [UUID] = []
        for profile in registry.profiles {
            progress(profile.id)
            do { try await refresh(profile.id) }
            catch { failures.append(profile.id) }
        }
        return AccountRefreshReport(currentAccountError: currentAccountError, failedAccountIDs: failures)
    }

    public func updateCredential(_ id: UUID) async throws {
        guard id != activeID else { throw AccountFailure("Codex manages the current account's sign-in. Refresh the account details.") }
        guard let profile = registry.profiles.first(where: { $0.id == id }) else { throw AccountFailure("Account not found.") }
        guard profile.credentialStorage == .localFile else {
            throw AccountFailure("Migrate this saved account or sign in again to create its local auth.json.")
        }
        let original = try storage.vault.read(id: id)
        let updated: Data = try await session(auth: original) { client in
            do {
                _ = try await client.request("account/read", params: ["refreshToken": true])
            } catch {
                let data = try Data(contentsOf: client.home.appendingPathComponent("auth.json"))
                if data != original { try self.saveRenewedCredential(data, profile: profile) }
                throw error
            }
            let data = try Data(contentsOf: client.home.appendingPathComponent("auth.json"))
            try self.saveRenewedCredential(data, profile: profile)
            return data
        }
        _ = try AuthDocument.read(updated)
        try await refresh(id)
    }

    public func beginLogin(openURL: (URL) throws -> Void) async throws -> UUID {
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
            try openURL(url)
            try await client.waitForLogin(id: start.loginId)
            let data = try Data(contentsOf: home.appendingPathComponent("auth.json"))
            let document = try AuthDocument.read(data)
            let info = try document.accountInfo()
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

    public func migrateCredential(_ id: UUID) async throws {
        guard let index = registry.profiles.firstIndex(where: { $0.id == id }) else {
            throw AccountFailure("Account not found.")
        }
        let profile = registry.profiles[index]
        guard profile.credentialStorage != .localFile else { return }
        let data = try await LegacyKeychain.read(id: id)
        let document = try AuthDocument.read(data)
        let info = try document.accountInfo()
        guard document.accountID == profile.accountID, info.email == profile.email else {
            throw AccountFailure("Saved credentials do not match the account record.")
        }
        try storage.vault.save(data, id: id)
        registry.profiles[index].credentialStorage = .localFile
        registry.profiles[index].lastError = nil
        registry.profiles[index].localizedError = nil
        try storage.save(registry)
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
        _ = try synchronizeCurrent()
        guard id != activeID else { return }
        guard let target = registry.profiles.first(where: { $0.id == id }) else { throw AccountFailure("Account not found.") }
        guard target.credentialStorage == .localFile else {
            throw AccountFailure("Migrate this saved account or sign in again to create its local auth.json.")
        }
        let targetData = try storage.vault.read(id: id)
        let targetInfo = try identify(targetData)
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
        _ = try synchronizeCurrent()
        let outgoing = try storage.readLive()
        try storage.install(targetData, replacing: outgoing)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let application = try await NSWorkspace.shared.openApplication(at: installation.application, configuration: configuration)
        guard application.bundleIdentifier == installation.bundleID, !application.isTerminated else {
            throw AccountFailure("The account was saved, but Codex did not start. Open the Codex app.")
        }
        guard let current = try storage.readLive() else { throw AccountFailure("The account file is missing after switching.") }
        let verifiedInfo = try identify(current)
        guard try AuthDocument.read(current).accountID == target.accountID, verifiedInfo.email == target.email else {
            throw AccountFailure("Account verification failed after Codex started. Sign in to the target account again.")
        }
        activeID = id
    }

    private func queryLimits(_ document: AuthDocument, plan: String?) async throws -> UsageSnapshot {
        let snapshot = try await session { client in
            try await client.useExternalTokens(document, plan: plan)
            return try await client.readLimits()
        }
        if let accountID = snapshot.response.accountId, accountID != document.accountID {
            throw AccountFailure("The quota response belongs to a different account.")
        }
        return snapshot
    }

    private func saveRenewedCredential(_ data: Data, profile: Profile) throws {
        let document = try AuthDocument.read(data)
        let info = try document.accountInfo()
        guard document.accountID == profile.accountID,
              info.email?.lowercased() == profile.email?.lowercased() else {
            throw AccountFailure("The renewed account identity does not match the saved record.")
        }
        try storage.vault.save(data, id: profile.id)
    }

    private func saveCredential(_ data: Data, document: AuthDocument, info: AccountInfo, label: String) throws -> UUID {
        let identity = document.accountID + "|" + (info.email?.lowercased() ?? "")
        if let index = registry.profiles.firstIndex(where: { $0.identity == identity }) {
            let id = registry.profiles[index].id
            try storage.vault.save(data, id: id)
            registry.profiles[index].credentialStorage = .localFile
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
