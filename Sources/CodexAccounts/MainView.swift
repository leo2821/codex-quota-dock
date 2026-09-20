import AccountCore
import AppKit
import SwiftUI

enum Palette {
    static let background = Color(red: 0.953, green: 0.965, blue: 0.984)
    static let sidebar = Color(red: 0.129, green: 0.184, blue: 0.278)
    static let ink = Color(red: 0.129, green: 0.184, blue: 0.278)
    static let accent = Color(red: 0.208, green: 0.412, blue: 0.875)
    static let success = Color(red: 0.067, green: 0.475, blue: 0.38)
    static let warning = Color(red: 0.71, green: 0.396, blue: 0.086)
    static let danger = Color(red: 0.714, green: 0.239, blue: 0.298)
    static func quota(_ percent: Double?) -> Color {
        guard let percent else { return .secondary }
        if percent <= 10 { return danger }
        if percent <= 25 { return warning }
        return accent
    }
}

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var showingAddAccount = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                if model.section == "settings" { SettingsPanel(model: model) }
                else { accounts }
                footer
            }.background(Palette.background)
        }
        .tint(Palette.accent).preferredColorScheme(.light)
        .alert(model.strings("Unable to complete the operation"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(model.strings("OK")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert(model.strings("Switch to %@?", model.pendingSwitch.map(model.displayLabel) ?? model.strings("Selected account")), isPresented: Binding(
            get: { model.pendingSwitch != nil }, set: { if !$0 { model.pendingSwitch = nil } })) {
            Button(model.strings("Cancel"), role: .cancel) { model.pendingSwitch = nil }
            Button(model.strings("Switch and restart Codex")) {
                if let profile = model.pendingSwitch { Task { await model.switchNow(profile) } }
            }
        } message: { Text(model.strings("Switching restarts Codex and may interrupt running tasks. Switch after your tasks finish.")) }
        .alert(model.strings("Remove the saved account?"), isPresented: Binding(get: { model.pendingRemoval != nil }, set: { if !$0 { model.pendingRemoval = nil } })) {
            Button(model.strings("Cancel"), role: .cancel) { model.pendingRemoval = nil }
            Button(model.strings("Remove account"), role: .destructive) { if let profile = model.pendingRemoval { model.remove(profile) } }
        } message: { Text(model.strings("The saved account record and local auth.json for %@ will be deleted from this app.", model.pendingRemoval.map(model.displayLabel) ?? model.strings("Selected account"))) }
        .sheet(item: $model.editingProfile) { profile in RenameSheet(model: model, profile: profile) }
        .sheet(isPresented: $showingAddAccount) { AddAccountSheet(model: model) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "person.crop.square.filled.and.at.rectangle")
                    .font(.system(size: 28, weight: .medium)).foregroundStyle(Color.white)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Codex\nQuota Dock").font(.system(size: 19, weight: .semibold))
                    Text(model.strings("Accounts & usage")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
            }.padding(.top, 48).padding(.bottom, 38)
            navButton(model.strings("Accounts & usage"), symbol: "square.grid.2x2", section: "accounts")
            navButton(model.strings("Settings"), symbol: "slider.horizontal.3", section: "settings").padding(.top, 7)
            Spacer()
            if let current = model.current {
                VStack(alignment: .leading, spacing: 9) {
                    Label(model.strings("Current Codex account"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                    Text(model.displayLabel(current)).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                    Text(current.plan?.capitalized ?? "ChatGPT").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }
            Button { model.openCodex() } label: {
                Label(model.strings("Open Codex"), systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).font(.system(size: 13)).padding(.top, 22).padding(.bottom, 25)
        }.padding(.horizontal, 22).frame(width: 218).foregroundStyle(.white).background(Palette.sidebar)
    }

    private func navButton(_ title: String, symbol: String, section: String) -> some View {
        Button { model.section = section } label: {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 13).padding(.vertical, 12)
                .background(model.section == section ? .white.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }

    private var accounts: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.strings("Accounts & usage")).font(.system(size: 29, weight: .bold)).foregroundStyle(Palette.ink)
                    Text(model.strings("Check your remaining quota and choose your next account."))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await model.refreshAll() } } label: {
                    Label(model.strings("Refresh all"), systemImage: "arrow.clockwise")
                }.controlSize(.large).disabled(model.busy)
                addMenu.controlSize(.large)
            }
            if model.isLoggingIn { loginBanner }
            if model.pendingCredentialMigrations > 0 { migrationBanner }
            if let error = model.currentAccountError {
                Label(model.strings("Current account needs attention: %@", error.description(using: model.strings)),
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(Palette.warning)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 9))
            }
            if model.profiles.isEmpty { emptyState }
            else {
                HStack(spacing: 14) {
                    Label(model.strings.accountCount(model.profiles.count), systemImage: "person.2")
                    if let date = model.nextReset {
                        Divider().frame(height: 13)
                        Text(model.strings("Next reset: %@", model.strings.dateTime(date)))
                    }
                    Spacer()
                }.font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(model.strings("Search by name or email"), text: $model.search).textFieldStyle(.plain)
                    }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 8)).frame(maxWidth: 310)
                    Spacer()
                    Toggle(model.strings("Sort by remaining quota"), isOn: $model.preferences.sortByQuota)
                        .toggleStyle(.checkbox).onChange(of: model.preferences.sortByQuota) { _, _ in model.savePreferences() }
                }.font(.system(size: 12))
                if let recommendation = model.recommendation, model.profiles.count > 1 {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkle").foregroundStyle(Palette.accent)
                        Text(model.strings("Available account: %@", model.displayLabel(recommendation))).lineLimit(1)
                        Spacer()
                        Button(model.strings("Switch & restart")) { model.requestSwitch(recommendation) }.disabled(model.busy)
                    }.font(.system(size: 12)).padding(12)
                        .background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                }
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(model.visibleProfiles) { profile in AccountCard(model: model, profile: profile) }
                        if model.visibleProfiles.isEmpty {
                            ContentUnavailableView(model.strings("No matching accounts"), systemImage: "magnifyingglass",
                                description: Text(model.strings("Try another name or email."))).padding(.vertical, 30)
                        }
                    }.padding(.bottom, 8)
                }.scrollIndicators(.hidden)
            }
        }.padding(.horizontal, 30).padding(.top, 45)
    }

    private var addMenu: some View {
        Button { showingAddAccount = true } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                Text(model.strings("Add account"))
            }.font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityLabel(model.strings("Add account")).disabled(model.busy)
    }

    private var emptyState: some View {
        VStack(spacing: 17) {
            Spacer()
            Image(systemName: "person.crop.rectangle.badge.plus").font(.system(size: 55, weight: .light)).foregroundStyle(Palette.accent)
            Text(model.strings("All your accounts at a glance")).font(.system(size: 24, weight: .semibold))
            Text(model.strings("Add ChatGPT accounts to check quotas, see reset times, and switch quickly."))
                .font(.system(size: 13)).foregroundStyle(.secondary)
            HStack {
                Button(model.strings("Sign in with ChatGPT")) { Task { await model.login() } }.buttonStyle(.borderedProminent)
                Button(model.strings("Import auth.json")) { Task { await model.importFile() } }
            }.controlSize(.large).padding(.top, 7).disabled(model.busy)
            Label(model.strings("Each account is saved as a private local auth.json file"), systemImage: "lock.shield")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
            Spacer()
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private var loginBanner: some View {
        HStack {
            ProgressView().controlSize(.small)
            Text(model.strings("Complete sign-in in your browser")).font(.system(size: 12))
            Spacer()
            if let url = model.loginURL { Button(model.strings("Open sign-in page")) { NSWorkspace.shared.open(url) } }
            Button(model.strings("Cancel sign-in")) { Task { await model.cancelLogin() } }
        }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 9))
    }

    private var migrationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.person.crop").foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.strings("%@ saved accounts need migration", String(model.pendingCredentialMigrations)))
                    .font(.system(size: 12, weight: .semibold))
                Text(model.strings("Save existing accounts as local files. macOS may request Keychain access for each account during migration."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(model.strings("Migrate saved accounts")) { Task { await model.migrateAccounts() } }
                .disabled(model.busy)
        }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 9))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.busy { ProgressView().controlSize(.mini) }
            else {
                Circle().fill(model.errorMessage == nil && model.currentAccountError == nil
                              && model.profiles.allSatisfy { $0.lastError == nil } ? Palette.success : Palette.warning)
                    .frame(width: 6, height: 6)
            }
            Text(model.statusText).lineLimit(1)
            Spacer()
            Image(systemName: "lock.shield")
            Text(model.strings("Stored on this Mac"))
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 30).padding(.vertical, 15)
    }
}
