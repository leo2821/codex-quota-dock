import AccountCore
import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var preferences = Preferences()
    @Published var activeID: UUID?
    @Published var busy = false
    @Published var refreshingID: UUID?
    @Published var status = "正在读取账号"
    @Published var errorMessage: String?
    @Published var search = ""
    @Published var section = "accounts"
    @Published var loginURL: URL?
    @Published var isLoggingIn = false
    @Published var pendingSwitch: Profile?
    @Published var pendingRemoval: Profile?
    @Published var editingProfile: Profile?
    @Published var started = false
    @Published var now = Date()
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    private var service: AccountService?
    private var lastRefresh: Date?
    private var timer: Task<Void, Never>?

    var current: Profile? { profiles.first { $0.id == activeID } }
    var visibleProfiles: [Profile] {
        sortedProfiles.filter {
            search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) ||
            ($0.email?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }
    var sortedProfiles: [Profile] {
        var result = profiles
        if preferences.sortByQuota {
            result.sort {
                let left = eligibleScore($0), right = eligibleScore($1)
                return left == right ? $0.createdAt < $1.createdAt : left > right
            }
        }
        return result
    }
    var recommendation: Profile? {
        profiles.filter { $0.id != activeID && eligibleScore($0) > 0 }
            .max { eligibleScore($0) < eligibleScore($1) }
    }
    var nextReset: Date? {
        profiles.flatMap { $0.usage?.response.buckets.flatMap(\.windows) ?? [] }
            .compactMap(\.resetDate).filter { $0 > Date() }.min()
    }
    var menuTitle: String {
        guard let current, current.lastError == nil, let usage = current.usage,
              usage.isCurrent(at: Date()), let percent = usage.availablePercent else { return "" }
        return String(format: "%.0f%%", percent)
    }

    func start() async {
        guard !started else { return }
        started = true
        do {
            let environment = ProcessInfo.processInfo.environment
            let root: URL
            if let override = environment["CODEX_ACCOUNTS_DATA_DIR"] { root = URL(fileURLWithPath: override) }
            else {
                root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true).appendingPathComponent("CodexAccounts")
            }
            let codexDirectory = environment["CODEX_ACCOUNTS_TARGET_DIR"].map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
            let storage = try AccountStorage(root: root, liveAuth: codexDirectory.appendingPathComponent("auth.json"))
            service = try AccountService(storage: storage, installation: CodexInstallation.discover())
            syncState()
            await refreshAll()
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    guard let self else { return }
                    self.now = Date()
                    if self.preferences.refreshSeconds > 0, !self.busy,
                       Date().timeIntervalSince(self.lastRefresh ?? .distantPast) >= Double(self.preferences.refreshSeconds) {
                        await self.refreshAll()
                    }
                }
            }
        } catch { fail(error) }
    }

    func refreshAll() async {
        guard let service, !busy else { return }
        busy = true
        defer { busy = false; refreshingID = nil; syncState() }
        status = "正在刷新全部账号"
        do {
            _ = try await service.synchronizeCurrent()
            syncState()
            var failures = 0
            for profile in service.registry.profiles {
                refreshingID = profile.id
                do { try await service.refresh(profile.id) }
                catch { failures += 1 }
                syncState()
            }
            lastRefresh = Date()
            if profiles.isEmpty { status = "添加账号即可查看额度" }
            else if failures > 0 { status = "\(failures) 个账号需要检查，详情见账号卡片" }
            else { status = "全部账号已刷新 · \(Date().formatted(date: .omitted, time: .shortened))" }
        } catch { fail(error) }
    }

    func refreshOne(_ profile: Profile) async {
        await perform("正在刷新 \(profile.label)") { service in
            _ = try await service.synchronizeCurrent()
            try await service.refresh(profile.id)
        }
    }

    func login() async {
        guard let service, !busy else { return }
        let existingIDs = Set(profiles.map(\.id))
        busy = true
        isLoggingIn = true
        status = "请在浏览器中完成 ChatGPT 登录"
        defer { busy = false; isLoggingIn = false; loginURL = nil; syncState() }
        do {
            let id = try await service.beginLogin { url in
                self.loginURL = url
                NSWorkspace.shared.open(url)
            }
            try await service.refresh(id)
            status = existingIDs.contains(id) ? "该账号已存在，登录信息已更新" : "新账号已添加"
        } catch is CancellationError { status = "登录已取消" }
        catch { fail(error) }
    }

    func cancelLogin() async {
        do { try await service?.cancelLogin() } catch { fail(error) }
    }

    func importCurrent() async {
        await perform("正在导入当前账号") { service in
            guard let data = try service.storage.readLive() else { throw AccountFailure("当前 Codex 尚未登录。") }
            let id = try await service.importCredential(data, label: "当前账号")
            _ = try await service.synchronizeCurrent()
            try await service.refresh(id)
        }
    }

    func importFile() async {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "选择 Codex 账号的 auth.json"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard await panel.begin() == .OK else { return }
        await perform("正在导入账号") { service in
            for url in panel.urls {
                let data = try Data(contentsOf: url)
                let id = try await service.importCredential(data, label: "")
                try await service.refresh(id)
            }
        }
    }

    func requestSwitch(_ profile: Profile) {
        guard !busy, profile.id != activeID else { return }
        if preferences.confirmSwitch { pendingSwitch = profile }
        else { Task { await switchNow(profile) } }
    }

    func switchNow(_ profile: Profile) async {
        pendingSwitch = nil
        await perform("正在切换到 \(profile.label)") { service in try await service.switchAccount(profile.id) }
    }

    func renew(_ profile: Profile) async {
        await perform("正在更新账号登录") { service in
            _ = try await service.synchronizeCurrent()
            try await service.updateCredential(profile.id)
        }
    }

    func rename(_ profile: Profile, label: String) {
        guard !busy else { return }
        do { try service?.rename(profile.id, label: label); editingProfile = nil; syncState() }
        catch { fail(error) }
    }

    func remove(_ profile: Profile) {
        guard !busy else { return }
        do { try service?.remove(profile.id); pendingRemoval = nil; syncState(); status = "账号已移除" }
        catch { fail(error) }
    }

    func savePreferences() {
        do { try service?.updatePreferences(preferences) } catch { fail(error) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { status = "请在系统设置的登录项中允许此应用" }
        } catch { fail(error) }
    }

    func openCodex() {
        if let installation = service?.installation { NSWorkspace.shared.open(installation.application) }
    }

    func displayEmail(_ profile: Profile) -> String {
        guard let email = profile.email else { return "ChatGPT 订阅账号" }
        guard preferences.maskEmails else { return email }
        let parts = email.split(separator: "@", maxSplits: 1)
        return parts.count == 2 ? String(parts[0].prefix(1)) + "••••@" + parts[1] : "••••••"
    }

    func displayLabel(_ profile: Profile) -> String {
        preferences.maskEmails && profile.label.contains("@") ? displayEmail(profile) : profile.label
    }

    private func eligibleScore(_ profile: Profile) -> Double {
        guard profile.lastError == nil, let usage = profile.usage, usage.isCurrent(at: Date()) else { return -1 }
        return usage.availablePercent ?? -1
    }

    private func perform(_ message: String, operation: (AccountService) async throws -> Void) async {
        guard let service, !busy else { return }
        busy = true
        status = message
        defer { busy = false; syncState() }
        do { try await operation(service); status = "操作完成" }
        catch { fail(error) }
    }

    private func syncState() {
        guard let service else { return }
        profiles = service.registry.profiles
        preferences = service.registry.preferences
        activeID = service.activeID
    }

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        status = "操作未完成，请查看提示"
    }
}
