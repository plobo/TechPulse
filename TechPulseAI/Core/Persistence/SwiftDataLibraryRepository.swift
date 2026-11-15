import Foundation
import SwiftData

/// SwiftData-backed library. Runs on its own model actor; only Sendable domain
/// values cross the actor boundary.
actor SwiftDataLibraryRepository: LibraryRepository, AILibraryRepository {
    nonisolated let modelContainer: ModelContainer
    private let context: ModelContext
    private let dateProvider: any DateProvider

    init(modelContainer: ModelContainer, dateProvider: any DateProvider = SystemDateProvider()) {
        self.modelContainer = modelContainer
        self.context = ModelContext(modelContainer)
        self.dateProvider = dateProvider
    }

    // MARK: Bookmarks

    func bookmarks() throws -> [Bookmark] {
        try context.fetch(FetchDescriptor<BookmarkRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
            .map { Bookmark(articleID: $0.articleID, createdAt: $0.createdAt) }
    }

    func toggleBookmark(_ article: Article) throws -> Bool {
        if let existing = try bookmarkRecord(article.id) {
            context.delete(existing)
            try context.save()
            return false
        }
        try cache(article)
        context.insert(BookmarkRecord(articleID: article.id, createdAt: dateProvider.now))
        try context.save()
        return true
    }

    func removeBookmark(articleID: ArticleID) throws {
        if let existing = try bookmarkRecord(articleID) {
            context.delete(existing)
            try context.save()
        }
    }

    func cachedArticles(ids: [ArticleID]) throws -> [Article] {
        let wanted = ids
        let records = try context.fetch(FetchDescriptor<CachedArticleRecord>(predicate: #Predicate { wanted.contains($0.articleID) }))
        let byID = Dictionary(records.map { ($0.articleID, $0.article) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] }
    }

    // MARK: History

    func recordOpen(_ article: Article) throws {
        try cache(article)
        let id = article.id
        if let record = try context.fetch(FetchDescriptor<ReadingHistoryRecord>(predicate: #Predicate { $0.articleID == id })).first {
            record.lastOpenedAt = dateProvider.now
            record.openCount += 1
        } else {
            context.insert(ReadingHistoryRecord(articleID: id, lastOpenedAt: dateProvider.now))
        }
        try context.save()
    }

    func history() throws -> [ReadingHistoryEntry] {
        try context.fetch(FetchDescriptor<ReadingHistoryRecord>(sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)]))
            .map { ReadingHistoryEntry(articleID: $0.articleID, lastOpenedAt: $0.lastOpenedAt, openCount: $0.openCount) }
    }

    func clearHistory() throws {
        try context.delete(model: ReadingHistoryRecord.self)
        try context.save()
    }

    // MARK: Notes

    func notes(for articleID: ArticleID) throws -> [ArticleNote] {
        let id = articleID
        return try context.fetch(FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.articleID == id },
                                                             sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
            .map(Self.note)
    }

    func allNotes() throws -> [ArticleNote] {
        try context.fetch(FetchDescriptor<NoteRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])).map(Self.note)
    }

    func saveNote(id: UUID?, articleID: ArticleID, text: String) throws -> ArticleNote {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryError.emptyNote }
        let now = dateProvider.now
        let record: NoteRecord
        if let id {
            guard let existing = try context.fetch(FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.noteID == id })).first else {
                throw LibraryError.noteNotFound
            }
            existing.text = trimmed
            existing.updatedAt = now
            record = existing
        } else {
            record = NoteRecord(noteID: UUID(), articleID: articleID, text: trimmed, createdAt: now)
            context.insert(record)
        }
        try context.save()
        return Self.note(record)
    }

    func deleteNote(id: UUID) throws {
        try context.delete(model: NoteRecord.self, where: #Predicate { $0.noteID == id })
        try context.save()
    }

    // MARK: Storage management

    func clearCache() throws -> Int {
        let keep = Set(try context.fetch(FetchDescriptor<BookmarkRecord>()).map(\.articleID))
            .union(try context.fetch(FetchDescriptor<NoteRecord>()).map(\.articleID))
        var removed = 0
        for record in try context.fetch(FetchDescriptor<CachedArticleRecord>()) where !keep.contains(record.articleID) {
            context.delete(record)
            removed += 1
        }
        try context.save()
        return removed
    }

    func exportData() throws -> Data {
        let export = LibraryExport(exportedAt: dateProvider.now, bookmarks: try bookmarks(), notes: try allNotes(),
                                   history: try history(), preferences: try preferences(),
                                   ai: try recentAIActivity(limit: .max))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    func deleteAllData() throws {
        try context.delete(model: BookmarkRecord.self)
        try context.delete(model: NoteRecord.self)
        try context.delete(model: ReadingHistoryRecord.self)
        try context.delete(model: CachedArticleRecord.self)
        try context.delete(model: PreferencesRecord.self)
        try context.delete(model: AIArtifactRecord.self)
        try context.delete(model: AIConversationRecord.self)
        try context.save()
    }

    // MARK: Preferences

    func preferences() throws -> UserPreferences {
        guard let record = try context.fetch(FetchDescriptor<PreferencesRecord>()).first,
              let prefs = try? JSONDecoder().decode(UserPreferences.self, from: record.payload) else { return .default }
        return prefs
    }

    func savePreferences(_ preferences: UserPreferences) throws {
        let payload = try JSONEncoder().encode(preferences)
        if let record = try context.fetch(FetchDescriptor<PreferencesRecord>()).first {
            record.payload = payload
        } else {
            context.insert(PreferencesRecord(payload: payload))
        }
        try context.save()
    }

    // MARK: AI history

    private static let aiEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        try? JSONDecoder.techPulse.decode(type, from: data)
    }

    func artifact(cacheKey: String) throws -> AIArtifact? {
        let key = cacheKey
        guard let record = try context.fetch(FetchDescriptor<AIArtifactRecord>(predicate: #Predicate { $0.cacheKey == key })).first
        else { return nil }
        return Self.decode(AIArtifact.self, record.payload)
    }

    func saveArtifact(_ artifact: AIArtifact) throws {
        let key = artifact.cacheKey
        let payload = try Self.aiEncoder.encode(artifact)
        if let existing = try context.fetch(FetchDescriptor<AIArtifactRecord>(predicate: #Predicate { $0.cacheKey == key })).first {
            existing.artifactID = artifact.id
            existing.articleID = artifact.articleID
            existing.kindRaw = artifact.kind.rawValue
            existing.createdAt = artifact.createdAt
            existing.payload = payload
        } else {
            context.insert(AIArtifactRecord(artifactID: artifact.id, cacheKey: key, articleID: artifact.articleID,
                                            kindRaw: artifact.kind.rawValue, createdAt: artifact.createdAt, payload: payload))
        }
        try context.save()
    }

    func conversation(articleID: ArticleID) throws -> AIConversation? {
        let id: String? = articleID
        var descriptor = FetchDescriptor<AIConversationRecord>(predicate: #Predicate { $0.articleID == id },
                                                              sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first.flatMap { Self.decode(AIConversation.self, $0.payload) }
    }

    func saveConversation(_ conversation: AIConversation) throws {
        let id = conversation.id
        let payload = try Self.aiEncoder.encode(conversation)
        if let existing = try context.fetch(FetchDescriptor<AIConversationRecord>(predicate: #Predicate { $0.conversationID == id })).first {
            existing.updatedAt = conversation.updatedAt
            existing.payload = payload
        } else {
            context.insert(AIConversationRecord(conversationID: id, articleID: conversation.articleID,
                                                updatedAt: conversation.updatedAt, payload: payload))
        }
        try context.save()
    }

    func recentAIActivity(limit: Int) throws -> [AIActivityItem] {
        let artifacts = try context.fetch(FetchDescriptor<AIArtifactRecord>())
            .compactMap { Self.decode(AIArtifact.self, $0.payload) }.map(AIActivityItem.artifact)
        let conversations = try context.fetch(FetchDescriptor<AIConversationRecord>())
            .compactMap { Self.decode(AIConversation.self, $0.payload) }.map(AIActivityItem.conversation)
        return Array((artifacts + conversations).sorted { $0.date > $1.date }.prefix(max(limit, 0)))
    }

    func deleteAIItem(id: UUID) throws {
        try context.delete(model: AIArtifactRecord.self, where: #Predicate { $0.artifactID == id })
        try context.delete(model: AIConversationRecord.self, where: #Predicate { $0.conversationID == id })
        try context.save()
    }

    func clearAIHistory() throws {
        try context.delete(model: AIArtifactRecord.self)
        try context.delete(model: AIConversationRecord.self)
        try context.save()
    }

    // MARK: Helpers

    private func bookmarkRecord(_ id: ArticleID) throws -> BookmarkRecord? {
        try context.fetch(FetchDescriptor<BookmarkRecord>(predicate: #Predicate { $0.articleID == id })).first
    }

    private func cache(_ article: Article) throws {
        let id = article.id
        if let existing = try context.fetch(FetchDescriptor<CachedArticleRecord>(predicate: #Predicate { $0.articleID == id })).first {
            existing.update(from: article)
        } else {
            context.insert(CachedArticleRecord(article: article))
        }
    }

    private static func note(_ record: NoteRecord) -> ArticleNote {
        ArticleNote(id: record.noteID, articleID: record.articleID, text: record.text,
                    createdAt: record.createdAt, updatedAt: record.updatedAt)
    }
}
