import SwiftUI

struct AddAccountSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(model.strings("Add account")).font(.system(size: 23, weight: .semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel(model.strings("Close"))
            }
            Text(model.strings("Choose how to add your ChatGPT account."))
                .font(.system(size: 13)).foregroundStyle(.secondary)
            action(model.strings("Sign in to a new ChatGPT account"), detail: model.strings("Open your browser and save the account after sign-in."), symbol: "person.crop.circle.badge.plus") {
                dismiss()
                Task { await model.login() }
            }
            action(model.strings("Import current Codex account"), detail: model.strings("Save the account already signed in on this Mac."), symbol: "arrow.down.circle") {
                dismiss()
                Task { await model.importCurrent() }
            }
            action(model.strings("Import from auth.json"), detail: model.strings("Choose one or more existing Codex account files."), symbol: "doc.badge.plus") {
                dismiss()
                Task { await model.importFile() }
            }
            Label(model.strings("Credentials are stored in your Mac's Keychain"), systemImage: "lock.shield")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(28).frame(width: 480).tint(Palette.accent)
    }
    private func action(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(Palette.accent).frame(width: 35)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}
