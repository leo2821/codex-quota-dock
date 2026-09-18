import AccountCore
import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum AppStatus: ExpressibleByStringLiteral {
    case message(String, [String])
    case refreshed(Date)

    init(_ key: String, _ arguments: String...) { self = .message(key, arguments) }
    init(stringLiteral value: String) { self = .message(value, []) }

    func text(using strings: Localizer) -> String {
        switch self {
        case let .message(key, arguments): return strings.format(key, arguments: arguments)
        case let .refreshed(date): return strings("All accounts refreshed · %@", strings.time(date))
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var preferences = Preferences()
    @Published var activeID: UUID?
    @Published var busy = false
    @Published var refreshingID: UUID?
    @Published var status: AppStatus = "Loading accounts"
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

    var strings: Localizer { Localizer(language: preferences.language) }
    var statusText: String { status.text(using: strings) }
    var current: Profile? { profiles.first { $0.id == activeID } }
    var pendingCredentialMigrations: Int { profiles.filter { $0.credentialStorage != .localFile }.count }
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
        status = "Refreshing all accounts"
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
            if profiles.isEmpty { status = "Add an account to view its quota" }
            else if failures > 0 { status = .init("Accounts needing attention: %@. See their cards for details.", String(failures)) }
            else { status = .refreshed(Date()) }
        } catch { fail(error) }
    }

    func refreshOne(_ profile: Profile) async {
        await perform(.init("Refreshing %@", profile.label)) { service in
            _ = try await service.synchronizeCurrent()
            try await service.refresh(profile.id)
        }
    }

    func login() async {
        guard let service, !busy else { return }
        let existingIDs = Set(profiles.map(\.id))
        busy = true
        isLoggingIn = true
        status = "Complete ChatGPT sign-in in your browser"
        defer { busy = false; isLoggingIn = false; loginURL = nil; syncState() }
        do {
            let id = try await service.beginLogin { url in
                self.loginURL = url
                guard NSWorkspace.shared.open(url) else {
                    throw AccountFailure("Unable to open the browser. Open the sign-in page and try again.")
                }
            }
            try await service.refresh(id)
            status = existingIDs.contains(id) ? "Existing account credentials updated" : "New account added"
        } catch is CancellationError { status = "Sign-in cancelled" }
        catch { fail(error) }
    }

    func cancelLogin() async {
        do { try await service?.cancelLogin() } catch { fail(error) }
    }

    func migrateAccounts() async {
        await perform("Migrating saved accounts") { service in
            for profile in service.registry.profiles where profile.credentialStorage != .localFile {
                self.refreshingID = profile.id
                self.status = .init("Migrating %@", self.displayLabel(profile))
                try await service.migrateCredential(profile.id)
                self.syncState()
            }
        }
        refreshingID = nil
        if pendingCredentialMigrations == 0 { await refreshAll() }
    }

    func openAccountFiles() {
        guard let service else { return }
        NSWorkspace.shared.activateFileViewerSelecting([service.storage.vault.root])
    }

    func importCurrent() async {
        await perform("Importing the current account") { service in
            guard let data = try service.storage.readLive() else { throw AccountFailure("Codex is not signed in.") }
            let id = try await service.importCredential(data, label: "")
            _ = try await service.synchronizeCurrent()
            try await service.refresh(id)
        }
    }

    func importFile() async {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = strings("Choose a Codex account's auth.json")
        panel.prompt = strings("Import")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard await panel.begin() == .OK else { return }
        await perform("Importing accounts") { service in
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
        await perform(.init("Switching to %@", profile.label)) { service in try await service.switchAccount(profile.id) }
    }

    func renew(_ profile: Profile) async {
        await perform("Renewing account credentials") { service in
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
        do { try service?.remove(profile.id); pendingRemoval = nil; syncState(); status = "Account removed" }
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
            if enabled && !launchAtLogin { status = "Allow this app in System Settings → Login Items" }
        } catch { fail(error) }
    }

    func openCodex() {
        if let installation = service?.installation { NSWorkspace.shared.open(installation.application) }
    }

    func displayEmail(_ profile: Profile) -> String {
        guard let email = profile.email else { return strings("ChatGPT subscription account") }
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

    private func perform(_ message: AppStatus, operation: (AccountService) async throws -> Void) async {
        guard let service, !busy else { return }
        busy = true
        status = message
        defer { busy = false; syncState() }
        do { try await operation(service); status = "Done" }
        catch { fail(error) }
    }

    private func syncState() {
        guard let service else { return }
        profiles = service.registry.profiles
        preferences = service.registry.preferences
        activeID = service.activeID
    }

    private func fail(_ error: Error) {
        errorMessage = (error as? AccountFailure)?.description(using: strings) ?? error.localizedDescription
        status = "Unable to complete the operation. Check the message."
    }
}
