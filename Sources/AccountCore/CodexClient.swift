import AppKit
import Foundation

public struct CodexInstallation {
    public let application: URL
    public let executable: URL
    public let bundleID: String

    public func resolveExecutable() throws -> URL {
        guard let executable = Self.findExecutable(in: application) else {
            throw AccountFailure("The Codex executable was not found in %@. Reinstall the desktop app.", application.path)
        }
        return executable
    }

    private static func findExecutable(in application: URL) -> URL? {
        let paths = ["Contents/Resources/codex-cli/bin/codex", "Contents/Resources/codex"]
        for path in paths {
            let candidate = application.appendingPathComponent(path)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    public static func discover() throws -> CodexInstallation {
        let candidates = [
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex"),
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            URL(fileURLWithPath: "/Applications/Codex.app")
        ].compactMap { $0 }
        for application in candidates {
            guard let bundle = Bundle(url: application), bundle.bundleIdentifier == "com.openai.codex" else { continue }
            if let executable = findExecutable(in: application) {
                return CodexInstallation(application: application, executable: executable, bundleID: "com.openai.codex")
            }
        }
        throw AccountFailure("Codex desktop was not found. Install the ChatGPT app that includes Codex.")
    }
}

@MainActor
public final class CodexClient {
    public let home: URL
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var reader: Task<Void, Never>?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var methods: [Int: String] = [:]
    private var timers: [Int: Task<Void, Never>] = [:]
    private var notifications: [LoginCompleted] = []
    private var loginWaiter: CheckedContinuation<LoginCompleted, Error>?
    private var stopped = false
    private var secretValues: [String] = []

    public init(installation: CodexInstallation, home: URL) throws {
        self.home = home
        let authFile = home.appendingPathComponent("auth.json")
        if FileManager.default.fileExists(atPath: authFile.path) {
            let document = try AuthDocument.read(Data(contentsOf: authFile))
            rememberSecrets(document)
        }
        process.executableURL = try installation.resolveExecutable()
        process.arguments = ["-c", "cli_auth_credentials_store=\"file\"",
                             "-c", "analytics.enabled=false", "-c", "feedback.enabled=false", "app-server"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = home.path
        environment.removeValue(forKey: "OPENAI_API_KEY")
        environment.removeValue(forKey: "CODEX_API_KEY")
        environment.removeValue(forKey: "CODEX_ACCESS_TOKEN")
        process.environment = environment
        process.currentDirectoryURL = home
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        reader = Task { [weak self, output] in
            do {
                for try await line in output.fileHandleForReading.bytes.lines {
                    guard let self, !self.stopped else { break }
                    try self.receive(Data(line.utf8))
                }
                self?.failAll(AccountFailure("The Codex connection is closed."))
            } catch {
                self?.failAll(AccountFailure("Unable to read the Codex response. Check that your installed version supports the account API."))
            }
        }
    }

    public func initialize() async throws {
        _ = try await request("initialize", params: [
            "clientInfo": ["name": "codex_accounts", "title": "Codex Quota Dock", "version": "1.2.1"],
            "capabilities": ["experimentalApi": true]
        ])
        try send(["method": "initialized", "params": [:]])
    }

    public func request(_ method: String, params: [String: Any] = [:], timeout: Double = 25) async throws -> Data {
        guard !stopped, process.isRunning else { throw AccountFailure("The Codex connection is closed.") }
        let id = nextID
        nextID += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                methods[id] = method
                timers[id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    self?.complete(id, result: .failure(AccountFailure("Codex request timed out (%@). Check your network connection.", method)))
                }
                do { try send(["id": id, "method": method, "params": params]) }
                catch { complete(id, result: .failure(error)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.complete(id, result: .failure(CancellationError())) }
        }
    }

    public func readAccount() async throws -> AccountInfo {
        let data = try await request("account/read", params: ["refreshToken": false])
        let result = try JSONDecoder().decode(AccountReadResponse.self, from: data)
        guard let account = result.account, account.type == "chatgpt" || account.type == "chatgptAuthTokens" else {
            throw AccountFailure("This account is not signed in with ChatGPT.")
        }
        return account
    }

    public func readLimits() async throws -> UsageSnapshot {
        let data = try await request("account/rateLimits/read")
        return UsageSnapshot(response: try JSONDecoder().decode(RateLimitsResponse.self, from: data))
    }

    public func useExternalTokens(_ document: AuthDocument, plan: String?) async throws {
        rememberSecrets(document)
        var params: [String: Any] = ["type": "chatgptAuthTokens",
                                     "accessToken": document.tokens!.access_token,
                                     "chatgptAccountId": document.accountID]
        if let plan { params["chatgptPlanType"] = plan }
        _ = try await request("account/login/start", params: params)
        notifications.removeAll()
    }

    public func startLogin() async throws -> LoginStart {
        let data = try await request("account/login/start", params: ["type": "chatgpt"])
        return try JSONDecoder().decode(LoginStart.self, from: data)
    }

    public func waitForLogin(id: String) async throws {
        let completion: LoginCompleted
        if let index = notifications.firstIndex(where: { $0.loginId == id }) {
            completion = notifications.remove(at: index)
        } else {
            completion = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { loginWaiter = $0 }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.loginWaiter?.resume(throwing: CancellationError())
                    self?.loginWaiter = nil
                }
            }
        }
        guard completion.loginId == id, completion.success else {
            throw AccountFailure("Sign-in was not completed. Open the browser and sign in again.")
        }
    }

    public func cancelLogin(id: String) async throws {
        _ = try await request("account/login/cancel", params: ["loginId": id])
    }

    public func stop() async throws {
        guard !stopped else { return }
        stopped = true
        failAll(CancellationError())
        try input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(40)) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        reader?.cancel()
        try output.fileHandleForReading.close()
    }

    private func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func receive(_ data: Data) throws {
        guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AccountFailure("Invalid Codex response format.")
        }
        if let method = message["method"] as? String {
            if let id = message["id"] {
                try send(["id": id, "error": ["code": -32601,
                     "message": "Sign in again to renew this account's credentials."]])
                return
            }
            if method == "account/login/completed", let params = message["params"] {
                let completion = try JSONDecoder().decode(LoginCompleted.self,
                    from: JSONSerialization.data(withJSONObject: params))
                if let waiter = loginWaiter { loginWaiter = nil; waiter.resume(returning: completion) }
                else { notifications.append(completion) }
            }
            return
        }
        guard let id = message["id"] as? Int else { return }
        if let error = message["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? -1
            let method = methods[id] ?? "unknown"
            let detail = error["message"] as? String ?? "The Codex response has no error description."
            complete(id, result: .failure(requestFailure(method: method, code: code, detail: detail)))
        } else if let result = message["result"] {
            complete(id, result: .success(try JSONSerialization.data(withJSONObject: result)))
        } else { complete(id, result: .failure(AccountFailure("The Codex response has no result."))) }
    }

    private func rememberSecrets(_ document: AuthDocument) {
        guard let tokens = document.tokens else { return }
        secretValues.append(contentsOf: [tokens.access_token, tokens.refresh_token, tokens.id_token, tokens.account_id]
            .compactMap { $0 }.filter { !$0.isEmpty })
    }

    private func requestFailure(method: String, code: Int, detail: String) -> AccountFailure {
        if detail == "workspace routing discovery timed out" {
            return AccountFailure("Codex's workspace lookup timed out. Try again later. (%@, %@)", method, String(code))
        }
        var safeDetail = detail
        for secret in secretValues { safeDetail = safeDetail.replacingOccurrences(of: secret, with: "[redacted]") }
        safeDetail = safeDetail.replacingOccurrences(of: #"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#,
                                                     with: "[redacted]", options: .regularExpression)
        safeDetail = safeDetail.replacingOccurrences(of: #"(?i)Bearer\s+\S+"#, with: "Bearer [redacted]", options: .regularExpression)
        safeDetail = safeDetail.replacingOccurrences(of: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
                                                     with: "[redacted]", options: .regularExpression)
        return AccountFailure("Codex request failed (%@, %@): %@", method, String(code), String(safeDetail.prefix(1000)))
    }

    private func complete(_ id: Int, result: Result<Data, Error>) {
        methods.removeValue(forKey: id)
        timers.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func failAll(_ error: Error) {
        for id in Array(pending.keys) { complete(id, result: .failure(error)) }
        loginWaiter?.resume(throwing: error)
        loginWaiter = nil
    }
}
