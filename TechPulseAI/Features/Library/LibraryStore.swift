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
        do {
            try await repository.removeBookmark(articleID: id)
            bookmarkedIDs.remove(id)
            revision += 1
        } catch {
            lastErrorMessage = "Couldn’t remove bookmark."
        }
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

    @discardableResult
    func clearHistory() async -> Bool {
        do {
            try await repository.clearHistory()
            readIDs = []
            revision += 1
            return true
        } catch {
            lastErrorMessage = "Couldn’t clear reading history."
            return false
        }
    }

    @discardableResult
    func saveNote(id: UUID? = nil, articleID: ArticleID, text: String) async throws -> ArticleNote {
        let note = try await repository.saveNote(id: id, articleID: articleID, text: text)
        revision += 1
        return note
    }

    @discardableResult
    func deleteNote(_ id: UUID) async -> Bool {
        do {
            try await repository.deleteNote(id: id)
            revision += 1
            return true
        } catch {
            lastErrorMessage = "Couldn’t delete note."
            return false
        }
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

    /// Returns the number of cached articles removed, or nil on failure.
    func clearCache() async -> Int? {
        do {
            let removed = try await repository.clearCache()
            revision += 1
            return removed
        } catch {
            lastErrorMessage = "Couldn’t clear the cache."
            return nil
        }
    }

    func deleteAllData() async throws {
        try await repository.deleteAllData()
        await load()
        revision += 1
    }
}
