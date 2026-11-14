import Foundation
import SwiftData

/// Version 1 of the on-device schema. Add `TechPulseSchemaV2` + a migration
/// stage in `TechPulseMigrationPlan` for any future model change.
enum TechPulseSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [CachedArticleRecord.self, BookmarkRecord.self, NoteRecord.self, ReadingHistoryRecord.self, PreferencesRecord.self]
    }

    @Model
    final class CachedArticleRecord {
        @Attribute(.unique) var articleID: String
        var canonicalURL: URL
        var title: String
        var summary: String?
        var excerpt: String?
        /// Only stored when the article's content is licensed for in-app display.
        var content: String?
        var imageURL: URL?
        var sourceID: String
        var sourceName: String
        var author: String?
        var publishedAt: Date?
        var fetchedAt: Date
        var categoryIDs: [String]
        var tags: [String]
        var readingTimeMinutes: Int?
        var contentAvailabilityRaw: String
        var difficultyRaw: String?

        init(article: Article) {
            articleID = article.id
            canonicalURL = article.canonicalURL
            title = article.title
            sourceID = article.sourceID
            sourceName = article.sourceName
            fetchedAt = article.fetchedAt
            categoryIDs = article.categoryIDs
            tags = article.tags
            contentAvailabilityRaw = article.contentAvailability.rawValue
            update(from: article)
        }

        func update(from article: Article) {
            canonicalURL = article.canonicalURL
            title = article.title
            summary = article.summary
            excerpt = article.excerpt
            content = article.contentAvailability == .full ? article.content : nil
            imageURL = article.imageURL
            sourceID = article.sourceID
            sourceName = article.sourceName
            author = article.author
            publishedAt = article.publishedAt
            fetchedAt = article.fetchedAt
            categoryIDs = article.categoryIDs
            tags = article.tags
            readingTimeMinutes = article.readingTimeMinutes
            contentAvailabilityRaw = article.contentAvailability.rawValue
            difficultyRaw = article.difficulty?.rawValue
        }

        var article: Article {
            Article(id: articleID, canonicalURL: canonicalURL, title: title, summary: summary, excerpt: excerpt,
                    content: content, imageURL: imageURL, sourceID: sourceID, sourceName: sourceName, author: author,
                    publishedAt: publishedAt, fetchedAt: fetchedAt, categoryIDs: categoryIDs, tags: tags,
                    readingTimeMinutes: readingTimeMinutes,
                    contentAvailability: ContentAvailability(rawValue: contentAvailabilityRaw) ?? .linkOnly,
                    difficulty: difficultyRaw.flatMap(Difficulty.init(rawValue:)))
        }
    }

    @Model
    final class BookmarkRecord {
        @Attribute(.unique) var articleID: String
        var createdAt: Date

        init(articleID: String, createdAt: Date) {
            self.articleID = articleID
            self.createdAt = createdAt
        }
    }

    @Model
    final class NoteRecord {
        @Attribute(.unique) var noteID: UUID
        var articleID: String
        var text: String
        var createdAt: Date
        var updatedAt: Date

        init(noteID: UUID, articleID: String, text: String, createdAt: Date) {
            self.noteID = noteID
            self.articleID = articleID
            self.text = text
            self.createdAt = createdAt
            self.updatedAt = createdAt
        }
    }

    @Model
    final class ReadingHistoryRecord {
        @Attribute(.unique) var articleID: String
        var lastOpenedAt: Date
        var openCount: Int

        init(articleID: String, lastOpenedAt: Date) {
            self.articleID = articleID
            self.lastOpenedAt = lastOpenedAt
            self.openCount = 1
        }
    }

    /// Single-row JSON blob so preference fields can evolve without schema migrations.
    @Model
    final class PreferencesRecord {
        @Attribute(.unique) var key: String
        var payload: Data

        init(key: String = "user", payload: Data) {
            self.key = key
            self.payload = payload
        }
    }
}

typealias CachedArticleRecord = TechPulseSchemaV1.CachedArticleRecord
typealias BookmarkRecord = TechPulseSchemaV1.BookmarkRecord
typealias NoteRecord = TechPulseSchemaV1.NoteRecord
typealias ReadingHistoryRecord = TechPulseSchemaV1.ReadingHistoryRecord
typealias PreferencesRecord = TechPulseSchemaV1.PreferencesRecord

enum TechPulseMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TechPulseSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum PersistenceController {
    /// Application Support/TechPulse/TechPulse.store (directory created on first launch).
    static func defaultStoreURL() throws -> URL {
        let directory = URL.applicationSupportDirectory.appending(path: "TechPulse", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "TechPulse.store")
    }

    static func makeContainer(storeURL: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TechPulseSchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            configuration = ModelConfiguration(schema: schema, url: try defaultStoreURL())
        }
        return try ModelContainer(for: schema, migrationPlan: TechPulseMigrationPlan.self, configurations: [configuration])
    }
}
