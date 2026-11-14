import Foundation

/// Runtime configuration resolved from the process environment / Info.plist.
/// No secrets live here: the app only knows the public backend base URL.
struct AppConfiguration: Sendable, Equatable {
    enum DataSource: Sendable, Equatable {
        /// Bundled, clearly-labelled sample fixtures (default until a backend exists).
        case sample
        /// TechPulse backend API (see README "Backend contract").
        case remote(URL)
    }

    static let baseURLKey = "TECHPULSE_API_BASE_URL"

    let dataSource: DataSource
    let usesInMemoryStore: Bool

    init(values: [String: String], arguments: [String] = []) {
        if let raw = values[Self.baseURLKey]?.trimmingCharacters(in: .whitespaces),
           let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host != nil {
            dataSource = .remote(url)
        } else {
            dataSource = .sample
        }
        usesInMemoryStore = arguments.contains("-ui-testing")
    }

    static var current: AppConfiguration {
        var values = ProcessInfo.processInfo.environment
        if let plistValue = Bundle.main.object(forInfoDictionaryKey: baseURLKey) as? String, !plistValue.isEmpty {
            values[baseURLKey] = values[baseURLKey] ?? plistValue
        }
        return AppConfiguration(values: values, arguments: ProcessInfo.processInfo.arguments)
    }
}
