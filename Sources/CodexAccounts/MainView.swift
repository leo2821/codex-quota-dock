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
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("知道了") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("切换到 \(model.pendingSwitch?.label ?? "所选账号")？", isPresented: Binding(
            get: { model.pendingSwitch != nil }, set: { if !$0 { model.pendingSwitch = nil } })) {
            Button("取消", role: .cancel) { model.pendingSwitch = nil }
            Button("切换并重启 Codex") {
                if let profile = model.pendingSwitch { Task { await model.switchNow(profile) } }
            }
        } message: { Text("切换会重新启动 Codex，正在执行的任务可能中断。请在任务完成后切换。") }
        .alert("移除保存的账号？", isPresented: Binding(get: { model.pendingRemoval != nil }, set: { if !$0 { model.pendingRemoval = nil } })) {
            Button("取消", role: .cancel) { model.pendingRemoval = nil }
            Button("移除账号", role: .destructive) { if let profile = model.pendingRemoval { model.remove(profile) } }
        } message: { Text("将从本应用和钥匙串中删除 \(model.pendingRemoval?.label ?? "该账号") 的保存记录。") }
        .sheet(item: $model.editingProfile) { profile in RenameSheet(model: model, profile: profile) }
        .sheet(isPresented: $showingAddAccount) { AddAccountSheet(model: model) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "person.crop.square.filled.and.at.rectangle")
                    .font(.system(size: 28, weight: .medium)).foregroundStyle(Color.white)
                VStack(alignment: .leading, spacing: 3) {
                    Text("QuotaDock").font(.system(size: 20, weight: .semibold))
                    Text("账号与额度").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
            }.padding(.top, 48).padding(.bottom, 38)
            navButton("账号与额度", symbol: "square.grid.2x2", section: "accounts")
            navButton("应用设置", symbol: "slider.horizontal.3", section: "settings").padding(.top, 7)
            Spacer()
            if let current = model.current {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Codex 当前账号", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                    Text(model.displayLabel(current)).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                    Text(current.plan?.capitalized ?? "ChatGPT").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }
            Button { model.openCodex() } label: {
                Label("打开 Codex", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity, alignment: .leading)
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
                    Text("账号与额度").font(.system(size: 29, weight: .bold)).foregroundStyle(Palette.ink)
                    Text("查看剩余额度，选择接下来使用的账号。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await model.refreshAll() } } label: {
                    Label("刷新全部", systemImage: "arrow.clockwise")
                }.controlSize(.large).disabled(model.busy)
                addMenu.controlSize(.large)
            }
            if model.isLoggingIn { loginBanner }
            if model.profiles.isEmpty { emptyState }
            else {
                HStack(spacing: 14) {
                    Label("\(model.profiles.count) 个账号", systemImage: "person.2")
                    if let date = model.nextReset {
                        Divider().frame(height: 13)
                        Text("最近重置：\(date.formatted(.dateTime.month().day().hour().minute()))")
                    }
                    Spacer()
                }.font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索账号名称或邮箱", text: $model.search).textFieldStyle(.plain)
                    }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 8)).frame(maxWidth: 310)
                    Spacer()
                    Toggle("按剩余额度排序", isOn: $model.preferences.sortByQuota)
                        .toggleStyle(.checkbox).onChange(of: model.preferences.sortByQuota) { _, _ in model.savePreferences() }
                }.font(.system(size: 12))
                if let recommendation = model.recommendation, model.profiles.count > 1 {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkle").foregroundStyle(Palette.accent)
                        Text("可用账号：\(model.displayLabel(recommendation))").lineLimit(1)
                        Spacer()
                        Button("切换并重启") { model.requestSwitch(recommendation) }.disabled(model.busy)
                    }.font(.system(size: 12)).padding(12)
                        .background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                }
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(model.visibleProfiles) { profile in AccountCard(model: model, profile: profile) }
                        if model.visibleProfiles.isEmpty {
                            ContentUnavailableView.search(text: model.search).padding(.vertical, 30)
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
                Text("添加账号")
            }.font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityLabel("添加账号").disabled(model.busy)
    }

    private var emptyState: some View {
        VStack(spacing: 17) {
            Spacer()
            Image(systemName: "person.crop.rectangle.badge.plus").font(.system(size: 55, weight: .light)).foregroundStyle(Palette.accent)
            Text("让多个账号一目了然").font(.system(size: 24, weight: .semibold))
            Text("添加 ChatGPT 账号后，可同时查看额度、重置时间并快速切换。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            HStack {
                Button("登录 ChatGPT 账号") { Task { await model.login() } }.buttonStyle(.borderedProminent)
                Button("导入 auth.json") { Task { await model.importFile() } }
            }.controlSize(.large).padding(.top, 7).disabled(model.busy)
            Label("登录凭据保存在本机钥匙串", systemImage: "lock.shield")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
            Spacer()
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private var loginBanner: some View {
        HStack {
            ProgressView().controlSize(.small)
            Text("请在浏览器中完成账号登录").font(.system(size: 12))
            Spacer()
            if let url = model.loginURL { Button("打开登录页面") { NSWorkspace.shared.open(url) } }
            Button("取消登录") { Task { await model.cancelLogin() } }
        }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 9))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.busy { ProgressView().controlSize(.mini) }
            else { Circle().fill(model.errorMessage == nil ? Palette.success : Palette.warning).frame(width: 6, height: 6) }
            Text(model.status).lineLimit(1)
            Spacer()
            Image(systemName: "lock.shield")
            Text("本机存储")
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 30).padding(.vertical, 15)
    }
}
