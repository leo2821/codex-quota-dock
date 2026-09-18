import SwiftUI

struct AddAccountSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("添加账号").font(.system(size: 23, weight: .semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("关闭")
            }
            Text("选择一种方式添加你的 ChatGPT 账号。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            action("登录新的 ChatGPT 账号", detail: "打开浏览器，登录后自动保存账号。", symbol: "person.crop.circle.badge.plus") {
                dismiss()
                Task { await model.login() }
            }
            action("导入当前 Codex 账号", detail: "保存这台 Mac 上已经登录的账号。", symbol: "arrow.down.circle") {
                dismiss()
                Task { await model.importCurrent() }
            }
            action("从 auth.json 文件导入", detail: "选择一个或多个已有的 Codex 账号文件。", symbol: "doc.badge.plus") {
                dismiss()
                Task { await model.importFile() }
            }
            Label("账号登录凭据保存在本机钥匙串", systemImage: "lock.shield")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(28).frame(width: 440).tint(Palette.accent)
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
