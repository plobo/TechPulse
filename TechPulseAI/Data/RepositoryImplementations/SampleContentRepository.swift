import Foundation

/// Bundled SAMPLE content in the backend wire format. Not live news.
struct SampleFixtures: Decodable, Sendable {
    var categories: [CategoryDTO]
    var sources: [SourceDTO]
    var articles: [ArticleDTO]

    static let resourceName = "SampleContent"

    static func load(from bundle: Bundle) throws -> SampleFixtures {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder.techPulse.decode(SampleFixtures.self, from: Data(contentsOf: url))
    }
}

/// In-memory repository over sample fixtures. Dates are rebased so the newest
/// sample item is one hour old, keeping the sample feed and briefing populated.
struct SampleContentRepository: ArticleRepository, CatalogRepository, BriefingRepository {
    private let allArticles: [Article]
    private let allCategories: [ArticleCategory]
    private let allSources: [Source]
    private let dateProvider: any DateProvider

    init(fixtures: SampleFixtures, dateProvider: any DateProvider) {
        self.dateProvider = dateProvider
        let now = dateProvider.now
        let newest = fixtures.articles.compactMap(\.publishedAt).max() ?? now
        let shift = now.addingTimeInterval(-3600).timeIntervalSince(newest)
        let rebased = fixtures.articles.map { dto -> ArticleDTO in
            var copy = dto
            copy.publishedAt = dto.publishedAt?.addingTimeInterval(shift)
            return copy
        }
        allArticles = ArticleSort.newest.sorted(
            ArticleDeduplicator.dedupe(rebased.compactMap { try? ArticleMapper.map($0, fetchedAt: now) }), query: "")
        allCategories = fixtures.categories.map(CatalogMapper.map)
        allSources = fixtures.sources.compactMap(CatalogMapper.map)
    }

    func articles(_ query: ArticleQuery) async throws -> ArticlePage {
        try Task.checkCancellation()
        let filtered = allArticles.filter { article in
            (query.categoryID.map { article.categoryIDs.contains($0) } ?? true)
                && (query.sourceIDs.isEmpty || query.sourceIDs.contains(article.sourceID))
        }
        let offset = query.cursor.flatMap(Int.init) ?? 0
        guard offset < filtered.count else { return ArticlePage(articles: [], nextCursor: nil) }
        let end = min(offset + max(query.limit, 1), filtered.count)
        return ArticlePage(articles: Array(filtered[offset..<end]), nextCursor: end < filtered.count ? String(end) : nil)
    }

    func article(id: ArticleID) async throws -> Article {
        guard let article = allArticles.first(where: { $0.id == id }) else { throw RepositoryError.notFound }
        return article
    }

    func search(_ query: SearchQuery) async throws -> [Article] {
        try Task.checkCancellation()
        let text = query.trimmedText
        guard !text.isEmpty else { return [] }
        let matches = allArticles.filter { article in
            ArticleSearchMatcher.matches(article, query: text)
                && (query.categoryID.map { article.categoryIDs.contains($0) } ?? true)
                && (query.sourceID.map { article.sourceID == $0 } ?? true)
                && (query.difficulty.map { article.difficulty == $0 } ?? true)
                && (query.from.map { (article.publishedAt ?? .distantPast) >= $0 } ?? true)
                && (query.to.map { (article.publishedAt ?? .distantFuture) <= $0 } ?? true)
        }
        return query.sort.sorted(matches, query: text)
    }

    func relatedArticles(to article: Article, limit: Int) async throws -> [Article] {
        let tags = Set(article.tags)
        let categories = Set(article.categoryIDs)
        func score(_ other: Article) -> Int {
            let tagOverlap = Set(other.tags).intersection(tags).count
            let categoryOverlap = Set(other.categoryIDs).intersection(categories).count
            return tagOverlap * 2 + categoryOverlap
        }
        let scored: [(article: Article, score: Int)] = allArticles
            .filter { $0.id != article.id }
            .map { ($0, score($0)) }
            .filter { $0.score > 0 }
        return scored.sorted { $0.score > $1.score }.prefix(limit).map(\.article)
    }

    func categories() async throws -> [ArticleCategory] { allCategories }
    func sources() async throws -> [Source] { allSources }

    func dailyBriefing() async throws -> DailyBriefing {
        DailyBriefingBuilder.build(from: allArticles, now: dateProvider.now)
    }
}
