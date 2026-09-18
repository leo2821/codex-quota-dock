import AccountCore
import SwiftUI

struct AccountCard: View {
    @ObservedObject var model: AppModel
    let profile: Profile
    private var active: Bool { model.activeID == profile.id }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let usage = profile.usage {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(usage.response.buckets) { bucket in
                            if usage.response.buckets.count > 1 {
                                Text(bucket.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            }
                            if bucket.windows.isEmpty {
                                Text(model.strings("No quota windows were returned for this account")).font(.system(size: 12)).foregroundStyle(.secondary)
                            } else {
                                HStack(alignment: .top, spacing: 24) {
                                    if let primary = bucket.primary { QuotaView(window: primary, now: context.date, strings: model.strings) }
                                    if bucket.primary != nil && bucket.secondary != nil { Divider().frame(height: 94) }
                                    if let secondary = bucket.secondary { QuotaView(window: secondary, now: context.date, strings: model.strings) }
                                }
                            }
                            if let credits = bucket.credits {
                                if credits.unlimited == true {
                                    Label(model.strings("Credits: unlimited"), systemImage: "creditcard").font(.system(size: 11)).foregroundStyle(.secondary)
                                } else if let balance = credits.balance {
                                    Label(model.strings("Credits: %@", balance), systemImage: "creditcard").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if usage.response.buckets.isEmpty {
                            Text(model.strings("Quota data is currently unavailable for this account")).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        HStack {
                            if let count = usage.response.rateLimitResetCredits?.availableCount { Text(model.strings("Available resets: %@", String(count))) }
                            Spacer()
                            if !usage.isCurrent(at: context.date) || profile.lastError != nil {
                                Label(model.strings("Previous result"), systemImage: "clock").foregroundStyle(Palette.warning)
                            }
                            Text(model.strings("Updated %@", model.strings.time(usage.fetchedAt)))
                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            } else if profile.lastError == nil {
                Text(model.strings("Waiting for quota data")).font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 16)
            }
            if let error = profile.lastError {
                Label(profile.localizedError?.description(using: model.strings) ?? error, systemImage: "exclamationmark.circle").font(.system(size: 11))
                    .foregroundStyle(Palette.warning).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(active ? Palette.accent.opacity(0.4) : Color.black.opacity(0.06), lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(String(profile.label.prefix(1)).uppercased()).font(.system(size: 17, weight: .semibold))
                .frame(width: 42, height: 42).foregroundStyle(Palette.accent)
                .background(Palette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(model.displayLabel(profile)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(profile.plan?.capitalized ?? "ChatGPT").font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3).background(Palette.background, in: Capsule())
                    if active {
                        Label(model.strings("In use"), systemImage: "checkmark.circle.fill").font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.success)
                    }
                }
                Text(model.displayEmail(profile)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if model.refreshingID == profile.id { ProgressView().controlSize(.small) }
            if !active { Button(model.strings("Switch & restart")) { model.requestSwitch(profile) }.disabled(model.busy) }
            Menu {
                Button(model.strings("Refresh quota")) { Task { await model.refreshOne(profile) } }
                Button(model.strings("Rename account")) { model.editingProfile = profile }
                if !active { Button(model.strings("Renew credentials")) { Task { await model.renew(profile) } } }
                Button(model.strings("Sign in again")) { Task { await model.login() } }
                Divider()
                Button(model.strings("Remove account"), role: .destructive) { model.pendingRemoval = profile }.disabled(active)
            } label: { Image(systemName: "ellipsis").frame(width: 20, height: 20) }
                .menuStyle(.borderlessButton).fixedSize().disabled(model.busy)
        }
    }
}

struct QuotaView: View {
    let window: QuotaWindow
    let now: Date
    let strings: Localizer
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title(using: strings)).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if let remaining = window.remainingPercent {
                    Text(remaining, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Palette.quota(remaining))
                    Text(strings("% remaining")).font(.system(size: 10)).foregroundStyle(.secondary)
                } else { Text(strings("Unknown")).font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary) }
            }
            GeometryReader { geometry in
                Capsule().fill(Palette.background).overlay(alignment: .leading) {
                    if let remaining = window.remainingPercent {
                        Capsule().fill(Palette.quota(remaining)).frame(width: geometry.size.width * remaining / 100)
                    }
                }
            }.frame(height: 5)
                .accessibilityLabel(strings("%@ remaining: %@", window.title(using: strings), window.remainingPercent.map { String(format: "%.0f%%", $0) } ?? strings("Unknown")))
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise").font(.system(size: 9))
                Text(window.countdown(at: now, using: strings)).font(.system(size: 11))
            }.foregroundStyle(window.needsRefresh(at: now) ? Palette.warning : .secondary)
            if let date = window.resetDate {
                Text(strings.dateTime(date))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
