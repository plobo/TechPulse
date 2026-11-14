import Foundation
import SwiftData
import SwiftUI

/// Explicit dependency container, built once at launch and passed down.
struct AppDependencies: Sendable {
    let articles: any ArticleRepository
    let catalog: any CatalogRepository
    let briefing: any BriefingRepository
    let library: any LibraryRepository
    let ai: any AIService
    let dateProvider: any DateProvider
    /// True when content comes from bundled sample fixtures (UI shows a badge).
    let isSampleData: Bool

    static func live(configuration: AppConfiguration) throws -> AppDependencies {
        let dateProvider = SystemDateProvider()
        if configuration.resetsStoreOnLaunch { PersistenceController.destroyDefaultStore() }
        let container = try PersistenceController.makeContainer(inMemory: configuration.usesInMemoryStore)
        let library = SwiftDataLibraryRepository(modelContainer: container, dateProvider: dateProvider)

        switch configuration.dataSource {
        case .sample:
            let sample = SampleContentRepository(fixtures: try SampleFixtures.load(from: .main), dateProvider: dateProvider)
            return AppDependencies(articles: sample, catalog: sample, briefing: sample, library: library,
                                   ai: UnavailableAIService(), dateProvider: dateProvider, isSampleData: true)
        case let .remote(baseURL):
            let client = APIClient(baseURL: baseURL, http: makeSession())
            let remote = RemoteContentRepository(client: client, dateProvider: dateProvider)
            return AppDependencies(articles: remote, catalog: remote, briefing: remote, library: library,
                                   ai: UnavailableAIService(), dateProvider: dateProvider, isSampleData: false)
        }
    }

    /// URLSession with bounded memory/disk caches for feed responses and images.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024)
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }

    /// In-memory sample dependencies for SwiftUI previews.
    static var preview: AppDependencies {
        // Force-try is acceptable here: previews only, bundled fixture.
        try! live(configuration: AppConfiguration(values: [:], arguments: ["-ui-testing"]))
    }
}

private struct AppDependenciesKey: EnvironmentKey {
    /// Only used when a view is rendered without injection (e.g. previews).
    static let defaultValue: AppDependencies = .preview
}

extension EnvironmentValues {
    var dependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}
