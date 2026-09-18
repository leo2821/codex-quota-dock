import AccountCore
import SwiftUI

struct SettingsPanel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.strings("Settings")).font(.system(size: 29, weight: .bold)).foregroundStyle(Palette.ink)
            Text(model.strings("Manage language, refresh frequency, privacy, and account switching."))
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Form {
                Section(model.strings("Language")) {
                    Picker(model.strings("App language"), selection: $model.preferences.language) {
                        Text(model.strings("Follow system")).tag(AppLanguage.system)
                        Text("简体中文").tag(AppLanguage.simplifiedChinese)
                        Text("English").tag(AppLanguage.english)
                    }.onChange(of: model.preferences.language) { _, _ in model.savePreferences() }
                    Text(model.strings("Language changes apply immediately to the window and menu bar."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Section(model.strings("Quota refresh")) {
                    Picker(model.strings("Automatic refresh"), selection: $model.preferences.refreshSeconds) {
                        Text(model.strings("Manual")).tag(0)
                        Text(model.strings("Every minute")).tag(60)
                        Text(model.strings("Every 2 minutes")).tag(120)
                        Text(model.strings("Every 5 minutes")).tag(300)
                        Text(model.strings("Every 15 minutes")).tag(900)
                    }.onChange(of: model.preferences.refreshSeconds) { _, _ in model.savePreferences() }
                    Text(model.strings("Reset times use this Mac's time zone. A new query confirms the quota after a reset."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Section(model.strings("Account switching")) {
                    Toggle(model.strings("Confirm before switching"), isOn: $model.preferences.confirmSwitch)
                        .onChange(of: model.preferences.confirmSwitch) { _, _ in model.savePreferences() }
                    Text(model.strings("Switching restarts Codex. With confirmation disabled, selecting an account switches immediately."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Section(model.strings("Display & startup")) {
                    Toggle(model.strings("Mask email addresses"), isOn: $model.preferences.maskEmails)
                        .onChange(of: model.preferences.maskEmails) { _, _ in model.savePreferences() }
                    Toggle(model.strings("Launch at login"), isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                }
                Section(model.strings("Account data")) {
                    LabeledContent(model.strings("Credentials"), value: model.strings("macOS Keychain"))
                    LabeledContent(model.strings("Quota source"), value: model.strings("Official Codex account API"))
                    LabeledContent(model.strings("Version"), value: "1.1.0")
                    Text(model.strings("Names, settings, and recent results are stored on this Mac. Failed queries keep the previous result with its timestamp."))
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
            Text(model.strings("Rename account")).font(.title2.weight(.semibold))
            TextField(model.strings("Account name"), text: $label).textFieldStyle(.roundedBorder)
                .onSubmit { model.rename(profile, label: label) }
            HStack {
                Spacer()
                Button(model.strings("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.strings("Save")) { model.rename(profile, label: label) }
                    .keyboardShortcut(.defaultAction).disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 380).onAppear { label = profile.label }
    }
}
