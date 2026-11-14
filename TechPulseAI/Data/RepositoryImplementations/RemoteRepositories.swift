import Foundation

/// Backend-backed repositories. The contract is illustrative (plan §7) and
/// unverified against a live server — see README "Backend contract".
struct RemoteContentRepository: ArticleRepository, CatalogRepository, BriefingRepository {
    let client: APIClient
    let dateProvider: any DateProvider

    func articles(_ query: ArticleQuery) async throws -> ArticlePage {
        // Single source is filtered server-side; multiple sources fall back to client filtering.
        let source = query.sourceIDs.count == 1 ? query.sourceIDs.first : nil
        let dto = try await client.send(.articles(category: query.categoryID, source: source, cursor: query.cursor, limit: query.limit),
                                        as: ArticlePageDTO.self)
        let page = ArticleMapper.map(dto, fetchedAt: dateProvider.now)
        let filtered = query.sourceIDs.isEmpty ? page.articles : page.articles.filter { query.sourceIDs.contains($0.sourceID) }
        return ArticlePage(articles: ArticleDeduplicator.dedupe(filtered), nextCursor: page.nextCursor)
    }

    func article(id: ArticleID) async throws -> Article {
        do {
            return try ArticleMapper.map(try await client.send(.article(id: id), as: ArticleDTO.self), fetchedAt: dateProvider.now)
        } catch APIError.http(status: 404) {
            throw RepositoryError.notFound
        }
    }

    func search(_ query: SearchQuery) async throws -> [Article] {
        guard !query.trimmedText.isEmpty else { return [] }
        let dto = try await client.send(.search(query), as: ArticlePageDTO.self)
        return ArticleDeduplicator.dedupe(ArticleMapper.map(dto, fetchedAt: dateProvider.now).articles)
    }

    /// No dedicated endpoint in the contract: use the article's primary category feed.
    func relatedArticles(to article: Article, limit: Int) async throws -> [Article] {
        let page = try await articles(ArticleQuery(categoryID: article.categoryIDs.first, limit: limit + 5))
        return Array(page.articles.filter { $0.id != article.id }.prefix(limit))
    }

    func categories() async throws -> [ArticleCategory] {
        try await client.send(.categories, as: [CategoryDTO].self).map(CatalogMapper.map)
    }

    func sources() async throws -> [Source] {
        try await client.send(.sources, as: [SourceDTO].self).compactMap(CatalogMapper.map)
    }

    func dailyBriefing() async throws -> DailyBriefing {
        CatalogMapper.map(try await client.send(.dailyBriefing, as: DailyBriefingDTO.self))
    }
}
