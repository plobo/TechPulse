import Foundation

enum RepositoryError: Error, Equatable {
    case notFound
}

protocol ArticleRepository: Sendable {
    func articles(_ query: ArticleQuery) async throws -> ArticlePage
    func article(id: ArticleID) async throws -> Article
    func search(_ query: SearchQuery) async throws -> [Article]
    func relatedArticles(to article: Article, limit: Int) async throws -> [Article]
}

protocol CatalogRepository: Sendable {
    func categories() async throws -> [ArticleCategory]
    func sources() async throws -> [Source]
}

protocol BriefingRepository: Sendable {
    func dailyBriefing() async throws -> DailyBriefing
}

protocol DateProvider: Sendable {
    var now: Date { get }
}

struct SystemDateProvider: DateProvider {
    var now: Date { Date() }
}
