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
                                Text("该账号未提供周期额度").font(.system(size: 12)).foregroundStyle(.secondary)
                            } else {
                                HStack(alignment: .top, spacing: 24) {
                                    if let primary = bucket.primary { QuotaView(window: primary, now: context.date) }
                                    if bucket.primary != nil && bucket.secondary != nil { Divider().frame(height: 94) }
                                    if let secondary = bucket.secondary { QuotaView(window: secondary, now: context.date) }
                                }
                            }
                            if let credits = bucket.credits {
                                if credits.unlimited == true {
                                    Label("额度余额：无限制", systemImage: "creditcard").font(.system(size: 11)).foregroundStyle(.secondary)
                                } else if let balance = credits.balance {
                                    Label("额度余额：\(balance)", systemImage: "creditcard").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if usage.response.buckets.isEmpty {
                            Text("服务暂未提供该账号的额度数据").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        HStack {
                            if let count = usage.response.rateLimitResetCredits?.availableCount { Text("可用重置次数：\(count)") }
                            Spacer()
                            if !usage.isCurrent(at: context.date) || profile.lastError != nil {
                                Label("上次查询", systemImage: "clock").foregroundStyle(Palette.warning)
                            }
                            Text("更新于 \(usage.fetchedAt.formatted(date: .omitted, time: .shortened))")
                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            } else if profile.lastError == nil {
                Text("等待查询额度").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 16)
            }
            if let error = profile.lastError {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11))
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
                        Label("当前使用", systemImage: "checkmark.circle.fill").font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.success)
                    }
                }
                Text(model.displayEmail(profile)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if model.refreshingID == profile.id { ProgressView().controlSize(.small) }
            if !active { Button("切换并重启") { model.requestSwitch(profile) }.disabled(model.busy) }
            Menu {
                Button("刷新额度") { Task { await model.refreshOne(profile) } }
                Button("修改账号名称") { model.editingProfile = profile }
                if !active { Button("更新登录凭据") { Task { await model.renew(profile) } } }
                Button("重新登录账号") { Task { await model.login() } }
                Divider()
                Button("移除账号", role: .destructive) { model.pendingRemoval = profile }.disabled(active)
            } label: { Image(systemName: "ellipsis").frame(width: 20, height: 20) }
                .menuStyle(.borderlessButton).fixedSize().disabled(model.busy)
        }
    }
}

struct QuotaView: View {
    let window: QuotaWindow
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if let remaining = window.remainingPercent {
                    Text(remaining, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Palette.quota(remaining))
                    Text("% 剩余").font(.system(size: 10)).foregroundStyle(.secondary)
                } else { Text("未知").font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary) }
            }
            GeometryReader { geometry in
                Capsule().fill(Palette.background).overlay(alignment: .leading) {
                    if let remaining = window.remainingPercent {
                        Capsule().fill(Palette.quota(remaining)).frame(width: geometry.size.width * remaining / 100)
                    }
                }
            }.frame(height: 5)
                .accessibilityLabel("\(window.title)剩余 \(window.remainingPercent.map { String(format: "%.0f%%", $0) } ?? "未知")")
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise").font(.system(size: 9))
                Text(window.countdown(at: now)).font(.system(size: 11))
            }.foregroundStyle(window.needsRefresh(at: now) ? Palette.warning : .secondary)
            if let date = window.resetDate {
                Text(date.formatted(.dateTime.month().day().hour().minute()))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
