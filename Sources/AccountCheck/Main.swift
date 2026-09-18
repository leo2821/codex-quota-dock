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
        let english = Localizer(language: .english)
        let chinese = Localizer(language: .simplifiedChinese)
        try check(english("Add account") == "Add account" && chinese("Add account") == "添加账号", "中英文语言资源可以读取")
        try check(english.accountCount(1) == "1 account" && english.accountCount(2) == "2 accounts"
                  && chinese.accountCount(2) == "2 个账号", "账号数量的中英文显示")
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
                    try check(window.countdown(at: date, using: chinese) == "等待刷新确认"
                              && window.countdown(at: date, using: english) == "Awaiting refresh", "真实重置时间的中英文状态")
                    try check(window.title(using: chinese) != window.title(using: english), "真实额度周期使用所选语言")
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
        catch let error as AccountFailure {
            cancellationObserved = true
            try check(error.description(using: english) == "Sign-in was not completed. Open the browser and sign in again."
                      && error.description(using: chinese) == "账号登录未完成。请重新打开浏览器登录。", "真实登录取消错误使用所选语言")
            let savedError = try JSONEncoder().encode(error)
            try check(try JSONDecoder().decode(AccountFailure.self, from: savedError) == error, "错误记录保存后仍可切换语言")
        }
        try check(cancellationObserved, "真实登录取消通知")
        try await loginClient.stop()
        try FileManager.default.removeItem(at: loginSession)

        let testID = UUID()
        let privateRoot = root.appendingPathComponent(testID.uuidString)
        let targetDirectory = privateRoot.appendingPathComponent("codex-target")
        try PrivateFiles.createDirectory(targetDirectory)
        let target = targetDirectory.appendingPathComponent("auth.json")
        try PrivateFiles.write(data, to: target)
        let storage = try AccountStorage(root: privateRoot.appendingPathComponent("application"), liveAuth: target)
        let vault = storage.vault
        let service = try AccountService(storage: storage, installation: installation)
        let profileID = try await service.importCredential(data, label: "验收账号")
        try check(try vault.read(id: profileID) == data, "真实账号的本地 auth.json 写入和读取")
        try check(service.registry.profiles.first?.credentialStorage == .localFile, "账号记录使用本地文件存储")
        try check(try CredentialVault(root: vault.root).read(id: profileID) == data, "重新打开存储后可以读取账号文件")
        let accountFile = vault.fileURL(id: profileID)
        let accountAttributes = try FileManager.default.attributesOfItem(atPath: accountFile.path)
        try check((accountAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "每个账号的 auth.json 权限为 0600")
        let accountDirectoryAttributes = try FileManager.default.attributesOfItem(atPath: accountFile.deletingLastPathComponent().path)
        try check((accountDirectoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700, "每个账号的目录权限为 0700")
        let duplicateID = try await service.importCredential(data, label: "验收账号")
        try check(duplicateID == profileID && service.registry.profiles.count == 1, "重复导入同一真实账号只保留一条记录")
        try check(try FileManager.default.contentsOfDirectory(at: vault.root, includingPropertiesForKeys: nil).count == 1,
                  "重复导入保留同一份账号文件")
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
        preferences.language = .english
        try service.updatePreferences(preferences)
        try check(try storage.load().preferences.refreshSeconds == 120, "应用设置持久保存")
        try check(try storage.load().preferences.language == .english, "英文语言设置持久保存")
        preferences.language = .simplifiedChinese
        try service.updatePreferences(preferences)
        try check(try storage.load().preferences.language == .simplifiedChinese, "中文语言设置持久保存")

        let codexRoot = authURL.deletingLastPathComponent()
        var preservedFiles: [URL: Data] = [:]
        for name in ["config.toml", ".codex-global-state.json"] {
            let source = codexRoot.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: source.path) {
                let destination = targetDirectory.appendingPathComponent(name)
                let contents = try Data(contentsOf: source)
                try PrivateFiles.write(contents, to: destination)
                preservedFiles[destination] = contents
            }
        }
        let sessions = codexRoot.appendingPathComponent("sessions", isDirectory: true)
        if let enumerator = FileManager.default.enumerator(at: sessions, includingPropertiesForKeys: [.isRegularFileKey]) {
            while let source = enumerator.nextObject() as? URL {
                guard source.pathExtension == "jsonl" else { continue }
                let destinationDirectory = targetDirectory.appendingPathComponent("sessions", isDirectory: true)
                try PrivateFiles.createDirectory(destinationDirectory)
                let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
                let contents = try Data(contentsOf: source)
                try PrivateFiles.write(contents, to: destination)
                preservedFiles[destination] = contents
                break
            }
        }

        let encoded = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data), options: [.prettyPrinted, .sortedKeys])
        try storage.install(encoded, replacing: data)
        try check(try storage.readLive() == encoded, "独立目录中的真实凭据原子替换")
        for (file, contents) in preservedFiles {
            try check(try Data(contentsOf: file) == contents, "替换凭据后保留真实文件副本：" + file.lastPathComponent)
        }
        var staleWriteRejected = false
        do { try storage.install(data, replacing: nil) }
        catch is AccountFailure { staleWriteRejected = true }
        try check(staleWriteRejected, "当前文件变化时拒绝覆盖")
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        try check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "凭据文件权限为 0600")
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: storage.root.path)
        try check((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700, "数据目录权限为 0700")
        var secondInstanceRejected = false
        do { _ = try AccountStorage(root: storage.root, liveAuth: target) }
        catch is AccountFailure { secondInstanceRejected = true }
        try check(secondInstanceRejected, "拒绝第二个写入同一数据目录的进程")

        try await service.switchAccount(profileID)
        try check(try storage.readLive() == encoded, "选择当前账号保持凭据内容一致")
        try FileManager.default.removeItem(at: target)
        _ = try await service.synchronizeCurrent(importIfMissing: false)
        try service.remove(profileID)
        try check(service.registry.profiles.isEmpty && (try storage.load()).profiles.isEmpty, "移除账号并保存记录")
        var credentialRemoved = false
        do { _ = try vault.read(id: profileID) }
        catch is AccountFailure { credentialRemoved = true }
        try check(credentialRemoved && !FileManager.default.fileExists(atPath: accountFile.path), "移除账号后删除对应的本地 auth.json")
        try check(try FileManager.default.contentsOfDirectory(at: storage.runtime, includingPropertiesForKeys: nil).isEmpty,
                  "账号操作完成后清理临时登录目录")
        try check(try Data(contentsOf: authURL) == data, "全部验证结束后原有 Codex 凭据保持一致")
        try FileManager.default.removeItem(at: privateRoot)
        print("验证完成。所有账号接口均使用本机真实 Codex 程序和现有账号。")
    }
}
