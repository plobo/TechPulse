import Foundation

// Wire formats for the TechPulse backend (see README "Backend contract").
// DTOs never leave the Data layer; map them to domain models first.

struct ArticleDTO: Codable, Sendable, Equatable {
    var id: String
    var canonicalURL: String
    var title: String
    var summary: String?
    var excerpt: String?
    var content: String?
    var imageURL: String?
    var sourceID: String
    var sourceName: String
    var author: String?
    var publishedAt: Date?
    var categoryIDs: [String]?
    var tags: [String]?
    var readingTimeMinutes: Int?
    var contentAvailability: String?
    var difficulty: String?

    enum CodingKeys: String, CodingKey {
        case id, title, summary, excerpt, content, author, tags, difficulty
        case canonicalURL = "canonical_url"
        case imageURL = "image_url"
        case sourceID = "source_id"
        case sourceName = "source_name"
        case publishedAt = "published_at"
        case categoryIDs = "category_ids"
        case readingTimeMinutes = "reading_time_minutes"
        case contentAvailability = "content_availability"
    }
}

struct ArticlePageDTO: Codable, Sendable, Equatable {
    var items: [ArticleDTO]
    var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

struct CategoryDTO: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var description: String?
    var icon: String?
}

struct SourceDTO: Codable, Sendable, Equatable {
    var id: String
    var name: String
    var homepageURL: String
    var feedURL: String?
    var type: String?
    var enabled: Bool?
    var attribution: String?

    enum CodingKeys: String, CodingKey {
        case id, name, type, enabled, attribution
        case homepageURL = "homepage_url"
        case feedURL = "feed_url"
    }
}

struct DailyBriefingDTO: Codable, Sendable, Equatable {
    var date: Date
    var articleIDs: [String]
    var introduction: String
    var keyThemes: [String]?
    var isAIGenerated: Bool?

    enum CodingKeys: String, CodingKey {
        case date, introduction
        case articleIDs = "article_ids"
        case keyThemes = "key_themes"
        case isAIGenerated = "is_ai_generated"
    }
}

extension JSONDecoder {
    /// ISO-8601 dates with or without fractional seconds.
    static var techPulse: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = try? Date(raw, strategy: .iso8601) { return date }
            if let date = try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(raw)")
        }
        return decoder
    }
}
