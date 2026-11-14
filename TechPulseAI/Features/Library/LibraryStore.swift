import Foundation
import Observation

/// Main-actor, observable facade over the library repository. Shared across
/// tabs so bookmark/read state stays consistent everywhere.
@MainActor
@Observable
final class LibraryStore {
    private(set) var bookmarkedIDs: Set<ArticleID> = []
    private(set) var readIDs: Set<ArticleID> = []
    private(set) var preferences = UserPreferences.default
    /// Bumped on every mutation so library screens can reload.
    private(set) var revision = 0
    var lastErrorMessage: String?

    let repository: any LibraryRepository

    init(repository: any LibraryRepository) {
        self.repository = repository
    }

    func load() async {
        do {
            bookmarkedIDs = Set(try await repository.bookmarks().map(\.articleID))
            readIDs = Set(try await repository.history().map(\.articleID))
            preferences = try await repository.preferences()
        } catch {
            lastErrorMessage = "Couldn’t load your library."
        }
    }

    func isBookmarked(_ id: ArticleID) -> Bool { bookmarkedIDs.contains(id) }
    func isRead(_ id: ArticleID) -> Bool { readIDs.contains(id) }

    func toggleBookmark(_ article: Article) async {
        do {
            if try await repository.toggleBookmark(article) {
                bookmarkedIDs.insert(article.id)
            } else {
                bookmarkedIDs.remove(article.id)
            }
            revision += 1
        } catch {
            lastErrorMessage = "Couldn’t update bookmark."
        }
    }

    func removeBookmark(_ id: ArticleID) async {
        try? await repository.removeBookmark(articleID: id)
        bookmarkedIDs.remove(id)
        revision += 1
    }

    func recordOpen(_ article: Article) async {
        do {
            try await repository.recordOpen(article)
            readIDs.insert(article.id)
            revision += 1
        } catch {
            // Reading history is best-effort; never block reading.
        }
    }

    func clearHistory() async {
        try? await repository.clearHistory()
        readIDs = []
        revision += 1
    }

    @discardableResult
    func saveNote(id: UUID? = nil, articleID: ArticleID, text: String) async throws -> ArticleNote {
        let note = try await repository.saveNote(id: id, articleID: articleID, text: text)
        revision += 1
        return note
    }

    func deleteNote(_ id: UUID) async {
        try? await repository.deleteNote(id: id)
        revision += 1
    }

    func updatePreferences(_ change: (inout UserPreferences) -> Void) async {
        var updated = preferences
        change(&updated)
        preferences = updated
        do {
            try await repository.savePreferences(updated)
        } catch {
            lastErrorMessage = "Couldn’t save settings."
        }
    }

    func clearCache() async -> Int {
        let removed = (try? await repository.clearCache()) ?? 0
        revision += 1
        return removed
    }

    func deleteAllData() async {
        try? await repository.deleteAllData()
        await load()
        revision += 1
    }
}
