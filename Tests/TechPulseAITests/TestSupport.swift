import Foundation
@testable import TechPulseAI

enum TestData {
    static let now = ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z")!

    static func article(
        id: String = UUID().uuidString,
        url: String? = nil,
        title: String = "Title",
        summary: String? = nil,
        sourceID: String = "src",
        sourceName: String = "Source",
        publishedAt: Date? = TestData.now,
        categoryIDs: [String] = ["ai-ml"],
        tags: [String] = [],
        availability: ContentAvailability = .excerptOnly
    ) -> Article {
        Article(
            id: id,
            canonicalURL: URL(string: url ?? "https://example.com/\(id)")!,
            title: title,
            summary: summary,
            excerpt: nil,
            content: nil,
            imageURL: nil,
            sourceID: sourceID,
            sourceName: sourceName,
            author: nil,
            publishedAt: publishedAt,
            fetchedAt: TestData.now,
            categoryIDs: categoryIDs,
            tags: tags,
            readingTimeMinutes: 3,
            contentAvailability: availability,
            difficulty: nil
        )
    }
}

/// Scripted HTTP client: returns queued results in order and records requests.
actor MockHTTPClient: HTTPClient {
    enum Reply {
        case response(status: Int, body: Data, headers: [String: String] = [:])
        case failure(any Error)
    }

    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        switch replies.removeFirst() {
        case let .response(status, body, headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            return (body, response)
        case let .failure(error):
            throw error
        }
    }
}

/// Records backoff delays instead of sleeping.
actor SleepRecorder {
    private(set) var delays: [Duration] = []
    func record(_ d: Duration) { delays.append(d) }
}

struct FixedDateProvider: DateProvider {
    let now: Date
}

/// Configurable article/catalog/briefing stub.
actor StubContentRepository: ArticleRepository, CatalogRepository, BriefingRepository {
    var pages: [String?: Result<ArticlePage, APIError>] = [:]   // keyed by cursor
    var categoryFilterLog: [CategoryID?] = []
    var briefingResult: Result<DailyBriefing, APIError> = .success(
        DailyBriefing(date: TestData.now, articleIDs: [], introduction: "intro", keyThemes: ["llm"], isAIGenerated: false))
    var store: [Article] = []
    var searchResults: [Article] = []
    var searchLog: [SearchQuery] = []
    var delays: [CategoryID?: Duration] = [:]

    init(pages: [String?: Result<ArticlePage, APIError>] = [:], store: [Article] = []) {
        self.pages = pages
        self.store = store
    }

    func setPage(_ cursor: String?, _ result: Result<ArticlePage, APIError>) { pages[cursor] = result }
    func setBriefing(_ result: Result<DailyBriefing, APIError>) { briefingResult = result }
    func setSearchResults(_ results: [Article]) { searchResults = results }
    func setDelay(_ category: CategoryID?, _ delay: Duration) { delays[category] = delay }

    func articles(_ query: ArticleQuery) async throws -> ArticlePage {
        categoryFilterLog.append(query.categoryID)
        if let delay = delays[query.categoryID] { try await Task.sleep(for: delay) }
        let result = pages[query.cursor] ?? .success(ArticlePage(articles: [], nextCursor: nil))
        let page = try result.get()
        guard let cat = query.categoryID else { return page }
        return ArticlePage(articles: page.articles.filter { $0.categoryIDs.contains(cat) }, nextCursor: page.nextCursor)
    }

    func article(id: ArticleID) async throws -> Article {
        guard let a = store.first(where: { $0.id == id }) else { throw RepositoryError.notFound }
        return a
    }

    func search(_ query: SearchQuery) async throws -> [Article] {
        searchLog.append(query)
        return searchResults
    }

    func relatedArticles(to article: Article, limit: Int) async throws -> [Article] {
        Array(store.filter { $0.id != article.id }.prefix(limit))
    }

    func categories() async throws -> [ArticleCategory] { ArticleCategory.builtIn }
    func sources() async throws -> [Source] {
        [Source(id: "src", name: "Source", homepageURL: URL(string: "https://example.com")!, feedURL: nil,
                type: .rss, isEnabled: true, attribution: nil)]
    }
    func dailyBriefing() async throws -> DailyBriefing { try briefingResult.get() }
}

extension AppDependencies {
    static func test(content: StubContentRepository = StubContentRepository()) throws -> AppDependencies {
        let container = try PersistenceController.makeContainer(inMemory: true)
        return AppDependencies(articles: content, catalog: content, briefing: content,
                               library: SwiftDataLibraryRepository(modelContainer: container, dateProvider: FixedDateProvider(now: TestData.now)),
                               ai: UnavailableAIService(), dateProvider: FixedDateProvider(now: TestData.now),
                               isSampleData: false)
    }
}

/// Library repository whose mutations always fail (reads return one bookmark "ai").
struct FailingLibraryRepository: LibraryRepository {
    struct Failure: Error {}
    func bookmarks() async throws -> [Bookmark] { [Bookmark(articleID: "ai", createdAt: TestData.now)] }
    func toggleBookmark(_ article: Article) async throws -> Bool { throw Failure() }
    func removeBookmark(articleID: ArticleID) async throws { throw Failure() }
    func cachedArticles(ids: [ArticleID]) async throws -> [Article] { [] }
    func recordOpen(_ article: Article) async throws { throw Failure() }
    func history() async throws -> [ReadingHistoryEntry] {
        [ReadingHistoryEntry(articleID: "ai", lastOpenedAt: TestData.now, openCount: 1)]
    }
    func clearHistory() async throws { throw Failure() }
    func notes(for articleID: ArticleID) async throws -> [ArticleNote] { [] }
    func allNotes() async throws -> [ArticleNote] { [] }
    func saveNote(id: UUID?, articleID: ArticleID, text: String) async throws -> ArticleNote { throw Failure() }
    func deleteNote(id: UUID) async throws { throw Failure() }
    func clearCache() async throws -> Int { throw Failure() }
    func exportData() async throws -> Data { Data("{}".utf8) }
    func deleteAllData() async throws { throw Failure() }
    func preferences() async throws -> UserPreferences { .default }
    func savePreferences(_ preferences: UserPreferences) async throws { throw Failure() }
}

final class CallFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.withLock { _count } }
    func hit() { lock.withLock { _count += 1 } }
}
