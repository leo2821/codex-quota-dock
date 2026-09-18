import Foundation

public struct AccountFailure: LocalizedError, Codable, Equatable {
    public let message: String
    public let arguments: [String]
    public init(_ message: String, _ arguments: String...) {
        self.message = message
        self.arguments = arguments
    }
    public func description(using strings: Localizer) -> String {
        strings.format(message, arguments: arguments)
    }
    public var errorDescription: String? { description(using: Localizer()) }
}

public struct AuthDocument: Decodable {
    public struct Tokens: Decodable {
        public let access_token: String
        public let refresh_token: String?
        public let id_token: String?
        public let account_id: String?
    }
    public let tokens: Tokens?
    public let auth_mode: String?
    public let OPENAI_API_KEY: String?

    public static func read(_ data: Data) throws -> AuthDocument {
        let document = try JSONDecoder().decode(AuthDocument.self, from: data)
        guard let tokens = document.tokens, !tokens.access_token.isEmpty,
              let accountID = tokens.account_id, !accountID.isEmpty else {
            throw AccountFailure("Choose a Codex account signed in with ChatGPT. This file has no subscription account credentials.")
        }
        return document
    }

    public var accountID: String { tokens!.account_id! }
}

public struct AccountInfo: Codable, Equatable {
    public let type: String
    public let email: String?
    public let planType: String?
}

public struct AccountReadResponse: Decodable {
    public let account: AccountInfo?
}

public struct QuotaWindow: Codable, Equatable, Identifiable {
    public let usedPercent: Double?
    public let windowDurationMins: Int?
    public let resetsAt: Double?
    public var id: String { "\(windowDurationMins ?? -1)-\(resetsAt ?? -1)" }
    public var remainingPercent: Double? {
        usedPercent.map { min(100, max(0, 100 - $0)) }
    }
    public var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
    public var title: String { title(using: Localizer()) }
    public func title(using strings: Localizer) -> String {
        guard let minutes = windowDurationMins else { return strings("Quota window") }
        if minutes == 10080 { return strings("Weekly limit") }
        if minutes % 1440 == 0 { return strings("%@-day limit", String(minutes / 1440)) }
        if minutes % 60 == 0 { return strings("%@-hour limit", String(minutes / 60)) }
        return strings("%@-minute limit", String(minutes))
    }
    public func countdown(at now: Date, using strings: Localizer = Localizer()) -> String {
        guard let resetDate else { return strings("Reset time unknown") }
        let seconds = Int(ceil(resetDate.timeIntervalSince(now)))
        if seconds <= 0 { return strings("Awaiting refresh") }
        let minutes = max(1, Int(ceil(Double(seconds) / 60)))
        if minutes >= 1440 { return strings("Resets in %@d %@h", String(minutes / 1440), String(minutes % 1440 / 60)) }
        if minutes >= 60 { return strings("Resets in %@h %@m", String(minutes / 60), String(minutes % 60)) }
        return strings("Resets in %@ min", String(minutes))
    }
    public func needsRefresh(at now: Date) -> Bool {
        resetDate.map { $0 <= now } ?? false
    }
}

public struct CreditBalance: Codable, Equatable {
    public let hasCredits: Bool?
    public let unlimited: Bool?
    public let balance: String?
}

public struct LimitBucket: Codable, Equatable, Identifiable {
    public let limitId: String?
    public let limitName: String?
    public let primary: QuotaWindow?
    public let secondary: QuotaWindow?
    public let credits: CreditBalance?
    public let planType: String?
    public var id: String { limitId ?? "codex" }
    public var title: String { limitName ?? (id == "codex" ? "Codex" : id) }
    public var windows: [QuotaWindow] { [primary, secondary].compactMap { $0 } }
}

public struct ResetCredits: Codable, Equatable {
    public let availableCount: Int?
}

public struct RateLimitsResponse: Codable, Equatable {
    public let rateLimits: LimitBucket?
    public let rateLimitsByLimitId: [String: LimitBucket]?
    public let rateLimitResetCredits: ResetCredits?
    public var buckets: [LimitBucket] {
        if let map = rateLimitsByLimitId, !map.isEmpty {
            return map.keys.sorted { lhs, rhs in
                if lhs == "codex" { return rhs != "codex" }
                if rhs == "codex" { return false }
                return lhs < rhs
            }.compactMap { key in
                guard let bucket = map[key] else { return nil }
                return LimitBucket(limitId: bucket.limitId ?? key, limitName: bucket.limitName,
                    primary: bucket.primary, secondary: bucket.secondary, credits: bucket.credits, planType: bucket.planType)
            }
        }
        return rateLimits.map { [$0] } ?? []
    }
    public var mainBucket: LimitBucket? {
        if let bucket = buckets.first(where: { $0.id == "codex" }) { return bucket }
        return rateLimits?.id == "codex" ? rateLimits : nil
    }
}

public struct UsageSnapshot: Codable, Equatable {
    public let response: RateLimitsResponse
    public let fetchedAt: Date
    public init(response: RateLimitsResponse, fetchedAt: Date = Date()) {
        self.response = response
        self.fetchedAt = fetchedAt
    }
    public var availablePercent: Double? {
        let values = response.mainBucket?.windows.compactMap(\.remainingPercent) ?? []
        return values.min()
    }
    public func isCurrent(at now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) < 600 &&
        !response.buckets.flatMap(\.windows).contains { $0.needsRefresh(at: now) }
    }
}

public enum CredentialStorage: String, Codable {
    case keychain
    case localFile
}

public struct Profile: Codable, Identifiable, Equatable {
    public let id: UUID
    public var label: String
    public let accountID: String
    public var email: String?
    public var plan: String?
    public var usage: UsageSnapshot?
    public var lastError: String?
    public var localizedError: AccountFailure?
    public var credentialStorage: CredentialStorage?
    public let createdAt: Date
    public init(label: String, accountID: String, info: AccountInfo) {
        id = UUID()
        self.label = label
        self.accountID = accountID
        email = info.email
        plan = info.planType
        credentialStorage = .localFile
        createdAt = Date()
    }
    public var identity: String { accountID + "|" + (email?.lowercased() ?? "") }
}

public struct Preferences: Codable {
    public var refreshSeconds: Int = 300
    public var confirmSwitch: Bool = true
    public var maskEmails: Bool = false
    public var sortByQuota: Bool = false
    public var language: AppLanguage = .system
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case refreshSeconds, confirmSwitch, maskEmails, sortByQuota, language
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        refreshSeconds = try values.decode(Int.self, forKey: .refreshSeconds)
        confirmSwitch = try values.decode(Bool.self, forKey: .confirmSwitch)
        maskEmails = try values.decode(Bool.self, forKey: .maskEmails)
        sortByQuota = try values.decode(Bool.self, forKey: .sortByQuota)
        language = try values.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
    }
}

public struct Registry: Codable {
    public var version: Int = 1
    public var profiles: [Profile] = []
    public var preferences = Preferences()
    public init() {}
}

public struct LoginStart: Decodable {
    public let loginId: String
    public let authUrl: String
}

public struct LoginCompleted: Decodable {
    public let loginId: String?
    public let success: Bool
    public let error: String?
}
