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

protocol LibraryRepository: Sendable {
    func bookmarks() async throws -> [Bookmark]
    /// Returns the new bookmarked state. Caches the article metadata for offline use.
    func toggleBookmark(_ article: Article) async throws -> Bool
    func removeBookmark(articleID: ArticleID) async throws
    func cachedArticles(ids: [ArticleID]) async throws -> [Article]

    func recordOpen(_ article: Article) async throws
    func history() async throws -> [ReadingHistoryEntry]
    func clearHistory() async throws

    func notes(for articleID: ArticleID) async throws -> [ArticleNote]
    func allNotes() async throws -> [ArticleNote]
    func saveNote(id: UUID?, articleID: ArticleID, text: String) async throws -> ArticleNote
    func deleteNote(id: UUID) async throws

    /// Removes cached article metadata not referenced by a bookmark or note. Returns count removed.
    func clearCache() async throws -> Int
    func exportData() async throws -> Data
    func deleteAllData() async throws

    func preferences() async throws -> UserPreferences
    func savePreferences(_ preferences: UserPreferences) async throws
}

/// On-device AI history (summaries, explanations, diagrams, conversations).
protocol AILibraryRepository: Sendable {
    func artifact(cacheKey: String) async throws -> AIArtifact?
    /// Upserts by `cacheKey`.
    func saveArtifact(_ artifact: AIArtifact) async throws
    func conversation(articleID: ArticleID) async throws -> AIConversation?
    func saveConversation(_ conversation: AIConversation) async throws
    func recentAIActivity(limit: Int) async throws -> [AIActivityItem]
    func deleteAIItem(id: UUID) async throws
    func clearAIHistory() async throws
}
