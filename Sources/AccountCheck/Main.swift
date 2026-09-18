import AccountCore
import Darwin
import Foundation

@main
struct AccountCheck {
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw AccountFailure("验证失败：" + message) }
        print("通过：" + message)
    }

    @MainActor
    static func main() async throws {
        setvbuf(stdout, nil, _IONBF, 0)
        guard CommandLine.arguments.count == 3 else {
            throw AccountFailure("用法：account-check 工作目录 auth.json路径")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        let authURL = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
        guard root != authURL.deletingLastPathComponent(), !root.path.hasPrefix("/tmp/") else {
            throw AccountFailure("验证需要独立的工作目录。")
        }
        try PrivateFiles.createDirectory(root)
        let data = try Data(contentsOf: authURL)
        let document = try AuthDocument.read(data)
        let installation = try CodexInstallation.discover()
        let session = root.appendingPathComponent(UUID().uuidString)
        try PrivateFiles.createDirectory(session)
        let client = try CodexClient(installation: installation, home: session)
        try await client.initialize()
        try await client.useExternalTokens(document, plan: nil)
        let account = try await client.readAccount()
        let usage = try await client.readLimits()
        try check(account.type == "chatgpt", "真实 Codex 账号接口")
        try check(!usage.response.buckets.isEmpty, "真实额度接口返回额度类别")
        try check(usage.response.mainBucket != nil, "识别 Codex 主要额度")
        let snapshotData = try JSONEncoder().encode(usage)
        try check(try JSONDecoder().decode(UsageSnapshot.self, from: snapshotData) == usage, "真实额度数据保存和读取一致")
        for bucket in usage.response.buckets {
            for window in bucket.windows {
                print("\(bucket.title) / \(window.title)：剩余 \(window.remainingPercent.map { String(format: "%.1f%%", $0) } ?? "未知")，\(window.countdown(at: Date()))")
                if let used = window.usedPercent, let remaining = window.remainingPercent {
                    try check(remaining == min(100, max(0, 100 - used)), "已用百分比换算为剩余额度")
                }
                if let date = window.resetDate {
                    try check(window.countdown(at: date) == "等待刷新确认", "到达真实重置时间后等待新查询")
                    try check(window.needsRefresh(at: date), "重置时间的刷新判断")
                    try check(!usage.isCurrent(at: date.addingTimeInterval(1)), "过期的真实额度记录标记为历史查询")
                }
            }
        }
        try await client.stop()
        try FileManager.default.removeItem(at: session)
        let loginSession = root.appendingPathComponent(UUID().uuidString)
        try PrivateFiles.createDirectory(loginSession)
        let loginClient = try CodexClient(installation: installation, home: loginSession)
        try await loginClient.initialize()
        let start = try await loginClient.startLogin()
        guard let loginURL = URL(string: start.authUrl) else { throw AccountFailure("登录地址无效。") }
        try check(loginURL.scheme == "https" && loginURL.host == "auth.openai.com", "真实浏览器登录接口")
        try await loginClient.cancelLogin(id: start.loginId)
        var cancellationObserved = false
        do { try await loginClient.waitForLogin(id: start.loginId) }
        catch is AccountFailure { cancellationObserved = true }
        try check(cancellationObserved, "真实登录取消通知")
        try await loginClient.stop()
        try FileManager.default.removeItem(at: loginSession)

        let testID = UUID()
        let vault = CredentialVault(service: "local.codexaccounts.validation." + testID.uuidString)
        let privateRoot = root.appendingPathComponent(testID.uuidString)
        let targetDirectory = privateRoot.appendingPathComponent("codex-target")
        try PrivateFiles.createDirectory(targetDirectory)
        let target = targetDirectory.appendingPathComponent("auth.json")
        try PrivateFiles.write(data, to: target)
        let storage = try AccountStorage(root: privateRoot.appendingPathComponent("application"), liveAuth: target, vault: vault)
        let service = try AccountService(storage: storage, installation: installation)
        let profileID = try await service.importCredential(data, label: "验收账号")
        try check(try vault.read(id: profileID) == data, "真实钥匙串写入和读取")
        let duplicateID = try await service.importCredential(data, label: "验收账号")
        try check(duplicateID == profileID && service.registry.profiles.count == 1, "重复导入同一真实账号只保留一条记录")
        try service.rename(profileID, label: "当前验收账号")
        try check(try storage.load().profiles.first?.label == "当前验收账号", "账号名称持久保存")
        _ = try await service.synchronizeCurrent()
        try check(service.activeID == profileID, "识别独立目录中的当前账号")
        try await service.refresh(profileID)
        try check(service.registry.profiles.first?.usage != nil, "通过正式服务代码刷新真实额度")
        let metadata = try Data(contentsOf: storage.root.appendingPathComponent("accounts.json"))
        let metadataText = String(decoding: metadata, as: UTF8.self)
        try check(!metadataText.contains(document.tokens!.access_token), "账号记录不包含 access_token")
        if let token = document.tokens?.refresh_token {
            try check(!metadataText.contains(token), "账号记录不包含 refresh_token")
        }
        var preferences = Preferences()
        preferences.refreshSeconds = 120
        preferences.maskEmails = true
        try service.updatePreferences(preferences)
        try check(try storage.load().preferences.refreshSeconds == 120, "应用设置持久保存")

        let encoded = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data), options: [.prettyPrinted, .sortedKeys])
        try storage.install(encoded, replacing: data)
        try check(try storage.readLive() == encoded, "独立目录中的真实凭据原子替换")
        var staleWriteRejected = false
        do { try storage.install(data, replacing: nil) }
        catch is AccountFailure { staleWriteRejected = true }
        try check(staleWriteRejected, "当前文件变化时拒绝覆盖")
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        try check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "凭据文件权限为 0600")
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: storage.root.path)
        try check((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700, "数据目录权限为 0700")
        var secondInstanceRejected = false
        do { _ = try AccountStorage(root: storage.root, liveAuth: target, vault: vault) }
        catch is AccountFailure { secondInstanceRejected = true }
        try check(secondInstanceRejected, "拒绝第二个写入同一数据目录的进程")

        try await service.switchAccount(profileID)
        try check(try storage.readLive() == encoded, "选择当前账号保持凭据内容一致")
        try FileManager.default.removeItem(at: target)
        _ = try await service.synchronizeCurrent(importIfMissing: false)
        try service.remove(profileID)
        try check(service.registry.profiles.isEmpty && (try storage.load()).profiles.isEmpty, "移除账号并保存记录")
        var keychainRemoved = false
        do { _ = try vault.read(id: profileID) }
        catch is AccountFailure { keychainRemoved = true }
        try check(keychainRemoved, "移除账号后删除对应钥匙串项目")
        try check(try Data(contentsOf: authURL) == data, "全部验证结束后原有 Codex 凭据保持一致")
        try FileManager.default.removeItem(at: privateRoot)
        print("验证完成。所有账号接口均使用本机真实 Codex 程序和现有账号。")
    }
}
