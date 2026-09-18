import AccountCore
import SwiftUI

struct SettingsPanel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("应用设置").font(.system(size: 29, weight: .bold)).foregroundStyle(Palette.ink)
            Text("管理刷新频率、账号显示与切换方式。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Form {
                Section("额度刷新") {
                    Picker("自动刷新", selection: $model.preferences.refreshSeconds) {
                        Text("手动刷新").tag(0)
                        Text("每分钟").tag(60)
                        Text("每 2 分钟").tag(120)
                        Text("每 5 分钟").tag(300)
                        Text("每 15 分钟").tag(900)
                    }.onChange(of: model.preferences.refreshSeconds) { _, _ in model.savePreferences() }
                    Text("重置时间使用这台 Mac 的时区。到达重置时间后，通过新的查询确认额度。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Section("账号切换") {
                    Toggle("切换前显示确认提示", isOn: $model.preferences.confirmSwitch)
                        .onChange(of: model.preferences.confirmSwitch) { _, _ in model.savePreferences() }
                    Text("切换会重新启动 Codex。关闭确认提示后，点击账号即可切换。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Section("显示与启动") {
                    Toggle("隐藏邮箱中的部分字符", isOn: $model.preferences.maskEmails)
                        .onChange(of: model.preferences.maskEmails) { _, _ in model.savePreferences() }
                    Toggle("登录 macOS 时启动", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                }
                Section("账号数据") {
                    LabeledContent("登录凭据", value: "macOS 钥匙串")
                    LabeledContent("额度来源", value: "Codex 官方账号接口")
                    LabeledContent("版本", value: "1.0.0")
                    Text("账号名称、设置和最近查询结果保存在本机。查询失败时会保留带时间标记的记录。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden).padding(.horizontal, -20)
        }.padding(.horizontal, 30).padding(.top, 45)
    }
}

struct RenameSheet: View {
    @ObservedObject var model: AppModel
    let profile: Profile
    @State private var label = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("修改账号名称").font(.title2.weight(.semibold))
            TextField("账号名称", text: $label).textFieldStyle(.roundedBorder)
                .onSubmit { model.rename(profile, label: label) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { model.rename(profile, label: label) }
                    .keyboardShortcut(.defaultAction).disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 380).onAppear { label = profile.label }
    }
}
