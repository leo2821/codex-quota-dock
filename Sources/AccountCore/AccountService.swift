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
            activeID = try saveCredential(data, document: document, info: info, label: "当前账号")
        } else { activeID = nil }
        return activeID
    }

    public func refresh(_ id: UUID) async throws {
        guard let index = registry.profiles.firstIndex(where: { $0.id == id }) else {
            throw AccountFailure("未找到该账号。")
        }
        let profile = registry.profiles[index]
        do {
            let data = try storage.vault.read(id: id)
            let document = try AuthDocument.read(data)
            guard document.accountID == profile.accountID else { throw AccountFailure("保存的账号凭据与账号记录不一致。") }
            let snapshot = try await session { client in
                try await client.useExternalTokens(document, plan: profile.plan)
                return try await client.readLimits()
            }
            registry.profiles[index].usage = snapshot
            registry.profiles[index].lastError = nil
            if let plan = snapshot.response.mainBucket?.planType { registry.profiles[index].plan = plan }
            try storage.save(registry)
        } catch {
            registry.profiles[index].lastError = error.localizedDescription
            try storage.save(registry)
            throw error
        }
    }

    public func updateCredential(_ id: UUID) async throws {
        guard id != activeID else { throw AccountFailure("当前账号由 Codex 自动更新登录。请刷新账号信息。") }
        guard let profile = registry.profiles.first(where: { $0.id == id }) else { throw AccountFailure("未找到该账号。") }
        let original = try storage.vault.read(id: id)
        let updated: Data = try await session(auth: original) { client in
            _ = try await client.request("account/read", params: ["refreshToken": true])
            let info = try await client.readAccount()
            let data = try Data(contentsOf: client.home.appendingPathComponent("auth.json"))
            let document = try AuthDocument.read(data)
            guard document.accountID == profile.accountID, info.email == profile.email else {
                throw AccountFailure("更新后的账号身份与保存的记录不一致。")
            }
            try self.storage.vault.save(data, id: id)
            return data
        }
        _ = try AuthDocument.read(updated)
        try await refresh(id)
    }

    public func beginLogin(openURL: (URL) -> Void) async throws -> UUID {
        guard loginClient == nil else { throw AccountFailure("另一个账号正在登录。") }
        let home = try storage.makeSession()
        let client = try CodexClient(installation: installation, home: home)
        loginClient = client
        do {
            try await client.initialize()
            let start = try await client.startLogin()
            loginID = start.loginId
            guard let url = URL(string: start.authUrl), url.scheme == "https",
                  let host = url.host, ["auth.openai.com", "auth0.openai.com", "chatgpt.com"].contains(host) else {
                throw AccountFailure("Codex 返回了无法识别的登录地址。")
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
        guard !clean.isEmpty, clean.count <= 60 else { throw AccountFailure("账号名称需要包含 1 至 60 个字符。") }
        guard let index = registry.profiles.firstIndex(where: { $0.id == id }) else { throw AccountFailure("未找到该账号。") }
        registry.profiles[index].label = clean
        try storage.save(registry)
    }

    public func remove(_ id: UUID) throws {
        guard id != activeID else { throw AccountFailure("请切换到其他账号后再移除当前账号。") }
        guard registry.profiles.contains(where: { $0.id == id }) else { throw AccountFailure("未找到该账号。") }
        try storage.vault.remove(id: id)
        registry.profiles.removeAll { $0.id == id }
        try storage.save(registry)
    }

    public func updatePreferences(_ preferences: Preferences) throws {
        guard [0, 60, 120, 300, 900].contains(preferences.refreshSeconds) else {
            throw AccountFailure("请选择支持的刷新间隔。")
        }
        registry.preferences = preferences
        try storage.save(registry)
    }

    public func switchAccount(_ id: UUID) async throws {
        _ = try await synchronizeCurrent()
        guard id != activeID else { return }
        guard let target = registry.profiles.first(where: { $0.id == id }) else { throw AccountFailure("未找到该账号。") }
        let targetData = try storage.vault.read(id: id)
        let targetInfo = try await identify(targetData)
        let targetDocument = try AuthDocument.read(targetData)
        guard targetDocument.accountID == target.accountID, targetInfo.email == target.email else {
            throw AccountFailure("账号凭据与账号记录不一致，请重新登录。")
        }
        try await refresh(id)
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: installation.bundleID)
        for application in applications {
            guard application.terminate() else { throw AccountFailure("Codex 暂时无法退出，请完成当前任务后重试。") }
        }
        let deadline = Date().addingTimeInterval(15)
        while applications.contains(where: { !$0.isTerminated }) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard applications.allSatisfy(\.isTerminated) else {
            throw AccountFailure("Codex 仍在运行。请正常退出 Codex 后重试。")
        }
        _ = try await synchronizeCurrent()
        let outgoing = try storage.readLive()
        try storage.install(targetData, replacing: outgoing)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let application = try await NSWorkspace.shared.openApplication(at: installation.application, configuration: configuration)
        guard application.bundleIdentifier == installation.bundleID, !application.isTerminated else {
            throw AccountFailure("账号已经写入，但 Codex 未成功启动。请打开 Codex 应用。")
        }
        guard let current = try storage.readLive() else { throw AccountFailure("切换后的账号文件不存在。") }
        let verifiedInfo = try await identify(current)
        guard try AuthDocument.read(current).accountID == target.accountID, verifiedInfo.email == target.email else {
            throw AccountFailure("Codex 启动后的账号核验失败，请重新登录目标账号。")
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
            try storage.save(registry)
            return id
        }
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = Profile(label: cleanLabel.isEmpty ? (info.email ?? "ChatGPT 账号") : cleanLabel,
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
