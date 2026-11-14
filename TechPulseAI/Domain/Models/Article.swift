import Foundation

enum ContentAvailability: String, Sendable, Hashable, Codable {
    /// Full text is licensed / supplied by an allowed feed and may be shown in-app.
    case full
    /// Only a publisher-provided excerpt may be shown; read the rest at the source.
    case excerptOnly
    /// Metadata and link only.
    case linkOnly
}

enum Difficulty: String, Sendable, Hashable, CaseIterable, Codable {
    case beginner, intermediate, advanced

    var title: String { rawValue.capitalized }
}

struct Article: Identifiable, Hashable, Sendable {
    let id: ArticleID
    let canonicalURL: URL
    let title: String
    let summary: String?
    let excerpt: String?
    /// Only populated when `contentAvailability == .full`.
    let content: String?
    let imageURL: URL?
    let sourceID: SourceID
    let sourceName: String
    let author: String?
    let publishedAt: Date?
    let fetchedAt: Date
    let categoryIDs: [CategoryID]
    let tags: [String]
    let readingTimeMinutes: Int?
    let contentAvailability: ContentAvailability
    let difficulty: Difficulty?
}

struct ArticlePage: Sendable, Equatable {
    let articles: [Article]
    let nextCursor: String?
}

struct ArticleQuery: Sendable, Hashable {
    var categoryID: CategoryID?
    var sourceIDs: Set<SourceID> = []
    var cursor: String?
    var limit: Int = 20
}

enum ArticleSort: String, Sendable, CaseIterable, Hashable {
    case newest, relevance

    var title: String { self == .newest ? "Newest" : "Relevance" }
}

struct SearchQuery: Sendable, Hashable {
    var text: String
    var categoryID: CategoryID?
    var sourceID: SourceID?
    var from: Date?
    var to: Date?
    var difficulty: Difficulty?
    var sort: ArticleSort = .relevance

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}
