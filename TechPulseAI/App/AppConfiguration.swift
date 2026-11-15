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
    /// UI-test only: wipe the on-disk store at launch.
    let resetsStoreOnLaunch: Bool
    /// UI-test only: use Demo AI and treat AI as enabled.
    let forcesDemoAI: Bool

    /// - Parameter allowInsecureLocalhost: Debug builds only — permits `http://localhost` / `127.0.0.1`
    ///   so the simulator can reach a local TechPulse server. Every other address must be HTTPS.
    init(values: [String: String], arguments: [String] = [], allowInsecureLocalhost: Bool = false) {
        if let raw = values[Self.baseURLKey]?.trimmingCharacters(in: .whitespaces),
           let url = URL(string: raw), let host = url.host()?.lowercased(), !host.isEmpty,
           url.scheme?.lowercased() == "https"
            || (allowInsecureLocalhost && url.scheme?.lowercased() == "http" && ["localhost", "127.0.0.1"].contains(host)) {
            dataSource = .remote(url)
        } else {
            dataSource = .sample
        }
        let uiTesting = arguments.contains("-ui-testing")
        usesInMemoryStore = uiTesting && !arguments.contains("-persistent-store")
        resetsStoreOnLaunch = uiTesting && arguments.contains("-reset-store")
        forcesDemoAI = uiTesting && arguments.contains("-demo-ai")
    }

    static var current: AppConfiguration {
        var values = ProcessInfo.processInfo.environment
        if let plistValue = Bundle.main.object(forInfoDictionaryKey: baseURLKey) as? String, !plistValue.isEmpty {
            values[baseURLKey] = values[baseURLKey] ?? plistValue
        }
        #if DEBUG
        let allowLocalhost = true
        #else
        let allowLocalhost = false
        #endif
        return AppConfiguration(values: values, arguments: ProcessInfo.processInfo.arguments, allowInsecureLocalhost: allowLocalhost)
    }
}
