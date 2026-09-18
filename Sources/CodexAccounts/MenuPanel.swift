import AccountCore
import AppKit
import SwiftUI

struct MenuPanel: View {
    @ObservedObject var model: AppModel
    var openMainWindow: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Codex Accounts", systemImage: "person.2.circle").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { Task { await model.refreshAll() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(model.busy).help("刷新全部账号")
            }
            if model.profiles.isEmpty {
                Text("打开账号管理，添加 ChatGPT 账号。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 15)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.sortedProfiles) { profile in profileRow(profile) }
                    }
                }.frame(maxHeight: min(CGFloat(model.profiles.count) * 132, 470))
            }
            Text(model.status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            Divider()
            HStack {
                Button("打开账号管理") { openMainWindow() }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }.font(.system(size: 12))
        }.padding(18).frame(width: 390).tint(Palette.accent)
    }

    private func profileRow(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayLabel(profile)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(model.displayEmail(profile)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if profile.id == model.activeID { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.success) }
                else {
                    Button("切换") {
                        if model.preferences.confirmSwitch {
                            openMainWindow()
                        }
                        model.requestSwitch(profile)
                    }.disabled(model.busy).help("切换并重新启动 Codex")
                }
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if let usage = profile.usage, let bucket = usage.response.mainBucket {
                    ForEach(Array(bucket.windows.enumerated()), id: \.offset) { _, window in
                        HStack {
                            Text(window.title).frame(width: 66, alignment: .leading)
                            Text(window.remainingPercent.map { String(format: "%.0f%%", $0) } ?? "未知")
                                .foregroundStyle(Palette.quota(window.remainingPercent)).monospacedDigit()
                            Spacer()
                            Text(window.countdown(at: context.date)).foregroundStyle(.secondary)
                        }.font(.system(size: 10))
                    }
                    if profile.lastError != nil || !usage.isCurrent(at: context.date) {
                        Text("上次查询：\(usage.fetchedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 10)).foregroundStyle(Palette.warning)
                    }
                } else { Text("额度尚未获取").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }.padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }
}
