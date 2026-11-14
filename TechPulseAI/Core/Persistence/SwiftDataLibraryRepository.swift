import Foundation
import SwiftData

/// SwiftData-backed library. Runs on its own model actor; only Sendable domain
/// values cross the actor boundary.
actor SwiftDataLibraryRepository: LibraryRepository {
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
                                   history: try history(), preferences: try preferences())
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
