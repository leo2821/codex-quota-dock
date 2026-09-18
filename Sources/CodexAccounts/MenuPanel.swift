import AccountCore
import AppKit
import SwiftUI

struct MenuPanel: View {
    @ObservedObject var model: AppModel
    var openMainWindow: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Codex Quota Dock", systemImage: "person.2.circle").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { Task { await model.refreshAll() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(model.busy).help(model.strings("Refresh all accounts"))
            }
            if model.profiles.isEmpty {
                Text(model.strings("Open the account manager to add a ChatGPT account."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 15)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.sortedProfiles) { profile in profileRow(profile) }
                    }
                }.frame(maxHeight: min(CGFloat(model.profiles.count) * 132, 470))
            }
            Text(model.statusText).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            Divider()
            HStack {
                Button(model.strings("Open account manager")) { openMainWindow() }
                Spacer()
                Button(model.strings("Quit")) { NSApp.terminate(nil) }
            }.font(.system(size: 12))
        }.padding(18).frame(width: 420).tint(Palette.accent).environment(\.locale, model.strings.locale)
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
                    Button(model.strings("Switch")) {
                        if model.preferences.confirmSwitch {
                            openMainWindow()
                        }
                        model.requestSwitch(profile)
                    }.disabled(model.busy).help(model.strings("Switch and restart Codex"))
                }
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if let usage = profile.usage, let bucket = usage.response.mainBucket {
                    ForEach(Array(bucket.windows.enumerated()), id: \.offset) { _, window in
                        HStack {
                            Text(window.title(using: model.strings)).frame(width: 86, alignment: .leading)
                            Text(window.remainingPercent.map { String(format: "%.0f%%", $0) } ?? model.strings("Unknown"))
                                .foregroundStyle(Palette.quota(window.remainingPercent)).monospacedDigit()
                            Spacer()
                            Text(window.countdown(at: context.date, using: model.strings)).foregroundStyle(.secondary)
                        }.font(.system(size: 10))
                    }
                    if profile.lastError != nil || !usage.isCurrent(at: context.date) {
                        Text(model.strings("Previous result: %@", model.strings.time(usage.fetchedAt)))
                            .font(.system(size: 10)).foregroundStyle(Palette.warning)
                    }
                } else { Text(model.strings("Quota not yet available")).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }.padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }
}
