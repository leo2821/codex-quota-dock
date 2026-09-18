import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public var id: String { rawValue }
    public var resourceIdentifier: String {
        if self == .system {
            return Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: Locale.preferredLanguages)[0]
        }
        return rawValue
    }
}

public struct Localizer {
    public let language: AppLanguage
    public var locale: Locale { Locale(identifier: language.resourceIdentifier) }
    private static let resourceURL: URL = {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.resourceURL!.appendingPathComponent("CodexAccounts_AccountCore.bundle")
        }
        return Bundle.module.bundleURL
    }()
    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: ["en", "zh-Hans"].map { identifier in
        let url = resourceURL.appendingPathComponent(identifier.lowercased() + ".lproj")
        guard let bundle = Bundle(url: url) else {
            preconditionFailure("Missing localization bundle: \(identifier)")
        }
        return (identifier, bundle)
    })

    public init(language: AppLanguage = .system) { self.language = language }

    public func callAsFunction(_ key: String, _ arguments: String...) -> String {
        format(key, arguments: arguments)
    }

    public func format(_ key: String, arguments: [String]) -> String {
        let format = Self.bundles[language.resourceIdentifier]!.localizedString(forKey: key, value: nil, table: nil)
        return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
    }

    public func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }

    public func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().hour().minute().locale(locale))
    }

    public func accountCount(_ count: Int) -> String {
        count == 1 ? self("1 account") : self("%@ accounts", String(count))
    }
}
